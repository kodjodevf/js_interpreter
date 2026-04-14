/// Main JavaScript engine - Public API
///
/// This class provides the main interface for using the JavaScript engine.
library;

import 'dart:async';
import 'bytecode/compiler.dart';
import 'bytecode/vm.dart';
import 'parser/parser.dart';
import 'runtime/module.dart';
import 'runtime/js_runtime.dart';
import 'runtime/js_value.dart';
import 'runtime/message_system.dart';
import 'runtime/native_functions.dart';
import 'runtime/realm.dart';
import 'runtime/runtime_bootstrap.dart';
import 'runtime/environment.dart' show Environment;

/// Main JavaScript engine
class JSInterpreter {
  bool _moduleMode = false;
  static int _nextInterpreterId = 0;
  final String _interpreterInstanceId;

  BytecodeVM? _vm;

  /// Console output buffer for bytecode mode
  List<String> get consoleOutput => _vm?.takeConsoleOutput() ?? [];

  /// Emits a debug trace to consoleOutput when a non-callable value is invoked.
  void enableNotAFunctionTracing([bool enabled = true]) {
    _vm?.traceNotAFunctionErrors = enabled;
  }

  JSInterpreter() : _interpreterInstanceId = 'vm-${_nextInterpreterId++}' {
    _channelFunctionsRegistered[getInterpreterInstanceId()] = {};
    _initBytecodeVM();
  }
  static final Map<String, Map<String, Function(dynamic arg)>>
  _channelFunctionsRegistered = {};

  static Map<String, Map<String, Function(dynamic arg)>>
  get channelFunctionsRegistered => _channelFunctionsRegistered;

  String getInterpreterInstanceId() {
    return _interpreterInstanceId;
  }

  /// Set module mode - in module context, certain identifiers are restricted
  void setModuleMode(bool isModule) {
    _moduleMode = isModule;
  }

  /// Check if currently in module mode
  bool get isModuleMode => _moduleMode;

  /// Registers a native function in the global environment
  void registerGlobal(String name, JSValue value) {
    _vm!.globals[name] = value;
    final globalThis = _vm!.globals['globalThis'];
    if (globalThis is JSObject) {
      globalThis.setProperty(name, value);
    }
  }

  /// Creates a createRealm function that can be used in JavaScript
  /// This implements $262.createRealm() for test262 tests
  JSNativeFunction createRealmFunction() {
    return JSRealmFactory.createRealmFunction();
  }

  void _initBytecodeVM() {
    _vm = BytecodeVM();
    RuntimeBootstrap.populateGlobals(
      _vm!.globals,
      getInterpreterInstanceId: getInterpreterInstanceId,
    );
  }

  /// Evaluates a JavaScript code string
  /// Maintains state between evaluations
  JSValue eval(String code) {
    return _evalBytecode(code);
  }

  JSValue _evalBytecode(String code, {bool allowTopLevelAwait = false}) {
    try {
      final program = JSParser.parseString(
        code,
        allowTopLevelAwait: allowTopLevelAwait,
      );
      final compiler = BytecodeCompiler();
      final bytecode = compiler.compile(program);
      return _vm!.execute(bytecode);
    } on JSException catch (e) {
      final value = e.value;
      if (value is JSObject && value.hasInternalSlot('ExposeAsDartError')) {
        final hostErrorName = value.getInternalSlot('HostErrorName');
        switch (hostErrorName) {
          case 'TypeError':
            throw JSTypeError(e.message);
          case 'ReferenceError':
            throw JSReferenceError(e.message);
          case 'SyntaxError':
            throw JSSyntaxError(e.message);
          case 'RangeError':
            throw JSRangeError(e.message);
          case 'URIError':
            throw JSURIError(e.message);
        }
      }
      rethrow;
    } catch (e) {
      if (e is JSError) rethrow;
      if (e.toString().contains('ParseError')) {
        final message = e.toString().replaceFirst(
          'ParseError at',
          'Unexpected token at',
        );
        throw JSSyntaxError(message);
      }
      if (e is Exception) rethrow;
      throw JSError('Evaluation error: $e');
    }
  }

  /// Evaluates a JavaScript code string asynchronously
  /// If the result is a JavaScript Promise, returns a Dart Future that resolves when the JS Promise resolves
  Future<JSValue> evalAsync(String code) async {
    // Parse with allowTopLevelAwait so that `await expr` works at the top level
    final JSValue result;
    try {
      result = _evalBytecode(code, allowTopLevelAwait: true);
    } catch (e) {
      if (e is JSError) rethrow;
      if (e.toString().contains('ParseError')) {
        final message = e.toString().replaceFirst(
          'ParseError at',
          'Unexpected token at',
        );
        throw JSSyntaxError(message);
      }
      if (e is Exception) rethrow;
      throw JSError('Evaluation error: $e');
    }

    // Execute pending async tasks after evaluation
    _vm!.runPendingTasks();

    if (result is JSPromise) {
      // If already fulfilled, return immediately
      if (result.state == PromiseState.fulfilled) {
        return Future.value(result.value ?? JSUndefined.instance);
      }
      if (result.state == PromiseState.rejected) {
        return Future.error(
          result.reason ?? JSValueFactory.string('Promise rejected'),
        );
      }

      // Promise is still pending (e.g. waiting on a setTimeout Timer).
      // Register .then() callbacks using the VM as the active runtime
      // so that microtask enqueuing and promise chaining work correctly.
      final completer = Completer<JSValue>();
      final vm = _vm!;

      final resolveCallback = JSNativeFunction(
        functionName: 'asyncResolve',
        nativeImpl: (args) {
          final value = args.isNotEmpty ? args[0] : JSValueFactory.undefined();
          if (!completer.isCompleted) {
            completer.complete(value);
          }
          return JSValueFactory.undefined();
        },
      );

      final rejectCallback = JSNativeFunction(
        functionName: 'asyncReject',
        nativeImpl: (args) {
          final error = args.isNotEmpty
              ? args[0]
              : JSValueFactory.string('Promise rejected');
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
          return JSValueFactory.undefined();
        },
      );

      // Use the VM to call .then() so JSRuntime.current is properly set
      final thenMethod = result.getProperty('then');
      if (thenMethod is JSFunction) {
        vm.callFunction(thenMethod, [resolveCallback, rejectCallback], result);
      }

      // Process microtasks enqueued by the .then() registration
      vm.runPendingTasks();

      return completer.future;
    } else {
      // Not a Promise, return immediately
      return Future.value(result);
    }
  }

