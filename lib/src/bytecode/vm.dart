/// Bytecode VM: executes compiled bytecode instructions.
///
/// Dispatches opcodes in a tight loop using a switch statement.
library;

import 'dart:async';
import 'dart:collection';
import '../runtime/environment.dart';
import 'dart:math' as math;

import '../runtime/js_value.dart';
import '../runtime/js_symbol.dart';
import '../runtime/js_regexp.dart';
import '../runtime/js_runtime.dart';
import '../runtime/native_functions.dart';
import '../runtime/function_prototype.dart';
import '../runtime/string_prototype.dart';
import '../runtime/number_prototype.dart';
import '../runtime/boolean_prototype.dart';
import '../runtime/bigint_prototype.dart';
import '../runtime/js_generator.dart';
import '../parser/parser.dart';
import '../parser/ast_nodes.dart';
import 'bytecode.dart';
import 'compiler.dart';
import 'opcodes.dart';

/// Result of VM execution
class VMResult {
  final JSValue value;
  final bool isReturn;
  final bool isException;

  const VMResult(this.value, {this.isReturn = false, this.isException = false});
  const VMResult.normal(this.value) : isReturn = false, isException = false;
  const VMResult.returned(this.value) : isReturn = true, isException = false;
  const VMResult.exception(this.value) : isReturn = false, isException = true;
}

/// The bytecode virtual machine.
///
/// Holds global state and executes FunctionBytecode objects.
class BytecodeVM implements JSRuntime {
  /// Global variables
  final Map<String, JSValue> globals = {};

  final Set<JSWeakMap> _registeredWeakMaps = <JSWeakMap>{};
  final Set<JSWeakRefObject> _registeredWeakRefs = <JSWeakRefObject>{};
  final Set<JSFinalizationRegistryObject> _registeredFinalizationRegistries =
      <JSFinalizationRegistryObject>{};

  /// Current stack frame being executed
  StackFrame? _currentFrame;

  /// Current function being called (for arguments.callee)
  _BytecodeFunction? _currentCalleeFunction;

  /// Optional callback to refresh external global state after host calls.
  void Function()? _postHostCallSync;

  // ==================================================================
  // Module system
  // ==================================================================

  /// Loaded module cache: resolvedId -> module exports object
  final Map<String, JSObject> _modules = {};

  /// Module loader callback (returns source code)
  Future<String> Function(String moduleId)? moduleLoader;

  /// Module resolver callback (resolves specifier relative to importer)
  String Function(String moduleId, String? importer)? moduleResolver;

  /// Module loading futures cache to avoid double-loading
  final Map<String, Future<JSObject>> _moduleLoadingFutures = {};

  /// Current module URL during module evaluation (for import.meta)
  String? _currentModuleUrl;

  /// Current resolved module id during module evaluation.
  String? _currentModuleId;

  /// Per-module hasTopLevelAwait info
  final Map<String, bool> _moduleHasTLA = {};

  /// Public API for loading a module (called from JSInterpreter)
  Future<JSObject> loadModuleAsync(String moduleId, [String? importer]) {
    return _loadModuleAsync(moduleId, importer);
  }

  /// Public getter for module TLA info
  bool hasModuleTLA(String resolvedId) => _moduleHasTLA[resolvedId] ?? false;

  /// Dynamic import handler — called by Op.import_
  /// Returns a JSPromise that resolves with the module namespace object.
  JSValue _dynamicImport(String moduleId) {
    final promise = JSPromise.createInternal();

    if (moduleLoader == null) {
      promise.reject(_makeError('TypeError', 'No module loader configured'));
      _drainMicrotasks();
      return promise;
    }

    _loadModuleAsync(moduleId)
        .then((exports) {
          final prev = JSRuntime.current;
          JSRuntime.setCurrent(this);
          try {
            promise.resolve(exports);
            _drainMicrotasks();
          } finally {
            JSRuntime.setCurrent(prev);
          }
        })
        .catchError((error) {
          final prev = JSRuntime.current;
          JSRuntime.setCurrent(this);
          try {
            promise.reject(JSString(error.toString()));
            _drainMicrotasks();
          } finally {
            JSRuntime.setCurrent(prev);
          }
        });

    return promise;
  }

  /// Load a module asynchronously, returning its exports object.
  Future<JSObject> _loadModuleAsync(String moduleId, [String? importer]) async {
    final resolvedId = moduleResolver?.call(moduleId, importer) ?? moduleId;

    // Avoid double-loading
    if (_moduleLoadingFutures.containsKey(resolvedId)) {
      return _moduleLoadingFutures[resolvedId]!;
    }

    // Return cached fully-loaded module
    if (_modules.containsKey(resolvedId)) {
      return _modules[resolvedId]!;
    }

    final future = _loadModuleImpl(resolvedId);
    _moduleLoadingFutures[resolvedId] = future;
    try {
      return await future;
    } finally {
      _moduleLoadingFutures.remove(resolvedId);
    }
  }

  Future<JSObject> _loadModuleImpl(String resolvedId) async {
    if (moduleLoader == null) {
      throw JSError('No module loader configured');
    }

    final exports = JSObject();
    _modules[resolvedId] = exports;

    try {
      final sourceCode = await moduleLoader!(resolvedId);

      // Parse as module (allow top-level await, imports/exports)
      final ast = JSParser.parseString(sourceCode, allowTopLevelAwait: true);

      await _ensureStaticModuleDependenciesLoaded(ast, resolvedId);

      // Detect top-level await
      final hasTLA = _detectTopLevelAwait(ast);
      _moduleHasTLA[resolvedId] = hasTLA;

      // Compile the module
      final compiler = BytecodeCompiler();
      compiler.moduleUrl = 'file:///$resolvedId';
      final bytecode = compiler.compileModule(ast);

      // Execute the module
      final moduleUrl = 'file:///$resolvedId';
      final previousModuleId = _currentModuleId;
      final previousModuleUrl = _currentModuleUrl;
      _currentModuleId = resolvedId;
      _currentModuleUrl = moduleUrl;

      try {
        if (hasTLA) {
          await _executeModuleAsync(bytecode, resolvedId, exports);
        } else {
          _executeModuleSync(bytecode, resolvedId, exports);
        }
      } finally {
        _currentModuleId = previousModuleId;
        _currentModuleUrl = previousModuleUrl;
      }

      return exports;
    } catch (_) {
      if (identical(_modules[resolvedId], exports)) {
        _modules.remove(resolvedId);
      }
      rethrow;
    }
  }

  Future<void> _ensureStaticModuleDependenciesLoaded(
    Program program,
    String importerResolvedId,
  ) async {
    for (final stmt in program.body) {
      String? specifier;
      if (stmt is ImportDeclaration) {
        specifier = stmt.source.value as String;
      } else if (stmt is ExportNamedDeclaration && stmt.source != null) {
        specifier = stmt.source!.value as String;
      } else if (stmt is ExportAllDeclaration) {
        specifier = stmt.source.value as String;
      }

      if (specifier == null) {
        continue;
      }

      final resolvedId =
          moduleResolver?.call(specifier, importerResolvedId) ?? specifier;

      // Cyclic dependency already has a placeholder in the module cache.
      if (_modules.containsKey(resolvedId) ||
          _moduleLoadingFutures.containsKey(resolvedId)) {
        continue;
      }

      await _loadModuleAsync(specifier, importerResolvedId);
    }
  }

  /// Execute a module synchronously, return its exports.
  void _executeModuleSync(
    FunctionBytecode script,
    String moduleId,
    JSObject exports,
  ) {
    final previousRuntime = JSRuntime.current;
    JSRuntime.setCurrent(this);
    final frame = StackFrame(func: script, thisValue: JSUndefined.instance);

    _installLiveModuleExports(frame, script, exports);

    try {
      _executeFrame(frame);
    } on _JSException catch (e) {
      throw JSException(e.value);
    } finally {
      JSRuntime.setCurrent(previousRuntime);
      runPendingTasks();
    }

    _extractModuleExports(frame, script, exports);
  }

  /// Execute a module with top-level await, return its exports.
  Future<void> _executeModuleAsync(
    FunctionBytecode script,
    String moduleId,
    JSObject exports,
  ) async {
    final previousRuntime = JSRuntime.current;
    JSRuntime.setCurrent(this);

    // Create frame and wrap in async execution
    final frame = StackFrame(func: script, thisValue: JSUndefined.instance);

    _installLiveModuleExports(frame, script, exports);

    final completer = Completer<void>();
    final outerPromise = JSPromise.createInternal();

    _asyncFuncResume(frame, outerPromise, null, false);
    _drainMicrotasks();

    // Chain on the outer promise to get the result
    final resolveCallback = JSNativeFunction(
      functionName: 'moduleResolve',
      nativeImpl: (args) {
        if (!completer.isCompleted) {
          _extractModuleExports(frame, script, exports);
          completer.complete();
        }
        return JSUndefined.instance;
      },
    );
    final rejectCallback = JSNativeFunction(
      functionName: 'moduleReject',
      nativeImpl: (args) {
        if (!completer.isCompleted) {
          final error = args.isNotEmpty
              ? args[0]
              : JSString('Module evaluation failed');
          completer.completeError(error);
        }
        return JSUndefined.instance;
      },
    );

    PromisePrototype.then([resolveCallback, rejectCallback], outerPromise);
    _drainMicrotasks();

    JSRuntime.setCurrent(previousRuntime);

    // Wait for Dart timers (setTimeout etc.) if needed
    return completer.future;
  }

  /// Extract exports from a completed module frame.
  void _extractModuleExports(
    StackFrame frame,
    FunctionBytecode script,
    JSObject exports,
  ) {
    final vars = script.vars;
    for (var i = 0; i < vars.length; i++) {
      final name = vars[i].name;
      // Export markers are prefixed with __export__
      if (name.startsWith('__export__')) {
        continue;
      }
    }
    // Also check globals set during module execution for 'default' export
    // (handled by putVar in the export compilation)
  }

  void _installLiveModuleExports(
    StackFrame frame,
    FunctionBytecode script,
    JSObject exports,
  ) {
    if (script.moduleExportBindings.isEmpty) {
      return;
    }

    for (final entry in script.moduleExportBindings.entries) {
      final exportName = entry.key;
      final localName = entry.value;
      final localIndex = script.vars.indexWhere(
        (variable) => variable.name == localName,
      );
      if (localIndex == -1) {
        continue;
      }

      exports.defineProperty(
        exportName,
        PropertyDescriptor(
          getter: JSNativeFunction(
            functionName: 'moduleExport:$exportName',
            nativeImpl: (_) => _readLocal(frame, localIndex),
          ),
          enumerable: true,
          configurable: true,
        ),
      );
    }
  }

  /// Detect if a program has top-level await
  bool _detectTopLevelAwait(Program program) {
    for (final stmt in program.body) {
      if (_stmtHasTLA(stmt)) return true;
    }
    return false;
  }

  bool _stmtHasTLA(Statement stmt) {
    if (stmt is ExpressionStatement) return _exprHasAwait(stmt.expression);
    if (stmt is VariableDeclaration) {
      for (final d in stmt.declarations) {
        if (d.init != null && _exprHasAwait(d.init!)) return true;
      }
    }
    if (stmt is IfStatement) return _exprHasAwait(stmt.test);
    if (stmt is ForStatement) {
      if (stmt.test != null && _exprHasAwait(stmt.test!)) return true;
      if (stmt.update != null && _exprHasAwait(stmt.update!)) return true;
    }
    if (stmt is ReturnStatement && stmt.argument != null) {
      return _exprHasAwait(stmt.argument!);
    }
    // ExportDeclarationStatement: check the inner declaration
    if (stmt is ExportDeclarationStatement) {
      return _stmtHasTLA(stmt.declaration);
    }
    if (stmt is ExportDefaultDeclaration) {
      return _exprHasAwait(stmt.declaration);
    }
    return false;
  }

  bool _exprHasAwait(Expression expr) {
    if (expr is AwaitExpression) return true;
    if (expr is FunctionExpression ||
        expr is ArrowFunctionExpression ||
        expr is AsyncArrowFunctionExpression ||
        expr is AsyncFunctionExpression) {
      return false; // Don't descend into nested functions
    }
    if (expr is BinaryExpression) {
      return _exprHasAwait(expr.left) || _exprHasAwait(expr.right);
    }
    if (expr is UnaryExpression) return _exprHasAwait(expr.operand);
    if (expr is ConditionalExpression) {
      return _exprHasAwait(expr.test) ||
          _exprHasAwait(expr.consequent) ||
          _exprHasAwait(expr.alternate);
    }
    if (expr is AssignmentExpression) return _exprHasAwait(expr.right);
    if (expr is CallExpression) {
      if (_exprHasAwait(expr.callee)) return true;
      for (final a in expr.arguments) {
        if (_exprHasAwait(a)) return true;
      }
    }
    if (expr is ArrayExpression) {
      for (final e in expr.elements) {
        if (e != null && _exprHasAwait(e)) return true;
      }
    }
    if (expr is ObjectExpression) {
      for (final p in expr.properties) {
        if (p.value is Expression && _exprHasAwait(p.value as Expression)) {
          return true;
        }
      }
    }
    if (expr is MemberExpression) return _exprHasAwait(expr.object);
    if (expr is SequenceExpression) {
      for (final e in expr.expressions) {
        if (_exprHasAwait(e)) return true;
      }
    }
    if (expr is TemplateLiteralExpression) {
      for (final e in expr.expressions) {
        if (_exprHasAwait(e)) return true;
      }
    }
    return false;
  }

  void setPostHostCallSync(void Function() callback) {
    _postHostCallSync = callback;
  }

  /// Initialize with standard globals (console, etc.)
  BytecodeVM() {
    _initGlobals();
  }

  void _initGlobals() {
    globals['undefined'] = JSUndefined.instance;
    globals['null'] = JSNull.instance;
    globals['true'] = JSBoolean(true);
    globals['false'] = JSBoolean(false);
    globals['NaN'] = JSNumber(double.nan);
    globals['Infinity'] = JSNumber(double.infinity);

    // console.log
    final console = JSObject();
    console.setProperty(
      'log',
      JSNativeFunction(
        functionName: 'log',
        nativeImpl: (args) {
          final output = args.map((a) => _jsToString(a)).join(' ');
          _consoleOutput.add(output);
          return JSUndefined.instance;
        },
      ),
    );
    console.setProperty(
      'error',
      JSNativeFunction(
        functionName: 'error',
        nativeImpl: (args) {
          final output = args.map((a) => _jsToString(a)).join(' ');
          _consoleOutput.add(output);
          return JSUndefined.instance;
        },
      ),
    );
    console.setProperty(
      'warn',
      JSNativeFunction(
        functionName: 'warn',
        nativeImpl: (args) {
          final output = args.map((a) => _jsToString(a)).join(' ');
          _consoleOutput.add(output);
          return JSUndefined.instance;
        },
      ),
    );
    globals['console'] = console;
    globals['__validateArrayDestructure__'] = JSNativeFunction(
      functionName: '__validateArrayDestructure__',
      nativeImpl: (args) {
        final value = args.isNotEmpty ? args[0] : JSUndefined.instance;
        final isIterable =
            value is JSArray ||
            value is JSString ||
            (value is JSObject &&
                value.hasProperty(JSSymbol.iterator.propertyKey));
        if (!isIterable) {
          final typeName = value.isNull ? 'null' : value.type.name;
          throw JSTypeError('$typeName is not iterable');
        }
        return JSUndefined.instance;
      },
    );

    globals['__validateObjectDestructure__'] = JSNativeFunction(
      functionName: '__validateObjectDestructure__',
      nativeImpl: (args) {
        final value = args.isNotEmpty ? args[0] : JSUndefined.instance;
        // Per spec: only null and undefined are not object-coercible
        // Primitives (number, string, boolean) are wrapped to objects
        if (value == JSNull.instance || value == JSUndefined.instance) {
          throw JSTypeError(
            'Cannot destructure \'${value == JSNull.instance ? "null" : "undefined"}\' as it is ${value == JSNull.instance ? "null" : "undefined"}.',
          );
        }
        return JSUndefined.instance;
      },
    );

    // Synchronous module import helper (for static import declarations)
    globals['__import_sync__'] = JSNativeFunction(
      functionName: '__import_sync__',
      nativeImpl: (args) {
        final moduleId = args.isNotEmpty ? _jsToString(args[0]) : '';
        if (_modules.containsKey(moduleId)) {
          return _modules[moduleId]!;
        }
        // Try with resolver
        final resolvedId =
            moduleResolver?.call(moduleId, _currentModuleId) ?? moduleId;
        if (_modules.containsKey(resolvedId)) {
          return _modules[resolvedId]!;
        }
        throw JSError(
          'Module $moduleId is not loaded. Use loadModule() to load it first.',
        );
      },
    );
  }

  /// Console output buffer (for testing)
  final List<String> _consoleOutput = [];

  /// Emits a trace record before throwing `is not a function` errors.
  bool traceNotAFunctionErrors = false;

  /// Emits a per-opcode execution trace when diagnosing VM bugs.
  bool traceExecution = false;

  /// Microtask queue for Promise callbacks
  final List<void Function()> _microtaskQueue = [];

  /// Get and clear console output
  List<String> takeConsoleOutput() {
    final out = List<String>.from(_consoleOutput);
    _consoleOutput.clear();
    return out;
  }

  void _traceNotAFunctionError(
    JSValue func,
    JSValue thisValue,
    List<JSValue> args,
  ) {
    if (!traceNotAFunctionErrors) {
      return;
    }

    final frame = _currentFrame;
    final functionName = frame == null
        ? '<no-frame>'
        : (frame.func.name.isEmpty ? '<anonymous>' : frame.func.name);
    final location = _describeCurrentLocation(frame);
    final opcode = _describeCurrentOpcode(frame);
    final stackSnapshot = _describeStackTop(frame);
    final localsSnapshot = _describeLocals(frame);
    final closureSnapshot = _describeClosureVars(frame);
    final argsDescription = args.map(_jsToString).join(', ');
    _consoleOutput.add(
      '[trace:not-a-function] '
      'callee=${_jsToString(func)} '
      'jsType=${_describeJsType(func)} '
      'dartType=${func.runtimeType} '
      'this=${_jsToString(thisValue)} '
      'args=[$argsDescription] '
      'function=$functionName '
      'opcode=$opcode '
      'pc=${frame?.pc ?? -1} '
      'location=$location '
      'stackTop=$stackSnapshot '
      'locals=$localsSnapshot '
      'closureVars=$closureSnapshot',
    );
  }

  String _describeCurrentOpcode(StackFrame? frame) {
    if (frame == null ||
        frame.pc < 0 ||
        frame.pc >= frame.func.bytecode.length) {
      return '<unknown>';
    }

    final rawOp = frame.func.bytecode[frame.pc];
    final op = Op.values[rawOp];
    return opInfo[op]?.name ?? op.name;
  }

  String _describeStackTop(StackFrame? frame, {int maxDepth = 4}) {
    if (frame == null || frame.sp == 0) {
      return '[]';
    }

    final start = frame.sp > maxDepth ? frame.sp - maxDepth : 0;
    final parts = <String>[];
    for (var index = start; index < frame.sp; index++) {
      parts.add('${index - start}:${_formatDebugValue(frame.stack[index])}');
    }
    return '[${parts.join(', ')}]';
  }

  String _describeLocals(StackFrame? frame, {int maxLocals = 8}) {
    if (frame == null || frame.locals.isEmpty) {
      return '[]';
    }

    final parts = <String>[];
    final count = frame.locals.length < maxLocals
        ? frame.locals.length
        : maxLocals;
    for (var index = 0; index < count; index++) {
      final name = frame.func.vars[index].name;
      parts.add('$name=${_formatDebugValue(frame.locals[index])}');
    }
    if (frame.locals.length > maxLocals) {
      parts.add('...');
    }
    return '[${parts.join(', ')}]';
  }

  String _describeClosureVars(StackFrame? frame, {int maxClosureVars = 8}) {
    if (frame == null || frame.closureVarRefs.isEmpty) {
      return '[]';
    }

    final parts = <String>[];
    final count = frame.closureVarRefs.length < maxClosureVars
        ? frame.closureVarRefs.length
        : maxClosureVars;
    for (var index = 0; index < count; index++) {
      final name = frame.func.closureVars[index].name;
      parts.add(
        '$name=${_formatDebugValue(frame.closureVarRefs[index].value)}',
      );
    }
    if (frame.closureVarRefs.length > maxClosureVars) {
      parts.add('...');
    }
    return '[${parts.join(', ')}]';
  }

  String _formatDebugValue(JSValue value) {
    final resolved = value is _VarRefWrapper ? value.ref.value : value;
    return '${_jsToString(resolved)}<${_describeJsType(resolved)}>';
  }

