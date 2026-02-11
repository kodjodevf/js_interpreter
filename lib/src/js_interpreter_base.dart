/// Main JavaScript engine - Public API
///
/// This class provides the main interface for using the JavaScript engine.
library;

import 'dart:async';
import 'evaluator/evaluator.dart' show JSEvaluator, JSModule;
import 'parser/parser.dart';
import 'runtime/js_value.dart';
import 'runtime/message_system.dart';
import 'runtime/native_functions.dart';
import 'runtime/realm.dart';
import 'runtime/environment.dart' show BindingType;

/// Main JavaScript engine
class JSInterpreter {
  late final JSEvaluator _evaluator;
  bool _moduleMode = false;

  JSInterpreter() {
    _evaluator = JSEvaluator(
      getInterpreterInstanceId: getInterpreterInstanceId(),
    );
    _channelFunctionsRegistered[getInterpreterInstanceId()] = {};
  }
  static final Map<String, Map<String, Function(dynamic arg)>>
  _channelFunctionsRegistered = {};

  static Map<String, Map<String, Function(dynamic arg)>>
  get channelFunctionsRegistered => _channelFunctionsRegistered;

  String getInterpreterInstanceId() {
    return hashCode.toString();
  }

  /// Set module mode - in module context, certain identifiers are restricted
  void setModuleMode(bool isModule) {
    _moduleMode = isModule;
    _evaluator.moduleMode = isModule;
  }

  /// Check if currently in module mode
  bool get isModuleMode => _moduleMode;

  /// Registers a native function in the global environment
  void registerGlobal(String name, JSValue value) {
    _evaluator.globalEnvironment.define(name, value, BindingType.var_);
  }

  /// Creates a createRealm function that can be used in JavaScript
  /// This implements $262.createRealm() for test262 tests
  JSNativeFunction createRealmFunction() {
    return JSRealmFactory.createRealmFunction();
  }

  /// Evaluates a JavaScript code string
  /// Maintains state between evaluations
  JSValue eval(String code) {
    try {
      final program = JSParser.parseString(code);
      final result = _evaluator.evaluate(program);
      // Process any pending microtasks (e.g. Promise callbacks)
      _evaluator.runPendingAsyncTasks();
      return result;
    } catch (e) {
      if (e is JSError) rethrow;

      // Convertir ParseError en JSSyntaxError
      if (e.toString().contains('ParseError')) {
        final message = e.toString().replaceFirst(
          'ParseError at',
          'Unexpected token at',
        );
        throw JSSyntaxError(message);
      }
      // Laisser passer les Exception standard pour les tests
      if (e is Exception) rethrow;
      throw JSError('Evaluation error: $e');
    }
  }

  /// Evaluates a JavaScript code string asynchronously
  /// If the result is a JavaScript Promise, returns a Dart Future that resolves when the JS Promise resolves
  Future<JSValue> evalAsync(String code) async {
    final result = eval(code);

    // Execute pending async tasks after evaluation
    _evaluator.runPendingAsyncTasks();

    if (result is JSPromise) {
      // Create a Completer to wait for the JS Promise resolution
      final completer = Completer<JSValue>();

      // Call then on the Promise with callbacks
      final thenMethod = result.getProperty('then') as JSFunction;
      _evaluator.callFunction(thenMethod, [
        JSNativeFunction(
          functionName: 'asyncResolve',
          nativeImpl: (args) {
            final value = args.isNotEmpty
                ? args[0]
                : JSValueFactory.undefined();
            completer.complete(value);
            return JSValueFactory.undefined();
          },
        ),
        JSNativeFunction(
          functionName: 'asyncReject',
          nativeImpl: (args) {
            final error = args.isNotEmpty
                ? args[0]
                : JSValueFactory.string('Promise rejected');
            completer.completeError(error);
            return JSValueFactory.undefined();
          },
        ),
      ], result);

      // Process microtasks to execute the .then() callback we just registered
      _evaluator.runPendingAsyncTasks();

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
    _evaluator.setGlobalVariable(name, jsValue);
  }

  /// Retrieves a global variable
  dynamic getGlobal(String name) {
    final jsValue = _evaluator.getGlobalVariable(name);
    return jsValue.primitiveValue;
  }

  /// Checks if a global variable exists
  bool hasGlobal(String name) {
    return _evaluator.hasGlobalVariable(name);
  }

  /// Evaluates a simple JavaScript expression
  JSValue evalExpression(String code) {
    try {
      final expression = JSParser.parseExpression(code);
      return expression.accept(_evaluator);
    } catch (e) {
      if (e is JSError) rethrow;
      throw JSError('Expression evaluation error: $e');
    }
  }

  /// Evaluates an expression and returns the Dart value
  dynamic evalExpressionToDart(String code) {
    final result = evalExpression(code);
    return result.primitiveValue;
  }

  /// Configures the module loader
  void setModuleLoader(Future<String> Function(String moduleId) loader) {
    _evaluator.setModuleLoader(loader);
  }

  /// Configures the module resolver
  void setModuleResolver(
    String Function(String moduleId, String? importer) resolver,
  ) {
    _evaluator.setModuleResolver(resolver);
  }

  /// Preloads a module asynchronously
  ///
  /// ES2022: Returns the loaded module to access exports
  Future<JSModule> loadModule(String moduleId, [String? importer]) async {
    return await _evaluator.loadModule(moduleId, importer);
  }

  /// Manually executes pending asynchronous tasks (for tests)
  void runPendingAsyncTasks() {
    _evaluator.runPendingAsyncTasks();
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
