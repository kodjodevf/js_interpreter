/// System of JavaScript values
///
/// This file implements the tagged union system to represent
/// all JavaScript values.
library;

import 'date_object.dart';
import 'error_object.dart';
import 'js_regexp.dart';
import 'js_symbol.dart';
import 'native_functions.dart';
import 'array_prototype.dart';
import 'string_prototype.dart';
import 'iterator_protocol.dart';
import 'environment.dart';
import 'function_prototype.dart';
import 'prototype_manager.dart';
import '../evaluator/evaluator.dart';
import '../parser/ast_nodes.dart';

/// Base JavaScript types according to ECMAScript
enum JSValueType {
  undefined,
  nullType,
  boolean,
  number,
  string,
  object,
  function,
  symbol,
  bigint,
}

/// Abstract base class for all JavaScript values
abstract class JSValue {
  JSValueType get type;

  /// Get the underlying primitive value
  dynamic get primitiveValue;

  /// JavaScript type conversions (coercion)
  bool toBoolean();
  double toNumber();
  @override
  String toString();
  JSObject toObject();

  /// Comparison operations
  bool equals(JSValue other);
  bool strictEquals(JSValue other);

  /// Type checks
  bool get isUndefined => type == JSValueType.undefined;
  bool get isNull => type == JSValueType.nullType;
  bool get isBoolean => type == JSValueType.boolean;
  bool get isNumber => type == JSValueType.number;
  bool get isString => type == JSValueType.string;
  bool get isObject => type == JSValueType.object;
  bool get isFunction => type == JSValueType.function;
  bool get isSymbol => type == JSValueType.symbol;
  bool get isBigInt => type == JSValueType.bigint;

  /// Check if value is "primitive" (non-object)
  bool get isPrimitive =>
      type != JSValueType.object && type != JSValueType.function;

  /// Check if value is "truthy"
  bool get isTruthy => toBoolean();

  /// Check if value is "falsy"
  bool get isFalsy => !toBoolean();

  @override
  bool operator ==(Object other) {
    if (other is JSValue) {
      return equals(other);
    }
    return false;
  }

  @override
  int get hashCode {
    // Use the type and primitive value for the hash
    return Object.hash(type, primitiveValue);
  }
}

/// Undefined value
class JSUndefined extends JSValue {
  static final JSUndefined instance = JSUndefined._();
  JSUndefined._();

  @override
  JSValueType get type => JSValueType.undefined;

  @override
  dynamic get primitiveValue => null;

  @override
  bool toBoolean() => false;

  @override
  double toNumber() => double.nan;

  @override
  String toString() => 'undefined';

  @override
  JSObject toObject() =>
      throw JSTypeError('Cannot convert undefined to object');

  @override
  bool equals(JSValue other) => other.isNull || other.isUndefined;

  @override
  bool strictEquals(JSValue other) => other.isUndefined;
}

/// Null value
class JSNull extends JSValue {
  static final JSNull instance = JSNull._();
  JSNull._();

  @override
  JSValueType get type => JSValueType.nullType;

  @override
  dynamic get primitiveValue => null;

  @override
  bool toBoolean() => false;

  @override
  double toNumber() => 0.0;

  @override
  String toString() => 'null';

  @override
  JSObject toObject() => throw JSTypeError('Cannot convert null to object');

  @override
  bool equals(JSValue other) => other.isNull || other.isUndefined;

  @override
  bool strictEquals(JSValue other) => other.isNull;
}

/// Boolean value
class JSBoolean extends JSValue {
  static final JSBoolean trueValue = JSBoolean._(true);
  static final JSBoolean falseValue = JSBoolean._(false);

  final bool value;

  JSBoolean._(this.value);

  factory JSBoolean(bool value) => value ? trueValue : falseValue;

  @override
  JSValueType get type => JSValueType.boolean;

  @override
  dynamic get primitiveValue => value;

  @override
  bool toBoolean() => value;

  @override
  double toNumber() => value ? 1.0 : 0.0;

  @override
  String toString() => value ? 'true' : 'false';

  @override
  JSObject toObject() => JSBooleanObject(value);

  @override
  bool equals(JSValue other) {
    if (other.isBoolean) return value == (other as JSBoolean).value;
    if (other.isNumber) return toNumber() == other.toNumber();
    if (other.isString) return toString() == other.toString();
    return false;
  }

  @override
  bool strictEquals(JSValue other) =>
      other.isBoolean && value == (other as JSBoolean).value;
}

/// Number value
class JSNumber extends JSValue {
  final double value;

  JSNumber(this.value);

  @override
  JSValueType get type => JSValueType.number;

  @override
  dynamic get primitiveValue => value;

  @override
  bool toBoolean() => value != 0.0 && !value.isNaN;

  @override
  double toNumber() => value;

  @override
  String toString() {
    if (value.isNaN) return 'NaN';
    if (value.isInfinite) return value.isNegative ? '-Infinity' : 'Infinity';
    // Check if it's a safe integer (can be represented exactly as int)
    // Only truncate for values within safe integer range to avoid overflow
    if (value == value.truncateToDouble() && value.abs() <= 9007199254740991) {
      // Number.MAX_SAFE_INTEGER
      return value.truncate().toString();
    }
    return value.toString();
  }

  @override
  JSObject toObject() => JSNumberObject(value);

  @override
  bool equals(JSValue other) {
    if (other.isNumber) {
      final otherValue = (other as JSNumber).value;
      if (value.isNaN && otherValue.isNaN) return false; // NaN != NaN
      return value == otherValue;
    }
    if (other.isBigInt) {
      // Delegate to BigInt's equals method for proper comparison
      return other.equals(this);
    }
    if (other.isString) return value == other.toNumber();
    if (other.isBoolean) return value == other.toNumber();
    return false;
  }

  @override
  bool strictEquals(JSValue other) =>
      other.isNumber && value == (other as JSNumber).value;
}

/// String value
class JSString extends JSValue {
  final String value;

  JSString(this.value);

  @override
  JSValueType get type => JSValueType.string;

  @override
  dynamic get primitiveValue => value;

  @override
  bool toBoolean() => value.isNotEmpty;

  @override
  double toNumber() {
    if (value.isEmpty) return 0.0;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 0.0;
    if (trimmed == 'Infinity') return double.infinity;
    if (trimmed == '-Infinity') return double.negativeInfinity;

    // Handle numeric prefixes like JavaScript does
    if (trimmed.startsWith('0b') || trimmed.startsWith('0B')) {
      // Binary literal
      final binaryPart = trimmed.substring(2);
      return int.tryParse(binaryPart, radix: 2)?.toDouble() ?? double.nan;
    } else if (trimmed.startsWith('0o') || trimmed.startsWith('0O')) {
      // Octal literal
      final octalPart = trimmed.substring(2);
      return int.tryParse(octalPart, radix: 8)?.toDouble() ?? double.nan;
    } else if (trimmed.startsWith('0x') || trimmed.startsWith('0X')) {
      // Hexadecimal literal
      final hexPart = trimmed.substring(2);
      return int.tryParse(hexPart, radix: 16)?.toDouble() ?? double.nan;
    }

    return double.tryParse(trimmed) ?? double.nan;
  }

  @override
  String toString() => value;

  @override
  JSObject toObject() => JSStringObject(value);

  @override
  bool equals(JSValue other) {
    if (other.isString) return value == (other as JSString).value;
    if (other.isNumber) return toNumber() == other.toNumber();
    if (other.isBoolean) return toNumber() == other.toNumber();
    return false;
  }

  @override
  bool strictEquals(JSValue other) =>
      other.isString && value == (other as JSString).value;

  /// String iteration support for primitive strings
  JSStringIterator getIterator() => JSStringIterator(value);
}

/// Representation of a JavaScript BigInt
class JSBigInt extends JSValue {
  final BigInt value;

  JSBigInt(this.value);

  @override
  JSValueType get type => JSValueType.bigint;

  @override
  dynamic get primitiveValue => value;

  @override
  bool toBoolean() => value != BigInt.zero;

  @override
  double toNumber() {
    // BigInt to Number: always convert, even with precision loss
    return value.toDouble();
  }

  @override
  String toString() => '${value}n';

  @override
  JSObject toObject() => JSBigIntObject(value);

