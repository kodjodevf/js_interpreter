/// JSON Object implementation for JavaScript
/// Provides JSON.parse() and JSON.stringify() functionality
library;

import 'dart:convert';
import 'package:js_interpreter/js_interpreter.dart';

/// JavaScript JSON Object implementation
class JSONObject {
  /// ES2019: Custom JSON stringify that properly escapes unpaired surrogates
  static String _customJsonStringify(dynamic value, String? spacer, int depth) {
    if (value == null) {
      return 'null';
    } else if (value is bool) {
      return value.toString();
    } else if (value is num) {
      // ES2019: Format numbers properly - remove .0 from integers
      if (value.isFinite) {
        if (value == value.toInt()) {
          return value.toInt().toString();
        }
        return value.toString();
      } else if (value.isNaN) {
        return 'null'; // JSON doesn't support NaN
      } else {
        return 'null'; // JSON doesn't support Infinity
      }
    } else if (value is String) {
      return _escapeJsonString(value);
    } else if (value is List) {
      final indent = spacer != null ? spacer * (depth + 1) : null;
      final newline = spacer != null ? '\n' : '';
      final innerIndent = spacer != null ? spacer * depth : '';

      if (value.isEmpty) return '[]';

      final buffer = StringBuffer('[');
      if (spacer != null) buffer.write(newline);

      for (int i = 0; i < value.length; i++) {
        if (spacer != null) buffer.write(indent);
        buffer.write(_customJsonStringify(value[i], spacer, depth + 1));
        if (i < value.length - 1) buffer.write(',');
        if (spacer != null) buffer.write(newline);
      }

      if (spacer != null) buffer.write(innerIndent);
      buffer.write(']');
      return buffer.toString();
    } else if (value is Map) {
      final indent = spacer != null ? spacer * (depth + 1) : null;
      final newline = spacer != null ? '\n' : '';
      final innerIndent = spacer != null ? spacer * depth : '';

      if (value.isEmpty) return '{}';

      final buffer = StringBuffer('{');
      if (spacer != null) buffer.write(newline);

      final entries = value.entries.toList();
      for (int i = 0; i < entries.length; i++) {
        final entry = entries[i];
        if (spacer != null) buffer.write(indent);
        buffer.write(_escapeJsonString(entry.key.toString()));
        buffer.write(':');
        if (spacer != null) buffer.write(' ');
        buffer.write(_customJsonStringify(entry.value, spacer, depth + 1));
        if (i < entries.length - 1) buffer.write(',');
        if (spacer != null) buffer.write(newline);
      }

      if (spacer != null) buffer.write(innerIndent);
      buffer.write('}');
      return buffer.toString();
    }
    return 'null';
  }

  /// ES2019: Escape a string for JSON with proper surrogate handling
  static String _escapeJsonString(String str) {
    final buffer = StringBuffer('"');

    for (int i = 0; i < str.length; i++) {
      final code = str.codeUnitAt(i);

      // Check for unpaired surrogates (0xD800-0xDFFF)
      if (code >= 0xD800 && code <= 0xDFFF) {
        // Check if it's part of a valid surrogate pair
        if (code >= 0xD800 && code <= 0xDBFF && i + 1 < str.length) {
          // High surrogate - check if followed by low surrogate
          final nextCode = str.codeUnitAt(i + 1);
          if (nextCode >= 0xDC00 && nextCode <= 0xDFFF) {
            // Valid surrogate pair - keep as is
            buffer.write(str[i]);
            buffer.write(str[i + 1]);
            i++; // Skip next character
            continue;
          }
        }
        // Unpaired surrogate - escape it
        buffer.write(
          '\\u${code.toRadixString(16).toUpperCase().padLeft(4, '0')}',
        );
        continue;
      }

      // Standard JSON escaping
      switch (str[i]) {
        case '"':
          buffer.write('\\"');
          break;
        case '\\':
          buffer.write('\\\\');
          break;
        case '\b':
          buffer.write('\\b');
          break;
        case '\f':
          buffer.write('\\f');
          break;
        case '\n':
          buffer.write('\\n');
          break;
        case '\r':
          buffer.write('\\r');
          break;
        case '\t':
          buffer.write('\\t');
          break;
        default:
          if (code < 0x20) {
            // Control characters
            buffer.write('\\u${code.toRadixString(16).padLeft(4, '0')}');
          } else {
            buffer.write(str[i]);
          }
      }
    }

    buffer.write('"');
    return buffer.toString();
  }

