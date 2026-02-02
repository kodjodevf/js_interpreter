/// Prototype for JavaScript BigInt
/// Implements methods available on BigInt
library;

import 'js_value.dart';
import 'native_functions.dart';

/// Prototype pour les BigInt
class BigIntPrototype {
  /// Retrieve a property on a BigInt (auto-boxing)
  static JSValue getBigIntProperty(BigInt bigint, String propertyName) {
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
            }

            // Get the BigInt from the first argument (this)
            BigInt bigint;
            if (args.isNotEmpty && args[0].isBigInt) {
              bigint = (args[0] as JSBigInt).value;
            } else {
              throw JSTypeError('toString called on non-BigInt value');
            }

            // Convert to string according to the base
            String result;
            switch (radix) {
              case 2:
                result = bigint.toRadixString(2);
                break;
              case 8:
                result = bigint.toRadixString(8);
                break;
              case 10:
                result = bigint.toString();
                break;
              case 16:
                result = bigint.toRadixString(16).toLowerCase();
                break;
              default:
                // For other bases, use toRadixString
                result = bigint.toRadixString(radix);
            }

            return JSValueFactory.string(result);
          },
        );

      case 'valueOf':
        return JSNativeFunction(
          functionName: 'valueOf',
          nativeImpl: (args) {
            // Return the BigInt itself
            if (args.isNotEmpty && args[0].isBigInt) {
              return args[0];
            } else {
              throw JSTypeError('valueOf called on non-BigInt value');
            }
          },
        );

      case 'toLocaleString':
        return JSNativeFunction(
          functionName: 'toLocaleString',
          nativeImpl: (args) {
            // Complete implementation of toLocaleString for BigInt
            if (args.isNotEmpty && args[0].isBigInt) {
              final bigint = (args[0] as JSBigInt).value;

              // In JavaScript, toLocaleString uses Intl.NumberFormat
              final formatted = _formatBigIntLocale(bigint, args.sublist(1));
              return JSValueFactory.string(formatted);
            } else {
              throw JSTypeError('toLocaleString called on non-BigInt value');
            }
          },
        );

      default:
        // Property not found
        return JSValueFactory.undefined();
    }
  }

  /// Format a BigInt according to locales (simplified implementation)
  static String _formatBigIntLocale(BigInt value, List<JSValue> options) {
    final str = value.toString();

    // Add thousand separators for readability
    if (str.length > 3) {
      final buffer = StringBuffer();
      for (int i = 0; i < str.length; i++) {
        if (i > 0 && (str.length - i) % 3 == 0) {
          buffer.write(',');
        }
        buffer.write(str[i]);
      }
      return buffer.toString();
    }

    return str;
  }
}