  @override
  bool equals(JSValue other) {
    if (other.isBigInt) return value == (other as JSBigInt).value;
    if (other.isNumber) {
      final otherNum = other.toNumber();
      if (otherNum.isInfinite || otherNum.isNaN) return false;

      // Check if it's an integer
      if (otherNum % 1 != 0) return false;

      // For large numbers, use string-based conversion to avoid precision loss
      if (otherNum.abs() > 9007199254740991) {
        // Number.MAX_SAFE_INTEGER
        final exp = otherNum.toStringAsExponential();
        final parts = exp.split('e');
        final mantissa = parts[0].replaceAll('.', '');
        final exponent = int.parse(parts[1]);
        final decimalPlaces = parts[0].contains('.')
            ? parts[0].split('.')[1].length
            : 0;
        final bigMantissa = BigInt.parse(mantissa);
        final otherBigInt =
            bigMantissa * BigInt.from(10).pow(exponent - decimalPlaces);
        return value == otherBigInt;
      }

      return value == BigInt.from(otherNum.toInt());
    }
    if (other.isString) {
      try {
        final otherBigInt = BigInt.parse(other.toString());
        return value == otherBigInt;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  @override
  bool strictEquals(JSValue other) =>
      other.isBigInt && value == (other as JSBigInt).value;
}

/// Base exception for JavaScript errors
class JSError extends Error {
  final String message;
  final String name;

  JSError(this.message, {this.name = 'Error'});

  @override
  String toString() => '$name: $message';
}

/// JavaScript TypeError - for operations on wrong types
class JSTypeError extends JSError {
  JSTypeError(super.message) : super(name: 'TypeError');
}

/// JavaScript ReferenceError - for undefined variables
class JSReferenceError extends JSError {
  JSReferenceError(super.message) : super(name: 'ReferenceError');
}

/// JavaScript SyntaxError - for parsing
class JSSyntaxError extends JSError {
  JSSyntaxError(super.message) : super(name: 'SyntaxError');
}

/// JavaScript RangeError - for out of range values
class JSRangeError extends JSError {
  JSRangeError(super.message) : super(name: 'RangeError');
}

/// JavaScript URIError - for invalid URI operations
class JSURIError extends JSError {
  JSURIError(super.message) : super(name: 'URIError');
}

/// AggregateError ES2021 - error containing multiple errors
class JSAggregateError extends JSError {
  final List<JSValue> errors;

  JSAggregateError(this.errors, [String? message])
    : super(message ?? 'All promises were rejected', name: 'AggregateError');

  @override
  String toString() {
    final errorCount = errors.length;
    return '$name: $message ($errorCount error${errorCount != 1 ? 's' : ''})';
  }
}

/// JavaScript Exception - for errors thrown by throw
/// This class represents JavaScript exceptions that can be caught by catch
class JSException extends JSError implements Exception {
  final JSValue value; // The value thrown (can be any JSValue)

  JSException(this.value)
    : super(_getErrorMessage(value), name: _getErrorName(value));

  static String _getErrorMessage(JSValue value) {
    if (value is JSString) {
      return value.value;
    } else if (value is JSObject) {
      // If it's a JavaScript Error object, get the message
      final message = value.getProperty('message');
      if (!message.isUndefined) {
        return message.toString();
      }
    }
    return value.toString();
  }

  static String _getErrorName(JSValue value) {
    if (value is JSObject) {
      // If it's a JavaScript Error object, get the name
      final name = value.getProperty('name');
      if (!name.isUndefined) {
        return name.toString();
      }
    }
    return 'Error';
  }

  /// Convert this exception to JSValue to be caught by catch
  JSValue toJSValue() => value;
}

/// JavaScript property descriptor for managing getters/setters
class PropertyDescriptor {
  JSValue? value;
  JSFunction? getter;
  JSFunction? setter;
  bool configurable;
  bool enumerable;
  bool writable;

  /// Track whether 'value' property was explicitly provided in the descriptor
  /// This distinguishes {configurable: true} from {value: undefined, configurable: true}
  bool hasValueProperty;

  PropertyDescriptor({
    this.value,
    this.getter,
    this.setter,
    this.configurable = true,
    this.enumerable = true,
    this.writable = true,
    this.hasValueProperty = true,
  });

  bool get isAccessor => getter != null || setter != null;
  bool get isData => value != null;
}

/// Mapped arguments object for non-strict functions with simple parameters
/// In ES5, when a function has simple (non-rest, non-destructured) parameters,
/// the arguments object is "mapped" - changes to arguments[i] also change the parameter,
/// and vice versa. This only applies in non-strict mode.
class JSMappedArguments extends JSObject {
  // Maps parameter indices to their names for synchronization
  final Map<int, String> parameterNames;

  // Reference to the function environment where parameters are stored
  final Environment functionEnv;

  JSMappedArguments({
    required this.parameterNames,
    required this.functionEnv,
    super.prototype,
  }) {
    // Mark this as an arguments object so that callee/caller access throws
    markAsArgumentsObject();
  }

  @override
  JSValue getProperty(String name) {
    // Check if this is a numeric index that's mapped to a parameter
    final index = int.tryParse(name);
    if (index != null && parameterNames.containsKey(index)) {
      final paramName = parameterNames[index]!;
      try {
        // Get the current value from the function environment
        return functionEnv.get(paramName);
      } catch (e) {
        // If parameter doesn't exist, fall back to regular property
        return super.getProperty(name);
      }
    }

    // For non-numeric properties or unmapped indices, use regular lookup
    return super.getProperty(name);
  }

  @override
  void setProperty(String name, JSValue value) {
    // Check if this is a numeric index that's mapped to a parameter
    final index = int.tryParse(name);
    if (index != null && parameterNames.containsKey(index)) {
      final paramName = parameterNames[index]!;
      try {
        // Set the value in the function environment (this also updates the parameter)
        functionEnv.set(paramName, value);
        return;
      } catch (e) {
        // If parameter doesn't exist, fall back to regular property
        super.setProperty(name, value);
        return;
      }
    }

    // For non-numeric properties or unmapped indices, use regular setProperty
    super.setProperty(name, value);
  }
}

/// Classes for wrapper objects (forward declarations)
class JSObject extends JSValue {
  // Map of properties
  final Map<String, JSValue> _properties = {};

  // Separate map for getters/setters
  final Map<String, PropertyDescriptor> _accessorProperties = {};

  // Flag to mark this object as an arguments object
  bool _isArgumentsObject = false;

  // Map to store descriptors of ALL properties (data + accessors)
  final Map<String, PropertyDescriptor> _propertyDescriptors = {};

  // ES6: Map to track symbol properties separately
  // Maps from symbol's string key to the actual JSSymbol instance
  final Map<String, JSSymbol> _symbolKeys = {};

  // Internal slots for ES6+ (e.g., [[PromiseState]], [[PromiseInstance]])
  final Map<String, dynamic> _internalSlots = {};

  // Reference to parent prototype (prototype chain)
  JSObject? _prototype;

  // Default constructor with Object.prototype as prototype
  JSObject({JSObject? prototype}) {
    if (prototype != null) {
      _prototype = prototype;
    } else {
      // This case should only be used for Object.create(null)
      // By default, use Object.prototype
      _prototype = objectPrototype; // Use getter instead of static field
    }
  }

  // Special constructor for Object.create(null)
  JSObject.withoutPrototype() : _prototype = null;

  /// Get an internal slot value
  dynamic getInternalSlot(String name) {
    return _internalSlots[name];
  }

  /// Set an internal slot value
  void setInternalSlot(String name, dynamic value) {
    _internalSlots[name] = value;
  }

  /// Check if an internal slot exists
  bool hasInternalSlot(String name) {
    return _internalSlots.containsKey(name);
  }

  // Singleton for Object.prototype (the root prototype)
  // DEPRECATED: Use PrototypeManager.current.objectPrototype instead
  static JSObject? _objectPrototype;

  static JSObject get objectPrototype {
    // First try to get from current Zone's PrototypeManager
    final manager = PrototypeManager.current;
    if (manager != null && manager.objectPrototype != null) {
      return manager.objectPrototype!;
    }

    // Fallback to static (for backward compatibility during migration)
    _objectPrototype ??= JSObject._createObjectPrototype();
    return _objectPrototype!;
  }

  /// Sets the object prototype in the current Zone's PrototypeManager
  static void setObjectPrototype(JSObject prototype) {
    final manager = PrototypeManager.current;
    if (manager != null) {
      manager.setObjectPrototype(prototype);
    } else {
      // Fallback to static
      _objectPrototype = prototype;
    }
  }

  /// Returns the [[Class]] tag for Object.prototype.toString
  /// According to ES6+ spec, check Symbol.toStringTag first
  static String _getToStringTag(JSValue value) {
    // 1. If undefined
    if (value.isUndefined) return 'Undefined';

    // 2. If null
    if (value.isNull) return 'Null';

    // 3. Check the actual type of the object
    if (value is JSArray) return 'Array';
    if (value is JSFunction || value is JSNativeFunction) return 'Function';
    if (value is JSRegExp) return 'RegExp';
    if (value is JSDate) return 'Date';
    if (value is JSError) return 'Error';
    if (value is JSMap) return 'Map';
    if (value is JSSet) return 'Set';
    if (value is JSWeakMap) return 'WeakMap';
    if (value is JSWeakSet) return 'WeakSet';
    if (value is JSPromise) return 'Promise';
    if (value is JSSymbol) return 'Symbol';
    if (value is JSBigInt) return 'BigInt';

    // Check for wrapper objects
    if (value is JSNumberObject) return 'Number';
    if (value is JSStringObject) return 'String';
    if (value is JSBooleanObject) return 'Boolean';

    // 4. For objects, check Symbol.toStringTag
    if (value is JSObject) {
      // Check for [[ErrorData]] internal slot (Error objects created via constructor)
      if (value.hasInternalSlot('ErrorData')) {
        return 'Error';
      }

      // Check if object has a Symbol.toStringTag
      final toStringTagKey = JSSymbol.toStringTag.toString();
      if (value._symbolKeys.containsKey(toStringTagKey)) {
        final tag = value._symbolKeys[toStringTagKey];
        if (tag != null && tag.isString) {
          return tag.toString();
        }
      }

      // Check if object has an internal [[Class]] slot (for prototypes)
      final internalClass = value.getInternalSlot('__internalClass__');
      if (internalClass != null) {
        return internalClass.toString();
      }

      // Check if it's an Arguments object
      if (value._properties.containsKey('callee')) {
        return 'Arguments';
      }
    }

    // 5. Check wrapped primitive types
    if (value.isBoolean) return 'Boolean';
    if (value.isNumber) return 'Number';
    if (value.isString) return 'String';

    // 6. Default: Object
    return 'Object';
  }

  // Private constructor for Object.prototype (without parent prototype)
  /// Creates a new Object.prototype instance
  /// This is public so it can be called from JSEvaluator during initialization
  static JSObject createObjectPrototype() {
    return JSObject._createObjectPrototype();
  }

  JSObject._createObjectPrototype() : _prototype = null {
    // Add native methods directly to Object.prototype
    // IMPORTANT: Pass functionPrototype: JSObject.withoutPrototype() to avoid circular dependency
    final emptyProto = JSObject.withoutPrototype();

    _properties['toString'] = JSNativeFunction(
      functionName: 'toString',
      nativeImpl: (args) {
        // Determine the thisBinding
        final thisObj = args.isNotEmpty ? args[0] : this;

        // Get the appropriate tag
        final tag = _getToStringTag(thisObj);
        return JSValueFactory.string('[object $tag]');
      },
      functionPrototype: emptyProto,
    );

    _properties['valueOf'] = JSNativeFunction(
      functionName: 'valueOf',
      nativeImpl: (args) {
        // New version (with thisBinding) for call/apply
        if (args.isNotEmpty) {
          final thisObj = args[0]; // First argument is 'this'
          return thisObj; // Returns the object on which valueOf is called
        }

        // Old version (without thisBinding) for direct compatibility
        return this; // Returns the object itself
      },
      functionPrototype: emptyProto,
    );

    _properties['hasOwnProperty'] = JSNativeFunction(
      functionName: 'hasOwnProperty',
      nativeImpl: (args) {
        // New version (with thisBinding) for call/apply
        if (args.length >= 2) {
          final thisObj = args[0]; // First argument is 'this'
          final propName = args[1]
              .toString(); // Second argument is the property name

          if (thisObj is JSObject) {
            final result = thisObj.hasOwnProperty(propName);
            return JSValueFactory.boolean(result);
          } else if (thisObj is JSNativeFunction) {
            // JSNativeFunction has special hasOwnProperty that tracks deleted props
            final result = thisObj.hasOwnProperty(propName);
            return JSValueFactory.boolean(result);
          } else if (thisObj is JSFunction) {
            // Functions are objects - check their direct properties
            final result = thisObj._properties.containsKey(propName);
            return JSValueFactory.boolean(result);
          }
        }

        // Old version (without thisBinding) for direct compatibility
        if (args.length == 1) {
          final propName = args[0].toString();
          final result = hasOwnProperty(propName);
          return JSValueFactory.boolean(result);
        }

        return JSValueFactory.boolean(false);
      },
      functionPrototype: emptyProto,
    );

    _properties['isPrototypeOf'] = JSNativeFunction(
      functionName: 'isPrototypeOf',
      nativeImpl: (args) {
        // args[0] is 'this' (the object on which isPrototypeOf was called)
        // args[1] is the argument to isPrototypeOf
        if (args.length < 2) return JSValueFactory.boolean(false);

        final thisObj = args[0]; // The prototype to check
        final testObj = args[1]; // The object to test

        // For JSObject types, walk the prototype chain
        if (testObj is JSObject) {
          if (thisObj is! JSObject) {
            return JSValueFactory.boolean(false);
          }
          // Walk the prototype chain of testObj to see if thisObj is in it
          JSObject? current = testObj._prototype;
          while (current != null) {
            if (identical(current, thisObj)) {
              return JSValueFactory.boolean(true);
            }
            current = current._prototype;
          }
          return JSValueFactory.boolean(false);
        }

        // For JSFunction types (functions are objects in JS), check if thisObj is their prototype
        if (testObj is JSFunction) {
          // Check Function.prototype
          final funcProto = JSFunction.functionPrototype;
          if (funcProto != null && identical(thisObj, funcProto)) {
            return JSValueFactory.boolean(true);
          }
          // Check Object.prototype (Function.prototype inherits from Object.prototype)
          if (thisObj is JSObject &&
              funcProto != null &&
              identical(funcProto._prototype, thisObj)) {
            return JSValueFactory.boolean(true);
          }
          return JSValueFactory.boolean(false);
        }

        return JSValueFactory.boolean(false);
      },
      functionPrototype: emptyProto,
    );

    _properties['propertyIsEnumerable'] = JSNativeFunction(
      functionName: 'propertyIsEnumerable',
      nativeImpl: (args) {
        // When called with .call(), args contains: [thisValue, propName]
        if (args.length < 2) return JSValueFactory.boolean(false);

        final thisValue = args[0];
        final propName = args[1].toString();

        if (thisValue is! JSObject && thisValue is! JSFunction) {
          return JSValueFactory.boolean(false);
        }

        // Get the property descriptor
        PropertyDescriptor? descriptor;
        if (thisValue is JSFunction) {
          descriptor = thisValue.getOwnPropertyDescriptor(propName);
        } else if (thisValue is JSObject) {
          descriptor = thisValue.getOwnPropertyDescriptor(propName);
        }

        // Return true only if property exists and is enumerable
        if (descriptor != null) {
          return JSValueFactory.boolean(descriptor.enumerable);
        }

        return JSValueFactory.boolean(false);
      },
      functionPrototype: emptyProto,
    );

    _properties['toLocaleString'] = JSNativeFunction(
      functionName: 'toLocaleString',
      nativeImpl: (args) {
        return JSValueFactory.string('[object Object]');
      },
      functionPrototype: emptyProto,
    );
  }

  @override
  JSValueType get type => JSValueType.object;

  @override
  dynamic get primitiveValue => this;

  @override
  bool toBoolean() => true; // Objects are always truthy

  // Getter to check if object is extensible
  bool isExtensible = true;

  /// Marks this object as an arguments object for strict property access handling
  void markAsArgumentsObject() {
    _isArgumentsObject = true;
  }

  @override
  double toNumber() {
    // Delegate to JSConversion.jsToNumber which has access to the evaluator
    // and can properly call user-defined valueOf/toString methods
    try {
      return JSConversion.jsToNumber(this);
    } on JSError catch (jsError) {
      // Convert JSError to JSException so it can be caught by JavaScript try-catch
      if (jsError is JSException) {
        rethrow;
      }

      // Get appropriate prototype from global constructor
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        JSObject? prototype;
        try {
          final constructorName = jsError.name;
          final constructor = evaluator.globalEnvironment.get(constructorName);
          if (constructor is JSFunction && constructor is JSObject) {
            final proto = constructor.getProperty('prototype');
            if (proto is JSObject) {
              prototype = proto;
            }
          }
        } catch (_) {
          // Continue without prototype if we can't get it
        }
        final errorValue = JSErrorObjectFactory.fromDartError(
          jsError,
          prototype,
        );
        throw JSException(errorValue);
      }

      // If no evaluator, rethrow as-is
      rethrow;
    }
  }

  @override
  String toString() => '[object Object]';

  @override
  JSObject toObject() => this;

  @override
  bool equals(JSValue other) => identical(this, other);

  @override
  bool strictEquals(JSValue other) => identical(this, other);

  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  int get hashCode {
    // For objects, use the identity of the object to avoid recursions
    return identityHashCode(this);
  }

  /// Define a property
  void setProperty(String name, JSValue value) {
    // 0. Check if object is extensible for new properties
    final existingDescriptor = getOwnPropertyDescriptor(name);
    final hasExistingProperty =
        existingDescriptor != null ||
        _properties.containsKey(name) ||
        _accessorProperties.containsKey(name);

    if (!isExtensible && !hasExistingProperty) {
      // ES6 Spec: Cannot add new properties to non-extensible objects
      // In strict mode: throw TypeError
      // In non-strict mode: silently ignore (fail silently)
      final evaluator = JSEvaluator.currentInstance;
      bool isStrictMode = false;
      if (evaluator != null) {
        try {
          isStrictMode = evaluator.isCurrentlyInStrictMode();
        } catch (_) {
          // If we can't determine strict mode, default to true for safety
          isStrictMode = true;
        }
      }

      if (isStrictMode) {
        throw JSTypeError('Cannot add property $name to non-extensible object');
      }
      // In non-strict mode, silently ignore
      return;
    }

    // 1. Check if property exists and is non-writable
    if (existingDescriptor != null &&
        existingDescriptor.isData &&
        !existingDescriptor.writable) {
      // Property is read-only - should throw in strict mode
      final evaluator = JSEvaluator.currentInstance;
      bool isStrictMode = false;
      if (evaluator != null) {
        try {
          isStrictMode = evaluator.isCurrentlyInStrictMode();
        } catch (_) {
          // If we can't determine strict mode, default to true for safety
          isStrictMode = true;
        }
      }

      if (isStrictMode) {
        throw JSTypeError('Cannot assign to read only property \'$name\'');
      }
      // In non-strict mode, silently ignore
      return;
    }

    // 1. Check s'il y a un setter pour cette properte
    if (_accessorProperties.containsKey(name)) {
      final descriptor = _accessorProperties[name]!;
      if (descriptor.setter != null) {
        // Call the setter with the right context
        final evaluator = JSEvaluator.currentInstance;
        if (evaluator != null) {
          try {
            evaluator.callFunction(descriptor.setter!, [value], this);
          } on JSError catch (jsError) {
            // Convert Dart JSError to JSException for JavaScript
            if (jsError is JSException) {
              rethrow;
            }

            // Retrieve appropriate prototype from global constructor
            JSObject? prototype;
            try {
              final constructorName = jsError.name;
              final constructor = evaluator.globalEnvironment.get(
                constructorName,
              );
              if (constructor is JSFunction && constructor is JSObject) {
                final proto = constructor.getProperty('prototype');
                if (proto is JSObject) {
                  prototype = proto;
                }
              }
            } catch (_) {
              // If we can't retrieve the prototype, continue without
            }
            final errorValue = JSErrorObjectFactory.fromDartError(
              jsError,
              prototype,
            );
            throw JSException(errorValue);
          }
          return; // Exit after calling the setter
        } else {
          throw JSError('No evaluator available for setter execution');
        }
      }
      // If il y a un getter mais pas de setter, la properte est en lecture seule
      if (descriptor.getter != null) {
        // In strict mode, this should throw an error
        throw JSTypeError('Cannot set property $name which has only a getter');
      }
    }

    // 2. Check setters in the prototype chain
    // Also check for non-writable data properties in the prototype chain
    // WORKAROUND: Skip inherited setter calls for numeric property keys like "0"
    // to avoid infinite recursion (see test262 case 15.4.4.15-8-b-i-22.js).
    // For non-numeric keys, we MUST check inherited setters (e.g., class getters/setters).
    bool isNumericKey =
        name.replaceAll(RegExp(r'\d'), '').isEmpty && name.isNotEmpty;

    if (!isNumericKey) {
      // Only walk prototype chain for non-numeric keys
      JSObject? current = _prototype;
      bool foundGetterWithoutSetter = false;
      while (current != null) {
        // Check if there's a non-writable data property in the prototype chain
        final protoDescriptor = current.getOwnPropertyDescriptor(name);
        if (protoDescriptor != null &&
            protoDescriptor.isData &&
            !protoDescriptor.writable) {
          // Found a non-writable data property in prototype chain
          // In strict mode, throw TypeError
          // In non-strict mode, silently ignore
          final evaluator = JSEvaluator.currentInstance;
          bool isStrictMode = false;
          if (evaluator != null) {
            try {
              isStrictMode = evaluator.isCurrentlyInStrictMode();
            } catch (_) {
              isStrictMode = false;
            }
          }
          if (isStrictMode) {
            throw JSTypeError('Cannot assign to read only property \'$name\'');
          }
          return; // Silently ignore in non-strict mode
        }

        if (current._accessorProperties.containsKey(name)) {
          final descriptor = current._accessorProperties[name]!;
          if (descriptor.setter != null) {
            // Call the inherited setter with 'this' pointing to original object
            final evaluator = JSEvaluator.currentInstance;
            if (evaluator != null) {
              try {
                evaluator.callFunction(descriptor.setter!, [value], this);
              } on JSError catch (jsError) {
                // Convert Dart JSError to JSException for JavaScript
                if (jsError is JSException) {
                  rethrow;
                }

                // Retrieve appropriate prototype from global constructor
                JSObject? prototype;
                try {
                  final constructorName = jsError.name;
                  final constructor = evaluator.globalEnvironment.get(
                    constructorName,
                  );
                  if (constructor is JSFunction && constructor is JSObject) {
                    final proto = constructor.getProperty('prototype');
                    if (proto is JSObject) {
                      prototype = proto;
                    }
                  }
                } catch (_) {
                  // If we can't retrieve the prototype, continue without
                }
                final errorValue = JSErrorObjectFactory.fromDartError(
                  jsError,
                  prototype,
                );
                throw JSException(errorValue);
              }
              return; // Exit after calling the setter
            } else {
              throw JSError(
                'No evaluator available for inherited setter execution',
              );
            }
          }
          // If there's an inherited getter but no setter, note that we found it
          // but continue looking for a setter higher in the chain
          if (descriptor.getter != null) {
            foundGetterWithoutSetter = true;
          }
        }
        current = current._prototype;
      }

      // If we found a getter without setter in chain, property is read-only
      if (foundGetterWithoutSetter) {
        return;
      }
    }

    // 3. Normal property - assign directly
    _properties[name] = value;
  }

  /// ES6: Sets a property with a symbol key and tracks the symbol
  void setPropertyWithSymbol(String stringKey, JSValue value, JSSymbol symbol) {
    // Track the symbol for Object.getOwnPropertySymbols()
    _symbolKeys[stringKey] = symbol;
    // Set the property normally
    setProperty(stringKey, value);
  }

  /// ES6: Returns all symbol keys tracked on this object (not including prototype chain)
  /// Used by Object.getOwnPropertySymbols()
  Iterable<JSSymbol> getSymbolKeys() {
    return _symbolKeys.values;
  }

  /// ES6: Gets a property value using a symbol key
  JSValue getPropertyBySymbol(JSSymbol symbol) {
    final stringKey = symbol.toString();
    return getProperty(stringKey);
  }

  /// Get a property
  JSValue getProperty(String name) {
    // For arguments objects, prevent access to 'callee' and 'caller' (ES5 strict requirement)
    // This check must come FIRST before any prototype chain lookup
    if (_isArgumentsObject && (name == 'callee' || name == 'caller')) {
      throw JSTypeError(
        '"caller", "callee", and "arguments" properties may not be accessed on strict mode functions or the arguments objects for calls to them',
      );
    }

    // Special support for __proto__
    if (name == '__proto__') {
      return _prototype ?? JSValueFactory.nullValue();
    }

    // 1. Check accessors (getters/setters) first
    if (_accessorProperties.containsKey(name)) {
      final descriptor = _accessorProperties[name]!;
      if (descriptor.getter != null) {
        // Check for circular references
        if (JSEvaluator.isGetterCycle(this, name)) {
          return JSValueFactory.undefined(); // Return undefined to avoid the cycle
        }

        // Call the getter with the right context
        final evaluator = JSEvaluator.currentInstance;
        if (evaluator != null) {
          try {
            // Mark this getter as active
            JSEvaluator.markGetterActive(this, name);
            final result = evaluator.callFunction(descriptor.getter!, [], this);
            return result;
          } finally {
            // Unmark getter as inactive
            JSEvaluator.unmarkGetterActive(this, name);
          }
        } else {
          throw JSError('No evaluator available for getter execution');
        }
      }
      return JSValueFactory.undefined();
    }

    // 2. Check normal properties
    if (_properties.containsKey(name)) {
      return _properties[name]!;
    }

    // 3. Search in the prototype chain
    JSObject? current = _prototype;
    while (current != null) {
      // Check accessors in the prototype
      if (current._accessorProperties.containsKey(name)) {
        final descriptor = current._accessorProperties[name]!;
        if (descriptor.getter != null) {
          // Check for circular references
          if (JSEvaluator.isGetterCycle(this, name)) {
            return JSValueFactory.undefined();
          }

          // Call getter with 'this' pointing to original object
          final evaluator = JSEvaluator.currentInstance;
          if (evaluator != null) {
            try {
              // Mark this getter as active
              JSEvaluator.markGetterActive(this, name);
              return evaluator.callFunction(descriptor.getter!, [], this);
            } finally {
              // Unmark getter as inactive
              JSEvaluator.unmarkGetterActive(this, name);
            }
          } else {
            throw JSError(
              'No evaluator available for inherited getter execution',
            );
          }
        }
      }
      // Check normal properties in the prototype
      if (current._properties.containsKey(name)) {
        return current._properties[name]!;
      }
      current = current._prototype;
    }

    // 4. If we have a prototype (not Object.create(null)),
    //    search in Object.prototype native methods
    if (_prototype != null) {
      final prototypeProperty = _getObjectPrototypeProperty(name);
      if (prototypeProperty != null) {
        return prototypeProperty;
      }
    }

    // 5. Property not found
    return JSValueFactory.undefined();
  }

  /// Define a getter for a property
  /// Defines a getter for a property.
  /// [enumerable] defaults to false for Object.defineProperty compatibility,
  /// but should be true for object literal getters per ES6 spec.
  void defineGetter(
    String name,
    JSFunction getter, {
    bool enumerable = false,
    JSSymbol? symbol,
  }) {
    final existing = _accessorProperties[name];
    if (existing != null && existing.setter != null) {
      // Preserve the existing setter
      _accessorProperties[name] = PropertyDescriptor(
        getter: getter,
        setter: existing.setter,
        enumerable: enumerable,
        configurable: true,
      );
    } else {
      _accessorProperties[name] = PropertyDescriptor(
        getter: getter,
        enumerable: enumerable,
        configurable: true,
      );
    }

    // Track the symbol if provided
    if (symbol != null) {
      _symbolKeys[name] = symbol;
    }
  }

  /// Defines a setter for a property.
  /// [enumerable] defaults to false for Object.defineProperty compatibility,
  /// but should be true for object literal setters per ES6 spec.
  void defineSetter(
    String name,
    JSFunction setter, {
    bool enumerable = false,
    JSSymbol? symbol,
  }) {
    final existing = _accessorProperties[name];
    if (existing != null && existing.getter != null) {
      // Preserve the existing getter
      _accessorProperties[name] = PropertyDescriptor(
        getter: existing.getter,
        setter: setter,
        enumerable: enumerable,
        configurable: true,
      );
    } else {
      _accessorProperties[name] = PropertyDescriptor(
        setter: setter,
        enumerable: enumerable,
        configurable: true,
      );
    }

    // Track the symbol if provided
    if (symbol != null) {
      _symbolKeys[name] = symbol;
    }
  }

  /// Define a property with a complete descriptor (Object.defineProperty)
  void defineProperty(String name, PropertyDescriptor descriptor) {
    // Check if object is extensible for new properties
    final existingDescriptor = _propertyDescriptors[name];
    final hasExistingProperty =
        existingDescriptor != null ||
        _properties.containsKey(name) ||
        _accessorProperties.containsKey(name);

    if (!isExtensible && !hasExistingProperty) {
      // In ES6, defineProperty on non-extensible object throws TypeError
      // Unlike setProperty which silently ignores
      throw JSTypeError(
        'Cannot define property $name on non-extensible object',
      );
    }

    // Check if property exists and is non-configurable
    if (existingDescriptor != null && !existingDescriptor.configurable) {
      // For non-configurable properties, we can only make limited changes per ES6
      // We can change writable from true to false only

      // Check if trying to change configurable or enumerable
      if (descriptor.configurable ||
          (descriptor.enumerable != existingDescriptor.enumerable)) {
        throw JSTypeError('Cannot redefine non-configurable property: $name');
      }

      // For data properties, we can only change writable from true to false
      if (!existingDescriptor.isAccessor && descriptor.hasValueProperty) {
        // Trying to change the value - not allowed
        throw JSTypeError('Cannot redefine non-configurable property: $name');
      }

      // Can change writable from true to false only
      // We CANNOT change writable from false to true
      if (descriptor.writable && !existingDescriptor.writable) {
        // Trying to change writable from false to true - not allowed
        throw JSTypeError('Cannot redefine non-configurable property: $name');
      }
    }

    // Store the complete descriptor
    _propertyDescriptors[name] = descriptor;

    if (descriptor.isAccessor) {
      // Accessor property (getter/setter)
      _accessorProperties[name] = descriptor;
      // Remove from _properties if it existed as a data property
      _properties.remove(name);
    } else {
      // Data property
      if (descriptor.value != null) {
        _properties[name] = descriptor.value!;
      }
      // Remove from _accessorProperties if it existed as an accessor
      _accessorProperties.remove(name);
    }
  }

  /// Get the descriptor of a property (Object.getOwnPropertyDescriptor)
  PropertyDescriptor? getOwnPropertyDescriptor(String name) {
    // Return the stored descriptor if it exists
    if (_propertyDescriptors.containsKey(name)) {
      return _propertyDescriptors[name];
    }

    // Check accessor properties (old method)
    if (_accessorProperties.containsKey(name)) {
      return _accessorProperties[name];
    }

    // Check data properties (old method - for compatibility)
    if (_properties.containsKey(name)) {
      return PropertyDescriptor(
        value: _properties[name],
        writable: true,
        enumerable: true,
        configurable: true,
      );
    }

    // Property doesn't exist
    return null;
  }

  /// CreateDataPropertyOrThrow (ES6) - Used by Array.from
  /// Attempts to create or update a data property
  /// Throws TypeError if it fails
  void createDataPropertyOrThrow(String name, JSValue value) {
    // Check if object is extensible (new property)
    final existingDesc = getOwnPropertyDescriptor(name);

    if (existingDesc == null && !isExtensible) {
      // Cannot add new property to non-extensible object
      throw JSTypeError('Cannot add property $name to non-extensible object');
    }

    // Per ES6 spec: CreateDataPropertyOrThrow uses [[DefineOwnProperty]]
    // A configurable property can ALWAYS be completely redefined,
    // even if it was non-writable, non-enumerable, or an accessor
    // Only non-configurable properties have restrictions
    if (existingDesc != null && !existingDesc.configurable) {
      // ES6 Spec 9.1.6.3 [[DefineOwnProperty]]:
      // If a property is non-configurable, you can ONLY change:
      // 1. The value (if writable is true)
      // 2. Nothing else - not the descriptor attributes

      // CreateDataProperty tries to create with {writable: true, enumerable: true, configurable: true}
      // This will fail if the existing property is non-configurable with different attributes

      // Check if trying to change configurable from false to true
      // This is ALWAYS forbidden for non-configurable properties
      throw JSTypeError('Cannot redefine non-configurable property \'$name\'');
    }

    // CreateDataProperty semantics: create a data property with all attributes set to true
    // For existing configurable properties, this will completely replace them
    // For new properties, create with full enumerable/writable/configurable attributes
    final newDescriptor = PropertyDescriptor(
      value: value,
      writable: true,
      enumerable: true,
      configurable: true,
    );

    // Remove from accessor properties if it was one (only if configurable)
    if (existingDesc == null || existingDesc.configurable) {
      _accessorProperties.remove(name);
    }

    // Store the descriptor and value
    _propertyDescriptors[name] = newDescriptor;
    _properties[name] = value;
  }

  /// Search for a property in Object.prototype
  JSValue? _getObjectPrototypeProperty(String name) {
    switch (name) {
      case 'toString':
        return JSNativeFunction(
          functionName: 'toString',
          nativeImpl: (args) {
            if (args.isNotEmpty) {
              final thisObj = args[0];
              if (thisObj is JSSymbol) {
                return JSValueFactory.string(thisObj.toString());
              }
            }
            return JSValueFactory.string('[object Object]');
          },
        );

      case 'valueOf':
        return JSNativeFunction(
          functionName: 'valueOf',
          nativeImpl: (args) {
            if (args.isEmpty) return JSObject();
            final thisObj = args[0]; // First argument is 'this'
            if (thisObj.isPrimitive) {
              return thisObj;
            }
            return thisObj; // Objects return themselves
          },
        );

      case 'hasOwnProperty':
        return JSNativeFunction(
          functionName: 'hasOwnProperty',
          nativeImpl: (args) {
            if (args.length < 2) return JSValueFactory.boolean(false);
            final thisObj = args[0]; // First argument is 'this'
            final propName = args[1]
                .toString(); // Second argument is the property name

            // Handle JSObject (regular objects)
            if (thisObj is JSObject) {
              final result = thisObj.hasOwnProperty(propName);
              return JSValueFactory.boolean(result);
            }

            // Handle JSClass (classes have getOwnPropertyDescriptor)
            if (thisObj is JSClass) {
              final descriptor = thisObj.getOwnPropertyDescriptor(propName);
              return JSValueFactory.boolean(descriptor != null);
            }

            // Handle JSFunction (functions can have own properties)
            if (thisObj is JSFunction) {
              final descriptor = thisObj.getOwnPropertyDescriptor(propName);
              return JSValueFactory.boolean(descriptor != null);
            }

            return JSValueFactory.boolean(false);
          },
        );

      case 'isPrototypeOf':
        return JSNativeFunction(
          functionName: 'isPrototypeOf',
          nativeImpl: (args) {
            if (args.length < 2) return JSValueFactory.boolean(false);
            final thisObj = args[0]; // First argument is 'this'
            final obj = args[1]; // Deuxieme argument est l'objet a tester

            if (thisObj is! JSObject || obj is! JSObject) {
              return JSValueFactory.boolean(false);
            }

            // Check si 'thisObj' est dans la chaine de prototypes de obj
            return JSValueFactory.boolean(thisObj._isPrototypeOf(obj));
          },
        );

      case 'propertyIsEnumerable':
        return JSNativeFunction(
          functionName: 'propertyIsEnumerable',
          nativeImpl: (args) {
            if (args.isEmpty) return JSValueFactory.boolean(false);
            final propName = args[0].toString();
            return JSValueFactory.boolean(hasOwnProperty(propName));
          },
        );

      case 'toLocaleString':
        return JSNativeFunction(
          functionName: 'toLocaleString',
          nativeImpl: (args) {
            return JSValueFactory.string('[object Object]');
          },
        );

      default:
        return null;
    }
  }

  /// Verifie si a property existe dans les propertes propres (pas la chaine de prototypes)
  bool hasOwnProperty(String name) {
    return _properties.containsKey(name) ||
        _accessorProperties.containsKey(name);
  }

  /// Verifie si a property est un accessor (getter/setter)
  bool hasAccessorProperty(String name) {
    return _accessorProperties.containsKey(name);
  }

  /// Obtient le descriptor d'un accessor sans l'appeler
  PropertyDescriptor? getAccessorDescriptor(String name) {
    if (_accessorProperties.containsKey(name)) {
      return _accessorProperties[name];
    }

    // Search dans la chaine de prototypes
    JSObject? current = _prototype;
    while (current != null) {
      if (current._accessorProperties.containsKey(name)) {
        return current._accessorProperties[name];
      }
      current = current._prototype;
    }

    return null;
  }

  /// Verifie si a property existe (heritee ou non)
  bool hasProperty(String name) {
    // 1. Propertetes propres (y compris accessors)
    if (_properties.containsKey(name)) return true;
    if (_accessorProperties.containsKey(name)) return true;

    // 2. Chaine de prototypes
    JSObject? current = _prototype;
    while (current != null) {
      if (current._properties.containsKey(name)) return true;
      if (current._accessorProperties.containsKey(name)) return true;
      current = current._prototype;
    }

    // 3. Object.prototype natif seulement si on a un prototype
    if (_prototype != null && _hasObjectPrototypeProperty(name)) return true;

    return false;
  }

  /// Obtient a property propre (sans recherche dans la chaine de prototypes)
  /// Utilise par ES2020 matchAll pour acceder aux propertes personnalisees d'arrays
  JSValue? getOwnPropertyDirect(String name) {
    return _properties[name];
  }

  /// Verifie si cet objet est dans la chaine de prototypes of the object donne
  bool _isPrototypeOf(JSObject obj) {
    JSObject? current = obj.getPrototype();
    while (current != null) {
      if (identical(current, this)) {
        return true;
      }
      current = current.getPrototype();
    }
    return false;
  }

  /// Obtient le prototype de cet objet
  JSObject? getPrototype() {
    return _prototype;
  }

  /// Definit le prototype de cet objet
  void setPrototype(JSObject? prototype) {
    _prototype = prototype;
  }

  /// Verifie si a property existe dans Object.prototype
  bool _hasObjectPrototypeProperty(String name) {
    const objectPrototypeMethods = {
      'toString',
      'valueOf',
      'hasOwnProperty',
      'isPrototypeOf',
      'propertyIsEnumerable',
      'toLocaleString',
    };
    return objectPrototypeMethods.contains(name);
  }

  /// Supprime a property
  bool deleteProperty(String name) {
    // Check if property is non-configurable
    final descriptor = _propertyDescriptors[name];
    if (descriptor != null && !descriptor.configurable) {
      return false; // Cannot delete non-configurable property
    }

    // Delete from all property storage locations
    bool removed = _properties.remove(name) != null;

    // Also delete from accessor properties (Object.defineProperty with get/set)
    if (_accessorProperties.containsKey(name)) {
      _accessorProperties.remove(name);
      removed = true;
    }

    // Also delete from property descriptors
    if (_propertyDescriptors.containsKey(name)) {
      _propertyDescriptors.remove(name);
      removed = true;
    }

    // Also delete from symbol keys if applicable
    if (_symbolKeys.containsKey(name)) {
      _symbolKeys.remove(name);
      removed = true;
    }

    return removed;
  }

  /// Obtient all cles de propertes
  List<String> getPropertyNames({bool enumerableOnly = false}) {
    // ES spec: Property names returned in this order:
    // 1. All integer indices (as strings) in ascending numeric order
    // 2. All string keys in insertion order
    // 3. All symbol keys in insertion order

    final integerIndices = <String, bool>{}; // Maps "0", "1", etc.
    final stringKeys = <String, bool>{};

    final allKeys = {..._properties.keys, ..._accessorProperties.keys};

    // Separate integer indices from string keys
    for (final key in allKeys) {
      if (_symbolKeys.containsKey(key)) continue; // Skip symbols

      // Check if it's a valid array index (0 to 2^32 - 2)
      final idx = int.tryParse(key);
      if (idx != null && idx >= 0 && idx < 4294967295) {
        integerIndices[key] = true;
      } else {
        stringKeys[key] = true;
      }
    }

    final names = <String>[];

    // Add integer indices in ascending order
    final sortedIndices = integerIndices.keys.toList();
    sortedIndices.sort((a, b) => int.parse(a).compareTo(int.parse(b)));

    if (enumerableOnly) {
      for (final key in sortedIndices) {
        final descriptor =
            _propertyDescriptors[key] ?? _accessorProperties[key];
        if (descriptor == null || descriptor.enumerable) {
          names.add(key);
        }
      }

      // Add string keys in insertion order
      for (final key in _properties.keys) {
        if (stringKeys.containsKey(key)) {
          final descriptor = _propertyDescriptors[key];
          if (descriptor == null || descriptor.enumerable) {
            names.add(key);
          }
        }
      }
      for (final key in _accessorProperties.keys) {
        if (stringKeys.containsKey(key)) {
          final descriptor = _accessorProperties[key];
          if (descriptor != null && descriptor.enumerable) {
            names.add(key);
          }
        }
      }
    } else {
      // Return all properties
      for (final key in sortedIndices) {
        names.add(key);
      }

      // Add string keys in insertion order
      for (final key in _properties.keys) {
        if (stringKeys.containsKey(key)) {
          names.add(key);
        }
      }
      for (final key in _accessorProperties.keys) {
        if (stringKeys.containsKey(key)) {
          names.add(key);
        }
      }
    }

    return names;
  }

  /// Obtient les noms de propertes pour les boucles for-in
  /// Ordre selon la specification ES2015+: numeriques d'abord (tries), puis strings (ordre d'insertion)
  List<String> getForInPropertyNames() {
    final names = <String>[];

    // Collecter all propertes enumerables (propres et heritees)
    final visited = <String>{};

    // Fonction recursive pour traverser la chaine de prototypes
    // Mais arreter avant Object.prototype pour eviter les propertes natives
    void collectProperties(JSObject obj) {
      // D'abord les propertes propres
      final ownNames = <String>[];

      // Collecter les propertes de donnees enumerables
      for (final key in obj._properties.keys) {
        if (obj._symbolKeys.containsKey(key)) continue; // Exclure les symboles

        final descriptor = obj._propertyDescriptors[key];
        if (descriptor == null || descriptor.enumerable) {
          if (!visited.contains(key)) {
            ownNames.add(key);
            visited.add(key);
          }
        }
      }

      // Collecter les propertes accesseur enumerables
      for (final key in obj._accessorProperties.keys) {
        if (obj._symbolKeys.containsKey(key)) continue; // Exclure les symboles

        final descriptor = obj._accessorProperties[key];
        if (descriptor != null && descriptor.enumerable) {
          if (!visited.contains(key)) {
            ownNames.add(key);
            visited.add(key);
          }
        }
      }

      // Trier selon l'ordre for-in: numeriques d'abord (tries numeriquement), puis strings
      final numericKeys = <String>[];
      final stringKeys = <String>[];

      for (final key in ownNames) {
        // Check si c'est une cle numerique (index array-like)
        final numValue = int.tryParse(key);
        if (numValue != null && numValue >= 0) {
          numericKeys.add(key);
        } else {
          stringKeys.add(key);
        }
      }

      // Trier les cles numeriques
      numericKeys.sort((a, b) => int.parse(a).compareTo(int.parse(b)));

      // Les cles string gardent l'ordre d'insertion (deja dans ownNames)
      names.addAll(numericKeys);
      names.addAll(stringKeys);

      // Puis les propertes du prototype (mais pas Object.prototype)
      if (obj._prototype != null && obj._prototype is JSObject) {
        final proto = obj._prototype as JSObject;
        // Check si c'est Object.prototype (qui a toString, valueOf, etc.)
        // If c'est le prototype global Object, ne pas l'inclure
        if (proto != JSObject.objectPrototype) {
          collectProperties(proto);
        }
      }
    }

    collectProperties(this);
    return names;
  }

  /// Convertit le JSObject en Map Dart pour un acces facile aux propertes
  /// Cela evite les multiples appels a getProperty() dans les tests
  Map<String, dynamic> toMap() {
    final result = <String, dynamic>{};

    for (final key in _properties.keys) {
      final value = getProperty(key);

      // Convertir les valeurs JSValue en types Dart natifs
      if (value.isNull || value.isUndefined) {
        result[key] = null;
      } else if (value.isBoolean) {
        result[key] = value.toBoolean();
      } else if (value.isNumber) {
        final num = value.toNumber();
        result[key] = num == num.truncateToDouble() ? num.toInt() : num;
      } else if (value.isString) {
        result[key] = value.toString();
      } else if (value is JSArray) {
        result[key] = value.toList();
      } else if (value is JSObject) {
        result[key] = value.toMap();
      } else {
        // For les autres types (fonctions, symboles, etc.), return la valeur JS
        result[key] = value;
      }
    }

    return result;
  }
}

/// Fonction JavaScript
class JSFunction extends JSValue {
  // Static reference to Function.prototype - set by the evaluator during initialization
  static JSObject? _functionPrototype;

  static JSObject? get functionPrototype {
    final manager = PrototypeManager.current;
    if (manager != null && manager.functionPrototype != null) {
      return manager.functionPrototype;
    }
    return _functionPrototype;
  }

  static void setFunctionPrototype(JSObject proto) {
    final manager = PrototypeManager.current;
    if (manager != null) {
      manager.setFunctionPrototype(proto);
    } else {
      _functionPrototype = proto;
    }
  }

  final dynamic declaration; // FunctionDeclaration AST node
  final dynamic closureEnvironment; // Environment captured at creation

  // NOUVEAU: Reference vers la classe parent si c'est une methode de classe
  JSClass? parentClass;

  // ES2019: Source text original de la fonction pour toString()
  String? sourceText;

  // ES2020: Module URL where this function was defined (for import.meta)
  String? moduleUrl;

  // Strict mode: true if function was defined in strict mode context
  final bool strictMode;

  // Arrow function: true if this is an arrow function (cannot be used as constructor)
  final bool isArrowFunction;

  // ES6: Method definition (concise methods in class/object) - no prototype property
  final bool isMethodDefinition;

  // Propertetes ECMAScript pour les fonctions
  late final Map<String, JSValue> _properties;
  final Map<String, PropertyDescriptor> _propertyDescriptors = {};
  late final String _name;
  late final int _length;
  late JSObject? _prototype; // Changed to nullable for method definitions

  // Internal slots for ES6+ specifications (e.g., [[Realm]])
  final Map<String, dynamic> _internalSlots = {};

  JSFunction(
    this.declaration,
    this.closureEnvironment, {
    this.sourceText,
    this.moduleUrl,
    this.strictMode = false,
    this.isArrowFunction = false,
    this.isMethodDefinition = false,
    JSObject? functionPrototype, // Add optional prototype parameter
    String?
    inferredName, // ES6: Inferred name for anonymous functions in destructuring
  }) {
    if (declaration != null) {
      _initializeFunctionProperties(inferredName);
    } else {
      // For les fonctions natives ou bound, initialiser avec des propertes vides
      _name = inferredName ?? 'anonymous';
      _length = 0;
      if (isMethodDefinition || isArrowFunction) {
        // Method definitions and arrow functions don't have prototype
        _prototype = null;
        _properties = {
          'length': JSValueFactory.number(_length.toDouble()),
          'name': JSValueFactory.string(_name),
        };
      } else {
        // Use provided prototype or create new one
        _prototype = functionPrototype ?? JSObject();
        _properties = {
          'length': JSValueFactory.number(_length.toDouble()),
          'name': JSValueFactory.string(_name),
          'prototype': _prototype!,
        };
      }

      // Set property descriptors for native functions too
      defineProperty(
        'length',
        PropertyDescriptor(
          value: JSValueFactory.number(_length.toDouble()),
          writable: false,
          enumerable: false,
          configurable: true,
        ),
      );

      defineProperty(
        'name',
        PropertyDescriptor(
          value: JSValueFactory.string(_name),
          writable: false,
          enumerable: false,
          configurable: true,
        ),
      );

      if (!isMethodDefinition && !isArrowFunction && _prototype != null) {
        defineProperty(
          'prototype',
          PropertyDescriptor(
            value: _prototype!,
            writable: true,
            enumerable: false,
            configurable: false,
          ),
        );
      }
    }
  }

  void _initializeFunctionProperties([String? inferredName]) {
    // Nom de la fonction
    if (declaration?.id?.name != null) {
      _name = declaration.id.name;
    } else {
      // Use inferred name if provided (ES6 function name inference)
      _name = inferredName ?? 'anonymous';
    }

    // Nombre de parametres - utiliser le getter virtuel
    _length = parameterCount;

    // ES6: Method definitions and arrow functions don't have prototype property
    if (isMethodDefinition || isArrowFunction) {
      _prototype = null;
      _properties = {
        'length': JSValueFactory.number(_length.toDouble()),
        'name': JSValueFactory.string(_name),
      };
    } else {
      // Prototype object pour les fonctions (only for regular functions)
      _prototype = JSObject();
      // ES6: constructor property should be writable, configurable, but NOT enumerable
      _prototype!.defineProperty(
        'constructor',
        PropertyDescriptor(
          value: this,
          writable: true,
          enumerable: false,
          configurable: true,
        ),
      );

      // Propertetes de la fonction selon ECMAScript
      _properties = {
        'length': JSValueFactory.number(_length.toDouble()),
        'name': JSValueFactory.string(_name),
        'prototype': _prototype!,
      };
    }

    // Per ES spec, function.length should have writable: false, enumerable: false, configurable: true
    defineProperty(
      'length',
      PropertyDescriptor(
        value: JSValueFactory.number(_length.toDouble()),
        writable: false,
        enumerable: false,
        configurable: true,
      ),
    );

    // function.name should be non-writable, non-enumerable, configurable
    defineProperty(
      'name',
      PropertyDescriptor(
        value: JSValueFactory.string(_name),
        writable: false,
        enumerable: false,
        configurable: true,
      ),
    );

    // function.prototype is writable, non-enumerable, non-configurable (only for regular functions)
    if (!isMethodDefinition && !isArrowFunction && _prototype != null) {
      defineProperty(
        'prototype',
        PropertyDescriptor(
          value: _prototype!,
          writable: true,
          enumerable: false,
          configurable: false,
        ),
      );
    }
  }

  // Internal slot methods for ES6+ specifications
  /// Get an internal slot value
  dynamic getInternalSlot(String name) {
    return _internalSlots[name];
  }

  /// Set an internal slot value
  void setInternalSlot(String name, dynamic value) {
    _internalSlots[name] = value;
  }

  /// Check if an internal slot exists
  bool hasInternalSlot(String name) {
    return _internalSlots.containsKey(name);
  }

  /// Set the name of an anonymous function (used when assigned to a variable)
  /// This follows ES6 SetFunctionName abstract operation
  void setFunctionName(String newName) {
    if (_name == 'anonymous' || _name.isEmpty) {
      // Update the properties map
      _properties['name'] = JSValueFactory.string(newName);
      // Also update the property descriptor
      _propertyDescriptors['name'] = PropertyDescriptor(
        value: JSValueFactory.string(newName),
        writable: false,
        enumerable: false,
        configurable: true,
      );
    }
  }

  /// Get the function's name
  String get functionName => _name;

  // Acces aux propertes de fonction

  JSValue getProperty(String name) {
    // First check if the property has an accessor (getter/setter)
    final descriptor = _propertyDescriptors[name];
    if (descriptor != null &&
        descriptor.isAccessor &&
        descriptor.getter != null) {
      // Call the getter with 'this' pointing to the function object
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        try {
          return evaluator.callFunction(descriptor.getter!, [], this);
        } catch (e) {
          // If getter throws, propagate the error
          rethrow;
        }
      }
    }

    // In strict mode, accessing 'caller' or 'callee' throws TypeError
    if (strictMode && (name == 'caller' || name == 'callee')) {
      throw JSTypeError(
        '"caller", "callee", and "arguments" properties may not be accessed on strict mode functions or the arguments objects for calls to them',
      );
    }

    // Per ES5 strict mode: accessing .caller when the CALLER is strict mode also throws
    // This check needs to happen via the evaluator's call stack
    if (name == 'caller') {
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        try {
          // This will throw TypeError if caller is a strict mode function
          final caller = evaluator.getCurrentCaller(this);
          return caller ?? JSValueFactory.nullValue();
        } on JSTypeError {
          rethrow;
        }
      }
      return JSValueFactory.nullValue();
    }

    // Then check if the property is actually present (might have been deleted)
    if (_properties.containsKey(name)) {
      final value = _properties[name];
      if (value != null) {
        return value;
      }
    }

    switch (name) {
      case 'length':
        return JSValueFactory.undefined();
      case 'name':
        return JSValueFactory.undefined();
      case 'prototype':
        return JSValueFactory.undefined();
      case 'toString':
        // Check if Function.prototype.toString has been overridden
        final funcProto = JSFunction.functionPrototype;
        if (funcProto != null) {
          final overriddenToString = funcProto.getProperty('toString');
          if (!overriddenToString.isUndefined) {
            // Return the overridden version
            return overriddenToString;
          }
        }
        // Otherwise return the native implementation
        return JSNativeFunction(
          functionName: 'toString',
          nativeImpl: (args) {
            return JSValueFactory.string(toString());
          },
        );
      case 'call':
        return _createCallMethod();
      case 'apply':
        return _createApplyMethod();
      case 'bind':
        return _createBindMethod();
      case 'hasOwnProperty':
        // Use la version Object.prototype.hasOwnProperty avec this binding
        return JSNativeFunction(
          functionName: 'hasOwnProperty',
          nativeImpl: (args) {
            String propName;

            if (args.length >= 2) {
              // Appel avec this binding: hasOwnProperty(thisObj, propName)
              propName = args[1].toString();
            } else if (args.length == 1) {
              // Appel direct: hasOwnProperty(propName)
              propName = args[0].toString();
            } else {
              return JSValueFactory.boolean(false);
            }

            // For les fonctions, verifier dans _properties (propertes directes)
            return JSValueFactory.boolean(_properties.containsKey(propName));
          },
        );
      default:
        // Check Function.prototype for inherited properties
        final funcProto = JSFunction.functionPrototype;
        if (funcProto != null) {
          final protoProp = funcProto.getProperty(name);
          if (!protoProp.isUndefined) {
            return protoProp;
          }
        }
        // Search dans les propertes personnalisees
        return _properties[name] ?? JSValueFactory.undefined();
    }
  }

