/// Implementation of TextEncoder and TextDecoder APIs for JavaScript
/// These classes allow text encoding and decoding using different encodings
library;

import 'dart:convert';
import 'js_value.dart';
import 'native_functions.dart';

/// Implementation de TextEncoder
class TextEncoder {
  /// The encoding used (always UTF-8 for this implementation)
  final String encoding = 'utf-8';

  /// Encode a string of characters to Uint8Array (represented by a JSArray)
  JSValue encode(String input) {
    final bytes = utf8.encode(input);
    final array = JSArray();
    for (var i = 0; i < bytes.length; i++) {
      array.elements.add(JSValueFactory.number(bytes[i].toDouble()));
    }
    return array;
  }

  /// Encode a string into an existing buffer
  JSValue encodeInto(String source, JSValue destination) {
    if (!destination.isObject) {
      throw JSTypeError(
        'TextEncoder.encodeInto: destination must be an array-like object',
      );
    }

    final bytes = utf8.encode(source);
    final destArray = destination as JSObject;

    // For JavaScript arrays, we can write as much as we want
    // The limit is the size of the source data
    var read = 0;
    var written = 0;

    // Copy all bytes (or as much as possible from the source)
    for (var i = 0; i < bytes.length; i++) {
      destArray.setProperty(
        i.toString(),
        JSValueFactory.number(bytes[i].toDouble()),
      );
      read++;
      written++;
    }

    // Create the result object
    final result = JSObject();
    result.setProperty('read', JSValueFactory.number(read.toDouble()));
    result.setProperty('written', JSValueFactory.number(written.toDouble()));

    return result;
  }

  /// Create a TextEncoder constructor
  static JSValue createTextEncoderConstructor() {
    return JSNativeFunction(
      functionName: 'TextEncoder',
      nativeImpl: (args) {
        // Handle encoding options
        bool fatal = false;
        if (args.isNotEmpty && args[0].isObject) {
          final options = args[0] as JSObject;
          final fatalOption = options.getProperty('fatal');
          if (fatalOption.isBoolean) {
            fatal = fatalOption.toBoolean();
          }
        }

        return TextEncoderInstance(fatal: fatal);
      },
      expectedArgs: 0,
      isConstructor: true, // TextEncoder is a constructor
    );
  }
}

/// TextEncoder instance (JavaScript object)
class TextEncoderInstance extends JSObject {
  final TextEncoder _encoder = TextEncoder();

  TextEncoderInstance({bool fatal = false}) {
    // Property encoding
    setProperty('encoding', JSValueFactory.string(_encoder.encoding));

    // Method encode
    setProperty(
      'encode',
      JSNativeFunction(
        functionName: 'encode',
        nativeImpl: (args) {
          if (args.isEmpty) {
            return _encoder.encode('');
          }
          final input = args[0].toString();
          return _encoder.encode(input);
        },
      ),
    );

    // Method encodeInto
    setProperty(
      'encodeInto',
      JSNativeFunction(
        functionName: 'encodeInto',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError('TextEncoder.encodeInto requires 2 arguments');
          }
          final source = args[0].toString();
          final destination = args[1];
          return _encoder.encodeInto(source, destination);
        },
      ),
    );
  }
}

/// Implementation of TextDecoder
class TextDecoder {
  final String encoding;
  final bool fatal;
  final bool ignoreBOM;

  TextDecoder({
    this.encoding = 'utf-8',
    this.fatal = false,
    this.ignoreBOM = false,
  });

  /// Gets the appropriate decoder based on encoding
  static Encoding getEncoding(String encoding) {
    final enc = encoding.toLowerCase();
    switch (enc) {
      case 'utf-8':
      case 'utf8':
        return utf8;
      case 'latin1':
      case 'iso-8859-1':
        return latin1;
      case 'ascii':
      case 'us-ascii':
        return ascii;
      default:
        // For unsupported encodings, use UTF-8 with a warning
        // In production, we would raise an error
        return utf8;
    }
  }

  /// Checks if the encoding is supported
  static bool isEncodingSupported(String encoding) {
    final enc = encoding.toLowerCase();
    return enc == 'utf-8' ||
        enc == 'utf8' ||
        enc == 'latin1' ||
        enc == 'iso-8859-1' ||
        enc == 'ascii' ||
        enc == 'us-ascii';
  }

