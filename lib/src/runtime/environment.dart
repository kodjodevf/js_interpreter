/// JavaScript execution environment
/// Management of scopes, execution contexts and variable binding
library;

import 'js_value.dart';

/// Types of variable binding according to ECMAScript
enum BindingType {
  var_, // var declarations (hoisted, function-scoped)
  let_, // let declarations (block-scoped)
  const_, // const declarations (block-scoped, immutable)
  function, // function declarations (hoisted)
  parameter, // function parameters
}

/// Exceptions for environment errors
class EnvironmentError extends JSError {
  EnvironmentError(super.message) : super(name: 'EnvironmentError');
}

/// Represents a variable binding in the environment
class Binding {
  final String name;
  final BindingType type;
  JSValue value;
  final bool mutable;
  bool initialized;

  Binding({
    required this.name,
    required this.type,
    required this.value,
    required this.mutable,
    this.initialized = true,
  });

  /// Create a var binding
  factory Binding.varBinding(String name, JSValue value) {
    return Binding(
      name: name,
      type: BindingType.var_,
      value: value,
      mutable: true,
      initialized: true,
    );
  }

  /// Create a let binding
  factory Binding.letBinding(String name, JSValue value) {
    return Binding(
      name: name,
      type: BindingType.let_,
      value: value,
      mutable: true,
      initialized: true,
    );
  }

  /// Create a const binding
  factory Binding.constBinding(String name, JSValue value) {
    return Binding(
      name: name,
      type: BindingType.const_,
      value: value,
      mutable: false,
      initialized: true,
    );
  }

  /// Create a function binding
  factory Binding.functionBinding(String name, JSValue value) {
    return Binding(
      name: name,
      type: BindingType.function,
      value: value,
      mutable: true,
      initialized: true,
    );
  }

  /// Create a parameter binding
  factory Binding.parameterBinding(String name, JSValue value) {
    return Binding(
      name: name,
      type: BindingType.parameter,
      value: value,
      mutable: true,
      initialized: true,
    );
  }

  /// Update the value of the binding
  void setValue(JSValue newValue) {
    if (!initialized) {
      throw JSReferenceError('Cannot access \'$name\' before initialization');
    }
    if (!mutable) {
      throw JSTypeError('Assignment to constant variable: $name');
    }
    value = newValue;
  }

  @override
  String toString() =>
      'Binding($name: $value, ${type.name}, mutable: $mutable)';
}

/// JavaScript lexical environment (scope)
class Environment {
  final Environment? parent;
  final Map<String, Binding> _bindings = {};
  final String debugName;
  static int _envCounter = 0;
  late final int envId;

  Environment({this.parent, this.debugName = 'Environment'}) {
    envId = _envCounter++;
  }

  /// Create a global environment
  factory Environment.global() {
    return Environment(debugName: 'Global');
  }

  /// Create a function environment
  factory Environment.function(Environment parent, String functionName) {
    return Environment(parent: parent, debugName: 'Function($functionName)');
  }

  /// Create a block environment
  factory Environment.block(Environment parent) {
    return Environment(parent: parent, debugName: 'Block');
  }

  /// Create a module environment
  factory Environment.module(Environment global) {
    return Environment(parent: global, debugName: 'Module');
  }

