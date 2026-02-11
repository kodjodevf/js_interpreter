/// System of native functions
///
/// but exposed as normal JavaScript functions
library;

import 'js_value.dart';
import '../evaluator/evaluator.dart';

/// Type of native function
typedef NativeFunction = JSValue Function(List<JSValue> args);

/// Native JavaScript function
class JSNativeFunction extends JSFunction {
  @override
  final String functionName;
  final NativeFunction nativeImpl;
  final int expectedArgs;

  /// If true, the function already has its context (this) bound via closure,
  /// so callWithThis should NOT prepend thisBinding to args
  final bool hasContextBound;

  /// If true, this function can be called with 'new' (is a constructor)
  /// Default is false for most native functions as per ES6 spec
  final bool _isConstructorInternal;

  /// If true, this is an async function and needs thisBinding passed through executor
  final bool isAsync;

  /// Track if 'name' property has been deleted
  bool _nameDeleted = false;

  /// Track if 'length' property has been deleted
  bool _lengthDeleted = false;

  JSNativeFunction({
    required this.functionName,
    required this.nativeImpl,
    this.expectedArgs = -1, // -1 = variadic
    this.hasContextBound = false,
    bool isConstructor = false, // Default: not a constructor
    this.isAsync = false, // Default: not async
    JSObject? functionPrototype, // Add optional prototype parameter
  }) : _isConstructorInternal = isConstructor,
       super(
         null,
         null,
         functionPrototype: functionPrototype,
       ); // Pass prototype to super

  @override
  bool get isConstructor => _isConstructorInternal;

  @override
  JSValue getProperty(String name) {
    // Allow 'prototype' property if it has been explicitly set, even for non-constructors
    // This allows Symbol and other non-constructor functions to have a prototype with methods
    if (name == 'prototype') {
      // Check if the property was explicitly set (in _properties)
      final explicitPrototype = super.getProperty(name);
      if (!explicitPrototype.isUndefined) {
        return explicitPrototype;
      }
      // Only return undefined if it wasn't explicitly set and this is not a constructor
      if (!isConstructor) {
        return JSValueFactory.undefined();
      }
    }
    // Override length to return expectedArgs if specified
    if (name == 'length' && expectedArgs >= 0 && !_lengthDeleted) {
      return JSValueFactory.number(expectedArgs.toDouble());
    }
    // Override name to return functionName
    if (name == 'name' && !_nameDeleted) {
      return JSValueFactory.string(functionName);
    }
    // Override hasOwnProperty to use our custom implementation
    if (name == 'hasOwnProperty') {
      // Capture this instance for the closure
      final thisInstance = this;
      return JSNativeFunction(
        functionName: 'hasOwnProperty',
        nativeImpl: (args) {
          String propName;
          if (args.length >= 2) {
            // Called with this binding: hasOwnProperty(thisObj, propName)
            propName = args[1].toString();
          } else if (args.length == 1) {
            propName = args[0].toString();
          } else {
            return JSValueFactory.boolean(false);
          }
          // Use the captured instance's hasOwnProperty method
          return JSValueFactory.boolean(thisInstance.hasOwnProperty(propName));
        },
      );
    }
    return super.getProperty(name);
  }

  /// Check if this function has the specified own property
  bool hasOwnProperty(String name) {
    // Non-constructor functions should not have a 'prototype' property
    if (name == 'prototype' && !isConstructor) {
      return false;
    }
    // Handle 'name' and 'length' specially - they have deleted flags
    if (name == 'name') return !_nameDeleted;
    if (name == 'length') return !_lengthDeleted;
    // For other properties, check parent's _properties (but exclude 'name' and 'length')
    if (super.containsOwnProperty(name) && name != 'name' && name != 'length') {
      return true;
    }
    return false;
  }

  /// Delete a property from this function (ES5 [[Delete]])
  @override
  bool deleteProperty(String name) {
    // Check if property is configurable
    if (name == 'name') {
      // 'name' is configurable, so allow deletion
      _nameDeleted = true;
      return true;
    }
    if (name == 'length') {
      // 'length' is configurable, so allow deletion
      _lengthDeleted = true;
      return true;
    }
    // For other properties, check if configurable and delete from parent's _properties
    final desc = getOwnPropertyDescriptor(name);
    if (desc != null) {
      if (desc.configurable) {
        return super.removeOwnProperty(name);
      } else {
        // Property exists but is not configurable - deletion fails
        return false;
      }
    }
    // Property doesn't exist - deletion succeeds
    return true;
  }

