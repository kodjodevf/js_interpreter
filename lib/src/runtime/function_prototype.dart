/// Implementation of Function prototype and advanced methods
/// Provides Function.prototype.call(), apply(), bind() and advanced properties
library;

import 'js_value.dart';
import 'environment.dart';
import 'native_functions.dart';
import '../evaluator/evaluator.dart';

/// Callback to execute a JavaScript function with 'this' support
typedef FunctionExecutor =
    JSValue Function(
      JSFunction func,
      List<JSValue> args, [
      JSValue? thisBinding,
    ]);

/// Function.prototype - methods available on all functions
class FunctionPrototype {
  /// Executor to call JavaScript functions
  static FunctionExecutor? _functionExecutor;

  /// Sets the executor for JavaScript functions (called by the evaluator)
  static void setFunctionExecutor(FunctionExecutor executor) {
    _functionExecutor = executor;
  }

  /// Function.prototype.call(thisArg, ...args)
  /// Calls a function with a specific 'this' context
  static JSValue call(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      throw JSTypeError('Function.prototype.call called on null or undefined');
    }

    // When called as a method: args = [func, thisArg, arg1, arg2, ...]
    // When called directly: args[0] would be the function (shouldn't happen)
    final func = args[0];
    if (!func.isFunction) {
      throw JSTypeError('Function.prototype.call called on non-function');
    }

    // ES6: Class constructors cannot be called without 'new'
    if (func is JSClass) {
      throw JSTypeError(
        'Class constructor ${func.name} cannot be invoked without \'new\'',
      );
    }

    // Remaining arguments after the function
    // args[1] is the thisArg, args[2:] are the function arguments
    final thisArg = args.length > 1 ? args[1] : JSValueFactory.undefined();
    final funcArgs = args.length > 2 ? args.sublist(2) : <JSValue>[];

    // Call the function with the correct 'this' context
    // IMPORTANT: Check JSNativeFunction BEFORE JSFunction because JSNativeFunction inherits from JSFunction
    if (func is JSNativeFunction) {
      // For native functions, use callWithThis
      return func.callWithThis(funcArgs, thisArg);
    } else if (func is JSFunction) {
      return _callFunctionWithThis(func, funcArgs, thisArg, env);
    }