  /// Decode an array of bytes into a string
  JSValue decode([JSValue? input, JSValue? options]) {
    List<int> bytes;

    if (input == null || input.isUndefined) {
      // If no input, return an empty string
      return JSValueFactory.string('');
    }

    if (input.isObject) {
      final obj = input as JSObject;
      bytes = [];

      // Try to get the length
      final lengthProp = obj.getProperty('length');
      final length = lengthProp.isNumber ? lengthProp.toNumber().toInt() : 0;

      // Extract the bytes
      for (var i = 0; i < length; i++) {
        final value = obj.getProperty(i.toString());
        if (value.isNumber) {
          bytes.add(value.toNumber().toInt());
        }
      }
    } else {
      throw JSTypeError(
        'TextDecoder.decode: input must be an array-like object',
      );
    }

    try {
      final decoder = TextDecoder.getEncoding(encoding);
      String result;

      if (decoder == utf8) {
        // For UTF-8, manually handle allowMalformed
        if (fatal) {
          result = utf8.decode(bytes);
        } else {
          result = utf8.decode(bytes, allowMalformed: true);
        }
      } else {
        // For other encodings, decode normally
        result = decoder.decode(bytes);
      }

      return JSValueFactory.string(result);
    } catch (e) {
      if (fatal) {
        throw JSTypeError(
          'TextDecoder.decode: invalid ${encoding.toUpperCase()} sequence',
        );
      }
      // Try to decode with allowMalformed for UTF-8, otherwise fallback
      try {
        if (TextDecoder.getEncoding(encoding) == utf8) {
          return JSValueFactory.string(
            utf8.decode(bytes, allowMalformed: true),
          );
        } else {
          // For other encodings, return empty string on error
          return JSValueFactory.string('');
        }
      } catch (fallbackError) {
        return JSValueFactory.string('');
      }
    }
  }

  /// Create a TextDecoder constructor
  static JSValue createTextDecoderConstructor() {
    return JSNativeFunction(
      functionName: 'TextDecoder',
      nativeImpl: (args) {
        String encoding = 'utf-8';
        bool fatal = false;
        bool ignoreBOM = false;

        // Parse the arguments
        if (args.isNotEmpty) {
          if (args[0].isString) {
            encoding = args[0].toString().toLowerCase();
            // Check if the encoding is supported
            if (!TextDecoder.isEncodingSupported(encoding)) {
              throw JSTypeError(
                'TextDecoder: The "$encoding" encoding is not supported',
              );
            }
          }
        }

        if (args.length > 1 && args[1].isObject) {
          final options = args[1] as JSObject;
          final fatalOption = options.getProperty('fatal');
          if (fatalOption.isBoolean) {
            fatal = fatalOption.toBoolean();
          }

          final ignoreBOMOption = options.getProperty('ignoreBOM');
          if (ignoreBOMOption.isBoolean) {
            ignoreBOM = ignoreBOMOption.toBoolean();
          }
        }

        return TextDecoderInstance(
          encoding: encoding,
          fatal: fatal,
          ignoreBOM: ignoreBOM,
        );
      },
      expectedArgs: 0,
      isConstructor: true, // TextDecoder is a constructor
    );
  }
}

/// TextDecoder instance (JavaScript object)
class TextDecoderInstance extends JSObject {
  final TextDecoder _decoder;

  TextDecoderInstance({
    required String encoding,
    required bool fatal,
    required bool ignoreBOM,
  }) : _decoder = TextDecoder(
         encoding: encoding,
         fatal: fatal,
         ignoreBOM: ignoreBOM,
       ) {
    // Property encoding
    setProperty('encoding', JSValueFactory.string(_decoder.encoding));

    // Property fatal
    setProperty('fatal', JSValueFactory.boolean(_decoder.fatal));

    // Property ignoreBOM
    setProperty('ignoreBOM', JSValueFactory.boolean(_decoder.ignoreBOM));

    // Method decode
    setProperty(
      'decode',
      JSNativeFunction(
        functionName: 'decode',
        nativeImpl: (args) {
          JSValue? input;
          JSValue? options;

          if (args.isNotEmpty) {
            input = args[0];
          }
          if (args.length > 1) {
            options = args[1];
          }

          return _decoder.decode(input, options);
        },
      ),
    );
  }
}
