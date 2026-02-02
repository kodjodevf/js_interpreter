/// Global JavaScript Number object
/// Implements the Number constructor and its static properties/methods
library;
// ignore_for_file: non_constant_identifier_names

import 'dart:math' as dart_math;
import 'js_value.dart';
import 'native_functions.dart';

/// Global Number object (constructor and static methods)
class NumberObject {
  // ===== STATIC PROPERTIES =====

  /// Number.MAX_VALUE - largest representable numeric value
  static JSValue get MAX_VALUE => JSValueFactory.number(double.maxFinite);

  /// Number.MIN_VALUE - smallest representable positive value
  static JSValue get MIN_VALUE => JSValueFactory.number(double.minPositive);

  /// Number.POSITIVE_INFINITY - positive infinity
  static JSValue get POSITIVE_INFINITY =>
      JSValueFactory.number(double.infinity);

  /// Number.NEGATIVE_INFINITY - negative infinity
  static JSValue get NEGATIVE_INFINITY =>
      JSValueFactory.number(double.negativeInfinity);

  /// Number.NaN - Not a Number
  static JSValue get NaN => JSValueFactory.number(double.nan);

  /// Number.MAX_SAFE_INTEGER - largest safe integer (2^53 - 1)
  static JSValue get MAX_SAFE_INTEGER =>
      JSValueFactory.number(9007199254740991.0);

  /// Number.MIN_SAFE_INTEGER - smallest safe integer (-(2^53 - 1))
  static JSValue get MIN_SAFE_INTEGER =>
      JSValueFactory.number(-9007199254740991.0);

  /// Number.EPSILON - smallest representable difference between 1 and the next number
  static JSValue get EPSILON =>
      JSValueFactory.number(dart_math.pow(2, -52).toDouble());

  // ===== STATIC METHODS =====

  /// Number.isFinite(value) - tests if the value is a finite number
  static JSValue isFinite(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.boolean(false);
    }

    final value = args[0];
    if (value.type != JSValueType.number) {
      return JSValueFactory.boolean(false);
    }

