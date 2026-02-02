/// Array prototype and native methods
///
/// Implements all Array ECMAScript methods
library;

import 'js_value.dart';
import 'native_functions.dart';
import 'iterator_protocol.dart';
import 'js_symbol.dart';
import 'js_regexp.dart';
import 'date_object.dart';
import '../evaluator/evaluator.dart';

/// Array prototype with all methods
class ArrayPrototype {
  /// Store references to original native functions set on Array.prototype
  /// This is used to detect when a method has been overridden
  static final Map<String, JSNativeFunction> _originalNatives = {};

  /// Clear all registered native functions (called when creating a new interpreter)
  static void clearOriginalNatives() {
    _originalNatives.clear();
  }

  /// Register an original native function
  static void registerOriginalNative(String name, JSNativeFunction fn) {
    _originalNatives[name] = fn;
  }

  /// Check if a function is the original native or has been overridden
  static bool isOriginalNative(String name, JSValue fn) {
    if (!_originalNatives.containsKey(name)) return false;
    return identical(fn, _originalNatives[name]);
  }

  /// Helper: Convert a numeric value to an integer, handling NaN and Infinity
  /// according to ECMAScript spec (ToInteger abstract operation)
  /// ToInteger truncates towards zero, not floor
  static int toArrayIndex(double num) {
    if (num.isNaN) return 0;
    if (num.isInfinite) return num > 0 ? 0x7FFFFFFF : 0;
    return num.truncate(); // Truncate towards zero, not floor
  }

  /// Array.prototype.length (property)
  static JSValue length(JSArray arr) {
    return JSValueFactory.number(arr.length);
  }

  /// Array.prototype.push(...elements)
  /// When called via callWithThis, the first argument is 'this' (the array)
  static JSValue push(List<JSValue> args, [JSArray? arr]) {
    // If arr is not provided, the first argument is 'this'
    JSValue thisObj;
    List<JSValue> elementsToAdd;

    final isCallOnPrototype =
        arr != null && identical(arr, JSArray.arrayPrototype);

    if (isCallOnPrototype && args.isNotEmpty) {
      thisObj = args[0];
      elementsToAdd = args.length > 1 ? args.sublist(1) : [];
    } else if (arr != null && args.isNotEmpty && identical(args[0], arr)) {
      // Direct call but thisBinding was prepended
      thisObj = arr;
      elementsToAdd = args.sublist(1);
    } else if (arr != null) {
      thisObj = arr;
      elementsToAdd = args;
    } else if (args.isNotEmpty) {
      // Fallback: first arg is this
      thisObj = args[0];
      elementsToAdd = args.length > 1 ? args.sublist(1) : [];
    } else {
      throw JSTypeError('Array.prototype.push requires this binding');
    }

    // ES spec: Throw TypeError if this is null or undefined
    if (thisObj.isNull || thisObj.isUndefined) {
      throw JSTypeError('Array.prototype.push called on null or undefined');
    }

    // Convert to Object (handles primitives like booleans, numbers, strings)
    // Note: JSFunction extends JSValue, not JSObject, but has all the same methods
    final dynamic targetObj = (thisObj is JSObject || thisObj is JSFunction)
        ? thisObj
        : thisObj.toObject();

    // Get current length
    final lengthValue = targetObj.getProperty('length');
    int len = _toLength(lengthValue);

    const maxLength = 9007199254740991; // 2^53 - 1

    // Add elements at indices starting from len
    for (final element in elementsToAdd) {
      // Check if we would exceed max length
      if (len >= maxLength) {
        throw JSTypeError('Invalid array length');
      }
      // Use strict set to throw TypeError if property is non-writable (ES spec: Set(O, P, V, true))
      _setPropertyStrict(targetObj, len.toString(), element);
      len++;
    }

    // Update length property (use strict mode to throw on non-writable)
    _setPropertyStrict(targetObj, 'length', JSValueFactory.number(len));

    return JSValueFactory.number(len);
  }

  /// Array.prototype.pop()
  static JSValue pop(List<JSValue> args, [JSArray? arr]) {
    JSValue thisObj;

    final isCallOnPrototype =
        arr != null && identical(arr, JSArray.arrayPrototype);

    if (isCallOnPrototype && args.isNotEmpty) {
      // .call(thisArg) - first arg is the this value
      thisObj = args[0];
    } else if (arr != null && args.isNotEmpty && identical(args[0], arr)) {
      // Direct call but thisBinding was prepended (rare case)
      thisObj = arr;
    } else if (arr != null) {
      // Normal call: arr.pop()
      thisObj = arr;
    } else if (args.isNotEmpty) {
      // Fallback
      thisObj = args[0];
    } else {
      throw JSTypeError('Array.prototype.pop requires this binding');
    }

    if (thisObj.isNull || thisObj.isUndefined) {
      throw JSTypeError('Array.prototype.pop called on null or undefined');
    }

    // Convert to Object (handles primitives like booleans, numbers, strings)
    // Note: JSFunction extends JSValue, not JSObject, but has all the same methods
    final dynamic targetObj = (thisObj is JSObject || thisObj is JSFunction)
        ? thisObj
        : thisObj.toObject();

    // Get current length
    final lengthValue = targetObj.getProperty('length');
    int len = _toLength(lengthValue);

    if (len == 0) {
      // Set length to 0 and return undefined (use strict mode)
      _setPropertyStrict(targetObj, 'length', JSValueFactory.number(0));
      return JSValueFactory.undefined();
    }

    // Get element at len-1
    final newLen = len - 1;
    final element = targetObj.getProperty(newLen.toString());

    // Delete the property
    targetObj.deleteProperty(newLen.toString());

    // Update length (use strict mode)
    _setPropertyStrict(targetObj, 'length', JSValueFactory.number(newLen));

    return element;
  }

  /// Array.prototype.shift()
  static JSValue shift(List<JSValue> args, [JSArray? arr]) {
    JSValue thisObj;

    final isCallOnPrototype =
        arr != null && identical(arr, JSArray.arrayPrototype);

    if (isCallOnPrototype && args.isNotEmpty) {
      // .call(thisArg) - first arg is the this value
      thisObj = args[0];
    } else if (arr != null && args.isNotEmpty && identical(args[0], arr)) {
      // Direct call but thisBinding was prepended (rare case)
      thisObj = arr;
    } else if (arr != null) {
      // Normal call: arr.shift()
      thisObj = arr;
    } else if (args.isNotEmpty) {
      // Fallback
      thisObj = args[0];
    } else {
      throw JSTypeError('Array.prototype.shift requires this binding');
    }

    if (thisObj.isNull || thisObj.isUndefined) {
      throw JSTypeError('Array.prototype.shift called on null or undefined');
    }

    // Convert to Object (handles primitives like booleans, numbers, strings)
    // Note: JSFunction extends JSValue, not JSObject, but has all the same methods
    final dynamic targetObj = (thisObj is JSObject || thisObj is JSFunction)
        ? thisObj
        : thisObj.toObject();

    // Get current length
    final lengthValue = targetObj.getProperty('length');
    int len = _toLength(lengthValue);

    if (len == 0) {
      // Set length to 0 and return undefined (use strict mode)
      _setPropertyStrict(targetObj, 'length', JSValueFactory.number(0));
      return JSValueFactory.undefined();
    }

    // Get first element
    final first = targetObj.getProperty('0');

    // Shift all elements down by one
    for (int k = 1; k < len; k++) {
      final from = k.toString();
      final to = (k - 1).toString();

      final fromValue = targetObj.getProperty(from);
      if (!fromValue.isUndefined || targetObj.hasProperty(from)) {
        _setPropertyStrict(targetObj, to, fromValue);
      } else {
        targetObj.deleteProperty(to);
      }
    }

    // Delete the last element
    targetObj.deleteProperty((len - 1).toString());

    // Update length (use strict mode)
    _setPropertyStrict(targetObj, 'length', JSValueFactory.number(len - 1));

    return first;
  }

  /// Array.prototype.unshift(...elements)
  static JSValue unshift(List<JSValue> args, [JSArray? arr]) {
    JSValue thisObj;
    List<JSValue> elementsToAdd;

    final isCallOnPrototype =
        arr != null && identical(arr, JSArray.arrayPrototype);

    if (isCallOnPrototype && args.isNotEmpty) {
      thisObj = args[0];
      elementsToAdd = args.length > 1 ? args.sublist(1) : [];
    } else if (arr != null && args.isNotEmpty && identical(args[0], arr)) {
      thisObj = arr;
      elementsToAdd = args.sublist(1);
    } else if (arr != null) {
      thisObj = arr;
      elementsToAdd = args;
    } else if (args.isNotEmpty) {
      thisObj = args[0];
      elementsToAdd = args.length > 1 ? args.sublist(1) : [];
    } else {
      throw JSTypeError('Array.prototype.unshift requires this binding');
    }

    if (thisObj.isNull || thisObj.isUndefined) {
      throw JSTypeError('Array.prototype.unshift called on null or undefined');
    }

    // Convert to Object (handles primitives like booleans, numbers, strings)
    // Note: JSFunction extends JSValue, not JSObject, but has all the same methods
    final dynamic targetObj = (thisObj is JSObject || thisObj is JSFunction)
        ? thisObj
        : thisObj.toObject();

    // Get current length
    final lengthValue = targetObj.getProperty('length');
    int len = _toLength(lengthValue);

    final argCount = elementsToAdd.length;

    const maxLength = 9007199254740991; // 2^53 - 1

    // Check if adding elements would exceed max length
    if (len + argCount > maxLength) {
      throw JSTypeError('Invalid array length');
    }

    // Even if argCount is 0, we still need to set length (to check if it's writable)
    if (argCount == 0) {
      _setPropertyStrict(targetObj, 'length', JSValueFactory.number(len));
      return JSValueFactory.number(len);
    }

    // Shift existing elements up by argCount
    // Start from the end to avoid overwriting
    for (int k = len - 1; k >= 0; k--) {
      final from = k.toString();
      final to = (k + argCount).toString();

      final fromValue = targetObj.getProperty(from);
      if (!fromValue.isUndefined || targetObj.hasProperty(from)) {
        _setPropertyStrict(targetObj, to, fromValue);
      } else {
        targetObj.deleteProperty(to);
      }
    }

    // Insert new elements at the beginning
    for (int j = 0; j < argCount; j++) {
      _setPropertyStrict(targetObj, j.toString(), elementsToAdd[j]);
    }

    // Update length (use strict mode)
    final newLen = len + argCount;
    _setPropertyStrict(targetObj, 'length', JSValueFactory.number(newLen));

    return JSValueFactory.number(newLen);
  }

  /// Array.prototype.slice(start?, end?)
  static JSValue slice(List<JSValue> args, JSArray arr) {
    final length = arr.length;
    var start = 0;
    var end = length;

    if (args.isNotEmpty) {
      final startNum = args[0].toNumber();
      if (!startNum.isNaN && !startNum.isInfinite) {
        start = startNum.truncate(); // ToInteger: truncate toward zero
      } else if (startNum.isNaN) {
        start = 0;
      } else if (startNum.isInfinite) {
        start = startNum > 0 ? length : 0;
      }
      if (start < 0) start = length + start;
      if (start < 0) start = 0;
      if (start > length) start = length;
    }

    if (args.length > 1) {
      final endNum = args[1].toNumber();
      if (!endNum.isNaN && !endNum.isInfinite) {
        end = endNum.truncate(); // ToInteger: truncate toward zero
      } else if (endNum.isNaN) {
        end = length;
      } else if (endNum.isInfinite) {
        end = endNum > 0 ? length : 0;
      }
      if (end < 0) end = length + end;
      if (end < 0) end = 0;
      if (end > length) end = length;
    }

    if (start >= end) {
      return JSValueFactory.array([]);
    }

    final result = arr.elements.sublist(start, end);
    return JSValueFactory.array(result);
  }

  /// Array.prototype.splice(start, deleteCount?, ...items)
  static JSValue splice(List<JSValue> args, JSArray arr) {
    final length = arr.length;

    if (args.isEmpty) {
      return JSValueFactory.array([]);
    }

    var start = toArrayIndex(args[0].toNumber());
    if (start < 0) start = length + start;
    if (start < 0) start = 0;
    if (start > length) start = length;

    var deleteCount = length - start;
    if (args.length > 1) {
      deleteCount = toArrayIndex(args[1].toNumber());
      if (deleteCount < 0) deleteCount = 0;
      if (deleteCount > length - start) deleteCount = length - start;
    }

    // Elements to remove
    final deleted = <JSValue>[];
    for (int i = 0; i < deleteCount; i++) {
      deleted.add(arr.elements.removeAt(start));
    }

    // Elements to insert
    if (args.length > 2) {
      final itemsToInsert = args.sublist(2);
      for (int i = 0; i < itemsToInsert.length; i++) {
        arr.elements.insert(start + i, itemsToInsert[i]);
      }
    }

    return JSValueFactory.array(deleted);
  }