  @override
  PropertyDescriptor? getOwnPropertyDescriptor(String name) {
    // length: writable: false, enumerable: false, configurable: true
    if (name == 'length' && !_lengthDeleted) {
      return PropertyDescriptor(
        value: expectedArgs >= 0
            ? JSValueFactory.number(expectedArgs.toDouble())
            : JSValueFactory.number(0),
        writable: false,
        enumerable: false,
        configurable: true,
      );
    }
    // name: writable: false, enumerable: false, configurable: true
    if (name == 'name' && !_nameDeleted) {
      return PropertyDescriptor(
        value: JSValueFactory.string(functionName),
        writable: false,
        enumerable: false,
        configurable: true,
      );
    }
    return super.getOwnPropertyDescriptor(name);
  }

  /// Get all property names for this native function
  /// Note: This doesn't override a parent method, JSFunction doesn't provide this
  List<String> getPropertyNames({bool enumerableOnly = false}) {
    // For built-in functions, property names must appear in specific order:
    // 1. "length" (if not deleted)
    // 2. "name" (if not deleted)
    // 3. All other properties from parent
    // Note: "prototype" should NOT be included for non-constructor functions

    final names = <String>[];

    // Add "length" first (it's always non-enumerable but configurable)
    if (!_lengthDeleted) {
      names.add('length');
    }

    // Add "name" second (it's always non-enumerable but configurable)
    if (!_nameDeleted) {
      names.add('name');
    }

    // Note: Constructors have a "prototype" property, but non-constructors don't
    if (isConstructor) {
      final prototypeObj = getProperty('prototype');
      if (prototypeObj is JSObject &&
          prototypeObj.hasOwnProperty('constructor')) {
        // Prototype property is present for constructors
        names.add('prototype');
      }
    }

    // Return just length, name, and optionally prototype for built-in functions
    return names;
  }

  /// Call native function with argument conversion
  JSValue call(List<JSValue> args) {
    try {
      return nativeImpl(args);
    } catch (e) {
      // Let JavaScript errors pass through directly without wrapping
      if (e is JSError) {
        rethrow;
      }
      // Let standard exceptions pass through for tests
      if (e is Exception) {
        rethrow;
      }
      throw JSError('Native function error in $functionName: $e');
    }
  }

  /// Call native function with specific this context
  JSValue callWithThis(List<JSValue> args, JSValue thisBinding) {
    // If this function already has context bound (e.g., from getArrayProperty),
    // don't prepend thisBinding
    if (hasContextBound) {
      return call(args);
    }

    // For constructor functions called with an existing instance (via super()),
    // pass the instance as the first argument so it can be initialized
    if (isConstructor &&
        thisBinding is JSObject &&
        !thisBinding.isNull &&
        !thisBinding.isUndefined) {
      final argsWithThis = [thisBinding, ...args];
      return call(argsWithThis);
    }

    // For Object.prototype methods that need this binding,
    // add thisBinding as first argument
    if (_needsThisBinding(thisBinding)) {
      final argsWithThis = [thisBinding, ...args];
      return call(argsWithThis);
    }

    // For other native functions, ignore this binding
    return call(args);
  }

  /// Check if this native function needs this binding
  bool _needsThisBinding(JSValue thisBinding) {
    // Getters need thisBinding (functions starting with "get ")
    if (functionName.startsWith('get ')) {
      return true;
    }

    const thisBindingMethods = {
      'hasOwnProperty',
      'isPrototypeOf',
      'propertyIsEnumerable',
      'valueOf',
      'toString',
      'toLocaleString',
      // Function.prototype methods that need the function as first arg
      'call',
      'apply',
      'bind',
      // Array methods that get 'this' as first argument (like join)
      'join',
      'push',
      'pop',
      'shift',
      'unshift',
      'concat',
      // Array static methods that need this binding for custom constructors
      'of',
      'from',
      // Array methods that support .call() with array-like objects
      // Note: flatMap is NOT here because its first arg is a callback, not thisArg
      'flat',
      // Array methods that take callback as first arg but support .call()
      // These methods detect .call() by checking if first arg is not a function
      'forEach',
      'map',
      'filter',
      'some',
      'every',
      'find',
      'findIndex',
      'reduce',
      'reduceRight',
      // Promise methods
      'then',
      'catch',
      'finally',
      'Promise.prototype.then',
      'Promise.prototype.catch',
      'Promise.prototype.finally',
      // Array methods that support array-like objects via .call()
      'indexOf',
      'lastIndexOf',
      'includes',
      'at',
      'reverse',
      'fill',
      'copyWithin',
    };

    if (thisBindingMethods.contains(functionName)) {
      return true;
    }

    return false;
  }
}