  /// Define a new binding in this environment
  void define(String name, JSValue value, BindingType type) {
    if (_bindings.containsKey(name)) {
      // Check if we can redefine
      final existing = _bindings[name]!;

      // var can be redefined in the same scope
      if (type == BindingType.var_ && existing.type == BindingType.var_) {
        existing.setValue(value);
        return;
      }

      // parameter binding that is uninitialized (TDZ) can be initialized
      if (type == BindingType.parameter &&
          existing.type == BindingType.parameter &&
          !existing.initialized) {
        existing.value = value;
        existing.initialized = true;
        return;
      }

      // function can be redefined by var in the same scope
      // var can also redeclare a parameter (necessary for code bundle)
      // const/let can be redeclared as var in non-strict global scope
      if ((type == BindingType.var_ && existing.type == BindingType.function) ||
          (type == BindingType.var_ &&
              existing.type == BindingType.parameter) ||
          (type == BindingType.function && existing.type == BindingType.var_) ||
          (type == BindingType.function &&
              existing.type == BindingType.function) ||
          (type == BindingType.var_ && existing.type == BindingType.const_) ||
          (type == BindingType.var_ && existing.type == BindingType.let_) ||
          (type == BindingType.const_ &&
              existing.type == BindingType.const_ &&
              _isGlobalScope()) ||
          (type == BindingType.const_ &&
              existing.type == BindingType.let_ &&
              _isGlobalScope()) ||
          (type == BindingType.const_ &&
              existing.type == BindingType.var_ &&
              _isGlobalScope())) {
        _bindings[name] = Binding(
          name: name,
          type: type,
          value: value,
          mutable: true,
          initialized: true,
        );
        return;
      }

      throw JSError('Identifier \'$name\' has already been declared');
    }

    final binding = switch (type) {
      BindingType.var_ => Binding.varBinding(name, value),
      BindingType.let_ => Binding.letBinding(name, value),
      BindingType.const_ => Binding.constBinding(name, value),
      BindingType.function => Binding.functionBinding(name, value),
      BindingType.parameter => Binding.parameterBinding(name, value),
    };

    _bindings[name] = binding;
  }

  /// Create an uninitialized binding (TDZ) for a parameter
  /// Used to establish the Temporal Dead Zone for parameters
  void defineUninitialized(String name, BindingType type) {
    if (_bindings.containsKey(name)) {
      // If the binding already exists and it's a parameter, we can leave it as is
      if (type == BindingType.parameter &&
          _bindings[name]!.type == BindingType.parameter) {
        _bindings[name]!.initialized = false;
        return;
      }
      throw JSError('Identifier \'$name\' has already been declared');
    }

    final binding = Binding(
      name: name,
      type: type,
      value: JSValueFactory.undefined(),
      mutable: true,
      initialized: false,
    );

    _bindings[name] = binding;
  }

  /// Mark a binding as initialized
  void markInitialized(String name) {
    if (_bindings.containsKey(name)) {
      _bindings[name]!.initialized = true;
    } else if (parent != null) {
      parent!.markInitialized(name);
    }
  }

  /// Retrieve the value of a variable
  JSValue get(String name) {
    // Search in this environment
    if (_bindings.containsKey(name)) {
      final binding = _bindings[name]!;
      if (!binding.initialized) {
        throw JSReferenceError('Cannot access \'$name\' before initialization');
      }
      return binding.value;
    }

    // Search in parent environment
    if (parent != null) {
      return parent!.get(name);
    }

    // Variable not found
    throw JSReferenceError('$name is not defined');
  }

  /// Assign a value to an existing variable
  void set(String name, JSValue value, {bool strictMode = false}) {
    // Search in this environment
    if (_bindings.containsKey(name)) {
      _bindings[name]!.setValue(value);
      return;
    }

    // Search in parent environment
    if (parent != null) {
      try {
        parent!.set(name, value, strictMode: strictMode);
        return;
      } catch (e) {
        if (e is! JSReferenceError) rethrow;
      }
    }

    // Variable not found
    // In strict mode, raise an error instead of creating a global variable
    if (strictMode) {
      throw JSReferenceError('$name is not defined');
    }

    // In non-strict mode, create a global variable
    _bindings[name] = Binding.varBinding(name, value);
  }

  /// Assign a value to a variable in THIS scope only (does not go up to parents)
  /// Used to update function parameters that shadow parent variables
  void setLocal(String name, JSValue value) {
    if (_bindings.containsKey(name)) {
      _bindings[name]!.setValue(value);
    } else {
      throw JSReferenceError('$name is not defined in local scope');
    }
  }