  /// Function executor for calling JavaScript functions
  static FunctionExecutor? _functionExecutor;

  /// Sets the function executor (called by evaluator)
  static void setFunctionExecutor(FunctionExecutor executor) {
    _functionExecutor = executor;
  }

  /// Creates the global JSON object
  static JSObject createJSONObject() {
    final jsonObject = JSObject();

    // JSON.parse(text[, reviver])
    jsonObject.setProperty(
      'parse',
      JSNativeFunction(
        functionName: 'parse',
        expectedArgs: 2,
        nativeImpl: (args) {
          if (args.isEmpty) {
            final evaluator = JSEvaluator.currentInstance;
            if (evaluator != null) {
              evaluator.throwJSSyntaxError('Unexpected end of JSON input');
            } else {
              throw JSError('SyntaxError: Unexpected end of JSON input');
            }
          }

          final text = args[0].toString();
          final reviver = args.length > 1 ? args[1] : null;

          try {
            final jsValue = _dartToJSValue(jsonDecode(text));

            if (reviver != null &&
                (reviver is JSNativeFunction || reviver is JSFunction)) {
              return _applyReviver(jsValue, reviver, '');
            }

            return jsValue;
          } catch (e) {
            final evaluator = JSEvaluator.currentInstance;
            if (evaluator != null) {
              // Extract the actual error message from Dart's jsonDecode error
              String errorMsg = e.toString();
              // Clean up the error message if it has 'FormatException:' prefix
              if (errorMsg.contains('FormatException:')) {
                errorMsg = errorMsg.replaceFirst('FormatException: ', '');
              }
              evaluator.throwJSSyntaxError(errorMsg);
            } else {
              throw JSError('SyntaxError: $e');
            }
          }
        },
      ),
    );

    // JSON.stringify(value[, replacer[, space]])
    jsonObject.setProperty(
      'stringify',
      JSNativeFunction(
        functionName: 'stringify',
        expectedArgs: 3,
        nativeImpl: (args) {
          if (args.isEmpty) {
            return JSValueFactory.undefined();
          }

          final value = args[0];
          final replacer = args.length > 1 ? args[1] : null;
          final space = args.length > 2 ? args[2] : null;

          // Handle special case: undefined should return undefined
          if (value.isUndefined) {
            return JSValueFactory.undefined();
          }

          try {
            // Convert JSValue to Dart object
            dynamic dartValue = _jsValueToDart(value, replacer);

            // Handle special case where dartValue is null
            if (dartValue == null) {
              // For JSNull, we should continue to stringify as "null"
              if (value.isNull) {
                // JSNull should become JSON "null"
                dartValue = null; // This is correct for JSON encoding
              } else if (value.isNumber) {
                // For NaN and Infinity at root level, return "null" string
                final num = value.toNumber();
                if (num.isNaN || num.isInfinite) {
                  return JSValueFactory.string('null');
                }
                // Other numbers that became null shouldn't happen
                return JSValueFactory.undefined();
              } else {
                // For undefined/function/symbol, return undefined
                return JSValueFactory.undefined();
              }
            }

            // Handle space parameter for pretty printing
            String? spacer;
            if (space != null) {
              if (space.isNumber) {
                final spaceNum = space.toNumber().floor().clamp(0, 10);
                spacer = ' ' * spaceNum;
              } else if (space.isString) {
                spacer = space.toString().substring(
                  0,
                  space.toString().length.clamp(0, 10),
                );
              }
            }

            // ES2019: Custom JSON encoding to handle unpaired surrogates
            String jsonResult = _customJsonStringify(dartValue, spacer, 0);

            return JSValueFactory.string(jsonResult);
          } catch (e) {
            // Laisser passer les JSError (comme circular references)
            if (e is JSError) {
              rethrow;
            }
            return JSValueFactory.undefined();
          }
        },
      ),
    );

    return jsonObject;
  }