  /// Array.prototype.join(separator?)
  static JSValue join(List<JSValue> args, JSArray arr) {
    final separator = args.isNotEmpty ? args[0] : JSValueFactory.string(',');

    final elements = <String>[];
    for (var i = 0; i < arr.length; i++) {
      final element = arr.getProperty(i.toString());
      // According to ECMAScript, undefined and null become empty strings
      if (element.isUndefined || element.isNull) {
        elements.add('');
      } else {
        elements.add(JSConversion.jsToString(element));
      }
    }
    return JSValueFactory.string(
      elements.join(JSConversion.jsToString(separator)),
    );
  }

  /// Array.prototype.toString()
  /// According to ES spec: If this doesn't have a callable join method, use Object.prototype.toString
  static JSValue toString_(List<JSValue> args, [JSArray? arr]) {
    // Determine the target object (this)
    JSValue thisValue;

    if (args.isNotEmpty) {
      // Called via .call(thisArg) - first argument is 'this'
      thisValue = args[0];
    } else if (arr != null) {
      // Appel direct sur un array
      thisValue = arr;
    } else {
      // Fallback: Object.prototype.toString behavior
      return _objectToString(JSValueFactory.undefined());
    }

    // If it's an array, call join directly
    if (thisValue is JSArray) {
      return join([], thisValue);
    }

    // Otherwise, check if thisValue has a callable join method
    if (thisValue is JSObject) {
      final joinMethod = thisValue.getProperty('join');
      if (joinMethod is JSFunction || joinMethod is JSNativeFunction) {
        // Call join() on this object
        // For now, fallback to Object.prototype.toString
        // because calling functions requires an evaluator
        return _objectToString(thisValue);
      }
    }

    // Pas de join callable: utiliser Object.prototype.toString
    return _objectToString(thisValue);
  }

  /// Helper to generate Object.prototype.toString result
  static JSValue _objectToString(JSValue value) {
    String tag;

    if (value.isUndefined) {
      tag = 'Undefined';
    } else if (value.isNull) {
      tag = 'Null';
    } else if (value is JSArray) {
      tag = 'Array';
    } else if (value is JSFunction || value is JSNativeFunction) {
      tag = 'Function';
    } else if (value.isBoolean) {
      tag = 'Boolean';
    } else if (value.isNumber) {
      tag = 'Number';
    } else if (value.isString) {
      tag = 'String';
    } else if (value is JSRegExp) {
      tag = 'RegExp';
    } else if (value is JSDate) {
      tag = 'Date';
    } else if (value is JSError) {
      tag = 'Error';
    } else if (value is JSMap) {
      tag = 'Map';
    } else if (value is JSSet) {
      tag = 'Set';
    } else if (value is JSObject) {
      // Check for Symbol.toStringTag
      final toStringTag = value.getProperty('Symbol.toStringTag');
      if (toStringTag.isString && toStringTag.toString().isNotEmpty) {
        tag = toStringTag.toString();
      } else {
        tag = 'Object';
      }
    } else {
      tag = 'Object';
    }

    return JSValueFactory.string('[object $tag]');
  }

  /// ToLength abstract operation (ES6 spec)
  /// Converts a value to an integer suitable for use as the length of an array-like object
  /// Propagates exceptions from ToPrimitive/ToNumber
  static int _toLength(JSValue value) {
    // ToNumber can throw if ToPrimitive fails
    final num = JSConversion.jsToNumber(value);

    // If ToNumber resulted in NaN, +0, or -0, return 0
    if (num.isNaN || num == 0) {
      return 0;
    }

    // If negative, return 0
    if (num < 0) {
      return 0;
    }

    // If greater than 2^53 - 1, return 2^53 - 1
    // 2^53 - 1 = 9007199254740991 (max safe integer in JavaScript)
    const maxLength = 9007199254740991;
    if (num.isInfinite || num > maxLength) {
      return maxLength;
    }

    // Return the integer part (truncate decimals)
    return num.floor().toInt();
  }

  /// Helper to check if a property can be written (ES spec Set operation)
  /// Throws TypeError if property is not writable
  static void _checkPropertyWritable(dynamic obj, String prop) {
    // Get property descriptor
    final descriptor = obj.getOwnPropertyDescriptor(prop);

    if (descriptor != null) {
      // Property exists - check if it's writable
      if (!descriptor.writable) {
        throw JSTypeError('Cannot assign to read only property \'$prop\'');
      }
    }

    // If property doesn't exist, check if object is extensible
  }

  /// Helper to safely set a property and throw TypeError if it fails
  /// This implements the ES spec Set(O, P, V, Throw=true)
  static void _setPropertyStrict(dynamic obj, String prop, JSValue value) {
    // Special handling for string objects - they have non-writable properties
    if (obj is JSStringObject) {
      if (prop == 'length' || int.tryParse(prop) != null) {
        throw JSTypeError('Cannot assign to read only property \'$prop\'');
      }
    }

    _checkPropertyWritable(obj, prop);
    obj.setProperty(prop, value);
  }

  /// Array.prototype.concat(...values)
  /// Supports array-like objects when called via .call()
  static JSValue concat(List<JSValue> args, [JSArray? arr]) {
    // Determine target object (this) and real arguments
    JSValue thisObj;
    List<JSValue> realArgs;

    // Check if called via .call() on Array.prototype
    final isCallOnPrototype =
        arr != null && identical(arr, JSArray.arrayPrototype);

    if (isCallOnPrototype && args.isNotEmpty) {
      // Called via .call(thisArg, ...) - first arg is 'this'
      thisObj = args[0];
      realArgs = args.length > 1 ? args.sublist(1) : [];
    } else if (arr != null && args.isNotEmpty && identical(args[0], arr)) {
      // Direct call on array - thisBinding was prepended so args[0] == arr
      // This is a duplicate, use arr as this and skip args[0]
      thisObj = arr;
      realArgs = args.sublist(1);
    } else if (arr != null) {
      // Direct call on array - no prepending happened (shouldn't occur with hasContextBound=false)
      thisObj = arr;
      realArgs = args;
    } else if (args.isNotEmpty) {
      // Fallback
      thisObj = args[0];
      realArgs = args.length > 1 ? args.sublist(1) : [];
    } else {
      return JSValueFactory.array([]);
    }

    final result = <JSValue>[];

    // Helper to check if a value should be spreadable
    bool isSpreadable(JSValue value) {
      // If value is not an object, it's not spreadable
      if (value is! JSObject) return false;

      // Check for Symbol.isConcatSpreadable property
      final spreadableSymbol = JSSymbol.isConcatSpreadable;
      final spreadableProp = value.getPropertyBySymbol(spreadableSymbol);

      // If Symbol.isConcatSpreadable is defined, use its value
      if (!spreadableProp.isUndefined) {
        return spreadableProp.toBoolean();
      }

      // Otherwise, spread if it's an Array
      return value is JSArray;
    }

    // Spread the 'this' object
    if (isSpreadable(thisObj)) {
      // Get the length property
      int length;
      if (thisObj is JSArray) {
        length = thisObj.length;
      } else if (thisObj is JSObject) {
        final lengthValue = thisObj.getProperty('length');
        length = _toLength(lengthValue);
      } else {
        length = 0;
      }

      // Spread elements by index
      for (var i = 0; i < length; i++) {
        final element = (thisObj as JSObject).getProperty(i.toString());
        result.add(element);
      }
    } else {
      result.add(thisObj);
    }

    // Add each argument
    for (final arg in realArgs) {
      if (isSpreadable(arg)) {
        // Get the length property
        final lengthValue = (arg as JSObject).getProperty('length');
        final length = _toLength(lengthValue);

        // Spread elements by index
        for (var i = 0; i < length; i++) {
          final element = arg.getProperty(i.toString());
          result.add(element);
        }
      } else {
        // Otherwise, add the element directly
        result.add(arg);
      }
    }

    return JSValueFactory.array(result);
  }

  /// Array.prototype.indexOf(searchElement, fromIndex?)
  /// Supports array-like objects when called via .call()
  static JSValue indexOf(List<JSValue> args, [JSArray? arr]) {
    // Determine target object (this) and real arguments
    JSValue thisObj;
    List<JSValue> realArgs;

    // Check if called via .call() on Array.prototype
    // In that case, arr will be Array.prototype and first arg is the real 'this' (passed via thisBindingMethods)
    final isCallOnPrototype =
        arr != null && identical(arr, JSArray.arrayPrototype);

    if (isCallOnPrototype && args.isNotEmpty) {
      // Called via .call(thisArg, ...) - first arg is 'this' (added by callWithThis)
      thisObj = args[0];
      realArgs = args.length > 1 ? args.sublist(1) : [];
    } else if (arr != null && args.isNotEmpty && identical(args[0], arr)) {
      // Direct call but thisBinding was prepended (arrayOnlyMethods)
      thisObj = arr;
      realArgs = args.sublist(1);
    } else if (arr != null) {
      // Direct call on array instance (arr is the bound context)
      thisObj = arr;
      realArgs = args;
    } else if (args.isNotEmpty) {
      // Fallback: first arg might be 'this'
      thisObj = args[0];
      realArgs = args.length > 1 ? args.sublist(1) : [];
    } else {
      return JSValueFactory.number(-1);
    }

    // ES spec: Throw TypeError if this is null or undefined
    if (thisObj.isNull || thisObj.isUndefined) {
      throw JSTypeError('Array.prototype.indexOf called on null or undefined');
    }

    // Convert primitives to objects (for string primitives, etc.)
    // But don't convert JSFunction - functions are already callable objects
    if (thisObj is! JSObject && thisObj is! JSFunction) {
      thisObj = thisObj.toObject();
    }

    // Get length from the object (works for array-like objects)
    // This MUST happen before checking arguments, as per ES spec
    // because getting length can throw (e.g., if length has invalid valueOf/toString)
    int len;
    if (thisObj is JSArray) {
      len = thisObj.length;
    } else if (thisObj is JSObject) {
      final lenVal = thisObj.getProperty('length');
      final lenNum = lenVal.toNumber();
      if (lenNum.isNaN || lenNum <= 0) {
        len = 0;
      } else if (lenNum.isInfinite || lenNum > 0x1FFFFFFFFFFFFF) {
        len = 0x1FFFFFFFFFFFFF; // 2^53 - 1
      } else {
        len = lenNum.floor().toInt();
      }
    } else if (thisObj is JSFunction) {
      final lenVal = thisObj.getProperty('length');
      final lenNum = lenVal.toNumber();
      if (lenNum.isNaN || lenNum <= 0) {
        len = 0;
      } else if (lenNum.isInfinite || lenNum > 0x1FFFFFFFFFFFFF) {
        len = 0x1FFFFFFFFFFFFF; // 2^53 - 1
      } else {
        len = lenNum.floor().toInt();
      }
    } else {
      len = 0;
    }

    // ES spec: If len is 0, return -1 (before processing fromIndex!)
    if (len == 0) {
      return JSValueFactory.number(-1);
    }

    // Get searchElement (defaults to undefined if not provided)
    final searchElement = realArgs.isEmpty
        ? JSValueFactory.undefined()
        : realArgs[0];

    var fromIndex = 0;
    if (realArgs.length > 1) {
      final fromArg = realArgs[1].toNumber();
      if (fromArg.isNaN) {
        fromIndex = 0;
      } else if (fromArg.isInfinite) {
        if (fromArg.isNegative) {
          fromIndex = 0;
        } else {
          return JSValueFactory.number(-1); // fromIndex >= len
        }
      } else {
        fromIndex = fromArg
            .truncate(); // ToInteger: truncate toward zero, not floor
        if (fromIndex < 0) {
          fromIndex = len + fromIndex;
          if (fromIndex < 0) fromIndex = 0;
        }
      }
    }

    // Search using Get(O, k) semantics with HasProperty (includes prototype chain per ES spec)
    for (int i = fromIndex; i < len; i++) {
      final kStr = i.toString();

      // ES spec: Use HasProperty which checks prototype chain
      // Support both JSObject and JSFunction (functions are callable objects)
      bool hasElement = false;
      if (thisObj is JSObject) {
        hasElement = thisObj.hasProperty(kStr);
      } else if (thisObj is JSFunction) {
        hasElement = thisObj.hasProperty(kStr);
      }

      if (!hasElement) {
        continue; // Skip holes and missing properties
      }

      // Get the element value (may come from prototype)
      JSValue element = JSValueFactory.undefined();
      if (thisObj is JSObject) {
        element = thisObj.getProperty(kStr);
      } else if (thisObj is JSFunction) {
        element = thisObj.getProperty(kStr);
      }

      if (element.strictEquals(searchElement)) {
        return JSValueFactory.number(i);
      }
    }

    return JSValueFactory.number(-1);
  }