  /// Evaluates a JavaScript expression and returns the Dart value
  dynamic evalToDart(String code) {
    try {
      final result = eval(code);
      return _toDartValue(result);
    } on JSObject catch (e) {
      throw e.toMap()['stack'] ?? e.toString();
    }
  }

  /// Evaluates a JavaScript expression asynchronously and returns the Dart value
  dynamic evalAsyncToDart(String code) async {
    try {
      final result = await evalAsync(code);
      return _toDartValue(result);
    } on JSObject catch (e) {
      throw e.toMap()['stack'] ?? e.toString();
    }
  }

  /// Defines a global variable
  void setGlobal(String name, dynamic value) {
    JSValue jsValue;
    if (value is JSException) {
      jsValue = value.toJSValue();
    } else {
      jsValue = JSValueFactory.fromDart(value);
    }
    _vm!.globals[name] = jsValue;
    final globalThis = _vm!.globals['globalThis'];
    if (globalThis is JSObject) {
      globalThis.setProperty(name, jsValue);
    }
  }

  /// Retrieves a global variable
  dynamic getGlobal(String name) {
    final jsValue = _vm!.globals[name] ?? JSUndefined.instance;
    return jsValue.primitiveValue;
  }

  /// Checks if a global variable exists
  bool hasGlobal(String name) {
    return _vm!.globals.containsKey(name);
  }

  /// Evaluates a simple JavaScript expression
  JSValue evalExpression(String code) {
    return eval(code);
  }

  /// Evaluates an expression and returns the Dart value
  dynamic evalExpressionToDart(String code) {
    final result = evalExpression(code);
    return result.primitiveValue;
  }

  /// Configures the module loader
  void setModuleLoader(Future<String> Function(String moduleId) loader) {
    _vm!.moduleLoader = loader;
  }

  /// Configures the module resolver
  void setModuleResolver(
    String Function(String moduleId, String? importer) resolver,
  ) {
    _vm!.moduleResolver = resolver;
  }

  /// Preloads a module asynchronously
  ///
  /// ES2022: Returns the loaded module to access exports
  Future<JSModule> loadModule(String moduleId, [String? importer]) async {
    final exports = await _vm!.loadModuleAsync(moduleId, importer);

    final resolvedId =
        _vm!.moduleResolver?.call(moduleId, importer) ?? moduleId;
    final module = JSModule(resolvedId, Environment.global());
    final previousRuntime = JSRuntime.current;
    JSRuntime.setCurrent(_vm!);
    try {
      for (final key in exports.getPropertyNames()) {
        final value = exports.getProperty(key);
        if (key == 'default') {
          module.defaultExport = value;
        }
        module.exports[key] = value;
      }
    } finally {
      JSRuntime.setCurrent(previousRuntime);
    }
    module.isLoaded = true;
    module.hasTopLevelAwait = _vm!.hasModuleTLA(resolvedId);
    module.status = ModuleStatus.evaluated;
    return module;
  }

  /// Manually executes pending asynchronous tasks (for tests)
  void runPendingAsyncTasks() {
    _vm!.runPendingTasks();
  }

  /// Runs the host-visible weak-reference collection step used by tests.
  void performHostGarbageCollection() {
    _vm!.performHostGarbageCollection();
    _vm!.runPendingTasks();
  }

  /// Registers a callback to receive messages from a JavaScript channel
  ///
  /// [channelName] - The name of the channel to listen to
  /// [callback] - The function to call when a message is received on this channel
  ///
  /// Example:
  /// ```dart
  /// interpreter.onMessage('user-input', (message) {
  ///   print('Message received: $message');
  /// });
  /// ```
  void onMessage(String channelName, dynamic Function(dynamic) callback) {
    MessageSystem(getInterpreterInstanceId()).onMessage(channelName, callback);
  }

  /// Removes all callbacks from a channel
  void removeChannel(String channelName) {
    MessageSystem(getInterpreterInstanceId()).removeChannel(channelName);
  }

  /// Removes a specific callback from a channel
  void removeCallback(String channelName, dynamic Function(dynamic) callback) {
    MessageSystem(
      getInterpreterInstanceId(),
    ).removeCallback(channelName, callback);
  }

  /// Returns the list of registered channels
  List<String> getChannels() {
    return MessageSystem(getInterpreterInstanceId()).getChannels();
  }

  /// Clears all channels and callbacks
  void clearMessageSystem() {
    MessageSystem(getInterpreterInstanceId()).clear();
  }

  dynamic _toDartValue(JSValue value) {
    if (value is JSBoolean) {
      return value.toBoolean();
    }
    if (value is JSArray) {
      return value.toList();
    }
    if (value is JSNumber) {
      return value.toNumber();
    }
    if (value is JSString) {
      return value.toString();
    }
    if (value is JSNull || value is JSUndefined) {
      return null;
    }
    if (value is JSObject) {
      return value.toMap();
    }
    return value.primitiveValue;
  }
}