    throw JSTypeError('Invalid function call');
  }

  /// Function.prototype.apply(thisArg, argsArray)
  /// Calls a function with a 'this' context and an array of arguments
  static JSValue apply(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      throw JSTypeError('Function.prototype.apply called on null or undefined');
    }

    final func = args[0];
    if (!func.isFunction) {
      throw JSTypeError('Function.prototype.apply called on non-function');
    }

    // ES6: Class constructors cannot be called without 'new'
    if (func is JSClass) {
      throw JSTypeError(
        'Class constructor ${func.name} cannot be invoked without \'new\'',
      );
    }

    final thisArg = args.length > 1 ? args[1] : JSValueFactory.undefined();
    List<JSValue> funcArgs = [];

    // Second argument must be an array, array-like object, or null/undefined
    if (args.length > 2) {
      final argsArray = args[2];
      if (argsArray.isNull || argsArray.isUndefined) {
        funcArgs = [];
      } else if (argsArray is JSArray) {
        funcArgs = argsArray.elements.toList();
      } else if (argsArray is JSObject) {
        // Support for array-like objects (has length property and numeric indices)
        final lengthProp = argsArray.getProperty('length');
        if (lengthProp.isNumber) {
          final length = lengthProp.toNumber().toInt();
          if (length < 0) {
            funcArgs = [];
          } else {
            funcArgs = List.generate(length, (i) {
              final value = argsArray.getProperty(i.toString());
              return value;
            });
          }
        } else {
          throw JSTypeError(
            'Function.prototype.apply: arguments list has wrong type',
          );
        }
      } else {
        throw JSTypeError(
          'Function.prototype.apply: arguments list has wrong type',
        );
      }
    }

    // Call the function with the correct 'this' context
    if (func is JSFunction) {
      return _callFunctionWithThis(func, funcArgs, thisArg, env);
    } else if (func is JSNativeFunction) {
      // For native functions, use callWithThis
      return func.callWithThis(funcArgs, thisArg);
    }

    throw JSTypeError('Invalid function call');
  }

  /// Function.prototype.bind(thisArg, ...args)
  /// Creates a new function with a 'this' context and predefined arguments
  static JSValue bind(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      throw JSTypeError('Function.prototype.bind called on null or undefined');
    }

    final func = args[0];
    if (!func.isFunction) {
      throw JSTypeError('Function.prototype.bind called on non-function');
    }

    final thisArg = args.length > 1 ? args[1] : JSValueFactory.undefined();
    final boundArgs = args.length > 2 ? args.sublist(2) : <JSValue>[];

    // Create a bound function
    return JSBoundFunction(func, thisArg, boundArgs);
  }

  /// toString() for functions
  static JSValue functionToString(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      throw JSTypeError(
        'Function.prototype.toString called on null or undefined',
      );
    }

    final func = args[0];
    if (!func.isFunction) {
      throw JSTypeError('Function.prototype.toString called on non-function');
    }

    if (func is JSFunction) {
      // ES2019: Return the source text if available, otherwise generate from declaration
      return JSValueFactory.string(func.toString());
    } else if (func is JSNativeFunction) {
      return JSValueFactory.string(
        'function ${func.functionName}() { [native code] }',
      );
    } else if (func is JSBoundFunction) {
      return JSValueFactory.string(
        'function bound ${func.originalFunction}() { [native code] }',
      );
    }

    return JSValueFactory.string('function () { [native code] }');
  }

  /// name property for functions
  static JSValue getName(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      return JSValueFactory.string('');
    }

    final func = args[0];
    if (func is JSFunction) {
      final name = func.declaration?.id?.name;
      return JSValueFactory.string(name ?? '');
    } else if (func is JSNativeFunction) {
      return JSValueFactory.string(func.functionName);
    } else if (func is JSBoundFunction) {
      return JSValueFactory.string('bound ${func.originalFunction}');
    }

    return JSValueFactory.string('');
  }

  /// length property for functions
  static JSValue getLength(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      return JSValueFactory.number(0);
    }

    final func = args[0];
    if (func is JSFunction) {
      final params = func.declaration?.params;
      return JSValueFactory.number(params?.length ?? 0);
    } else if (func is JSBoundFunction) {
      // For a bound function, length = original.length - boundArgs.length
      double originalLength = 0;
      if (func.originalFunction is JSFunction) {
        final originalFunc = func.originalFunction as JSFunction;
        originalLength = originalFunc.parameterCount.toDouble();
      } else if (func.originalFunction is JSNativeFunction) {
        // Native functions don't have parameterCount, use 0
        originalLength = 0;
      }

      final boundLength = func.boundArgs.length;
      return JSValueFactory.number(
        (originalLength - boundLength).clamp(0, double.infinity),
      );
    }

    return JSValueFactory.number(0);
  }

  /// Utility method to call a JSFunction with a 'this' context
  static JSValue _callFunctionWithThis(
    JSFunction func,
    List<JSValue> args,
    JSValue thisArg,
    Environment env,
  ) {
    // Use the executor with 'this' support
    if (_functionExecutor != null) {
      return _functionExecutor!(func, args, thisArg);
    }

    // Fallback: return undefined if no executor
    return JSValueFactory.undefined();
  }

  /// Adds Function.prototype methods to a function object
  static void addPrototypeMethods(JSObject funcObj) {
    funcObj.setProperty(
      'call',
      JSNativeFunction(
        functionName: 'call',
        nativeImpl: (args) => call(args, Environment.global()),
      ),
    );

    funcObj.setProperty(
      'apply',
      JSNativeFunction(
        functionName: 'apply',
        nativeImpl: (args) => apply(args, Environment.global()),
      ),
    );

    funcObj.setProperty(
      'bind',
      JSNativeFunction(
        functionName: 'bind',
        nativeImpl: (args) => bind(args, Environment.global()),
      ),
    );

    funcObj.setProperty(
      'toString',
      JSNativeFunction(
        functionName: 'toString',
        nativeImpl: (args) => functionToString(args, Environment.global()),
      ),
    );

    // Properties with getters
    funcObj.setProperty(
      'name',
      JSNativeFunction(
        functionName: 'get name',
        nativeImpl: (args) => getName(args, Environment.global()),
      ),
    );

    funcObj.setProperty(
      'length',
      JSNativeFunction(
        functionName: 'get length',
        nativeImpl: (args) => getLength(args, Environment.global()),
      ),
    );
  }

  /// Access to Function.prototype properties
  static JSValue getFunctionProperty(JSFunction func, String propertyName) {
    switch (propertyName) {
      case 'call':
        return JSNativeFunction(
          functionName: 'call',
          nativeImpl: (args) => call([func, ...args], Environment.global()),
        );
      case 'apply':
        return JSNativeFunction(
          functionName: 'apply',
          nativeImpl: (args) => apply([func, ...args], Environment.global()),
        );
      case 'bind':
        return JSNativeFunction(
          functionName: 'bind',
          nativeImpl: (args) => bind([func, ...args], Environment.global()),
        );
      case 'length':
        return JSValueFactory.number(func.parameterCount);
      case 'name':
        final declaration = func.declaration;
        if (declaration?.id != null) {
          return JSValueFactory.string(declaration.id.name);
        }
        return JSValueFactory.string('anonymous');
      case 'toString':
        return JSNativeFunction(
          functionName: 'toString',
          nativeImpl: (args) => functionToString([func], Environment.global()),
        );
      default:
        return JSValueFactory.undefined();
    }
  }
}