  /// Check if this function has an own property with the given name
  bool containsOwnProperty(String name) {
    return _properties.containsKey(name);
  }

  // Methodes factory pour les methodes de fonction
  JSNativeFunction _createCallMethod() {
    return JSNativeFunction(
      functionName: 'call',
      nativeImpl: (args) {
        // function.call(thisArg, ...args)
        final evaluator = JSEvaluator.currentInstance;
        if (evaluator == null) {
          throw JSError('No evaluator available for function.call');
        }

        // First argument is 'this', le reste sont les arguments de la fonction
        final thisArg = args.isNotEmpty ? args[0] : JSValueFactory.undefined();
        final functionArgs = args.length > 1 ? args.sublist(1) : <JSValue>[];

        // Don't wrap JS errors - let TypeError, ReferenceError etc propagate
        return evaluator.callFunction(this, functionArgs, thisArg);
      },
    );
  }

  JSNativeFunction _createApplyMethod() {
    return JSNativeFunction(
      functionName: 'apply',
      nativeImpl: (args) {
        // function.apply(thisArg, argsArray)
        final evaluator = JSEvaluator.currentInstance;
        if (evaluator == null) {
          throw JSError('No evaluator available for function.apply');
        }

        // First argument is 'this'
        final thisArg = args.isNotEmpty ? args[0] : JSValueFactory.undefined();

        // Deuxieme argument doit etre un array, array-like object, ou null/undefined
        List<JSValue> functionArgs = [];
        if (args.length > 1) {
          final argsArray = args[1];
          if (argsArray.isNull || argsArray.isUndefined) {
            functionArgs = [];
          } else if (argsArray is JSArray) {
            functionArgs = argsArray.elements.toList();
          } else if (argsArray is JSObject) {
            // Support for array-like objects (has length property and numeric indices)
            final lengthProp = argsArray.getProperty('length');
            if (lengthProp.isNumber) {
              final length = lengthProp.toNumber().toInt();
              if (length < 0) {
                functionArgs = [];
              } else {
                functionArgs = List.generate(length, (i) {
                  final value = argsArray.getProperty(i.toString());
                  return value;
                });
              }
            } else {
              throw JSError(
                'Function.prototype.apply: arguments list has wrong type',
              );
            }
          } else {
            throw JSError(
              'Function.prototype.apply: arguments list has wrong type',
            );
          }
        }

        // Don't wrap JS errors - let TypeError, ReferenceError etc propagate
        return evaluator.callFunction(this, functionArgs, thisArg);
      },
    );
  }

  JSNativeFunction _createBindMethod() {
    return JSNativeFunction(
      functionName: 'bind',
      nativeImpl: (args) {
        // function.bind(thisArg, ...boundArgs)
        final thisArg = args.isNotEmpty ? args[0] : JSValueFactory.undefined();
        final boundArgs = args.length > 1 ? args.sublist(1) : <JSValue>[];
        final originalFunction = this; // Capturer la fonction originale

        // Create a function bound
        return JSBoundFunction(originalFunction, thisArg, boundArgs);
      },
    );
  }

  void setProperty(String name, JSValue value) {
    if (name == 'length' || name == 'name') {
      // ES6: length and name are non-writable once set
      // However, we need to allow setting during initialization
      if (_properties.containsKey(name)) {
        // Property already exists - check if writable
        final descriptor = _propertyDescriptors[name];
        if (descriptor != null && !descriptor.writable) {
          // Non-writable property - in strict mode throw, in non-strict silently ignore
          final evaluator = JSEvaluator.currentInstance;
          if (evaluator != null) {
            try {
              final isStrictMode = evaluator.isCurrentlyInStrictMode();
              if (isStrictMode) {
                throw JSTypeError(
                  'Cannot assign to read only property \'$name\'',
                );
              }
            } catch (e) {
              if (e is JSTypeError) rethrow;
            }
          }
          // In non-strict mode, silently ignore the write
          return;
        }

        // In non-strict mode or if writable, update the value
        _properties[name] = value;
        return;
      }
      // Property doesn't exist yet - allow initial assignment
      _properties[name] = value;
      return;
    }
    // Check si la properte a un descripteur
    final descriptor = _propertyDescriptors[name];
    if (descriptor != null) {
      // If c'est un accessor property avec getter mais sans setter, c'est read-only
      if (descriptor.isAccessor) {
        if (descriptor.getter != null && descriptor.setter == null) {
          // Accessor property without setter - cannot be set
          // In strict mode, throw TypeError
          // In non-strict mode, silently ignore
          final evaluator = JSEvaluator.currentInstance;
          bool isStrictMode = false;
          if (evaluator != null) {
            try {
              isStrictMode = evaluator.isCurrentlyInStrictMode();
            } catch (_) {
              // Default to non-strict for functions (to match JS behavior)
              isStrictMode = false;
            }
          }
          if (isStrictMode) {
            throw JSTypeError(
              'Cannot set property $name which has only a getter',
            );
          }
          return; // Silently ignore in non-strict mode
        }
        // If there's a setter, call it
        if (descriptor.setter != null) {
          final evaluator = JSEvaluator.currentInstance;
          if (evaluator != null) {
            evaluator.callFunction(descriptor.setter!, [value], this);
            return;
          }
        }
      }
      // For data properties, check writable
      if (!descriptor.writable) {
        // In strict mode, throw TypeError
        // In non-strict mode, silently ignore
        final evaluator = JSEvaluator.currentInstance;
        bool isStrictMode = false;
        if (evaluator != null) {
          try {
            isStrictMode = evaluator.isCurrentlyInStrictMode();
          } catch (_) {
            isStrictMode = false;
          }
        }
        if (isStrictMode) {
          throw JSTypeError('Cannot assign to read only property \'$name\'');
        }
        return; // Silently ignore in non-strict mode
      }
    }
    _properties[name] = value;
  }

  /// Define a property with a complete descriptor (Object.defineProperty)
  void defineProperty(String name, PropertyDescriptor descriptor) {
    _propertyDescriptors[name] = descriptor;
    if (descriptor.value != null) {
      _properties[name] = descriptor.value!;
    }
  }

  /// Remove a property from this function's own properties
  bool removeOwnProperty(String name) {
    _propertyDescriptors.remove(name);
    return _properties.remove(name) != null;
  }

  /// Delete a property from this function (ES5 [[Delete]])
  bool deleteProperty(String name) {
    // Check if property is configurable
    final desc = getOwnPropertyDescriptor(name);
    if (desc != null && desc.configurable) {
      return removeOwnProperty(name);
    }
    // If property exists but is not configurable, deletion fails
    if (desc != null && !desc.configurable) {
      return false;
    }
    // If property doesn't exist, deletion succeeds
    return true;
  }

  /// Obtient le descripteur de properte pour a property donnee
  PropertyDescriptor? getOwnPropertyDescriptor(String name) {
    // D'abord verifier les descripteurs explicites
    if (_propertyDescriptors.containsKey(name)) {
      return _propertyDescriptors[name];
    }
    // For les propertes normales, creer un descripteur by default
    if (_properties.containsKey(name)) {
      // ES6: Function properties have specific attributes
      if (name == 'length' || name == 'name') {
        // length and name are non-writable, non-enumerable, but configurable
        return PropertyDescriptor(
          value: _properties[name],
          writable: false,
          enumerable: false,
          configurable: true,
        );
      } else if (name == 'prototype') {
        // prototype is non-writable, non-enumerable, non-configurable
        return PropertyDescriptor(
          value: _properties[name],
          writable: false,
          enumerable: false,
          configurable: false,
        );
      } else {
        // Other properties use default attributes
        return PropertyDescriptor(
          value: _properties[name],
          writable: true,
          enumerable: true,
          configurable: true,
        );
      }
    }
    return null;
  }

  /// Set a property descriptor for a function property
  /// This allows setting the writable, enumerable, and configurable flags
  void defineOwnProperty(String name, PropertyDescriptor descriptor) {
    _propertyDescriptors[name] = descriptor;
    if (descriptor.value != null) {
      _properties[name] = descriptor.value!;
    }
  }

  bool hasProperty(String name) {
    return _properties.containsKey(name) ||
        ['call', 'apply', 'bind', 'toString'].contains(name);
  }

  @override
  JSValueType get type => JSValueType.function;

  @override
  dynamic get primitiveValue => this;

  @override
  bool toBoolean() => true; // Les fonctions sont toujours truthy

  @override
  double toNumber() => double.nan; // [object Function] -> NaN

  @override
  String toString() {
    // ES2019: Return original source text if available
    if (sourceText != null) {
      return sourceText!;
    }
    // Fallback pour les fonctions natives ou sans source
    return 'function ${declaration?.id?.name ?? 'anonymous'}() { [native code] }';
  }

  @override
  JSObject toObject() => FunctionObject(this); // Fonctions sont des objets en JS

  @override
  bool equals(JSValue other) => identical(this, other);

  @override
  bool strictEquals(JSValue other) => identical(this, other);

  /// Nombre de parametres de la fonction
  /// Per ES spec: function.length is the count of parameters before
  /// the first one with a default value or a rest parameter
  int get parameterCount {
    final params = declaration?.params;
    if (params == null) return 0;

    int count = 0;
    for (final param in params) {
      // Rest parameters don't count towards length
      if (param.isRest) break;
      // Stop counting when we hit a parameter with a default value
      if (param.defaultValue != null) break;
      count++;
    }
    return count;
  }

  /// Check if this function can be used as a constructor
  /// Arrow functions cannot be used as constructors
  /// Regular functions and class constructors can be
  bool get isConstructor => !isArrowFunction;
}

/// Classe JavaScript (ES6 class)
class JSClass extends JSValue {
  final dynamic declaration; // ClassDeclaration AST node
  final dynamic closureEnvironment; // Environment captured at creation
  final JSClass? superClass; // Classe parent
  final JSFunction?
  superFunction; // Fonction native parente (ex: Promise, Array)
  final bool extendsNull; // True when class extends null
  final JSValue?
  _superFunctionPrototype; // Cached prototype from superFunction (to avoid multiple getter calls)

  // Propertetes de la classe
  late final Map<String, JSValue> _properties;
  late final Map<String, JSValue> _staticMethods;
  late final Map<String, JSValue> _methods;
  late final Map<String, PropertyDescriptor> _accessorProperties;
  late final Set<String> _privateFields; // Propertetes privees declarees
  late final List<dynamic> _instanceFields; // Field declarations pour instances
  JSFunction? _constructor;
  String _name =
      'anonymous'; // Mutable to allow setting name for anonymous classes
  late final JSObject _prototype;

  JSClass(
    this.declaration,
    this.closureEnvironment, [
    this.superClass,
    this.superFunction,
    this.extendsNull = false,
    this._superFunctionPrototype,
  ]) {
    _initializeClassProperties();
  }

