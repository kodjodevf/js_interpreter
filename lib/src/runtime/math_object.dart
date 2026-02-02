// ignore_for_file: non_constant_identifier_names

library;

import 'dart:math' as dart_math;
import 'dart:typed_data';
import 'js_value.dart';
import 'js_symbol.dart';
import 'native_functions.dart';

/// Math object with all methods and constants
class MathObject {
  // ===== CONSTANTES MATH =====

  /// Math.E - base of natural logarithms (approximately 2.718)
  static JSValue get E => JSValueFactory.number(dart_math.e);

  /// Math.LN10 - natural logarithm of 10 (approximately 2.303)
  static JSValue get LN10 => JSValueFactory.number(dart_math.ln10);

  /// Math.LN2 - natural logarithm of 2 (approximately 0.693)
  static JSValue get LN2 => JSValueFactory.number(dart_math.ln2);

  /// Math.LOG10E - logarithm base 10 of E (approximately 0.434)
  static JSValue get LOG10E => JSValueFactory.number(dart_math.log10e);

  /// Math.LOG2E - logarithm base 2 of E (approximately 1.443)
  static JSValue get LOG2E => JSValueFactory.number(dart_math.log2e);

  /// Math.PI - ratio of circumference/diameter (approximately 3.14159)
  static JSValue get PI => JSValueFactory.number(dart_math.pi);

  /// Math.SQRT1_2 - square root of 1/2 (approximately 0.707)
  static JSValue get SQRT1_2 => JSValueFactory.number(dart_math.sqrt1_2);

  /// Math.SQRT2 - square root of 2 (approximately 1.414)
  static JSValue get SQRT2 => JSValueFactory.number(dart_math.sqrt2);

  // ===== METHODES MATH =====

  /// Math.abs(x) - absolute value
  static JSValue abs(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN) return JSValueFactory.number(double.nan);