  /// Array.prototype.lastIndexOf(searchElement, fromIndex?)
  /// Supports array-like objects when called via .call()
  static JSValue lastIndexOf(List<JSValue> args, [JSArray? arr]) {
    // Determine target object (this) and real arguments
    JSValue thisObj;
    List<JSValue> realArgs;

    // Check if called via .call() on Array.prototype
    final isCallOnPrototype =
        arr != null && identical(arr, JSArray.arrayPrototype);

    if (args.isNotEmpty && isCallOnPrototype) {
      // Called via .call(thisArg, ...) - first arg is 'this'
      thisObj = args[0];
      realArgs = args.length > 1 ? args.sublist(1) : [];
    } else if (arr != null && args.isNotEmpty && identical(args[0], arr)) {
      // Direct call but thisBinding was prepended
      thisObj = arr;
      realArgs = args.sublist(1);
    } else if (arr != null) {
      // Direct call on array
      thisObj = arr;
      realArgs = args;
    } else if (args.isNotEmpty) {
      // Called via .call without an arr context
      thisObj = args[0];
      realArgs = args.length > 1 ? args.sublist(1) : [];
    } else {
      return JSValueFactory.number(-1);
    }

    // ES spec: Throw TypeError if this is null or undefined
    if (thisObj.isNull || thisObj.isUndefined) {
      throw JSTypeError(
        'Array.prototype.lastIndexOf called on null or undefined',
      );
    }

    // Convert primitives to objects (for string primitives, etc.)
    // Note: JSFunction extends JSValue, not JSObject, but functions are objects
    if (thisObj is! JSObject && thisObj is! JSFunction) {
      thisObj = thisObj.toObject();
    }

    // Get length from the object (works for array-like objects)
    int len;
    if (thisObj is JSArray) {
      len = thisObj.length;
    } else if (thisObj is JSFunction) {
      final func = thisObj;
      final lenVal = func.getProperty('length');
      final lenNum = lenVal.toNumber();
      if (lenNum.isNaN || lenNum <= 0) {
        len = 0;
      } else if (lenNum.isInfinite || lenNum > 0x1FFFFFFFFFFFFF) {
        len = 0x1FFFFFFFFFFFFF; // 2^53 - 1
      } else {
        len = lenNum.floor().toInt();
      }
    } else if (thisObj is JSObject) {
      final lenVal = thisObj.getProperty('length');
      final lenNum = lenVal.toNumber();
      if (lenNum.isNaN || lenNum <= 0) {
        len = 0;
      } else if (lenNum.isInfinite || lenNum > 0x1FFFFFFFFFFFFF) {
        len = 0x1FFFFFFFFFFFFF; // 2^53 - 1
      } else {
        len = lenNum.floor().toInt();
      }
    } else {
      // Fallback - should not reach here after toObject conversion
      len = 0;
    }

    // ES spec: If len is 0, return -1
    if (len == 0) {
      return JSValueFactory.number(-1);
    }

    // Get searchElement (defaults to undefined if not provided)
    final searchElement = realArgs.isEmpty
        ? JSValueFactory.undefined()
        : realArgs[0];

    var fromIndex = len - 1;
    if (realArgs.length > 1) {
      final fromArg = realArgs[1].toNumber();
      if (fromArg.isNaN) {
        // ES spec: ToInteger(NaN) = 0, so fromIndex becomes 0
        // Then k = min(0, len-1) = 0, meaning only index 0 is searched
        fromIndex = 0;
      } else if (fromArg.isInfinite) {
        if (fromArg.isNegative) {
          return JSValueFactory.number(-1);
        } else {
          fromIndex = len - 1;
        }
      } else {
        fromIndex = fromArg.truncate(); // ToInteger: truncate toward zero
        if (fromIndex < 0) {
          fromIndex = len + fromIndex;
        }
        if (fromIndex >= len) fromIndex = len - 1;
      }
    }

    // Search backwards using Get(O, k) semantics
    for (int i = fromIndex; i >= 0; i--) {
      final kStr = i.toString();
      JSValue element;
      bool hasElement;

      if (thisObj is JSArray) {
        // ES spec: Use HasProperty (7.3.11) which checks prototype chain
        // This allows finding values from Array.prototype for array holes
        hasElement = thisObj.hasProperty(kStr);
        if (hasElement) {
          // Use getProperty to support accessor properties and prototype chain
          element = thisObj.getProperty(kStr);
        } else {
          continue;
        }
      } else if (thisObj is JSFunction) {
        // Functions are array-like objects - check for numeric properties
        hasElement = thisObj.hasProperty(kStr);
        if (hasElement) {
          element = thisObj.getProperty(kStr);
        } else {
          continue;
        }
      } else if (thisObj is JSObject) {
        hasElement = thisObj.hasProperty(kStr);
        if (hasElement) {
          element = thisObj.getProperty(kStr);
        } else {
          continue;
        }
      } else {
        continue;
      }

      if (element.strictEquals(searchElement)) {
        return JSValueFactory.number(i);
      }
    }

    return JSValueFactory.number(-1);
  }

  /// Array.prototype.includes(searchElement, fromIndex?)
  /// Utilise la comparaison SameValueZero (NaN === NaN est true)
  static JSValue includes(List<JSValue> args, [JSValue? defaultThis]) {
    // Get 'this' value - handle both normal calls and .call()
    JSValue thisValue;
    List<JSValue> realArgs;

    // When in arrayOnlyMethods with hasContextBound:false,
    // callWithThis ALWAYS prepends thisBinding to args.
    //
    // Normal call: [1,2,3].includes(2)
    //   -> callWithThis([2], [1,2,3]) prepends to [[1,2,3], 2]
    //   -> args[0] identical to defaultThis, skip args[0], use realArgs=[2]
    //
    // .call(): [].includes.call(obj, "tc39")
    //   -> callWithThis(["tc39"], obj) prepends to [obj, "tc39"]
    //   -> args[0] NOT identical to defaultThis, use args[0] as thisValue

    bool calledViaCallOrApply =
        defaultThis != null &&
        args.isNotEmpty &&
        args[0] is JSObject &&
        !identical(args[0], defaultThis);

    if (calledViaCallOrApply) {
      // Called via .call(obj, searchElement, fromIndex)
      thisValue = args[0];
      realArgs = args.length > 1 ? args.sublist(1) : [];
    } else if (defaultThis != null) {
      // Normal call: thisBinding was prepended, skip args[0]
      thisValue = defaultThis;
      realArgs = args.length > 1 ? args.sublist(1) : [];
    } else if (args.isNotEmpty) {
      // Fallback: use args[0] as thisValue
      thisValue = args[0];
      realArgs = args.length > 1 ? args.sublist(1) : [];
    } else {
      throw JSTypeError('Array.prototype.includes called on null or undefined');
    }

    // ES spec: Throw TypeError if this is null or undefined
    if (thisValue.isNull || thisValue.isUndefined) {
      throw JSTypeError('Array.prototype.includes called on null or undefined');
    }

    // Convert to object
    final thisObj = thisValue is JSObject ? thisValue : thisValue.toObject();

    // If no arguments, search for undefined
    final searchElement = realArgs.isNotEmpty
        ? realArgs[0]
        : JSValueFactory.undefined();

    // Get length from the object
    int len;
    if (thisObj is JSArray) {
      len = thisObj.length;
    } else {
      final lenVal = thisObj.getProperty('length');
      final lenNum = lenVal.toNumber();
      if (lenNum.isNaN || lenNum <= 0) {
        len = 0;
      } else if (lenNum.isInfinite || lenNum > 0x1FFFFFFFFFFFFF) {
        len = 0x1FFFFFFFFFFFFF; // 2^53 - 1
      } else {
        len = lenNum.floor().toInt();
      }
    }

    // ES spec: If len is 0, return false immediately without converting fromIndex
    if (len == 0) {
      return JSValueFactory.boolean(false);
    }

    var fromIndex = 0;
    if (realArgs.length > 1) {
      fromIndex = toArrayIndex(realArgs[1].toNumber());
      if (fromIndex < 0) {
        fromIndex = len + fromIndex;
        if (fromIndex < 0) fromIndex = 0;
      }
    }

    for (int i = fromIndex; i < len; i++) {
      // Use getProperty to support accessor properties
      final element = thisObj.getProperty(i.toString());
      // SameValueZero comparison: like strictEquals but NaN === NaN
      if (_sameValueZero(element, searchElement)) {
        return JSValueFactory.boolean(true);
      }
    }

    return JSValueFactory.boolean(false);
  }

  /// SameValueZero comparison algorithm (ES2016)
  /// Identical to strictEquals except NaN === NaN returns true
  static bool _sameValueZero(JSValue a, JSValue b) {
    // If both are numbers, check NaN
    if (a.isNumber && b.isNumber) {
      final aNum = a.toNumber();
      final bNum = b.toNumber();

      // NaN === NaN in SameValueZero (different from strictEquals)
      if (aNum.isNaN && bNum.isNaN) {
        return true;
      }

      // For other numbers, use normal equality
      return aNum == bNum;
    }

    // For other types, use strictEquals
    return a.strictEquals(b);
  }

  /// Array.prototype.reverse()
  /// Array.prototype.reverse()
  /// Generic method that works on array-like objects
  static JSValue reverse(List<JSValue> args, [JSValue? defaultThis]) {
    // Get 'this' value - handle both normal calls and .call()
    JSValue thisValue;

    // Detection: args[0] is an OBJECT and different from defaultThis
    bool calledViaCallOrApply =
        defaultThis != null &&
        args.isNotEmpty &&
        args[0] is JSObject &&
        !identical(args[0], defaultThis);

    if (calledViaCallOrApply) {
      // Called via .call(obj, ...)
      thisValue = args[0];
    } else if (defaultThis != null) {
      // Normal call: arr.reverse()
      thisValue = defaultThis;
    } else if (args.isNotEmpty) {
      // Fallback
      thisValue = args[0];
    } else {
      throw JSTypeError('Array.prototype.reverse called on null or undefined');
    }

    if (thisValue.isNull || thisValue.isUndefined) {
      throw JSTypeError('Array.prototype.reverse called on null or undefined');
    }

    // Convert to object
    final obj = thisValue is JSObject ? thisValue : thisValue.toObject();

    // Get length
    final len = _getLength(obj);

    // Reverse by swapping elements from both ends
    final middle = (len / 2).floor();
    int lower = 0;

    // Fast path for JSArray - but need to check for holes and prototype chain
    if (obj is JSArray) {
      while (lower != middle) {
        final upper = len - lower - 1;
        final lowerKey = lower.toString();
        final upperKey = upper.toString();

        // ES spec order is important - getter at lowerKey might modify the array
        // Step 7d: Let lowerExists = HasProperty(O, lowerP)
        final lowerExists = obj.hasProperty(lowerKey);

        // Step 7f: If lowerExists, let lowerValue = Get(O, lowerP)
        // This might trigger a getter that modifies the array (e.g., sets length = 0)
        JSValue? lowerValue;
        if (lowerExists) {
          lowerValue = obj.getProperty(lowerKey);
        }

        // Step 7g: Let upperExists = HasProperty(O, upperP)
        // Check AFTER getting lowerValue, as the array might have changed
        final upperExists = obj.hasProperty(upperKey);

        // Step 7i: If upperExists, let upperValue = Get(O, upperP)
        JSValue? upperValue;
        if (upperExists) {
          upperValue = obj.getProperty(upperKey);
        }

        // Swap based on which properties exist
        // Step 7j-m
        if (lowerExists && upperExists) {
          // Both exist - swap them
          // Note: If set fails (e.g., getter-only), this throws
          // which is correct per spec (Set with Throw = true)
          obj.setProperty(lowerKey, upperValue!);
          obj.setProperty(upperKey, lowerValue!);
        } else if (!lowerExists && upperExists) {
          // Only upper exists - move it to lower and delete upper
          obj.setProperty(lowerKey, upperValue!);
          obj.deleteProperty(upperKey);
        } else if (lowerExists && !upperExists) {
          // Only lower exists - move it to upper and delete lower
          obj.setProperty(upperKey, lowerValue!);
          obj.deleteProperty(lowerKey);
        }
        // If both don't exist, do nothing

        lower++;
      }
    } else {
      // Generic path for array-like objects
      while (lower != middle) {
        final upper = len - lower - 1;
        final lowerKey = lower.toString();
        final upperKey = upper.toString();

        // Get both values and check if properties exist
        final lowerValue = obj.getProperty(lowerKey);
        final upperValue = obj.getProperty(upperKey);
        final lowerExists = obj.hasProperty(lowerKey);
        final upperExists = obj.hasProperty(upperKey);

        // Swap based on which properties exist
        if (lowerExists && upperExists) {
          obj.setProperty(lowerKey, upperValue);
          obj.setProperty(upperKey, lowerValue);
        } else if (!lowerExists && upperExists) {
          obj.setProperty(lowerKey, upperValue);
          obj.deleteProperty(upperKey);
        } else if (lowerExists && !upperExists) {
          obj.setProperty(upperKey, lowerValue);
          obj.deleteProperty(lowerKey);
        }
        // If both don't exist, do nothing

        lower++;
      }
    }

    return obj;
  }