    final num = value.toNumber();
    return JSValueFactory.boolean(num.isFinite);
  }

  /// Number.isInteger(value) - tests if the value is an integer
  static JSValue isInteger(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.boolean(false);
    }

    final value = args[0];
    if (value.type != JSValueType.number) {
      return JSValueFactory.boolean(false);
    }

    final num = value.toNumber();
    if (!num.isFinite) {
      return JSValueFactory.boolean(false);
    }

    return JSValueFactory.boolean(num == num.toInt());
  }

  /// Number.isNaN(value) - tests if the value is NaN
  static JSValue isNaN(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.boolean(false);
    }

    final value = args[0];
    if (value.type != JSValueType.number) {
      return JSValueFactory.boolean(false);
    }

    final num = value.toNumber();
    return JSValueFactory.boolean(num.isNaN);
  }

  /// Number.isSafeInteger(value) - tests if the value is a safe integer
  static JSValue isSafeInteger(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.boolean(false);
    }

    final value = args[0];
    if (value.type != JSValueType.number) {
      return JSValueFactory.boolean(false);
    }

    final num = value.toNumber();
    if (!num.isFinite || num != num.toInt()) {
      return JSValueFactory.boolean(false);
    }

    const maxSafe = 9007199254740991.0;
    const minSafe = -9007199254740991.0;
    return JSValueFactory.boolean(num >= minSafe && num <= maxSafe);
  }

  /// Number.parseFloat(string) - parse a string to floating point number
  static JSValue parseFloat(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final str = args[0].toString().trim();
    if (str.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    // Handle special cases
    if (str == 'Infinity' || str == '+Infinity') {
      return JSValueFactory.number(double.infinity);
    }
    if (str == '-Infinity') {
      return JSValueFactory.number(double.negativeInfinity);
    }
    if (str == 'NaN') {
      return JSValueFactory.number(double.nan);
    }

    // Parse until first invalid character
    var validStr = '';
    var hasDecimal = false;
    var hasE = false;
    var i = 0;

    // Optional sign
    if (i < str.length && (str[i] == '+' || str[i] == '-')) {
      validStr += str[i];
      i++;
    }

    // Numeric part
    while (i < str.length) {
      final char = str[i];
      if (char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57) {
        // Digits 0-9
        validStr += char;
      } else if (char == '.' && !hasDecimal && !hasE) {
        validStr += char;
        hasDecimal = true;
      } else if ((char == 'e' || char == 'E') && !hasE && validStr.isNotEmpty) {
        validStr += char;
        hasE = true;
        // Optional sign apres e/E
        if (i + 1 < str.length && (str[i + 1] == '+' || str[i + 1] == '-')) {
          i++;
          validStr += str[i];
        }
      } else {
        break;
      }
      i++;
    }

    if (validStr.isEmpty || validStr == '+' || validStr == '-') {
      return JSValueFactory.number(double.nan);
    }

    try {
      final result = double.parse(validStr);
      return JSValueFactory.number(result);
    } catch (e) {
      return JSValueFactory.number(double.nan);
    }
  }

  /// Number.parseInt(string, radix) - parse a string to integer with radix
  static JSValue parseInt(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final str = args[0].toString().trim();
    var radix = args.length > 1 ? args[1].toNumber().toInt() : 10;

    if (str.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    // Validate radix
    if (radix != 0 && (radix < 2 || radix > 36)) {
      return JSValueFactory.number(double.nan);
    }

    // Auto-detect base if radix = 0
    var cleanStr = str;
    if (radix == 0) {
      if (cleanStr.startsWith('0x') || cleanStr.startsWith('0X')) {
        radix = 16;
        cleanStr = cleanStr.substring(2);
      } else if (cleanStr.startsWith('0b') || cleanStr.startsWith('0B')) {
        radix = 2;
        cleanStr = cleanStr.substring(2);
      } else if (cleanStr.startsWith('0') && cleanStr.length > 1) {
        radix = 8;
        cleanStr = cleanStr.substring(1);
      } else {
        radix = 10;
      }
    }

    // Handle sign
    var negative = false;
    if (cleanStr.startsWith('-')) {
      negative = true;
      cleanStr = cleanStr.substring(1);
    } else if (cleanStr.startsWith('+')) {
      cleanStr = cleanStr.substring(1);
    }

    // Parse until first invalid character
    var result = 0.0;
    for (int i = 0; i < cleanStr.length; i++) {
      final char = cleanStr[i];
      var digit = -1;

      if (char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57) {
        digit = char.codeUnitAt(0) - 48; // 0-9
      } else if (char.codeUnitAt(0) >= 97 && char.codeUnitAt(0) <= 122) {
        digit = char.codeUnitAt(0) - 97 + 10; // a-z
      } else if (char.codeUnitAt(0) >= 65 && char.codeUnitAt(0) <= 90) {
        digit = char.codeUnitAt(0) - 65 + 10; // A-Z
      }

      if (digit < 0 || digit >= radix) {
        break;
      }

      result = result * radix + digit;
    }

    if (negative) {
      result = -result;
    }

    return JSValueFactory.number(result);
  }

  // ===== CONSTRUCTOR =====

  /// Number(value) - Number constructor
  static JSValue constructor(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(0);
    }

    final value = args[0];
    switch (value.type) {
      case JSValueType.number:
        return value;
      case JSValueType.boolean:
        return JSValueFactory.number((value as JSBoolean).value ? 1 : 0);
      case JSValueType.string:
        final str = (value as JSString).value.trim();
        if (str.isEmpty) {
          return JSValueFactory.number(0);
        }
        return parseFloat([value]);
      case JSValueType.undefined:
        return JSValueFactory.number(double.nan);
      case JSValueType.nullType:
        return JSValueFactory.number(0);
      default:
        return JSValueFactory.number(double.nan);
    }
  }

  // ===== FACTORY =====

  /// Creates the global Number object with all its properties and methods
  static JSObject createNumberObject() {
    final number = JSObject();

    // ===== STATIC PROPERTIES (non-writable, non-enumerable, non-configurable) =====
    // According to ECMAScript, these Number constants are non-writable and non-configurable
    number.defineProperty(
      'MAX_VALUE',
      PropertyDescriptor(
        value: MAX_VALUE,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    number.defineProperty(
      'MIN_VALUE',
      PropertyDescriptor(
        value: MIN_VALUE,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    number.defineProperty(
      'POSITIVE_INFINITY',
      PropertyDescriptor(
        value: POSITIVE_INFINITY,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    number.defineProperty(
      'NEGATIVE_INFINITY',
      PropertyDescriptor(
        value: NEGATIVE_INFINITY,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    number.defineProperty(
      'NaN',
      PropertyDescriptor(
        value: NaN,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    number.defineProperty(
      'MAX_SAFE_INTEGER',
      PropertyDescriptor(
        value: MAX_SAFE_INTEGER,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    number.defineProperty(
      'MIN_SAFE_INTEGER',
      PropertyDescriptor(
        value: MIN_SAFE_INTEGER,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    number.defineProperty(
      'EPSILON',
      PropertyDescriptor(
        value: EPSILON,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );

    // ===== STATIC METHODS =====
    number.setProperty(
      'isFinite',
      JSNativeFunction(functionName: 'isFinite', nativeImpl: isFinite),
    );
    number.setProperty(
      'isInteger',
      JSNativeFunction(functionName: 'isInteger', nativeImpl: isInteger),
    );
    number.setProperty(
      'isNaN',
      JSNativeFunction(functionName: 'isNaN', nativeImpl: isNaN),
    );
    number.setProperty(
      'isSafeInteger',
      JSNativeFunction(
        functionName: 'isSafeInteger',
        nativeImpl: isSafeInteger,
      ),
    );
    number.setProperty(
      'parseFloat',
      JSNativeFunction(functionName: 'parseFloat', nativeImpl: parseFloat),
    );
    number.setProperty(
      'parseInt',
      JSNativeFunction(functionName: 'parseInt', nativeImpl: parseInt),
    );

    return number;
  }
}