/// "Bound" function created by Function.prototype.bind()
class JSBoundFunction extends JSFunction {
  final JSValue originalFunction;
  final JSValue thisArg;
  final List<JSValue> boundArgs;

  late final String _boundName;
  late final int _boundLength;
  late final JSObject _boundPrototype;

  JSBoundFunction(this.originalFunction, this.thisArg, this.boundArgs)
    : super(null, null) {
    _initializeBoundFunctionProperties();
  }

  void _initializeBoundFunctionProperties() {
    // Nom de la fonction bound - handle JSClass, JSFunction, and other callables
    String originalName;
    if (originalFunction is JSClass) {
      originalName = (originalFunction as JSClass)
          .getProperty('name')
          .toString();
    } else if (originalFunction is JSFunction) {
      originalName = (originalFunction as JSFunction).functionName;
    } else {
      originalName = 'anonymous';
    }
    _boundName = 'bound $originalName';

    // Number of parameters for the bound function (original - boundArgs)
    int originalCount;
    if (originalFunction is JSClass) {
      // For classes, get parameter count from constructor
      final constructor = (originalFunction as JSClass).constructor;
      originalCount = constructor?.parameterCount ?? 0;
    } else if (originalFunction is JSFunction) {
      originalCount = (originalFunction as JSFunction).parameterCount;
    } else {
      originalCount = 0;
    }
    _boundLength = (originalCount - boundArgs.length).clamp(0, originalCount);

    // Prototype object for bound functions
    _boundPrototype = JSObject();
    _boundPrototype.setProperty('constructor', this);
  }

  @override
  JSValue getProperty(String name) {
    // Special handling for 'prototype' property to support Object.defineProperty
    if (name == 'prototype') {
      final descriptor = getOwnPropertyDescriptor(name);
      if (descriptor != null) {
        // If there's a getter, execute it
        if (descriptor.getter != null) {
          final evaluator = JSEvaluator.currentInstance;
          if (evaluator != null) {
            return evaluator.callFunction(descriptor.getter!, [], this);
          }
        }
        // If there's a setter but no getter, return undefined (ES6 spec)
        if (descriptor.setter != null && descriptor.getter == null) {
          return JSValueFactory.undefined();
        }
      }
      // Return the bound prototype if no descriptor or it's a data property
      return _boundPrototype;
    }

    switch (name) {
      case 'length':
        return JSValueFactory.number(_boundLength.toDouble());
      case 'name':
        return JSValueFactory.string(_boundName);
      default:
        // For other properties, use the default logic
        return super.getProperty(name);
    }
  }

  @override
  void setProperty(String name, JSValue value) {
    // Bound functions don't have configurable properties like length/name
    if (name == 'length' || name == 'name') {
      return;
    }
    // For other properties, we could store them somewhere, but for now we ignore them
  }

  @override
  bool hasProperty(String name) {
    return [
      'length',
      'name',
      'prototype',
      'call',
      'apply',
      'bind',
      'toString',
    ].contains(name);
  }

  @override
  bool deleteProperty(String name) {
    // Bound function properties cannot be deleted
    return false;
  }

  List<String> getPropertyNames({bool enumerableOnly = false}) {
    return ['length', 'name', 'prototype'];
  }