  /// Array.prototype.sort(compareFn?)
  static JSValue sort(List<JSValue> args, JSArray arr) {
    if (args.isEmpty) {
      // Alphabetical sort by default
      arr.elements.sort((a, b) {
        final aStr = JSConversion.jsToString(a);
        final bStr = JSConversion.jsToString(b);
        return aStr.compareTo(bStr);
      });
      return arr;
    }

    // Check if a compareFn is provided
    final compareFn = args[0];
    if (!compareFn.isFunction) {
      // If it's not a function, use default sort
      arr.elements.sort((a, b) {
        final aStr = JSConversion.jsToString(a);
        final bStr = JSConversion.jsToString(b);
        return aStr.compareTo(bStr);
      });
      return arr;
    }

    // Use the custom comparison function
    final evaluator = JSEvaluator.currentInstance;
    if (evaluator == null) {
      throw JSError('No evaluator available for function execution');
    }

    arr.elements.sort((a, b) {
      try {
        // Appeler compareFn(a, b)
        final result = evaluator.callFunction(compareFn, [a, b]);

        // The result must be a number
        if (result.isNumber) {
          final comparison = result.toNumber();
          if (comparison < 0) return -1;
          if (comparison > 0) return 1;
          return 0;
        }

        // If it's not a number, convert to number
        final comparison = result.toNumber();
        if (comparison.isNaN) return 0;
        if (comparison < 0) return -1;
        if (comparison > 0) return 1;
        return 0;
      } catch (e) {
        // On error, use default sort
        final aStr = JSConversion.jsToString(a);
        final bStr = JSConversion.jsToString(b);
        return aStr.compareTo(bStr);
      }
    });

    return arr;
  }

  /// Array.prototype.forEach(callback, thisArg?)
  /// When called via .call(), first arg is 'this' (array-like object)
  static JSValue forEach(List<JSValue> args, [JSValue? defaultThis]) {
    // Get 'this' value - could be array-like object when called via .call()
    JSValue thisValue;
    List<JSValue> restArgs;

    // Detect if called via .call(thisArg, callback, ...)
    // When called via .call(), callWithThis prepends thisArg to args
    // Special case: forEach.call(functionObj, callback) where functionObj is a JSFunction
    bool calledViaCall =
        args.isNotEmpty &&
        (!args[0].isFunction ||
            (args[0].isFunction && args.length > 1 && args[1].isFunction)) &&
        (args[0] is JSArray ||
            args[0] is JSObject ||
            args[0] is JSFunction ||
            args[0] is JSNativeFunction ||
            args[0].isNull ||
            args[0].isUndefined ||
            args[0].isBoolean ||
            args[0].isString ||
            args[0].isNumber);

    if (calledViaCall) {
      final first = args[0];
      // Check if first arg is null or undefined - must throw TypeError
      if (first.isNull || first.isUndefined) {
        throw JSTypeError(
          'Array.prototype.forEach called on null or undefined',
        );
      }
      thisValue = first;
      restArgs = args.length > 1 ? args.sublist(1) : [];
    } else if (defaultThis != null) {
      thisValue = defaultThis;
      restArgs = args;
    } else {
      throw JSTypeError('Array.prototype.forEach called on null or undefined');
    }

    // Convert to object first so we can get the length property from its prototype chain
    final thisObj = thisValue is JSObject ? thisValue : thisValue.toObject();

    // ES6 spec: Get length at the start (step 3)
    // Handle NaN and Infinity properly using helper
    // NOTE: This is done BEFORE checking callback to trigger side effects
    final len = _getLength(thisObj);

    // NOW check if callback is valid
    if (restArgs.isEmpty || !restArgs[0].isFunction) {
      throw JSTypeError(
        'Array.prototype.forEach: callback is ${restArgs.isEmpty ? "missing" : restArgs[0].type}',
      );
    }

    final callback = restArgs[0];
    final thisArg = restArgs.length > 1
        ? restArgs[1]
        : JSValueFactory.undefined();

    // ES6 spec: Iterate using HasProperty and Get at each step (step 7)
    // This ensures deleted elements are not visited
    for (int i = 0; i < len; i++) {
      final key = i.toString();

      // Check if property exists at THIS iteration point (not before)
      bool hasProperty = false;
      if (thisObj is JSArray) {
        // For JSArray, check if index is valid and not a hole
        if (i < thisObj.elements.length && !thisObj.elements[i].isUndefined) {
          hasProperty = true;
        } else if (thisObj.hasOwnProperty(key)) {
          hasProperty = true;
        } else {
          hasProperty = _hasInPrototypeChain(thisObj, key);
        }
      } else {
        // For objects, check hasOwnProperty or prototype chain
        hasProperty =
            thisObj.hasOwnProperty(key) || _hasInPrototypeChain(thisObj, key);
      }

      if (hasProperty) {
        // Get the value dynamically at each iteration
        final element = thisObj.getProperty(key);

        // After getting the property (which may have side effects like deleting other properties),
        // re-check if this property still exists
        bool stillHasProperty = false;
        if (thisObj is JSArray) {
          // For JSArray, re-check if index is valid and not a hole
          if (i < thisObj.elements.length && !thisObj.elements[i].isUndefined) {
            stillHasProperty = true;
          } else if (thisObj.hasOwnProperty(key)) {
            stillHasProperty = true;
          } else {
            stillHasProperty = _hasInPrototypeChain(thisObj, key);
          }
        } else {
          // For objects, re-check
          stillHasProperty =
              thisObj.hasOwnProperty(key) || _hasInPrototypeChain(thisObj, key);
        }

        // Only call callback if property still exists after getting it
        if (stillHasProperty) {
          // callback(element, index, array)
          final callbackArgs = [element, JSValueFactory.number(i), thisObj];
          _callFunction(callback, callbackArgs, thisArg);
        }
      }
    }

    return JSValueFactory.undefined();
  }

  /// Array.prototype.map(callback, thisArg?)
  /// When called via .call(), first arg is 'this' (array-like object)
  static JSValue map(List<JSValue> args, [JSValue? defaultThis]) {
    // Get 'this' value - could be array-like object when called via .call()
    JSValue thisValue;
    List<JSValue> restArgs;

    // Detect if called via .call(thisArg, callback, ...)
    // We detect this by checking if first arg is NOT a function
    bool calledViaCall =
        args.isNotEmpty &&
        !args[0].isFunction &&
        (args[0] is JSArray ||
            args[0] is JSObject ||
            args[0].isNull ||
            args[0].isUndefined ||
            args[0].isBoolean ||
            args[0].isString ||
            args[0].isNumber);

    if (calledViaCall) {
      final first = args[0];
      if (first.isNull || first.isUndefined) {
        throw JSTypeError('Array.prototype.map called on null or undefined');
      }
      thisValue = first;
      restArgs = args.length > 1 ? args.sublist(1) : [];
    } else if (defaultThis != null) {
      thisValue = defaultThis;
      restArgs = args;
    } else {
      throw JSTypeError('Array.prototype.map called on null or undefined');
    }

    final thisObj = thisValue is JSObject ? thisValue : thisValue.toObject();

    // Get length BEFORE validating callback (ES6 spec order)
    final len = _getLength(thisObj);

    if (restArgs.isEmpty || !restArgs[0].isFunction) {
      throw JSTypeError(
        'Array.prototype.map: callback is ${restArgs.isEmpty ? "missing" : restArgs[0].type}',
      );
    }

    final callback = restArgs[0];
    final thisArg = restArgs.length > 1
        ? restArgs[1]
        : JSValueFactory.undefined();
    final result = <JSValue>[];

    for (int i = 0; i < len; i++) {
      // Check if this index is a hole (for JSArray)
      bool isHole = false;
      if (thisObj is JSArray) {
        isHole = thisObj.isHole(i);
      } else {
        // For other objects, check if property has the value via HasProperty
        // If property exists, we map it; if not, it's a "hole"
        if (!thisObj.hasProperty(i.toString())) {
          isHole = true;
        }
      }

      if (isHole) {
        // Preserve holes by adding undefined or creating a hole
        // ES2020: map() preserves holes by not calling callback for holes
        // but still adds undefined to the result array
        result.add(JSValueFactory.undefined());
      } else {
        // Use proper Get() semantics - triggers accessors
        final element = thisObj.getProperty(i.toString());
        // callback(element, index, array)
        final callbackArgs = [element, JSValueFactory.number(i), thisObj];
        final mapped = _callFunction(callback, callbackArgs, thisArg);
        result.add(mapped);
      }
    }

    return JSValueFactory.array(result);
  }

  /// Array.prototype.filter(callback, thisArg?)
  /// When called via .call(), first arg is 'this' (array-like object)
  static JSValue filter(List<JSValue> args, [JSValue? defaultThis]) {
    // Get 'this' value - could be array-like object when called via .call()
    JSValue thisValue;
    List<JSValue> restArgs;

    // Detect if called via .call(thisArg, callback, ...)
    bool calledViaCall =
        args.isNotEmpty &&
        !args[0].isFunction &&
        (args[0] is JSArray ||
            args[0] is JSObject ||
            args[0].isNull ||
            args[0].isUndefined ||
            args[0].isBoolean ||
            args[0].isString ||
            args[0].isNumber);

    if (calledViaCall) {
      final first = args[0];
      if (first.isNull || first.isUndefined) {
        throw JSTypeError('Array.prototype.filter called on null or undefined');
      }
      thisValue = first;
      restArgs = args.length > 1 ? args.sublist(1) : [];
    } else if (defaultThis != null) {
      thisValue = defaultThis;
      restArgs = args;
    } else {
      throw JSTypeError('Array.prototype.filter called on null or undefined');
    }

    // Convert to object first so we can get the length property from its prototype chain
    final thisObj = thisValue is JSObject ? thisValue : thisValue.toObject();

    // Get length FIRST (before validating callback) - ES6 spec order
    // This allows side effects in length getter to occur before validation
    final len = _getLength(thisObj);

    // NOW validate callback - after length access
    if (restArgs.isEmpty || !restArgs[0].isFunction) {
      throw JSTypeError(
        'Array.prototype.filter: callback is ${restArgs.isEmpty ? "missing" : restArgs[0].type}',
      );
    }

    final callback = restArgs[0];
    final thisArg = restArgs.length > 1
        ? restArgs[1]
        : JSValueFactory.undefined();

    final result = <JSValue>[];

    for (int i = 0; i < len; i++) {
      // Check if this index is a hole (for JSArray)
      bool isHole = false;
      if (thisObj is JSArray) {
        isHole = thisObj.isHole(i);
      } else {
        // For other objects, check if property exists
        if (!thisObj.hasProperty(i.toString())) {
          isHole = true;
        }
      }

      if (!isHole) {
        // Use proper Get() semantics - triggers accessors
        final element = thisObj.getProperty(i.toString());
        // callback(element, index, array)
        final callbackArgs = [element, JSValueFactory.number(i), thisObj];
        final shouldInclude = _callFunction(callback, callbackArgs, thisArg);
        if (shouldInclude.toBoolean()) {
          result.add(element);
        }
      }
      // Holes are skipped - not added to result
    }

    return JSValueFactory.array(result);
  }