class JSConversion {
  /// Convert JSValue to string
  static String jsToString(JSValue value) {
    switch (value.type) {
      case JSValueType.undefined:
        return 'undefined';
      case JSValueType.nullType:
        return 'null';
      case JSValueType.boolean:
        return (value as JSBoolean).value ? 'true' : 'false';
      case JSValueType.number:
        final num = (value as JSNumber).value;
        // Reproduce number formatting
        if (num.isNaN) return 'NaN';
        if (num.isInfinite) return num.isNegative ? '-Infinity' : 'Infinity';
        if (num == num.toInt()) return num.toInt().toString();
        return num.toString();
      case JSValueType.string:
        return (value as JSString).value;
      case JSValueType.object:
        // Handle wrapper objects: Boolean, Number, String
        if (value is JSBooleanObject) {
          return value.primitiveValue ? 'true' : 'false';
        }
        if (value is JSNumberObject) {
          final num = value.primitiveValue;
          if (num.isNaN) return 'NaN';
          if (num.isInfinite) return num.isNegative ? '-Infinity' : 'Infinity';
          if (num == num.toInt()) return num.toInt().toString();
          return num.toString();
        }
        if (value is JSStringObject) {
          return value.value;
        }
        if (value is JSObject) {
          // Try to call toString() method for ToPrimitive(hint: string)
          final toStringMethod = value.getProperty('toString');
          if (toStringMethod is JSFunction ||
              toStringMethod is JSNativeFunction) {
            final evaluator = JSEvaluator.currentInstance;
            if (evaluator != null) {
              // Call toString() - let exceptions propagate
              final result = toStringMethod is JSNativeFunction
                  ? toStringMethod.call([value])
                  : evaluator.callFunction(toStringMethod, [], value);
              // If toString returns a primitive, use it
              if (result.isString) {
                return result.toString();
              } else if (result.isNumber ||
                  result.isBoolean ||
                  result.isNull ||
                  result.isUndefined) {
                // Recursively convert the primitive result
                return jsToString(result);
              }
              // If toString returns an object, try valueOf
              final valueOfMethod = value.getProperty('valueOf');
              if (valueOfMethod is JSFunction ||
                  valueOfMethod is JSNativeFunction) {
                final valueOfResult = valueOfMethod is JSNativeFunction
                    ? valueOfMethod.call([value])
                    : evaluator.callFunction(valueOfMethod, [], value);
                if (valueOfResult.isString ||
                    valueOfResult.isNumber ||
                    valueOfResult.isBoolean ||
                    valueOfResult.isNull ||
                    valueOfResult.isUndefined) {
                  return jsToString(valueOfResult);
                }
                // Both toString and valueOf returned non-primitives
                throw JSTypeError('Cannot convert object to primitive value');
              }
            }
          } else {
            // toString doesn't exist or is not a function. Try valueOf.
            final valueOfMethod = value.getProperty('valueOf');
            if (valueOfMethod is JSFunction ||
                valueOfMethod is JSNativeFunction) {
              final evaluator = JSEvaluator.currentInstance;
              if (evaluator != null) {
                final valueOfResult = valueOfMethod is JSNativeFunction
                    ? valueOfMethod.call([value])
                    : evaluator.callFunction(valueOfMethod, [], value);
                if (valueOfResult.isString ||
                    valueOfResult.isNumber ||
                    valueOfResult.isBoolean ||
                    valueOfResult.isNull ||
                    valueOfResult.isUndefined) {
                  return jsToString(valueOfResult);
                }
                // valueOf returned non-primitive, throw error
                throw JSTypeError('Cannot convert object to primitive value');
              }
            }
            // Neither toString nor valueOf exist or are callable
            // This happens with Object.create(null) which has no prototype
            throw JSTypeError('Cannot convert object to primitive value');
          }
          return '[object Object]';
        }
        return '[object Object]';
      case JSValueType.function:
        // Functions are objects and can have custom toString/valueOf
        final func = value as JSFunction;
        // Check if this function has custom toString/valueOf (from user assignment)
        final toStringMethod = func.getProperty('toString');
        final evaluator = JSEvaluator.currentInstance;
        if (evaluator != null) {
          // Check if toString returns a primitive or object
          if (toStringMethod is JSFunction ||
              toStringMethod is JSNativeFunction) {
            final result = toStringMethod is JSNativeFunction
                ? toStringMethod.call([func])
                : evaluator.callFunction(toStringMethod, [], func);
            // If toString returns a primitive, use it
            if (result.isString) {
              return result.toString();
            } else if (result.isNumber ||
                result.isBoolean ||
                result.isNull ||
                result.isUndefined) {
              return jsToString(result);
            }
            // If toString returns an object, try valueOf
            final valueOfMethod = func.getProperty('valueOf');
            if (valueOfMethod is JSFunction ||
                valueOfMethod is JSNativeFunction) {
              final valueOfResult = valueOfMethod is JSNativeFunction
                  ? valueOfMethod.call([func])
                  : evaluator.callFunction(valueOfMethod, [], func);
              if (valueOfResult.isString ||
                  valueOfResult.isNumber ||
                  valueOfResult.isBoolean ||
                  valueOfResult.isNull ||
                  valueOfResult.isUndefined) {
                return jsToString(valueOfResult);
              }
              // Both toString and valueOf returned non-primitives
              throw JSTypeError('Cannot convert object to primitive value');
            }
          }
        }
        // Fall back to default function toString
        return func.toString();
      default:
        return value.toString();
    }
  }