  @override
  String toString() {
    if (originalFunction is JSFunction) {
      final name =
          (originalFunction as JSFunction).declaration?.id?.name ?? 'anonymous';
      return 'function bound $name() { [native code] }';
    } else if (originalFunction is JSNativeFunction) {
      final name = (originalFunction as JSNativeFunction).functionName;
      return 'function bound $name() { [native code] }';
    }
    return 'function bound () { [native code] }';
  }

  /// Bound functions inherit constructability from their target function
  @override
  bool get isConstructor {
    if (originalFunction is JSFunction) {
      return (originalFunction as JSFunction).isConstructor;
    } else if (originalFunction is JSNativeFunction) {
      return (originalFunction as JSNativeFunction).isConstructor;
    }
    return false;
  }
}

/// Extension to add advanced properties to functions
extension FunctionExtensions on JSFunction {
  /// Gets the function name
  String get functionName {
    if (this is JSNativeFunction) {
      return (this as JSNativeFunction).functionName;
    }
    return declaration?.id?.name ?? 'anonymous';
  }

  /// Gets the number of parameters
  int get parameterCount {
    if (this is JSBoundFunction) {
      final bound = this as JSBoundFunction;
      int originalCount;
      if (bound.originalFunction is JSClass) {
        final constructor = (bound.originalFunction as JSClass).constructor;
        originalCount = constructor?.parameterCount ?? 0;
      } else if (bound.originalFunction is JSFunction) {
        originalCount = (bound.originalFunction as JSFunction).parameterCount;
      } else {
        originalCount = 0;
      }
      return (originalCount - bound.boundArgs.length).clamp(0, originalCount);
    }
    return declaration?.params?.length ?? 0;
  }
}

/// Support for arrow functions (arrow functions)
class JSArrowFunction extends JSFunction {
  final List<String> parameters;
  final dynamic body; // Expression ou BlockStatement
  final bool hasRestParam;
  final int restParamIndex;

  // ES2019: Store complete Parameter objects for destructuring support
  final List<dynamic>? parametersList; // List<Parameter> from AST

  // Captured 'this' binding from lexical context
  final JSValue? capturedThis;

  // Captured 'new.target' from lexical context (ES6)
  // Arrow functions don't have their own new.target, they inherit from enclosing context
  final JSValue? capturedNewTarget;

  // Store the class context if created in a constructor
  // This allows arrow functions to access the correct 'this' binding
  // even when called from a different execution context
  final JSClass? capturedClassContext;

  // ES6: Inferred name when assigned to a variable
  final String? inferredName;

  JSArrowFunction({
    required this.parameters,
    required this.body,
    required dynamic closureEnvironment,
    this.hasRestParam = false,
    this.restParamIndex = -1,
    this.parametersList,
    this.capturedThis,
    this.capturedNewTarget,
    this.capturedClassContext,
    this.inferredName,
    String? sourceText,
    String? moduleUrl,
    bool strictMode = false,
  }) : super(
         null,
         closureEnvironment,
         sourceText: sourceText,
         moduleUrl: moduleUrl,
         strictMode: strictMode,
         isArrowFunction: true,
       );

  @override
  JSValue getProperty(String name) {
    switch (name) {
      case 'length':
        return JSValueFactory.number(parameterCount.toDouble());
      case 'name':
        // ES6: Arrow functions have inferred name or empty string
        return JSValueFactory.string(inferredName ?? '');
      case 'prototype':
        // Arrow functions don't have a prototype property
        return JSValueFactory.undefined();
      case 'caller':
      case 'arguments':
        // ES6: Arrow functions throw TypeError when accessing caller/arguments
        throw JSTypeError(
          "'caller', 'callee', and 'arguments' properties may not be accessed on strict mode functions or the arguments objects for calls to them",
        );
      default:
        // For other properties, delegate to parent class
        return super.getProperty(name);
    }
  }

  @override
  void setProperty(String name, JSValue value) {
    switch (name) {
      case 'caller':
      case 'arguments':
        // ES6: Arrow functions throw TypeError when setting caller/arguments
        throw JSTypeError(
          "'caller', 'callee', and 'arguments' properties may not be accessed on strict mode functions or the arguments objects for calls to them",
        );
      default:
        super.setProperty(name, value);
    }
  }