  /// Array.prototype.find(callback, thisArg?)
  /// When called via .call(), first arg is 'this' (array-like object)
  static JSValue find(List<JSValue> args, [JSValue? defaultThis]) {
    // Get 'this' value - could be array-like object when called via .call()
    JSValue thisValue;
    List<JSValue> restArgs;

    // Detect if called via .call(thisArg, callback, ...)
    bool calledViaCall =
        args.isNotEmpty &&
        !args[0].isFunction &&
        (args[0] is JSArray ||
            args[0] is JSObject ||
            args[0].isNull ||
            args[0].isUndefined ||
            args[0].isBoolean ||
            args[0].isString ||
            args[0].isNumber);

    if (calledViaCall) {
      final first = args[0];
      if (first.isNull || first.isUndefined) {
        throw JSTypeError('Array.prototype.find called on null or undefined');
      }
      thisValue = first;
      restArgs = args.length > 1 ? args.sublist(1) : [];
    } else if (defaultThis != null) {
      thisValue = defaultThis;
      restArgs = args;
    } else {
      throw JSTypeError('Array.prototype.find called on null or undefined');
    }

    // Capture length FIRST (can have side effects)
    // Per ES6 spec: length is captured before callback validation
    final thisObj = thisValue is JSObject ? thisValue : thisValue.toObject();
    final len = _getLength(thisObj);

    // NOW validate callback - after length access
    if (restArgs.isEmpty || !restArgs[0].isFunction) {
      throw JSTypeError(
        'Array.prototype.find: callback is ${restArgs.isEmpty ? "missing" : restArgs[0].type}',
      );
    }

    final callback = restArgs[0];
    final thisArg = restArgs.length > 1
        ? restArgs[1]
        : JSValueFactory.undefined();

    // Iterate up to the captured length, accessing elements during iteration
    // This allows the callback to modify the array
    for (int i = 0; i < len; i++) {
      // Access element at index i (may not exist if array was modified)
      final element = thisObj.getProperty(i.toString());

      // callback(element, index, array)
      final callbackArgs = [element, JSValueFactory.number(i), thisObj];
      final found = _callFunction(callback, callbackArgs, thisArg);
      if (found.toBoolean()) {
        return element;
      }
    }

    return JSValueFactory.undefined();
  }

  /// Array.prototype.findIndex(callback, thisArg?)
  /// When called via .call(), first arg is 'this' (array-like object)
  static JSValue findIndex(List<JSValue> args, [JSValue? defaultThis]) {
    // Get 'this' value - could be array-like object when called via .call()
    JSValue thisValue;
    List<JSValue> restArgs;

    // Detect if called via .call(thisArg, callback, ...)
    bool calledViaCall =
        args.isNotEmpty &&
        !args[0].isFunction &&
        (args[0] is JSArray ||
            args[0] is JSObject ||
            args[0].isNull ||
            args[0].isUndefined ||
            args[0].isBoolean ||
            args[0].isString ||
            args[0].isNumber);

    if (calledViaCall) {
      final first = args[0];
      if (first.isNull || first.isUndefined) {
        throw JSTypeError(
          'Array.prototype.findIndex called on null or undefined',
        );
      }
      thisValue = first;
      restArgs = args.length > 1 ? args.sublist(1) : [];
    } else if (defaultThis != null) {
      thisValue = defaultThis;
      restArgs = args;
    } else {
      throw JSTypeError(
        'Array.prototype.findIndex called on null or undefined',
      );
    }

    // Capture length FIRST (can have side effects)
    // Per ES6 spec: length is captured before callback validation
    final thisObj = thisValue is JSObject ? thisValue : thisValue.toObject();
    final len = _getLength(thisObj);

    // NOW validate callback - after length access
    if (restArgs.isEmpty || !restArgs[0].isFunction) {
      throw JSTypeError(
        'Array.prototype.findIndex: callback is ${restArgs.isEmpty ? "missing" : restArgs[0].type}',
      );
    }

    final callback = restArgs[0];
    final thisArg = restArgs.length > 1
        ? restArgs[1]
        : JSValueFactory.undefined();

    // Iterate up to the captured length, accessing elements during iteration
    for (int i = 0; i < len; i++) {
      // Access element at index i (may not exist if array was modified)
      final element = thisObj.getProperty(i.toString());

      // callback(element, index, array)
      final callbackArgs = [element, JSValueFactory.number(i), thisObj];
      final found = _callFunction(callback, callbackArgs, thisArg);
      if (found.toBoolean()) {
        return JSValueFactory.number(i);
      }
    }

    return JSValueFactory.number(-1);
  }

  /// Array.prototype.findLast(callback, thisArg?) - ES2023
  /// Finds the last element that satisfies the predicate, iterating from end to start
  static JSValue findLast(List<JSValue> args, JSArray arr) {
    if (args.isEmpty || !args[0].isFunction) {
      throw JSTypeError(
        'Array.prototype.findLast: callback is ${args.isEmpty ? "missing" : args[0].type}',
      );
    }

    final callback = args[0];
    final thisArg = args.length > 1 ? args[1] : JSValueFactory.undefined();

    // Iterate from the end to the start
    for (int i = arr.elements.length - 1; i >= 0; i--) {
      // callback(element, index, array)
      final callbackArgs = [arr.elements[i], JSValueFactory.number(i), arr];

      final found = _callFunction(callback, callbackArgs, thisArg);
      if (found.toBoolean()) {
        return arr.elements[i];
      }
    }

    return JSValueFactory.undefined();
  }

  /// Array.prototype.findLastIndex(callback, thisArg?) - ES2023
  /// Finds the last index that satisfies the predicate, iterating from end to start
  /// Returns -1 if not found
  static JSValue findLastIndex(List<JSValue> args, JSArray arr) {
    if (args.isEmpty || !args[0].isFunction) {
      throw JSTypeError(
        'Array.prototype.findLastIndex: callback is ${args.isEmpty ? "missing" : args[0].type}',
      );
    }

    final callback = args[0];
    final thisArg = args.length > 1 ? args[1] : JSValueFactory.undefined();

    // Iterate from the end to the start
    for (int i = arr.elements.length - 1; i >= 0; i--) {
      // callback(element, index, array)
      final callbackArgs = [arr.elements[i], JSValueFactory.number(i), arr];

      final found = _callFunction(callback, callbackArgs, thisArg);
      if (found.toBoolean()) {
        return JSValueFactory.number(i);
      }
    }

    return JSValueFactory.number(-1);
  }

  /// Array.prototype.reduce(callback, initialValue?)
  /// When called via .call(), first arg is 'this' (array-like object)
  static JSValue reduce(List<JSValue> args, [JSValue? defaultThis]) {
    // Get 'this' value - could be array-like object when called via .call()
    JSValue thisValue;
    List<JSValue> restArgs;

    // Detect if called via .call(thisArg, callback, initialValue?)
    // We detect this by checking if first arg is NOT a function
    bool calledViaCall =
        args.isNotEmpty &&
        !args[0].isFunction &&
        (args[0] is JSArray ||
            args[0] is JSObject ||
            args[0].isNull ||
            args[0].isUndefined ||
            args[0].isBoolean ||
            args[0].isString ||
            args[0].isNumber);

    if (calledViaCall) {
      final first = args[0];
      if (first.isNull || first.isUndefined) {
        throw JSTypeError('Array.prototype.reduce called on null or undefined');
      }
      thisValue = first;
      restArgs = args.length > 1 ? args.sublist(1) : [];
    } else if (defaultThis != null) {
      thisValue = defaultThis;
      restArgs = args;
    } else {
      throw JSTypeError('Array.prototype.reduce called on null or undefined');
    }

    // Get elements from array-like object FIRST (accesses length, can have side effects)
    // This must happen before callback validation per ES6 spec
    final elements = _toArrayLikeElements(thisValue);
    final thisObj = thisValue is JSObject ? thisValue : thisValue.toObject();

    // NOW validate callback - after length access
    if (restArgs.isEmpty || !restArgs[0].isFunction) {
      throw JSTypeError(
        'Array.prototype.reduce: callback is ${restArgs.isEmpty ? "missing" : restArgs[0].type}',
      );
    }

    if (elements.isEmpty && restArgs.length < 2) {
      throw JSTypeError('Reduce of empty array with no initial value');
    }

    final callback = restArgs[0];
    var accumulator = restArgs.length > 1 ? restArgs[1] : elements[0];
    final startIndex = restArgs.length > 1 ? 0 : 1;

    for (int i = startIndex; i < elements.length; i++) {
      // callback(accumulator, currentValue, index, array)
      final callbackArgs = [
        accumulator,
        elements[i],
        JSValueFactory.number(i),
        thisObj,
      ];

      accumulator = _callFunction(
        callback,
        callbackArgs,
        JSValueFactory.undefined(),
      );
    }

    return accumulator;
  }

  /// Array.prototype.some(callback, thisArg?)
  /// When called via .call(), first arg is 'this' (array-like object)
  static JSValue some(List<JSValue> args, [JSValue? defaultThis]) {
    // Get 'this' value - could be array-like object when called via .call()
    JSValue thisValue;
    List<JSValue> restArgs;

    // Detect if called via .call(thisArg, callback, ...)
    bool calledViaCall =
        args.isNotEmpty &&
        !args[0].isFunction &&
        (args[0] is JSArray ||
            args[0] is JSObject ||
            args[0].isNull ||
            args[0].isUndefined ||
            args[0].isBoolean ||
            args[0].isString ||
            args[0].isNumber);

    if (calledViaCall) {
      final first = args[0];
      if (first.isNull || first.isUndefined) {
        throw JSTypeError('Array.prototype.some called on null or undefined');
      }
      thisValue = first;
      restArgs = args.length > 1 ? args.sublist(1) : [];
    } else if (defaultThis != null) {
      thisValue = defaultThis;
      restArgs = args;
    } else {
      throw JSTypeError('Array.prototype.some called on null or undefined');
    }

    // Get elements from array-like object FIRST (accesses length, can have side effects)
    // This must happen before callback validation per ES6 spec
    final elements = _toArrayLikeElements(thisValue);
    final thisObj = thisValue is JSObject ? thisValue : thisValue.toObject();

    // NOW validate callback - after length access
    if (restArgs.isEmpty || !restArgs[0].isFunction) {
      throw JSTypeError(
        'Array.prototype.some: callback is ${restArgs.isEmpty ? "missing" : restArgs[0].type}',
      );
    }

    final callback = restArgs[0];
    final thisArg = restArgs.length > 1
        ? restArgs[1]
        : JSValueFactory.undefined();

    for (int i = 0; i < elements.length; i++) {
      // callback(element, index, array)
      final callbackArgs = [elements[i], JSValueFactory.number(i), thisObj];
      final result = _callFunction(callback, callbackArgs, thisArg);
      if (result.toBoolean()) {
        return JSValueFactory.boolean(true);
      }
    }
    return JSValueFactory.boolean(false);
  }

  /// Array.prototype.every(callback, thisArg?)
  /// When called via .call(), first arg is 'this' (array-like object)
  static JSValue every(List<JSValue> args, [JSValue? defaultThis]) {
    // Get 'this' value - could be array-like object when called via .call()
    JSValue thisValue;
    List<JSValue> restArgs;

    // Detect if called via .call(thisArg, callback, ...)
    bool calledViaCall =
        args.isNotEmpty &&
        !args[0].isFunction &&
        (args[0] is JSArray ||
            args[0] is JSObject ||
            args[0].isNull ||
            args[0].isUndefined ||
            args[0].isBoolean ||
            args[0].isString ||
            args[0].isNumber);

    if (calledViaCall) {
      final first = args[0];
      if (first.isNull || first.isUndefined) {
        throw JSTypeError('Array.prototype.every called on null or undefined');
      }
      thisValue = first;
      restArgs = args.length > 1 ? args.sublist(1) : [];
    } else if (defaultThis != null) {
      thisValue = defaultThis;
      restArgs = args;
    } else {
      throw JSTypeError('Array.prototype.every called on null or undefined');
    }

    // Convert to object first so we can get the length property from its prototype chain
    final thisObj = thisValue is JSObject ? thisValue : thisValue.toObject();

    // Get length FIRST (before validating callback) - ES6 spec order
    // This allows side effects in length getter to occur before validation
    final len = _getLength(thisObj);

    // NOW validate callback - after length access
    if (restArgs.isEmpty || !restArgs[0].isFunction) {
      throw JSTypeError(
        'Array.prototype.every: callback is ${restArgs.isEmpty ? "missing" : restArgs[0].type}',
      );
    }

    final callback = restArgs[0];
    final thisArg = restArgs.length > 1
        ? restArgs[1]
        : JSValueFactory.undefined();

    // ES6 spec: Use HasProperty (checks prototype chain) and Get for each index
    for (int i = 0; i < len; i++) {
      final key = i.toString();
      // HasProperty check - includes prototype chain
      bool hasProperty = false;
      if (thisObj is JSArray) {
        // For arrays, check own property or prototype
        hasProperty =
            (i < thisObj.elements.length && !thisObj.isHole(i)) ||
            thisObj.hasOwnProperty(key) ||
            _hasInPrototypeChain(thisObj, key);
      } else {
        hasProperty =
            thisObj.hasOwnProperty(key) || _hasInPrototypeChain(thisObj, key);
      }

      if (hasProperty) {
        // Get value (will check prototype chain automatically)
        final element = thisObj.getProperty(key);
        // callback(element, index, array)
        final callbackArgs = [element, JSValueFactory.number(i), thisObj];
        final result = _callFunction(callback, callbackArgs, thisArg);
        if (!result.toBoolean()) {
          return JSValueFactory.boolean(false);
        }
      }
    }

    return JSValueFactory.boolean(true);
  }