  /// Force assignment of a variable in THIS scope only, without checking mutability
  /// Used during generator re-execution to reassign const variables
  void setLocalForce(String name, JSValue value) {
    if (_bindings.containsKey(name)) {
      _bindings[name]!.value = value;
    } else {
      throw JSReferenceError('$name is not defined in local scope');
    }
  }

  /// Check if a variable exists in this scope or its parents
  bool has(String name) {
    if (_bindings.containsKey(name)) return true;
    return parent?.has(name) ?? false;
  }

  /// Check if a variable exists in this scope only
  bool hasLocal(String name) => _bindings.containsKey(name);

  /// Returns the binding of a local variable (or null if it doesn't exist)
  Binding? getBinding(String name) => _bindings[name];

  /// Check if this scope is the global scope
  bool _isGlobalScope() {
    return parent == null;
  }

  /// Returns all variables of this scope
  Map<String, JSValue> getLocals() {
    return Map.fromEntries(
      _bindings.entries.map((e) => MapEntry(e.key, e.value.value)),
    );
  }

  /// Create a temporary uninitialized binding (for hoisting)
  void createHoistedBinding(String name, BindingType type) {
    if (_bindings.containsKey(name)) return;

    _bindings[name] = Binding(
      name: name,
      type: type,
      value: JSValueFactory.undefined(),
      mutable: type != BindingType.const_,
      initialized: false,
    );
  }

  /// Initialize a hoisted binding
  void initializeHoistedBinding(String name, JSValue value) {
    if (!_bindings.containsKey(name)) {
      throw JSError('No hoisted binding found for $name');
    }

    final binding = _bindings[name]!;
    binding.value = value;
    binding.initialized = true;
  }

  /// Delete a binding from this environment
  /// Returns true if the binding was deleted, false if it didn't exist
  bool delete(String name) {
    if (_bindings.containsKey(name)) {
      _bindings.remove(name);
      return true;
    }
    return false;
  }

  @override
  String toString() {
    final locals = _bindings.keys.join(', ');
    return '$debugName: {$locals}${parent != null ? ' -> ${parent.toString()}' : ''}';
  }
}

/// Environment wrapper for with statements
/// Delegates property lookups to an object before checking environment bindings
class WithEnvironment extends Environment {
  final JSObject withObject;

  WithEnvironment({required Environment parent, required this.withObject})
    : super(parent: parent, debugName: 'With');

  @override
  JSValue get(String name) {
    // First try the with object's properties
    if (withObject.hasProperty(name)) {
      return withObject.getProperty(name);
    }

    // Then try the parent environment
    return super.get(name);
  }

  @override
  void set(String name, JSValue value, {bool strictMode = false}) {
    // First try the with object's properties
    if (withObject.hasProperty(name)) {
      withObject.setProperty(name, value);
      return;
    }

    // Then try the parent environment
    super.set(name, value, strictMode: strictMode);
  }

  @override
  bool has(String name) {
    // Check both with object and parent environment
    return withObject.hasProperty(name) || super.has(name);
  }

  @override
  bool delete(String name) {
    // First try to delete from with object
    if (withObject.hasProperty(name)) {
      return withObject.deleteProperty(name);
    }

    // Then try parent environment
    return super.delete(name);
  }
}

/// Types of JavaScript exceptions for flow control
enum ExceptionType { none, return_, break_, continue_, throw_ }

/// Exception for JavaScript flow control
class FlowControlException implements Exception {
  final ExceptionType type;
  final JSValue? value;
  final String? label;
  final JSValue? completionValue; // Value before the abrupt completion

  const FlowControlException(
    this.type, {
    this.value,
    this.label,
    this.completionValue,
  });

  factory FlowControlException.return_([JSValue? value]) {
    return FlowControlException(ExceptionType.return_, value: value);
  }