  void _initializeClassProperties() {
    // Nom de la classe
    _name = declaration?.id?.name ?? 'anonymous';

    // Prototype object pour les instances de la classe
    _prototype = JSObject();
    // ES6: constructor property should be writable, configurable, but NOT enumerable
    _prototype.defineProperty(
      'constructor',
      PropertyDescriptor(
        value: this,
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );

    // If il y a une superclasse, heriter de son prototype
    if (superClass != null) {
      _prototype.setPrototype(superClass!._prototype);
    } else if (superFunction != null) {
      // For les fonctions natives comme Promise, utiliser leur prototype
      // Use the cached prototype if available to avoid calling the getter again
      final nativePrototype =
          _superFunctionPrototype ?? superFunction!.getProperty('prototype');
      if (nativePrototype is JSObject) {
        _prototype.setPrototype(nativePrototype);
      }
    } else if (extendsNull) {
      // class C extends null { } - prototype chain is null
      _prototype.setPrototype(null);
    }

    // Initialiser les collections
    _staticMethods = {};
    _methods = {};
    _accessorProperties = {};
    _privateFields = {}; // Initialiser l'ensemble des propertes privees
    _instanceFields = []; // Initialiser la liste des champs d'instance

    // Initialiser le constructor a null
    _constructor = null;

    // Parser les methodes de la classe
    _parseMethods();

    // Propertetes de la classe selon ECMAScript
    _properties = {
      'name': JSValueFactory.string(_name),
      'prototype': _prototype,
      'length': JSValueFactory.number(
        _constructor?.parameterCount.toDouble() ?? 0.0,
      ),
    };
  }

  /// Returns true if this class is derived (has extends clause)
  /// A class extends null is considered derived even though there's no superclass
  bool get isDerivedClass =>
      superClass != null || superFunction != null || extendsNull;

  void _parseMethods() {
    if (declaration?.body?.members != null) {
      for (final member in declaration.body.members) {
        // Handle FieldDeclaration (static and instance fields)
        if (member is FieldDeclaration) {
          String fieldName;
          bool isPrivateField = false;

          if (member.key is IdentifierExpression) {
            final ident = member.key as IdentifierExpression;
            fieldName = ident.name;

            // Skip empty class elements (marked with __empty__)
            if (fieldName == '__empty__') {
              continue;
            }
          } else if (member.key is PrivateIdentifierExpression) {
            fieldName = (member.key as PrivateIdentifierExpression).name;
            isPrivateField = true;
          } else if (member.key is LiteralExpression) {
            // Handle numeric property names: 1() { ... }
            final lit = member.key as LiteralExpression;
            // Convert the numeric value to the appropriate string form
            // If it's a whole number, convert without decimal point
            if (lit.value is num) {
              final numValue = lit.value as num;
              if (numValue.floor() == numValue) {
                fieldName = numValue.toInt().toString();
              } else {
                fieldName = numValue.toString();
              }
            } else {
              fieldName = lit.value.toString();
            }
          } else {
            // For computed property names, evaluate the expression to get the key
            final evaluator = JSEvaluator.currentInstance;
            if (evaluator != null) {
              // Errors during evaluation of computed property names MUST be propagated
              // per ES6 spec: ClassFieldDefinitionEvaluation must propagate abrupt completions
              final keyValue = member.key.accept(evaluator);
              fieldName = keyValue.toString();
            } else {
              continue;
            }
          }

          final storageKey = isPrivateField ? '_private_$fieldName' : fieldName;

          // Evaluate the initializer if present
          JSValue initialValue = JSValueFactory.undefined();
          if (member.initializer != null) {
            final evaluator = JSEvaluator.currentInstance;
            if (evaluator != null) {
              try {
                initialValue = member.initializer!.accept(evaluator);
              } catch (e) {
                // On d'erreur, utiliser undefined
              }
            }
          }

          // Store static fields in _staticMethods (reusing existing map)
          if (member.isStatic) {
            _staticMethods[storageKey] = initialValue;
          } else {
            // Store instance fields for initialization during construction
            _instanceFields.add(member);
          }

          if (isPrivateField) {
            _privateFields.add(fieldName);
          }
        }

        // Traiter les MethodDefinition
        if (member is MethodDefinition) {
          // Extraire le nom de la methode selon le type de cle
          String methodName;
          String? methodFunctionName; // The name to set on the function
          bool isPrivateMethod = false;

          if (member.computed) {
            // Propertete computed: [expression] - evaluer l'expression pour obtenir le nom
            final evaluator = JSEvaluator.currentInstance;
            if (evaluator != null) {
              // For computed property names, errors MUST be propagated
              // This includes ReferenceError for unresolvable identifiers
              final computedKey = member.key.accept(evaluator);

              // ToPropertyKey conversion - must handle Symbols and throw TypeError if not convertible
              if (computedKey is JSSymbol) {
                methodName = computedKey.toString();
                // Symbol method names follow special rules:
                // - If symbol has no description: name = ""
                // - If symbol has description: name = "[description]"
                final desc = computedKey.description;
                methodFunctionName = desc != null ? '[$desc]' : '';
              } else {
                // Use JSConversion.jsToString for proper ToPropertyKey conversion
                // This will throw TypeError if the object can't be converted to a primitive
                methodName = JSConversion.jsToString(computedKey);
                methodFunctionName = null; // Will be set later
              }
              // Les propertes computed ne peuvent pas etre privees
              isPrivateMethod = false;
            } else {
              // Pas d'evaluateur disponible, ignorer
              continue;
            }
          } else if (member.key is IdentifierExpression) {
            methodName = (member.key as IdentifierExpression).name;
            methodFunctionName = null;
          } else if (member.key is PrivateIdentifierExpression) {
            methodName = (member.key as PrivateIdentifierExpression).name;
            methodFunctionName = null;
            isPrivateMethod = true;
          } else if (member.key is LiteralExpression) {
            // Handle numeric property names: 1() { ... }
            final lit = member.key as LiteralExpression;
            // Convert the numeric value to the appropriate string form
            // If it's a whole number, convert without decimal point
            if (lit.value is num) {
              final numValue = lit.value as num;
              if (numValue.floor() == numValue) {
                methodName = numValue.toInt().toString();
              } else {
                methodName = numValue.toString();
              }
            } else {
              methodName = lit.value.toString();
            }
            methodFunctionName = null;
          } else {
            // Type de cle non supporte
            continue;
          }

          // Determine if this is the constructor or a method
          final isConstructorMethod =
              member.kind.toString() == 'MethodKind.constructor';

          // ES2019: Generate source text for method
          final sourceText = member.toString();
          final methodFunction = JSFunction(
            member.value,
            closureEnvironment,
            sourceText: sourceText,
            // ES6: Non-constructor methods don't have prototype property
            isMethodDefinition: !isConstructorMethod,
          );

          // Set the method name for non-constructor methods
          if (!isConstructorMethod) {
            // Use methodFunctionName if it was computed (for symbols),
            // otherwise use methodName
            final nameToSet = methodFunctionName ?? methodName;
            methodFunction.setFunctionName(nameToSet);
          }

          // NOUVEAU: Definir la classe parent pour les methodes (statiques et d'instance)
          methodFunction.parentClass =
              this; // NOUVEAU: Transformer les noms des methodes privees
          final storageKey = isPrivateMethod
              ? '_private_$methodName'
              : methodName;

          switch (member.kind.toString()) {
            case 'MethodKind.constructor':
              _constructor = methodFunction;
              break;
            case 'MethodKind.method':
              if (member.isStatic) {
                // Cannot define 'prototype' or 'constructor' as static methods
                if (storageKey == 'prototype' || storageKey == 'constructor') {
                  throw JSTypeError(
                    'Cannot define static method or property named "$storageKey" on class',
                  );
                }
                _staticMethods[storageKey] = methodFunction;
              } else {
                _methods[storageKey] = methodFunction;
                // ES6: Class methods should be writable, configurable, but NOT enumerable
                _prototype.defineProperty(
                  storageKey,
                  PropertyDescriptor(
                    value: methodFunction,
                    writable: true,
                    enumerable: false,
                    configurable: true,
                  ),
                );
              }
              // Collecter les noms des propertes privees
              if (isPrivateMethod) {
                _privateFields.add(methodName);
              }
              break;
            case 'MethodKind.get':
              // Set the getter function name with "get " prefix
              if (methodFunctionName != null) {
                // Symbol case: "get " or "get [description]"
                methodFunction.setFunctionName('get $methodFunctionName');
              } else {
                // Regular case: "get methodName"
                methodFunction.setFunctionName('get $methodName');
              }
              if (member.isStatic) {
                // Cannot define 'prototype' or 'constructor' as static getters
                if (storageKey == 'prototype' || storageKey == 'constructor') {
                  throw JSTypeError(
                    'Cannot define static getter named "$storageKey" on class',
                  );
                }
                // Static getter - define on the class itself
                defineGetter(storageKey, methodFunction);
              } else {
                // Instance getter - define on the prototype
                _prototype.defineGetter(storageKey, methodFunction);
              }
              // Collecter les noms des propertes privees
              if (isPrivateMethod) {
                _privateFields.add(methodName);
              }
              break;
            case 'MethodKind.set':
              // Set the setter function name with "set " prefix
              if (methodFunctionName != null) {
                // Symbol case: "set " or "set [description]"
                methodFunction.setFunctionName('set $methodFunctionName');
              } else {
                // Regular case: "set methodName"
                methodFunction.setFunctionName('set $methodName');
              }
              if (member.isStatic) {
                // Cannot define 'prototype' or 'constructor' as static setters
                if (storageKey == 'prototype' || storageKey == 'constructor') {
                  throw JSTypeError(
                    'Cannot define static setter named "$storageKey" on class',
                  );
                }
                // Static setter - define on the class itself
                defineSetter(storageKey, methodFunction);
              } else {
                // Instance setter - define on the prototype
                _prototype.defineSetter(storageKey, methodFunction);
              }
              // Collecter les noms des propertes privees
              if (isPrivateMethod) {
                _privateFields.add(methodName);
              }
              break;
          }
        }

        // ES2022: Handle StaticBlockDeclaration (static initialization blocks)
        if (member is StaticBlockDeclaration) {
          final evaluator = JSEvaluator.currentInstance;
          if (evaluator != null) {
            try {
              // Execute the static block with the class as 'this' context
              evaluator.executeStaticBlock(member.body, this);
            } catch (e) {
              // Propagate errors from static block execution
              rethrow;
            }
          }
        }
      }
    }
  }

  JSValue getProperty(String name) {
    switch (name) {
      case 'name':
        return _properties['name']!;
      case 'prototype':
        return _properties['prototype']!;
      case 'length':
        return _properties['length']!;
      // ES6: Classes inherit from Function.prototype, so they have call/apply/bind
      case 'call':
        return JSNativeFunction(
          functionName: 'call',
          nativeImpl: (args) =>
              FunctionPrototype.call([this, ...args], Environment.global()),
        );
      case 'apply':
        return JSNativeFunction(
          functionName: 'apply',
          nativeImpl: (args) =>
              FunctionPrototype.apply([this, ...args], Environment.global()),
        );
      case 'bind':
        return JSNativeFunction(
          functionName: 'bind',
          nativeImpl: (args) =>
              FunctionPrototype.bind([this, ...args], Environment.global()),
        );
      case 'toString':
        return JSNativeFunction(
          functionName: 'toString',
          nativeImpl: (args) =>
              JSValueFactory.string('class $name { [native code] }'),
        );
      case 'hasOwnProperty':
        // ES6: Classes inherit hasOwnProperty from Function.prototype
        // Return a bound version that checks this class's own properties
        final thisClass = this;
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
            // Check if this class has the property
            final descriptor = thisClass.getOwnPropertyDescriptor(propName);
            return JSValueFactory.boolean(descriptor != null);
          },
        );
      default:
        // 1. Check accessors (getters/setters) first
        if (_accessorProperties.containsKey(name)) {
          final descriptor = _accessorProperties[name]!;
          if (descriptor.getter != null) {
            // Call the getter with the right context
            final evaluator = JSEvaluator.currentInstance;
            if (evaluator != null) {
              try {
                return evaluator.callFunction(descriptor.getter!, [], this);
              } catch (e) {
                throw JSError('Error calling getter for property $name: $e');
              }
            } else {
              throw JSError('No evaluator available for getter execution');
            }
          }
          return JSValueFactory.undefined();
        }

        // 2. Search dans les methodes statiques
        if (_staticMethods.containsKey(name)) {
          return _staticMethods[name]!;
        }

        // 3. Si pas trouve dans les methodes statiques, chercher dans le prototype
        // Cela permet d'acceder aux methodes d'instance depuis super
        // IMPORTANT: On cherche dans le prototype AVANT de remonter dans superClass
        // to avoid short-circuiting overridden methods
        final prototypeValue = _properties['prototype']!;
        if (prototypeValue is JSObject) {
          final methodInPrototype = prototypeValue.getProperty(name);
          if (!methodInPrototype.isUndefined) {
            return methodInPrototype;
          }
        }

        // 4. Search dans les methodes statiques de la superclasse (inheritance)
        // Seulement si on n'a pas trouve dans le prototype
        if (superClass != null) {
          final superStaticMethod = superClass!.getProperty(name);
          if (!superStaticMethod.isUndefined) {
            return superStaticMethod;
          }
        }

        return JSValueFactory.undefined();
    }
  }

  void setProperty(String name, JSValue value) {
    // 1. Check s'il y a un setter pour cette properte
    if (_accessorProperties.containsKey(name)) {
      final descriptor = _accessorProperties[name]!;
      if (descriptor.setter != null) {
        // Call the setter with the right context
        final evaluator = JSEvaluator.currentInstance;
        if (evaluator != null) {
          try {
            evaluator.callFunction(descriptor.setter!, [value], this);
            return; // Exit after calling the setter
          } catch (e) {
            throw JSError('Error calling setter for property $name: $e');
          }
        } else {
          throw JSError('No evaluator available for setter execution');
        }
      }
      // If il y a un getter mais pas de setter, la properte est en lecture seule
      if (descriptor.getter != null) {
        // In strict mode, this should throw an error
        throw JSTypeError('Cannot set property $name which has only a getter');
      }
    }

    // 2. Propertete normale - affecter directement
    _staticMethods[name] = value;
  }

  /// Define a getter for a property statique
  void defineGetter(String name, JSFunction getter) {
    final existing = _accessorProperties[name];
    if (existing != null && existing.setter != null) {
      // Preserve the existing setter
      _accessorProperties[name] = PropertyDescriptor(
        getter: getter,
        setter: existing.setter,
        enumerable: false,
        configurable: true,
      );
    } else {
      _accessorProperties[name] = PropertyDescriptor(
        getter: getter,
        enumerable: false,
        configurable: true,
      );
    }
  }

  /// Definit un setter pour a property statique
  void defineSetter(String name, JSFunction setter) {
    final existing = _accessorProperties[name];
    if (existing != null && existing.getter != null) {
      // Preserve the existing getter
      _accessorProperties[name] = PropertyDescriptor(
        getter: existing.getter,
        setter: setter,
        enumerable: false,
        configurable: true,
      );
    } else {
      _accessorProperties[name] = PropertyDescriptor(
        setter: setter,
        enumerable: false,
        configurable: true,
      );
    }
  }

  /// Create une nouvelle instance de la classe
  JSValue construct(List<JSValue> args, [JSObject? existingInstance]) {
    // Use l'instance existante ou creer un nouvel objet avec le prototype de la classe
    final instance = existingInstance ?? JSObject();
    if (existingInstance == null) {
      instance.setPrototype(_prototype);
    }

    // Appeler le constructor s'il existe
    if (_constructor != null) {
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        // Appeler le constructor avec 'this' lie a l'instance
        // Do NOT catch JS exceptions here - let them propagate
        final result = evaluator.callFunction(_constructor!, args, instance);

        // If le constructor returns an object, le return a la place de l'instance
        if (result.isObject && !result.isNull) {
          return result;
        }
      } else {
        throw JSError('No evaluator available for constructor execution');
      }
    } else if (superClass != null) {
      // If pas de constructor mais il y a une superclass, appeler le constructor de la superclass
      // C'est le comportement by default en JavaScript ES6 pour les classes derivees
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        // Appeler le constructor de la superclass avec l'instance actuelle
        // Do NOT catch JS exceptions here - let them propagate
        final result = superClass!.construct(args, instance);

        // If le constructor de la superclass returns an object different, le retourner
        if (result.isObject && !result.isNull && result != instance) {
          return result;
        }
      }
    } else if (superFunction != null) {
      // If pas de constructor mais il y a a function native parent, l'appeler
      // C'est le comportement by default pour les classes qui etendent Promise, Array, etc.
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        // Call the native superfunction with the instance as 'this' context
        // Do NOT catch exceptions - let them propagate
        if (superFunction is JSNativeFunction) {
          (superFunction as JSNativeFunction).callWithThis(args, instance);
        } else {
          evaluator.callFunction(superFunction as JSFunction, args, instance);
        }
      }
    }

    return instance;
  }

  @override
  JSValueType get type => JSValueType.function; // Les classes sont des fonctions en JavaScript

  @override
  dynamic get primitiveValue => this;

  @override
  bool toBoolean() => true;

  @override
  double toNumber() => double.nan;

  @override
  String toString() => '[class $name]';

  @override
  JSObject toObject() => _prototype;

  @override
  bool equals(JSValue other) => identical(this, other);

  @override
  bool strictEquals(JSValue other) => identical(this, other);

  String get name => _name;

  /// Set the name of an anonymous class (used when assigned to a variable)
  /// This should only be called for classes without an explicit name
  set name(String newName) {
    if (_name == 'anonymous' || _name.isEmpty) {
      _name = newName;
      _properties['name'] = JSValueFactory.string(newName);
    }
  }

  JSFunction? get constructor => _constructor;
  JSObject get prototype => _prototype;

  /// Obtient le descriptor d'un accessor depuis le prototype sans l'appeler
  PropertyDescriptor? getPrototypeAccessorDescriptor(String name) {
    final prototypeValue = _properties['prototype'];
    if (prototypeValue is JSObject) {
      return prototypeValue.getAccessorDescriptor(name);
    }
    return null;
  }

  /// Verifie si cette classe declare la properte privee donnee
  bool hasPrivateField(String fieldName) {
    return _privateFields.contains(fieldName);
  }

  /// Verifie si cette classe a des propertes privees enregistrees
  bool hasAnyPrivateFields() {
    return _privateFields.isNotEmpty;
  }

  /// Obtient la liste des champs d'instance a initialiser
  List<dynamic> get instanceFields => _instanceFields;

  /// Override getOwnPropertyDescriptor to include static methods
  /// Classes have both instance prototype properties and static properties
  PropertyDescriptor? getOwnPropertyDescriptor(String name) {
    // First check accessor properties (static getters/setters)
    if (_accessorProperties.containsKey(name)) {
      return _accessorProperties[name];
    }

    // Then check static methods
    if (_staticMethods.containsKey(name)) {
      final staticMethod = _staticMethods[name]!;
      // Static methods are data properties with writable: true, enumerable: false, configurable: true
      return PropertyDescriptor(
        value: staticMethod,
        writable: true,
        enumerable: false,
        configurable: true,
      );
    }

    // Then check in regular properties (on the _properties map)
    // Classes store constructor, name, length, and prototype in _properties
    if (_properties.containsKey(name)) {
      final prop = _properties[name]!;
      // ES6: Class prototype property is non-writable, non-enumerable, non-configurable
      if (name == 'prototype') {
        return PropertyDescriptor(
          value: prop,
          writable: false,
          enumerable: false,
          configurable: false,
        );
      }
      // ES6: Class name and length properties are non-writable, non-enumerable, but configurable
      if (name == 'name' || name == 'length') {
        return PropertyDescriptor(
          value: prop,
          writable: false,
          enumerable: false,
          configurable: true,
        );
      }
      return PropertyDescriptor(
        value: prop,
        writable: true,
        enumerable: false, // Static properties should not be enumerable
        configurable: true,
      );
    }

    // Property doesn't exist
    return null;
  }
}

/// Array JavaScript
class JSArray extends JSObject {
  final List<JSValue> _elements = [];

  /// Set of indices that are holes (never explicitly set)
  /// Used to distinguish [0, undefined, 2] from [0, , 2]
  final Set<int> _holes = {};

  /// Static reference to Array.prototype - set by the evaluator during initialization
  static JSArray? _arrayPrototype;

  /// Set the global Array.prototype reference
  static void setArrayPrototype(JSArray prototype) {
    final manager = PrototypeManager.current;
    if (manager != null) {
      manager.setArrayPrototype(prototype);
    } else {
      _arrayPrototype = prototype;
    }
  }

  /// Get the global Array.prototype reference
  static JSArray? get arrayPrototype {
    final manager = PrototypeManager.current;
    if (manager != null && manager.arrayPrototype != null) {
      return manager.arrayPrototype;
    }
    return _arrayPrototype;
  }

  JSArray([List<JSValue>? elements]) {
    if (elements != null) {
      _elements.addAll(elements);
    }
    // Note: Do NOT auto-set prototype here as it breaks many array methods.
    // The prototype chain for user-visible arrays should be handled explicitly
    // through ArrayPrototype.getArrayProperty which already does prototype lookup.
  }

  /// Override getPrototype to return Array.prototype for proper prototype chain
  @override
  JSObject? getPrototype() {
    // If _prototype is explicitly set, use it (even if it's Object.prototype)
    if (_prototype != null) {
      return _prototype;
    }
    // Fallback: return Array.prototype if not set
    return _arrayPrototype;
  }

  /// Getter pour la longueur de l'array
  /// Prend en compte les elements sparse
  int get length {
    if (_sparseElements == null || _sparseElements!.isEmpty) {
      return _elements.length;
    }
    // La longueur est le max entre la longueur dense et le plus grand indice sparse + 1
    final maxSparseIndex = _sparseElements!.keys.reduce(
      (a, b) => a > b ? a : b,
    );
    return maxSparseIndex + 1 > _elements.length
        ? maxSparseIndex + 1
        : _elements.length;
  }

  /// Getter pour acceder aux elements (pour ArrayPrototype)
  List<JSValue> get elements => _elements;

  @override
  JSValueType get type => JSValueType.object; // Les arrays sont des objets en JS

  @override
  dynamic get primitiveValue => _elements;

  /// Seuil au-dela duquel on utilise un stockage sparse
  static const int _sparseThreshold = 10000;

  /// Stockage sparse pour les indices tres grands
  Map<int, JSValue>? _sparseElements;

  /// Acces aux elements
  JSValue get(int index) {
    // Check d'abord le stockage sparse pour les grands indices
    if (index >= _sparseThreshold && _sparseElements != null) {
      return _sparseElements![index] ?? JSValueFactory.undefined();
    }
    if (index < 0 || index >= _elements.length) {
      return JSValueFactory.undefined();
    }
    return _elements[index];
  }

  /// Modification d'element
  /// Note: For indices >= 4294967295 (2^32-1), use setProperty as they are not valid array indices
  void set(int index, JSValue value) {
    // Validate that this is a valid array index (< 2^32 - 1)
    // Indices >= 4294967295 are not array indices and should be stored as regular properties
    if (index >= 4294967295 || index < 0) {
      // Store as a regular object property, not as an array element
      super.setProperty(index.toString(), value);
      return;
    }

    // Remove from holes set if it was a hole (now being explicitly set)
    _holes.remove(index);

    // For les indices tres grands mais valides, utiliser un stockage sparse
    if (index >= _sparseThreshold) {
      _sparseElements ??= {};
      _sparseElements![index] = value;
      return;
    }

    // Etendre l'array si necessaire (seulement pour les petits indices)
    while (_elements.length <= index) {
      _elements.add(JSValueFactory.undefined());
    }
    _elements[index] = value;
  }

  /// Override getProperty pour gerer les indices numeriques sous forme de chaines
  @override
  JSValue getProperty(String name) {
    // Check si c'est un indice numerique
    final index = _parseArrayIndex(name);
    if (index != null) {
      // Check for accessor properties first (Object.defineProperty with getter)
      if (_accessorProperties.containsKey(name)) {
        final descriptor = _accessorProperties[name]!;
        if (descriptor.getter != null) {
          // Check for circular references
          if (JSEvaluator.isGetterCycle(this, name)) {
            return JSValueFactory.undefined();
          }
          // Call the getter with the right context
          final evaluator = JSEvaluator.currentInstance;
          if (evaluator != null) {
            try {
              JSEvaluator.markGetterActive(this, name);
              final result = evaluator.callFunction(
                descriptor.getter!,
                [],
                this,
              );
              return result;
            } finally {
              JSEvaluator.unmarkGetterActive(this, name);
            }
          }
        }
        return JSValueFactory.undefined();
      }
      // Get the value first (may be undefined)
      final value = get(index);

      // Check if index is a hole or out of bounds
      // If so, check prototype chain (Array.prototype may have this index)
      if (isHole(index) || index >= length || value.isUndefined) {
        // Check prototype chain for inherited properties
        final inherited = ArrayPrototype.getArrayProperty(this, name);
        // Return inherited property if found and not a hole, otherwise return value (undefined or hole)
        if (!inherited.isUndefined || (index >= length && !isHole(index))) {
          return inherited;
        }
      }
      // Valid index with value, return element directly
      return value;
    }
    // Use ArrayPrototype pour all propertes
    return ArrayPrototype.getArrayProperty(this, name);
  }

  /// Override hasProperty to check array elements and prototype chain
  @override
  bool hasProperty(String name) {
    // Check if it's a numeric index
    final index = _parseArrayIndex(name);
    if (index != null) {
      // First check if we have an accessor property (takes precedence)
      if (_accessorProperties.containsKey(name)) {
        return true;
      }

      // Check if we have the element (not a hole and within bounds)
      if (!isHole(index) && index < length) {
        return true;
      }

      // Check prototype chain for inherited properties at this index
      JSObject? current = getPrototype();
      while (current != null) {
        // If the prototype is also a JSArray, check its elements
        if (current is JSArray) {
          if (!current.isHole(index) && index < current.length) {
            return true;
          }
        }
        // Also check _properties for non-element properties
        if (current._properties.containsKey(name)) {
          return true;
        }
        if (current._accessorProperties.containsKey(name)) {
          return true;
        }
        current = current.getPrototype();
      }
      return false;
    }
    // For non-numeric properties, use the parent implementation
    return super.hasProperty(name);
  }