  /// Array.prototype.reduceRight(callback, initialValue?)
  /// When called via .call(), first arg is 'this' (array-like object)
  static JSValue reduceRight(List<JSValue> args, [JSValue? defaultThis]) {
    // Get 'this' value - could be array-like object when called via .call()
    JSValue thisValue;
    List<JSValue> restArgs;

    // Detect if called via .call(thisArg, callback, initialValue?)
    bool calledViaCall =
        args.isNotEmpty &&
        !args[0].isFunction &&
        (args[0] is JSArray ||
            args[0] is JSObject ||
            args[0].isNull ||
            args[0].isUndefined ||
            args[0].isBoolean ||
            args[0].isString ||
            args[0].isNumber);

    if (calledViaCall) {
      final first = args[0];
      if (first.isNull || first.isUndefined) {
        throw JSTypeError(
          'Array.prototype.reduceRight called on null or undefined',
        );
      }
      thisValue = first;
      restArgs = args.length > 1 ? args.sublist(1) : [];
    } else if (defaultThis != null) {
      thisValue = defaultThis;
      restArgs = args;
    } else {
      throw JSTypeError(
        'Array.prototype.reduceRight called on null or undefined',
      );
    }

    // Get elements from array-like object FIRST (accesses length, can have side effects)
    // This must happen before callback validation per ES6 spec
    final elements = _toArrayLikeElements(thisValue);
    final thisObj = thisValue is JSObject ? thisValue : thisValue.toObject();

    // NOW validate callback - after length access
    if (restArgs.isEmpty || !restArgs[0].isFunction) {
      throw JSTypeError(
        'Array.prototype.reduceRight: callback is ${restArgs.isEmpty ? "missing" : restArgs[0].type}',
      );
    }

    if (elements.isEmpty && restArgs.length < 2) {
      throw JSTypeError('Reduce of empty array with no initial value');
    }

    final callback = restArgs[0];
    var accumulator = restArgs.length > 1
        ? restArgs[1]
        : elements[elements.length - 1];
    final startIndex = restArgs.length > 1
        ? elements.length - 1
        : elements.length - 2;

    for (int i = startIndex; i >= 0; i--) {
      // callback(accumulator, currentValue, index, array)
      final callbackArgs = [
        accumulator,
        elements[i],
        JSValueFactory.number(i),
        thisObj,
      ];

      accumulator = _callFunction(
        callback,
        callbackArgs,
        JSValueFactory.undefined(),
      );
    }

    return accumulator;
  }

  /// Array.prototype.at(index)
  /// Supports array-like objects when called via .call()
  static JSValue at(List<JSValue> args, [JSArray? arr]) {
    // Determine target object (this) and real arguments
    JSValue thisObj;
    List<JSValue> realArgs;

    // Check if called via .call() on Array.prototype
    final isCallOnPrototype =
        arr != null && identical(arr, JSArray.arrayPrototype);

    if (isCallOnPrototype && args.isNotEmpty) {
      // Called via .call(thisArg, ...) - first arg is 'this'
      thisObj = args[0];
      realArgs = args.length > 1 ? args.sublist(1) : [];
    } else if (arr != null && args.isNotEmpty && identical(args[0], arr)) {
      // Direct call on array instance - thisBinding was prepended
      // Since 'at' is in arrayOnlyMethods, the system prepends the array itself
      // So args = [array, index, ...] and arr = array
      thisObj = arr;
      realArgs = args.sublist(1);
    } else if (arr != null) {
      // Direct call without thisBinding prepending (shouldn't happen normally)
      thisObj = arr;
      realArgs = args;
    } else if (args.isNotEmpty) {
      // Fallback
      thisObj = args[0];
      realArgs = args.length > 1 ? args.sublist(1) : [];
    } else {
      return JSValueFactory.undefined();
    }

    // ES2022: ToObject(this) - throw TypeError for null/undefined
    if (thisObj.isNull || thisObj.isUndefined) {
      throw JSTypeError('Array.prototype.at called on null or undefined');
    }

    // ES2022: If no argument, treat as at(undefined) which converts to 0
    final indexValue = realArgs.isEmpty
        ? JSValueFactory.undefined()
        : realArgs[0];

    // ES2022: ToInteger(index) - converts to number via ToPrimitive and ToNumber
    final numericIndex = JSConversion.jsToNumber(indexValue);

    // ToInteger: truncate towards zero
    final index = numericIndex.isNaN ? 0 : numericIndex.truncate();

    // Get length from the object
    int len;
    if (thisObj is JSArray) {
      len = thisObj.length;
    } else if (thisObj is JSObject) {
      final lenVal = thisObj.getProperty('length');
      len = _toLength(lenVal);
    } else {
      len = 0;
    }

    final normalizedIndex = index < 0 ? len + index : index;

    if (normalizedIndex < 0 || normalizedIndex >= len) {
      return JSValueFactory.undefined();
    }

    // Get element from object
    if (thisObj is JSArray) {
      return thisObj.elements[normalizedIndex];
    } else if (thisObj is JSObject) {
      return thisObj.getProperty(normalizedIndex.toString());
    } else {
      return JSValueFactory.undefined();
    }
  }

  /// Array.prototype.entries()
  /// Returns an iterator over [index, value] pairs
  static JSValue entries(List<JSValue> args, JSArray arr) {
    return JSArrayIterator(arr, IteratorKind.entries);
  }

  /// Array.prototype.keys()
  /// Returns an iterator over indices
  static JSValue keys(List<JSValue> args, JSArray arr) {
    return JSArrayIterator(arr, IteratorKind.keys);
  }

  /// Array.prototype.values()
  /// Returns an iterator over values
  static JSValue values(List<JSValue> args, JSArray arr) {
    return JSArrayIterator(arr, IteratorKind.valueKind);
  }

  /// Array.prototype.fill(value[, start[, end]])
  /// Fills all elements of an array with a static value
  static JSValue fill(List<JSValue> args, [JSValue? defaultThis]) {
    // Get 'this' value - handle both normal calls and .call()
    // See includes() for detailed explanation
    JSValue thisValue;
    List<JSValue> realArgs;

    bool calledViaCallOrApply =
        defaultThis != null &&
        args.isNotEmpty &&
        args[0] is JSObject &&
        !identical(args[0], defaultThis);

    if (calledViaCallOrApply) {
      thisValue = args[0];
      realArgs = args.length > 1 ? args.sublist(1) : [];
    } else if (defaultThis != null) {
      thisValue = defaultThis;
      realArgs = args.length > 1
          ? args.sublist(1)
          : []; // Skip prepended thisBinding
    } else if (args.isNotEmpty) {
      thisValue = args[0];
      realArgs = args.length > 1 ? args.sublist(1) : [];
    } else {
      throw JSTypeError('Array.prototype.fill called on null or undefined');
    }

    if (thisValue.isNull || thisValue.isUndefined) {
      throw JSTypeError('Array.prototype.fill called on null or undefined');
    }

    // Convert to object
    final obj = thisValue is JSObject ? thisValue : thisValue.toObject();

    // value: value to fill with (default: undefined)
    final value = realArgs.isNotEmpty
        ? realArgs[0]
        : JSValueFactory.undefined();

    // Get length
    final length = _getLength(obj);

    var start = 0;
    if (realArgs.length > 1 && !realArgs[1].isUndefined) {
      start = toArrayIndex(realArgs[1].toNumber());
      if (start < 0) {
        start = length + start;
        if (start < 0) start = 0;
      }
      if (start > length) start = length;
    }

    var end = length;
    if (realArgs.length > 2 && !realArgs[2].isUndefined) {
      end = toArrayIndex(realArgs[2].toNumber());
      if (end < 0) {
        end = length + end;
        if (end < 0) end = 0;
      }
      if (end > length) end = length;
    }

    // Fast path for JSArray
    if (obj is JSArray) {
      for (int i = start; i < end; i++) {
        // Use setProperty to properly handle holes
        obj.setProperty(i.toString(), value);
      }
    } else {
      // Generic path for objects
      for (int i = start; i < end; i++) {
        obj.setProperty(i.toString(), value);
      }
    }

    return obj;
  }

  /// Array.prototype.copyWithin(target[, start[, end]])
  /// Copies part of an array to another location in the same array
  static JSValue copyWithin(List<JSValue> args, [JSValue? defaultThis]) {
    // Get 'this' value - handle both normal calls and .call()
    // See includes() for detailed explanation
    JSValue thisValue;
    List<JSValue> realArgs;

    bool calledViaCallOrApply =
        defaultThis != null &&
        args.isNotEmpty &&
        args[0] is JSObject &&
        !identical(args[0], defaultThis);

    if (calledViaCallOrApply) {
      thisValue = args[0];
      realArgs = args.length > 1 ? args.sublist(1) : [];
    } else if (defaultThis != null) {
      thisValue = defaultThis;
      realArgs = args.length > 1
          ? args.sublist(1)
          : []; // Skip prepended thisBinding
    } else if (args.isNotEmpty) {
      thisValue = args[0];
      realArgs = args.length > 1 ? args.sublist(1) : [];
    } else {
      throw JSTypeError(
        'Array.prototype.copyWithin called on null or undefined',
      );
    }

    if (thisValue.isNull || thisValue.isUndefined) {
      throw JSTypeError(
        'Array.prototype.copyWithin called on null or undefined',
      );
    }

    // Convert to object
    final obj = thisValue is JSObject ? thisValue : thisValue.toObject();

    // Get length
    final length = _getLength(obj);

    // target: position to copy elements to (default: 0)
    var target = 0;
    if (realArgs.isNotEmpty && !realArgs[0].isUndefined) {
      target = toArrayIndex(realArgs[0].toNumber());
      if (target < 0) {
        target = length + target;
        if (target < 0) target = 0;
      }
      if (target > length) target = length;
    }

    // start: start index of copy (default 0)
    var start = 0;
    if (realArgs.length > 1 && !realArgs[1].isUndefined) {
      start = toArrayIndex(realArgs[1].toNumber());
      if (start < 0) {
        start = length + start;
        if (start < 0) start = 0;
      }
      if (start > length) start = length;
    }

    // end: end index of copy (default length)
    var end = length;
    if (realArgs.length > 2 && !realArgs[2].isUndefined) {
      end = toArrayIndex(realArgs[2].toNumber());
      if (end < 0) {
        end = length + end;
        if (end < 0) end = 0;
      }
      if (end > length) end = length;
    }

    // Number of elements to copy
    final count = (end - start).clamp(0, length - target);

    if (count <= 0) {
      return obj;
    }

    // Fast path for JSArray
    if (obj is JSArray) {
      // Copy elements (handling holes correctly per ES spec)
      // We need to track which indices exist vs are holes
      final temp = <JSValue?>[];
      final sourceExists = <bool>[];

      for (int i = 0; i < count; i++) {
        final sourceIndex = start + i;
        final key = sourceIndex.toString();
        // Use hasProperty to check if index exists (respects length and holes)
        if (obj.hasProperty(key)) {
          temp.add(obj.getProperty(key));
          sourceExists.add(true);
        } else {
          temp.add(null); // Use null to mark non-existent properties
          sourceExists.add(false);
        }
      }

      // Copy from temp to destination, preserving hole semantics
      for (int i = 0; i < count; i++) {
        final destIndex = target + i;
        if (sourceExists[i]) {
          // Source had a value - set it at destination
          obj.setProperty(destIndex.toString(), temp[i]!);
        } else {
          // Source didn't exist - DeletePropertyOrThrow to create hole
          final deleted = obj.deleteProperty(destIndex.toString());
          if (!deleted) {
            throw JSTypeError('Cannot delete property');
          }
        }
      }
    } else {
      // Generic path for objects - use hasProperty/getProperty/setProperty
      final temp = <JSValue?>[];
      final sourceExists = <bool>[];

      for (int i = 0; i < count; i++) {
        final key = (start + i).toString();
        if (obj.hasProperty(key)) {
          temp.add(obj.getProperty(key));
          sourceExists.add(true);
        } else {
          temp.add(null);
          sourceExists.add(false);
        }
      }

      // Copy to destination, handling holes correctly
      for (int i = 0; i < count; i++) {
        final destKey = (target + i).toString();
        if (sourceExists[i]) {
          obj.setProperty(destKey, temp[i]!);
        } else {
          // Source didn't exist - DeletePropertyOrThrow to preserve hole
          final deleted = obj.deleteProperty(destKey);
          if (!deleted) {
            throw JSTypeError('Cannot delete property');
          }
        }
      }
    }

    return obj;
  }

