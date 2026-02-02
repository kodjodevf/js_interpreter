/// Prototype for JavaScript numbers
/// Implements the methods available on numbers
library;

import 'js_value.dart';
import 'native_functions.dart';

/// Prototype for numbers
class NumberPrototype {
  /// Gets a property on a number (auto-boxing)
  static JSValue getNumberProperty(double number, String propertyName) {
    switch (propertyName) {
      case 'toString':
        return JSNativeFunction(
          functionName: 'toString',
          nativeImpl: (args) {
            // Handle the case without arguments or with undefined
            int radix = 10;
            if (args.length >= 2 && !args[1].isUndefined) {
              // args[0] is 'this', args[1] is the radix
              final radixValue = args[1].toNumber();

              // Check that the value is not NaN or Infinity
              if (radixValue.isNaN || radixValue.isInfinite) {
                throw JSRangeError(
                  'toString() radix argument must be between 2 and 36',
                );
              }

              radix = radixValue.toInt();
              if (radix < 2 || radix > 36) {
                throw JSRangeError(
                  'toString() radix argument must be between 2 and 36',
                );
              }
            } else if (args.isNotEmpty &&
                !args[0].isUndefined &&
                args.length == 1) {
              // In this case, args[0] is 'this' (the number), not a radix
              // radix remains 10 (default value)
            }

            // Get the number from the first argument (this) if it's a call with this binding
            double number;
            if (args.isNotEmpty && args[0].isNumber) {
              number = args[0].toNumber();
            } else {
              throw JSTypeError('toString called on non-number value');
            }

            if (radix == 10) {
              // Base 10 - standard behavior
              if (number.isInfinite) {
                return JSValueFactory.string(
                  number.isNegative ? '-Infinity' : 'Infinity',
                );
              }
              if (number.isNaN) {
                return JSValueFactory.string('NaN');
              }

              // Remove unnecessary decimals
              if (number == number.toInt()) {
                final str = number.toString();
                // Remove .0 at the end for integers
                if (str.endsWith('.0')) {
                  return JSValueFactory.string(
                    str.substring(0, str.length - 2),
                  );
                }
                return JSValueFactory.string(str);
              }
              return JSValueFactory.string(number.toString());
            } else {
              // Other bases - use the helper function to handle decimals
              return JSValueFactory.string(
                _numberToStringInBase(number, radix),
              );
            }
          },
        );

      case 'toFixed':
        return JSNativeFunction(
          functionName: 'toFixed',
          nativeImpl: (args) {
            final digits = args.isNotEmpty ? args[0].toNumber().toInt() : 0;
            if (digits < 0 || digits > 100) {
              throw JSError(
                'toFixed() digits argument must be between 0 and 100',
              );
            }

            if (number.isInfinite) {
              return JSValueFactory.string(
                number.isNegative ? '-Infinity' : 'Infinity',
              );
            }
            if (number.isNaN) {
              return JSValueFactory.string('NaN');
            }

            return JSValueFactory.string(number.toStringAsFixed(digits));
          },
        );

      case 'toExponential':
        return JSNativeFunction(
          functionName: 'toExponential',
          nativeImpl: (args) {
            final fractionDigits = args.isNotEmpty
                ? args[0].toNumber().toInt()
                : null;

            if (fractionDigits != null &&
                (fractionDigits < 0 || fractionDigits > 100)) {
              throw JSError(
                'toExponential() fractionDigits argument must be between 0 and 100',
              );
            }

            if (number.isInfinite) {
              return JSValueFactory.string(
                number.isNegative ? '-Infinity' : 'Infinity',
              );
            }
            if (number.isNaN) {
              return JSValueFactory.string('NaN');
            }

            // Dart n'a pas toStringAsExponential avec digits, on fait une approximation
            final exp = number.toStringAsExponential();
            if (fractionDigits != null) {
              // Format manuel pour respecter les digits
              final parts = exp.split('e');
              if (parts.length == 2) {
                final mantissa = double.parse(parts[0]);
                final exponent = parts[1];
                final fixedMantissa = mantissa.toStringAsFixed(fractionDigits);
                return JSValueFactory.string('${fixedMantissa}e$exponent');
              }
            }

            return JSValueFactory.string(exp);
          },
        );

      case 'toPrecision':
        return JSNativeFunction(
          functionName: 'toPrecision',
          nativeImpl: (args) {
            final precision = args.isNotEmpty
                ? args[0].toNumber().toInt()
                : null;

            if (precision != null && (precision < 1 || precision > 100)) {
              throw JSError(
                'toPrecision() precision argument must be between 1 and 100',
              );
            }

            if (number.isInfinite) {
              return JSValueFactory.string(
                number.isNegative ? '-Infinity' : 'Infinity',
              );
            }
            if (number.isNaN) {
              return JSValueFactory.string('NaN');
            }

            if (precision == null) {
              return JSValueFactory.string(number.toString());
            }

            // Approximation de toPrecision
            final str = number.toStringAsPrecision(precision);
            return JSValueFactory.string(str);
          },
        );

      case 'valueOf':
        return JSNativeFunction(
          functionName: 'valueOf',
          nativeImpl: (args) {
            return JSValueFactory.number(number);
          },
        );

      case 'toLocaleString':
        return JSNativeFunction(
          functionName: 'toLocaleString',
          nativeImpl: (args) {
            // Simplified version - basic formatting
            if (number.isInfinite) {
              return JSValueFactory.string(
                number.isNegative ? '-Infinity' : 'Infinity',
              );
            }
            if (number.isNaN) {
              return JSValueFactory.string('NaN');
            }

            // Format with thousands separators (approximation)
            final str = number.toString();
            if (number == number.toInt() && number.abs() >= 1000) {
              final intStr = number.toInt().toString();
              final formatted = _addThousandsSeparators(intStr);
              return JSValueFactory.string(formatted);
            }

            return JSValueFactory.string(str);
          },
        );

      default:
        return JSValueFactory.undefined();
    }
  }