  String _describeJsType(JSValue value) {
    if (value.isUndefined) return 'undefined';
    if (value.isNull) return 'null';
    if (value.isBoolean) return 'boolean';
    if (value.isNumber) return 'number';
    if (value.isString) return 'string';
    if (value.isSymbol) return 'symbol';
    if (value.isBigInt) return 'bigint';
    if (value is JSNativeFunction ||
        value is JSFunction ||
        value is DynamicFunction ||
        value is RuntimeCallableFunction ||
        value is _BytecodeFunction) {
      return 'function';
    }
    if (value is JSArray) return 'object(array)';
    if (value is JSObject) return 'object';
    return value.type.name;
  }

  String _describeCurrentLocation(StackFrame? frame) {
    if (frame == null) {
      return '<unknown>';
    }

    final mappings = frame.func.sourceMap;
    if (mappings == null || mappings.isEmpty) {
      return '${frame.func.name.isEmpty ? '<anonymous>' : frame.func.name}@pc=${frame.pc}';
    }

    SourceMapping current = mappings.first;
    for (final mapping in mappings) {
      if (mapping.bytecodeOffset > frame.pc) {
        break;
      }
      current = mapping;
    }
    final functionName = frame.func.name.isEmpty
        ? '<anonymous>'
        : frame.func.name;
    return '$functionName@${current.line}:${current.column}';
  }

  ({int line, int column})? _currentSourcePosition([StackFrame? frame]) {
    final activeFrame = frame ?? _currentFrame;
    if (activeFrame == null) {
      return null;
    }

    final mappings = activeFrame.func.sourceMap;
    if (mappings == null || mappings.isEmpty) {
      return null;
    }

    SourceMapping current = mappings.first;
    for (final mapping in mappings) {
      if (mapping.bytecodeOffset > activeFrame.pc) {
        break;
      }
      current = mapping;
    }
    return (line: current.line, column: current.column);
  }

  String _formatStackFrame(StackFrame frame) {
    final position = _currentSourcePosition(frame);
    final functionName = frame.func.name.isEmpty
        ? '<anonymous>'
        : frame.func.name;
    if (position == null) {
      return functionName;
    }
    return '$functionName:${position.line}:${position.column}';
  }

  String captureCurrentStackTrace() {
    final lines = <String>[];
    for (
      StackFrame? frame = _currentFrame;
      frame != null;
      frame = frame.callerFrame
    ) {
      lines.add(_formatStackFrame(frame));
    }
    return lines.join('\n');
  }

  List<int>? captureCurrentSourcePosition() {
    final position = _currentSourcePosition();
    if (position == null) {
      return null;
    }
    return [position.line, position.column];
  }

  // ==================================================================
  // JSRuntime interface implementation
  // ==================================================================

  @override
  JSValue callFunction(
    JSValue func,
    List<JSValue> args, [
    JSValue? thisBinding,
  ]) {
    // Ensure JSRuntime.current is set to this VM so that callbacks
    // triggered asynchronously (e.g. from setTimeout) can access the runtime.
    final previousRuntime = JSRuntime.current;
    final needsRestore = !identical(previousRuntime, this);
    if (needsRestore) {
      JSRuntime.setCurrent(this);
    }
    try {
      return _callFunctionInternal(func, args, thisBinding);
    } on _ThrowSignal catch (sig) {
      _rethrowCallFunctionError(sig.value);
    } on _JSException catch (e) {
      _rethrowCallFunctionError(e.value);
    } on JSError {
      rethrow;
    } finally {
      if (needsRestore) {
        JSRuntime.setCurrent(previousRuntime);
      }
    }
  }

  Never _rethrowCallFunctionError(JSValue value) {
    if (value is JSObject && value.hasInternalSlot('HostErrorName')) {
      switch (value.getInternalSlot('HostErrorName')) {
        case 'TypeError':
          throw JSTypeError(value.getProperty('message').toString());
        case 'ReferenceError':
          throw JSReferenceError(value.getProperty('message').toString());
        case 'SyntaxError':
          throw JSSyntaxError(value.getProperty('message').toString());
        case 'RangeError':
          throw JSRangeError(value.getProperty('message').toString());
        case 'URIError':
          throw JSURIError(value.getProperty('message').toString());
      }
    }
    throw JSException(value);
  }

  JSValue _callFunctionInternal(
    JSValue func,
    List<JSValue> args, [
    JSValue? thisBinding,
  ]) {
    final thisVal = thisBinding ?? JSUndefined.instance;
    // For _BytecodeFunction: use the VM's own call path
    if (func is _BytecodeFunction) {
      return _callBytecodeFunction(func, thisVal, args);
    }
    // For bound functions
    if (func is JSBoundFunction) {
      final allArgs = [...func.boundArgs, ...args];
      return _callFunctionInternal(
        func.originalFunction,
        allArgs,
        func.thisArg,
      );
    }
    // For native functions (including array methods, etc.)
    if (func is JSNativeFunction) {
      if (func.isConstructor) {
        return func.callWithThis(args, JSUndefined.instance);
      }
      return func.callWithThis(args, thisVal);
    }
    // DynamicFunction from Function() constructor
    if (func is DynamicFunction) {
      return func.execute(args, thisVal);
    }
    if (func is RuntimeCallableFunction) {
      final callable = func as RuntimeCallableFunction;
      return callable.callWithRuntime(args, thisVal, this);
    }
    if (func is JSFunction) {
      final promoted = _tryPromoteLegacyFunction(func);
      if (promoted != null) {
        return _callBytecodeFunction(promoted, thisVal, args);
      }
    }
    if (func is JSFunction) {
      throw JSTypeError(
        'Unsupported legacy JSFunction in bytecode VM: ${func.declaration.runtimeType}',
      );
    }
    _traceNotAFunctionError(func, thisVal, args);
    throw JSTypeError('${_jsToString(func)} is not a function');
  }

  @override
  bool isStrictMode() => _currentFrame?.func.isStrict ?? false;

  @override
  void enqueueMicrotask(void Function() callback) {
    _microtaskQueue.add(callback);
  }

  @override
  void notifyPromiseResolved(JSPromise promise) {
    // No-op for now — the synchronous VM doesn't need to wake up tasks
  }

  @override
  void runPendingTasks() {
    // Ensure JSRuntime.current is set so microtask callbacks
    // (e.g. Promise._settle) can access the runtime.
    final previousRuntime = JSRuntime.current;
    final needsRestore = !identical(previousRuntime, this);
    if (needsRestore) {
      JSRuntime.setCurrent(this);
    }
    try {
      _drainMicrotasks();
    } finally {
      if (needsRestore) {
        JSRuntime.setCurrent(previousRuntime);
      }
    }
  }

  /// Drain the microtask queue. Can be called mid-execution (e.g. after await).
  /// Caller must ensure JSRuntime.current is set to this VM.
  void _drainMicrotasks() {
    while (_microtaskQueue.isNotEmpty) {
      final task = _microtaskQueue.removeAt(0);
      task();
    }
  }

  @override
  JSValue evalCode(String code, {bool directEval = false}) {
    final inheritedStrictMode = directEval && isStrictMode();
    final initialFunctionDepth =
        directEval &&
            _currentFrame != null &&
            _currentFrame!.func.name != '<script>'
        ? 1
        : 0;
    final forcedSuperVarName = directEval
        ? _findVisibleSuperBindingName(_currentFrame)
        : null;
    final program = JSParser.parseString(
      code,
      initialStrictMode: inheritedStrictMode,
      initialFunctionDepth: initialFunctionDepth,
      initialClassContext: forcedSuperVarName != null,
    );
    final compiler = BytecodeCompiler();
    final bytecode = compiler.compile(
      program,
      forcedStrictMode: inheritedStrictMode,
      forcedSuperVarName: forcedSuperVarName,
    );

    if (directEval && _currentFrame != null) {
      final previousRuntime = JSRuntime.current;
      JSRuntime.setCurrent(this);
      final hostFrame = _currentFrame!;
      final frame = StackFrame(
        func: bytecode,
        thisValue: hostFrame.thisValue,
        newTarget: hostFrame.newTarget,
        callerFrame: hostFrame,
        evalBindings: _collectDirectEvalHostBindings(hostFrame),
        withObjects: List<JSObject>.of(hostFrame.withObjects),
        isDirectEvalFrame: true,
        directEvalHostFrame: hostFrame,
      );

      JSValue result;
      try {
        result = _executeFrame(frame);
      } on _JSException catch (e) {
        throw JSException(e.value);
      } finally {
        JSRuntime.setCurrent(previousRuntime);
        runPendingTasks();
      }

      _persistDirectEvalLocals(frame);
      return result;
    }

    return execute(bytecode);
  }

  @override
  JSValue getGlobal(String name) {
    return _lookupGlobalBinding(name) ?? JSUndefined.instance;
  }

  @override
  void registerWeakMap(JSWeakMap weakMap) {
    _registeredWeakMaps.add(weakMap);
  }

  @override
  void registerWeakRef(JSWeakRefObject weakRef) {
    _registeredWeakRefs.add(weakRef);
  }

  @override
  void registerFinalizationRegistry(JSFinalizationRegistryObject registry) {
    _registeredFinalizationRegistries.add(registry);
  }

  @override
  bool isValueReachable(JSValue value) {
    final visited = HashSet<Object>.identity();

    bool mark(JSValue candidate) =>
        jsValueReferencesTarget(candidate, value, visited: visited);

    for (
      StackFrame? frame = _currentFrame;
      frame != null;
      frame = frame.callerFrame
    ) {
      if (mark(frame.thisValue) || mark(frame.newTarget)) {
        return true;
      }
      final callee = frame.calleeFunction;
      if (callee != null && mark(callee)) {
        return true;
      }
      for (final arg in frame.args) {
        if (mark(arg)) {
          return true;
        }
      }
      for (final passedArg in frame.passedArgs) {
        if (mark(passedArg)) {
          return true;
        }
      }
      for (var i = 0; i < frame.locals.length; i++) {
        if (i < frame.func.vars.length &&
            frame.func.vars[i].name.startsWith('__')) {
          continue;
        }
        if (mark(frame.locals[i])) {
          return true;
        }
      }
      for (final closureVar in frame.closureVarRefs) {
        if (mark(closureVar.value)) {
          return true;
        }
      }
      for (final binding in frame.evalBindings.values) {
        if (mark(binding.value)) {
          return true;
        }
      }
      for (final withObject in frame.withObjects) {
        if (mark(withObject)) {
          return true;
        }
      }
    }

    return false;
  }

  @override
  void performHostGarbageCollection() {
    for (final weakRef in _registeredWeakRefs.toList(growable: false)) {
      weakRef.clearIfCollected(this);
    }
    for (final weakMap in _registeredWeakMaps.toList(growable: false)) {
      weakMap.purgeCollectedEntries(this);
    }
    for (final registry in _registeredFinalizationRegistries.toList(
      growable: false,
    )) {
      registry.collectGarbage(this);
    }
  }

  @override
  JSValue? getCurrentCaller(JSFunction callee) {
    final currentFrame = _currentFrame;
    if (currentFrame == null) {
      return JSValueFactory.undefined();
    }

    final callerFunction = currentFrame.callerFrame?.calleeFunction;
    if (callerFunction == null) {
      return JSValueFactory.undefined();
    }

    if (callerFunction is _BytecodeFunction &&
        callerFunction.bytecode.isStrict) {
      throw JSTypeError(
        '"caller", "callee", and "arguments" properties may not be accessed on strict mode functions or the arguments objects for calls to them',
      );
    }

    if (callerFunction.strictMode) {
      throw JSTypeError(
        '"caller", "callee", and "arguments" properties may not be accessed on strict mode functions or the arguments objects for calls to them',
      );
    }

    return callerFunction;
  }

  final _activeGetters = Set<JSValue>.identity();
  final _activeGetterPairs = <(JSObject, String)>{};
  final _activeSetters = <(JSObject, String)>{};

  @override
  bool isGetterCycle(JSObject obj, String property) =>
      _activeGetterPairs.contains((obj, property));
  @override
  void markGetterActive(JSObject obj, String property) =>
      _activeGetterPairs.add((obj, property));
  @override
  void unmarkGetterActive(JSObject obj, String property) =>
      _activeGetterPairs.remove((obj, property));
  @override
  bool isSetterCycle(JSObject obj, String property) =>
      _activeSetters.contains((obj, property));
  @override
  void markSetterActive(JSObject obj, String property) =>
      _activeSetters.add((obj, property));
  @override
  void unmarkSetterActive(JSObject obj, String property) =>
      _activeSetters.remove((obj, property));

  @override
  JSValue evalASTNode(dynamic node) => JSUndefined.instance;

  @override
  void executeStaticBlock(dynamic body, JSValue classObj) {}

  /// Execute a top-level FunctionBytecode (script)
  JSValue execute(FunctionBytecode script) {
    final previousRuntime = JSRuntime.current;
    JSRuntime.setCurrent(this);
    final frame = StackFrame(func: script, thisValue: _getGlobalThis());

    JSValue result;
    try {
      result = _executeFrame(frame);
    } on _JSException catch (e) {
      // Convert internal exception to public JSException
      throw JSException(e.value);
    } finally {
      JSRuntime.setCurrent(previousRuntime);
      // Process microtasks after each top-level execution
      runPendingTasks();
    }

    // Persist top-level locals into globals
    _persistTopLevelLocals(frame);

    return result;
  }

  /// Persist top-level locals into globals so subsequent eval() calls can
  /// access variables declared in previous eval() calls.
  void _persistTopLevelLocals(StackFrame frame) {
    final vars = frame.func.vars;
    for (var i = 0; i < vars.length; i++) {
      final variable = vars[i];
      if (!_shouldPersistTopLevelBinding(variable)) {
        continue;
      }

      final name = variable.name;
      final value = frame.locals[i];
      if (value is _VarRefWrapper) {
        // Preserve the VarRef so future closure writes propagate
        if (!value.ref.value.isUndefined || !globals.containsKey(name)) {
          globals[name] = value;
        }
      } else if (variable.isLexical || variable.isConst) {
        if (!value.isUndefined || !globals.containsKey(name)) {
          globals[name] = _VarRefWrapper(
            LocalBindingVarRef(
              name,
              isConst: variable.isConst,
              isLexical: variable.isLexical,
              value: value,
            ),
          );
        }
      } else {
        if (!value.isUndefined || !globals.containsKey(name)) {
          globals[name] = value;
        }
      }
    }
  }

  bool _shouldPersistTopLevelBinding(VarDef variable) {
    if (variable.scope == VarScope.funcScope) {
      return true;
    }
    return variable.isLexical && variable.scopeLevel == 0;
  }

  bool _isPersistentLexicalGlobal(JSValue? value) {
    return value is _VarRefWrapper &&
        value.ref is LocalBindingVarRef &&
        (value.ref as LocalBindingVarRef).isLexical;
  }

  void _syncTopLevelLocalToGlobal(StackFrame frame, int index, JSValue value) {
    if (frame.callerFrame != null) {
      return;
    }
    if (index < 0 || index >= frame.func.vars.length) {
      return;
    }

    final varDef = frame.func.vars[index];
    if (varDef.scope != VarScope.funcScope) {
      return;
    }

    final globalThis = globals['globalThis'];
    if (globalThis is JSObject) {
      globalThis.setProperty(varDef.name, value);
      _syncGlobalCacheFromObject(varDef.name, globalThis);
    } else {
      _syncGlobalCacheValue(varDef.name, value);
    }
  }

  void _syncGlobalCacheValue(String name, JSValue value) {
    final existing = globals[name];
    if (_isPersistentLexicalGlobal(existing)) {
      return;
    }
    if (existing is _VarRefWrapper) {
      existing.ref.value = value;
      return;
    }
    globals[name] = value;
  }

  void _syncGlobalCacheFromObject(String name, JSObject globalThis) {
    final descriptor = globalThis.getOwnPropertyDescriptor(name);
    if (descriptor == null) {
      if (!_isPersistentLexicalGlobal(globals[name])) {
        globals.remove(name);
      }
      return;
    }
    _syncGlobalCacheValue(name, globalThis.getProperty(name));
  }

  /// Internal call — used by VM ops. Wraps host errors into _ThrowSignal.
  JSValue _callFunction(JSValue func, JSValue thisValue, List<JSValue> args) {
    try {
      if (func is _BytecodeFunction) {
        return _callBytecodeFunction(func, thisValue, args);
      }
      // Handle bound functions (JSBoundFunction extends JSFunction, not JSNativeFunction)
      if (func is JSBoundFunction) {
        final allArgs = [...func.boundArgs, ...args];
        return _callFunction(func.originalFunction, func.thisArg, allArgs);
      }
      if (func is JSNativeFunction) {
        // For constructor functions called as regular functions (e.g. Array(10)
        // without 'new'), pass undefined as thisBinding so the constructor
        // receives only the user-supplied args, just like _callConstructor does.
        // Preserve an object receiver for native super() calls so built-in
        // constructors like Promise can initialize the derived instance.
        if (func.isConstructor) {
          // Date() without new returns a string per spec
          if (func.functionName == 'Date') {
            _postHostCallSync?.call();
            return JSString(DateTime.now().toString());
          }
          final constructorThis =
              thisValue is JSObject &&
                  !thisValue.isNull &&
                  !thisValue.isUndefined
              ? thisValue
              : JSUndefined.instance;
          final result = constructorThis is JSObject
              ? JSNativeFunction.withConstructorCall(
                  () => func.callWithThis(args, constructorThis),
                )
              : func.callWithThis(args, constructorThis);
          _postHostCallSync?.call();
          return result;
        }
        final result = func.callWithThis(args, thisValue);
        _postHostCallSync?.call();
        return result;
      }
      // DynamicFunction from Function() constructor — has its own execute()
      if (func is DynamicFunction) {
        final result = func.execute(args, thisValue);
        _postHostCallSync?.call();
        return result;
      }
      if (func is RuntimeCallableFunction) {
        final callable = func as RuntimeCallableFunction;
        final result = callable.callWithRuntime(args, thisValue, this);
        _postHostCallSync?.call();
        return result;
      }
      if (func is JSFunction) {
        throw JSTypeError(
          'Unsupported legacy JSFunction in bytecode VM: ${func.declaration.runtimeType}',
        );
      }
      _traceNotAFunctionError(func, thisValue, args);
      throw JSTypeError('${_jsToString(func)} is not a function');
    } on JSException catch (e) {
      throw _ThrowSignal(e.value);
    } on JSError catch (e) {
      final errorValue = _makeError(e.name, e.message);
      if (func is JSNativeFunction &&
          (func.functionName == 'BigInt' ||
              (func.functionName == 'Number' && e is JSTypeError) ||
              (func.functionName == 'setTimeout' && e is JSTypeError)) &&
          errorValue is JSObject) {
        errorValue.setInternalSlot('ExposeAsDartError', true);
      }
      throw _ThrowSignal(errorValue);
    }
  }

  JSValue _callDirectEval(JSValue func, List<JSValue> args) {
    if (_isDirectEvalTarget(func)) {
      final code = args.isNotEmpty ? args[0].toString() : '';
      try {
        return evalCode(code, directEval: true);
      } on JSException catch (e) {
        throw _ThrowSignal(e.value);
      } on JSError catch (e) {
        throw _ThrowSignal(_makeError(e.name, e.message));
      } catch (e) {
        throw _ThrowSignal(_makeSyntaxErrorFromParseFailure(e));
      }
    }
    return _callFunction(func, JSUndefined.instance, args);
  }

  bool _isDirectEvalTarget(JSValue func) {
    if (func is JSObject &&
        func.hasInternalSlot('[[GlobalEval]]') &&
        func.getInternalSlot('[[GlobalEval]]') == true) {
      return true;
    }

    final globalEval = globals['eval'];
    if (identical(func, globalEval)) {
      return true;
    }

    final globalThis = globals['globalThis'];
    if (globalThis is JSObject && globalThis.hasProperty('eval')) {
      return identical(func, globalThis.getProperty('eval'));
    }

    return false;
  }