  /// Convert array to string
  static String arrayToString(JSArray array) {
    final elements = <String>[];
    for (int i = 0; i < array.length; i++) {
      final element = array.get(i);
      if (element.isNull || element.isUndefined) {
        // null and undefined elements are converted to empty string in array.toString()
        elements.add('');
      } else {
        elements.add(jsToString(element));
      }
    }
    // Use comma without space (matching JavaScript Array.prototype.toString())
    return elements.join(',');
  }

  /// Convert JSValue to number
  static double toNumber(JSValue value) {
    return value.toNumber();
  }

  /// Convert JSValue to number with correct ToPrimitive
  /// Handle objects with valueOf/toString via evaluator
  static double jsToNumber(JSValue value) {
    switch (value.type) {
      case JSValueType.undefined:
        return double.nan;
      case JSValueType.nullType:
        return 0.0;
      case JSValueType.boolean:
        return (value as JSBoolean).value ? 1.0 : 0.0;
      case JSValueType.number:
        return (value as JSNumber).value;
      case JSValueType.symbol:
        // ES6: Symbol values throw TypeError in ToNumber
        throw JSTypeError('Cannot convert a Symbol value to a number');
      case JSValueType.string:
        final str = (value as JSString).value.trim();
        if (str.isEmpty) return 0.0;
        if (str == 'Infinity') return double.infinity;
        if (str == '-Infinity') return double.negativeInfinity;
        return double.tryParse(str) ?? double.nan;
      case JSValueType.object:
        // Handle wrapper objects
        if (value is JSNumberObject) {
          return value.primitiveValue;
        }
        if (value is JSBooleanObject) {
          return value.primitiveValue ? 1.0 : 0.0;
        }
        if (value is JSStringObject) {
          final str = value.value.trim();
          if (str.isEmpty) return 0.0;
          return double.tryParse(str) ?? double.nan;
        }

        // For general objects, use ToPrimitive with hint "number"
        if (value is JSObject) {
          final evaluator = JSEvaluator.currentInstance;
          if (evaluator != null) {
            // 1. Try valueOf() first (hint: number)
            final valueOfMethod = value.getProperty('valueOf');
            if (valueOfMethod is JSFunction ||
                valueOfMethod is JSNativeFunction) {
              final valueOfResult = valueOfMethod is JSNativeFunction
                  ? valueOfMethod.call([value])
                  : evaluator.callFunction(valueOfMethod, [], value);

              // If valueOf returns a primitive, convert it to number
              if (valueOfResult is! JSObject ||
                  valueOfResult is JSNull ||
                  valueOfResult is JSUndefined) {
                return jsToNumber(valueOfResult);
              }
            }

            // 2. Try toString() next
            final toStringMethod = value.getProperty('toString');
            if (toStringMethod is JSFunction ||
                toStringMethod is JSNativeFunction) {
              final toStringResult = toStringMethod is JSNativeFunction
                  ? toStringMethod.call([value])
                  : evaluator.callFunction(toStringMethod, [], value);

              if (toStringResult is! JSObject ||
                  toStringResult is JSNull ||
                  toStringResult is JSUndefined) {
                return jsToNumber(toStringResult);
              }
            }

            // 3. If both valueOf and toString returned non-primitives, throw TypeError
            throw JSTypeError('Cannot convert object to primitive value');
          }
        }

        // If ToPrimitive fails (no evaluator), return NaN
        return double.nan;
      case JSValueType.function:
        return double.nan;
      default:
        return double.nan;
    }
  }