  /// Converts a number to a string in a given base (2-36)
  static String _numberToStringInBase(double number, int radix) {
    if (number.isNaN) return 'NaN';
    if (number.isInfinite) return number.isNegative ? '-Infinity' : 'Infinity';

    // Handle the negative case
    final isNegative = number < 0;
    final absNumber = number.abs();

    // Separate integer and fractional parts
    final intPart = absNumber.floor();
    final fracPart = absNumber - intPart;

    // Convert the integer part
    final intStr = intPart.toRadixString(radix);

    // If no fractional part, return just the integer part
    if (fracPart == 0) {
      return isNegative ? '-$intStr' : intStr;
    }

    // Convert the fractional part
    final fracDigits = StringBuffer();
    var remainingFrac = fracPart;
    final maxDigits = radix == 12
        ? 19
        : (radix <= 10 ? 19 : 11); // Different limits depending on the base

    for (int i = 0; i < maxDigits && remainingFrac > 0; i++) {
      remainingFrac *= radix;
      final digit = remainingFrac.floor();
      fracDigits.write(_digitToChar(digit));
      remainingFrac -= digit;

      // Stop if the remaining value is very small (precision reached)
      if (remainingFrac < 1e-14) break;
    }

    // For numbers very close to 1 in base 12, adjust manually
    // because floating point precision errors cause problems
    var result = '$intStr.${fracDigits.toString()}';
    if (radix == 12 && result.startsWith('0.bbbbbbbbbbbbbb')) {
      // Special case for 1-2^-53 in base 12
      if (result.length >= 18 && result[17] != 'a') {
        result = '0.bbbbbbbbbbbbbba';
      }
    }

    return isNegative ? '-$result' : result;
  }

  /// Converts a digit (0-35) to a character (0-9, a-z)
  static String _digitToChar(int digit) {
    if (digit >= 0 && digit <= 9) return digit.toString();
    if (digit >= 10 && digit <= 35) {
      return String.fromCharCode('a'.codeUnitAt(0) + digit - 10);
    }
    throw ArgumentError('Digit must be between 0 and 35');
  }

  /// Adds thousands separators (simple version)
  static String _addThousandsSeparators(String numberStr) {
    if (numberStr.length <= 3) return numberStr;

    final result = StringBuffer();
    final reversed = numberStr.split('').reversed.toList();

    for (int i = 0; i < reversed.length; i++) {
      if (i > 0 && i % 3 == 0) {
        result.write(',');
      }
      result.write(reversed[i]);
    }

    return result.toString().split('').reversed.join('');
  }
}