  @override
  PropertyDescriptor? getOwnPropertyDescriptor(String name) {
    // ES6: Arrow functions have specific property descriptors
    switch (name) {
      case 'length':
        return PropertyDescriptor(
          value: JSValueFactory.number(parameterCount.toDouble()),
          writable: false,
          enumerable: false,
          configurable: true,
        );
      case 'name':
        // ES6: Arrow functions have inferred name or empty string
        return PropertyDescriptor(
          value: JSValueFactory.string(inferredName ?? ''),
          writable: false,
          enumerable: false,
          configurable: true,
        );
      case 'prototype':
        // Arrow functions don't have a prototype property
        return null;
      default:
        return super.getOwnPropertyDescriptor(name);
    }
  }

  @override
  String toString() {
    // ES2019: Return original source text if available
    if (sourceText != null) {
      return sourceText!;
    }
    final params = parameters.join(', ');
    return '($params) => { [native code] }';
  }

  @override
  int get parameterCount {
    // ES6: function.length is the number of params before the first with default value or rest
    if (parametersList != null) {
      int count = 0;
      for (final param in parametersList!) {
        // Stop counting at first param with default value or rest param
        if (param.defaultValue != null || param.isRest) break;
        count++;
      }
      return count;
    }
    return parameters.length;
  }

  /// Arrow functions are never constructors in ES6+
  @override
  bool get isConstructor => false;
}

/// Async arrow function - similar to JSArrowFunction but for async arrows
class JSAsyncArrowFunction extends JSArrowFunction {
  JSAsyncArrowFunction({
    required super.parameters,
    required super.body,
    required super.closureEnvironment,
    super.capturedThis,
    super.capturedNewTarget,
    super.hasRestParam,
    super.restParamIndex,
    super.parametersList,
    super.inferredName,
    super.moduleUrl,
  });

  @override
  String toString() {
    final params = parameters.join(', ');
    return 'async ($params) => { [native code] }';
  }
}

/// Function created dynamically via new Function(params, body)
/// This function parses and executes its body code when called
class DynamicFunction extends JSFunction {
  final List<String> parameterNames;
  final String bodyCode;
  final bool isStrict;
  final JSEvaluator evaluator;

  DynamicFunction({
    required this.parameterNames,
    required this.bodyCode,
    required this.isStrict,
    required this.evaluator,
  }) : super(
         null, // declaration (will be parsed on demand)
         evaluator.globalEnvironment, // closureEnvironment
         strictMode: isStrict,
       );

  @override
  bool get isConstructor => true;

  @override
  int get parameterCount => parameterNames.length;

  @override
  String toString() {
    final params = parameterNames.join(', ');
    return 'function anonymous($params) {\n$bodyCode\n}';
  }

  /// Execute this function with the given arguments
  JSValue execute(List<JSValue> args, JSValue? thisBinding) {
    return evaluator.executeDynamicFunction(this, args, thisBinding);
  }
}

/// Global Function object with constructor and static methods
class FunctionGlobal {
  /// Function() constructor - creates a new function from code
  static JSValue constructor(List<JSValue> args, Environment env) {
    // Capture the current evaluator's global environment for GetFunctionRealm
    final currentEvaluator = JSEvaluator.currentInstance;

    if (args.isEmpty) {
      // new Function() without arguments returns an empty function
      final func = JSNativeFunction(
        functionName: 'anonymous',
        nativeImpl: (callArgs) => JSValueFactory.undefined(),
        isConstructor:
            true, // Functions created via Function() are constructors
      );
      // Store realm reference for GetFunctionRealm implementation
      if (currentEvaluator != null) {
        func.setInternalSlot('Realm', currentEvaluator);
      }
      return func;
    }

    // The last argument is the body, the others are parameters
    final body = args.last.toString();

    // Parse parameters - they can be separate arguments or comma-separated in a single arg
    final rawParameters = args.sublist(0, args.length - 1);
    final parameters = <String>[];

    for (final arg in rawParameters) {
      final paramStr = arg.toString().trim();
      // Split by comma if there are multiple params in one argument
      if (paramStr.contains(',')) {
        parameters.addAll(
          paramStr.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty),
        );
      } else if (paramStr.isNotEmpty) {
        parameters.add(paramStr);
      }
    }

    // Check if body contains "use strict" directive at the beginning
    final trimmedBody = body.trimLeft();
    final isStrictMode =
        trimmedBody.startsWith('"use strict"') ||
        trimmedBody.startsWith("'use strict'");

