/// Implementation of the Object prototype and global Object in JavaScript
/// Provides all static and instance methods of Object
library;

import 'js_value.dart';
import 'environment.dart';
import 'native_functions.dart';
import '../evaluator/evaluator.dart';

/// Object Prototype - methods available on all objects
class ObjectPrototype {
  /// objectToString() - Returns a string representation of the object
  static JSValue objectToString(List<JSValue> args, Environment env) {
    // In JavaScript, toString() is called on 'this'
    // For simplicity, we use the first argument or create a default object
    if (args.isEmpty) {
      return JSValueFactory.string('[object Object]');
    }

    final thisValue = args[0];
    return JSValueFactory.string(thisValue.toString());
  }

  /// valueOf() - Returns the primitive value of the object
  static JSValue valueOf(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      return JSObject();
    }

    final thisValue = args[0];
    if (thisValue.isPrimitive) {
      return thisValue;
    }

    return thisValue; // Objects return themselves
  }

  /// hasOwnProperty(prop) - Checks if the object has the specified property
  static JSValue hasOwnProperty(List<JSValue> args, Environment env) {
    if (args.length < 2) {
      return JSValueFactory.boolean(false);
    }

    final thisValue = args[0];
    final property = args[1].toString();

    // Handle JSClass and JSFunction objects which have getOwnPropertyDescriptor
    if (thisValue is JSClass || thisValue is JSFunction) {
      // Try to get the property descriptor
      if (thisValue is JSClass) {
        final descriptor = thisValue.getOwnPropertyDescriptor(property);
        return JSValueFactory.boolean(descriptor != null);
      } else if (thisValue is JSFunction) {
        // For regular functions, check if they have the property
        final descriptor = thisValue.getOwnPropertyDescriptor(property);
        if (descriptor != null) {
          return JSValueFactory.boolean(true);
        }
        // Fall through to check as object below
      }
    }

    if (thisValue.type != JSValueType.object) {
      return JSValueFactory.boolean(false);
    }

    final obj = thisValue.toObject();
    // Use getOwnPropertyDescriptor to check only own properties, not inherited
    final descriptor = obj.getOwnPropertyDescriptor(property);
    return JSValueFactory.boolean(descriptor != null);
  }

  /// propertyIsEnumerable(prop) - Checks if the property is enumerable
  static JSValue propertyIsEnumerable(List<JSValue> args, Environment env) {
    if (args.length < 2) {
      return JSValueFactory.boolean(false);
    }

    final thisValue = args[0];
    final property = args[1].toString();

    if (thisValue is! JSObject && thisValue is! JSFunction) {
      return JSValueFactory.boolean(false);
    }

    // Get the property descriptor
    PropertyDescriptor? descriptor;
    if (thisValue is JSFunction) {
      descriptor = thisValue.getOwnPropertyDescriptor(property);
    } else if (thisValue is JSObject) {
      descriptor = thisValue.getOwnPropertyDescriptor(property);
    }

    // Return true only if property exists and is enumerable
    if (descriptor != null) {
      return JSValueFactory.boolean(descriptor.enumerable);
    }

    return JSValueFactory.boolean(false);
  }

  /// isPrototypeOf(obj) - Checks if the object is in the prototype chain
  static JSValue isPrototypeOf(List<JSValue> args, Environment env) {
    if (args.length < 2) {
      return JSValueFactory.boolean(false);
    }

    final thisValue = args[0]; // The object on which isPrototypeOf was called
    final testValue = args[1]; // The object to test

    // If testValue is not an object, return false
    if (testValue is! JSObject) {
      return JSValueFactory.boolean(false);
    }

    // If thisValue is not an object, return false
    if (thisValue is! JSObject) {
      return JSValueFactory.boolean(false);
    }

    // Walk the prototype chain of testValue
    JSObject? currentProto = testValue.getPrototype();
    while (currentProto != null) {
      // Check if current prototype is identical to thisValue
      if (identical(currentProto, thisValue)) {
        return JSValueFactory.boolean(true);
      }
      currentProto = currentProto.getPrototype();
    }

    return JSValueFactory.boolean(false);
  }
}

/// Global Object with its static methods
class ObjectGlobal {
  /// Object.keys(obj) - Returns an array of enumerable keys of the object
  static JSValue keys(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      throw Exception('Object.keys called on null or undefined');
    }

    final obj = args[0];

    // Check if it's null or undefined
    if (obj.type == JSValueType.nullType || obj.type == JSValueType.undefined) {
      throw Exception('Object.keys called on null or undefined');
    }

    if (obj.type != JSValueType.object) {
      // For primitives, return an empty array
      return JSValueFactory.array([]);
    }

    final jsObj = obj.toObject();
    final keys = jsObj.getPropertyNames(enumerableOnly: true);

    final keyValues = keys.map((key) => JSValueFactory.string(key)).toList();