  JSValue _callBytecodeFunction(
    _BytecodeFunction func,
    JSValue thisValue,
    List<JSValue> args, {
    JSValue? newTarget,
  }) {
    var currentFunc = func;
    var currentThis = thisValue;
    var currentArgs = args;
    var currentNewTarget = newTarget ?? JSUndefined.instance;

    // Trampoline loop: tail calls restart here instead of recursing.
    while (true) {
      final bc = currentFunc.bytecode;

      if (currentThis is JSObject && _instanceOf(currentThis, currentFunc)) {
        final fieldInit = _getProperty(currentFunc, '__fieldInit__');
        if (fieldInit is _BytecodeFunction) {
          _callBytecodeFunction(fieldInit, currentThis, const []);
        }
      }

      final JSValue effectiveThisValue;
      final JSValue effectiveNewTarget;
      if (bc.kind == FunctionKind.arrow || bc.kind == FunctionKind.asyncArrow) {
        effectiveThisValue = currentFunc.lexicalThis;
        effectiveNewTarget = currentFunc.lexicalNewTarget;
      } else if (bc.isStrict) {
        effectiveThisValue = currentThis;
        effectiveNewTarget = currentNewTarget;
      } else if (currentThis.isNull || currentThis.isUndefined) {
        effectiveThisValue = _getGlobalThis();
        effectiveNewTarget = currentNewTarget;
      } else if (currentThis is JSNumber ||
          (currentThis is! JSObject &&
              currentThis is! JSNativeFunction &&
              currentThis is! JSFunction &&
              currentThis.isNumber)) {
        effectiveThisValue = _callConstructor(
          globals['Number'] as JSNativeFunction,
          [currentThis],
        );
        effectiveNewTarget = currentNewTarget;
      } else if (currentThis is JSString ||
          (currentThis is! JSObject && currentThis.isString)) {
        effectiveThisValue = _callConstructor(
          globals['String'] as JSNativeFunction,
          [currentThis],
        );
        effectiveNewTarget = currentNewTarget;
      } else if (currentThis is JSBoolean) {
        effectiveThisValue = _callConstructor(
          globals['Boolean'] as JSNativeFunction,
          [currentThis],
        );
        effectiveNewTarget = currentNewTarget;
      } else {
        effectiveThisValue = currentThis;
        effectiveNewTarget = currentNewTarget;
      }

      final frame = StackFrame(
        func: bc,
        thisValue: effectiveThisValue,
        newTarget: effectiveNewTarget,
        calleeFunction: currentFunc,
        callerFrame: _currentFrame,
        passedArgs: List<JSValue>.of(currentArgs),
        evalBindings: Map<String, VarRef>.from(
          currentFunc.capturedEvalBindings,
        ),
        withObjects: List<JSObject>.of(currentFunc.capturedWithObjects),
      );

      // Track current callee for arguments.callee
      final savedCallee = _currentCalleeFunction;
      _currentCalleeFunction = currentFunc;

      if (bc.name.isNotEmpty) {
        for (var i = 0; i < bc.vars.length; i++) {
          if (bc.vars[i].name == bc.name) {
            frame.locals[i] = _VarRefWrapper(
              FunctionExprNameVarRef(bc.name, currentFunc),
            );
            break;
          }
        }
      }

      if (bc.hasRest) {
        final normalCount = bc.argCount - 1;
        for (var i = 0; i < currentArgs.length && i < normalCount; i++) {
          frame.args[i] = currentArgs[i];
        }
        final restArr = _createArray();
        for (var i = normalCount; i < currentArgs.length; i++) {
          restArr.push(currentArgs[i]);
        }
        frame.args[normalCount] = restArr;
      } else {
        for (var i = 0; i < currentArgs.length && i < frame.args.length; i++) {
          frame.args[i] = currentArgs[i];
        }
      }

      for (
        var i = 0;
        i < currentFunc.closureVarRefs.length &&
            i < frame.closureVarRefs.length;
        i++
      ) {
        frame.closureVarRefs[i] = currentFunc.closureVarRefs[i];
      }

      // Generator functions: don't execute, return a JSGenerator
      if (bc.kind == FunctionKind.generator) {
        return _createBytecodeGenerator(frame);
      }

      // Async generator functions: return an async generator object whose
      // .next() calls drive the suspended frame.
      if (bc.kind == FunctionKind.asyncGenerator) {
        return _createBytecodeAsyncGenerator(frame);
      }

      // Async functions
      if (bc.kind == FunctionKind.asyncFunction ||
          bc.kind == FunctionKind.asyncArrow) {
        final promise = JSPromise.createInternal();
        _asyncFuncResume(frame, promise, null, false);
        return promise;
      }

      final result = _executeFrameForBytecodeCall(frame);
      if (result is _TailCall) {
        final target = result.func;
        if (target is _BytecodeFunction) {
          currentFunc = target;
          currentThis = result.thisVal ?? JSUndefined.instance;
          currentArgs = result.args;
          continue;
        }
        _currentCalleeFunction = savedCallee;
        return _callFunction(
          target,
          result.thisVal ?? JSUndefined.instance,
          result.args,
        );
      }
      _currentCalleeFunction = savedCallee;
      return result as JSValue;
    }
  }

  Object _executeFrameForBytecodeCall(StackFrame frame) {
    final savedFrame = _currentFrame;
    _currentFrame = frame;

    try {
      return _run(frame, captureTailCall: true);
    } on _ReturnSignal catch (sig) {
      return sig.value;
    } on _AwaitSuspend catch (suspend) {
      final outerPromise = JSPromise.createInternal();
      _handleAwaitSuspend(frame, outerPromise, suspend);
      _drainMicrotasks();
      _persistTopLevelLocals(frame);
      return outerPromise;
    } on _ThrowSignal catch (sig) {
      throw _JSException(sig.value);
    } finally {
      _currentFrame = savedFrame;
    }
  }

  /// Resume an async function from a suspended frame (or start it for the first time).
  ///
  /// - Executes the frame until completion or until `OP_await` suspends it.
  /// - On completion: resolves/rejects `promise` with the return value or error.
  /// - On suspension (_AwaitSuspend): wraps the awaited value in Promise.resolve(),
  ///   chains `.then(resume, reject)` so that when the inner promise settles,
  ///   execution resumes from where it left off.
  void _asyncFuncResume(
    StackFrame frame,
    JSPromise promise,
    JSValue? inputValue,
    bool isThrow,
  ) {
    // If resuming after an await, place the resolved value back on the stack
    // or handle a rejection.
    if (inputValue != null) {
      frame.isSuspended = false;
    }

    try {
      late JSValue result;
      if (isThrow && inputValue != null) {
        // The awaited promise was rejected — throw into the frame.
        try {
          result = _executeFrameWithThrow(frame, inputValue);
        } on _AwaitSuspend catch (suspend) {
          _handleAwaitSuspend(frame, promise, suspend);
          return;
        }
      } else {
        // Normal resume: push the resolved value onto the stack.
        if (inputValue != null) {
          frame.push(inputValue);
        }
        try {
          result = _executeFrame(frame);
        } on _AwaitSuspend catch (suspend) {
          _handleAwaitSuspend(frame, promise, suspend);
          return;
        }
      }

      // Async function completed normally — resolve the outer promise.
      if (result is JSPromise) {
        // If the async function returns a Promise, chain it to the outer promise.
        final thenFn = result.getProperty('then');
        if (thenFn is JSFunction) {
          _callFunctionInternal(thenFn, [
            JSNativeFunction(
              functionName: 'asyncResolve',
              nativeImpl: (args) {
                promise.resolve(
                  args.isNotEmpty ? args[0] : JSUndefined.instance,
                );
                return JSUndefined.instance;
              },
            ),
            JSNativeFunction(
              functionName: 'asyncReject',
              nativeImpl: (args) {
                promise.reject(
                  args.isNotEmpty ? args[0] : JSUndefined.instance,
                );
                return JSUndefined.instance;
              },
            ),
          ], result);
          _drainMicrotasks();
        } else {
          promise.resolve(result);
        }
      } else {
        promise.resolve(result);
      }
    } on _JSException catch (e) {
      // Async function threw — reject the outer promise.
      promise.reject(e.value);
    } catch (e) {
      // Unexpected error
      promise.reject(e is JSValue ? e : JSValueFactory.string(e.toString()));
    }
  }

  /// Handle an _AwaitSuspend by chaining .then on the pending promise
  /// so that execution resumes when it settles.
  void _handleAwaitSuspend(
    StackFrame frame,
    JSPromise outerPromise,
    _AwaitSuspend suspend,
  ) {
    final pendingPromise = suspend.promise;

    // Create resolve/reject callbacks that resume the async function.
    final resolveCallback = JSNativeFunction(
      functionName: 'asyncAwaitResume',
      nativeImpl: (args) {
        final resolvedValue = args.isNotEmpty ? args[0] : JSUndefined.instance;
        _asyncFuncResume(frame, outerPromise, resolvedValue, false);
        _drainMicrotasks();
        return JSUndefined.instance;
      },
    );

    final rejectCallback = JSNativeFunction(
      functionName: 'asyncAwaitReject',
      nativeImpl: (args) {
        final reason = args.isNotEmpty ? args[0] : JSUndefined.instance;
        _asyncFuncResume(frame, outerPromise, reason, true);
        _drainMicrotasks();
        return JSUndefined.instance;
      },
    );

    // Chain .then() on the pending promise.
    // Use PromisePrototype.then directly to avoid prototype lookup issues.
    PromisePrototype.then([resolveCallback, rejectCallback], pendingPromise);
    _drainMicrotasks();
  }

  /// Execute a frame that may have been resumed after an await suspension.
  /// If isThrow is true, throw the given error into the frame's exception handlers.
  JSValue _executeFrameWithThrow(StackFrame frame, JSValue error) {
    // Find an exception handler in the frame
    if (frame.exceptionHandlers.isNotEmpty) {
      final handler = frame.exceptionHandlers.removeLast();
      // Restore stack depth and jump to catch PC
      frame.sp = handler.stackDepth;
      frame.push(error);
      frame.pc = handler.catchPc;
      return _executeFrame(frame);
    }
    // No handler — propagate as _JSException
    throw _JSException(error);
  }

  /// Create a JSGenerator that wraps bytecode execution with suspend/resume.
  JSGenerator _createBytecodeGenerator(StackFrame frame) {
    // Track delegation state for yield*
    JSObject? delegatedIterator;
    JSValue? delegatedNextFn;

    late final Map<String, dynamic> Function(JSValue, GeneratorState) callback;
    callback = (JSValue inputValue, GeneratorState previousState) {
      // Handle active yield* delegation
      if (delegatedIterator != null) {
        final nextResult = _callFunction(
          delegatedNextFn!,
          delegatedIterator!,
          previousState == GeneratorState.suspendedStart ? [] : [inputValue],
        );
        if (nextResult is JSObject) {
          final done = nextResult.getProperty('done');
          if (done is JSBoolean && done.value) {
            // Delegation complete — push return value to frame and continue
            final retVal = nextResult.getProperty('value');
            delegatedIterator = null;
            delegatedNextFn = null;
            frame.push(retVal);
            // Fall through to resume execution
          } else {
            // Yield the delegated value
            return {'value': nextResult.getProperty('value'), 'done': false};
          }
        } else {
          delegatedIterator = null;
          delegatedNextFn = null;
          frame.push(JSUndefined.instance);
        }
      } else if (previousState == GeneratorState.suspendedYield) {
        // Resume from yield: push the value passed to .next(value)
        frame.push(inputValue);
      }

      // Execute until yield or return
      final savedFrame = _currentFrame;
      _currentFrame = frame;

      try {
        final result = _run(frame);
        // Normal completion (fell off end of function)
        return {'value': result, 'done': true};
      } on _ReturnSignal catch (sig) {
        return {'value': sig.value, 'done': true};
      } on _YieldSignal catch (sig) {
        if (sig.delegate) {
          // yield* — set up delegation
          final iterable = sig.value;
          JSObject? iterator;

          if (iterable is JSGenerator) {
            iterator = iterable;
          } else if (iterable is JSArray) {
            // Create an iterator from the array
            final values = <JSValue>[];
            for (var i = 0; i < iterable.length; i++) {
              values.add(iterable.getProperty(i.toString()));
            }
            iterator = _makeArrayIterator(values);
          } else if (iterable is JSString) {
            final chars = <JSValue>[];
            for (var i = 0; i < iterable.value.length; i++) {
              chars.add(JSString(iterable.value[i]));
            }
            iterator = _makeArrayIterator(chars);
          } else if (iterable is JSObject) {
            final symbolKey = JSSymbol.iterator.propertyKey;
            final iterFn = iterable.getProperty(symbolKey);
            if (iterFn is JSFunction) {
              final result = _callFunction(iterFn, iterable, []);
              if (result is JSObject) {
                iterator = result;
              }
            }
          }

          if (iterator == null) {
            throw _ThrowSignal(
              _makeError(
                'TypeError',
                '${_jsToString(iterable)} is not iterable',
              ),
            );
          }

          final nextFn = iterator.getProperty('next');
          if (nextFn is! JSFunction) {
            throw _ThrowSignal(
              _makeError('TypeError', 'iterator.next is not a function'),
            );
          }

          delegatedIterator = iterator;
          delegatedNextFn = nextFn;

          // Get the first value from the delegate
          final firstResult = _callFunction(nextFn, iterator, []);
          if (firstResult is JSObject) {
            final done = firstResult.getProperty('done');
            if (done is JSBoolean && done.value) {
              // Delegate is immediately done
              delegatedIterator = null;
              delegatedNextFn = null;
              frame.push(firstResult.getProperty('value'));
              // Re-enter execution to continue after yield*
              return callback(inputValue, GeneratorState.suspendedYield);
            }
            return {'value': firstResult.getProperty('value'), 'done': false};
          }
          return {'value': JSUndefined.instance, 'done': false};
        }
        // Normal yield
        return {'value': sig.value, 'done': false};
      } on _ThrowSignal catch (sig) {
        throw JSException(sig.value);
      } finally {
        _currentFrame = savedFrame;
      }
    };

    return JSGenerator(generatorFunction: callback);
  }

  /// Create a JSAsyncGenerator that wraps bytecode execution with
  /// suspend/resume semantics. The JSAsyncGenerator wrapper is responsible for
  /// returning Promises from .next(), .return(), and .throw().
  JSAsyncGenerator _createBytecodeAsyncGenerator(StackFrame frame) {
    // Reuse the same suspend/resume behavior as synchronous generators.
    JSObject? delegatedIterator;
    JSValue? delegatedNextFn;

    late final Map<String, dynamic> Function(JSValue, GeneratorState) callback;
    callback = (JSValue inputValue, GeneratorState previousState) {
      if (delegatedIterator != null) {
        final nextResult = _unwrapIteratorStep(
          _callFunction(
            delegatedNextFn!,
            delegatedIterator!,
            previousState == GeneratorState.suspendedStart ? [] : [inputValue],
          ),
          allowAsync: true,
        );
        if (nextResult is JSObject) {
          final done = nextResult.getProperty('done');
          if (done is JSBoolean && done.value) {
            final retVal = nextResult.getProperty('value');
            delegatedIterator = null;
            delegatedNextFn = null;
            frame.push(retVal);
          } else {
            return {'value': nextResult.getProperty('value'), 'done': false};
          }
        } else {
          delegatedIterator = null;
          delegatedNextFn = null;
          frame.push(JSUndefined.instance);
        }
      } else if (previousState == GeneratorState.suspendedYield) {
        frame.push(inputValue);
      }

      final savedFrame = _currentFrame;
      _currentFrame = frame;

      try {
        final result = _run(frame);
        return {'value': result, 'done': true};
      } on _ReturnSignal catch (sig) {
        return {'value': sig.value, 'done': true};
      } on _YieldSignal catch (sig) {
        if (sig.delegate) {
          final iterable = sig.value;
          JSObject? iterator;

          if (iterable is JSGenerator || iterable is JSAsyncGenerator) {
            iterator = iterable as JSObject;
          } else if (iterable is JSArray) {
            final values = <JSValue>[];
            for (var i = 0; i < iterable.length; i++) {
              values.add(iterable.getProperty(i.toString()));
            }
            iterator = _makeArrayIterator(values);
          } else if (iterable is JSString) {
            final chars = <JSValue>[];
            for (var i = 0; i < iterable.value.length; i++) {
              chars.add(JSString(iterable.value[i]));
            }
            iterator = _makeArrayIterator(chars);
          } else if (iterable is JSObject) {
            iterator = _getIteratorObject(iterable, allowAsync: true);
          }

          if (iterator == null) {
            throw _ThrowSignal(
              _makeError(
                'TypeError',
                '${_jsToString(iterable)} is not iterable',
              ),
            );
          }

          final nextFn = iterator.getProperty('next');
          if (nextFn is! JSFunction) {
            throw _ThrowSignal(
              _makeError('TypeError', 'iterator.next is not a function'),
            );
          }

          delegatedIterator = iterator;
          delegatedNextFn = nextFn;

          final firstResult = _unwrapIteratorStep(
            _callFunction(nextFn, iterator, []),
            allowAsync: true,
          );
          if (firstResult is JSObject) {
            final done = firstResult.getProperty('done');
            if (done is JSBoolean && done.value) {
              delegatedIterator = null;
              delegatedNextFn = null;
              frame.push(firstResult.getProperty('value'));
              return callback(inputValue, GeneratorState.suspendedYield);
            }
            return {'value': firstResult.getProperty('value'), 'done': false};
          }
          return {'value': JSUndefined.instance, 'done': false};
        }
        return {'value': sig.value, 'done': false};
      } on _ThrowSignal catch (sig) {
        throw JSException(sig.value);
      } finally {
        _currentFrame = savedFrame;
      }
    };

    return JSAsyncGenerator(generatorFunction: callback);
  }

  /// Helper to make a simple array iterator object
  JSObject _makeArrayIterator(List<JSValue> values) {
    var index = 0;
    final iterator = JSObject();
    iterator.setProperty(
      'next',
      JSNativeFunction(
        functionName: 'next',
        nativeImpl: (args) {
          if (index < values.length) {
            final result = JSObject();
            result.setProperty('value', values[index++]);
            result.setProperty('done', JSBoolean(false));
            return result;
          }
          final result = JSObject();
          result.setProperty('value', JSUndefined.instance);
          result.setProperty('done', JSBoolean(true));
          return result;
        },
      ),
    );
    return iterator;
  }

  JSValue _getGlobalThis() {
    return globals['globalThis'] ?? JSObject();
  }

  JSObject _coerceWithObject(JSValue value) {
    if (value.isNull || value.isUndefined) {
      throw JSTypeError('Cannot convert undefined or null to object');
    }
    if (value is JSObject) {
      return value;
    }
    return value.toObject();
  }

  JSValue? _lookupWithBinding(String name) {
    final frame = _currentFrame;
    if (frame == null) {
      return null;
    }
    for (var i = frame.withObjects.length - 1; i >= 0; i--) {
      final obj = frame.withObjects[i];
      if (obj.hasProperty(name)) {
        return obj.getProperty(name);
      }
    }
    return null;
  }

  bool _hasWithBinding(String name) {
    final frame = _currentFrame;
    if (frame == null) {
      return false;
    }
    for (var i = frame.withObjects.length - 1; i >= 0; i--) {
      if (frame.withObjects[i].hasProperty(name)) {
        return true;
      }
    }
    return false;
  }

  bool _assignWithBinding(String name, JSValue value) {
    final frame = _currentFrame;
    if (frame == null) {
      return false;
    }
    for (var i = frame.withObjects.length - 1; i >= 0; i--) {
      final obj = frame.withObjects[i];
      if (obj.hasProperty(name)) {
        obj.setProperty(name, value);
        return true;
      }
    }
    return false;
  }

  JSValue? _lookupCurrentFrameBinding(String name) {
    final frame = _currentFrame;
    if (frame == null) {
      return null;
    }

    final ordinaryValue = _lookupOrdinaryBindingInFrame(frame, name);
    if (ordinaryValue != null) {
      return ordinaryValue;
    }

    final closureValue = _lookupClosureBindingInFrame(frame, name);
    if (closureValue != null) {
      return closureValue;
    }

    return null;
  }

  bool _assignCurrentFrameBinding(String name, JSValue value) {
    final frame = _currentFrame;
    if (frame == null) {
      return false;
    }

    if (_assignOrdinaryBindingInFrame(frame, name, value)) {
      return true;
    }

    if (_assignClosureBindingInFrame(frame, name, value)) {
      return true;
    }

    return false;
  }

  JSValue? _lookupNonWithBinding(String name) {
    final currentValue = _lookupCurrentFrameBinding(name);
    if (currentValue != null) {
      return currentValue;
    }

    final evalValue = _lookupEvalBinding(name);
    if (evalValue != null) {
      return evalValue;
    }

    if (_currentFrame?.isDirectEvalFrame == true) {
      final ordinaryValue = _lookupDirectEvalHostBinding(
        _currentFrame!.callerFrame,
        name,
      );
      if (ordinaryValue != null) {
        return ordinaryValue;
      }
    }

    final cachedValue = globals[name];
    if (_isPersistentLexicalGlobal(cachedValue)) {
      return (cachedValue as _VarRefWrapper).ref.value;
    }
    final globalThis = globals['globalThis'];
    if (cachedValue is _VarRefWrapper) {
      if (globalThis is JSObject) {
        final descriptor = globalThis.getOwnPropertyDescriptor(name);
        if (descriptor == null ||
            (!descriptor.isAccessor &&
                descriptor.writable &&
                descriptor.configurable)) {
          return cachedValue.ref.value;
        }
        if (globalThis.hasProperty(name)) {
          return globalThis.getProperty(name);
        }
      }
      return cachedValue.ref.value;
    }

    if (globalThis is JSObject && globalThis.hasProperty(name)) {
      return globalThis.getProperty(name);
    }

    if (cachedValue != null || globals.containsKey(name)) {
      return cachedValue ?? JSUndefined.instance;
    }

    return null;
  }