  /// Definition de propertes pour les arrays (cas special pour length)
  @override
  void setProperty(String name, JSValue value) {
    if (name == 'length') {
      // Modification speciale de la properte length
      // ES6 ArraySetLength:
      // 3. Let newLen be ? ToUint32(Desc.[[Value]]).
      // 4. Let numberLen be ? ToNumber(Desc.[[Value]]).
      // 12. If oldLenDesc.[[Writable]] is false, return false.

      // Helper function to perform ToPrimitive with hint "number"
      JSValue toPrimitive(JSValue val) {
        if (val is JSObject &&
            !val.isNull &&
            !val.isUndefined &&
            val is! JSNumberObject) {
          final evaluator = JSEvaluator.currentInstance;
          JSValue? primitiveResult;

          // Try Symbol.toPrimitive first (ES2015+)
          if (evaluator != null) {
            final toPrimSymbolKey = JSSymbol.symbolToPrimitive.toString();
            final toPrimitiveProp = val.getProperty(toPrimSymbolKey);
            if (toPrimitiveProp is JSNativeFunction) {
              final result = toPrimitiveProp.call([
                val,
                JSValueFactory.string('number'),
              ]);
              if (result is! JSObject ||
                  result is JSNull ||
                  result is JSUndefined) {
                primitiveResult = result;
              }
            } else if (toPrimitiveProp is JSFunction) {
              try {
                final result = evaluator.callFunction(toPrimitiveProp, [
                  JSValueFactory.string('number'),
                ], val);
                if (result is! JSObject ||
                    result is JSNull ||
                    result is JSUndefined) {
                  primitiveResult = result;
                }
              } on JSError catch (jsError) {
                // Convertir les erreurs Dart en JSException et relancer
                if (jsError is JSException) {
                  rethrow;
                }
                JSObject? prototype;
                try {
                  final constructorName = jsError.name;
                  final ctor = evaluator.globalEnvironment.get(constructorName);
                  if (ctor is JSFunction && ctor is JSObject) {
                    final proto = ctor.getProperty('prototype');
                    if (proto is JSObject) {
                      prototype = proto;
                    }
                  }
                } catch (_) {}
                final errorValue = JSErrorObjectFactory.fromDartError(
                  jsError,
                  prototype,
                );
                throw JSException(errorValue);
              }
            }
          }

          // Try valueOf
          if (primitiveResult == null) {
            final valueOfProp = val.getProperty('valueOf');
            if (valueOfProp is JSNativeFunction) {
              final result = valueOfProp.call([val]);
              if (!identical(result, val) &&
                  (result is! JSObject ||
                      result is JSNull ||
                      result is JSUndefined)) {
                primitiveResult = result;
              }
            } else if (valueOfProp is JSFunction &&
                JSEvaluator.currentInstance != null) {
              final result = JSEvaluator.currentInstance!.callFunction(
                valueOfProp,
                [],
                val,
              );
              if (!identical(result, val) &&
                  (result is! JSObject ||
                      result is JSNull ||
                      result is JSUndefined)) {
                primitiveResult = result;
              }
            }
          }

          // Try toString
          if (primitiveResult == null) {
            final toStringProp = val.getProperty('toString');
            if (toStringProp is JSNativeFunction) {
              final result = toStringProp.call([val]);
              if (result is! JSObject ||
                  result is JSNull ||
                  result is JSUndefined) {
                primitiveResult = result;
              }
            } else if (toStringProp is JSFunction &&
                JSEvaluator.currentInstance != null) {
              final result = JSEvaluator.currentInstance!.callFunction(
                toStringProp,
                [],
                val,
              );
              if (result is! JSObject ||
                  result is JSNull ||
                  result is JSUndefined) {
                primitiveResult = result;
              }
            }
          }

          // If still no primitive, throw TypeError (ES6 spec)
          if (primitiveResult == null) {
            throw JSTypeError('Cannot convert object to primitive value');
          }

          return primitiveResult;
        }
        return val;
      }

      // Step 1: ToUint32 - coerce to primitive, then to number
      final uint32Primitive = toPrimitive(value);
      final uint32Value = uint32Primitive.toNumber();

      // Step 2: ToNumber - coerce to primitive again, then to number
      // This is important - we must call ToPrimitive twice per spec
      final numberPrimitive = toPrimitive(value);
      final numberValue = numberPrimitive.toNumber();

      // Check if uint32Value and numberValue match
      if (uint32Value.isNaN || uint32Value.isInfinite) {
        throw JSRangeError('Invalid array length');
      }

      // Check if numberValue is a valid integer
      final intValue = uint32Value.truncate();
      if (uint32Value != intValue.toDouble()) {
        throw JSRangeError('Invalid array length');
      }

      // Check bounds: 0 to 4294967295
      if (intValue < 0 || intValue > 4294967295) {
        throw JSRangeError('Invalid array length');
      }

      // Validate that uint32 and number values match (should usually be true)
      if (numberValue != uint32Value) {
        throw JSRangeError('Invalid array length');
      }

      final newLength = intValue;

      // Check if length property is writable - ES6 spec says we check AFTER coercion
      final lengthDesc = getOwnPropertyDescriptor('length');
      if (lengthDesc != null && !lengthDesc.writable) {
        // Cannot assign to read-only length property
        throw JSTypeError('Cannot assign to read only property \'length\'');
      }

      if (newLength < _elements.length) {
        // Truncate array - check that properties to be deleted are configurable
        // ES spec: If a non-configurable property is encountered, stop deletion
        // and set length to the index after the non-configurable property
        int actualNewLength = newLength;
        for (int i = _elements.length - 1; i >= newLength; i--) {
          final propName = i.toString();
          if (_propertyDescriptors.containsKey(propName)) {
            final descriptor = _propertyDescriptors[propName]!;
            if (!descriptor.configurable) {
              // Cannot delete this property - stop here
              actualNewLength = i + 1;
              break;
            }
          }
          // Delete the property descriptor if it exists and is configurable
          _propertyDescriptors.remove(propName);
        }

        // Truncate to the actual achievable length
        _elements.length = actualNewLength;
        // Clean up sparse elements beyond the new length
        if (_sparseElements != null) {
          _sparseElements!.removeWhere((key, _) => key >= actualNewLength);
        }
      } else if (newLength > length) {
        // For les grandes longueurs, on ne pre-alloue pas
        // On garde juste le concept que length est newLength
        // Les elements non definis seront undefined lors de l'acces
        if (newLength <= _sparseThreshold) {
          // Petite extension, on peut l'allouer
          // Mark new indices as holes - they're not "set" properties
          while (_elements.length < newLength) {
            _elements.add(JSValueFactory.undefined());
            _holes.add(_elements.length - 1);
          }
        }
        // For les grandes extensions, on stocke juste la longueur logique
        // via un element sparse factice
        else if (_sparseElements == null ||
            _sparseElements!.isEmpty ||
            (_sparseElements!.keys.isEmpty
                    ? 0
                    : _sparseElements!.keys.reduce((a, b) => a > b ? a : b)) <
                newLength - 1) {
          // Stocker un marqueur a newLength - 1 pour que length returns newLength
          _sparseElements ??= {};
          _sparseElements![newLength - 1] = JSValueFactory.undefined();
        }
      }
      // If newLength == length, rien a faire
    } else {
      // Check si c'est un indice numerique valide (chaine de caracteres representant un entier)
      final index = _parseArrayIndex(name);
      if (index != null && index >= 0) {
        // First, check if there's an own property descriptor for this index
        final ownDescriptor = getOwnPropertyDescriptor(name);
        if (ownDescriptor != null) {
          // There's an explicit descriptor - use super.setProperty to respect it
          super.setProperty(name, value);
          return;
        }

        // Check if there's a setter in the prototype chain
        // If so, use super.setProperty which handles prototype setters correctly
        JSObject? current = _prototype;
        bool hasSetter = false;
        while (current != null) {
          final descriptor = current.getOwnPropertyDescriptor(name);
          if (descriptor != null && descriptor.setter != null) {
            hasSetter = true;
            break;
          }
          current = current._prototype;
        }

        if (hasSetter) {
          // Use super.setProperty to invoke the setter properly
          super.setProperty(name, value);
        } else {
          // No descriptor and no setter in prototype chain, directly set the element
          set(index, value);
        }
      } else {
        // For les autres propertes, utiliser la logique by default
        super.setProperty(name, value);
      }
    }
  }

  /// Override getOwnPropertyDescriptor to handle array length property
  @override
  PropertyDescriptor? getOwnPropertyDescriptor(String name) {
    if (name == 'length') {
      // Check if length descriptor is already stored
      final stored = super.getOwnPropertyDescriptor(name);
      if (stored != null) {
        return stored;
      }

      // Array length property always exists with these default attributes
      // writable: true, enumerable: false, configurable: false
      return PropertyDescriptor(
        value: JSValueFactory.number(length.toDouble()),
        writable: true,
        enumerable: false,
        configurable: false,
      );
    }

    // For other properties, use parent implementation
    return super.getOwnPropertyDescriptor(name);
  }

  /// Override defineProperty to handle special array length semantics
  @override
  void defineProperty(String name, PropertyDescriptor descriptor) {
    if (name == 'length') {
      final existingDesc = getOwnPropertyDescriptor('length');

      if (!descriptor.hasValueProperty) {
        // No value provided - use standard OrdinaryDefineOwnProperty for length
        // ES6: if trying to define an accessor property (getter/setter), throw TypeError
        // because length is always a data property
        if (descriptor.getter != null || descriptor.setter != null) {
          throw JSTypeError(
            'Cannot define an accessor property for non-configurable data property',
          );
        }

        // But arrays always have a non-configurable length property
        // So trying to define length without a value should fail if the property is non-configurable
        // or if we're trying to change configurable/enumerable flags

        if (existingDesc != null && !existingDesc.configurable) {
          // Length is non-configurable
          // Check if trying to change configurable or enumerable (only if explicitly specified)
          if (descriptor.configurable == true ||
              (descriptor.enumerable != existingDesc.enumerable)) {
            throw JSTypeError(
              'Cannot redefine non-configurable property: length',
            );
          }
          // For writable: can change from true to false only
          // Cannot change from false to true (that's a violation)
          if (descriptor.writable && !existingDesc.writable) {
            // Trying to change writable from false to true - not allowed
            throw JSTypeError(
              'Cannot redefine non-configurable property: length',
            );
          }
        }

        // If all validations passed, call parent to update descriptor
        super.defineProperty(name, descriptor);
        return;
      }

      // Value IS provided - do ArraySetLength special handling
      // First: validate the value (this may throw RangeError)
      // We do this BEFORE checking writable per ES6 spec

      // Helper to validate the length value without modifying the array
      // This checks for overflow and invalid values
      JSValue validateLengthValue(JSValue value) {
        // Helper function to perform ToPrimitive with hint "number"
        JSValue toPrimitive(JSValue val) {
          if (val is JSObject &&
              !val.isNull &&
              !val.isUndefined &&
              val is! JSNumberObject) {
            final evaluator = JSEvaluator.currentInstance;
            JSValue? primitiveResult;

            // Try Symbol.toPrimitive first (ES2015+)
            if (evaluator != null) {
              final toPrimSymbolKey = JSSymbol.symbolToPrimitive.toString();
              final toPrimitiveProp = val.getProperty(toPrimSymbolKey);
              if (toPrimitiveProp is JSNativeFunction) {
                final result = toPrimitiveProp.call([
                  val,
                  JSValueFactory.string('number'),
                ]);
                if (result is! JSObject ||
                    result is JSNull ||
                    result is JSUndefined) {
                  primitiveResult = result;
                }
              } else if (toPrimitiveProp is JSFunction) {
                try {
                  final result = evaluator.callFunction(toPrimitiveProp, [
                    JSValueFactory.string('number'),
                  ], val);
                  if (result is! JSObject ||
                      result is JSNull ||
                      result is JSUndefined) {
                    primitiveResult = result;
                  }
                } catch (e) {
                  rethrow;
                }
              }
            }

            // Try valueOf
            if (primitiveResult == null) {
              final valueOfProp = val.getProperty('valueOf');
              if (valueOfProp is JSNativeFunction) {
                final result = valueOfProp.call([val]);
                if (!identical(result, val) &&
                    (result is! JSObject ||
                        result is JSNull ||
                        result is JSUndefined)) {
                  primitiveResult = result;
                }
              } else if (valueOfProp is JSFunction &&
                  JSEvaluator.currentInstance != null) {
                final result = JSEvaluator.currentInstance!.callFunction(
                  valueOfProp,
                  [],
                  val,
                );
                if (!identical(result, val) &&
                    (result is! JSObject ||
                        result is JSNull ||
                        result is JSUndefined)) {
                  primitiveResult = result;
                }
              }
            }

            // Try toString
            if (primitiveResult == null) {
              final toStringProp = val.getProperty('toString');
              if (toStringProp is JSNativeFunction) {
                final result = toStringProp.call([val]);
                if (result is! JSObject ||
                    result is JSNull ||
                    result is JSUndefined) {
                  primitiveResult = result;
                }
              } else if (toStringProp is JSFunction &&
                  JSEvaluator.currentInstance != null) {
                final result = JSEvaluator.currentInstance!.callFunction(
                  toStringProp,
                  [],
                  val,
                );
                if (result is! JSObject ||
                    result is JSNull ||
                    result is JSUndefined) {
                  primitiveResult = result;
                }
              }
            }

            // If still no primitive, throw TypeError (ES6 spec)
            if (primitiveResult == null) {
              throw JSTypeError('Cannot convert object to primitive value');
            }

            return primitiveResult;
          }
          return val;
        }

        // Step 1: ToUint32
        final uint32Primitive = toPrimitive(value);
        final uint32Value = uint32Primitive.toNumber();

        // Step 2: ToNumber
        final numberPrimitive = toPrimitive(value);
        final numberValue = numberPrimitive.toNumber();

        // Check if values are valid
        if (uint32Value.isNaN || uint32Value.isInfinite) {
          throw JSRangeError('Invalid array length');
        }

        // Check if numberValue is a valid integer
        final intValue = uint32Value.truncate();
        if (uint32Value != intValue.toDouble()) {
          throw JSRangeError('Invalid array length');
        }

        // Check bounds: 0 to 4294967295
        if (intValue < 0 || intValue > 4294967295) {
          throw JSRangeError('Invalid array length');
        }

        // Validate that uint32 and number values match (should usually be true)
        if (numberValue != uint32Value) {
          throw JSRangeError('Invalid array length');
        }

        return JSValueFactory.number(uint32Value);
      }

      // Validate the value FIRST (per ES6 spec)
      final validatedValue = validateLengthValue(descriptor.value!);

      // Get the CURRENT descriptor (which may have changed during coercion)
      final currentDesc = getOwnPropertyDescriptor('length');

      // THEN check writable status (per ValidateAndApplyPropertyDescriptor)
      if (currentDesc != null &&
          !currentDesc.writable &&
          descriptor.writable == true) {
        // Trying to change from non-writable to writable - not allowed
        throw JSTypeError('Cannot redefine non-configurable property: length');
      }

      // Build a new descriptor with the validated value
      final newDesc = PropertyDescriptor(
        value: validatedValue,
        writable: descriptor.writable,
        configurable: descriptor.configurable,
        enumerable: descriptor.enumerable,
        hasValueProperty: true,
      );

      // Call parent defineProperty which validates and applies
      super.defineProperty(name, newDesc);
      return;
    }

    // ES6 9.4.2.1: [[DefineOwnProperty]] for Array Exotic Objects
    // If P is an array index, check if we need to update length
    final index = _parseArrayIndex(name);
    if (index != null) {
      // Get old length before defining the property
      final oldLen = length;

      // Define the property first
      super.defineProperty(name, descriptor);

      // Then update length if needed (per spec step 4)
      if (index >= oldLen) {
        // Update the internal length (extends _elements if needed)
        final newLength = index + 1;
        while (_elements.length < newLength) {
          _elements.add(JSValueFactory.undefined());
          // Mark new indices as holes
          _holes.add(_elements.length - 1);
        }
      }
      return;
    }

    // For other properties, use the parent implementation
    super.defineProperty(name, descriptor);
  }

  /// Parse a string en indice de tableau valide (entier non-negatif)
  /// Returns null si ce n'est pas un indice valide
  static int? _parseArrayIndex(String name) {
    // Un indice de tableau valide est un entier non-negatif < 2^32 - 1
    // et sa representation string doit etre identique au nom d'origine
    if (name.isEmpty) return null;

    // Check que ce sont tous des chiffres
    for (int i = 0; i < name.length; i++) {
      final c = name.codeUnitAt(i);
      if (c < 48 || c > 57) return null; // '0' = 48, '9' = 57
    }

    // Eviter les zeros en tete (sauf "0" lui-meme)
    if (name.length > 1 && name[0] == '0') return null;

    // Parser l'entier
    final parsed = int.tryParse(name);
    if (parsed == null || parsed < 0) return null;

    // Check la limite d'indice de tableau (2^32 - 1)
    if (parsed >= 4294967295) return null;

    // Check que la representation string est identique
    if (parsed.toString() != name) return null;

    return parsed;
  }

  // Methodes pour les operations natives
  JSValue push(JSValue value) {
    _elements.add(value);
    return JSValueFactory.number(_elements.length);
  }

  JSValue pop() {
    if (_elements.isEmpty) {
      return JSValueFactory.undefined();
    }
    return _elements.removeLast();
  }

  /// Obtient all cles de propertes pour les arrays
  /// Inclut les indices numeriques et les propertes heritees
  @override
  List<String> getPropertyNames({bool enumerableOnly = false}) {
    final names = <String>[];

    // Add les indices numeriques (sauf holes)
    for (int i = 0; i < _elements.length; i++) {
      if (!_holes.contains(i)) {
        names.add(i.toString());
      }
    }

    // Add les elements sparse (sauf holes)
    if (_sparseElements != null) {
      for (final key in _sparseElements!.keys) {
        if (!_holes.contains(key)) {
          names.add(key.toString());
        }
      }
    }

    // Add les propertes personnalisees
    names.addAll(super.getPropertyNames(enumerableOnly: enumerableOnly));

    return names;
  }

  /// Obtient les noms de propertes pour les boucles for-in (arrays)
  /// Ordre selon la specification ES2015+: numeriques d'abord (tries), puis propertes heritees enumerables
  @override
  List<String> getForInPropertyNames() {
    final names = <String>[];

    // Add les indices numeriques (toujours enumerables pour les arrays)
    for (int i = 0; i < _elements.length; i++) {
      names.add(i.toString());
    }

    // Add les propertes heritees enumerables (mais pas Object.prototype)
    final visited = <String>{};

    void collectInheritedProperties(JSObject obj) {
      if (obj._prototype != null && obj._prototype is JSObject) {
        final proto = obj._prototype as JSObject;

        // Arreter avant Object.prototype
        if (proto == JSObject.objectPrototype) return;

        // Collecter les propertes enumerables du prototype
        for (final key in proto._properties.keys) {
          if (proto._symbolKeys.containsKey(key)) continue;

          final descriptor = proto._propertyDescriptors[key];
          if (descriptor == null || descriptor.enumerable) {
            if (!visited.contains(key) && !names.contains(key)) {
              visited.add(key);
              names.add(key);
            }
          }
        }

        for (final key in proto._accessorProperties.keys) {
          if (proto._symbolKeys.containsKey(key)) continue;

          final descriptor = proto._accessorProperties[key];
          if (descriptor != null && descriptor.enumerable) {
            if (!visited.contains(key) && !names.contains(key)) {
              visited.add(key);
              names.add(key);
            }
          }
        }

        // Continuer avec le prototype du prototype
        collectInheritedProperties(proto);
      }
    }

    collectInheritedProperties(this);
    return names;
  }

  @override
  String toString() {
    // JavaScript: Array.prototype.toString() calls join(',')
    // Returns elements joined by commas, with null/undefined converted to empty string
    final result = StringBuffer();
    for (int i = 0; i < _elements.length; i++) {
      if (i > 0) result.write(',');
      final element = _elements[i];
      if (!element.isNull && !element.isUndefined) {
        result.write(element.toString());
      }
    }
    return result.toString();
  }

  /// Conversion vers une liste Dart avec les valeurs primitives
  List<dynamic> toList() {
    return _elements.map((element) {
      if (element.isNull || element.isUndefined) return null;
      if (element.isBoolean) return element.toBoolean();
      if (element.isNumber) {
        final num = element.toNumber();
        return num == num.truncateToDouble() ? num.toInt() : num;
      }
      if (element.isString) return element.toString();
      if (element is JSArray) {
        return element.elements.map((e) {
          if (e.isNull || e.isUndefined) return null;
          if (e.isBoolean) return e.toBoolean();
          if (e.isNumber) {
            final num = e.toNumber();
            return num == num.truncateToDouble() ? num.toInt() : num;
          }
          if (e.isString) return e.toString();
          if (e is JSArray) return e.toList();
          if (e is JSObject) return e.toMap();
          return e;
        }).toList();
      }
      if (element is JSObject) return element.toMap();
      return element;
    }).toList();
  }

  /// Conversion to primitive (for type coercion)
  String toPrimitive() => _elements.map((e) => e.toString()).join(',');

  /// Check if the array has an own element at the given index
  /// This is false for holes in sparse arrays
  bool hasOwnIndex(int index) {
    // Check accessor properties first (e.g., from Object.defineProperty)
    // Accessors take precedence over holes
    final indexStr = index.toString();
    if (_accessorProperties.containsKey(indexStr)) {
      return true;
    }

    // Check if it's a hole
    if (_holes.contains(index)) {
      return false;
    }

    // Check sparse storage
    if (index >= _sparseThreshold && _sparseElements != null) {
      return _sparseElements!.containsKey(index);
    }

    // For dense storage, check if index is in bounds
    if (index < 0 || index >= _elements.length) {
      return false;
    }

    return true;
  }

  /// Mark an index as a hole (elision in array literal)
  void markHole(int index) {
    _holes.add(index);
  }

  /// Check if an index is a hole
  bool isHole(int index) {
    return _holes.contains(index);
  }

  /// Override hasOwnProperty to handle array indices
  @override
  bool hasOwnProperty(String name) {
    // Check if it's a numeric array index
    final index = _parseArrayIndex(name);
    if (index != null) {
      return hasOwnIndex(index);
    }
    // For non-numeric properties, use parent implementation
    return super.hasOwnProperty(name);
  }

  @override
  bool deleteProperty(String name) {
    // For numeric indices, mark as a hole instead of just deleting
    final index = _parseArrayIndex(name);
    if (index != null) {
      // Mark the index as a hole to make hasOwnIndex return false
      markHole(index);

      // Also clear any sparse storage for this index
      if (index >= _sparseThreshold && _sparseElements != null) {
        _sparseElements!.remove(index);
      }

      // Also clear from dense storage if in range
      if (index < _elements.length) {
        _elements[index] = JSValueFactory.undefined();
      }

      // Also delete from accessor properties (Object.defineProperty with get/set)
      if (_accessorProperties.containsKey(name)) {
        _accessorProperties.remove(name);
      }

      // Also delete from property descriptors
      if (_propertyDescriptors.containsKey(name)) {
        _propertyDescriptors.remove(name);
      }

      return true;
    }

    // For non-numeric properties, use parent implementation
    return super.deleteProperty(name);
  }

  @override
  bool equals(JSValue other) {
    // Strict equality - same reference
    if (identical(this, other)) return true;

    // Egalite faible JavaScript - conversion ToPrimitive
    if (other.type == JSValueType.string) {
      return toPrimitive() == other.toString();
    }

    if (other.type == JSValueType.number) {
      final primitiveValue = toPrimitive();
      final numberValue = JSValueFactory.string(primitiveValue).toNumber();
      return numberValue == (other as JSNumber).value;
    }

    // Autres types - utiliser la logique by default of the object
    return identical(this, other);
  }

  // Heritees de JSObject, pas besoin de redefinir toObject, equals, strictEquals
}

/// Objet wrapper String JavaScript (cree avec new String(...))
/// Contrairement a JSString (primitive), c'est an object avec des propertes
class JSStringObject extends JSObject {
  final String _value;

  // Static prototype for all String objects
  static JSObject? _stringPrototype;

  static void setStringPrototype(JSObject prototype) {
    final manager = PrototypeManager.current;
    if (manager != null) {
      manager.setStringPrototype(prototype);
    }
    // Always set static as fallback
    _stringPrototype = prototype;
  }

  static JSObject? get stringPrototype {
    final manager = PrototypeManager.current;
    if (manager != null && manager.stringPrototype != null) {
      return manager.stringPrototype;
    }
    return _stringPrototype;
  }

  JSStringObject(this._value) : super() {
    // Set the prototype to String.prototype if available
    final proto = stringPrototype;
    if (proto != null) {
      setPrototype(proto);
    }

    // Definir length comme properte propre (read-only)
    _propertyDescriptors['length'] = PropertyDescriptor(
      value: JSValueFactory.number(_value.length),
      writable: false,
      enumerable: false,
      configurable: false,
    );
    _properties['length'] = JSValueFactory.number(_value.length);

    // Definir chaque caractere comme properte indexee
    for (int i = 0; i < _value.length; i++) {
      final indexStr = i.toString();
      _propertyDescriptors[indexStr] = PropertyDescriptor(
        value: JSValueFactory.string(_value[i]),
        writable: false,
        enumerable: true,
        configurable: false,
      );
      _properties[indexStr] = JSValueFactory.string(_value[i]);
    }

    // Marquer comme objet String pour Symbol.toStringTag
    _properties['[[InternalType]]'] = JSValueFactory.string('String');
  }

  /// La valeur primitive of the string
  String get value => _value;

  @override
  JSValue getProperty(String name) {
    // Special support for __proto__
    if (name == '__proto__') {
      return _prototype ?? JSValueFactory.nullValue();
    }
    // Check d'abord les propertes propres (length, indices)
    if (_properties.containsKey(name)) {
      return _properties[name]!;
    }

    // First check _prototype (String.prototype) which has 'constructor' property
    if (_prototype != null) {
      final protoValue = _prototype!.getProperty(name);
      if (!protoValue.isUndefined) {
        return protoValue;
      }
    }

    // Fall back to StringPrototype static methods for string-specific methods
    final stringMethod = StringPrototype.getStringProperty(_value, name);
    if (!stringMethod.isUndefined) {
      return stringMethod;
    }

    // Finally check Object.prototype
    return JSObject.objectPrototype.getProperty(name);
  }

  @override
  void setProperty(String name, JSValue value) {
    // length et les indices sont read-only
    if (name == 'length' || int.tryParse(name) != null) {
      // Silently ignore in non-strict mode (comme en JS)
      return;
    }
    super.setProperty(name, value);
  }

  @override
  bool hasOwnProperty(String name) {
    if (name == 'length') return true;
    final index = int.tryParse(name);
    if (index != null && index >= 0 && index < _value.length) {
      return true;
    }
    return super.hasOwnProperty(name);
  }

  @override
  List<String> getPropertyNames({bool enumerableOnly = false}) {
    final names = <String>[];
    // Indices de caracteres (enumerables)
    for (int i = 0; i < _value.length; i++) {
      names.add(i.toString());
    }
    // length n'est pas enumerable
    if (!enumerableOnly) {
      names.add('length');
    }
    names.addAll(super.getPropertyNames(enumerableOnly: enumerableOnly));
    return names;
  }

  @override
  String toString() => _value;

  @override
  double toNumber() => double.tryParse(_value) ?? double.nan;

  @override
  bool equals(JSValue other) {
    // When comparing a String object with another value using ==,
    // convert this to its primitive value first (ToPrimitive)
    if (other is JSString) {
      return _value == other.value;
    } else if (other is JSStringObject) {
      return _value == other._value;
    }
    // For other types, convert both to primitives and compare
    // This handles cases like new String("5") == 5
    return JSString(_value).equals(other);
  }
}

/// Objet Map JavaScript
class JSMap extends JSObject {
  final Map<JSValue, JSValue> _map = {};

  JSMap() : super() {
    initializeIterator();
  }

  /// Add ou mettre a jour une paire cle-valeur
  JSValue set(JSValue key, JSValue value) {
    _map[key] = value;
    return JSValueFactory.undefined(); // Returns undefined comme en JS standard
  }

  /// Recuperer la valeur associee a une cle
  JSValue get(JSValue key) {
    return _map[key] ?? JSValueFactory.undefined();
  }

  /// Check si une cle existe
  JSValue has(JSValue key) {
    return JSValueFactory.boolean(_map.containsKey(key));
  }

  /// Remove une paire cle-valeur
  JSValue delete(JSValue key) {
    final existed = _map.containsKey(key);
    _map.remove(key);
    return JSValueFactory.boolean(existed);
  }

  /// Vider la map
  JSValue clear() {
    _map.clear();
    return JSValueFactory.undefined();
  }

  /// Get la taille de la map
  int get size => _map.length;

  /// Get les entrees de la map pour l'iteration
  Iterable<MapEntry<JSValue, JSValue>> get entries => _map.entries;

  @override
  JSValue getProperty(String name) {
    return MapPrototype.getMapProperty(this, name);
  }

  @override
  String toString() => '[object Map]';

  /// Conversion to primitive (for type coercion)
  String toPrimitive() => '[object Map]';

  @override
  bool equals(JSValue other) {
    // Strict equality - same reference
    return identical(this, other);
  }
}

/// Prototype pour les objets Map
class MapPrototype {
  /// Map.prototype.set(key, value)
  static JSValue set(List<JSValue> args, JSMap map) {
    if (args.length < 2) {
      throw JSTypeError('Map.prototype.set requires at least 2 arguments');
    }
    return map.set(args[0], args[1]);
  }