  /// Convertit une JSValue en boolean
  static bool toBool(JSValue value) {
    return value.toBoolean();
  }
}

/// Console object implementation
class ConsoleObject {
  static JSValue log(List<JSValue> args) {
    final output = <String>[];

    for (final arg in args) {
      output.add(JSConversion.jsToString(arg));
    }

    // Display on stdout
    print(output.join(' '));

    return JSValueFactory.undefined();
  }

  /// console.error() - to stderr
  static JSValue error(List<JSValue> args) {
    final output = <String>[];

    for (final arg in args) {
      output.add(JSConversion.jsToString(arg));
    }

    // In Dart, no direct stderr, we use print with a prefix
    print('ERROR: ${output.join(' ')}');

    return JSValueFactory.undefined();
  }

  /// console.warn() - warning
  static JSValue warn(List<JSValue> args) {
    final output = <String>[];

    for (final arg in args) {
      output.add(JSConversion.jsToString(arg));
    }

    print('WARNING: ${output.join(' ')}');

    return JSValueFactory.undefined();
  }

  /// Create console object with all its methods
  static JSObject createConsoleObject() {
    final console = JSObject();

    // Add methods as properties
    console.setProperty(
      'log',
      JSNativeFunction(functionName: 'log', nativeImpl: log),
    );

    console.setProperty(
      'error',
      JSNativeFunction(functionName: 'error', nativeImpl: error),
    );

    console.setProperty(
      'warn',
      JSNativeFunction(functionName: 'warn', nativeImpl: warn),
    );

    return console;
  }
}

/// Type of native function qui accepte thisBinding en premier argument
typedef PromiseNativeFunction =
    JSValue Function(List<JSValue> args, JSValue thisBinding);

/// Specialized class for Promise static methods
/// that validate `this` binding and pass it to nativeImpl
class PromiseStaticMethod extends JSNativeFunction {
  final PromiseNativeFunction? promiseNativeImpl;
  final bool isCtorFn;

  PromiseStaticMethod({
    required super.functionName,
    NativeFunction? nativeImpl,
    this.promiseNativeImpl,
    required super.expectedArgs,
    this.isCtorFn = true,
  }) : super(nativeImpl: nativeImpl ?? (args) => JSValueFactory.undefined());

  @override
  bool get isConstructor => isCtorFn;

  @override
  JSValue callWithThis(List<JSValue> args, JSValue thisBinding) {
    // ES6 Spec 25.4.4.3: If Type(C) is not Object, throw a TypeError exception.
    // This applies to Promise.resolve, Promise.reject, Promise.all, Promise.race, etc.

    // Reject if this is undefined or null (not objects)
    if (thisBinding is JSUndefined || thisBinding is JSNull) {
      throw JSTypeError('Promise.$functionName called on non-object');
    }

    // Reject if this is a primitive (number, string, boolean, symbol)
    if (thisBinding is JSNumber ||
        thisBinding is JSString ||
        thisBinding is JSBoolean ||
        thisBinding.isSymbol) {
      throw JSTypeError('Promise.$functionName called on non-object');
    }

    // If this is a function, it must be a constructor
    if (thisBinding is JSFunction) {
      if (thisBinding is JSNativeFunction && !thisBinding.isConstructor) {
        // Non-constructor native function (like eval)
        throw JSTypeError('Promise.$functionName invoked on non-constructor');
      }
    }

    // thisBinding should be an object (function or regular object)
    // ES6 allows calling Promise.resolve/reject on any object

    // If we have a promise-specific impl, call it with thisBinding
    if (promiseNativeImpl != null) {
      return promiseNativeImpl!(args, thisBinding);
    }

    return call(args);
  }
}