  void _assignNonWithBinding(String name, JSValue value) {
    if (_assignCurrentFrameBinding(name, value)) {
      return;
    }

    if (_assignEvalBinding(name, value)) {
      return;
    }

    if (_currentFrame?.isDirectEvalFrame == true &&
        _assignDirectEvalHostBinding(_currentFrame!.callerFrame, name, value)) {
      return;
    }

    _setGlobalBinding(name, value);
  }

  JSValue? _lookupGlobalBinding(String name) {
    final withValue = _lookupWithBinding(name);
    if (withValue != null) {
      return withValue;
    }

    final evalValue = _lookupEvalBinding(name);
    if (evalValue != null) {
      return evalValue;
    }

    if (_currentFrame?.isDirectEvalFrame == true) {
      final ordinaryValue = _lookupDirectEvalHostBinding(
        _currentFrame!.callerFrame,
        name,
      );
      if (ordinaryValue != null) {
        return ordinaryValue;
      }
    }

    final cachedValue = globals[name];
    if (_isPersistentLexicalGlobal(cachedValue)) {
      return (cachedValue as _VarRefWrapper).ref.value;
    }
    final globalThis = globals['globalThis'];
    if (cachedValue is _VarRefWrapper) {
      if (globalThis is JSObject) {
        final descriptor = globalThis.getOwnPropertyDescriptor(name);
        if (descriptor == null ||
            (!descriptor.isAccessor &&
                descriptor.writable &&
                descriptor.configurable)) {
          return cachedValue.ref.value;
        }
        if (globalThis.hasProperty(name)) {
          return globalThis.getProperty(name);
        }
      }
      return cachedValue.ref.value;
    }

    if (globalThis is JSObject && globalThis.hasProperty(name)) {
      return globalThis.getProperty(name);
    }

    if (cachedValue != null || globals.containsKey(name)) {
      return cachedValue ?? JSUndefined.instance;
    }

    return null;
  }

  bool _hasGlobalBinding(String name) {
    if (_hasWithBinding(name)) {
      return true;
    }

    if (_lookupEvalBinding(name) != null) {
      return true;
    }

    if (_currentFrame?.isDirectEvalFrame == true) {
      if (_lookupDirectEvalHostBinding(_currentFrame!.callerFrame, name) !=
          null) {
        return true;
      }
    }

    if (_isPersistentLexicalGlobal(globals[name])) {
      return true;
    }

    final globalThis = globals['globalThis'];
    if (globalThis is JSObject && globalThis.hasProperty(name)) {
      return true;
    }

    if (globals.containsKey(name)) {
      return true;
    }

    return false;
  }

  String? _findVisibleSuperBindingName(StackFrame? frame) {
    StackFrame? current = frame;
    while (current != null) {
      for (final variable in current.func.vars) {
        if (variable.name.startsWith('__super_')) {
          return variable.name;
        }
      }
      for (final closureVar in current.func.closureVars) {
        if (closureVar.name.startsWith('__super_')) {
          return closureVar.name;
        }
      }
      for (final name in current.evalBindings.keys) {
        if (name.startsWith('__super_')) {
          return name;
        }
      }
      current = current.callerFrame;
    }
    return null;
  }

  void _setGlobalBinding(String name, JSValue value) {
    if (_assignWithBinding(name, value)) {
      return;
    }

    if (_assignEvalBinding(name, value)) {
      return;
    }

    if (_currentFrame?.isDirectEvalFrame == true) {
      if (_assignDirectEvalHostBinding(
        _currentFrame!.callerFrame,
        name,
        value,
      )) {
        return;
      }
    }

    final existing = globals[name];
    if (existing is _VarRefWrapper) {
      existing.ref.value = value;
      return;
    }

    final globalThis = globals['globalThis'];
    if (globalThis is JSObject) {
      globalThis.setProperty(name, value);
      _syncGlobalCacheFromObject(name, globalThis);
    } else {
      _syncGlobalCacheValue(name, value);
    }
  }

  JSValue? _lookupEvalBinding(String name) {
    StackFrame? frame = _currentFrame;
    while (frame != null) {
      final binding = frame.evalBindings[name];
      if (binding != null) {
        return binding.value;
      }
      frame = frame.callerFrame;
    }
    return null;
  }

  bool _assignEvalBinding(String name, JSValue value) {
    StackFrame? frame = _currentFrame;
    while (frame != null) {
      final binding = frame.evalBindings[name];
      if (binding != null) {
        binding.value = value;
        return true;
      }
      frame = frame.callerFrame;
    }
    return false;
  }

  Map<String, VarRef> _collectVisibleEvalBindings(StackFrame frame) {
    final bindings = <String, VarRef>{};
    StackFrame? current = frame;
    while (current != null) {
      current.evalBindings.forEach((name, ref) {
        bindings.putIfAbsent(name, () => ref);
      });
      current = current.callerFrame;
    }
    return bindings;
  }

  Map<String, VarRef> _collectDirectEvalHostBindings(StackFrame frame) {
    final bindings = _collectVisibleEvalBindings(frame);
    final localLimit = _directEvalHostLocalLimit(frame);

    for (var i = localLimit - 1; i >= 0; i--) {
      final variable = frame.func.vars[i];
      if (variable.isLexical &&
          identical(frame.locals[i], JSTemporalDeadZone.instance)) {
        continue;
      }
      bindings.putIfAbsent(
        variable.name,
        () => _ensureLocalBindingRef(frame, i),
      );
    }

    for (var i = frame.func.closureVars.length - 1; i >= 0; i--) {
      final closureVar = frame.func.closureVars[i];
      if (identical(
        frame.closureVarRefs[i].value,
        JSTemporalDeadZone.instance,
      )) {
        continue;
      }
      bindings.putIfAbsent(closureVar.name, () => frame.closureVarRefs[i]);
    }

    return bindings;
  }

  Map<String, VarRef> _collectVisibleDirectEvalBindings(StackFrame frame) {
    final bindings = _collectVisibleEvalBindings(frame);
    StackFrame? current = frame;
    var isHostFrame = true;
    while (current != null) {
      final localLimit = isHostFrame
          ? _directEvalHostLocalLimit(current)
          : current.func.vars.length;

      for (var i = localLimit - 1; i >= 0; i--) {
        final variable = current.func.vars[i];
        if (variable.isLexical &&
            identical(current.locals[i], JSTemporalDeadZone.instance)) {
          continue;
        }
        bindings.putIfAbsent(
          variable.name,
          () => _ensureLocalBindingRef(current!, i),
        );
      }

      for (var i = current.func.closureVars.length - 1; i >= 0; i--) {
        final closureVar = current.func.closureVars[i];
        if (identical(
          current.closureVarRefs[i].value,
          JSTemporalDeadZone.instance,
        )) {
          continue;
        }
        bindings.putIfAbsent(closureVar.name, () => current!.closureVarRefs[i]);
      }

      current = current.callerFrame;
      isHostFrame = false;
    }

    return bindings;
  }

  Map<String, VarRef> _snapshotEvalBindings(Map<String, VarRef> bindings) {
    final snapshot = <String, VarRef>{};
    bindings.forEach((name, ref) {
      JSValue currentValue;
      try {
        currentValue = ref.value;
      } on JSReferenceError {
        currentValue = JSTemporalDeadZone.instance;
      }

      if (ref is LocalBindingVarRef) {
        snapshot[name] = LocalBindingVarRef(
          name,
          isConst: ref.isConst,
          isLexical: ref.isLexical,
          value: currentValue,
        );
      } else if (ref is LexicalVarRef) {
        snapshot[name] = LocalBindingVarRef(
          name,
          isConst: false,
          isLexical: true,
          value: currentValue,
        );
      } else {
        snapshot[name] = VarRef(currentValue);
      }
    });
    return snapshot;
  }

  VarRef _ensureLocalBindingRef(StackFrame frame, int index) {
    final local = frame.locals[index];
    if (local is _VarRefWrapper) {
      return local.ref;
    }

    final variable = frame.func.vars[index];
    final ref = variable.isLexical || variable.isConst
        ? LocalBindingVarRef(
            variable.name,
            isConst: variable.isConst,
            isLexical: variable.isLexical,
            value: local,
          )
        : VarRef(local);
    frame.locals[index] = _VarRefWrapper(ref);
    return ref;
  }

  JSValue? _lookupOrdinaryBindingInFrame(StackFrame frame, String name) {
    return _lookupOrdinaryBindingInFrameWithLimit(
      frame,
      name,
      frame.func.vars.length,
    );
  }

  JSValue? _lookupOrdinaryBindingInFrameWithLimit(
    StackFrame frame,
    String name,
    int localLimit,
  ) {
    final cappedLocalLimit = localLimit.clamp(0, frame.func.vars.length);
    JSReferenceError? pendingTdzError;
    for (var i = cappedLocalLimit - 1; i >= 0; i--) {
      if (frame.func.vars[i].name != name) {
        continue;
      }
      try {
        return _readLocal(frame, i);
      } on JSReferenceError catch (error) {
        pendingTdzError ??= error;
      }
    }
    for (var i = 0; i < frame.func.argNames.length; i++) {
      if (frame.func.argNames[i] == name) {
        return frame.args[i];
      }
    }
    if (pendingTdzError != null) {
      throw pendingTdzError;
    }
    return null;
  }

  bool _assignOrdinaryBindingInFrame(
    StackFrame frame,
    String name,
    JSValue value,
  ) {
    return _assignOrdinaryBindingInFrameWithLimit(
      frame,
      name,
      value,
      frame.func.vars.length,
    );
  }

  bool _assignOrdinaryBindingInFrameWithLimit(
    StackFrame frame,
    String name,
    JSValue value,
    int localLimit,
  ) {
    final cappedLocalLimit = localLimit.clamp(0, frame.func.vars.length);
    for (var i = cappedLocalLimit - 1; i >= 0; i--) {
      if (frame.func.vars[i].name != name) {
        continue;
      }
      _writeLocal(frame, i, value);
      return true;
    }

    for (var i = 0; i < frame.func.argNames.length; i++) {
      if (frame.func.argNames[i] == name) {
        frame.args[i] = value;
        return true;
      }
    }
    return false;
  }

  JSValue? _lookupDirectEvalHostBinding(StackFrame? frame, String name) {
    if (frame == null) {
      return null;
    }

    final localLimit = _directEvalHostLocalLimit(frame);

    final hostValue = _lookupOrdinaryBindingInFrameWithLimit(
      frame,
      name,
      localLimit,
    );
    if (hostValue != null) {
      return hostValue;
    }

    final hostClosureValue = _lookupClosureBindingInFrame(frame, name);
    if (hostClosureValue != null) {
      return hostClosureValue;
    }

    StackFrame? current = frame.callerFrame;
    while (current != null) {
      final evalBinding = current.evalBindings[name];
      if (evalBinding != null) {
        return evalBinding.value;
      }

      final ordinaryValue = _lookupOrdinaryBindingInFrame(current, name);
      if (ordinaryValue != null) {
        return ordinaryValue;
      }
      current = current.callerFrame;
    }

    return null;
  }

  bool _assignDirectEvalHostBinding(
    StackFrame? frame,
    String name,
    JSValue value,
  ) {
    if (frame == null) {
      return false;
    }

    final localLimit = _directEvalHostLocalLimit(frame);

    if (_assignOrdinaryBindingInFrameWithLimit(
      frame,
      name,
      value,
      localLimit,
    )) {
      return true;
    }

    if (_assignClosureBindingInFrame(frame, name, value)) {
      return true;
    }

    StackFrame? current = frame.callerFrame;
    while (current != null) {
      final evalBinding = current.evalBindings[name];
      if (evalBinding != null) {
        evalBinding.value = value;
        return true;
      }

      if (_assignOrdinaryBindingInFrame(current, name, value)) {
        return true;
      }

      current = current.callerFrame;
    }

    return false;
  }

  int? _findClosureBindingIndexInFrame(StackFrame frame, String name) {
    for (var i = 0; i < frame.func.closureVars.length; i++) {
      if (frame.func.closureVars[i].name == name) {
        return i;
      }
    }
    return null;
  }

  JSValue? _lookupClosureBindingInFrame(StackFrame frame, String name) {
    final index = _findClosureBindingIndexInFrame(frame, name);
    if (index == null) {
      return null;
    }
    return frame.closureVarRefs[index].value;
  }

  bool _assignClosureBindingInFrame(
    StackFrame frame,
    String name,
    JSValue value,
  ) {
    final index = _findClosureBindingIndexInFrame(frame, name);
    if (index == null) {
      return false;
    }
    frame.closureVarRefs[index].value = value;
    return true;
  }

  int _directEvalHostLocalLimit(StackFrame frame) {
    if (_currentFrame?.isDirectEvalFrame == true &&
        identical(frame, _currentFrame!.directEvalHostFrame)) {
      return frame.func.vars.length;
    }
    if (identical(frame, _currentFrame)) {
      return frame.func.vars.length;
    }
    if (frame.pc >= frame.func.bodyStartPc) {
      return frame.func.vars.length;
    }
    return frame.func.parameterVarCount;
  }

  VarRef _ensureDirectEvalHostBinding(StackFrame host, String name) {
    final existing = host.evalBindings[name];
    if (existing != null) {
      return existing;
    }

    final closureIndex = _findClosureBindingIndexInFrame(host, name);
    if (closureIndex != null) {
      final binding = VarRef(JSUndefined.instance);
      host.closureVarRefs[closureIndex] = binding;
      host.evalBindings[name] = binding;
      return binding;
    }

    final binding = VarRef(JSUndefined.instance);
    host.evalBindings[name] = binding;
    return binding;
  }

  void _persistDirectEvalLocals(StackFrame frame) {
    if (frame.func.isStrict) {
      return;
    }

    final host = frame.directEvalHostFrame;
    if (host == null) {
      return;
    }

    for (var i = 0; i < frame.func.vars.length; i++) {
      final variable = frame.func.vars[i];
      if (variable.scope != VarScope.funcScope) {
        continue;
      }

      final value = _readLocal(frame, i);
      if (_assignOrdinaryBindingInFrameWithLimit(
        host,
        variable.name,
        value,
        host.func.parameterVarCount,
      )) {
        continue;
      }

      _ensureDirectEvalHostBinding(host, variable.name).value = value;
    }
  }

  /// Convert a JSArray (or any iterable) to a Dart list of JSValue
  List<JSValue> _jsArrayToList(JSValue val) {
    if (val is JSArray) {
      final list = <JSValue>[];
      for (var i = 0; i < val.length; i++) {
        list.add(val.getProperty(i.toString()));
      }
      return list;
    }
    return [];
  }

  _ForOfIterator _createForOfIterator(
    JSValue iterable, {
    bool allowAsync = false,
  }) {
    if (iterable is JSArray) {
      return _ForOfIterator(List<JSValue>.from(iterable.elements));
    }

    if (iterable is JSString) {
      final chars = <JSValue>[];
      for (var i = 0; i < iterable.value.length; i++) {
        chars.add(JSString(iterable.value[i]));
      }
      return _ForOfIterator(chars);
    }

    if (iterable is JSObject) {
      final iterator = _getIteratorObject(iterable, allowAsync: allowAsync);
      if (iterator != null) {
        final values = <JSValue>[];
        final nextFn = iterator.getProperty('next');
        if (nextFn is JSFunction) {
          while (true) {
            final result = _unwrapIteratorStep(
              _callFunction(nextFn, iterator, []),
              allowAsync: allowAsync,
            );
            if (result is! JSObject) {
              break;
            }
            final done = result.getProperty('done');
            if (done is JSBoolean && done.value) {
              break;
            }
            values.add(result.getProperty('value'));
          }
        }
        return _ForOfIterator(values);
      }
    }

    throw JSTypeError('${iterable.type.name} is not iterable');
  }

  JSObject? _getIteratorObject(JSObject iterable, {bool allowAsync = false}) {
    if (allowAsync) {
      final asyncIterFn = iterable.getProperty(
        JSSymbol.asyncIterator.propertyKey,
      );
      if (asyncIterFn is JSFunction) {
        final asyncIterator = _unwrapIteratorStep(
          _callFunction(asyncIterFn, iterable, []),
          allowAsync: true,
        );
        if (asyncIterator is JSObject) {
          return asyncIterator;
        }
      }
    }

    final iterFn = iterable.getProperty(JSSymbol.iterator.propertyKey);
    if (iterFn is JSFunction) {
      final iterator = _unwrapIteratorStep(
        _callFunction(iterFn, iterable, []),
        allowAsync: allowAsync,
      );
      if (iterator is JSObject) {
        return iterator;
      }
    }

    return null;
  }

  JSValue _unwrapIteratorStep(JSValue value, {required bool allowAsync}) {
    if (!allowAsync) {
      return value;
    }

    _drainMicrotasks();
    var current = value;
    while (current is JSPromise && current.state == PromiseState.fulfilled) {
      current = current.value ?? JSUndefined.instance;
    }
    if (current is JSPromise && current.state == PromiseState.rejected) {
      final reason =
          current.reason ?? JSValueFactory.string('Promise rejected');
      throw _JSException(reason);
    }
    return current;
  }

  // ================================================================
  // Main execution loop
  // ================================================================

  JSValue _executeFrame(StackFrame frame) {
    final savedFrame = _currentFrame;
    _currentFrame = frame;

    try {
      final result = _run(frame) as JSValue;
      return result;
    } on _ReturnSignal catch (sig) {
      return sig.value;
    } on _AwaitSuspend catch (suspend) {
      // Top-level await: wrap the frame in the async mechanism
      final outerPromise = JSPromise.createInternal();
      _handleAwaitSuspend(frame, outerPromise, suspend);
      _drainMicrotasks();
      // Persist locals to globals after initial execution
      _persistTopLevelLocals(frame);
      return outerPromise;
    } on _ThrowSignal catch (sig) {
      // Unhandled exception — propagate as Dart error
      throw _JSException(sig.value);
    } finally {
      _currentFrame = savedFrame;
    }
  }