  /// Map.prototype.get(key)
  static JSValue get(List<JSValue> args, JSMap map) {
    if (args.isEmpty) {
      throw JSTypeError('Map.prototype.get requires 1 argument');
    }
    return map.get(args[0]);
  }

  /// Map.prototype.has(key)
  static JSValue has(List<JSValue> args, JSMap map) {
    if (args.isEmpty) {
      throw JSTypeError('Map.prototype.has requires 1 argument');
    }
    return map.has(args[0]);
  }

  /// Map.prototype.delete(key)
  static JSValue delete_(List<JSValue> args, JSMap map) {
    if (args.isEmpty) {
      throw JSTypeError('Map.prototype.delete requires 1 argument');
    }
    return map.delete(args[0]);
  }

  /// Map.prototype.clear()
  static JSValue clear(List<JSValue> args, JSMap map) {
    return map.clear();
  }

  /// Get a property of the object Map
  static JSValue getMapProperty(JSMap map, String name) {
    // First check if it's one of the special Map properties
    switch (name) {
      case 'set':
        return JSNativeFunction(
          functionName: 'set',
          nativeImpl: (args) => set(args, map),
        );
      case 'get':
        return JSNativeFunction(
          functionName: 'get',
          nativeImpl: (args) => get(args, map),
        );
      case 'has':
        return JSNativeFunction(
          functionName: 'has',
          nativeImpl: (args) => has(args, map),
        );
      case 'delete':
        return JSNativeFunction(
          functionName: 'delete',
          nativeImpl: (args) => delete_(args, map),
        );
      case 'clear':
        return JSNativeFunction(
          functionName: 'clear',
          nativeImpl: (args) => clear(args, map),
        );
      case 'size':
        return JSValueFactory.number(map.size.toDouble());
      case 'entries':
        return JSNativeFunction(
          functionName: 'entries',
          nativeImpl: (args) => JSMapIterator(map, IteratorKind.entries),
        );
      case 'keys':
        return JSNativeFunction(
          functionName: 'keys',
          nativeImpl: (args) => JSMapIterator(map, IteratorKind.keys),
        );
      case 'values':
        return JSNativeFunction(
          functionName: 'values',
          nativeImpl: (args) => JSMapIterator(map, IteratorKind.valueKind),
        );
      default:
        // Check the object's own properties first
        if (map._properties.containsKey(name)) {
          return map._properties[name]!;
        }
        // Then check the prototype
        return JSObject.objectPrototype.getProperty(name);
    }
  }
}

/// Objet Set JavaScript
class JSSet extends JSObject {
  final Set<JSValue> _set = {};

  JSSet() : super() {
    initializeIterator();
  }

  /// Add un element au set
  JSValue add(JSValue value) {
    _set.add(value);
    return this; // Returns this pour permettre le chainage
  }

  /// Check si un element existe
  JSValue has(JSValue value) {
    return JSValueFactory.boolean(_set.contains(value));
  }

  /// Remove un element du set
  JSValue delete(JSValue value) {
    final existed = _set.contains(value);
    _set.remove(value);
    return JSValueFactory.boolean(existed);
  }

  /// Vider le set
  JSValue clear() {
    _set.clear();
    return JSValueFactory.undefined();
  }

  /// Get la taille du set
  int get size => _set.length;

  /// Get les valeurs du set pour l'iteration
  Iterable<JSValue> get values => _set;

  @override
  JSValue getProperty(String name) {
    return SetPrototype.getSetProperty(this, name);
  }

  @override
  String toString() => '[object Set]';

  /// Conversion to primitive (for type coercion)
  String toPrimitive() => '[object Set]';

  @override
  bool equals(JSValue other) {
    // Strict equality - same reference
    return identical(this, other);
  }
}

/// Prototype pour les objets Set
class SetPrototype {
  /// Set.prototype.add(value)
  static JSValue add(List<JSValue> args, JSSet set) {
    if (args.isEmpty) {
      throw JSTypeError('Set.prototype.add requires 1 argument');
    }
    return set.add(args[0]);
  }

  /// Set.prototype.has(value)
  static JSValue has(List<JSValue> args, JSSet set) {
    if (args.isEmpty) {
      throw JSTypeError('Set.prototype.has requires 1 argument');
    }
    return set.has(args[0]);
  }

  /// Set.prototype.delete(value)
  static JSValue delete_(List<JSValue> args, JSSet set) {
    if (args.isEmpty) {
      throw JSTypeError('Set.prototype.delete requires 1 argument');
    }
    return set.delete(args[0]);
  }

  /// Set.prototype.clear()
  static JSValue clear(List<JSValue> args, JSSet set) {
    return set.clear();
  }

  /// Get a property of the object Set
  static JSValue getSetProperty(JSSet set, String name) {
    switch (name) {
      case 'add':
        return JSNativeFunction(
          functionName: 'add',
          nativeImpl: (args) => add(args, set),
        );
      case 'has':
        return JSNativeFunction(
          functionName: 'has',
          nativeImpl: (args) => has(args, set),
        );
      case 'delete':
        return JSNativeFunction(
          functionName: 'delete',
          nativeImpl: (args) => delete_(args, set),
        );
      case 'clear':
        return JSNativeFunction(
          functionName: 'clear',
          nativeImpl: (args) => clear(args, set),
        );
      case 'size':
        return JSValueFactory.number(set.size.toDouble());
      case 'values':
        return JSNativeFunction(
          functionName: 'values',
          nativeImpl: (args) => JSSetIterator(set),
        );
      default:
        // Check the object's own properties first
        if (set._properties.containsKey(name)) {
          return set._properties[name]!;
        }
        // Then check the prototype
        return JSObject.objectPrototype.getProperty(name);
    }
  }
}

/// WeakMap implementation - Map with weak references to keys
class JSWeakMap extends JSObject {
  // Using Expando for weak references - Dart's Expando provides weak key references
  final Expando<JSValue> _map = Expando<JSValue>();

  JSWeakMap() : super() {
    // Initialize prototype methods
    _initializePrototype();
  }

  // Public method to set a value (used by constructor)
  void setValue(JSObject key, JSValue value) {
    _map[key] = value;
  }

  void _initializePrototype() {
    // WeakMap.prototype.set(key, value)
    _properties['set'] = JSNativeFunction(
      functionName: 'set',
      nativeImpl: (args) {
        if (args.isEmpty) {
          throw JSTypeError(
            'WeakMap.prototype.set requires at least 1 argument',
          );
        }

        final key = args[0];
        if (key is! JSObject) {
          throw JSTypeError('WeakMap keys must be objects');
        }

        final value = args.length > 1 ? args[1] : JSValueFactory.undefined();
        _map[key] = value;

        return this;
      },
    );

    // WeakMap.prototype.get(key)
    _properties['get'] = JSNativeFunction(
      functionName: 'get',
      nativeImpl: (args) {
        if (args.isEmpty) {
          throw JSTypeError('WeakMap.prototype.get requires 1 argument');
        }

        final key = args[0];
        if (key is! JSObject) {
          throw JSTypeError('WeakMap keys must be objects');
        }

        return _map[key] ?? JSValueFactory.undefined();
      },
    );

    // WeakMap.prototype.has(key)
    _properties['has'] = JSNativeFunction(
      functionName: 'has',
      nativeImpl: (args) {
        if (args.isEmpty) {
          throw JSTypeError('WeakMap.prototype.has requires 1 argument');
        }

        final key = args[0];
        if (key is! JSObject) {
          throw JSTypeError('WeakMap keys must be objects');
        }

        return JSValueFactory.boolean(_map[key] != null);
      },
    );

    // WeakMap.prototype.delete(key)
    _properties['delete'] = JSNativeFunction(
      functionName: 'delete',
      nativeImpl: (args) {
        if (args.isEmpty) {
          throw JSTypeError('WeakMap.prototype.delete requires 1 argument');
        }

        final key = args[0];
        if (key is! JSObject) {
          throw JSTypeError('WeakMap keys must be objects');
        }

        final hadKey = _map[key] != null;
        _map[key] = null; // Remove the entry

        return JSValueFactory.boolean(hadKey);
      },
    );
  }

  @override
  String toString() => '[object WeakMap]';

  @override
  bool equals(JSValue other) {
    return identical(this, other);
  }
}

/// WeakSet implementation - Set with weak references to values
class JSWeakSet extends JSObject {
  // Using Expando for weak references
  final Expando<bool> _set = Expando<bool>();

  JSWeakSet() : super() {
    // Initialize prototype methods
    _initializePrototype();
  }

  // Public method to add a value (used by constructor)
  void addValue(JSObject value) {
    _set[value] = true;
  }

  void _initializePrototype() {
    // WeakSet.prototype.add(value)
    _properties['add'] = JSNativeFunction(
      functionName: 'add',
      nativeImpl: (args) {
        if (args.isEmpty) {
          throw JSTypeError('WeakSet.prototype.add requires 1 argument');
        }

        final value = args[0];
        if (value is! JSObject) {
          throw JSTypeError('WeakSet values must be objects');
        }

        _set[value] = true;
        return this;
      },
    );

    // WeakSet.prototype.has(value)
    _properties['has'] = JSNativeFunction(
      functionName: 'has',
      nativeImpl: (args) {
        if (args.isEmpty) {
          throw JSTypeError('WeakSet.prototype.has requires 1 argument');
        }

        final value = args[0];
        if (value is! JSObject) {
          throw JSTypeError('WeakSet values must be objects');
        }

        return JSValueFactory.boolean(_set[value] == true);
      },
    );

    // WeakSet.prototype.delete(value)
    _properties['delete'] = JSNativeFunction(
      functionName: 'delete',
      nativeImpl: (args) {
        if (args.isEmpty) {
          throw JSTypeError('WeakSet.prototype.delete requires 1 argument');
        }

        final value = args[0];
        if (value is! JSObject) {
          throw JSTypeError('WeakSet values must be objects');
        }

        final hadValue = _set[value] == true;
        _set[value] = null; // Remove the entry

        return JSValueFactory.boolean(hadValue);
      },
    );
  }

  @override
  String toString() => '[object WeakSet]';

  @override
  bool equals(JSValue other) {
    return identical(this, other);
  }
}

/// Proxy implementation - Metaprogramming proxy with traps
class JSProxy extends JSObject {
  final JSValue _target;
  late final JSObject _handler;

  JSProxy(this._target, JSValue handler) : super() {
    if (handler is! JSObject) {
      throw JSTypeError('Proxy handler must be an object');
    }
    _handler = handler;
  }

  /// Get the target of this proxy
  JSValue get target => _target;

  /// Set the internal prototype without triggering the setPrototypeOf trap
  /// This is used during Proxy construction
  void setInternalPrototype(JSObject? prototype) {
    super.setPrototype(prototype);
  }

  @override
  JSValue getProperty(String name) {
    // Check if handler has a 'get' trap
    final getTrap = _handler.getProperty('get');
    if (getTrap is JSFunction) {
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        return evaluator.callFunction(getTrap, [
          _target,
          JSValueFactory.string(name),
          this,
        ], _handler);
      }
    }

    // Default behavior: delegate to target
    if (_target is JSObject) {
      return _target.getProperty(name);
    }

    // Handle function targets (JSFunction, JSNativeFunction, etc.)
    if (_target is JSFunction) {
      return _target.getProperty(name);
    }
    if (_target is JSNativeFunction) {
      return _target.getProperty(name);
    }

    return JSValueFactory.undefined();
  }

  @override
  void setProperty(String name, JSValue value) {
    // Check if handler has a 'set' trap
    final setTrap = _handler.getProperty('set');
    if (setTrap is JSFunction) {
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        final result = evaluator.callFunction(setTrap, [
          _target,
          JSValueFactory.string(name),
          value,
          this,
        ], _handler);
        if (!result.toBoolean()) {
          throw JSTypeError('Proxy set trap returned false');
        }
        return;
      }
    }

    // Default behavior: delegate to target
    if (_target is JSObject) {
      _target.setProperty(name, value);
    } else if (_target is JSFunction) {
      _target.setProperty(name, value);
    } else if (_target is JSNativeFunction) {
      _target.setProperty(name, value);
    }
  }

  @override
  bool hasProperty(String name) {
    // Check if handler has a 'has' trap
    final hasTrap = _handler.getProperty('has');
    if (hasTrap is JSFunction) {
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        final result = evaluator.callFunction(hasTrap, [
          _target,
          JSValueFactory.string(name),
        ], _handler);
        return result.toBoolean();
      }
    }

    // Default behavior: delegate to target
    if (_target is JSObject) {
      return _target.hasProperty(name);
    } else if (_target is JSFunction) {
      return _target.hasProperty(name);
    } else if (_target is JSNativeFunction) {
      return _target.hasProperty(name);
    }
    return false;
  }

  @override
  bool deleteProperty(String name) {
    // Check if handler has a 'deleteProperty' trap
    final deleteTrap = _handler.getProperty('deleteProperty');
    if (deleteTrap is JSFunction) {
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        final result = evaluator.callFunction(deleteTrap, [
          _target,
          JSValueFactory.string(name),
        ], _handler);
        if (!result.toBoolean()) {
          throw JSTypeError('Cannot delete property');
        }
        return true;
      }
    }

    // Default behavior: delegate to target
    if (_target is JSObject) {
      return _target.deleteProperty(name);
    } else if (_target is JSFunction) {
      return _target.deleteProperty(name);
    } else if (_target is JSNativeFunction) {
      return _target.deleteProperty(name);
    }
    return false;
  }

  JSValue call(List<JSValue> args) {
    // Check if handler has an 'apply' trap
    final applyTrap = _handler.getProperty('apply');
    if (applyTrap is JSFunction) {
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        try {
          return evaluator.callFunction(applyTrap, [
            _target,
            this,
            JSValueFactory.array(args),
          ], _handler);
        } catch (e) {
          throw JSError('Proxy apply trap threw: $e');
        }
      }
    }

    // Default behavior: delegate to target
    if (_target is JSFunction) {
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        return evaluator.callFunction(
          _target,
          args,
          JSValueFactory.undefined(),
        );
      }
    }

    throw JSTypeError('Proxy target is not callable');
  }

  JSValue construct(List<JSValue> args) {
    // Check if handler has a 'construct' trap
    final constructTrap = _handler.getProperty('construct');
    if (constructTrap is JSFunction) {
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        try {
          final result = evaluator.callFunction(constructTrap, [
            _target,
            JSValueFactory.array(args),
          ], _handler);
          if (result is! JSObject) {
            throw JSTypeError('Proxy construct trap must return an object');
          }
          return result;
        } catch (e) {
          if (e is JSTypeError && e.message.contains('must return an object')) {
            rethrow;
          }
          throw JSError('Proxy construct trap threw: $e');
        }
      }
    }

    // Default behavior: delegate to target
    if (_target is JSFunction) {
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        // Create new object and call function as constructor
        final newObject = JSObject();
        final prototypeValue = _target.getProperty('prototype');
        if (prototypeValue is JSObject) {
          newObject.setPrototype(prototypeValue);
        }
        newObject.setProperty('constructor', _target);
        evaluator.callFunction(_target, args, newObject);
        return newObject;
      }
    }

    throw JSTypeError('Proxy target is not a constructor');
  }

  @override
  JSObject? getPrototype() {
    // Check if handler has a 'getPrototypeOf' trap
    final getPrototypeTrap = _handler.getProperty('getPrototypeOf');
    if (getPrototypeTrap is JSFunction) {
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        final result = evaluator.callFunction(getPrototypeTrap, [
          _target,
        ], _handler);
        if (result is JSObject || result.type == JSValueType.nullType) {
          return result as JSObject?;
        }
        throw JSTypeError(
          'Proxy getPrototypeOf trap must return an object or null',
        );
      }
    }

    // Default behavior: delegate to target
    if (_target is JSObject) {
      return _target.getPrototype();
    }
    return null;
  }

  @override
  void setPrototype(JSObject? prototype) {
    // Check if handler has a 'setPrototypeOf' trap
    final setPrototypeTrap = _handler.getProperty('setPrototypeOf');
    if (setPrototypeTrap is JSFunction) {
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        final result = evaluator.callFunction(setPrototypeTrap, [
          _target,
          prototype ?? JSValueFactory.nullValue(),
        ], _handler);
        if (!result.toBoolean()) {
          throw JSTypeError('Proxy setPrototypeOf trap returned false');
        }
        return;
      }
    }

    // Default behavior: delegate to target
    if (_target is JSObject) {
      _target.setPrototype(prototype);
    }
  }

  List<String> getOwnPropertyNames() {
    // Check if handler has an 'ownKeys' trap
    final ownKeysTrap = _handler.getProperty('ownKeys');
    if (ownKeysTrap is JSFunction) {
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        try {
          final result = evaluator.callFunction(ownKeysTrap, [
            _target,
          ], _handler);
          if (result is JSArray) {
            return result.elements
                .whereType<JSString>()
                .map((element) => element.value)
                .toList();
          }
          throw JSTypeError('Proxy ownKeys trap must return an array');
        } catch (e) {
          if (e is JSTypeError && e.message.contains('must return an array')) {
            rethrow;
          }
          throw JSError('Proxy ownKeys trap threw: $e');
        }
      }
    }

    // Default behavior: delegate to target
    if (_target is JSObject) {
      return _target.getPropertyNames();
    }
    // For function targets, return an empty list (functions don't enumerate properties this way)
    return [];
  }

  @override
  String toString() => '[object Proxy]';

  @override
  bool equals(JSValue other) {
    return identical(this, other);
  }

  // Helper method to get the revocable proxy
  static JSObject revocable(JSValue target, JSValue handler) {
    if (target is! JSObject) {
      throw JSTypeError('Proxy.revocable target must be an object');
    }
    if (handler is! JSObject) {
      throw JSTypeError('Proxy.revocable handler must be an object');
    }

    final proxy = JSProxy(target, handler);
    var revoked = false;

    final revokeFunction = JSNativeFunction(
      functionName: 'revoke',
      nativeImpl: (args) {
        if (!revoked) {
          revoked = true;
        }
        return JSValueFactory.undefined();
      },
    );

    final result = JSObject();
    result.setProperty('proxy', proxy);
    result.setProperty('revoke', revokeFunction);

    return result;
  }
}

/// Reflect implementation - Reflection API companion to Proxy
class JSReflect extends JSObject {
  JSReflect() : super() {
    _initializeStaticMethods();
  }

  void _initializeStaticMethods() {
    // Reflect.get(target, propertyKey[, receiver])
    setProperty(
      'get',
      JSNativeFunction(
        functionName: 'Reflect.get',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError('Reflect.get requires at least 2 arguments');
          }

          final target = args[0];
          final propertyKey = args[1];
          // receiver is not used in this implementation

          if (target is! JSObject) {
            throw JSTypeError('Reflect.get target must be an object');
          }

          final propName = propertyKey.toString();
          return target.getProperty(propName);
        },
      ),
    );

    // Reflect.set(target, propertyKey, value[, receiver])
    setProperty(
      'set',
      JSNativeFunction(
        functionName: 'Reflect.set',
        nativeImpl: (args) {
          if (args.length < 3) {
            throw JSTypeError('Reflect.set requires at least 3 arguments');
          }

          final target = args[0];
          final propertyKey = args[1];
          final value = args[2];
          // receiver is not used in this implementation

          if (target is! JSObject) {
            throw JSTypeError('Reflect.set target must be an object');
          }

          final propName = propertyKey.toString();
          try {
            target.setProperty(propName, value);
            return JSValueFactory.boolean(true);
          } on JSError {
            // Per ES6 spec, Reflect.set returns false if the operation fails
            // JSError (including JSTypeError) means the operation failed
            return JSValueFactory.boolean(false);
          } catch (e) {
            // Other exceptions are unexpected, so rethrow
            rethrow;
          }
        },
      ),
    );

    // Reflect.has(target, propertyKey)
    setProperty(
      'has',
      JSNativeFunction(
        functionName: 'Reflect.has',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError('Reflect.has requires 2 arguments');
          }

          final target = args[0];
          final propertyKey = args[1];

          if (target is! JSObject) {
            throw JSTypeError('Reflect.has target must be an object');
          }

          final propName = propertyKey.toString();
          return JSValueFactory.boolean(target.hasProperty(propName));
        },
      ),
    );

    // Reflect.deleteProperty(target, propertyKey)
    setProperty(
      'deleteProperty',
      JSNativeFunction(
        functionName: 'Reflect.deleteProperty',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError('Reflect.deleteProperty requires 2 arguments');
          }

          final target = args[0];
          final propertyKey = args[1];

          if (target is! JSObject) {
            throw JSTypeError(
              'Reflect.deleteProperty target must be an object',
            );
          }

          final propName = propertyKey.toString();
          final deleted = target.deleteProperty(propName);
          return JSValueFactory.boolean(deleted);
        },
      ),
    );

    // Reflect.apply(target, thisArgument, argumentsList)
    setProperty(
      'apply',
      JSNativeFunction(
        functionName: 'Reflect.apply',
        nativeImpl: (args) {
          if (args.length < 3) {
            throw JSTypeError('Reflect.apply requires 3 arguments');
          }

          final target = args[0];
          final thisArg = args[1];
          final argumentsList = args[2];

          if (target is! JSFunction) {
            throw JSTypeError('Reflect.apply target must be a function');
          }

          if (argumentsList is! JSArray) {
            throw JSTypeError('Reflect.apply argumentsList must be an array');
          }

          final evaluator = JSEvaluator.currentInstance;
          if (evaluator != null) {
            return evaluator.callFunction(
              target,
              argumentsList.elements,
              thisArg,
            );
          }

          throw JSError('No evaluator available for Reflect.apply');
        },
      ),
    );

    // Reflect.construct(target, argumentsList[, newTarget])
    setProperty(
      'construct',
      JSNativeFunction(
        functionName: 'Reflect.construct',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError(
              'Reflect.construct requires at least 2 arguments',
            );
          }

          final target = args[0];
          final argumentsList = args[1];
          final newTarget = args.length > 2 ? args[2] : target;

          if (target is! JSFunction) {
            throw JSTypeError('Reflect.construct target must be a constructor');
          }

          if (argumentsList is! JSArray) {
            throw JSTypeError(
              'Reflect.construct argumentsList must be an array',
            );
          }

          // newTarget must be a constructor if specified
          if (newTarget != target && newTarget is! JSFunction) {
            throw JSTypeError(
              'Reflect.construct newTarget must be a constructor',
            );
          }

          final evaluator = JSEvaluator.currentInstance;
          if (evaluator != null) {
            // Create new object
            final newObject = JSObject();

            // For Promise constructor specifically, we need to call it BEFORE
            // accessing NewTarget.prototype. This matches the spec where executor
            // validation (step 2) happens BEFORE GetPrototypeFromConstructor (step 3).
            if (target.functionName == 'Promise') {
              // Call the constructor with no prototype pre-set
              // The constructor will validate the executor and throw if invalid
              try {
                evaluator.callFunction(
                  target,
                  argumentsList.elements,
                  newObject,
                );
              } on JSTypeError catch (e) {
                // Convert Dart JSTypeError to JavaScript TypeError
                final errorValue = JSErrorObjectFactory.fromDartError(e);
                throw JSException(errorValue);
              }

              // Only after constructor succeeds, set the proper prototype
              final constructorForProto = newTarget is JSFunction
                  ? newTarget
                  : target;
              final prototypeValue = constructorForProto.getProperty(
                'prototype',
              );
              if (prototypeValue is JSObject) {
                newObject.setPrototype(prototypeValue);
              }
            } else {
              // For other constructors, set prototype first (original behavior)
              final constructorForProto = newTarget is JSFunction
                  ? newTarget
                  : target;
              final prototypeValue = constructorForProto.getProperty(
                'prototype',
              );
              if (prototypeValue is JSObject) {
                newObject.setPrototype(prototypeValue);
              }
              try {
                evaluator.callFunction(
                  target,
                  argumentsList.elements,
                  newObject,
                );
              } on JSTypeError catch (e) {
                // Convert Dart JSTypeError to JavaScript TypeError
                final errorValue = JSErrorObjectFactory.fromDartError(e);
                throw JSException(errorValue);
              }
            }

            newObject.setProperty('constructor', target);
            return newObject;
          }

          throw JSError('No evaluator available for Reflect.construct');
        },
      ),
    );

    // Reflect.getPrototypeOf(target)
    setProperty(
      'getPrototypeOf',
      JSNativeFunction(
        functionName: 'Reflect.getPrototypeOf',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSTypeError('Reflect.getPrototypeOf requires 1 argument');
          }

          final target = args[0];
          if (target is! JSObject) {
            throw JSTypeError(
              'Reflect.getPrototypeOf target must be an object',
            );
          }

          return target.getPrototype() ?? JSValueFactory.nullValue();
        },
      ),
    );

    // Reflect.setPrototypeOf(target, prototype)
    setProperty(
      'setPrototypeOf',
      JSNativeFunction(
        functionName: 'Reflect.setPrototypeOf',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError('Reflect.setPrototypeOf requires 2 arguments');
          }

          final target = args[0];
          final prototype = args[1];

          if (target is! JSObject) {
            throw JSTypeError(
              'Reflect.setPrototypeOf target must be an object',
            );
          }

          if (prototype is! JSObject &&
              prototype.type != JSValueType.nullType) {
            throw JSTypeError(
              'Reflect.setPrototypeOf prototype must be an object or null',
            );
          }

          target.setPrototype(prototype as JSObject);
          return JSValueFactory.boolean(true);
        },
      ),
    );

    // Reflect.ownKeys(target)
    setProperty(
      'ownKeys',
      JSNativeFunction(
        functionName: 'Reflect.ownKeys',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSTypeError('Reflect.ownKeys requires 1 argument');
          }

          final target = args[0];
          if (target is! JSObject) {
            throw JSTypeError('Reflect.ownKeys target must be an object');
          }

          final keys = target.getPropertyNames();
          return JSValueFactory.array(
            keys.map((key) => JSValueFactory.string(key)).toList(),
          );
        },
      ),
    );

    // Reflect.preventExtensions(target)
    setProperty(
      'preventExtensions',
      JSNativeFunction(
        functionName: 'Reflect.preventExtensions',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSTypeError('Reflect.preventExtensions requires 1 argument');
          }

          final target = args[0];
          if (target is! JSObject) {
            throw JSTypeError(
              'Reflect.preventExtensions target must be an object',
            );
          }

          // Marquer l'objet comme non-extensible
          target.isExtensible = false;
          return JSValueFactory.boolean(true);
        },
      ),
    );

    // Reflect.isExtensible(target)
    setProperty(
      'isExtensible',
      JSNativeFunction(
        functionName: 'Reflect.isExtensible',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSTypeError('Reflect.isExtensible requires 1 argument');
          }

          final target = args[0];
          if (target is! JSObject) {
            throw JSTypeError('Reflect.isExtensible target must be an object');
          }

          return JSValueFactory.boolean(target.isExtensible);
        },
      ),
    );
  }

  @override
  String toString() => '[object Reflect]';

  @override
  bool equals(JSValue other) {
    return identical(this, other);
  }
}