    // In strict mode, check for duplicate parameter names and reserved names
    if (isStrictMode) {
      final paramSet = <String>{};
      for (final param in parameters) {
        // Check for duplicate parameters
        if (paramSet.contains(param)) {
          throw JSSyntaxError(
            'Duplicate parameter name "$param" not allowed in strict mode',
          );
        }
        // Check for reserved names in strict mode
        if (param == 'eval' || param == 'arguments') {
          throw JSSyntaxError(
            'Parameter name "$param" not allowed in strict mode',
          );
        }
        paramSet.add(param);
      }
    }

    // Parse and execute the function body dynamically using the evaluator
    if (currentEvaluator != null) {
      // Create JSFunction that will parse and execute the body when called
      final func = DynamicFunction(
        parameterNames: parameters,
        bodyCode: body,
        isStrict: isStrictMode,
        evaluator: currentEvaluator,
      );
      // Store realm reference for GetFunctionRealm implementation
      func.setInternalSlot('Realm', currentEvaluator);
      return func;
    }

    // Fallback: return a function that returns undefined
    final func = JSNativeFunction(
      functionName: 'anonymous',
      nativeImpl: (callArgs) => JSValueFactory.undefined(),
      isConstructor: true,
    );
    if (currentEvaluator != null) {
      func.setInternalSlot('Realm', currentEvaluator);
    }
    return func;
  }

  /// Creates the global Function object
  static JSFunction createFunctionGlobal() {
    final func = JSNativeFunction(
      functionName: 'Function',
      nativeImpl: (args) => constructor(args, Environment.global()),
      expectedArgs: 1,
      isConstructor: true, // Function is a constructor
    );

    // Create Function.prototype with call, apply, bind methods
    final prototype = _createFunctionPrototypeObject();
    func.setProperty('prototype', prototype);

    // Set Function.prototype.constructor to point back to Function
    prototype.setProperty('constructor', func);

    // Set the static reference to Function.prototype on JSFunction
    JSFunction.setFunctionPrototype(prototype);

    return func;
  }

  /// Creates the Function.prototype object with all methods
  static JSObject _createFunctionPrototypeObject() {
    final prototype = JSObject();

    // Function.prototype.call - calls the function with a specified 'this'
    prototype.setProperty(
      'call',
      JSNativeFunction(
        functionName: 'call',
        nativeImpl: (args) =>
            FunctionPrototype.call(args, Environment.global()),
      ),
    );

    // Function.prototype.apply - comme call mais prend un tableau d'arguments
    prototype.setProperty(
      'apply',
      JSNativeFunction(
        functionName: 'apply',
        nativeImpl: (args) =>
            FunctionPrototype.apply(args, Environment.global()),
      ),
    );

    // Function.prototype.bind - creates a new function with 'this' bound
    prototype.setProperty(
      'bind',
      JSNativeFunction(
        functionName: 'bind',
        nativeImpl: (args) =>
            FunctionPrototype.bind(args, Environment.global()),
      ),
    );

    // Function.prototype.toString
    prototype.setProperty(
      'toString',
      JSNativeFunction(
        functionName: 'toString',
        nativeImpl: (args) =>
            FunctionPrototype.functionToString(args, Environment.global()),
      ),
    );

    // Function.prototype.constructor pointe vers Function
    // Will be set after initialization

    return prototype;
  }

  /// Creates the call method for functions
  static JSNativeFunction createCallMethod() {
    return JSNativeFunction(
      functionName: 'call',
      nativeImpl: (args) {
        // Implementation of function.call()
        if (args.isEmpty) return JSValueFactory.undefined();

        // Le premier argument est 'this', les autres sont les arguments de fonction
        // Note: Full implementation would require access to the evaluator
        return JSValueFactory.undefined();
      },
    );
  }

  /// Creates the apply method for functions
  static JSNativeFunction createApplyMethod() {
    return JSNativeFunction(
      functionName: 'apply',
      nativeImpl: (args) {
        // Implementation of function.apply()
        // Note: Full implementation would require access to the evaluator
        return JSValueFactory.undefined();
      },
    );
  }

  /// Creates the bind method for functions
  static JSNativeFunction createBindMethod() {
    return JSNativeFunction(
      functionName: 'bind',
      nativeImpl: (args) {
        // Implementation of function.bind()
        // Note: Full implementation would require access to the evaluator
        return JSValueFactory.undefined();
      },
    );
  }
}