  /// Convert Dart object to JSValue
  static JSValue _dartToJSValue(dynamic dartValue) {
    if (dartValue == null) {
      return JSValueFactory.nullValue();
    } else if (dartValue is bool) {
      return JSValueFactory.boolean(dartValue);
    } else if (dartValue is num) {
      return JSValueFactory.number(dartValue.toDouble());
    } else if (dartValue is String) {
      return JSValueFactory.string(dartValue);
    } else if (dartValue is List) {
      final List<JSValue> jsElements = [];
      for (final element in dartValue) {
        jsElements.add(_dartToJSValue(element));
      }
      return JSValueFactory.array(jsElements);
    } else if (dartValue is Map<String, dynamic>) {
      final jsObject = JSObject();
      dartValue.forEach((key, value) {
        jsObject.setProperty(key, _dartToJSValue(value));
      });
      return jsObject;
    } else {
      // Fallback for other types
      return JSValueFactory.string(dartValue.toString());
    }
  }

  /// Convert JSValue to Dart object with replacer support
  static dynamic _jsValueToDart(JSValue jsValue, JSValue? replacer) {
    final Set<JSValue> visited = <JSValue>{};

    // If we have a replacer function, create a wrapper object to call it on the root
    if (replacer != null &&
        (replacer is JSNativeFunction || replacer is JSFunction)) {
      final wrapper = JSObject();
      wrapper.setProperty('', jsValue);
      final result = _jsValueToDartRecursive(wrapper, replacer, '', visited);
      if (result is Map<String, dynamic> && result.containsKey('')) {
        return result[''];
      }
      return result;
    }

    return _jsValueToDartRecursive(jsValue, replacer, '', visited);
  }

  /// Convert JSValue to native Dart types (public API)
  /// Recursively converts JSObjects to Maps, JSArrays to Lists, etc.
  static dynamic jsValueToDart(JSValue jsValue) {
    return _jsValueToDart(jsValue, null);
  }