class JSBooleanObject extends JSObject {
  @override
  final bool primitiveValue;

  // Static prototype for all Boolean objects
  static JSObject? _booleanPrototype;

  static void setBooleanPrototype(JSObject prototype) {
    final manager = PrototypeManager.current;
    if (manager != null) {
      manager.setBooleanPrototype(prototype);
    }
    // Always set static as fallback
    _booleanPrototype = prototype;
  }

  static JSObject? get booleanPrototype {
    final manager = PrototypeManager.current;
    if (manager != null && manager.booleanPrototype != null) {
      return manager.booleanPrototype;
    }
    return _booleanPrototype;
  }

  JSBooleanObject(this.primitiveValue) {
    // Set the prototype to Boolean.prototype if available
    final proto = booleanPrototype;
    if (proto != null) {
      setPrototype(proto);
    }
  }

  @override
  JSValue getProperty(String name) {
    // Let methods come from the prototype (Boolean.prototype)
    // This ensures valueOf and toString are the same as Boolean.prototype.valueOf/toString
    return super.getProperty(name);
  }

  @override
  bool equals(JSValue other) {
    // When comparing a Boolean object with another value using ==,
    // convert this to its primitive value first (ToPrimitive)
    if (other is JSBoolean) {
      return primitiveValue == other.value;
    } else if (other is JSBooleanObject) {
      return primitiveValue == other.primitiveValue;
    }
    // For other types, convert both to primitives and compare
    return JSBoolean(primitiveValue).equals(other);
  }
}

class JSNumberObject extends JSObject {
  @override
  final double primitiveValue;

  // Static prototype for all Number objects
  static JSObject? _numberPrototype;

  static void setNumberPrototype(JSObject prototype) {
    final manager = PrototypeManager.current;
    if (manager != null) {
      manager.setNumberPrototype(prototype);
    }
    // Always set static as fallback
    _numberPrototype = prototype;
  }

  static JSObject? get numberPrototype {
    final manager = PrototypeManager.current;
    if (manager != null && manager.numberPrototype != null) {
      return manager.numberPrototype;
    }
    return _numberPrototype;
  }

  JSNumberObject(this.primitiveValue) {
    // Set the prototype to Number.prototype if available
    final proto = numberPrototype;
    if (proto != null) {
      setPrototype(proto);
    }
  }

  @override
  double toNumber() => primitiveValue;

  @override
  String toString() => primitiveValue.toString();

  @override
  JSValue getProperty(String name) {
    // Let methods come from the prototype (Number.prototype)
    // This ensures valueOf and toString are the same as Number.prototype.valueOf/toString
    return super.getProperty(name);
  }

  @override
  bool equals(JSValue other) {
    // When comparing a Number object with another value using ==,
    // convert this to its primitive value first (ToPrimitive)
    if (other is JSNumber) {
      return primitiveValue == other.value;
    } else if (other is JSNumberObject) {
      return primitiveValue == other.primitiveValue;
    }
    // For other types, convert both to primitives and compare
    return JSNumber(primitiveValue).equals(other);
  }
}

class JSBigIntObject extends JSObject {
  @override
  final BigInt primitiveValue;
  JSBigIntObject(this.primitiveValue);
}

/// Factory to create JSValue
class JSValueFactory {
  static JSValue undefined() => JSUndefined.instance;
  static JSValue nullValue() => JSNull.instance;
  static JSValue boolean(bool value) => JSBoolean(value);
  static JSValue number(num value) => JSNumber(value.toDouble());
  static JSValue bigint(BigInt value) => JSBigInt(value);
  static JSValue symbol([String? description]) =>
      JSSymbol(description) as JSValue;
  static JSValue string(String value) => JSString(value);
  static JSObject object([Map<String, JSValue>? properties]) {
    final obj = JSObject();
    if (properties != null) {
      for (final entry in properties.entries) {
        obj.setProperty(entry.key, entry.value);
      }
    }
    return obj;
  }

  /// Creates an arguments object with restricted access to callee/caller
  static JSObject argumentsObject([Map<String, JSValue>? properties]) {
    final obj = object(properties);
    obj.markAsArgumentsObject();
    return obj;
  }

  static JSValue function(
    dynamic declaration,
    dynamic environment, {
    String? sourceText,
    bool strictMode = false,
  }) => JSFunction(
    declaration,
    environment,
    sourceText: sourceText ?? declaration?.toString(),
    strictMode: strictMode,
  );

  static JSArray array([List<JSValue>? elements]) => JSArray(elements);
  static JSClass classValue(
    dynamic declaration,
    dynamic environment, [
    JSClass? superClass,
    JSFunction? superFunction,
    bool extendsNull = false,
    JSValue? superFunctionPrototype,
  ]) => JSClass(
    declaration,
    environment,
    superClass,
    superFunction,
    extendsNull,
    superFunctionPrototype,
  );

  /// Create a JSValue from a Dart value
  static JSValue fromDart(dynamic value) {
    // If it's already a JSValue, return it directly
    if (value is JSValue) return value;

    if (value == null) return nullValue();
    if (value is bool) return boolean(value);
    if (value is num) return number(value);
    if (value is String) return string(value);

    // Support for lists
    if (value is List) {
      final jsValues = value.map((item) => fromDart(item)).toList();
      return array(jsValues);
    }

    // Support for maps
    if (value is Map<String, dynamic>) {
      final jsObject = object({});
      value.forEach((key, val) {
        jsObject.setProperty(key, fromDart(val));
      });
      return jsObject;
    }

    // Support for maps generiques
    if (value is Map) {
      final jsObject = object({});
      value.forEach((key, val) {
        jsObject.setProperty(key.toString(), fromDart(val));
      });
      return jsObject;
    }

    // Support for Dart functions
    if (value is Function) {
      // Create a real JavaScript function that wraps the Dart function
      return JSNativeFunction(
        functionName: 'dartFunction',
        nativeImpl: (List<JSValue> args) {
          try {
            // Convert JS arguments to Dart arguments
            final dartArgs = args.map((jsArg) => jsArg.primitiveValue).toList();

            // Call the Dart function with basic reflection
            dynamic result;

            // Try calling with different numbers of arguments
            if (dartArgs.isEmpty) {
              result = Function.apply(value, []);
            } else if (dartArgs.length == 1) {
              result = Function.apply(value, [dartArgs[0]]);
            } else if (dartArgs.length == 2) {
              result = Function.apply(value, [dartArgs[0], dartArgs[1]]);
            } else if (dartArgs.length == 3) {
              result = Function.apply(value, [
                dartArgs[0],
                dartArgs[1],
                dartArgs[2],
              ]);
            } else {
              result = Function.apply(value, dartArgs);
            }

            // Convert the result to JSValue
            return fromDart(result);
          } catch (e) {
            throw JSError('Dart function call error: $e');
          }
        },
      );
    }

    // Fallback: convert to string for other types
    return string(value.toString());
  }

  /// Create a new empty JavaScript object
  static JSObject createObject() => JSObject();

  /// Create a new JavaScript Promise
  static JSPromise createPromise() {
    // Create a promise without executor - it will be resolved manually
    final promise = JSPromise._internal();
    return promise;
  }
}

/// Promise states
enum PromiseState { pending, fulfilled, rejected }

/// JavaScript Promise object
class JSPromise extends JSObject {
  PromiseState _state = PromiseState.pending;
  JSValue? _value;
  JSValue? _reason;

  // Callbacks for then/catch
  final List<JSValue> _onFulfilledCallbacks = [];
  final List<JSValue> _onRejectedCallbacks = [];

  // Shared prototype for all Promise instances
  static JSObject? _promisePrototype;

  static JSObject? get promisePrototype {
    final manager = PrototypeManager.current;
    if (manager != null && manager.promisePrototype != null) {
      return manager.promisePrototype;
    }
    return _promisePrototype;
  }

  JSPromise(JSValue executor) : super(prototype: promisePrototype) {
    // The constructor takes an executor that will be called immediately
    if (executor is JSFunction) {
      _executeExecutor(executor);
    } else {
      throw JSTypeError('Promise executor must be a function');
    }
  }

  /// Private constructor to create a promise without executor
  JSPromise._internal() : super(prototype: promisePrototype);

  /// Creates a new promise without executor (for subclasses)
  factory JSPromise.createInternal() => JSPromise._internal();

  /// Define the Promise prototype (called from evaluator)
  static void setPromisePrototype(JSObject prototype) {
    final manager = PrototypeManager.current;
    if (manager != null) {
      manager.setPromisePrototype(prototype);
    } else {
      _promisePrototype = prototype;
    }
  }

  void _executeExecutor(JSFunction executor) {
    // Create resolve and reject functions
    // Per ES6 spec, both have length = 1
    // Note: Resolve and reject are NOT constructors
    final resolveFunction = JSNativeFunction(
      functionName: '', // Anonymous function per spec
      expectedArgs: 1, // Length property = 1
      nativeImpl: (args) {
        if (_state == PromiseState.pending) {
          _state = PromiseState.fulfilled;
          _value = args.isNotEmpty ? args[0] : JSValueFactory.undefined();
          _settle();
        }
        return JSValueFactory.undefined();
      },
      isConstructor: false, // Resolve is not a constructor
    );

    final rejectFunction = JSNativeFunction(
      functionName: '', // Anonymous function per spec
      expectedArgs: 1, // Length property = 1
      nativeImpl: (args) {
        if (_state == PromiseState.pending) {
          _state = PromiseState.rejected;
          _reason = args.isNotEmpty ? args[0] : JSValueFactory.undefined();
          _settle();
        }
        return JSValueFactory.undefined();
      },
      isConstructor: false, // Reject is not a constructor
    );

    // Call the executor with resolve and reject
    try {
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        evaluator.callFunction(executor, [
          resolveFunction,
          rejectFunction,
        ], JSValueFactory.undefined());
      } else {
        throw JSError('No evaluator available for Promise executor');
      }
    } catch (e) {
      // If the executor throws an exception, reject the promise
      if (_state == PromiseState.pending) {
        _state = PromiseState.rejected;
        _reason = e is JSValue ? e : JSValueFactory.string(e.toString());
        _settle();
      }
    }
  }

  void _settle() {
    // Schedule callback execution as microtasks
    // Per ES6 spec, Promise callbacks must execute asynchronously
    final evaluator = JSEvaluator.currentInstance;
    if (evaluator == null) return;

    // Enqueue microtasks for all callbacks
    if (_state == PromiseState.fulfilled) {
      for (final callback in _onFulfilledCallbacks) {
        if (callback is JSFunction) {
          evaluator.asyncScheduler.enqueueMicrotask(() {
            try {
              evaluator.callFunction(callback, [
                _value ?? JSValueFactory.undefined(),
              ], JSValueFactory.undefined());
            } catch (e) {
              // Ignore errors in callbacks
            }
          });
        }
      }
    } else if (_state == PromiseState.rejected) {
      for (final callback in _onRejectedCallbacks) {
        if (callback is JSFunction) {
          evaluator.asyncScheduler.enqueueMicrotask(() {
            try {
              evaluator.callFunction(callback, [
                _reason ?? JSValueFactory.undefined(),
              ], JSValueFactory.undefined());
            } catch (e) {
              // Ignore errors in callbacks
            }
          });
        }
      }
    }

    // Notify the scheduler that this Promise has been resolved
    evaluator.asyncScheduler.enqueueMicrotask(() {
      evaluator.notifyPromiseResolved(this);
    });

    // Clear callback lists
    _onFulfilledCallbacks.clear();
    _onRejectedCallbacks.clear();
  }

  /// Resolve the promise with a value
  void resolve(JSValue value) {
    if (_state == PromiseState.pending) {
      _state = PromiseState.fulfilled;
      _value = value;
      _settle();
    }
  }

  /// Reject the promise with a reason
  void reject(JSValue reason) {
    if (_state == PromiseState.pending) {
      _state = PromiseState.rejected;
      _reason = reason;
      _settle();
    }
  }

  /// Getters for state and values (used by await)
  PromiseState get state => _state;
  JSValue? get value => _value;
  JSValue? get reason => _reason;

  @override
  String toString() => '[object Promise]';

  /// Conversion to primitive (for type coercion)
  String toPrimitive() => '[object Promise]';

  @override
  bool equals(JSValue other) {
    // Strict equality - same reference
    return identical(this, other);
  }
}

/// Prototype for Promise objects
class PromisePrototype {
  /// SameValue comparison per ES6 7.2.10
  /// SameValue(x, y) returns true if x and y are the same value
  static bool _sameValue(JSValue x, JSValue y) {
    // Same reference
    if (identical(x, y)) return true;

    // Different types - not same
    if (x.runtimeType != y.runtimeType) return false;

    // For primitives, compare by type and value
    if (x is JSNumber && y is JSNumber) {
      // Special case: both NaN are considered same in SameValue
      if (x.value.isNaN && y.value.isNaN) return true;
      return x.value == y.value;
    }

    if (x is JSString && y is JSString) {
      return x.value == y.value;
    }

    if (x is JSBoolean && y is JSBoolean) {
      return x.value == y.value;
    }

    if (x is JSNull || x is JSUndefined || x is JSNull || y is JSUndefined) {
      return identical(x.runtimeType, y.runtimeType);
    }

    // For objects, symbols, functions: reference equality
    return identical(x, y);
  }

  /// Promise.prototype.then(onFulfilled, onRejected)
  static JSValue then(List<JSValue> args, JSPromise promise) {
    final onFulfilled = args.isNotEmpty && args[0] is JSFunction
        ? args[0]
        : null;
    final onRejected = args.length > 1 && args[1] is JSFunction
        ? args[1]
        : null;

    // Create a new promise for chaining
    final newPromise = JSPromise(
      JSNativeFunction(
        functionName: 'executor',
        nativeImpl: (executorArgs) {
          final resolve = executorArgs[0];
          final reject = executorArgs[1];
          final evaluator = JSEvaluator.currentInstance;
          if (evaluator == null) return JSValueFactory.undefined();

          if (promise._state == PromiseState.fulfilled) {
            // Schedule callback execution as microtask
            evaluator.asyncScheduler.enqueueMicrotask(() {
              if (onFulfilled != null) {
                try {
                  final result = evaluator.callFunction(
                    onFulfilled as JSFunction,
                    [promise._value ?? JSValueFactory.undefined()],
                    JSValueFactory.undefined(),
                  );

                  // If the result is a Promise, wait for its resolution
                  if (result is JSPromise) {
                    then([
                      JSNativeFunction(
                        functionName: 'chainResolve',
                        nativeImpl: (args) {
                          (resolve as JSNativeFunction).call(args);
                          return JSValueFactory.undefined();
                        },
                      ),
                      JSNativeFunction(
                        functionName: 'chainReject',
                        nativeImpl: (args) {
                          (reject as JSNativeFunction).call(args);
                          return JSValueFactory.undefined();
                        },
                      ),
                    ], result);
                  } else {
                    (resolve as JSNativeFunction).call([result]);
                  }
                } catch (e) {
                  (reject as JSNativeFunction).call([
                    JSValueFactory.string(e.toString()),
                  ]);
                }
              } else {
                (resolve as JSNativeFunction).call([
                  promise._value ?? JSValueFactory.undefined(),
                ]);
              }
            });
          } else if (promise._state == PromiseState.rejected) {
            // Schedule callback execution as microtask
            evaluator.asyncScheduler.enqueueMicrotask(() {
              if (onRejected != null) {
                try {
                  final result = evaluator.callFunction(
                    onRejected as JSFunction,
                    [promise._reason ?? JSValueFactory.undefined()],
                    JSValueFactory.undefined(),
                  );

                  // If the result is a Promise, wait for its resolution
                  if (result is JSPromise) {
                    then([
                      JSNativeFunction(
                        functionName: 'chainResolve',
                        nativeImpl: (args) {
                          (resolve as JSNativeFunction).call(args);
                          return JSValueFactory.undefined();
                        },
                      ),
                      JSNativeFunction(
                        functionName: 'chainReject',
                        nativeImpl: (args) {
                          (reject as JSNativeFunction).call(args);
                          return JSValueFactory.undefined();
                        },
                      ),
                    ], result);
                  } else {
                    (resolve as JSNativeFunction).call([result]);
                  }
                } catch (e) {
                  (reject as JSNativeFunction).call([
                    JSValueFactory.string(e.toString()),
                  ]);
                }
              } else {
                (reject as JSNativeFunction).call([
                  promise._reason ?? JSValueFactory.undefined(),
                ]);
              }
            });
          } else {
            // Promise encore en attente
            if (onFulfilled != null) {
              promise._onFulfilledCallbacks.add(
                JSNativeFunction(
                  functionName: 'thenCallback',
                  nativeImpl: (callbackArgs) {
                    final evaluator = JSEvaluator.currentInstance;
                    if (evaluator == null) return JSValueFactory.undefined();

                    // Enqueue the callback as a microtask
                    evaluator.asyncScheduler.enqueueMicrotask(() {
                      try {
                        final result = evaluator.callFunction(
                          onFulfilled as JSFunction,
                          callbackArgs,
                          JSValueFactory.undefined(),
                        );

                        // If the result is a Promise, wait for its resolution
                        if (result is JSPromise) {
                          then([
                            JSNativeFunction(
                              functionName: 'chainResolve',
                              nativeImpl: (args) {
                                (resolve as JSNativeFunction).call(args);
                                return JSValueFactory.undefined();
                              },
                            ),
                            JSNativeFunction(
                              functionName: 'chainReject',
                              nativeImpl: (args) {
                                (reject as JSNativeFunction).call(args);
                                return JSValueFactory.undefined();
                              },
                            ),
                          ], result);
                        } else {
                          (resolve as JSNativeFunction).call([result]);
                        }
                      } catch (e) {
                        (reject as JSNativeFunction).call([
                          JSValueFactory.string(e.toString()),
                        ]);
                      }
                    });
                    return JSValueFactory.undefined();
                  },
                ),
              );
            }

            if (onRejected != null) {
              promise._onRejectedCallbacks.add(
                JSNativeFunction(
                  functionName: 'catchCallback',
                  nativeImpl: (callbackArgs) {
                    final evaluator = JSEvaluator.currentInstance;
                    if (evaluator == null) return JSValueFactory.undefined();

                    // Enqueue the callback as a microtask
                    evaluator.asyncScheduler.enqueueMicrotask(() {
                      try {
                        final result = evaluator.callFunction(
                          onRejected as JSFunction,
                          callbackArgs,
                          JSValueFactory.undefined(),
                        );

                        // If the result is a Promise, wait for its resolution
                        if (result is JSPromise) {
                          then([
                            JSNativeFunction(
                              functionName: 'chainResolve',
                              nativeImpl: (args) {
                                (resolve as JSNativeFunction).call(args);
                                return JSValueFactory.undefined();
                              },
                            ),
                            JSNativeFunction(
                              functionName: 'chainReject',
                              nativeImpl: (args) {
                                (reject as JSNativeFunction).call(args);
                                return JSValueFactory.undefined();
                              },
                            ),
                          ], result);
                        } else {
                          (resolve as JSNativeFunction).call([result]);
                        }
                      } catch (e) {
                        (reject as JSNativeFunction).call([
                          JSValueFactory.string(e.toString()),
                        ]);
                      }
                    });
                    return JSValueFactory.undefined();
                  },
                ),
              );
            }
          }
          return JSValueFactory.undefined();
        },
      ),
    );

    return newPromise;
  }

  /// Promise.prototype.catch(onRejected)
  static JSValue catch_(List<JSValue> args, JSPromise promise) {
    if (args.isEmpty) {
      throw JSTypeError('Promise.prototype.catch requires 1 argument');
    }
    return then([JSValueFactory.undefined(), args[0]], promise);
  }

  /// Promise.prototype.finally(onFinally)
  static JSValue finally_(List<JSValue> args, JSPromise promise) {
    if (args.isEmpty) {
      throw JSTypeError('Promise.prototype.finally requires 1 argument');
    }

    final onFinally = args[0];
    if (onFinally is! JSFunction) {
      throw JSTypeError(
        'Promise.prototype.finally callback must be a function',
      );
    }

    return then([
      JSNativeFunction(
        functionName: 'finallyFulfilled',
        nativeImpl: (callbackArgs) {
          final evaluator = JSEvaluator.currentInstance;
          if (evaluator != null) {
            evaluator.callFunction(onFinally, [], JSValueFactory.undefined());
          }
          return callbackArgs.isNotEmpty
              ? callbackArgs[0]
              : JSValueFactory.undefined();
        },
      ),
      JSNativeFunction(
        functionName: 'finallyRejected',
        nativeImpl: (callbackArgs) {
          final evaluator = JSEvaluator.currentInstance;
          if (evaluator != null) {
            evaluator.callFunction(onFinally, [], JSValueFactory.undefined());
          }
          throw callbackArgs.isNotEmpty
              ? callbackArgs[0]
              : JSValueFactory.undefined();
        },
      ),
    ], promise);
  }

  /// Get a property of the object Promise
  static JSValue getPromiseProperty(JSPromise promise, String name) {
    switch (name) {
      case 'then':
        return JSNativeFunction(
          functionName: 'then',
          nativeImpl: (args) => then(args, promise),
        );
      case 'catch':
        return JSNativeFunction(
          functionName: 'catch',
          nativeImpl: (args) => catch_(args, promise),
        );
      case 'finally':
        return JSNativeFunction(
          functionName: 'finally',
          nativeImpl: (args) => finally_(args, promise),
        );
      default:
        // Search dans Object.prototype
        return JSObject.objectPrototype.getProperty(name);
    }
  }

  /// Promise.resolve(value) - with this binding support
  static JSValue resolveWithThis(List<JSValue> args, JSValue thisBinding) {
    final value = args.isNotEmpty ? args[0] : JSValueFactory.undefined();

    // ES6 25.4.4.5 step 3: If IsPromise(x) is true,
    // Check if value is a Promise and if its constructor matches thisBinding
    if (value is JSPromise) {
      // Get the constructor property of the promise
      JSValue xConstructor = JSValueFactory.undefined();
      try {
        xConstructor = value.getProperty('constructor');
      } catch (e) {
        // If getting constructor throws, propagate
        rethrow;
      }

      // Use SameValue comparison: check if xConstructor === thisBinding
      // SameValue: same type, same value
      final sameValue = _sameValue(xConstructor, thisBinding);
      if (sameValue) {
        // Return the original promise
        return value;
      }
    }

    // If thisBinding is Promise itself (not a subclass), use the fast path
    if (thisBinding is JSNativeFunction &&
        thisBinding.functionName == 'Promise') {
      // Fast path for Promise.resolve
      return JSPromise(
        JSNativeFunction(
          functionName: 'resolveExecutor',
          nativeImpl: (executorArgs) {
            final resolve = executorArgs[0] as JSNativeFunction;
            final evaluator = JSEvaluator.currentInstance;
            if (evaluator != null) {
              evaluator.callFunction(resolve, [
                value,
              ], JSValueFactory.undefined());
            }
            return JSValueFactory.undefined();
          },
        ),
      );
    }

    // For subclasses or custom constructors, create via new this(executor)
    // Create executor function with length = 2
    // Per ES6 spec, implement capability executor semantics:
    // - Track if resolve/reject have been SET to non-undefined values
    // - Throw TypeError if already SET
    final resolveSetter = <JSValue?>[null]; // Track if resolve is SET
    final rejectSetter = <JSValue?>[null]; // Track if reject is SET
    final capturedResolve = <JSValue?>[
      null,
    ]; // Capture resolve for later validation
    final capturedReject = <JSValue?>[
      null,
    ]; // Capture reject for later validation

    final executor = JSNativeFunction(
      functionName: '',
      expectedArgs: 2,
      nativeImpl: (executorArgs) {
        final resolve = executorArgs.isNotEmpty
            ? executorArgs[0]
            : JSValueFactory.undefined();
        final reject = executorArgs.length > 1
            ? executorArgs[1]
            : JSValueFactory.undefined();

        // Capture the capabilities for later validation
        capturedResolve[0] = resolve;
        capturedReject[0] = reject;

        // Check if resolve is not undefined and already SET
        if (!resolve.isUndefined && resolveSetter[0] != null) {
          throw JSTypeError(
            'Promise capability executor resolve already called',
          );
        }

        // Check if reject is not undefined and already SET
        if (!reject.isUndefined && rejectSetter[0] != null) {
          throw JSTypeError(
            'Promise capability executor reject already called',
          );
        }

        // Mark resolve as SET if non-undefined
        if (!resolve.isUndefined) {
          resolveSetter[0] = resolve;
        }

        // Mark reject as SET if non-undefined
        if (!reject.isUndefined) {
          rejectSetter[0] = reject;
        }

        // DO NOT call resolve here - just capture it for later
        // The resolution will happen after the constructor returns
        return JSValueFactory.undefined();
      },
    );

    // Call this(executor) - whether it's a constructor or regular function
    JSValue result;
    try {
      if (thisBinding is JSNativeFunction) {
        // Call as regular function (may not be a constructor)
        result = thisBinding.call([executor]);
        // If result is an object, set up the prototype
        if (result is JSObject) {
          final prototypeValue = thisBinding.getProperty('prototype');
          if (prototypeValue is JSObject) {
            result.setPrototype(prototypeValue);
          }
          if (!result.hasOwnProperty('constructor')) {
            result.setProperty('constructor', thisBinding);
          }
        }
      } else if (thisBinding is JSClass) {
        result = thisBinding.construct([executor]);
      } else if (thisBinding is JSFunction) {
        // Can call any JSFunction
        final evaluator = JSEvaluator.currentInstance;
        if (evaluator != null) {
          result = evaluator.callFunction(thisBinding, [
            executor,
          ], JSValueFactory.undefined());
        } else {
          throw JSError('No evaluator for Promise constructor');
        }
      } else {
        throw JSTypeError('Promise.resolve called on non-callable');
      }
    } catch (e) {
      rethrow;
    }

    // After constructor execution, validate capabilities per ES6 25.4.1.5
    // 8. If IsCallable(promiseCapability.[[Resolve]]) is false, throw a TypeError exception.
    // 9. If IsCallable(promiseCapability.[[Reject]]) is false, throw a TypeError exception.
    final resolveCapability = capturedResolve[0];
    final rejectCapability = capturedReject[0];

    // Validate both resolve and reject are callable
    if (resolveCapability == null || !resolveCapability.isFunction) {
      throw JSTypeError('Promise capability resolve is not callable');
    }
    if (rejectCapability == null || !rejectCapability.isFunction) {
      throw JSTypeError('Promise capability reject is not callable');
    }

    // Step 5: Call promiseCapability.[[Resolve]] with x
    // Per ES6: Perform ? Call(promiseCapability.[[Resolve]], undefined, « x »).
    final evaluator = JSEvaluator.currentInstance;
    if (evaluator != null) {
      evaluator.callFunction(resolveCapability, [
        value,
      ], JSValueFactory.undefined());
    }

    return result;
  }