    return JSValueFactory.number(num.abs());
  }

  /// Math.acos(x) - arc cosine
  static JSValue acos(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN || num < -1 || num > 1) {
      return JSValueFactory.number(double.nan);
    }

    return JSValueFactory.number(dart_math.acos(num));
  }

  /// Math.acosh(x) - hyperbolic arc cosine
  static JSValue acosh(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN || num < 1) {
      return JSValueFactory.number(double.nan);
    }

    // acosh(x) = ln(x + sqrt(x² - 1))
    return JSValueFactory.number(
      dart_math.log(num + dart_math.sqrt(num * num - 1)),
    );
  }

  /// Math.asin(x) - arc sine
  static JSValue asin(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN || num < -1 || num > 1) {
      return JSValueFactory.number(double.nan);
    }

    return JSValueFactory.number(dart_math.asin(num));
  }

  /// Math.asinh(x) - hyperbolic arc sine
  static JSValue asinh(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN) return JSValueFactory.number(double.nan);

    // Special cases for infinity
    if (num == double.infinity) return JSValueFactory.number(double.infinity);
    if (num == double.negativeInfinity) {
      return JSValueFactory.number(double.negativeInfinity);
    }

    // Special case for -0 and +0 (must preserve sign)
    if (num == 0) return JSValueFactory.number(num); // Preserves -0 vs +0

    // asinh(x) = ln(x + sqrt(x² + 1))
    return JSValueFactory.number(
      dart_math.log(num + dart_math.sqrt(num * num + 1)),
    );
  }

  /// Math.atan(x) - arc tangent
  static JSValue atan(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN) return JSValueFactory.number(double.nan);

    return JSValueFactory.number(dart_math.atan(num));
  }

  /// Math.atanh(x) - hyperbolic arc tangent
  static JSValue atanh(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN || num <= -1 || num >= 1) {
      return JSValueFactory.number(double.nan);
    }

    // atanh(x) = 0.5 * ln((1 + x) / (1 - x))
    return JSValueFactory.number(0.5 * dart_math.log((1 + num) / (1 - num)));
  }

  /// Math.atan2(y, x) - arc tangent of y/x
  static JSValue atan2(List<JSValue> args) {
    if (args.length < 2) {
      return JSValueFactory.number(double.nan);
    }

    final y = args[0].toNumber();
    final x = args[1].toNumber();

    if (y.isNaN || x.isNaN) return JSValueFactory.number(double.nan);

    return JSValueFactory.number(dart_math.atan2(y, x));
  }

  /// Math.cbrt(x) - cube root
  static JSValue cbrt(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN) return JSValueFactory.number(double.nan);

    // cbrt(x) = sign(x) * |x|^(1/3)
    final sign = num >= 0 ? 1 : -1;
    return JSValueFactory.number(sign * dart_math.pow(num.abs(), 1 / 3));
  }

  /// Math.ceil(x) - ceiling (smallest integer >= x)
  static JSValue ceil(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN || num.isInfinite) return JSValueFactory.number(num);

    return JSValueFactory.number(num.ceilToDouble());
  }

  /// Math.clz32(x) - number of leading zeros in 32-bit representation
  static JSValue clz32(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(32);
    }

    final num = args[0].toNumber();
    if (num.isNaN || num.isInfinite || num == 0) {
      return JSValueFactory.number(32);
    }

    final uint32 = (num.floor() & 0xFFFFFFFF);
    if (uint32 == 0) return JSValueFactory.number(32);

    // Count leading zeros
    var count = 0;
    var mask = 0x80000000;
    for (int i = 0; i < 32; i++) {
      if ((uint32 & mask) != 0) break;
      count++;
      mask >>= 1;
    }

    return JSValueFactory.number(count.toDouble());
  }

  /// Math.cos(x) - cosine
  static JSValue cos(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN || num.isInfinite) return JSValueFactory.number(double.nan);

    return JSValueFactory.number(dart_math.cos(num));
  }

  /// Math.cosh(x) - hyperbolic cosine
  static JSValue cosh(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN) return JSValueFactory.number(double.nan);

    // cosh(x) = (e^x + e^(-x)) / 2
    final exp_x = dart_math.exp(num);
    final exp_minus_x = dart_math.exp(-num);
    return JSValueFactory.number((exp_x + exp_minus_x) / 2);
  }

  /// Math.exp(x) - e^x
  static JSValue exp(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN) return JSValueFactory.number(double.nan);

    return JSValueFactory.number(dart_math.exp(num));
  }

  /// Math.expm1(x) - e^x - 1
  static JSValue expm1(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN) return JSValueFactory.number(double.nan);

    // For small values, exp(x) - 1 ≈ x to avoid precision errors
    if (num.abs() < 1e-15) return JSValueFactory.number(num);

    return JSValueFactory.number(dart_math.exp(num) - 1);
  }

  /// Math.floor(x) - floor (largest integer <= x)
  static JSValue floor(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN || num.isInfinite) return JSValueFactory.number(num);

    return JSValueFactory.number(num.floorToDouble());
  }

  /// Math.fround(x) - rounded to nearest 32-bit float
  static JSValue fround(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN) return JSValueFactory.number(double.nan);
    if (num.isInfinite) return JSValueFactory.number(num);

    // Convert to float32 using Float32List
    final float32List = Float32List(1);
    float32List[0] = num;
    return JSValueFactory.number(float32List[0]);
  }

  /// Math.hypot(...values) - square root of sum of squares
  static JSValue hypot(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(0);
    }

    var sumOfSquares = 0.0;
    var hasNaN = false;
    var hasInfinity = false;

    for (final arg in args) {
      final num = arg.toNumber();
      if (num.isNaN) {
        hasNaN = true;
      } else if (num.isInfinite) {
        hasInfinity = true;
      } else {
        sumOfSquares += num * num;
      }
    }

    if (hasNaN) return JSValueFactory.number(double.nan);
    if (hasInfinity) return JSValueFactory.number(double.infinity);

    return JSValueFactory.number(dart_math.sqrt(sumOfSquares));
  }

  /// Math.imul(x, y) - signed 32-bit multiplication
  static JSValue imul(List<JSValue> args) {
    if (args.length < 2) {
      return JSValueFactory.number(0);
    }

    final a = args[0].toNumber().floor() & 0xFFFFFFFF;
    final b = args[1].toNumber().floor() & 0xFFFFFFFF;

    // 32-bit multiplication with overflow
    final result = (a * b) & 0xFFFFFFFF;

    // Convert to signed 32-bit
    final signed = result > 0x7FFFFFFF ? result - 0x100000000 : result;

    return JSValueFactory.number(signed.toDouble());
  }

  /// Math.log(x) - natural logarithm
  static JSValue log(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN || num < 0) return JSValueFactory.number(double.nan);
    if (num == 0) return JSValueFactory.number(double.negativeInfinity);

    return JSValueFactory.number(dart_math.log(num));
  }

  /// Math.log1p(x) - ln(1 + x)
  static JSValue log1p(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN || num < -1) return JSValueFactory.number(double.nan);
    if (num == -1) return JSValueFactory.number(double.negativeInfinity);

    // For small values, ln(1 + x) ≈ x to avoid precision errors
    if (num.abs() < 1e-15) return JSValueFactory.number(num);

    return JSValueFactory.number(dart_math.log(1 + num));
  }

  /// Math.log10(x) - logarithm base 10
  static JSValue log10(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN || num < 0) return JSValueFactory.number(double.nan);
    if (num == 0) return JSValueFactory.number(double.negativeInfinity);

    return JSValueFactory.number(dart_math.log(num) / dart_math.ln10);
  }

  /// Math.log2(x) - logarithm base 2
  static JSValue log2(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN || num < 0) return JSValueFactory.number(double.nan);
    if (num == 0) return JSValueFactory.number(double.negativeInfinity);

    return JSValueFactory.number(dart_math.log(num) / dart_math.ln2);
  }

  /// Math.max(...values) - maximum value
  static JSValue max(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.negativeInfinity);
    }

    var maxVal = double.negativeInfinity;

    for (final arg in args) {
      final num = arg.toNumber();
      if (num.isNaN) return JSValueFactory.number(double.nan);
      if (num > maxVal) maxVal = num;
    }

    return JSValueFactory.number(maxVal);
  }

  /// Math.min(...values) - minimum value
  static JSValue min(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.infinity);
    }

    var minVal = double.infinity;

    for (final arg in args) {
      final num = arg.toNumber();
      if (num.isNaN) return JSValueFactory.number(double.nan);
      if (num < minVal) minVal = num;
    }

    return JSValueFactory.number(minVal);
  }

  /// Math.pow(base, exponent) - base^exponent
  static JSValue pow(List<JSValue> args) {
    if (args.length < 2) {
      return JSValueFactory.number(double.nan);
    }

    final base = args[0].toNumber();
    final exponent = args[1].toNumber();

    if (base.isNaN || exponent.isNaN) return JSValueFactory.number(double.nan);

    return JSValueFactory.number(dart_math.pow(base, exponent).toDouble());
  }

  /// Math.random() - random number between 0 (inclusive) and 1 (exclusive)
  static JSValue random(List<JSValue> args) {
    return JSValueFactory.number(dart_math.Random().nextDouble());
  }

  /// Math.round(x) - rounded to nearest integer
  static JSValue round(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN || num.isInfinite) return JSValueFactory.number(num);

    return JSValueFactory.number(num.roundToDouble());
  }

  /// Math.sign(x) - sign of x (-1, 0, +1)
  static JSValue sign(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN) return JSValueFactory.number(double.nan);
    if (num == 0 || num == -0.0) return JSValueFactory.number(num);

    return JSValueFactory.number(num > 0 ? 1.0 : -1.0);
  }

  /// Math.sin(x) - sine
  static JSValue sin(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN || num.isInfinite) return JSValueFactory.number(double.nan);

    return JSValueFactory.number(dart_math.sin(num));
  }

  /// Math.sinh(x) - hyperbolic sine
  static JSValue sinh(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN) return JSValueFactory.number(double.nan);

    // sinh(x) = (e^x - e^(-x)) / 2
    final exp_x = dart_math.exp(num);
    final exp_minus_x = dart_math.exp(-num);
    return JSValueFactory.number((exp_x - exp_minus_x) / 2);
  }

  /// Math.sqrt(x) - square root
  static JSValue sqrt(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN || num < 0) return JSValueFactory.number(double.nan);

    return JSValueFactory.number(dart_math.sqrt(num));
  }

  /// Math.tan(x) - tangent
  static JSValue tan(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN || num.isInfinite) return JSValueFactory.number(double.nan);

    return JSValueFactory.number(dart_math.tan(num));
  }

  /// Math.tanh(x) - hyperbolic tangent
  static JSValue tanh(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN) return JSValueFactory.number(double.nan);

    // tanh(x) = (e^x - e^(-x)) / (e^x + e^(-x))
    final exp_x = dart_math.exp(num);
    final exp_minus_x = dart_math.exp(-num);
    return JSValueFactory.number((exp_x - exp_minus_x) / (exp_x + exp_minus_x));
  }

  /// Math.trunc(x) - integer part (removes decimals)
  static JSValue trunc(List<JSValue> args) {
    if (args.isEmpty) {
      return JSValueFactory.number(double.nan);
    }

    final num = args[0].toNumber();
    if (num.isNaN || num.isInfinite) return JSValueFactory.number(num);

    return JSValueFactory.number(num.truncateToDouble());
  }

  /// Create Math object with all its methods and constants
  static JSObject createMathObject() {
    final math = JSObject();

    // ===== CONSTANTS =====
    // Properties must be non-writable, non-enumerable, non-configurable
    // Just like in standard JavaScript
    math.defineProperty(
      'E',
      PropertyDescriptor(
        value: E,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    math.defineProperty(
      'LN10',
      PropertyDescriptor(
        value: LN10,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    math.defineProperty(
      'LN2',
      PropertyDescriptor(
        value: LN2,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    math.defineProperty(
      'LOG10E',
      PropertyDescriptor(
        value: LOG10E,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    math.defineProperty(
      'LOG2E',
      PropertyDescriptor(
        value: LOG2E,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    math.defineProperty(
      'PI',
      PropertyDescriptor(
        value: PI,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    math.defineProperty(
      'SQRT1_2',
      PropertyDescriptor(
        value: SQRT1_2,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    math.defineProperty(
      'SQRT2',
      PropertyDescriptor(
        value: SQRT2,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );

    // ===== METHODS =====
    math.setProperty(
      'abs',
      JSNativeFunction(functionName: 'abs', nativeImpl: abs, expectedArgs: 1),
    );
    math.setProperty(
      'acos',
      JSNativeFunction(functionName: 'acos', nativeImpl: acos, expectedArgs: 1),
    );
    math.setProperty(
      'acosh',
      JSNativeFunction(
        functionName: 'acosh',
        nativeImpl: acosh,
        expectedArgs: 1,
      ),
    );
    math.setProperty(
      'asin',
      JSNativeFunction(functionName: 'asin', nativeImpl: asin, expectedArgs: 1),
    );
    math.setProperty(
      'asinh',
      JSNativeFunction(
        functionName: 'asinh',
        nativeImpl: asinh,
        expectedArgs: 1,
      ),
    );
    math.setProperty(
      'atan',
      JSNativeFunction(functionName: 'atan', nativeImpl: atan, expectedArgs: 1),
    );
    math.setProperty(
      'atanh',
      JSNativeFunction(
        functionName: 'atanh',
        nativeImpl: atanh,
        expectedArgs: 1,
      ),
    );
    math.setProperty(
      'atan2',
      JSNativeFunction(
        functionName: 'atan2',
        nativeImpl: atan2,
        expectedArgs: 2,
      ),
    );
    math.setProperty(
      'cbrt',
      JSNativeFunction(functionName: 'cbrt', nativeImpl: cbrt, expectedArgs: 1),
    );
    math.setProperty(
      'ceil',
      JSNativeFunction(functionName: 'ceil', nativeImpl: ceil, expectedArgs: 1),
    );
    math.setProperty(
      'clz32',
      JSNativeFunction(
        functionName: 'clz32',
        nativeImpl: clz32,
        expectedArgs: 1,
      ),
    );
    math.setProperty(
      'cos',
      JSNativeFunction(functionName: 'cos', nativeImpl: cos, expectedArgs: 1),
    );
    math.setProperty(
      'cosh',
      JSNativeFunction(functionName: 'cosh', nativeImpl: cosh, expectedArgs: 1),
    );
    math.setProperty(
      'exp',
      JSNativeFunction(functionName: 'exp', nativeImpl: exp, expectedArgs: 1),
    );
    math.setProperty(
      'expm1',
      JSNativeFunction(
        functionName: 'expm1',
        nativeImpl: expm1,
        expectedArgs: 1,
      ),
    );
    math.setProperty(
      'floor',
      JSNativeFunction(
        functionName: 'floor',
        nativeImpl: floor,
        expectedArgs: 1,
      ),
    );
    math.setProperty(
      'fround',
      JSNativeFunction(
        functionName: 'fround',
        nativeImpl: fround,
        expectedArgs: 1,
      ),
    );
    math.setProperty(
      'hypot',
      JSNativeFunction(
        functionName: 'hypot',
        nativeImpl: hypot,
        expectedArgs: 2,
      ),
    );
    math.setProperty(
      'imul',
      JSNativeFunction(functionName: 'imul', nativeImpl: imul, expectedArgs: 2),
    );
    math.setProperty(
      'log',
      JSNativeFunction(functionName: 'log', nativeImpl: log, expectedArgs: 1),
    );
    math.setProperty(
      'log1p',
      JSNativeFunction(
        functionName: 'log1p',
        nativeImpl: log1p,
        expectedArgs: 1,
      ),
    );
    math.setProperty(
      'log10',
      JSNativeFunction(
        functionName: 'log10',
        nativeImpl: log10,
        expectedArgs: 1,
      ),
    );
    math.setProperty(
      'log2',
      JSNativeFunction(functionName: 'log2', nativeImpl: log2, expectedArgs: 1),
    );
    math.setProperty(
      'max',
      JSNativeFunction(functionName: 'max', nativeImpl: max, expectedArgs: 2),
    );
    math.setProperty(
      'min',
      JSNativeFunction(functionName: 'min', nativeImpl: min, expectedArgs: 2),
    );
    math.setProperty(
      'pow',
      JSNativeFunction(functionName: 'pow', nativeImpl: pow, expectedArgs: 2),
    );
    math.setProperty(
      'random',
      JSNativeFunction(
        functionName: 'random',
        nativeImpl: random,
        expectedArgs: 0,
      ),
    );
    math.setProperty(
      'round',
      JSNativeFunction(
        functionName: 'round',
        nativeImpl: round,
        expectedArgs: 1,
      ),
    );
    math.setProperty(
      'sign',
      JSNativeFunction(functionName: 'sign', nativeImpl: sign, expectedArgs: 1),
    );
    math.setProperty(
      'sin',
      JSNativeFunction(functionName: 'sin', nativeImpl: sin, expectedArgs: 1),
    );
    math.setProperty(
      'sinh',
      JSNativeFunction(functionName: 'sinh', nativeImpl: sinh, expectedArgs: 1),
    );
    math.setProperty(
      'sqrt',
      JSNativeFunction(functionName: 'sqrt', nativeImpl: sqrt, expectedArgs: 1),
    );
    math.setProperty(
      'tan',
      JSNativeFunction(functionName: 'tan', nativeImpl: tan, expectedArgs: 1),
    );
    math.setProperty(
      'tanh',
      JSNativeFunction(functionName: 'tanh', nativeImpl: tanh, expectedArgs: 1),
    );
    math.setProperty(
      'trunc',
      JSNativeFunction(
        functionName: 'trunc',
        nativeImpl: trunc,
        expectedArgs: 1,
      ),
    );

    // Re-define all methods with enumerable=false (they were set with setProperty above)
    // This ensures they match ES standard property descriptors
    final methodNames = [
      'abs',
      'acos',
      'acosh',
      'asin',
      'asinh',
      'atan',
      'atanh',
      'atan2',
      'cbrt',
      'ceil',
      'clz32',
      'cos',
      'cosh',
      'exp',
      'expm1',
      'floor',
      'fround',
      'hypot',
      'imul',
      'log',
      'log1p',
      'log10',
      'log2',
      'max',
      'min',
      'pow',
      'random',
      'round',
      'sign',
      'sin',
      'sinh',
      'sqrt',
      'tan',
      'tanh',
      'trunc',
    ];

    for (final name in methodNames) {
      final method = math.getProperty(name);
      math.defineProperty(
        name,
        PropertyDescriptor(
          value: method,
          writable: true,
          enumerable: false,
          configurable: true,
        ),
      );
    }

    // Add Symbol.toStringTag = "Math"
    // This is required by ES6: Math[Symbol.toStringTag] === "Math"
    // The property has attributes { [[Writable]]: false, [[Enumerable]]: false, [[Configurable]]: true }
    math.defineProperty(
      JSSymbol.toStringTag.toString(),
      PropertyDescriptor(
        value: JSValueFactory.string('Math'),
        writable: false,
        enumerable: false,
        configurable: true,
      ),
    );

    return math;
  }
}