  /// The core execution loop.
  Object _run(StackFrame frame, {bool captureTailCall = false}) {
    final bc = frame.func.bytecode;
    final cpool = frame.func.constantPool;

    // Cache frequently accessed fields for performance
    final stack = frame.stack;
    final args = frame.args;
    final closureVarRefs = frame.closureVarRefs;
    final exceptionHandlers = frame.exceptionHandlers;
    var sp = frame.sp;
    var pc = frame.pc;

    // Helper macros as closures
    void push(JSValue v) {
      stack[sp++] = v;
    }

    JSValue pop() {
      return stack[--sp];
    }

    JSValue peek() {
      return stack[sp - 1];
    }

    while (true) {
      try {
        while (true) {
          final opByte = bc[pc++];

          final op = Op.values[opByte];

          frame.pc = pc - 1;
          frame.sp = sp;

          if (traceExecution) {
            print(
              '[trace:vm] '
              'fn=${frame.func.name.isEmpty ? '<anonymous>' : frame.func.name} '
              'pc=${pc - 1} '
              'op=${opInfo[op]?.name ?? op.name} '
              'sp=$sp '
              'stack=${_describeStackTop(frame)} '
              'locals=${_describeLocals(frame)}',
            );
          }

          switch (op) {
            // ============================================================
            // Stack manipulation
            // ============================================================

            case Op.pushUndefined:
              push(JSUndefined.instance);

            case Op.pushNull:
              push(JSNull.instance);

            case Op.pushTrue:
              push(JSBoolean(true));

            case Op.pushFalse:
              push(JSBoolean(false));

            case Op.pushI32:
              final v = readI32(bc, pc);
              pc += 4;
              push(JSNumber(v.toDouble()));

            case Op.pushF64:
              final v = readF64(bc, pc);
              pc += 8;
              push(JSNumber(v));

            case Op.pushConst:
              final idx = readU16(bc, pc);
              pc += 2;
              final c = cpool[idx];
              if (c is String) {
                push(JSString(c));
              } else if (c is BigInt) {
                push(JSBigInt(c));
              } else if (c is double) {
                push(JSNumber(c));
              } else if (c is int) {
                push(JSNumber(c.toDouble()));
              } else {
                push(JSUndefined.instance);
              }

            case Op.pushEmptyString:
              push(JSString(''));

            case Op.push0:
              push(JSNumber(0));
            case Op.push1:
              push(JSNumber(1));
            case Op.push2:
              push(JSNumber(2));
            case Op.push3:
              push(JSNumber(3));
            case Op.push4:
              push(JSNumber(4));
            case Op.push5:
              push(JSNumber(5));
            case Op.push6:
              push(JSNumber(6));
            case Op.push7:
              push(JSNumber(7));

            case Op.dup:
              stack[sp] = stack[sp - 1];
              sp++;

            case Op.dup2:
              stack[sp] = stack[sp - 2];
              stack[sp + 1] = stack[sp - 1];
              sp += 2;

            case Op.drop:
              sp--;

            case Op.swap:
              final tmp = stack[sp - 1];
              stack[sp - 1] = stack[sp - 2];
              stack[sp - 2] = tmp;

            case Op.rot3l:
              // [a, b, c] -> [b, c, a]
              final a = stack[sp - 3];
              stack[sp - 3] = stack[sp - 2];
              stack[sp - 2] = stack[sp - 1];
              stack[sp - 1] = a;

            case Op.insert3:
              // [a, b, c] -> [c, a, b]
              final c = stack[sp - 1];
              stack[sp - 1] = stack[sp - 2];
              stack[sp - 2] = stack[sp - 3];
              stack[sp - 3] = c;

            case Op.insert4:
              // [a, b, c, d] -> [d, a, b, c]
              final d = stack[sp - 1];
              stack[sp - 1] = stack[sp - 2];
              stack[sp - 2] = stack[sp - 3];
              stack[sp - 3] = stack[sp - 4];
              stack[sp - 4] = d;

            case Op.nop:
              break;

            // ============================================================
            // Local variable access
            // ============================================================

            case Op.getLoc:
              final idx = readU16(bc, pc);
              pc += 2;
              push(_readLocal(frame, idx));

            case Op.putLoc:
              final idx = readU16(bc, pc);
              pc += 2;
              final putVal = pop();
              _writeLocal(frame, idx, putVal, initializing: true);

            case Op.setLoc:
              final idx = readU16(bc, pc);
              pc += 2;
              final setVal = stack[sp - 1]; // keep on stack
              _writeLocal(frame, idx, setVal);

            case Op.getLoc0:
              push(_readLocal(frame, 0));
            case Op.getLoc1:
              push(_readLocal(frame, 1));
            case Op.getLoc2:
              push(_readLocal(frame, 2));
            case Op.getLoc3:
              push(_readLocal(frame, 3));

            case Op.putLoc0:
              final pv0 = pop();
              _writeLocal(frame, 0, pv0, initializing: true);
            case Op.putLoc1:
              final pv1 = pop();
              _writeLocal(frame, 1, pv1, initializing: true);
            case Op.putLoc2:
              final pv2 = pop();
              _writeLocal(frame, 2, pv2, initializing: true);
            case Op.putLoc3:
              final pv3 = pop();
              _writeLocal(frame, 3, pv3, initializing: true);

            // ============================================================
            // Argument access
            // ============================================================

            case Op.getArg:
              final idx = readU16(bc, pc);
              pc += 2;
              push(args[idx]);

            case Op.putArg:
              final idx = readU16(bc, pc);
              pc += 2;
              args[idx] = pop();

            case Op.setArg:
              final idx = readU16(bc, pc);
              pc += 2;
              args[idx] = stack[sp - 1];

            case Op.getArg0:
              push(args[0]);
            case Op.getArg1:
              push(args[1]);
            case Op.getArg2:
              push(args[2]);
            case Op.getArg3:
              push(args[3]);

            // ============================================================
            // Closure variable access
            // ============================================================

            case Op.getVarRef:
              final idx = readU16(bc, pc);
              pc += 2;
              push(closureVarRefs[idx].value);

            case Op.putVarRef:
              final idx = readU16(bc, pc);
              pc += 2;
              closureVarRefs[idx].value = pop();

            case Op.setVarRef:
              final idx = readU16(bc, pc);
              pc += 2;
              closureVarRefs[idx].value = stack[sp - 1];

            // ============================================================
            // Global variable access
            // ============================================================

            case Op.getVar:
              final atom = readU32(bc, pc);
              pc += 4;
              final name = cpool[atom] as String;
              final val = _lookupGlobalBinding(name);
              if (val == null) {
                throw _ThrowSignal(
                  _makeError('ReferenceError', '$name is not defined'),
                );
              }
              push(val);

            case Op.putVar:
              final atom = readU32(bc, pc);
              pc += 4;
              final name = cpool[atom] as String;
              final newVal = pop();
              _setGlobalBinding(name, newVal);

            case Op.checkVar:
              final atom = readU32(bc, pc);
              pc += 4;
              final name = cpool[atom] as String;
              push(JSBoolean(_hasGlobalBinding(name)));

            case Op.checkVarStrict:
              final atom = readU32(bc, pc);
              pc += 4;
              final name = cpool[atom] as String;
              if (!_hasGlobalBinding(name)) {
                throw _ThrowSignal(
                  _makeError('ReferenceError', '$name is not defined'),
                );
              }

            case Op.defineVar:
              final atom = readU32(bc, pc);
              pc += 4;
              final _ = bc[pc++]; // flags (ignored for now)
              final name = cpool[atom] as String;
              if (_currentFrame?.isDirectEvalFrame == true &&
                  !_currentFrame!.func.isStrict) {
                final host = _currentFrame!.directEvalHostFrame;
                if (host != null &&
                    _lookupOrdinaryBindingInFrameWithLimit(
                          host,
                          name,
                          host.func.parameterVarCount,
                        ) ==
                        null) {
                  _ensureDirectEvalHostBinding(host, name);
                }
              } else if (!globals.containsKey(name)) {
                globals[name] = JSUndefined.instance;
              }

            // ============================================================
            // Property access
            // ============================================================

            case Op.getField:
              final atom = readU32(bc, pc);
              pc += 4;
              final name = cpool[atom] as String;
              final obj = pop();
              push(_getProperty(obj, name));

            case Op.putField:
              final atom = readU32(bc, pc);
              pc += 4;
              final name = cpool[atom] as String;
              final val = pop();
              final obj = pop();
              _setProperty(obj, name, val);

            case Op.getElem:
              final key = pop();
              final obj = pop();
              if (key is JSSymbol) {
                push(
                  obj is JSObject || obj is JSFunction
                      ? _getProperty(obj, key.propertyKey)
                      : JSUndefined.instance,
                );
              } else {
                final keyStr = _jsToString(key);
                push(_getProperty(obj, keyStr));
              }

            case Op.putElem:
              final val = pop();
              final key = pop();
              final obj = pop();
              if (key is JSSymbol) {
                if (obj is JSObject) {
                  obj.setPropertyWithSymbol(key.propertyKey, val, key);
                } else if (obj is JSFunction) {
                  obj.setProperty(key.propertyKey, val);
                  obj.registerSymbolKey(key.propertyKey, key);
                }
              } else {
                final keyStr = _jsToString(key);
                _setProperty(obj, keyStr, val);
              }

            case Op.deleteField:
              final atom = readU32(bc, pc);
              pc += 4;
              final name = cpool[atom] as String;
              final obj = pop();
              if (obj.isNull || obj.isUndefined) {
                throw _ThrowSignal(
                  _makeError(
                    'TypeError',
                    "Cannot convert ${obj.isNull ? 'null' : 'undefined'} to object",
                  ),
                );
              } else if (obj is JSObject) {
                final deleted = obj.deleteProperty(name);
                if (deleted && identical(obj, globals['globalThis'])) {
                  globals.remove(name);
                }
                if (!deleted && frame.func.isStrict) {
                  throw _ThrowSignal(
                    _makeError(
                      'TypeError',
                      'Cannot delete property $name of object',
                    ),
                  );
                }
                push(JSBoolean(deleted));
              } else if (obj is JSFunction) {
                final deleted = obj.deleteProperty(name);
                if (!deleted && frame.func.isStrict) {
                  throw _ThrowSignal(
                    _makeError(
                      'TypeError',
                      'Cannot delete property $name of object',
                    ),
                  );
                }
                push(JSBoolean(deleted));
              } else {
                push(JSBoolean(true));
              }

            case Op.deleteElem:
              final key = pop();
              final obj = pop();
              if (obj.isNull || obj.isUndefined) {
                throw _ThrowSignal(
                  _makeError(
                    'TypeError',
                    "Cannot convert ${obj.isNull ? 'null' : 'undefined'} to object",
                  ),
                );
              } else if (obj is JSObject) {
                final keyStr = key is JSSymbol
                    ? key.propertyKey
                    : _jsToString(key);
                final deleted = obj.deleteProperty(keyStr);
                if (deleted && identical(obj, globals['globalThis'])) {
                  globals.remove(keyStr);
                }
                if (!deleted && frame.func.isStrict) {
                  throw _ThrowSignal(
                    _makeError(
                      'TypeError',
                      'Cannot delete property $keyStr of object',
                    ),
                  );
                }
                push(JSBoolean(deleted));
              } else if (obj is JSFunction) {
                final keyStr = key is JSSymbol
                    ? key.propertyKey
                    : _jsToString(key);
                final deleted = obj.deleteProperty(keyStr);
                if (!deleted && frame.func.isStrict) {
                  throw _ThrowSignal(
                    _makeError(
                      'TypeError',
                      'Cannot delete property $keyStr of object',
                    ),
                  );
                }
                push(JSBoolean(deleted));
              } else {
                push(JSBoolean(true));
              }

            case Op.inOp:
              final obj = pop();
              final key = pop();
              if (obj is! JSObject) {
                throw _ThrowSignal(
                  _makeError(
                    'TypeError',
                    'Cannot use "in" operator to search for "${_jsToString(key)}" in ${_jsToString(obj)}',
                  ),
                );
              }
              push(JSBoolean(obj.hasProperty(_jsToString(key))));

            case Op.instanceOf:
              final ctor = pop();
              final obj = pop();
              push(JSBoolean(_instanceOf(obj, ctor)));

            // ============================================================
            // Object/Array creation
            // ============================================================

            case Op.object:
              push(JSObject());

            case Op.array:
              push(_createArray());

            case Op.arrayAppend:
              final val = pop();
              final arr = stack[sp - 1];
              if (arr is JSArray) {
                arr.push(val);
              }

            case Op.arrayHole:
              final arr = stack[sp - 1];
              if (arr is JSArray) {
                final idx = arr.length;
                arr.push(JSUndefined.instance);
                arr.markHole(idx);
              }

            case Op.defineProp:
              final atom = readU32(bc, pc);
              pc += 4;
              final _ = bc[pc++]; // flags
              final name = cpool[atom] as String;
              final val = pop();
              final obj = stack[sp - 1]; // object stays on stack
              if (obj is JSObject) {
                obj.setProperty(name, val);
              }

            case Op.copyDataProperties:
              final source = pop();
              final target = stack[sp - 1];
              if (target is JSObject && source is JSObject) {
                for (final key in source.getPropertyNames()) {
                  target.setProperty(key, source.getProperty(key));
                }
              }

            case Op.setProto:
              final proto = pop();
              final obj = stack[sp - 1];
              if (obj is JSObject && proto is JSObject) {
                obj.setPrototype(proto);
              }

            // ============================================================
            // Arithmetic & bitwise operators
            // ============================================================

            case Op.add:
              final right = pop();
              final left = pop();
              push(_add(left, right));

            case Op.sub:
              final right = pop();
              final left = pop();
              push(_sub(left, right));

            case Op.mul:
              final right = pop();
              final left = pop();
              push(_mul(left, right));

            case Op.div:
              final right = pop();
              final left = pop();
              push(_div(left, right));

            case Op.mod:
              final right = pop();
              final left = pop();
              push(_mod(left, right));

            case Op.pow:
              final right = pop();
              final left = pop();
              push(_powValue(left, right));

            case Op.shl:
              final right = pop();
              final left = pop();
              push(_shl(left, right));

            case Op.sar:
              final right = pop();
              final left = pop();
              push(_sar(left, right));

            case Op.shr:
              final right = pop();
              final left = pop();
              push(
                JSNumber(
                  (_toUint32(left.toNumber()) >>
                          (_toUint32(right.toNumber()) & 0x1F))
                      .toDouble(),
                ),
              );

            case Op.bitAnd:
              final right = pop();
              final left = pop();
              push(_bitAnd(left, right));

            case Op.bitOr:
              final right = pop();
              final left = pop();
              push(_bitOr(left, right));

            case Op.bitXor:
              final right = pop();
              final left = pop();
              push(_bitXor(left, right));

            case Op.neg:
              final v = pop();
              push(_neg(v));

            case Op.plus:
              final v = pop();
              push(JSNumber(v.toNumber()));

            case Op.toNumeric:
              final v = pop();
              if (v.isBigInt) {
                push(v);
              } else {
                push(JSNumber(v.toNumber()));
              }

            case Op.bitNot:
              final v = pop();
              push(_bitNot(v));

            case Op.not:
              final v = pop();
              push(JSBoolean(!v.toBoolean()));

            case Op.typeOf:
              final v = pop();
              push(JSString(_typeOf(v)));

            case Op.voidOp:
              pop();
              push(JSUndefined.instance);

            case Op.inc:
              final v = pop();
              push(_inc(v));

            case Op.dec:
              final v = pop();
              push(_dec(v));

            // ============================================================
            // Comparison operators
            // ============================================================

            case Op.lt:
              final right = pop();
              final left = pop();
              final cmp = _compare(left, right);
              final result = JSBoolean(cmp != null && cmp < 0);
              if (traceExecution) {
                print(
                  '[trace:cmp] op=lt left=${_formatDebugValue(left)} '
                  'right=${_formatDebugValue(right)} cmp=$cmp '
                  'result=${_formatDebugValue(result)}',
                );
              }
              push(result);

            case Op.lte:
              final right = pop();
              final left = pop();
              final cmp = _compare(left, right);
              push(JSBoolean(cmp != null && cmp <= 0));

            case Op.gt:
              final right = pop();
              final left = pop();
              final cmp = _compare(left, right);
              push(JSBoolean(cmp != null && cmp > 0));

            case Op.gte:
              final right = pop();
              final left = pop();
              final cmp = _compare(left, right);
              push(JSBoolean(cmp != null && cmp >= 0));

            case Op.eq:
              final right = pop();
              final left = pop();
              push(JSBoolean(_abstractEquals(left, right)));

            case Op.neq:
              final right = pop();
              final left = pop();
              push(JSBoolean(!_abstractEquals(left, right)));

            case Op.strictEq:
              final right = pop();
              final left = pop();
              push(JSBoolean(left.strictEquals(right)));

            case Op.strictNeq:
              final right = pop();
              final left = pop();
              push(JSBoolean(!left.strictEquals(right)));

            case Op.isNullOrUndefined:
              final v = pop();
              push(JSBoolean(v.isNull || v.isUndefined));

            // ============================================================
            // Control flow
            // ============================================================

            case Op.ifFalse:
              final offset = readI16(bc, pc);
              pc += 2;
              final v = pop();
              if (traceExecution) {
                print(
                  '[trace:branch] op=if_false cond=${_formatDebugValue(v)} '
                  'taken=${!v.toBoolean()} target=${pc - 3 + offset}',
                );
              }
              if (!v.toBoolean()) {
                pc = pc - 3 + offset; // relative to instruction start
              }

            case Op.ifTrue:
              final offset = readI16(bc, pc);
              pc += 2;
              final v = pop();
              if (v.toBoolean()) {
                pc = pc - 3 + offset;
              }

            case Op.goto_:
              pc = readI32(bc, pc);

            case Op.ifFalse8:
              final offset = bc[pc] >= 128 ? bc[pc] - 256 : bc[pc];
              pc++;
              final v = pop();
              if (!v.toBoolean()) {
                pc = pc - 2 + offset;
              }

            case Op.ifTrue8:
              final offset = bc[pc] >= 128 ? bc[pc] - 256 : bc[pc];
              pc++;
              final v = pop();
              if (v.toBoolean()) {
                pc = pc - 2 + offset;
              }

            case Op.goto8:
              final offset = bc[pc] >= 128 ? bc[pc] - 256 : bc[pc];
              pc++;
              pc = pc - 2 + offset;

            // ============================================================
            // Function calls
            // ============================================================

            case Op.call:
              final callPc = pc - 1;
              final argc = readU16(bc, pc);
              pc += 2;
              final callResumePc = pc;
              // Stack: [func, arg0, arg1, ..., argN]
              sp -= argc;
              final args = _StackArgsView(stack, sp, argc);
              final func = stack[--sp];
              frame.sp = sp;
              frame.pc = callPc;
              final result = _callFunction(func, JSUndefined.instance, args);
              sp = frame.sp;
              pc = callResumePc;
              frame.pc = callResumePc;
              push(result);

            case Op.callDirectEval:
              final directEvalPc = pc - 1;
              final directEvalArgc = readU16(bc, pc);
              pc += 2;
              final directEvalResumePc = pc;
              sp -= directEvalArgc;
              final directEvalArgs = _StackArgsView(stack, sp, directEvalArgc);
              final directEvalFunc = stack[--sp];
              frame.sp = sp;
              frame.pc = directEvalPc;
              final directEvalResult = _callDirectEval(
                directEvalFunc,
                directEvalArgs,
              );
              sp = frame.sp;
              pc = directEvalResumePc;
              frame.pc = directEvalResumePc;
              push(directEvalResult);

            case Op.callMethod:
              final callMethodPc = pc - 1;
              final argc = readU16(bc, pc);
              pc += 2;
              final callMethodResumePc = pc;
              // Stack: [obj, func, arg0, ..., argN]
              sp -= argc;
              final args = _StackArgsView(stack, sp, argc);
              final func = stack[--sp];
              final obj = stack[--sp];
              frame.sp = sp;
              frame.pc = callMethodPc;
              final result = _callFunction(func, obj, args);
              sp = frame.sp;
              pc = callMethodResumePc;
              frame.pc = callMethodResumePc;
              push(result);

            case Op.callConstructor:
              final callConstructorPc = pc - 1;
              final argc = readU16(bc, pc);
              pc += 2;
              final callConstructorResumePc = pc;
              sp -= argc;
              final args = _StackArgsView(stack, sp, argc);
              final ctor = stack[--sp];
              frame.sp = sp;
              frame.pc = callConstructorPc;
              final result = _callConstructor(ctor, args);
              sp = frame.sp;
              pc = callConstructorResumePc;
              frame.pc = callConstructorResumePc;
              push(result);

            case Op.tailCall:
              final argc = readU16(bc, pc);
              pc += 2;
              sp -= argc;
              final tailArgs = _StackArgsView(stack, sp, argc);
              final tailFunc = stack[--sp];
              final tailCall = _TailCall(tailFunc, tailArgs);
              if (captureTailCall) {
                return tailCall;
              }
              throw tailCall;

            case Op.tailCallMethod:
              final argc = readU16(bc, pc);
              pc += 2;
              sp -= argc;
              final args = _StackArgsView(stack, sp, argc);
              final func = stack[--sp];
              final obj = stack[--sp];
              final tailCall = _TailCall(func, args, thisVal: obj);
              if (captureTailCall) {
                return tailCall;
              }
              throw tailCall;

            case Op.apply:
              // Stack: [func, argsArray] -> [result]
              final argsArr = pop();
              final func = pop();
              final args = _jsArrayToList(argsArr);
              frame.sp = sp;
              frame.pc = pc;
              final result = _callFunction(func, _getGlobalThis(), args);
              sp = frame.sp;
              pc = frame.pc;
              push(result);

            case Op.applyDirectEval:
              final directEvalArgsArr = pop();
              final directEvalFunc = pop();
              final directEvalArgs = _jsArrayToList(directEvalArgsArr);
              frame.sp = sp;
              frame.pc = pc;
              final directEvalResult = _callDirectEval(
                directEvalFunc,
                directEvalArgs,
              );
              sp = frame.sp;
              pc = frame.pc;
              push(directEvalResult);

            case Op.applyMethod:
              // Stack: [obj, func, argsArray] -> [result]
              final argsArr = pop();
              final func = pop();
              final obj = pop();
              final args = _jsArrayToList(argsArr);
              frame.sp = sp;
              frame.pc = pc;
              final result = _callFunction(func, obj, args);
              sp = frame.sp;
              pc = frame.pc;
              push(result);

            case Op.applyConstructor:
              // Stack: [constructor, argsArray] -> [instance]
              final argsArr = pop();
              final ctor = pop();
              final args = _jsArrayToList(argsArr);
              frame.sp = sp;
              frame.pc = pc;
              final result = _callConstructor(ctor, args);
              sp = frame.sp;
              pc = frame.pc;
              push(result);

            case Op.return_:
              final val = pop();
              throw _ReturnSignal(val);

            case Op.returnUndef:
              throw _ReturnSignal(JSUndefined.instance);

            // ============================================================
            // Closures
            // ============================================================

            case Op.fclosure:
              final funcIdx = readU16(bc, pc);
              pc += 2;
              final funcBytecode = cpool[funcIdx] as FunctionBytecode;

              // Create closure by capturing variable references
              final closureRefs = <VarRef>[];
              for (final cv in funcBytecode.closureVars) {
                switch (cv.kind) {
                  case ClosureVarKind.local:
                    closureRefs.add(_ensureLocalBindingRef(frame, cv.index));
                  case ClosureVarKind.arg:
                    closureRefs.add(VarRef(frame.args[cv.index]));
                  case ClosureVarKind.varRef:
                    closureRefs.add(frame.closureVarRefs[cv.index]);
                }
              }

              push(
                _BytecodeFunction(
                  funcBytecode,
                  closureRefs,
                  this,
                  lexicalThis: frame.thisValue,
                  lexicalNewTarget: frame.newTarget,
                  capturedEvalBindings: frame.isDirectEvalFrame
                      ? _snapshotEvalBindings(
                          _collectVisibleDirectEvalBindings(
                            frame.directEvalHostFrame!,
                          ),
                        )
                      : _collectVisibleEvalBindings(frame),
                  capturedWithObjects: List<JSObject>.of(frame.withObjects),
                ),
              );

            // ============================================================
            // Exception handling
            // ============================================================

            case Op.throw_:
              final val = pop();
              throw _ThrowSignal(val);

            case Op.throwError:
              final atom = readU32(bc, pc);
              pc += 4;
              final errorType = bc[pc++];
              final name = cpool[atom] as String;
              final errorName = switch (errorType) {
                0 => 'TypeError',
                1 => 'ReferenceError',
                2 => 'SyntaxError',
                3 => 'RangeError',
                _ => 'Error',
              };
              throw _ThrowSignal(_makeError(errorName, name));

            case Op.catch_:
              final catchPc = readI32(bc, pc);
              pc += 4;
              frame.exceptionHandlers.add(
                ExceptionHandler(catchPc: catchPc, stackDepth: sp),
              );

            case Op.uncatch:
              if (frame.exceptionHandlers.isNotEmpty) {
                frame.exceptionHandlers.removeLast();
              }

            case Op.gosub:
              // Legacy opcode path; current compiler inlines finally blocks.
              pc += 4; // skip offset for now

            case Op.ret:
              // Legacy opcode path paired with Op.gosub.
              break;

            // ============================================================
            // Async/Await (basic support)
            // ============================================================

            case Op.await_:
              // Synchronously unwrap already-resolved Promises.
              var awaited = pop();
              // Drain microtasks first — a preceding expression may have
              // resolved a promise whose settlement is still queued.
              _drainMicrotasks();
              // Unwrap nested fulfilled promises
              while (awaited is JSPromise &&
                  awaited.state == PromiseState.fulfilled) {
                awaited = awaited.value ?? JSUndefined.instance;
              }
              if (awaited is JSPromise &&
                  awaited.state == PromiseState.rejected) {
                final reason =
                    awaited.reason ?? JSValueFactory.string('Promise rejected');
                throw _JSException(reason);
              }
              // If a non-promise value (including unwrapped promise results),
              // push it back and continue synchronously.
              if (awaited is! JSPromise) {
                push(awaited);
                break;
              }
              // Promise is still pending — suspend execution.
              // Save current PC and SP so we can resume later.
              frame.pc = pc;
              frame.sp = sp;
              frame.isSuspended = true;
              throw _AwaitSuspend(awaited);

            case Op.returnAsync:
              final val = pop();
              // Wrap in resolved promise in the future
              throw _ReturnSignal(val);

            // ============================================================
            // Iteration
            // ============================================================

            case Op.forInStart:
              final obj = pop();
              if (obj is JSObject) {
                final keys = obj.getForInPropertyNames();
                push(_ForInIterator(keys, source: obj));
              } else {
                push(_ForInIterator([]));
              }

            case Op.forInNext:
              final iter = stack[sp - 1] as _ForInIterator;
              final nextKey = _nextForInKey(iter);
              if (nextKey != null) {
                push(JSString(nextKey));
                push(JSBoolean(false)); // not done
              } else {
                push(JSUndefined.instance);
                push(JSBoolean(true)); // done
              }

            case Op.forOfStart:
              final iterable = pop();
              push(_createForOfIterator(iterable));

            case Op.forOfNext:
              final iter = stack[sp - 1] as _ForOfIterator;
              if (iter.hasNext) {
                push(iter.next());
                push(JSBoolean(false));
              } else {
                push(JSUndefined.instance);
                push(JSBoolean(true));
              }

            case Op.iteratorClose:
              pop(); // discard iterator

            case Op.forAwaitOfStart:
              final iterable = pop();
              push(_createForOfIterator(iterable, allowAsync: true));

            case Op.forAwaitOfNext:
              final iter = stack[sp - 1] as _ForOfIterator;
              if (iter.hasNext) {
                push(iter.next());
                push(JSBoolean(false));
              } else {
                push(JSUndefined.instance);
                push(JSBoolean(true));
              }

            // ============================================================
            // Generators (stubs)
            // ============================================================

            case Op.initialYield:
              // No-op: generator initialization is handled by _createBytecodeGenerator
              break;

            case Op.yield_:
              final yieldVal = pop();
              frame.sp = sp;
              frame.pc = pc;
              throw _YieldSignal(yieldVal);

            case Op.yieldStar:
              final yieldStarVal = pop();
              frame.sp = sp;
              frame.pc = pc;
              throw _YieldSignal(yieldStarVal, delegate: true);

            case Op.asyncYieldStar:
              // Legacy opcode path; async generator delegation is handled by
              // the JSAsyncGenerator wrapper around Op.yieldStar.
              break;

            // ============================================================
            // Scope
            // ============================================================

            case Op.withGetVar:
              final atom = readU32(bc, pc);
              pc += 4;
              final name = cpool[atom] as String;
              final withValue = _lookupWithBinding(name);
              final resolved = withValue ?? _lookupNonWithBinding(name);
              if (resolved == null) {
                throw _ThrowSignal(
                  _makeError('ReferenceError', '$name is not defined'),
                );
              }
              push(resolved);

            case Op.withPutVar:
              final atom = readU32(bc, pc);
              pc += 4;
              final name = cpool[atom] as String;
              final newVal = pop();
              if (!_assignWithBinding(name, newVal)) {
                _assignNonWithBinding(name, newVal);
              }

            case Op.enterWith:
              final obj = pop();
              frame.withObjects.add(_coerceWithObject(obj));

            case Op.leaveWith:
              if (frame.withObjects.isNotEmpty) {
                frame.withObjects.removeLast();
              }

            case Op.enterScope:
              pc += 2;

            case Op.leaveScope:
              pc += 2;

            // ============================================================
            // Class (stubs)
            // ============================================================

            case Op.defineClass:
              pc += 4;
              push(JSObject()); // placeholder

            case Op.defineMethod:
              final atom = readU32(bc, pc);
              pc += 4;
              final func = pop();
              final obj = peek();
              final name = frame.func.constantPool[atom] as String;
              final desc = PropertyDescriptor(
                value: func,
                writable: true,
                enumerable: false,
                configurable: true,
              );
              if (obj is JSObject) {
                obj.defineProperty(name, desc);
              } else if (obj is JSFunction) {
                obj.defineProperty(name, desc);
              }

            case Op.defineGetter:
              final atom = readU32(bc, pc);
              pc += 4;
              final func = pop();
              final obj = peek();
              final name = frame.func.constantPool[atom] as String;
              if (func is JSFunction) {
                PropertyDescriptor? existing;
                if (obj is JSObject) {
                  existing = obj.getOwnPropertyDescriptor(name);
                } else if (obj is JSFunction) {
                  existing = obj.getOwnPropertyDescriptor(name);
                }
                final desc = PropertyDescriptor(
                  getter: func,
                  setter: existing?.setter,
                  enumerable: false,
                  configurable: true,
                );
                if (obj is JSObject) {
                  obj.defineProperty(name, desc);
                } else if (obj is JSFunction) {
                  obj.defineProperty(name, desc);
                }
              }

            case Op.defineGetterEnum:
              final enumGetterAtom = readU32(bc, pc);
              pc += 4;
              final enumGetterFunc = pop();
              final enumGetterObj = peek();
              final enumGetterName =
                  frame.func.constantPool[enumGetterAtom] as String;
              if (enumGetterFunc is JSFunction) {
                PropertyDescriptor? existingEnum;
                if (enumGetterObj is JSObject) {
                  existingEnum = enumGetterObj.getOwnPropertyDescriptor(
                    enumGetterName,
                  );
                } else if (enumGetterObj is JSFunction) {
                  existingEnum = enumGetterObj.getOwnPropertyDescriptor(
                    enumGetterName,
                  );
                }
                final desc = PropertyDescriptor(
                  getter: enumGetterFunc,
                  setter: existingEnum?.setter,
                  enumerable: true,
                  configurable: true,
                );
                if (enumGetterObj is JSObject) {
                  enumGetterObj.defineProperty(enumGetterName, desc);
                } else if (enumGetterObj is JSFunction) {
                  enumGetterObj.defineProperty(enumGetterName, desc);
                }
              }

            case Op.defineSetter:
              final atom = readU32(bc, pc);
              pc += 4;
              final func = pop();
              final obj = peek();
              final name = frame.func.constantPool[atom] as String;
              if (func is JSFunction) {
                PropertyDescriptor? existing;
                if (obj is JSObject) {
                  existing = obj.getOwnPropertyDescriptor(name);
                } else if (obj is JSFunction) {
                  existing = obj.getOwnPropertyDescriptor(name);
                }
                final desc = PropertyDescriptor(
                  getter: existing?.getter,
                  setter: func,
                  enumerable: false,
                  configurable: true,
                );
                if (obj is JSObject) {
                  obj.defineProperty(name, desc);
                } else if (obj is JSFunction) {
                  obj.defineProperty(name, desc);
                }
              }

            case Op.defineSetterEnum:
              final enumSetterAtom = readU32(bc, pc);
              pc += 4;
              final enumSetterFunc = pop();
              final enumSetterObj = peek();
              final enumSetterName =
                  frame.func.constantPool[enumSetterAtom] as String;
              if (enumSetterFunc is JSFunction) {
                PropertyDescriptor? existing;
                if (enumSetterObj is JSObject) {
                  existing = enumSetterObj.getOwnPropertyDescriptor(
                    enumSetterName,
                  );
                } else if (enumSetterObj is JSFunction) {
                  existing = enumSetterObj.getOwnPropertyDescriptor(
                    enumSetterName,
                  );
                }
                final desc = PropertyDescriptor(
                  getter: existing?.getter,
                  setter: enumSetterFunc,
                  enumerable: true,
                  configurable: true,
                );
                if (enumSetterObj is JSObject) {
                  enumSetterObj.defineProperty(enumSetterName, desc);
                } else if (enumSetterObj is JSFunction) {
                  enumSetterObj.defineProperty(enumSetterName, desc);
                }
              }

            case Op.defineGetterElem:
              final key = pop();
              final func = pop();
              final obj = peek();
              final name = key is JSSymbol ? key.propertyKey : _jsToString(key);
              if (obj is JSFunction && name == 'prototype') {
                throw JSTypeError(
                  "Classes may not have a static property named 'prototype'",
                );
              }
              if (func is JSFunction) {
                PropertyDescriptor? existing;
                if (obj is JSObject) {
                  existing = obj.getOwnPropertyDescriptor(name);
                } else if (obj is JSFunction) {
                  existing = obj.getOwnPropertyDescriptor(name);
                }
                final desc = PropertyDescriptor(
                  getter: func,
                  setter: existing?.setter,
                  enumerable: false,
                  configurable: true,
                );
                if (obj is JSObject) {
                  obj.defineProperty(name, desc);
                  if (key is JSSymbol) obj.registerSymbolKey(name, key);
                } else if (obj is JSFunction) {
                  obj.defineProperty(name, desc);
                  if (key is JSSymbol) obj.registerSymbolKey(name, key);
                }
              }

            case Op.defineSetterElem:
              final key = pop();
              final func = pop();
              final obj = peek();
              final name = key is JSSymbol ? key.propertyKey : _jsToString(key);
              if (obj is JSFunction && name == 'prototype') {
                throw JSTypeError(
                  "Classes may not have a static property named 'prototype'",
                );
              }
              if (func is JSFunction) {
                PropertyDescriptor? existing;
                if (obj is JSObject) {
                  existing = obj.getOwnPropertyDescriptor(name);
                } else if (obj is JSFunction) {
                  existing = obj.getOwnPropertyDescriptor(name);
                }
                final desc = PropertyDescriptor(
                  getter: existing?.getter,
                  setter: func,
                  enumerable: false,
                  configurable: true,
                );
                if (obj is JSObject) {
                  obj.defineProperty(name, desc);
                  if (key is JSSymbol) obj.registerSymbolKey(name, key);
                } else if (obj is JSFunction) {
                  obj.defineProperty(name, desc);
                  if (key is JSSymbol) obj.registerSymbolKey(name, key);
                }
              }

            case Op.defineMethodElem:
              final key = pop();
              final func = pop();
              final obj = peek();
              final name = key is JSSymbol ? key.propertyKey : _jsToString(key);
              // ES6 14.5.14: Static computed property named "prototype" throws TypeError
              if (obj is JSFunction && name == 'prototype') {
                throw JSTypeError(
                  "Classes may not have a static property named 'prototype'",
                );
              }
              final desc = PropertyDescriptor(
                value: func,
                writable: true,
                enumerable: false,
                configurable: true,
              );
              if (obj is JSObject) {
                obj.defineProperty(name, desc);
                if (key is JSSymbol) obj.registerSymbolKey(name, key);
              } else if (obj is JSFunction) {
                obj.defineProperty(name, desc);
                if (key is JSSymbol) obj.registerSymbolKey(name, key);
              }

            case Op.getSuperField:
              final key = pop();
              final target = pop();
              push(
                _getSuperProperty(target, _jsToString(key), frame.thisValue),
              );

            case Op.putSuperField:
              pop(); // value
              pop(); // key

            // ============================================================
            // Miscellaneous
            // ============================================================

            case Op.debugger_:
              break;

            case Op.import_:
              final specifier = pop();
              final moduleId = _jsToString(specifier);
              push(_dynamicImport(moduleId));

            case Op.regexp:
              final flags = pop();
              final pattern = pop();
              try {
                push(JSRegExp(_jsToString(pattern), _jsToString(flags)));
              } catch (e) {
                final message = e.toString().replaceFirst(
                  'FormatException: ',
                  '',
                );
                throw _ThrowSignal(_makeError('SyntaxError', message));
              }

            case Op.spread:
              // Pop iterable, peek array below, append all elements
              final iterable = pop();
              final arr = peek();
              if (arr is JSArray) {
                if (iterable is JSArray) {
                  for (var i = 0; i < iterable.length; i++) {
                    arr.push(iterable.getProperty(i.toString()));
                  }
                } else if (iterable is JSString) {
                  for (var i = 0; i < iterable.value.length; i++) {
                    arr.push(JSString(iterable.value[i]));
                  }
                } else if (iterable is JSObject) {
                  // Try Symbol.iterator protocol
                  final iterFn = iterable.getProperty(
                    JSSymbol.iterator.propertyKey,
                  );
                  if (iterFn is JSFunction) {
                    final iterator = _callFunction(iterFn, iterable, []);
                    if (iterator is JSObject) {
                      while (true) {
                        final nextFn = iterator.getProperty('next');
                        if (nextFn is! JSFunction) break;
                        final result = _callFunction(nextFn, iterator, []);
                        if (result is JSObject) {
                          final done = result.getProperty('done');
                          if (done is JSBoolean && done.value) break;
                          arr.push(result.getProperty('value'));
                        } else {
                          break;
                        }
                      }
                    }
                  } else {
                    throw JSTypeError(
                      '${_jsToString(iterable)} is not iterable',
                    );
                  }
                } else {
                  throw JSTypeError('${_jsToString(iterable)} is not iterable');
                }
              }
              break;

            case Op.templateLiteral:
              final count = readU16(bc, pc);
              pc += 2;
              // Pop count items and concatenate
              var result = '';
              final parts = List<JSValue>.filled(count, JSUndefined.instance);
              for (var i = 0; i < count; i++) {
                parts[count - 1 - i] = pop();
              }
              for (final p in parts) {
                result += _jsToString(p);
              }
              push(JSString(result));

            case Op.optionalChain:
              final offset = readI16(bc, pc);
              pc += 2;
              final val = peek();
              if (val.isNull || val.isUndefined) {
                sp--;
                push(JSUndefined.instance);
                pc = pc - 3 + offset;
              }

            case Op.nullishCoalesce:
              final offset = readI16(bc, pc);
              pc += 2;
              final val = peek();
              if (!val.isNull && !val.isUndefined) {
                pc = pc - 3 + offset;
              }

            case Op.typeOfVar:
              final atom = readU32(bc, pc);
              pc += 4;
              final name = cpool[atom] as String;
              final val = _lookupGlobalBinding(name);
              push(JSString(val == null ? 'undefined' : _typeOf(val)));

            case Op.deleteVar:
              final atom = readU32(bc, pc);
              pc += 4;
              final name = cpool[atom] as String;
              bool deleted;
              final globalThis = globals['globalThis'];
              if (globalThis is JSObject && globalThis.hasProperty(name)) {
                deleted = globalThis.deleteProperty(name);
                if (deleted) {
                  globals.remove(name);
                }
              } else {
                deleted = globals.containsKey(name);
                globals.remove(name);
              }
              push(JSBoolean(deleted));

            case Op.destructureArray:
            case Op.destructureObject:
            case Op.getIterator:
            case Op.iteratorNext:
              // Legacy destructuring opcodes not emitted by the current compiler.
              break;

            case Op.createArguments:
            case Op.createMappedArguments:
              final isMappedArguments = op == Op.createMappedArguments;
              final JSObject argsObj = isMappedArguments
                  ? _BytecodeMappedArguments(frame.passedArgs, frame.args)
                  : JSObject();
              if (!isMappedArguments) {
                for (var i = 0; i < frame.passedArgs.length; i++) {
                  argsObj.defineProperty(
                    i.toString(),
                    PropertyDescriptor(
                      value: frame.passedArgs[i],
                      writable: true,
                      enumerable: true,
                      configurable: true,
                    ),
                  );
                }
              }
              argsObj.defineProperty(
                'length',
                PropertyDescriptor(
                  value: JSNumber(frame.passedArgs.length.toDouble()),
                  writable: true,
                  enumerable: false,
                  configurable: true,
                ),
              );
              // Add callee property (non-strict mode only; strict creates poison pill)
              if (!frame.func.isStrict) {
                // Find the _BytecodeFunction that owns this frame
                for (final g in globals.values) {
                  if (g is _BytecodeFunction && g.bytecode == frame.func) {
                    argsObj.defineProperty(
                      'callee',
                      PropertyDescriptor(
                        value: g,
                        writable: true,
                        enumerable: false,
                        configurable: true,
                      ),
                    );
                    break;
                  }
                }
                // If not found as global, check locals of parent frames
                if (!argsObj.hasOwnProperty('callee')) {
                  // Set current function from the frame stack
                  argsObj.defineProperty(
                    'callee',
                    PropertyDescriptor(
                      value: _currentCalleeFunction ?? JSUndefined.instance,
                      writable: true,
                      enumerable: false,
                      configurable: true,
                    ),
                  );
                }
              } else {
                argsObj.markAsArgumentsObject();
                final throwTypeError = JSNativeFunction(
                  functionName: 'ThrowTypeError',
                  nativeImpl: (_) => throw JSTypeError(
                    'Access to arguments.callee is not allowed in strict mode',
                  ),
                );
                argsObj.defineProperty(
                  'callee',
                  PropertyDescriptor(
                    getter: throwTypeError,
                    setter: throwTypeError,
                    enumerable: false,
                    configurable: false,
                  ),
                );
                argsObj.defineProperty(
                  'caller',
                  PropertyDescriptor(
                    getter: throwTypeError,
                    setter: throwTypeError,
                    enumerable: false,
                    configurable: false,
                  ),
                );
              }
              // Add Symbol.iterator for iterability
              final arrayProto = globals['Array'];
              if (arrayProto is JSNativeFunction) {
                final proto = arrayProto.getProperty('prototype');
                if (proto is JSObject) {
                  final iterSym = JSSymbol.iterator.propertyKey;
                  final iterFn = proto.getProperty(iterSym);
                  if (!iterFn.isUndefined) {
                    argsObj.defineProperty(
                      iterSym,
                      PropertyDescriptor(
                        value: iterFn,
                        writable: true,
                        enumerable: false,
                        configurable: true,
                      ),
                    );
                    argsObj.registerSymbolKey(iterSym, JSSymbol.iterator);
                  }
                }
              }
              push(argsObj);
              break;

            case Op.getThis:
              push(frame.thisValue);

            case Op.getNewTarget:
              push(frame.newTarget);

            case Op.objectRest:
              // Object rest destructuring
              // Stack: [obj, key0, key1, ..., keyN-1]
              final keyCount = readU16(bc, pc);
              pc += 2;
              // Pop excluded keys
              final excludedKeys = <String>{};
              for (var i = 0; i < keyCount; i++) {
                excludedKeys.add(_jsToString(pop()));
              }
              // Pop source object
              final srcObj = pop();
              // Create rest object with remaining properties
              final restObj = JSObject();
              if (srcObj is JSObject) {
                for (final key in srcObj.getPropertyNames()) {
                  if (!excludedKeys.contains(key)) {
                    restObj.setProperty(key, srcObj.getProperty(key));
                  }
                }
              }
              push(restObj);
          }
        }
      } on _ThrowSignal catch (sig) {
        if (exceptionHandlers.isNotEmpty) {
          final handler = exceptionHandlers.removeLast();
          sp = handler.stackDepth;
          pc = handler.catchPc;
          push(sig.value);
          continue; // re-enter outer loop
        }
        rethrow;
      } on _JSException catch (e) {
        if (exceptionHandlers.isNotEmpty) {
          final handler = exceptionHandlers.removeLast();
          sp = handler.stackDepth;
          pc = handler.catchPc;
          push(e.value);
          continue;
        }
        rethrow;
      }
    }
  }