  /// Recursive implementation with circular reference detection
  static dynamic _jsValueToDartRecursive(
    JSValue jsValue,
    JSValue? replacer,
    String key,
    Set<JSValue> visited,
  ) {
    // Detect circular references
    if (jsValue is JSObject && visited.contains(jsValue)) {
      throw JSError('TypeError: Converting circular structure to JSON');
    }

    if (jsValue.isUndefined || jsValue.isFunction || jsValue.isSymbol) {
      return null; // These are not serialized in JSON
    } else if (jsValue.isNull) {
      return null;
    } else if (jsValue.isBoolean) {
      return jsValue.toBoolean();
    } else if (jsValue.isNumber) {
      final num = jsValue.toNumber();
      if (num.isNaN || num.isInfinite) {
        return null;
      }
      return num;
    } else if (jsValue.isString) {
      // Return string as-is - will be handled by JSON encoder
      return jsValue.toString();
    } else if (jsValue is JSArray) {
      visited.add(jsValue);

      final List<dynamic> result = [];
      final length = jsValue.length;
      for (int i = 0; i < length; i++) {
        final element = jsValue.getProperty(i.toString());

        // Apply replacer function to each element
        JSValue processedElement = element;
        if (replacer != null &&
            (replacer is JSNativeFunction || replacer is JSFunction)) {
          try {
            if (replacer is JSNativeFunction) {
              processedElement = replacer.nativeImpl([
                JSValueFactory.number(i.toDouble()),
                element,
              ]);
            } else if (_functionExecutor != null) {
              processedElement = _functionExecutor!(replacer, [
                JSValueFactory.number(i.toDouble()),
                element,
              ]);
            }
          } catch (e) {
            processedElement = element;
          }
        }

        final converted = _jsValueToDartRecursive(
          processedElement,
          replacer,
          i.toString(),
          visited,
        );

        // In arrays, undefined elements should become null in JSON
        // Don't skip - add all elements (undefined becomes null via conversion)
        result.add(converted);
      }

      visited.remove(jsValue);
      return result;
    } else if (jsValue is JSObject) {
      visited.add(jsValue);

      // Check if it's a Date object - call toISOString() if available
      if (jsValue.hasProperty('toISOString')) {
        try {
          final toISOString = jsValue.getProperty('toISOString');
          if (toISOString is JSNativeFunction) {
            final isoString = toISOString.nativeImpl([]);
            visited.remove(jsValue);
            return isoString.toString();
          }
        } catch (e) {
          // Fall through to regular object handling
        }
      }

      final Map<String, dynamic> result = {};

      // Get properties to process (filtered by replacer if it's an array)
      List<String> keysToProcess = jsValue.getPropertyNames().toList();

      if (replacer != null && replacer is JSArray) {
        // Filter keys based on replacer array
        final allowedKeys = <String>{};
        for (int i = 0; i < replacer.length; i++) {
          final keyValue = replacer.getProperty(i.toString());
          if (keyValue.isString || keyValue.isNumber) {
            allowedKeys.add(keyValue.toString());
          }
        }
        keysToProcess = keysToProcess
            .where((key) => allowedKeys.contains(key))
            .toList();
      }

      // Process each allowed property
      for (final propKey in keysToProcess) {
        final value = jsValue.getProperty(propKey);

        // Apply replacer function to property
        JSValue processedValue = value;
        if (replacer != null &&
            (replacer is JSNativeFunction || replacer is JSFunction)) {
          try {
            if (replacer is JSNativeFunction) {
              processedValue = replacer.nativeImpl([
                JSValueFactory.string(propKey),
                value,
              ]);
            } else if (_functionExecutor != null) {
              processedValue = _functionExecutor!(replacer, [
                JSValueFactory.string(propKey),
                value,
              ]);
            }
          } catch (e) {
            processedValue = value;
          }
        }

        // Skip only undefined values and functions after replacer processing
        if (!processedValue.isUndefined && !processedValue.isFunction) {
          final converted = _jsValueToDartRecursive(
            processedValue,
            replacer,
            propKey,
            visited,
          );
          // Include null values explicitly, exclude only undefined->null conversions
          if (converted != null || processedValue.isNull) {
            result[propKey] = converted;
          }
        }
      }

      visited.remove(jsValue);
      return result;
    } else {
      return jsValue.toString();
    }
  }

  /// Apply reviver function to parsed JSON
  static JSValue _applyReviver(JSValue value, JSValue reviver, String key) {
    if (value is JSObject) {
      if (value is JSArray) {
        // Process array elements first
        final length = value.length;
        final keysToRemove = <String>[];

        for (int i = 0; i < length; i++) {
          final keyStr = i.toString();
          final element = value.getProperty(keyStr);
          final transformed = _applyReviver(element, reviver, keyStr);

          if (transformed.isUndefined) {
            keysToRemove.add(keyStr);
          } else {
            // For arrays, directly modify the elements array
            try {
              value.elements[i] = transformed;
            } catch (e) {
              // Fallback to setProperty
              value.setProperty(keyStr, transformed);
            }
          }
        }

        // Remove undefined elements from sparse arrays
        // Arrays maintain sparse structure for undefined values
        // for (final k in keysToRemove) {
        //   value.deleteProperty(k);
        // }
      } else {
        // Process object properties first
        final keysToRemove = <String>[];
        final propertyNames = value.getPropertyNames().toList();

        for (final propKey in propertyNames) {
          final propValue = value.getProperty(propKey);
          final transformed = _applyReviver(propValue, reviver, propKey);

          if (transformed.isUndefined) {
            keysToRemove.add(propKey);
          } else {
            value.setProperty(propKey, transformed);
          }
        }

        // Remove undefined properties
        for (final k in keysToRemove) {
          value.deleteProperty(k);
        }
      }
    }

    // Apply reviver to current value
    try {
      if (reviver is JSNativeFunction) {
        final result = reviver.nativeImpl([JSValueFactory.string(key), value]);
        return result;
      } else if (_functionExecutor != null) {
        final result = _functionExecutor!(reviver, [
          JSValueFactory.string(key),
          value,
        ]);
        return result;
      }
      return value;
    } catch (e) {
      return value; // Return original on error
    }
  }
}