  /// ES2019: Array.prototype.flat(depth = 1)
  /// When called via .call(), first arg is 'this' (array-like object)
  static JSValue flat(List<JSValue> args, [JSValue? defaultThis]) {
    // Get 'this' value - handle .call() semantics
    JSValue thisValue;
    List<JSValue> restArgs;

    // Detect if called via .call(thisArg, depth)
    // When called via .call(), callWithThis prepends thisArg to args
    // We detect this by checking if first arg is NOT a number (depth should be a number)
    // and is an array, object, null, undefined, or primitive
    bool calledViaCall =
        args.isNotEmpty &&
        !args[0].isNumber &&
        (args[0] is JSArray ||
            args[0] is JSObject ||
            args[0].isNull ||
            args[0].isUndefined ||
            args[0].isBoolean ||
            args[0].isString);

    if (calledViaCall) {
      final first = args[0];
      // Check if first arg is null or undefined - must throw TypeError
      if (first.isNull || first.isUndefined) {
        throw JSTypeError('Array.prototype.flat called on null or undefined');
      }
      thisValue = first;
      restArgs = args.length > 1 ? args.sublist(1) : [];
    } else if (defaultThis != null) {
      // Check if defaultThis is null or undefined
      if (defaultThis.isNull || defaultThis.isUndefined) {
        throw JSTypeError('Array.prototype.flat called on null or undefined');
      }
      thisValue = defaultThis;
      restArgs = args;
    } else {
      throw JSTypeError('Array.prototype.flat called on null or undefined');
    }

    // Get depth parameter (default 1) using ToIntegerOrInfinity
    int depth = 1;
    if (restArgs.isNotEmpty) {
      final depthValue = restArgs[0];
      // ToIntegerOrInfinity conversion
      final depthNum = depthValue.toNumber();
      if (depthNum.isNaN || depthNum == 0) {
        depth = 0;
      } else if (depthNum.isInfinite && depthNum > 0) {
        depth = 999999; // Treat +Infinity as very large number
      } else if (depthNum.isInfinite && depthNum < 0) {
        depth = 0; // Treat -Infinity as 0
      } else {
        depth = depthNum.truncate(); // truncate towards zero
      }
    }

    // Treat negative depth as 0 (no flattening)
    if (depth < 0) depth = 0;

    // Flatten the array, properly handling holes vs explicit undefined
    final result = _flattenArrayWithHoles(thisValue, depth);

    // Per ES2019 spec, we need to check if constructor is valid
    // Get constructor from thisValue
    JSValue constructor = JSValueFactory.undefined();
    if (thisValue is JSObject) {
      constructor = thisValue.getProperty('constructor');
    }

    // Check if constructor is valid (must be undefined or callable)
    // Note: Callable includes functions, classes, and objects with Symbol.hasInstance
    if (!constructor.isUndefined) {
      // Check if it's callable (function, class, or has [[Call]] internal method)
      bool isCallable =
          constructor.isFunction ||
          constructor is JSNativeFunction ||
          (constructor is JSObject &&
              (constructor.hasProperty('call') ||
                  constructor.hasProperty('apply')));

      if (!isCallable) {
        throw JSTypeError('Constructor must be callable');
      }
    }

    return JSValueFactory.array(result);
  }

  /// Recursive helper to flatten array to specified depth
  /// Properly distinguishes between holes (empty slots) and explicit undefined values
  static List<JSValue> _flattenArrayWithHoles(JSValue source, int depth) {
    if (depth <= 0) {
      // At depth 0, just copy elements (skipping holes)
      return _copyArraySkippingHoles(source);
    }

    final result = <JSValue>[];
    final length = _getLength(source);

    for (int i = 0; i < length; i++) {
      // Check if this index is a hole
      if (_isHoleAt(source, i)) {
        // Skip holes - this is per ECMAScript spec
        continue;
      }

      final element = _getElementAt(source, i);

      if (element is JSArray) {
        // Recursively flatten nested arrays
        result.addAll(_flattenArrayWithHoles(element, depth - 1));
      } else {
        // Keep non-array elements (including null and explicit undefined)
        result.add(element);
      }
    }
    return result;
  }

  /// Copy array elements, skipping holes but keeping explicit undefined
  static List<JSValue> _copyArraySkippingHoles(JSValue source) {
    final result = <JSValue>[];
    final length = _getLength(source);

    for (int i = 0; i < length; i++) {
      if (!_isHoleAt(source, i)) {
        result.add(_getElementAt(source, i));
      }
    }
    return result;
  }

  /// Get the length of an array or array-like object
  /// Handles NaN, Infinity, and negative values safely
  static int _getLength(JSValue source) {
    if (source is JSArray) {
      return source.length;
    }
    if (source is JSObject) {
      final lengthValue = source.getProperty('length');
      final length = lengthValue.toNumber();
      if (length.isNaN || length.isInfinite || length < 0) {
        return 0;
      }
      return length.toInt().clamp(0, 0x1FFFFFFFFFFFFF);
    }
    return 0;
  }

  /// Check if an index is a hole in the source array/object
  static bool _isHoleAt(JSValue source, int index) {
    if (source is JSArray) {
      // Use the JSArray's hole tracking
      return source.isHole(index);
    }
    if (source is JSObject) {
      // For array-like objects, check if the property exists using hasOwnProperty
      // A hole is when the property doesn't exist at that index
      return !source.hasOwnProperty(index.toString());
    }
    return false;
  }

  /// Get element at index from array or array-like object
  static JSValue _getElementAt(JSValue source, int index) {
    if (source is JSArray) {
      return source.get(index);
    }
    if (source is JSObject) {
      return source.getProperty(index.toString());
    }
    return JSValueFactory.undefined();
  }

  /// ES2019: Array.prototype.flatMap(callback, thisArg?)
  static JSValue flatMap(List<JSValue> args, JSArray arr) {
    if (args.isEmpty) {
      throw JSTypeError('flatMap requires a callback function');
    }

    final callback = args[0];
    if (!callback.isFunction) {
      throw JSTypeError('Callback must be a function');
    }

    final thisArg = args.length > 1 ? args[1] : JSValueFactory.undefined();

    final mapped = <JSValue>[];
    for (int i = 0; i < arr.elements.length; i++) {
      final element = arr.elements[i];

      // Call callback with (element, index, array)
      final callArgs = [element, JSValueFactory.number(i.toDouble()), arr];

      final result = _callFunction(callback, callArgs, thisArg);

      // If result is an array, add its elements (flatten by 1 level)
      if (result is JSArray) {
        mapped.addAll(result.elements);
      } else {
        mapped.add(result);
      }
    }

    return JSValueFactory.array(mapped);
  }

  /// ES2023: Array.prototype.toReversed()
  /// Non-mutating version of reverse() - returns a new array with elements in reverse order
  /// Unlike slice().reverse(), this method replaces holes with undefined
  static JSValue toReversed(List<JSValue> args, JSArray arr) {
    final length = arr.elements.length;
    final result = <JSValue>[];

    // Iterate from end to start, filling holes with undefined
    for (int i = length - 1; i >= 0; i--) {
      result.add(arr.elements[i]);
    }

    return JSValueFactory.array(result);
  }

  /// ES2023: Array.prototype.toSorted(compareFn?)
  /// Non-mutating version of sort() - returns a new sorted array
  static JSValue toSorted(List<JSValue> args, JSArray arr) {
    // Create a copy of the array elements
    final copy = List<JSValue>.from(arr.elements);

    if (args.isEmpty) {
      // Default alphabetic sort
      copy.sort((a, b) {
        final aStr = JSConversion.jsToString(a);
        final bStr = JSConversion.jsToString(b);
        return aStr.compareTo(bStr);
      });
      return JSValueFactory.array(copy);
    }

    // Check if a compareFn is provided
    final compareFn = args[0];
    if (!compareFn.isFunction) {
      // If not a function, use default sort
      copy.sort((a, b) {
        final aStr = JSConversion.jsToString(a);
        final bStr = JSConversion.jsToString(b);
        return aStr.compareTo(bStr);
      });
      return JSValueFactory.array(copy);
    }

    // Use custom comparison function
    copy.sort((a, b) {
      final result = _callFunction(compareFn, [
        a,
        b,
      ], JSValueFactory.undefined());
      return result.toNumber().toInt();
    });

    return JSValueFactory.array(copy);
  }

  /// ES2023: Array.prototype.toSpliced(start, deleteCount?, ...items)
  /// Non-mutating version of splice() - returns a new array with elements removed/added
  static JSValue toSpliced(List<JSValue> args, JSArray arr) {
    final length = arr.elements.length;

    if (args.isEmpty) {
      // No arguments: return a copy of the array
      return JSValueFactory.array(List<JSValue>.from(arr.elements));
    }

    // Parse start index
    var start = toArrayIndex(args[0].toNumber());
    if (start < 0) start = length + start;
    if (start < 0) start = 0;
    if (start > length) start = length;

    // Parse deleteCount
    var deleteCount = length - start;
    if (args.length > 1) {
      deleteCount = toArrayIndex(args[1].toNumber());
      if (deleteCount < 0) deleteCount = 0;
      if (deleteCount > length - start) deleteCount = length - start;
    }

    // Items to insert
    final itemsToInsert = args.length > 2 ? args.sublist(2) : <JSValue>[];

    // Build the result array
    final result = <JSValue>[];

    // Add elements before start
    for (int i = 0; i < start; i++) {
      result.add(arr.elements[i]);
    }

    // Add new items
    result.addAll(itemsToInsert);

    // Add elements after deleted section
    for (int i = start + deleteCount; i < length; i++) {
      result.add(arr.elements[i]);
    }

    return JSValueFactory.array(result);
  }

  /// ES2023: Array.prototype.with(index, value)
  /// Non-mutating method that returns a new array with the element at the given index replaced
  static JSValue arrayWith(List<JSValue> args, JSArray arr) {
    if (args.isEmpty) {
      throw JSTypeError('with() requires at least one argument');
    }

    final length = arr.elements.length;

    // Parse index
    var index = toArrayIndex(args[0].toNumber());

    // Handle negative indices
    if (index < 0) {
      index = length + index;
    }

    // Check bounds
    if (index < 0 || index >= length) {
      throw JSRangeError('Invalid index: $index');
    }

    // Get the value to set
    final value = args.length > 1 ? args[1] : JSValueFactory.undefined();

    // Create a copy of the array
    final result = List<JSValue>.from(arr.elements);

    // Replace the element at the given index
    result[index] = value;

    return JSValueFactory.array(result);
  }

  /// Helper function to call a JavaScript function with context
  static JSValue _callFunction(
    JSValue function,
    List<JSValue> args,
    JSValue thisBinding,
  ) {
    // Check if it's a native function
    if (function is JSNativeFunction) {
      return function.nativeImpl(args);
    }

    // Use the current evaluator to execute JavaScript functions
    final evaluator = JSEvaluator.currentInstance;
    if (evaluator == null) {
      throw JSError('No evaluator available for function execution');
    }

    try {
      // Appeler la fonction JavaScript avec le bon contexte this
      return evaluator.callFunction(function, args, thisBinding);
    } catch (e) {
      // If it's a JSException (JavaScript exception), propagate it as-is
      if (e is JSException) {
        rethrow;
      }
      // For other errors, wrap them as JSError
      throw JSError('Error executing callback function: $e');
    }
  }