  /// Promise.reject(reason) - with this binding support
  static JSValue rejectWithThis(List<JSValue> args, JSValue thisBinding) {
    final reason = args.isNotEmpty ? args[0] : JSValueFactory.undefined();

    // If thisBinding is Promise itself (not a subclass), use the fast path
    if (thisBinding is JSNativeFunction &&
        thisBinding.functionName == 'Promise') {
      // Fast path for Promise.reject
      return JSPromise(
        JSNativeFunction(
          functionName: 'rejectExecutor',
          nativeImpl: (executorArgs) {
            if (executorArgs.length > 1) {
              final reject = executorArgs[1] as JSNativeFunction;
              final evaluator = JSEvaluator.currentInstance;
              if (evaluator != null) {
                evaluator.callFunction(reject, [
                  reason,
                ], JSValueFactory.undefined());
              }
            }
            return JSValueFactory.undefined();
          },
        ),
      );
    }

    // For subclasses or custom constructors, create via new this(executor)
    // Create executor function that follows Promise capability semantics:
    // - Track if resolve/reject have been SET to non-undefined values
    // - Throw TypeError if already SET
    final resolveSetter = <JSValue?>[null]; // Track if resolve is SET
    final rejectSetter = <JSValue?>[null]; // Track if reject is SET
    final capturedResolve = <JSValue?>[
      null,
    ]; // Capture resolve for later validation
    final capturedReject = <JSValue?>[
      null,
    ]; // Capture reject for later validation

    final executor = JSNativeFunction(
      functionName: '',
      expectedArgs: 2,
      nativeImpl: (executorArgs) {
        final resolve = executorArgs.isNotEmpty
            ? executorArgs[0]
            : JSValueFactory.undefined();
        final reject = executorArgs.length > 1
            ? executorArgs[1]
            : JSValueFactory.undefined();

        // Capture the capabilities for later validation
        capturedResolve[0] = resolve;
        capturedReject[0] = reject;

        // Check if resolve is not undefined and already SET
        if (!resolve.isUndefined && resolveSetter[0] != null) {
          throw JSTypeError(
            'Promise capability executor resolve already called',
          );
        }

        // Mark resolve as SET if non-undefined
        if (!resolve.isUndefined) {
          resolveSetter[0] = resolve;
        }

        // Check if reject is not undefined and already SET
        if (!reject.isUndefined && rejectSetter[0] != null) {
          throw JSTypeError(
            'Promise capability executor reject already called',
          );
        }

        // Mark reject as SET if non-undefined
        if (!reject.isUndefined) {
          rejectSetter[0] = reject;
        }

        // DO NOT call reject here - just capture it for later
        // The rejection will happen after the constructor returns
        return JSValueFactory.undefined();
      },
    );

    // Call this(executor) - whether it's a constructor or regular function
    JSValue result;
    try {
      if (thisBinding is JSNativeFunction) {
        // Call as regular function (may not be a constructor)
        result = thisBinding.call([executor]);
        // If result is an object, set up the prototype
        if (result is JSObject) {
          final prototypeValue = thisBinding.getProperty('prototype');
          if (prototypeValue is JSObject) {
            result.setPrototype(prototypeValue);
          }
          if (!result.hasOwnProperty('constructor')) {
            result.setProperty('constructor', thisBinding);
          }
        }
      } else if (thisBinding is JSClass) {
        result = thisBinding.construct([executor]);
      } else if (thisBinding is JSFunction) {
        // Can call any JSFunction
        final evaluator = JSEvaluator.currentInstance;
        if (evaluator != null) {
          result = evaluator.callFunction(thisBinding, [
            executor,
          ], JSValueFactory.undefined());
        } else {
          throw JSError('No evaluator for Promise constructor');
        }
      } else {
        throw JSTypeError('Promise.reject called on non-callable');
      }
    } catch (e) {
      rethrow;
    }

    // After constructor execution, validate capabilities per ES6 25.4.1.5
    // 8. If IsCallable(promiseCapability.[[Resolve]]) is false, throw a TypeError exception.
    // 9. If IsCallable(promiseCapability.[[Reject]]) is false, throw a TypeError exception.
    final resolveCapability = capturedResolve[0];
    final rejectCapability = capturedReject[0];

    // Validate reject is callable
    if (rejectCapability == null || !rejectCapability.isFunction) {
      throw JSTypeError('Promise capability reject is not callable');
    }

    // Validate resolve is callable
    if (resolveCapability == null || !resolveCapability.isFunction) {
      throw JSTypeError('Promise capability resolve is not callable');
    }

    // Step 5: Call promiseCapability.[[Reject]] with reason
    // Per ES6: Perform ? Call(promiseCapability.[[Reject]], undefined, « reason »).
    final evaluator = JSEvaluator.currentInstance;
    if (evaluator != null) {
      evaluator.callFunction(rejectCapability, [
        reason,
      ], JSValueFactory.undefined());
    }

    return result;
  }

  /// Promise.resolve(value)
  static JSValue resolve(List<JSValue> args) {
    final value = args.isNotEmpty ? args[0] : JSValueFactory.undefined();

    return JSPromise(
      JSNativeFunction(
        functionName: 'resolveExecutor',
        nativeImpl: (executorArgs) {
          final resolve = executorArgs[0] as JSNativeFunction;
          final evaluator = JSEvaluator.currentInstance;
          if (evaluator != null) {
            evaluator.callFunction(resolve, [
              value,
            ], JSValueFactory.undefined());
          }
          return JSValueFactory.undefined();
        },
      ),
    );
  }

  /// Promise.reject(reason)
  static JSValue reject(List<JSValue> args) {
    final reason = args.isNotEmpty ? args[0] : JSValueFactory.undefined();

    return JSPromise(
      JSNativeFunction(
        functionName: 'rejectExecutor',
        nativeImpl: (executorArgs) {
          final reject = executorArgs[1] as JSNativeFunction;
          final evaluator = JSEvaluator.currentInstance;
          if (evaluator != null) {
            evaluator.callFunction(reject, [
              reason,
            ], JSValueFactory.undefined());
          }
          return JSValueFactory.undefined();
        },
      ),
    );
  }

  /// Promise.all(iterable)
  static JSValue all(List<JSValue> args) {
    if (args.isEmpty) {
      throw JSTypeError('Promise.all requires 1 argument');
    }

    final iterable = args[0];

    // Return a rejected promise if the argument is not iterable
    if (iterable is! JSArray) {
      return JSPromise(
        JSNativeFunction(
          functionName: 'allRejectExecutor',
          nativeImpl: (executorArgs) {
            final reject = executorArgs[1] as JSNativeFunction;
            final evaluator = JSEvaluator.currentInstance;
            if (evaluator != null) {
              // Create a TypeError object
              final typeErrorCtor = evaluator.globalEnvironment.get(
                'TypeError',
              );
              JSValue errorValue;
              if (typeErrorCtor is JSNativeFunction) {
                errorValue = typeErrorCtor.call([
                  JSValueFactory.string('${iterable.type} is not iterable'),
                ]);
              } else {
                // Fallback: create error manually
                errorValue = JSValueFactory.object({});
                if (errorValue is JSObject) {
                  errorValue.setProperty(
                    'name',
                    JSValueFactory.string('TypeError'),
                  );
                  errorValue.setProperty(
                    'message',
                    JSValueFactory.string('${iterable.type} is not iterable'),
                  );
                }
              }

              evaluator.callFunction(reject, [
                errorValue,
              ], JSValueFactory.undefined());
            }
            return JSValueFactory.undefined();
          },
        ),
      );
    }

    return JSPromise(
      JSNativeFunction(
        functionName: 'allExecutor',
        nativeImpl: (executorArgs) {
          final resolve = executorArgs[0] as JSNativeFunction;
          final reject = executorArgs[1] as JSNativeFunction;

          final promises = iterable.elements;
          if (promises.isEmpty) {
            final evaluator = JSEvaluator.currentInstance;
            if (evaluator != null) {
              evaluator.callFunction(resolve, [
                JSValueFactory.array(),
              ], JSValueFactory.undefined());
            }
            return JSValueFactory.undefined();
          }

          final results = List<JSValue>.filled(
            promises.length,
            JSValueFactory.undefined(),
          );
          var completed = 0;

          for (var i = 0; i < promises.length; i++) {
            final promise = promises[i];
            if (promise is JSPromise) {
              PromisePrototype.then([
                JSNativeFunction(
                  functionName: 'allResolve',
                  nativeImpl: (callbackArgs) {
                    results[i] = callbackArgs.isNotEmpty
                        ? callbackArgs[0]
                        : JSValueFactory.undefined();
                    completed++;
                    if (completed == promises.length) {
                      final evaluator = JSEvaluator.currentInstance;
                      if (evaluator != null) {
                        evaluator.callFunction(resolve, [
                          JSValueFactory.array(results),
                        ], JSValueFactory.undefined());
                      }
                    }
                    return JSValueFactory.undefined();
                  },
                ),
                JSNativeFunction(
                  functionName: 'allReject',
                  nativeImpl: (callbackArgs) {
                    final evaluator = JSEvaluator.currentInstance;
                    if (evaluator != null) {
                      evaluator.callFunction(
                        reject,
                        callbackArgs,
                        JSValueFactory.undefined(),
                      );
                    }
                    return JSValueFactory.undefined();
                  },
                ),
              ], promise);
            } else {
              // If ce n'est pas une promise, traiter comme a value resolue
              results[i] = promise;
              completed++;
              if (completed == promises.length) {
                final evaluator = JSEvaluator.currentInstance;
                if (evaluator != null) {
                  evaluator.callFunction(resolve, [
                    JSValueFactory.array(results),
                  ], JSValueFactory.undefined());
                }
              }
            }
          }
          return JSValueFactory.undefined();
        },
      ),
    );
  }

  /// Promise.race(iterable)
  static JSValue race(List<JSValue> args) {
    if (args.isEmpty) {
      throw JSTypeError('Promise.race requires 1 argument');
    }

    final iterable = args[0];
    if (iterable is! JSArray) {
      throw JSTypeError('Promise.race argument must be iterable');
    }

    return JSPromise(
      JSNativeFunction(
        functionName: 'raceExecutor',
        nativeImpl: (executorArgs) {
          final resolve = executorArgs[0] as JSNativeFunction;
          final reject = executorArgs[1] as JSNativeFunction;

          final promises = iterable.elements;
          if (promises.isEmpty) {
            // Rester en attente indefiniment
            return JSValueFactory.undefined();
          }

          for (final promise in promises) {
            if (promise is JSPromise) {
              PromisePrototype.then([
                JSNativeFunction(
                  functionName: 'raceResolve',
                  nativeImpl: (callbackArgs) {
                    final evaluator = JSEvaluator.currentInstance;
                    if (evaluator != null) {
                      evaluator.callFunction(
                        resolve,
                        callbackArgs,
                        JSValueFactory.undefined(),
                      );
                    }
                    return JSValueFactory.undefined();
                  },
                ),
                JSNativeFunction(
                  functionName: 'raceReject',
                  nativeImpl: (callbackArgs) {
                    final evaluator = JSEvaluator.currentInstance;
                    if (evaluator != null) {
                      evaluator.callFunction(
                        reject,
                        callbackArgs,
                        JSValueFactory.undefined(),
                      );
                    }
                    return JSValueFactory.undefined();
                  },
                ),
              ], promise);
            } else {
              // If ce n'est pas une promise, resoudre immediatement
              final evaluator = JSEvaluator.currentInstance;
              if (evaluator != null) {
                evaluator.callFunction(resolve, [
                  promise,
                ], JSValueFactory.undefined());
              }
              return JSValueFactory.undefined();
            }
          }
          return JSValueFactory.undefined();
        },
      ),
    );
  }

  /// ES2020: Promise.allSettled(iterable)
  /// Attend que all promesses soient resolues (fulfilled OU rejected)
  /// Returns an array d'objets {status, value/reason}
  static JSValue allSettled(List<JSValue> args) {
    if (args.isEmpty) {
      throw JSTypeError('Promise.allSettled requires 1 argument');
    }

    final iterable = args[0];
    if (iterable is! JSArray) {
      throw JSTypeError('Promise.allSettled argument must be iterable');
    }

    return JSPromise(
      JSNativeFunction(
        functionName: 'allSettledExecutor',
        nativeImpl: (executorArgs) {
          final resolve = executorArgs[0] as JSNativeFunction;

          final promises = iterable.elements;
          if (promises.isEmpty) {
            final evaluator = JSEvaluator.currentInstance;
            if (evaluator != null) {
              evaluator.callFunction(resolve, [
                JSValueFactory.array(),
              ], JSValueFactory.undefined());
            }
            return JSValueFactory.undefined();
          }

          final results = List<JSValue?>.filled(promises.length, null);
          var completed = 0;

          void checkCompletion() {
            if (completed == promises.length) {
              final evaluator = JSEvaluator.currentInstance;
              if (evaluator != null) {
                evaluator.callFunction(resolve, [
                  JSValueFactory.array(results.cast<JSValue>()),
                ], JSValueFactory.undefined());
              }
            }
          }

          for (var i = 0; i < promises.length; i++) {
            final index = i; // Capturer l'index pour la closure
            final promise = promises[i];

            if (promise is JSPromise) {
              PromisePrototype.then([
                JSNativeFunction(
                  functionName: 'allSettledFulfilled',
                  nativeImpl: (callbackArgs) {
                    // Create l'objet de resultat {status: 'fulfilled', value: ...}
                    final resultObj = JSValueFactory.object({});
                    resultObj.setProperty(
                      'status',
                      JSValueFactory.string('fulfilled'),
                    );
                    resultObj.setProperty(
                      'value',
                      callbackArgs.isNotEmpty
                          ? callbackArgs[0]
                          : JSValueFactory.undefined(),
                    );
                    results[index] = resultObj;
                    completed++;
                    checkCompletion();
                    return JSValueFactory.undefined();
                  },
                ),
                JSNativeFunction(
                  functionName: 'allSettledRejected',
                  nativeImpl: (callbackArgs) {
                    // Create l'objet de resultat {status: 'rejected', reason: ...}
                    final resultObj = JSValueFactory.object({});
                    resultObj.setProperty(
                      'status',
                      JSValueFactory.string('rejected'),
                    );
                    resultObj.setProperty(
                      'reason',
                      callbackArgs.isNotEmpty
                          ? callbackArgs[0]
                          : JSValueFactory.undefined(),
                    );
                    results[index] = resultObj;
                    completed++;
                    checkCompletion();
                    return JSValueFactory.undefined();
                  },
                ),
              ], promise);
            } else {
              // If ce n'est pas une promise, traiter comme a value fulfilled
              final resultObj = JSValueFactory.object({});
              resultObj.setProperty(
                'status',
                JSValueFactory.string('fulfilled'),
              );
              resultObj.setProperty('value', promise);
              results[i] = resultObj;
              completed++;
              checkCompletion();
            }
          }
          return JSValueFactory.undefined();
        },
      ),
    );
  }

  /// ES2021: Promise.any(iterable)
  /// Resout avec la premiere promise qui se resout (fulfilled)
  /// Rejette avec AggregateError si all promises rejettent
  static JSValue any(List<JSValue> args) {
    if (args.isEmpty) {
      throw JSTypeError('Promise.any requires 1 argument');
    }

    final iterable = args[0];
    if (iterable is! JSArray) {
      throw JSTypeError('Promise.any argument must be iterable');
    }

    return JSPromise(
      JSNativeFunction(
        functionName: 'anyExecutor',
        nativeImpl: (executorArgs) {
          final resolve = executorArgs[0] as JSNativeFunction;
          final reject = executorArgs[1] as JSNativeFunction;

          final promises = iterable.elements;

          // Cas special: tableau vide rejette avec AggregateError
          if (promises.isEmpty) {
            final evaluator = JSEvaluator.currentInstance;
            if (evaluator != null) {
              final aggregateError = JSValueFactory.object({});
              aggregateError.setProperty(
                'name',
                JSValueFactory.string('AggregateError'),
              );
              aggregateError.setProperty(
                'message',
                JSValueFactory.string('All promises were rejected'),
              );
              aggregateError.setProperty('errors', JSValueFactory.array([]));
              evaluator.callFunction(reject, [
                aggregateError,
              ], JSValueFactory.undefined());
            }
            return JSValueFactory.undefined();
          }

          final errors = List<JSValue?>.filled(promises.length, null);
          var rejectedCount = 0;
          var resolved = false;

          void checkAllRejected() {
            if (rejectedCount == promises.length && !resolved) {
              // Toutes les promises ont rejete - creer AggregateError
              final evaluator = JSEvaluator.currentInstance;
              if (evaluator != null) {
                final aggregateError = JSValueFactory.object({});
                aggregateError.setProperty(
                  'name',
                  JSValueFactory.string('AggregateError'),
                );
                aggregateError.setProperty(
                  'message',
                  JSValueFactory.string('All promises were rejected'),
                );
                aggregateError.setProperty(
                  'errors',
                  JSValueFactory.array(errors.cast<JSValue>()),
                );
                evaluator.callFunction(reject, [
                  aggregateError,
                ], JSValueFactory.undefined());
              }
            }
          }

          for (var i = 0; i < promises.length; i++) {
            final index = i; // Capturer l'index pour la closure
            final promise = promises[i];

            if (promise is JSPromise) {
              PromisePrototype.then([
                JSNativeFunction(
                  functionName: 'anyFulfilled',
                  nativeImpl: (callbackArgs) {
                    if (!resolved) {
                      resolved = true;
                      final evaluator = JSEvaluator.currentInstance;
                      if (evaluator != null) {
                        evaluator.callFunction(resolve, [
                          callbackArgs.isNotEmpty
                              ? callbackArgs[0]
                              : JSValueFactory.undefined(),
                        ], JSValueFactory.undefined());
                      }
                    }
                    return JSValueFactory.undefined();
                  },
                ),
                JSNativeFunction(
                  functionName: 'anyRejected',
                  nativeImpl: (callbackArgs) {
                    errors[index] = callbackArgs.isNotEmpty
                        ? callbackArgs[0]
                        : JSValueFactory.undefined();
                    rejectedCount++;
                    checkAllRejected();
                    return JSValueFactory.undefined();
                  },
                ),
              ], promise);
            } else {
              // If ce n'est pas une promise, traiter comme a value fulfilled
              if (!resolved) {
                resolved = true;
                final evaluator = JSEvaluator.currentInstance;
                if (evaluator != null) {
                  evaluator.callFunction(resolve, [
                    promise,
                  ], JSValueFactory.undefined());
                }
              }
            }
          }
          return JSValueFactory.undefined();
        },
      ),
    );
  }
}

/// Implementation de globalThis JavaScript
/// Fournit l'acces a l'environnement global
class JSGlobalThis extends JSObject {
  final Environment _environment;
  // Store property descriptors for global properties
  final Map<String, PropertyDescriptor> _globalDescriptors = {};
  // Track deleted global properties so they don't get accessed again
  final Set<String> _deletedProperties = {};

  JSGlobalThis(this._environment) : super();

  @override
  JSValue getProperty(String name) {
    // Check if property was deleted
    if (_deletedProperties.contains(name)) {
      return JSValueFactory.undefined();
    }

    // First check if it's an accessor property in the parent class
    // (added by defineProperty with getter/setter)
    final accessorDesc = _globalDescriptors[name];
    if (accessorDesc != null && accessorDesc.isAccessor) {
      // Call parent's getProperty to invoke the getter
      return super.getProperty(name);
    }

    // Acces aux variables globales
    try {
      return _environment.get(name);
    } catch (e) {
      // Fall back to parent class for inherited methods like propertyIsEnumerable
      return super.getProperty(name);
    }
  }

  @override
  void setProperty(String name, JSValue value) {
    // Remove from deleted set if it was previously deleted
    _deletedProperties.remove(name);
    // Definition de variables globales
    _environment.set(name, value);
  }

  @override
  void defineProperty(String name, PropertyDescriptor descriptor) {
    // Remove from deleted set if it was previously deleted
    _deletedProperties.remove(name);
    // Store descriptor and set the property value if provided
    _globalDescriptors[name] = descriptor;

    // For accessor properties (with getter/setter), also store in parent class
    // so they can be properly accessed
    if (descriptor.isAccessor) {
      super.defineProperty(name, descriptor);
    } else if (descriptor.value != null) {
      // For data properties, store in environment
      setProperty(name, descriptor.value!);
    }
  }

  @override
  PropertyDescriptor? getOwnPropertyDescriptor(String name) {
    // Check if property was deleted
    if (_deletedProperties.contains(name)) {
      return null;
    }

    // First check if we have a stored descriptor for this global property
    if (_globalDescriptors.containsKey(name)) {
      return _globalDescriptors[name];
    }

    // Check if the property exists in the environment
    if (_environment.hasLocal(name)) {
      try {
        final value = _environment.get(name);
        return PropertyDescriptor(
          value: value,
          writable: true,
          enumerable: true,
          configurable: true,
        );
      } catch (_) {
        return null;
      }
    }

    // Fall back to parent implementation for inherited properties
    return super.getOwnPropertyDescriptor(name);
  }

  @override
  bool hasOwnProperty(String name) {
    // Check if property was deleted
    if (_deletedProperties.contains(name)) {
      return false;
    }

    // Check if we have a stored descriptor for this global property
    if (_globalDescriptors.containsKey(name)) {
      return true;
    }

    // Check if the property exists in the environment
    if (_environment.hasLocal(name)) {
      return true;
    }

    // Fall back to parent implementation for inherited properties
    return super.hasOwnProperty(name);
  }

  @override
  bool hasProperty(String name) {
    // Check if property was deleted
    if (_deletedProperties.contains(name)) {
      return false;
    }

    // Check if we have a stored descriptor for this global property
    if (_globalDescriptors.containsKey(name)) {
      return true;
    }

    // Check if the property exists in the environment
    if (_environment.hasLocal(name)) {
      return true;
    }

    // Fall back to parent implementation for inherited properties
    return super.hasProperty(name);
  }

  @override
  bool deleteProperty(String name) {
    // Check if the property is configurable (only delete if configurable)
    if (_globalDescriptors.containsKey(name)) {
      final descriptor = _globalDescriptors[name];
      if (descriptor != null && !descriptor.configurable) {
        return false; // Cannot delete non-configurable property
      }
      // Delete the property descriptor and mark as deleted
      _globalDescriptors.remove(name);
      _deletedProperties.add(name);
      // Also delete from the environment
      _environment.delete(name);
      return true;
    }

    // For properties in the environment, mark as deleted
    if (_environment.hasLocal(name)) {
      _deletedProperties.add(name);
      _environment.delete(name);
      return true;
    }

    // Fall back to parent implementation for inherited properties
    return super.deleteProperty(name);
  }

  @override
  String toString() => '[object globalThis]';
}

/// A wrapper object that presents a JSFunction as a JSObject
/// This allows functions to be used with Object.getOwnPropertyNames, etc.
class FunctionObject extends JSObject {
  final JSFunction function;

  FunctionObject(this.function);

  @override
  JSValue getProperty(String name) {
    // Delegate to the function's getProperty method
    return function.getProperty(name);
  }

  @override
  void setProperty(String name, JSValue value) {
    // Delegate to the function's setProperty method
    function.setProperty(name, value);
  }

  @override
  bool hasOwnProperty(String name) {
    // Check if the function has this property
    return function.containsOwnProperty(name);
  }

  @override
  List<String> getPropertyNames({bool enumerableOnly = false}) {
    // Delegate to the function's getPropertyNames method if it exists
    // Otherwise, return the basic properties
    if (function is JSNativeFunction) {
      return (function as JSNativeFunction).getPropertyNames(
        enumerableOnly: enumerableOnly,
      );
    }
    // For regular functions, return length, name, and prototype
    final names = <String>[];
    if (function.containsOwnProperty('length')) {
      names.add('length');
    }
    if (function.containsOwnProperty('name')) {
      names.add('name');
    }
    if (function.containsOwnProperty('prototype')) {
      names.add('prototype');
    }
    return names;
  }

  @override
  String toString() => function.toString();

  @override
  bool equals(JSValue other) => function.equals(other);

  @override
  bool strictEquals(JSValue other) => function.strictEquals(other);
}