  // ================================================================
  // Helper methods
  // ================================================================

  JSValue _add(JSValue left, JSValue right) {
    if (left is JSNumber && right is JSNumber) {
      return JSNumber(left.value + right.value);
    }
    // String concatenation if either side is a string
    if (left.isString || right.isString) {
      return JSString(_jsToString(left) + _jsToString(right));
    }
    if (left.isBigInt || right.isBigInt) {
      final l = _requireBigInt(left);
      final r = _requireBigInt(right);
      return JSBigInt(l + r);
    }
    return JSNumber(left.toNumber() + right.toNumber());
  }

  JSValue _sub(JSValue left, JSValue right) {
    if (left is JSNumber && right is JSNumber) {
      return JSNumber(left.value - right.value);
    }
    if (left.isBigInt || right.isBigInt) {
      final l = _requireBigInt(left);
      final r = _requireBigInt(right);
      return JSBigInt(l - r);
    }
    return JSNumber(left.toNumber() - right.toNumber());
  }

  JSValue _mul(JSValue left, JSValue right) {
    if (left is JSNumber && right is JSNumber) {
      return JSNumber(left.value * right.value);
    }
    if (left.isBigInt || right.isBigInt) {
      final l = _requireBigInt(left);
      final r = _requireBigInt(right);
      return JSBigInt(l * r);
    }
    return JSNumber(left.toNumber() * right.toNumber());
  }