    return JSValueFactory.array(keyValues);
  }

  /// Object.values(obj) - Returns an array of enumerable values of the object
  static JSValue values(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      throw JSTypeError('Object.values called on null or undefined');
    }

    final obj = args[0];
    if (obj.type != JSValueType.object) {
      return JSValueFactory.array([]);
    }

    final jsObj = obj.toObject();
    final keys = jsObj.getPropertyNames(enumerableOnly: true);
    final values = keys.map((key) => jsObj.getProperty(key)).toList();

    return JSValueFactory.array(values);
  }

  /// Object.entries(obj) - Returns an array of [key, value] pairs
  static JSValue entries(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      throw JSTypeError('Object.entries called on null or undefined');
    }

    final obj = args[0];
    if (obj.type != JSValueType.object) {
      return JSValueFactory.array([]);
    }

    final jsObj = obj.toObject();
    final keys = jsObj.getPropertyNames(enumerableOnly: true);
    final entries = keys.map((key) {
      final value = jsObj.getProperty(key);
      return JSValueFactory.array([JSValueFactory.string(key), value]);
    }).toList();

    return JSValueFactory.array(entries);
  }

  /// ES2019: Object.fromEntries(iterable) - Creates an object from entries
  static JSValue fromEntries(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      throw JSTypeError('Object.fromEntries called with no arguments');
    }

    final iterable = args[0];
    final result = JSObject();

    // Handle JSArray
    if (iterable is JSArray) {
      for (final entry in iterable.elements) {
        if (entry is JSArray && entry.elements.isNotEmpty) {
          // Get key (convert to string)
          final key = JSConversion.jsToString(entry.elements[0]);
          // Get value (or undefined if not present)
          final value = entry.elements.length > 1
              ? entry.elements[1]
              : JSValueFactory.undefined();
          result.setProperty(key, value);
        }
      }
    }
    // Handle Map
    else if (iterable is JSMap) {
      for (final entry in iterable.entries) {
        final key = JSConversion.jsToString(entry.key);
        final value = entry.value;
        result.setProperty(key, value);
      }
    }
    // Handle other iterables (if they have entries)
    else if (iterable is JSObject) {
      // Try to get entries from the object
      // Return empty object for unsupported types
      return result;
    }

    return result;
  }

  /// Object.assign(target, ...sources) - Copies enumerable properties
  /// ES6: Also copies symbol properties
  static JSValue assign(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      throw Exception('Object.assign requires at least 1 argument');
    }

    final target = args[0];
    if (target.type != JSValueType.object) {
      throw Exception('Object.assign target must be an object');
    }

    final targetObj = target.toObject();

    // Copy properties from each source
    for (int i = 1; i < args.length; i++) {
      final source = args[i];
      if (source.type == JSValueType.object) {
        final sourceObj = source.toObject();

        // Copy string/number properties
        for (final key in sourceObj.getPropertyNames()) {
          final value = sourceObj.getProperty(key);
          targetObj.setProperty(key, value);
        }

        // ES6: Also copy symbol properties
        for (final symbol in sourceObj.getSymbolKeys()) {
          final stringKey = symbol.toString();
          final value = sourceObj.getProperty(stringKey);
          targetObj.setPropertyWithSymbol(stringKey, value, symbol);
        }
      }
    }

    return target;
  }

  /// Object.create(proto) - Creates a new object with the specified prototype
  static JSValue create(List<JSValue> args, Environment env) {
    if (args.isNotEmpty) {
      if (args[0].type == JSValueType.nullType) {
        // Object.create(null) - objet sans prototype
        return JSObject.withoutPrototype();
      } else if (args[0].type == JSValueType.object) {
        // Object.create(obj) - utiliser obj comme prototype
        final prototype = args[0] as JSObject;
        return JSObject(prototype: prototype);
      } else {
        throw JSTypeError('Object prototype may only be an Object or null');
      }
    }

    // No argument - use Object.prototype by default
    return JSObject();
  }

  /// Object.freeze(obj) - Freezes an object (prevents modifications)
  static JSValue freeze(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      throw JSTypeError('Object.freeze called on null or undefined');
    }

    final obj = args[0];
    if (obj.type == JSValueType.object && obj is JSObject) {
      // 1. Special handling for arrays - need to freeze length property explicitly
      // Do this BEFORE making object non-extensible
      if (obj is JSArray) {
        final lengthDesc = obj.getOwnPropertyDescriptor('length');
        if (lengthDesc != null) {
          final frozenLengthDesc = PropertyDescriptor(
            value: lengthDesc.value,
            writable: false, // Make length non-writable
            enumerable: false,
            configurable: false,
          );
          obj.defineProperty('length', frozenLengthDesc);
        }
      }

      // 2. Make all properties non-writable and non-configurable
      final allProperties = obj.getPropertyNames();
      for (final propName in allProperties) {
        // Skip 'length' for arrays as we already handled it
        if (obj is JSArray && propName == 'length') {
          continue;
        }

        var descriptor = obj.getOwnPropertyDescriptor(propName);

        // For array elements without explicit descriptors, create one from the value
        if (descriptor == null && obj is JSArray) {
          final index = int.tryParse(propName);
          if (index != null && index >= 0 && index < obj.length) {
            final value = obj.getProperty(propName);
            descriptor = PropertyDescriptor(
              value: value,
              writable: true,
              enumerable: true,
              configurable: true,
            );
          }
        }

        if (descriptor != null) {
          // Create new descriptor with writable=false and configurable=false
          final frozenDescriptor = PropertyDescriptor(
            value: descriptor.value,
            writable: false, // Make non-writable
            enumerable: descriptor.enumerable,
            configurable: false, // Make non-configurable
            getter: descriptor.getter,
            setter: descriptor.setter,
          );
          obj.defineProperty(propName, frozenDescriptor);
        }
      }

      // 3. Make object non-extensible (prevent adding new properties)
      // Do this AFTER modifying all properties
      obj.isExtensible = false;
    }

    return obj;
  }

  /// Object.seal(obj) - Seals an object (prevents adding/deleting properties)
  static JSValue seal(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      throw JSTypeError('Object.seal called on null or undefined');
    }

    final obj = args[0];
    if (obj.type == JSValueType.object && obj is JSObject) {
      // 1. Make object non-extensible (prevent adding new properties)
      obj.isExtensible = false;

      // 2. Make all properties non-configurable (but keep writable status)
      final allProperties = obj.getPropertyNames();
      for (final propName in allProperties) {
        final descriptor = obj.getOwnPropertyDescriptor(propName);
        if (descriptor != null) {
          // Create new descriptor with configurable=false but keep writable
          final sealedDescriptor = PropertyDescriptor(
            value: descriptor.value,
            writable: descriptor.writable, // Keep current writable status
            enumerable: descriptor.enumerable,
            configurable: false, // Make non-configurable
            getter: descriptor.getter,
            setter: descriptor.setter,
          );
          obj.defineProperty(propName, sealedDescriptor);
        }
      }
    }

    return obj;
  }

  /// Object.isFrozen(obj) - Checks if an object is frozen
  static JSValue isFrozen(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      return JSValueFactory.boolean(true);
    }

    final obj = args[0];
    if (obj.type != JSValueType.object || obj is! JSObject) {
      // Non-objects are considered frozen
      return JSValueFactory.boolean(true);
    }

    // An object is frozen if:
    // 1. It is not extensible
    if (obj.isExtensible) {
      return JSValueFactory.boolean(false);
    }

    // 2. All of its properties are non-configurable
    // 3. All data properties are non-writable
    final allProperties = obj.getPropertyNames();
    for (final propName in allProperties) {
      final descriptor = obj.getOwnPropertyDescriptor(propName);
      if (descriptor != null) {
        // If any property is configurable, object is not frozen
        if (descriptor.configurable) {
          return JSValueFactory.boolean(false);
        }
        // If it's a data property and writable, object is not frozen
        if (descriptor.isData && descriptor.writable) {
          return JSValueFactory.boolean(false);
        }
      }
    }

    return JSValueFactory.boolean(true);
  }

  /// Object.isSealed(obj) - Checks if an object is sealed
  static JSValue isSealed(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      return JSValueFactory.boolean(true);
    }

    final obj = args[0];
    if (obj.type != JSValueType.object || obj is! JSObject) {
      // Non-objects are considered sealed
      return JSValueFactory.boolean(true);
    }

    // An object is sealed if:
    // 1. It is not extensible
    if (obj.isExtensible) {
      return JSValueFactory.boolean(false);
    }

    // 2. All of its properties are non-configurable
    final allProperties = obj.getPropertyNames();
    for (final propName in allProperties) {
      final descriptor = obj.getOwnPropertyDescriptor(propName);
      if (descriptor != null && descriptor.configurable) {
        return JSValueFactory.boolean(false);
      }
    }

    return JSValueFactory.boolean(true);
  }

  /// Object.isExtensible(obj) - Checks if an object is extensible
  static JSValue isExtensible(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      throw JSTypeError('Object.isExtensible called on null or undefined');
    }

    final obj = args[0];
    if (obj.isNull || obj.isUndefined) {
      throw JSTypeError('Object.isExtensible called on null or undefined');
    }

    // Functions are extensible by default (per ES spec)
    if (obj is JSFunction) {
      return JSValueFactory.boolean(true);
    }

    // For objects, check their extensible flag
    if (obj.type == JSValueType.object) {
      final jsObj = obj as JSObject;
      return JSValueFactory.boolean(jsObj.isExtensible);
    }

    // For primitives, they are not objects so not extensible
    return JSValueFactory.boolean(false);
  }

  /// Object.preventExtensions(obj) - Prevents extending an object
  static JSValue preventExtensions(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      throw JSTypeError('Object.preventExtensions called on null or undefined');
    }

    final obj = args[0];
    if (obj.isNull || obj.isUndefined) {
      throw JSTypeError('Object.preventExtensions called on null or undefined');
    }

    // For objects, mark as non-extensible
    if (obj.type == JSValueType.object) {
      final jsObj = obj as JSObject;
      jsObj.isExtensible = false;
      return obj; // Return the object itself
    }

    // For primitives, return the primitive (no effect)
    return obj;
  }

  /// Object.getPrototypeOf(obj) - Retourne le prototype d'un objet
  static JSValue getPrototypeOf(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      throw JSTypeError('Object.getPrototypeOf called on null or undefined');
    }

    final obj = args[0];
    if (obj.isNull || obj.isUndefined) {
      throw JSTypeError('Object.getPrototypeOf called on null or undefined');
    }

    // For classes (which are "constructor functions" in JS)
    // return their prototype according to the prototype chain
    if (obj is JSClass) {
      // If class extends another class, return the superclass
      if (obj.superClass != null) {
        return obj.superClass!;
      }
      // If class extends a native function (like Error), return that function
      if (obj.superFunction != null) {
        return obj.superFunction!;
      }
      // If class extends null, the [[Prototype]] is Function.prototype
      // For base classes without extends, the [[Prototype]] is also Function.prototype
      final funcProto = JSFunction.functionPrototype;
      return funcProto ?? JSValueFactory.nullValue();
    }

    // For functions, return Function.prototype
    if (obj is JSFunction) {
      final funcProto = JSFunction.functionPrototype;
      return funcProto ?? JSValueFactory.nullValue();
    }

    // For objects, return their prototype
    if (obj is JSObject) {
      return obj.getPrototype() ?? JSValueFactory.nullValue();
    }

    // For primitives, return null (their prototype is not yet implemented as an object)

    return JSValueFactory.nullValue();
  }

  /// Object.setPrototypeOf(obj, prototype) - Sets the prototype of an object (ES6)
  static JSValue setPrototypeOf(List<JSValue> args, Environment env) {
    if (args.length < 2) {
      throw JSTypeError('Object.setPrototypeOf requires 2 arguments');
    }

    final obj = args[0];

    // En JavaScript, les fonctions sont des objets
    // Accepter JSObject ET JSFunction
    if (obj is! JSObject && obj is! JSFunction) {
      throw JSTypeError('Object.setPrototypeOf called on non-object');
    }

    final proto = args[1];

    // prototype must be an object or null
    if (!proto.isNull && proto is! JSObject && proto is! JSFunction) {
      throw JSTypeError(
        'Object.setPrototypeOf: prototype must be an object or null',
      );
    }

    // Set the prototype
    if (obj is JSObject) {
      obj.setPrototype(proto.isNull ? null : proto as JSObject?);
    } else if (obj is JSFunction) {
      // For functions, set the prototype via setProperty
      // (functions can have properties like objects)
      obj.setProperty('__proto__', proto);
    }

    // Return the object (per ES6 spec)
    return obj;
  }

  /// Object.is(value1, value2) - Determines if two values are identical
  /// Similar to === but with special cases for NaN and +0/-0
  static JSValue is_(List<JSValue> args, Environment env) {
    if (args.length < 2) {
      // If less than 2 arguments, compare with undefined
      final value1 = args.isNotEmpty ? args[0] : JSValueFactory.undefined();
      final value2 = JSValueFactory.undefined();
      return JSValueFactory.boolean(_sameValue(value1, value2));
    }

    final value1 = args[0];
    final value2 = args[1];

    return JSValueFactory.boolean(_sameValue(value1, value2));
  }

  /// Algorithme SameValue de l'ECMAScript
  static bool _sameValue(JSValue x, JSValue y) {
    // If types differ, they are not identical
    if (x.type != y.type) {
      return false;
    }

    // Cas particulier: undefined
    if (x.isUndefined) {
      return true;
    }

    // Cas particulier: null
    if (x.isNull) {
      return true;
    }

    // Cas particulier: Number
    if (x.isNumber) {
      final xNum = x.toNumber();
      final yNum = y.toNumber();

      // NaN equals NaN in Object.is (different from ===)
      if (xNum.isNaN && yNum.isNaN) {
        return true;
      }

      // +0 and -0 are different in Object.is (different from ===)
      if (xNum == 0 && yNum == 0) {
        // Check the sign
        return (1 / xNum).isNegative == (1 / yNum).isNegative;
      }

      return xNum == yNum;
    }

    // Cas particulier: String
    if (x.isString) {
      return x.toString() == y.toString();
    }

    // Cas particulier: Boolean
    if (x.isBoolean) {
      return x.toBoolean() == y.toBoolean();
    }

    // Cas particulier: BigInt
    if (x.isBigInt) {
      return x == y; // Use reference equality for BigInt
    }

    // Cas particulier: Symbol
    if (x.isSymbol) {
      return x == y; // Symbols are compared by reference
    }

    // For objects and functions: reference comparison
    return identical(x, y);
  }

  /// Object.hasOwn(obj, prop) - Modern method for hasOwnProperty
  static JSValue hasOwn(List<JSValue> args, Environment env) {
    if (args.length < 2) {
      return JSValueFactory.boolean(false);
    }

    final obj = args[0];
    final property = args[1].toString();

    if (obj.type != JSValueType.object) {
      return JSValueFactory.boolean(false);
    }

    final jsObj = obj.toObject();
    // ES2022: Use hasOwnProperty to check only own properties, not inherited
    return JSValueFactory.boolean(jsObj.hasOwnProperty(property));
  }

  /// Object.defineProperty(obj, prop, descriptor) - Defines a property with descriptor
  static JSValue defineProperty(List<JSValue> args, Environment env) {
    if (args.length < 3) {
      throw JSTypeError('Object.defineProperty requires 3 arguments');
    }

    final obj = args[0];
    final property = args[1].toString();
    final descriptorArg = args[2];

    // Accept JSObject and JSFunction (functions are objects in JS)
    if (obj is! JSObject && obj is! JSFunction) {
      throw JSTypeError('Object.defineProperty called on non-object');
    }

    JSObject? jsObj;
    JSFunction? jsFunc;

    if (obj is JSObject) {
      jsObj = obj;
    } else if (obj is JSFunction) {
      jsFunc = obj;
    }

    // Create the descriptor from the passed object
    PropertyDescriptor descriptor;

    if (descriptorArg.type == JSValueType.object) {
      final descObj = descriptorArg as JSObject;

      // Check if there are get/set (accessor property)
      final getter = descObj.getProperty('get');
      final setter = descObj.getProperty('set');
      final value = descObj.getProperty('value');
      final hasValue = descObj.hasProperty('value');

      // ES6: defaults are false for all flags if not specified
      final configurable = descObj.hasProperty('configurable')
          ? descObj.getProperty('configurable').toBoolean()
          : false;
      final enumerable = descObj.hasProperty('enumerable')
          ? descObj.getProperty('enumerable').toBoolean()
          : false;
      final writable = descObj.hasProperty('writable')
          ? descObj.getProperty('writable').toBoolean()
          : false;

      if (getter.type == JSValueType.function ||
          setter.type == JSValueType.function) {
        // Accessor property
        descriptor = PropertyDescriptor(
          getter: getter.type == JSValueType.function
              ? getter as JSFunction
              : null,
          setter: setter.type == JSValueType.function
              ? setter as JSFunction
              : null,
          configurable: configurable,
          enumerable: enumerable,
          hasValueProperty: false,
        );
      } else {
        // Data property (even if value is undefined)
        descriptor = PropertyDescriptor(
          value: value,
          writable: writable,
          configurable: configurable,
          enumerable: enumerable,
          hasValueProperty: hasValue,
        );
      }
    } else {
      throw JSTypeError('Property descriptor must be an object');
    }

    // Define the property with the descriptor
    if (jsObj != null) {
      jsObj.defineProperty(property, descriptor);
    } else if (jsFunc != null) {
      jsFunc.defineProperty(property, descriptor);
    }

    return obj; // Return the modified object
  }

  /// Object.defineProperties(obj, properties) - ES5
  /// Defines multiple properties with their descriptors
  static JSValue defineProperties(List<JSValue> args, Environment env) {
    if (args.length < 2) {
      throw JSTypeError('Object.defineProperties requires 2 arguments');
    }

    final obj = args[0];
    final propsArg = args[1];

    if (obj.type != JSValueType.object) {
      throw JSTypeError('Object.defineProperties called on non-object');
    }

    if (propsArg.type != JSValueType.object) {
      throw JSTypeError(
        'Object.defineProperties: properties argument must be an object',
      );
    }

    final jsObj = obj as JSObject;
    final propsObj = propsArg as JSObject;

    // Get all enumerable properties of the properties object
    final propNames = propsObj.getPropertyNames();

    for (final propName in propNames) {
      // Check that the property is enumerable
      final propDescriptor = propsObj.getOwnPropertyDescriptor(propName);
      if (propDescriptor != null && propDescriptor.enumerable) {
        // Get the descriptor for this property
        final descriptorArg = propsObj.getProperty(propName);

        if (descriptorArg.type == JSValueType.object) {
          final descObj = descriptorArg as JSObject;

          // Create the descriptor from the object
          final getter = descObj.getProperty('get');
          final setter = descObj.getProperty('set');
          final value = descObj.getProperty('value');

          final configurable = descObj.hasProperty('configurable')
              ? descObj.getProperty('configurable').toBoolean()
              : true;
          final enumerable = descObj.hasProperty('enumerable')
              ? descObj.getProperty('enumerable').toBoolean()
              : true;
          final writable = descObj.hasProperty('writable')
              ? descObj.getProperty('writable').toBoolean()
              : true;

          PropertyDescriptor descriptor;

          if (getter.type == JSValueType.function ||
              setter.type == JSValueType.function) {
            // Accessor property
            descriptor = PropertyDescriptor(
              getter: getter.type == JSValueType.function
                  ? getter as JSFunction
                  : null,
              setter: setter.type == JSValueType.function
                  ? setter as JSFunction
                  : null,
              configurable: configurable,
              enumerable: enumerable,
            );
          } else {
            // Data property (even if value is not defined, we create the descriptor)
            descriptor = PropertyDescriptor(
              value: value.isUndefined ? JSValueFactory.undefined() : value,
              writable: writable,
              configurable: configurable,
              enumerable: enumerable,
            );
          }

          // Define the property with the descriptor
          jsObj.defineProperty(propName, descriptor);
        }
      }
    }

    return obj; // Return the modified object
  }

  /// Object.getOwnPropertyDescriptor(obj, prop) - Gets the descriptor of a property
  static JSValue getOwnPropertyDescriptor(List<JSValue> args, Environment env) {
    if (args.length < 2) {
      return JSValueFactory.undefined();
    }

    final obj = args[0];
    final property = args[1].toString();

    PropertyDescriptor? descriptor;

    // Support pour les fonctions (Number, String, etc.)
    if (obj is JSFunction) {
      descriptor = obj.getOwnPropertyDescriptor(property);
    } else if (obj is JSClass) {
      // Support for class constructors (static properties and methods)
      descriptor = obj.getOwnPropertyDescriptor(property);
    } else if (obj.type == JSValueType.object) {
      final jsObj = obj as JSObject;
      descriptor = jsObj.getOwnPropertyDescriptor(property);
    } else {
      return JSValueFactory.undefined();
    }

    if (descriptor == null) {
      return JSValueFactory.undefined();
    }

    // Create an object representing the descriptor
    final descObj = JSObject();

    if (descriptor.isAccessor) {
      // Accessor property
      if (descriptor.getter != null) {
        descObj.setProperty('get', descriptor.getter!);
      } else {
        descObj.setProperty('get', JSValueFactory.undefined());
      }

      if (descriptor.setter != null) {
        descObj.setProperty('set', descriptor.setter!);
      } else {
        descObj.setProperty('set', JSValueFactory.undefined());
      }

      descObj.setProperty(
        'configurable',
        JSValueFactory.boolean(descriptor.configurable),
      );
      descObj.setProperty(
        'enumerable',
        JSValueFactory.boolean(descriptor.enumerable),
      );
    } else {
      // Data property
      descObj.setProperty(
        'value',
        descriptor.value ?? JSValueFactory.undefined(),
      );
      descObj.setProperty(
        'writable',
        JSValueFactory.boolean(descriptor.writable),
      );
      descObj.setProperty(
        'configurable',
        JSValueFactory.boolean(descriptor.configurable),
      );
      descObj.setProperty(
        'enumerable',
        JSValueFactory.boolean(descriptor.enumerable),
      );
    }

    return descObj;
  }

  /// Object.getOwnPropertyDescriptors(obj) - ES2017
  /// Returns an object containing all descriptors of own properties
  static JSValue getOwnPropertyDescriptors(
    List<JSValue> args,
    Environment env,
  ) {
    if (args.isEmpty) {
      throw JSTypeError(
        'Object.getOwnPropertyDescriptors called on null or undefined',
      );
    }

    final obj = args[0];

    if (obj.isNull || obj.isUndefined) {
      throw JSTypeError(
        'Object.getOwnPropertyDescriptors called on null or undefined',
      );
    }

    // Convert to object if necessary (for primitives)
    final jsObj = obj.toObject();

    // Create the result object that will contain all descriptors
    final descriptors = JSObject();

    // Get all own properties (enumerable and non-enumerable)
    final allKeys = jsObj.getPropertyNames();

    for (final key in allKeys) {
      // Get the descriptor for each property
      final descriptor = jsObj.getOwnPropertyDescriptor(key);

      if (descriptor != null) {
        // Create an object representing the descriptor
        final descObj = JSObject();

        if (descriptor.isAccessor) {
          // Accessor property
          if (descriptor.getter != null) {
            descObj.setProperty('get', descriptor.getter!);
          } else {
            descObj.setProperty('get', JSValueFactory.undefined());
          }

          if (descriptor.setter != null) {
            descObj.setProperty('set', descriptor.setter!);
          } else {
            descObj.setProperty('set', JSValueFactory.undefined());
          }

          descObj.setProperty(
            'configurable',
            JSValueFactory.boolean(descriptor.configurable),
          );
          descObj.setProperty(
            'enumerable',
            JSValueFactory.boolean(descriptor.enumerable),
          );
        } else {
          // Data property
          descObj.setProperty(
            'value',
            descriptor.value ?? JSValueFactory.undefined(),
          );
          descObj.setProperty(
            'writable',
            JSValueFactory.boolean(descriptor.writable),
          );
          descObj.setProperty(
            'configurable',
            JSValueFactory.boolean(descriptor.configurable),
          );
          descObj.setProperty(
            'enumerable',
            JSValueFactory.boolean(descriptor.enumerable),
          );
        }

        // Add this descriptor to the result object
        descriptors.setProperty(key, descObj);
      }
    }

    return descriptors;
  }

  /// Object.getOwnPropertyNames(obj) - ES5
  /// Returns an array containing all own property names (enumerable and non-enumerable)
  static JSValue getOwnPropertyNames(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      throw JSTypeError(
        'Object.getOwnPropertyNames called on null or undefined',
      );
    }

    final obj = args[0];

    if (obj.isNull || obj.isUndefined) {
      throw JSTypeError(
        'Object.getOwnPropertyNames called on null or undefined',
      );
    }

    // Convert to object if necessary (for primitives)
    final jsObj = obj.toObject();

    // Get all own properties (enumerable and non-enumerable)
    final allKeys = jsObj.getPropertyNames();

    // Create an array with all property names
    final keysArray = JSArray();
    for (final key in allKeys) {
      keysArray.push(JSValueFactory.string(key));
    }

    return keysArray;
  }

  /// Object.getOwnPropertySymbols(obj) - ES6
  /// Returns an array of all symbol properties found directly on a given object
  static JSValue getOwnPropertySymbols(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      throw JSTypeError(
        'Object.getOwnPropertySymbols called on null or undefined',
      );
    }

    final obj = args[0];

    if (obj.isNull || obj.isUndefined) {
      throw JSTypeError(
        'Object.getOwnPropertySymbols called on null or undefined',
      );
    }

    // Get all symbol properties
    final symbolsArray = JSArray();

    // ES6: Retrieve all tracked symbol keys from the object
    if (obj is JSObject) {
      // Access the _symbolKeys map to get all symbol properties
      // The map contains string keys to JSSymbol instances
      for (final symbol in obj.getSymbolKeys()) {
        symbolsArray.elements.add(symbol);
      }
    }

    return symbolsArray;
  }

  /// Object.groupBy(items, callbackFn) - ES2024
  /// Groups elements of an iterable according to the string values returned by a callback function
  /// Returns an object where each key is a unique group identifier and each value is an array of elements
  static JSValue groupBy(List<JSValue> args, Environment env) {
    if (args.isEmpty) {
      throw JSTypeError('Object.groupBy requires at least one argument');
    }

    final items = args[0];

    if (args.length < 2 || !args[1].isFunction) {
      throw JSTypeError('Object.groupBy requires a callback function');
    }

    final callbackFn = args[1];

    // Convert items to list
    List<JSValue> itemsList;
    if (items is JSArray) {
      itemsList = items.elements;
    } else {
      throw JSTypeError('Object.groupBy requires an iterable');
    }

    // Create result object to hold groups
    final result = JSObject();

    // Group elements by callback return value
    for (int i = 0; i < itemsList.length; i++) {
      final element = itemsList[i];

      // Call callback with (element, index)
      final key = _callCallbackFunction(
        callbackFn,
        [element, JSValueFactory.number(i)],
        JSValueFactory.undefined(),
        env,
      );

      // Convert key to string (property key coercion)
      final keyString = key.isNull ? 'null' : key.toString();

      // Get or create array for this group
      JSArray groupArray;
      if (result.hasProperty(keyString)) {
        final existingGroup = result.getProperty(keyString);
        if (existingGroup is JSArray) {
          groupArray = existingGroup;
        } else {
          groupArray = JSArray();
          result.setProperty(keyString, groupArray);
        }
      } else {
        groupArray = JSArray();
        result.setProperty(keyString, groupArray);
      }

      // Add element to group
      groupArray.push(element);
    }

    return result;
  }

  /// Helper method to call a callback function with proper context
  static JSValue _callCallbackFunction(
    JSValue function,
    List<JSValue> args,
    JSValue thisBinding,
    Environment env,
  ) {
    // Check if it's a native function
    if (function is JSNativeFunction) {
      return function.nativeImpl(args);
    }

    // Try to get current evaluator instance for JS functions
    try {
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        return evaluator.callFunction(function, args, thisBinding);
      }
    } catch (e) {
      // Fallback: throw an error
    }

    throw JSError('Unable to call callback function');
  }

  /// Creates the global Object with all its methods
  static JSNativeFunction createObjectGlobal() {
    // Object constructeur - retourne un nouvel objet ou convertit la valeur en objet
    final objectConstructor = JSNativeFunction(
      functionName: 'Object',
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSObject();
        }

        final value = args[0];
        if (value.isNull || value.isUndefined) {
          return JSObject();
        }

        // Symbols must be wrapped, even though JSSymbol extends JSObject
        if (value.isSymbol) {
          return value.toObject();
        }

        // If it's already an object, return it as is
        if (value is JSObject) {
          return value;
        }

        // If it's a function, return it as-is (functions are objects)
        if (value is JSFunction) {
          return value;
        }

        // Convert primitive to wrapper object using toObject()
        return value.toObject();
      },
      expectedArgs: 1,
      isConstructor: true, // Object is a constructor
    );

    // Add Object.prototype as a static property
    objectConstructor.setProperty('prototype', JSObject.objectPrototype);

    // IMPORTANT: Add the constructor property to Object.prototype
    // so that all objects have access to their constructor
    JSObject.objectPrototype.setProperty('constructor', objectConstructor);

    // Static methods of Object with wrappers for the environment
    objectConstructor.setProperty(
      'keys',
      JSNativeFunction(
        functionName: 'keys',
        nativeImpl: (args) => keys(args, Environment.global()),
        expectedArgs: 1,
      ),
    );
    objectConstructor.setProperty(
      'values',
      JSNativeFunction(
        functionName: 'values',
        nativeImpl: (args) => values(args, Environment.global()),
        expectedArgs: 1,
      ),
    );
    objectConstructor.setProperty(
      'entries',
      JSNativeFunction(
        functionName: 'entries',
        nativeImpl: (args) => entries(args, Environment.global()),
        expectedArgs: 1,
      ),
    );
    objectConstructor.setProperty(
      'fromEntries',
      JSNativeFunction(
        functionName: 'fromEntries',
        nativeImpl: (args) => fromEntries(args, Environment.global()),
        expectedArgs: 1,
      ),
    );
    objectConstructor.setProperty(
      'assign',
      JSNativeFunction(
        functionName: 'assign',
        nativeImpl: (args) => assign(args, Environment.global()),
        expectedArgs: 2,
      ),
    );
    objectConstructor.setProperty(
      'create',
      JSNativeFunction(
        functionName: 'create',
        nativeImpl: (args) => create(args, Environment.global()),
        expectedArgs: 2,
      ),
    );
    objectConstructor.setProperty(
      'freeze',
      JSNativeFunction(
        functionName: 'freeze',
        nativeImpl: (args) => freeze(args, Environment.global()),
        expectedArgs: 1,
      ),
    );
    objectConstructor.setProperty(
      'seal',
      JSNativeFunction(
        functionName: 'seal',
        nativeImpl: (args) => seal(args, Environment.global()),
        expectedArgs: 1,
      ),
    );
    objectConstructor.setProperty(
      'isFrozen',
      JSNativeFunction(
        functionName: 'isFrozen',
        nativeImpl: (args) => isFrozen(args, Environment.global()),
        expectedArgs: 1,
      ),
    );
    objectConstructor.setProperty(
      'isSealed',
      JSNativeFunction(
        functionName: 'isSealed',
        nativeImpl: (args) => isSealed(args, Environment.global()),
        expectedArgs: 1,
      ),
    );
    objectConstructor.setProperty(
      'isExtensible',
      JSNativeFunction(
        functionName: 'isExtensible',
        nativeImpl: (args) => isExtensible(args, Environment.global()),
        expectedArgs: 1,
      ),
    );
    objectConstructor.setProperty(
      'preventExtensions',
      JSNativeFunction(
        functionName: 'preventExtensions',
        nativeImpl: (args) => preventExtensions(args, Environment.global()),
        expectedArgs: 1,
      ),
    );
    objectConstructor.setProperty(
      'getPrototypeOf',
      JSNativeFunction(
        functionName: 'getPrototypeOf',
        nativeImpl: (args) => getPrototypeOf(args, Environment.global()),
        expectedArgs: 1,
      ),
    );
    objectConstructor.setProperty(
      'setPrototypeOf',
      JSNativeFunction(
        functionName: 'setPrototypeOf',
        nativeImpl: (args) => setPrototypeOf(args, Environment.global()),
        expectedArgs: 2,
      ),
    );
    objectConstructor.setProperty(
      'hasOwn',
      JSNativeFunction(
        functionName: 'hasOwn',
        nativeImpl: (args) => hasOwn(args, Environment.global()),
        expectedArgs: 2,
      ),
    );
    objectConstructor.setProperty(
      'is',
      JSNativeFunction(
        functionName: 'is',
        nativeImpl: (args) => is_(args, Environment.global()),
        expectedArgs: 2,
      ),
    );
    objectConstructor.setProperty(
      'defineProperty',
      JSNativeFunction(
        functionName: 'defineProperty',
        nativeImpl: (args) => defineProperty(args, Environment.global()),
        expectedArgs: 3,
      ),
    );
    objectConstructor.setProperty(
      'getOwnPropertyDescriptor',
      JSNativeFunction(
        functionName: 'getOwnPropertyDescriptor',
        nativeImpl: (args) =>
            getOwnPropertyDescriptor(args, Environment.global()),
        expectedArgs: 2,
      ),
    );
    objectConstructor.setProperty(
      'getOwnPropertyDescriptors',
      JSNativeFunction(
        functionName: 'getOwnPropertyDescriptors',
        nativeImpl: (args) =>
            getOwnPropertyDescriptors(args, Environment.global()),
        expectedArgs: 1,
      ),
    );
    objectConstructor.setProperty(
      'defineProperties',
      JSNativeFunction(
        functionName: 'defineProperties',
        nativeImpl: (args) => defineProperties(args, Environment.global()),
        expectedArgs: 2,
      ),
    );
    objectConstructor.setProperty(
      'getOwnPropertyNames',
      JSNativeFunction(
        functionName: 'getOwnPropertyNames',
        nativeImpl: (args) => getOwnPropertyNames(args, Environment.global()),
        expectedArgs: 1,
      ),
    );
    objectConstructor.setProperty(
      'getOwnPropertySymbols',
      JSNativeFunction(
        functionName: 'getOwnPropertySymbols',
        nativeImpl: (args) => getOwnPropertySymbols(args, Environment.global()),
        expectedArgs: 1,
      ),
    );
    objectConstructor.setProperty(
      'groupBy',
      JSNativeFunction(
        functionName: 'groupBy',
        nativeImpl: (args) => groupBy(args, Environment.global()),
        expectedArgs: 2,
      ),
    );

    return objectConstructor;
  }
}