  /// Helper to check if a property exists in the prototype chain
  static bool _hasInPrototypeChain(JSObject obj, String key) {
    var current = obj.getProperty('__proto__');
    while (current is JSObject && !current.isNull) {
      if (current.hasOwnProperty(key)) {
        return true;
      }
      current = current.getProperty('__proto__');
    }
    return false;
  }

  /// Helper to convert an array-like object to a list of elements
  /// This implements ToObject + Get("length") + indexed property access
  static List<JSValue> _toArrayLikeElements(JSValue obj) {
    if (obj is JSArray) {
      return obj.elements;
    }
    if (obj is JSObject) {
      final lengthValue = obj.getProperty('length');
      final length = lengthValue.toNumber();
      if (length.isNaN || length < 0) {
        return [];
      }
      final len = length.floor();
      final result = <JSValue>[];
      for (int i = 0; i < len; i++) {
        result.add(obj.getProperty(i.toString()));
      }
      return result;
    }
    // For primitives, convert to object first
    final objValue = obj.toObject();
    return _toArrayLikeElements(objValue);
  }

  /// Gets a property/method for an array (auto-boxing)
  static JSValue getArrayProperty(JSArray arr, String propertyName) {
    // Special case for __proto__
    if (propertyName == '__proto__') {
      return arr.getPrototype() ?? JSValueFactory.nullValue();
    }

    // First check if it's a valid numeric index for an array
    // Valid array indices are integers from 0 to 2^32 - 2 (4294967294)
    final index = int.tryParse(propertyName);
    if (index != null && index >= 0 && index < 4294967295) {
      // This is a valid array index
      // First check if array has this index (not a hole)
      if (index < arr.elements.length && !arr.isHole(index)) {
        return arr.elements[index];
      }
      // Index is a hole or out of bounds - check prototype chain per [[Get]] semantics
      final proto = arr.getPrototype();
      if (proto != null) {
        final inherited = proto.getProperty(propertyName);
        if (!inherited.isUndefined) {
          return inherited;
        }
      }
      return JSValueFactory.undefined();
    }

    // Check if the property is defined directly on the array itself
    // This includes non-index numeric properties like "4294967295"
    final ownProp = arr.getOwnPropertyDirect(propertyName);
    if (ownProp != null && !ownProp.isUndefined) {
      return ownProp;
    }

    // List of native methods that are handled in the switch below
    // We check Array.prototype for methods that are NOT in this list,
    // or that have been explicitly overridden by user code
    // List of native methods that are handled in the switch below
    // These must NOT be looked up from Array.prototype first
    // Symbol.iterator is included here since it's handled in the default block
    final symbolIteratorKey = JSSymbol.iterator.toString();
    final nativeMethods = {
      'length',
      'push',
      'pop',
      'shift',
      'unshift',
      'slice',
      'splice',
      'join',
      'toString',
      'concat',
      'indexOf',
      'lastIndexOf',
      'forEach',
      'map',
      'filter',
      'reduce',
      'reduceRight',
      'every',
      'some',
      'find',
      'findIndex',
      'findLast',
      'findLastIndex',
      'includes',
      'reverse',
      'sort',
      'fill',
      'copyWithin',
      'isArray',
      'at',
      'toReversed',
      'toSorted',
      'toSpliced',
      'with',
      'flat',
      'flatMap',
      'keys',
      'values',
      'entries',
      symbolIteratorKey, // Symbol.iterator - must be native to capture correct array
    };

    // Check if the property is defined on Array.prototype AND is not a native method
    // This allows overriding built-in methods like Array.prototype.toString = Object.prototype.toString
    final arrayProto = JSArray.arrayPrototype;
    if (arrayProto != null && !nativeMethods.contains(propertyName)) {
      final protoProp = arrayProto.getOwnPropertyDirect(propertyName);
      if (protoProp != null && !protoProp.isUndefined) {
        return protoProp;
      }
    }

    // For native methods, check if they've been overridden on Array.prototype
    // The prototype property takes precedence over native implementation
    if (arrayProto != null && nativeMethods.contains(propertyName)) {
      final protoProp = arrayProto.getOwnPropertyDirect(propertyName);
      if (protoProp != null && !protoProp.isUndefined) {
        // Check if this is NOT the original native function we registered
        // If it's different, it means user overrode it (e.g., Array.prototype.toString = Object.prototype.toString)
        if (!isOriginalNative(propertyName, protoProp)) {
          // It's been overridden - return the overridden version
          return protoProp;
        }
        // It's the original native - fall through to switch to create properly bound version
      }
    }

    // Then return the native Array method if one exists.
    // NOTE: We intentionally do NOT check Object.prototype here - Array has its own
    // built-in methods that should take precedence. The prototype chain is only used
    // for methods explicitly set on Array.prototype (handled above).

    switch (propertyName) {
      case 'length':
        return length(arr);
      case 'push':
        // Returns a function that can be called with or without thisBinding
        return JSNativeFunction(
          functionName: 'push',
          expectedArgs: 1,
          nativeImpl: (args) {
            // If called via callWithThis, the first arg is 'this'
            // If called directly, we use captured 'arr'
            if (args.isNotEmpty && args[0] is JSArray) {
              return push(args);
            }
            return push(args, arr);
          },
        );
      case 'pop':
        return JSNativeFunction(
          functionName: 'pop',
          expectedArgs: 0,
          nativeImpl: (args) => pop(args, arr),
        );
      case 'shift':
        return JSNativeFunction(
          functionName: 'shift',
          expectedArgs: 0,
          nativeImpl: (args) => shift(args, arr),
        );
      case 'unshift':
        return JSNativeFunction(
          functionName: 'unshift',
          expectedArgs: 1,
          nativeImpl: (args) => unshift(args, arr),
        );
      case 'slice':
        return JSNativeFunction(
          functionName: 'slice',
          nativeImpl: (args) => slice(args, arr),
        );
      case 'splice':
        return JSNativeFunction(
          functionName: 'splice',
          nativeImpl: (args) => splice(args, arr),
        );
      case 'join':
        return JSNativeFunction(
          functionName: 'join',
          nativeImpl: (args) => join(args, arr),
          hasContextBound: true,
        );
      case 'toString':
        return JSNativeFunction(
          functionName: 'toString',
          nativeImpl: (args) => toString_(args, arr),
          hasContextBound: false, // Allow call/apply to override this
        );
      case 'concat':
        return JSNativeFunction(
          functionName: 'concat',
          nativeImpl: (args) => concat(args, arr),
          hasContextBound: false, // Allow .call() to prepend thisBinding
        );
      case 'indexOf':
        return JSNativeFunction(
          functionName: 'indexOf',
          nativeImpl: (args) => indexOf(args, arr),
          expectedArgs: 1, // searchElement is required
          hasContextBound: false, // Allow .call() to work with generic objects
        );
      case 'lastIndexOf':
        return JSNativeFunction(
          functionName: 'lastIndexOf',
          nativeImpl: (args) => lastIndexOf(args, arr),
          expectedArgs: 1, // searchElement is required
          hasContextBound: false, // Allow .call() to work with generic objects
        );
      case 'includes':
        return JSNativeFunction(
          functionName: 'includes',
          nativeImpl: (args) =>
              includes(args, arr), // arr is used as defaultThis
          expectedArgs: 1, // searchElement is required
          hasContextBound: false, // Allow .call() to work with generic objects
        );
      case 'reverse':
        return JSNativeFunction(
          functionName: 'reverse',
          nativeImpl: (args) =>
              reverse(args, arr), // arr is used as defaultThis
          expectedArgs: 0, // No required parameters
          hasContextBound: false, // Allow .call() to work with generic objects
        );
      case 'sort':
        return JSNativeFunction(
          functionName: 'sort',
          nativeImpl: (args) => sort(args, arr),
        );
      case 'forEach':
        return JSNativeFunction(
          functionName: 'forEach',
          nativeImpl: (args) => forEach(args, arr),
        );
      case 'map':
        return JSNativeFunction(
          functionName: 'map',
          nativeImpl: (args) => map(args, arr),
        );
      case 'filter':
        return JSNativeFunction(
          functionName: 'filter',
          nativeImpl: (args) => filter(args, arr),
        );
      case 'find':
        return JSNativeFunction(
          functionName: 'find',
          nativeImpl: (args) => find(args, arr),
        );
      case 'findIndex':
        return JSNativeFunction(
          functionName: 'findIndex',
          nativeImpl: (args) => findIndex(args, arr),
        );
      case 'findLast':
        // ES2023
        return JSNativeFunction(
          functionName: 'findLast',
          nativeImpl: (args) => findLast(args, arr),
        );
      case 'findLastIndex':
        // ES2023
        return JSNativeFunction(
          functionName: 'findLastIndex',
          nativeImpl: (args) => findLastIndex(args, arr),
        );
      case 'reduce':
        return JSNativeFunction(
          functionName: 'reduce',
          nativeImpl: (args) => reduce(args, arr),
        );
      case 'some':
        return JSNativeFunction(
          functionName: 'some',
          nativeImpl: (args) => some(args, arr),
        );
      case 'every':
        return JSNativeFunction(
          functionName: 'every',
          nativeImpl: (args) => every(args, arr),
        );
      case 'reduceRight':
        return JSNativeFunction(
          functionName: 'reduceRight',
          nativeImpl: (args) => reduceRight(args, arr),
        );
      case 'at':
        return JSNativeFunction(
          functionName: 'at',
          nativeImpl: (args) => at(args, arr),
          expectedArgs: 1, // index is required
        );
      case 'entries':
        return JSNativeFunction(
          functionName: 'entries',
          nativeImpl: (args) => entries(args, arr),
        );
      case 'keys':
        return JSNativeFunction(
          functionName: 'keys',
          nativeImpl: (args) => keys(args, arr),
        );
      case 'values':
        return JSNativeFunction(
          functionName: 'values',
          nativeImpl: (args) => values(args, arr),
        );
      case 'fill':
        return JSNativeFunction(
          functionName: 'fill',
          nativeImpl: (args) => fill(args, arr),
          expectedArgs: 1, // value is required
        );
      case 'copyWithin':
        return JSNativeFunction(
          functionName: 'copyWithin',
          nativeImpl: (args) => copyWithin(args, arr),
          expectedArgs: 2, // target and start are required
        );
      case 'flat':
        // ES2019
        return JSNativeFunction(
          functionName: 'flat',
          nativeImpl: (args) => flat(args, arr),
        );
      case 'flatMap':
        // ES2019
        return JSNativeFunction(
          functionName: 'flatMap',
          nativeImpl: (args) => flatMap(args, arr),
        );
      case 'toReversed':
        // ES2023
        return JSNativeFunction(
          functionName: 'toReversed',
          nativeImpl: (args) => toReversed(args, arr),
        );
      case 'toSorted':
        // ES2023
        return JSNativeFunction(
          functionName: 'toSorted',
          nativeImpl: (args) => toSorted(args, arr),
        );
      case 'toSpliced':
        // ES2023
        return JSNativeFunction(
          functionName: 'toSpliced',
          nativeImpl: (args) => toSpliced(args, arr),
        );
      case 'with':
        // ES2023
        return JSNativeFunction(
          functionName: 'with',
          nativeImpl: (args) => arrayWith(args, arr),
        );
      default:
        // Check for Symbol.iterator
        if (propertyName == JSSymbol.iterator.toString()) {
          return JSNativeFunction(
            functionName: 'Symbol.iterator',
            nativeImpl: (args) {
              // Return an iterator for the array
              return JSArrayIterator(arr, IteratorKind.valueKind);
            },
          );
        }
        // ES2020: Check custom properties of base object
        // Arrays can have additional properties like 'index', 'input', 'groups'
        // (used by String.prototype.matchAll)
        final ownProperty = arr.getOwnPropertyDirect(propertyName);
        if (ownProperty != null) {
          return ownProperty;
        }

        // For non-native methods, try the prototype chain
        // Start from the array's prototype and walk up
        // Only check Object.prototype for built-in methods since that's where
        // isPrototypeOf, hasOwnProperty, etc. are defined
        final objectProto = JSObject.objectPrototype;
        // Check if Object.prototype has this property
        final objectProp = objectProto.getProperty(propertyName);
        if (!objectProp.isUndefined) {
          return objectProp;
        }

        return JSValueFactory.undefined();
    }
  }
}