  JSValue _div(JSValue left, JSValue right) {
    if (left is JSNumber && right is JSNumber) {
      return JSNumber(left.value / right.value);
    }
    if (left.isBigInt || right.isBigInt) {
      final l = _requireBigInt(left);
      final r = _requireBigInt(right);
      return JSBigInt(l ~/ r);
    }
    return JSNumber(left.toNumber() / right.toNumber());
  }

  JSValue _mod(JSValue left, JSValue right) {
    if (left is JSNumber && right is JSNumber) {
      return JSNumber(left.value % right.value);
    }
    if (left.isBigInt || right.isBigInt) {
      final l = _requireBigInt(left);
      final r = _requireBigInt(right);
      return JSBigInt(l.remainder(r));
    }
    return JSNumber(left.toNumber() % right.toNumber());
  }

  JSValue _powValue(JSValue left, JSValue right) {
    if (left.isBigInt || right.isBigInt) {
      final base = _requireBigInt(left);
      final exp = _requireBigInt(right);
      if (exp < BigInt.zero) {
        throw _ThrowSignal(
          _makeError('RangeError', 'Exponent must be positive'),
        );
      }
      return JSBigInt(base.pow(exp.toInt()));
    }
    return JSNumber(_pow(left.toNumber(), right.toNumber()));
  }

  JSValue _shl(JSValue left, JSValue right) {
    if (left.isBigInt || right.isBigInt) {
      final l = _requireBigInt(left);
      final r = _requireBigInt(right);
      return JSBigInt(l << r.toInt());
    }
    final result =
        _toInt32(left.toNumber()) << (_toUint32(right.toNumber()) & 0x1F);
    return JSNumber(result.toSigned(32).toDouble());
  }

  JSValue _sar(JSValue left, JSValue right) {
    if (left.isBigInt || right.isBigInt) {
      final l = _requireBigInt(left);
      final r = _requireBigInt(right);
      return JSBigInt(l >> r.toInt());
    }
    final result =
        _toInt32(left.toNumber()) >> (_toUint32(right.toNumber()) & 0x1F);
    return JSNumber(result.toSigned(32).toDouble());
  }

  JSValue _bitAnd(JSValue left, JSValue right) {
    if (left.isBigInt || right.isBigInt) {
      final l = _requireBigInt(left);
      final r = _requireBigInt(right);
      return JSBigInt(l & r);
    }
    return JSNumber(
      (_toInt32(left.toNumber()) & _toInt32(right.toNumber()))
          .toSigned(32)
          .toDouble(),
    );
  }

  JSValue _bitOr(JSValue left, JSValue right) {
    if (left.isBigInt || right.isBigInt) {
      final l = _requireBigInt(left);
      final r = _requireBigInt(right);
      return JSBigInt(l | r);
    }
    return JSNumber(
      (_toInt32(left.toNumber()) | _toInt32(right.toNumber()))
          .toSigned(32)
          .toDouble(),
    );
  }

  JSValue _bitXor(JSValue left, JSValue right) {
    if (left.isBigInt || right.isBigInt) {
      final l = _requireBigInt(left);
      final r = _requireBigInt(right);
      return JSBigInt(l ^ r);
    }
    return JSNumber(
      (_toInt32(left.toNumber()) ^ _toInt32(right.toNumber()))
          .toSigned(32)
          .toDouble(),
    );
  }

  JSValue _neg(JSValue value) {
    if (value is JSNumber) return JSNumber(-value.value);
    if (value.isBigInt) {
      return JSBigInt(-_requireBigInt(value));
    }
    return JSNumber(-value.toNumber());
  }

  JSValue _bitNot(JSValue value) {
    if (value.isBigInt) {
      return JSBigInt(~_requireBigInt(value));
    }
    return JSNumber((~_toInt32(value.toNumber())).toDouble());
  }

  JSValue _inc(JSValue value) {
    if (value is JSNumber) return JSNumber(value.value + 1);
    if (value.isBigInt) {
      return JSBigInt(_requireBigInt(value) + BigInt.one);
    }
    return JSNumber(value.toNumber() + 1);
  }

  JSValue _dec(JSValue value) {
    if (value is JSNumber) return JSNumber(value.value - 1);
    if (value.isBigInt) {
      return JSBigInt(_requireBigInt(value) - BigInt.one);
    }
    return JSNumber(value.toNumber() - 1);
  }

  String _typeOf(JSValue val) {
    if (val.isUndefined) return 'undefined';
    if (val.isNull) return 'object';
    if (val.isBoolean) return 'boolean';
    if (val.isNumber) return 'number';
    if (val.isString) return 'string';
    if (val.isSymbol) return 'symbol';
    if (val.isBigInt) return 'bigint';
    if (val is JSFunction ||
        val is JSNativeFunction ||
        val is _BytecodeFunction) {
      return 'function';
    }
    return 'object';
  }

  int? _compare(JSValue left, JSValue right) {
    if (left is JSNumber && right is JSNumber) {
      final l = left.value;
      final r = right.value;
      if (l < r) return -1;
      if (l > r) return 1;
      if (l == r) return 0;
      return null;
    }
    if (left.isString && right.isString) {
      return _jsToString(left).compareTo(_jsToString(right));
    }
    if (left.isBigInt && right.isBigInt) {
      final l = (left as JSBigInt).value;
      final r = (right as JSBigInt).value;
      return l.compareTo(r);
    }
    final l = left.toNumber();
    final r = right.toNumber();
    if (l.isNaN || r.isNaN) return null;
    if (l < r) return -1;
    if (l > r) return 1;
    return 0;
  }

  String? _nextForInKey(_ForInIterator iter) {
    while (iter.hasNext) {
      final key = iter.next();
      final source = iter.source;
      if (source is JSProxy) {
        final descriptor = source.getOwnPropertyDescriptor(key);
        if (descriptor == null || !descriptor.enumerable) {
          continue;
        }
      }
      return key;
    }
    return null;
  }

  BigInt _requireBigInt(JSValue value) {
    if (value is JSBigInt) {
      return value.value;
    }
    throw _ThrowSignal(
      _makeError(
        'TypeError',
        'Cannot mix BigInt and other types, use explicit conversions',
      ),
    );
  }

  JSValue _getProperty(JSValue obj, String name) {
    // null/undefined property access throws TypeError
    if (obj.isNull || obj.isUndefined) {
      throw _ThrowSignal(
        _makeError(
          'TypeError',
          "Cannot read properties of ${obj.isNull ? 'null' : 'undefined'} (reading '$name')",
        ),
      );
    }
    if (obj is JSArray) {
      return obj.getProperty(name);
    }
    if (obj is JSObject) {
      try {
        return obj.getProperty(name);
      } on JSException catch (e) {
        _appendOuterStackFrame(e.value);
        rethrow;
      }
    }
    // JSFunction / JSNativeFunction are NOT JSObject, handle separately
    if (obj is JSNativeFunction) {
      return obj.getProperty(name);
    }
    if (obj is JSFunction) {
      return obj.getProperty(name);
    }
    // Auto-boxing for strings
    if (obj is JSString || obj.isString) {
      final str = obj is JSString ? obj.value : obj.toString();
      final result = StringPrototype.getStringProperty(str, name);
      if (!result.isUndefined) return result;
      // Fall through to String.prototype for inherited properties
      final stringCtor = globals['String'];
      if (stringCtor is JSNativeFunction) {
        final proto = stringCtor.getProperty('prototype');
        if (proto is JSObject) {
          final val = proto.getProperty(name);
          if (!val.isUndefined) return val;
        }
      }
      return result;
    }
    // Auto-boxing for numbers
    if (obj is JSNumber || obj.isNumber) {
      final num_ = obj is JSNumber ? obj.value : obj.toNumber();
      final result = NumberPrototype.getNumberProperty(num_, name);
      if (!result.isUndefined) return result;
      final numberCtor = globals['Number'];
      if (numberCtor is JSNativeFunction) {
        final proto = numberCtor.getProperty('prototype');
        if (proto is JSObject) {
          final val = proto.getProperty(name);
          if (!val.isUndefined) return val;
        }
      }
      return result;
    }
    // Auto-boxing for booleans
    if (obj is JSBoolean) {
      final result = BooleanPrototype.getBooleanProperty(obj.value, name);
      if (result.isUndefined) {
        final boolCtor = globals['Boolean'];
        if (boolCtor is JSNativeFunction) {
          final proto = boolCtor.getProperty('prototype');
          if (proto is JSObject) {
            final val = proto.getProperty(name);
            if (!val.isUndefined) return val;
          }
        }
      }
      return result;
    }
    // Auto-boxing for BigInt
    if (obj is JSBigInt) {
      return BigIntPrototype.getBigIntProperty(obj.value, name);
    }
    // Auto-boxing for symbols
    if (obj is JSSymbol) {
      if (name == 'description') {
        return obj.description != null
            ? JSString(obj.description!)
            : JSUndefined.instance;
      }
      if (name == 'toString') {
        return JSNativeFunction(
          functionName: 'toString',
          expectedArgs: 0,
          nativeImpl: (args) => JSString(obj.toString()),
        );
      }
      // Try Symbol.prototype
      final proto = JSSymbolObject.symbolPrototype;
      if (proto != null) {
        return proto.getProperty(name);
      }
      return JSUndefined.instance;
    }
    return JSUndefined.instance;
  }

  void _setProperty(JSValue obj, String name, JSValue value) {
    try {
      if (obj is JSObject) {
        if (name == '__proto__') {
          obj.setPrototype(value is JSObject ? value : null);
          return;
        }
        obj.setProperty(name, value);
        if (identical(obj, globals['globalThis'])) {
          _syncGlobalCacheFromObject(name, obj);
        }
      } else if (obj is JSFunction) {
        obj.setProperty(name, value);
      }
      // Setting properties on primitives is silently ignored
    } on JSException catch (e) {
      _appendOuterStackFrame(e.value);
      throw _ThrowSignal(e.value);
    } on JSError catch (e) {
      throw _ThrowSignal(_makeError(e.name, e.message));
    }
  }

  JSValue? _getFunctionPrototypeChainValue(JSFunction function) {
    if (function.containsOwnProperty('__proto__')) {
      final explicitProto = function.getProperty('__proto__');
      if (explicitProto is JSObject || explicitProto is JSFunction) {
        return explicitProto;
      }
      if (explicitProto.isNull) {
        return null;
      }
    }
    return JSFunction.functionPrototype;
  }

  bool _instanceOf(JSValue obj, JSValue ctor) {
    if (ctor is! JSObject && ctor is! JSFunction) return false;
    // Check prototype chain against ctor.prototype
    final proto = _getProperty(ctor, 'prototype');
    if (proto is! JSObject) return false;

    JSValue? current;
    if (obj is JSObject) {
      current = obj.getPrototype();
    } else if (obj is JSFunction) {
      current = _getFunctionPrototypeChainValue(obj);
    } else {
      return false;
    }

    while (current != null) {
      if (identical(current, proto)) return true;
      if (current is JSObject) {
        current = current.getPrototype();
      } else if (current is JSFunction) {
        current = _getFunctionPrototypeChainValue(current);
      } else {
        break;
      }
    }
    return false;
  }

  JSValue _callConstructor(JSValue ctor, List<JSValue> args) {
    try {
      if (ctor is _BytecodeFunction) {
        if (!ctor.isConstructor) {
          throw JSTypeError('${ctor.functionName} is not a constructor');
        }
        final instance = JSObject();
        // Set prototype
        final proto = _getProperty(ctor, 'prototype');
        if (proto is JSObject) {
          instance.setPrototype(proto);
        }
        final result = _callBytecodeFunction(
          ctor,
          instance,
          args,
          newTarget: ctor,
        );
        // Constructors must preserve any object return value, including
        // callable objects such as functions.
        if (result is JSObject || result is JSFunction) return result;
        return instance;
      }
      if (ctor is JSBoundFunction) {
        final allArgs = [...ctor.boundArgs, ...args];
        return _callConstructor(ctor.originalFunction, allArgs);
      }
      if (ctor is JSNativeFunction) {
        if (ctor.isConstructor) {
          final result = JSNativeFunction.withConstructorCall(
            () => ctor.callWithThis(args, JSUndefined.instance),
          );
          // If the result is already an object, return it
          if (result is JSObject) return result;
          // For wrapper constructors (new Boolean/Number/String),
          // wrap the primitive result in a wrapper object
          switch (ctor.functionName) {
            case 'Boolean':
              return JSBooleanObject(result.toBoolean());
            case 'Number':
              return JSNumberObject(
                result is JSNumber ? result.value : result.toNumber(),
              );
            case 'String':
              return JSStringObject(_jsToString(result));
            default:
              return result;
          }
        }
        throw JSTypeError('${_jsToString(ctor)} is not a constructor');
      }
      if (ctor is DynamicFunction) {
        final instance = JSObject();
        final proto = ctor.getProperty('prototype');
        if (proto is JSObject) {
          instance.setPrototype(proto);
        }
        final result = ctor.execute(args, instance);
        if (result is JSObject || result is JSFunction) return result;
        return instance;
      }
      if (ctor is JSFunction) {
        final promoted = _tryPromoteLegacyFunction(ctor);
        if (promoted != null) {
          final instance = JSObject();
          final proto = promoted.getProperty('prototype');
          if (proto is JSObject) {
            instance.setPrototype(proto);
          }
          final result = _callBytecodeFunction(promoted, instance, args);
          if (result is JSObject || result is JSFunction) return result;
          return instance;
        }
      }
      if (ctor is JSFunction) {
        throw JSTypeError(
          'Unsupported legacy JSFunction constructor in bytecode VM: ${ctor.declaration.runtimeType}',
        );
      }
      throw JSTypeError('${_jsToString(ctor)} is not a constructor');
    } on JSException catch (e) {
      throw _ThrowSignal(e.value);
    } on JSError catch (e) {
      throw _ThrowSignal(_makeError(e.name, e.message));
    }
  }

  _BytecodeFunction? _tryPromoteLegacyFunction(JSFunction func) {
    final existing = func.getInternalSlot('[[BytecodeFunction]]');
    if (existing is _BytecodeFunction) {
      return existing;
    }

    if (!_hasPromotableLegacyDeclaration(func)) {
      return null;
    }

    final env = func.closureEnvironment;
    if (env is! Environment || !_hasGlobalRootEnvironment(env)) {
      return null;
    }

    try {
      final compiler = BytecodeCompiler();
      final outerBindings = _collectNonGlobalBindingNames(env);
      final bytecode = outerBindings.isEmpty
          ? compiler.compileJSFunction(func)
          : compiler.compileJSFunctionWithOuterBindings(func, outerBindings);

      final closureRefs = <VarRef>[];
      for (final closureVar in bytecode.closureVars) {
        final binding = _resolveLegacyCapturedBinding(env, closureVar.name);
        if (binding == null || !_canProjectLegacyCapturedBinding(binding)) {
          return null;
        }
        closureRefs.add(_projectLegacyCapturedBinding(binding));
      }

      final promoted = _BytecodeFunction(bytecode, closureRefs, this);

      final prototype = func.getProperty('prototype');
      if (prototype is JSObject) {
        promoted.setProperty('prototype', prototype);
      }

      func.setInternalSlot('[[BytecodeFunction]]', promoted);
      return promoted;
    } catch (_) {
      return null;
    }
  }

  bool _hasPromotableLegacyDeclaration(JSFunction func) {
    if (func is JSNativeFunction ||
        func is JSBoundFunction ||
        func is DynamicFunction ||
        func is RuntimeCallableFunction) {
      return false;
    }

    return func.declaration is FunctionDeclaration ||
        func.declaration is AsyncFunctionDeclaration ||
        func.declaration is MethodDefinition ||
        func.declaration is FunctionExpression ||
        func.declaration is AsyncFunctionExpression ||
        func.declaration is ArrowFunctionExpression ||
        func.declaration is AsyncArrowFunctionExpression;
  }