  factory FlowControlException.break_([
    String? label,
    JSValue? completionValue,
  ]) {
    return FlowControlException(
      ExceptionType.break_,
      label: label,
      completionValue: completionValue,
    );
  }

  factory FlowControlException.continue_([
    String? label,
    JSValue? completionValue,
  ]) {
    return FlowControlException(
      ExceptionType.continue_,
      label: label,
      completionValue: completionValue,
    );
  }

  factory FlowControlException.throw_(JSValue value) {
    return FlowControlException(ExceptionType.throw_, value: value);
  }

  @override
  String toString() => 'FlowControlException(${type.name}, $value, $label)';
}

/// JavaScript execution context
class ExecutionContext {
  final Environment lexicalEnvironment;
  final Environment variableEnvironment;
  final JSValue thisBinding;
  final bool strictMode;
  final String debugName;

  // For functions
  final JSValue? function;
  final List<JSValue>? arguments;

  // For new.target - the function/class called with 'new'
  final JSValue? newTarget;

  // For functions async
  final dynamic asyncTask; // AsyncTask? - evite l'import circulaire

  // Trace of parameters to validate eval() in default parameters
  final Set<String>?
  parameterNames; // Non-null si on evalue des parametres by default

  // Track if we're in a catch block (catch parameters are non-deletable)
  final bool inCatch;

  ExecutionContext({
    required this.lexicalEnvironment,
    required this.variableEnvironment,
    required this.thisBinding,
    this.strictMode = false,
    this.debugName = 'ExecutionContext',
    this.function,
    this.arguments,
    this.newTarget,
    this.asyncTask,
    this.parameterNames,
    this.inCatch = false,
  });

  /// Create a global context
  factory ExecutionContext.global(
    Environment globalEnv, {
    JSValue? globalThis,
  }) {
    return ExecutionContext(
      lexicalEnvironment: globalEnv,
      variableEnvironment: globalEnv,
      thisBinding: globalThis ?? JSValueFactory.undefined(),
      debugName: 'Global',
    );
  }

  /// Create a function context
  factory ExecutionContext.function({
    required Environment lexicalEnv,
    required Environment varEnv,
    required JSValue thisBinding,
    required JSValue function,
    required List<JSValue> arguments,
    bool strictMode = false,
    dynamic asyncTask,
  }) {
    return ExecutionContext(
      lexicalEnvironment: lexicalEnv,
      variableEnvironment: varEnv,
      thisBinding: thisBinding,
      strictMode: strictMode,
      debugName: 'Function',
      function: function,
      arguments: arguments,
      asyncTask: asyncTask,
    );
  }

  @override
  String toString() => '$debugName: $lexicalEnvironment';
}

/// JavaScript execution stack
class ExecutionStack {
  final List<ExecutionContext> _stack = [];

  /// Current context
  ExecutionContext get current {
    if (_stack.isEmpty) {
      throw EnvironmentError('No execution context');
    }
    return _stack.last;
  }

  /// Push a new context
  void push(ExecutionContext context) {
    _stack.add(context);
  }

  /// Pop the current context
  ExecutionContext pop() {
    if (_stack.isEmpty) {
      throw EnvironmentError('Cannot pop empty execution stack');
    }
    return _stack.removeLast();
  }

  /// Stack size
  int get size => _stack.length;

  /// Check if the stack is empty
  bool get isEmpty => _stack.isEmpty;

  /// Stack trace for debugging
  List<String> getStackTrace() {
    return _stack.map((ctx) => ctx.debugName).toList();
  }

  /// Access all contexts of the stack (for inspection)
  List<ExecutionContext> get contexts => List.unmodifiable(_stack);

  /// Check if we are in strict mode
  bool currentStrictMode() {
    if (_stack.isEmpty) {
      return false;
    }
    return _stack.last.strictMode;
  }

  @override
  String toString() => 'ExecutionStack(${getStackTrace().join(' -> ')})';
}