  bool _hasGlobalRootEnvironment(Environment env) {
    Environment? current = env;
    while (current != null) {
      if (current.parent == null) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  Set<String> _collectNonGlobalBindingNames(Environment env) {
    final names = <String>{};
    Environment? current = env;
    while (current != null && current.parent != null) {
      names.addAll(current.getLocals().keys);
      current = current.parent;
    }
    return names;
  }

  Binding? _resolveLegacyCapturedBinding(Environment env, String name) {
    Environment? current = env;
    while (current != null && current.parent != null) {
      final binding = current.getBinding(name);
      if (binding != null) {
        return binding;
      }
      current = current.parent;
    }
    return null;
  }

  bool _canProjectLegacyCapturedBinding(Binding binding) {
    return binding.type == BindingType.var_ ||
        binding.type == BindingType.let_ ||
        binding.type == BindingType.function ||
        binding.type == BindingType.parameter ||
        binding.type == BindingType.const_ ||
        binding.type == BindingType.functionExprName;
  }

  VarRef _projectLegacyCapturedBinding(Binding binding) {
    return LegacyBindingVarRef(binding);
  }

  /// ToPrimitive: convert an object to a primitive value by calling
  /// valueOf() / toString() in the appropriate order.
  JSValue _toPrimitive(JSValue val, {String hint = 'default'}) {
    if (val is! JSObject) return val;
    // Try Symbol.toPrimitive
    // (omitted for now — most objects don't have it)

    // OrdinaryToPrimitive
    final methodNames = (hint == 'string')
        ? ['toString', 'valueOf']
        : ['valueOf', 'toString'];
    for (final name in methodNames) {
      final method = _getProperty(val, name);
      if (method is JSNativeFunction ||
          method is _BytecodeFunction ||
          method is JSFunction ||
          method is JSBoundFunction) {
        final result = _callFunction(method, val, []);
        if (result is! JSObject) return result;
      }
    }
    throw JSTypeError('Cannot convert object to primitive value');
  }

  /// Abstract Equality Comparison (7.2.14)
  bool _abstractEquals(JSValue x, JSValue y) {
    // Same type: delegate to equals/strictEquals
    if (x.type == y.type) return x.strictEquals(y);

    // null == undefined
    if (x.isNull && y.isUndefined) return true;
    if (x.isUndefined && y.isNull) return true;

    // Number == String → compare as numbers
    if (x.isNumber && y.isString) return x.equals(JSNumber(y.toNumber()));
    if (x.isString && y.isNumber) return JSNumber(x.toNumber()).equals(y);

    // BigInt == String
    if (x.isBigInt && y.isString) return x.equals(y);
    if (x.isString && y.isBigInt) return y.equals(x);

    // Boolean == anything → ToNumber(bool) == other
    if (x.isBoolean) return _abstractEquals(JSNumber(x.toNumber()), y);
    if (y.isBoolean) return _abstractEquals(x, JSNumber(y.toNumber()));

    // Object == String/Number/BigInt/Symbol → ToPrimitive(object) == other
    if ((x.isString || x.isNumber || x.isBigInt || x is JSSymbol) &&
        y is JSObject) {
      return _abstractEquals(x, _toPrimitive(y));
    }
    if (x is JSObject &&
        (y.isString || y.isNumber || y.isBigInt || y is JSSymbol)) {
      return _abstractEquals(_toPrimitive(x), y);
    }

    // BigInt == Number
    if (x.isBigInt && y.isNumber) return x.equals(y);
    if (x.isNumber && y.isBigInt) return y.equals(x);

    return false;
  }

  static String _jsToString(JSValue val) {
    if (val is JSString) return val.primitiveValue;
    return val.toString();
  }

  JSValue _makeError(String type, String message) {
    final obj = JSObject();
    obj.setProperty('name', JSString(type));
    obj.setProperty('message', JSString(message));
    final embeddedPosition = type == 'SyntaxError'
        ? RegExp(r':(\d+):(\d+)$').firstMatch(message)
        : null;
    final stack = captureCurrentStackTrace();
    if (embeddedPosition != null) {
      final line = int.parse(embeddedPosition.group(1)!);
      final column = int.parse(embeddedPosition.group(2)!);
      obj.setProperty('stack', JSString('<eval>:$line:$column'));
      obj.setProperty('lineNumber', JSNumber(line.toDouble()));
      obj.setProperty('columnNumber', JSNumber(column.toDouble()));
    } else {
      obj.setProperty(
        'stack',
        JSString(stack.isEmpty ? '$type: $message' : stack),
      );
    }
    final position = _currentSourcePosition();
    if (embeddedPosition == null && position != null) {
      obj.setProperty('lineNumber', JSNumber(position.line.toDouble()));
      obj.setProperty('columnNumber', JSNumber(position.column.toDouble()));
    }
    obj.setInternalSlot('HostErrorName', type);
    obj.setInternalSlot('ErrorData', true);
    // Set constructor to the global error constructor so instanceof/constructor checks work
    final ctor = globals[type];
    if (ctor is JSNativeFunction) {
      obj.setProperty('constructor', ctor);
      // Set prototype chain for proper inheritance
      final proto = ctor.getProperty('prototype');
      if (proto is JSObject) {
        obj.setPrototype(proto);
      }
    }
    return obj;
  }

  JSValue _makeSyntaxErrorFromParseFailure(Object error) {
    final raw = error.toString();
    int? line;
    int? column;
    String message = raw;

    try {
      final dynamic dynamicError = error;
      final dynamicLine = dynamicError.line;
      final dynamicColumn = dynamicError.column;
      if (dynamicLine is int && dynamicColumn is int) {
        line = dynamicLine;
        column = dynamicColumn;
        final dynamicMessage = dynamicError.message;
        if (dynamicMessage is String && dynamicMessage.isNotEmpty) {
          message = dynamicMessage;
        }
      }
    } catch (_) {}

    if (line == null || column == null) {
      final match = RegExp(
        r'ParseError at (\d+):(\d+):\s*(.*)$',
      ).firstMatch(raw);
      if (match != null) {
        line = int.parse(match.group(1)!);
        column = int.parse(match.group(2)!);
        message = raw;
      }
    }

    final obj = JSObject();
    obj.setProperty('name', JSString('SyntaxError'));
    obj.setProperty('message', JSString(message));
    if (line != null && column != null) {
      obj.setProperty('stack', JSString('<eval>:$line:$column'));
      obj.setProperty('lineNumber', JSNumber(line.toDouble()));
      obj.setProperty('columnNumber', JSNumber(column.toDouble()));
    } else {
      obj.setProperty('stack', JSString('SyntaxError: $raw'));
    }
    obj.setInternalSlot('HostErrorName', 'SyntaxError');
    obj.setInternalSlot('ErrorData', true);
    final ctor = globals['SyntaxError'];
    if (ctor is JSNativeFunction) {
      obj.setProperty('constructor', ctor);
      final proto = ctor.getProperty('prototype');
      if (proto is JSObject) {
        obj.setPrototype(proto);
      }
    }
    return obj;
  }

  void _appendOuterStackFrame(JSValue errorValue) {
    if (errorValue is! JSObject) {
      return;
    }
    final outerStack = captureCurrentStackTrace();
    if (outerStack.isEmpty) {
      return;
    }
    final stackValue = errorValue.getProperty('stack');
    final existing = stackValue.isUndefined ? '' : stackValue.toString();
    if (existing.contains(outerStack)) {
      return;
    }
    final merged = existing.isEmpty ? outerStack : '$existing\n$outerStack';
    errorValue.setProperty('stack', JSString(merged));
  }

  static double _pow(double base, double exp) {
    if (exp == 0) return 1;
    if (base == 1) return 1;
    if (exp.isInfinite) {
      if (base.abs() == 1) return double.nan;
      if (base.abs() < 1) return exp > 0 ? 0 : double.infinity;
      return exp > 0 ? double.infinity : 0;
    }
    // Use Dart's pow
    final result =
        !base.isNaN &&
            !base.isInfinite &&
            base == base.truncateToDouble() &&
            exp == exp.truncateToDouble() &&
            exp >= 0
        ? _intPow(base.toInt(), exp.toInt()).toDouble()
        : _doublePow(base, exp);
    return result;
  }

  static int _intPow(int base, int exp) {
    if (exp < 0) return 0; // integer division: rounds to 0
    var result = 1;
    for (var i = 0; i < exp; i++) {
      result *= base;
    }
    return result;
  }

  static double _doublePow(double base, double exp) {
    // Dart doesn't have a built-in pow that handles all JS edge cases
    // Use dart:math pow
    return _dartPow(base, exp);
  }

  static int _toInt32(double n) {
    if (n.isNaN || n.isInfinite || n == 0) return 0;
    final i = n.truncate();
    return i.toSigned(32);
  }

  static int _toUint32(double n) {
    if (n.isNaN || n.isInfinite || n == 0) return 0;
    final i = n.truncate();
    return i.toUnsigned(32);
  }

  JSArray _createArray([List<JSValue>? elements]) {
    final array = JSArray(elements);
    final proto = JSArray.arrayPrototype;
    if (proto != null) {
      array.setPrototype(proto);
    }
    return array;
  }

  JSValue _readLocal(StackFrame frame, int index) {
    final local = frame.locals[index];
    if (local is _VarRefWrapper) {
      return local.ref.value;
    }

    final variable = frame.func.vars[index];
    if (variable.isLexical && identical(local, JSTemporalDeadZone.instance)) {
      throw JSReferenceError(
        'Cannot access \'${variable.name}\' before initialization',
      );
    }

    return local;
  }

  void _writeLocal(
    StackFrame frame,
    int index,
    JSValue value, {
    bool initializing = false,
  }) {
    final existing = frame.locals[index];
    if (existing is _VarRefWrapper) {
      if (initializing) {
        existing.ref.initialize(value);
      } else {
        existing.ref.value = value;
      }
      _syncTopLevelLocalToGlobal(frame, index, value);
      return;
    }

    final variable = frame.func.vars[index];
    if (!initializing &&
        variable.isConst &&
        !identical(existing, JSTemporalDeadZone.instance)) {
      throw JSTypeError('Assignment to constant variable: ${variable.name}');
    }

    frame.locals[index] = value;
    _syncTopLevelLocalToGlobal(frame, index, value);
  }

  JSValue _getSuperProperty(JSValue target, String name, JSValue receiver) {
    JSValue? current = target;

    while (current != null) {
      PropertyDescriptor? descriptor;
      JSValue? next;

      if (current is JSObject) {
        descriptor = current.getOwnPropertyDescriptor(name);
        next = current.getPrototype();
      } else if (current is JSFunction) {
        descriptor = current.getOwnPropertyDescriptor(name);
        next = _getFunctionPrototypeChainValue(current);
      } else {
        break;
      }

      if (descriptor != null) {
        if (descriptor.isAccessor) {
          final getter = descriptor.getter;
          if (getter == null) {
            return JSUndefined.instance;
          }
          // Cycle detection: track the specific getter function
          if (_activeGetters.contains(getter)) {
            return JSUndefined.instance;
          }
          _activeGetters.add(getter);
          try {
            return _callFunction(getter, receiver, const []);
          } finally {
            _activeGetters.remove(getter);
          }
        }
        return descriptor.value ?? JSUndefined.instance;
      }

      current = next;
    }

    return JSUndefined.instance;
  }
}

// ================================================================
// Internal helper types
// ================================================================

/// A bytecode function closure: a compiled function + captured variable refs.
/// Extends JSNativeFunction so it can be used as a callback by the existing runtime.
class _BytecodeFunction extends JSNativeFunction {
  final FunctionBytecode bytecode;
  final List<VarRef> closureVarRefs;
  final Map<String, VarRef> capturedEvalBindings;
  final List<JSObject> capturedWithObjects;
  final JSValue lexicalThis;
  final JSValue lexicalNewTarget;
  final BytecodeVM _vm;

  static bool _isConstructableKind(FunctionKind kind) {
    switch (kind) {
      case FunctionKind.normal:
      case FunctionKind.constructor_:
        return true;
      case FunctionKind.arrow:
      case FunctionKind.method:
      case FunctionKind.getter:
      case FunctionKind.setter:
      case FunctionKind.generator:
      case FunctionKind.asyncFunction:
      case FunctionKind.asyncArrow:
      case FunctionKind.asyncGenerator:
        return false;
    }
  }

  _BytecodeFunction(
    this.bytecode,
    this.closureVarRefs,
    this._vm, {
    JSValue? lexicalThis,
    JSValue? lexicalNewTarget,
    Map<String, VarRef>? capturedEvalBindings,
    List<JSObject>? capturedWithObjects,
  }) : capturedEvalBindings = capturedEvalBindings ?? <String, VarRef>{},
       capturedWithObjects = capturedWithObjects ?? <JSObject>[],
       lexicalThis = lexicalThis ?? JSUndefined.instance,
       lexicalNewTarget = lexicalNewTarget ?? JSUndefined.instance,
       super(
         functionName: bytecode.name,
         expectedArgs: bytecode.expectedArgCount,
         nativeImpl: (_) => JSUndefined.instance, // overridden by getter below
         isConstructor: _isConstructableKind(bytecode.kind),
       ) {
    final proto = super.getProperty('prototype');
    if (proto is JSObject) {
      proto.defineProperty(
        'constructor',
        PropertyDescriptor(
          value: this,
          writable: true,
          enumerable: false,
          configurable: true,
        ),
      );
    }
  }

  /// Override nativeImpl getter so ArrayPrototype._callFunction etc. use bytecode execution
  @override
  NativeFunction get nativeImpl =>
      (args) => _vm._callBytecodeFunction(this, _vm._getGlobalThis(), args);

  @override
  JSValue call(List<JSValue> args) {
    // Native runtime calls this with args (no thisValue prepended)
    return _vm._callBytecodeFunction(this, _vm._getGlobalThis(), args);
  }

  @override
  JSValue callWithThis(List<JSValue> args, JSValue thisBinding) {
    return _vm._callBytecodeFunction(this, thisBinding, args);
  }

  @override
  String toString() => bytecode.sourceText ?? super.toString();

  @override
  JSValue getProperty(String name) {
    switch (name) {
      case 'lineNumber':
        final mapping = bytecode.sourceMap?.isNotEmpty == true
            ? bytecode.sourceMap!.first
            : null;
        final line = mapping?.line ?? bytecode.sourceLine;
        return line == null ? JSUndefined.instance : JSNumber(line.toDouble());
      case 'columnNumber':
        final mapping = bytecode.sourceMap?.isNotEmpty == true
            ? bytecode.sourceMap!.first
            : null;
        final column = mapping?.column ?? bytecode.sourceColumn;
        return column == null
            ? JSUndefined.instance
            : JSNumber(column.toDouble());
      case 'prototype':
        // Lazily create a proper prototype object if not yet set
        final existing = super.getProperty('prototype');
        if (existing is JSObject) {
          // Only set constructor if not already defined
          if (existing.getOwnPropertyDescriptor('constructor') == null) {
            existing.defineProperty(
              'constructor',
              PropertyDescriptor(
                value: this,
                writable: true,
                enumerable: false,
                configurable: true,
              ),
            );
          }
          return existing;
        }
        if (!existing.isUndefined) return existing;
        final proto = JSObject();
        proto.defineProperty(
          'constructor',
          PropertyDescriptor(
            value: this,
            writable: true,
            enumerable: false,
            configurable: true,
          ),
        );
        super.setProperty('prototype', proto);
        return proto;
      case 'call':
        return JSNativeFunction(
          functionName: 'call',
          hasContextBound: true,
          nativeImpl: (args) {
            final thisArg = args.isNotEmpty ? args[0] : JSUndefined.instance;
            final callArgs = args.length > 1 ? args.sublist(1) : <JSValue>[];
            return _vm._callFunction(this, thisArg, callArgs);
          },
        );
      case 'apply':
        return JSNativeFunction(
          functionName: 'apply',
          hasContextBound: true,
          nativeImpl: (args) {
            final thisArg = args.isNotEmpty ? args[0] : JSUndefined.instance;
            List<JSValue> callArgs = [];
            if (args.length > 1) {
              final argsArray = args[1];
              if (argsArray is JSArray) {
                callArgs = argsArray.elements.toList();
              } else if (!argsArray.isNull && !argsArray.isUndefined) {
                if (argsArray is JSObject) {
                  final len = argsArray.getProperty('length');
                  if (!len.isUndefined && !len.isNull) {
                    final count = len.toNumber().toInt();
                    callArgs = List.generate(
                      count,
                      (i) => argsArray.getProperty('$i'),
                    );
                  }
                }
              }
            }
            return _vm._callFunction(this, thisArg, callArgs);
          },
        );
      case 'bind':
        return JSNativeFunction(
          functionName: 'bind',
          hasContextBound: true,
          nativeImpl: (args) {
            final thisArg = args.isNotEmpty ? args[0] : JSUndefined.instance;
            final boundArgs = args.length > 1 ? args.sublist(1) : <JSValue>[];
            return JSBoundFunction(this, thisArg, boundArgs);
          },
        );
      default:
        return super.getProperty(name);
    }
  }

  @override
  JSValueType get type => JSValueType.function;

  @override
  bool toBoolean() => true;

  @override
  double toNumber() => double.nan;

  @override
  bool equals(JSValue other) => identical(this, other);

  @override
  bool strictEquals(JSValue other) => identical(this, other);
}

/// Wrapper so locals that get captured can be boxed inline.
class _VarRefWrapper extends JSValue {
  final VarRef ref;
  _VarRefWrapper(this.ref);

  @override
  JSValueType get type => ref.value.type;
  @override
  dynamic get primitiveValue => ref.value.primitiveValue;
  @override
  bool toBoolean() => ref.value.toBoolean();
  @override
  double toNumber() => ref.value.toNumber();
  @override
  String toString() => ref.value.toString();
  @override
  JSObject toObject() => ref.value.toObject();
  @override
  bool equals(JSValue other) => ref.value.equals(other);
  @override
  bool strictEquals(JSValue other) => ref.value.strictEquals(other);
}

/// Internal signal for return statements
class _ReturnSignal {
  final JSValue value;
  _ReturnSignal(this.value);
}

/// Internal signal for yield (generator suspension)
class _YieldSignal {
  final JSValue value;
  final bool delegate;
  _YieldSignal(this.value, {this.delegate = false});
}

/// Internal signal for throw statements
class _ThrowSignal {
  final JSValue value;
  _ThrowSignal(this.value);
}

/// Internal signal: await hit a pending Promise, suspend execution.
class _AwaitSuspend {
  final JSPromise promise;
  _AwaitSuspend(this.promise);
}

/// Internal signal for tail call optimization: instead of recursing, reuse frame.
class _TailCall {
  final JSValue func;
  final List<JSValue> args;
  final JSValue? thisVal;
  _TailCall(this.func, this.args, {this.thisVal});
}

class _StackArgsView extends ListBase<JSValue> {
  final List<JSValue> _source;
  final int _start;
  final int _length;

  _StackArgsView(this._source, this._start, this._length);

  @override
  int get length => _length;

  @override
  set length(int newLength) {
    throw UnsupportedError('Cannot resize stack args view');
  }

  @override
  JSValue operator [](int index) {
    RangeError.checkValidIndex(index, this, null, _length);
    return _source[_start + index];
  }

  @override
  void operator []=(int index, JSValue value) {
    throw UnsupportedError('Cannot mutate stack args view');
  }
}

class _BytecodeMappedArguments extends JSObject {
  final List<JSValue> _actualArgs;
  final List<JSValue> _parameterSlots;
  final Set<int> _connectedIndices = <int>{};

  _BytecodeMappedArguments(this._actualArgs, this._parameterSlots) {
    final mappedCount = math.min(_parameterSlots.length, _actualArgs.length);
    for (var i = 0; i < _actualArgs.length; i++) {
      defineProperty(
        i.toString(),
        PropertyDescriptor(
          value: _actualArgs[i],
          writable: true,
          enumerable: true,
          configurable: true,
        ),
      );
      if (i < mappedCount) {
        _connectedIndices.add(i);
      }
    }
  }

  bool _isConnectedIndex(int index, String name) =>
      _connectedIndices.contains(index) && hasOwnProperty(name);

  @override
  JSValue getProperty(String name) {
    final index = int.tryParse(name);
    if (index != null && _isConnectedIndex(index, name)) {
      return _parameterSlots[index];
    }
    return super.getProperty(name);
  }

  @override
  void setProperty(String name, JSValue value) {
    super.setProperty(name, value);
    final index = int.tryParse(name);
    if (index != null && _isConnectedIndex(index, name)) {
      final descriptor = super.getOwnPropertyDescriptor(name);
      if (descriptor != null && !descriptor.isAccessor) {
        _parameterSlots[index] = value;
      }
    }
  }

  @override
  void defineProperty(String name, PropertyDescriptor descriptor) {
    final index = int.tryParse(name);
    final wasConnected =
        index != null &&
        _connectedIndices.contains(index) &&
        hasOwnProperty(name);
    PropertyDescriptor descriptorToApply = descriptor;

    if (wasConnected && !descriptor.hasValueProperty && !descriptor.writable) {
      descriptorToApply = PropertyDescriptor(
        value: _parameterSlots[index],
        writable: descriptor.writable,
        enumerable: descriptor.enumerable,
        configurable: descriptor.configurable,
        hasValueProperty: true,
      );
    }

    super.defineProperty(name, descriptorToApply);

    if (index == null || !wasConnected) {
      return;
    }

    if (descriptorToApply.hasValueProperty) {
      final mappedValue = descriptorToApply.value ?? JSUndefined.instance;
      _parameterSlots[index] = mappedValue;
    }

    final currentDescriptor = super.getOwnPropertyDescriptor(name);
    if (descriptorToApply.isAccessor ||
        (currentDescriptor != null && !currentDescriptor.writable)) {
      _connectedIndices.remove(index);
    }
  }

  @override
  bool deleteProperty(String name) {
    final deleted = super.deleteProperty(name);
    final index = int.tryParse(name);
    if (deleted && index != null) {
      _connectedIndices.remove(index);
    }
    return deleted;
  }

  @override
  PropertyDescriptor? getOwnPropertyDescriptor(String name) {
    final descriptor = super.getOwnPropertyDescriptor(name);
    final index = int.tryParse(name);
    if (descriptor == null ||
        index == null ||
        !_isConnectedIndex(index, name)) {
      return descriptor;
    }
    if (descriptor.isAccessor) {
      return descriptor;
    }
    return PropertyDescriptor(
      value: _parameterSlots[index],
      writable: descriptor.writable,
      enumerable: descriptor.enumerable,
      configurable: descriptor.configurable,
      hasValueProperty: descriptor.hasValueProperty,
    );
  }
}

/// Exception wrapper for unhandled JS exceptions
class _JSException implements Exception {
  final JSValue value;
  _JSException(this.value);

  @override
  String toString() => 'JSException: ${BytecodeVM._jsToString(value)}';
}

/// Iterator for for-in loops
class _ForInIterator extends JSValue {
  final List<String> keys;
  final JSObject? source;
  int _index = 0;

  _ForInIterator(this.keys, {this.source});

  bool get hasNext => _index < keys.length;
  String next() => keys[_index++];

  @override
  JSValueType get type => JSValueType.object;
  @override
  dynamic get primitiveValue => null;
  @override
  bool toBoolean() => true;
  @override
  double toNumber() => double.nan;
  @override
  String toString() => '[ForInIterator]';
  @override
  JSObject toObject() => JSObject();
  @override
  bool equals(JSValue other) => identical(this, other);
  @override
  bool strictEquals(JSValue other) => identical(this, other);
}

/// Iterator for for-of loops
class _ForOfIterator extends JSValue {
  final List<JSValue> values;
  int _index = 0;

  _ForOfIterator(this.values);

  bool get hasNext => _index < values.length;
  JSValue next() => values[_index++];

  @override
  JSValueType get type => JSValueType.object;
  @override
  dynamic get primitiveValue => null;
  @override
  bool toBoolean() => true;
  @override
  double toNumber() => double.nan;
  @override
  String toString() => '[ForOfIterator]';
  @override
  JSObject toObject() => JSObject();
  @override
  bool equals(JSValue other) => identical(this, other);
  @override
  bool strictEquals(JSValue other) => identical(this, other);
}

/// Dart math pow
double _dartPow(double base, double exp) {
  return math.pow(base, exp).toDouble();
}
