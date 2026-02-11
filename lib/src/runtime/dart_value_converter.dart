/// Converter JSValue -> Native Dart types
/// Converts JavaScript values to pure Dart types (int, double, String, bool, List, Map)
library;

import 'js_value.dart';

/// Class to convert JavaScript values to native Dart types
class DartValueConverter {
  /// Convert a JSValue to native Dart type
  /// - JSBoolean -> bool
  /// - JSNumber -> int or double
  /// - JSString -> String
  /// - JSArray -> List
  /// - JSObject -> Map
  /// - JSNull/JSUndefined -> null
  /// - Error objects -> Map with message, name, stack
  static dynamic toDartValue(JSValue value) {
    if (value is JSBoolean) {
      return value.toBoolean();
    }

    if (value is JSNumber) {
      final num = value.toNumber();
      // Convert to int if it's an integer number
      if (num == num.toInt()) {
        return num.toInt();
      }
      return num;
    }

    if (value is JSString) {
      return value.toString();
    }

    if (value is JSArray) {
      return _arrayToDartList(value);
    }

    if (value is JSObject) {
      // Check if it's an error object
      if (_isErrorObject(value)) {
        return _errorObjectToDartMap(value);
      }
      return _objectToDartMap(value);
    }

    if (value is JSNull || value is JSUndefined) {
      return null;
    }

    // Fallback for other types
    if (value is JSBigInt) {
      return value.value.toInt();
    }

    return null;
  }

  /// Verifies if an object is a JavaScript error object
  /// Only returns true for actual Error instances (prototype chain contains Error)
  static bool _isErrorObject(JSObject obj) {
    try {
      // Check if the 'name' property ends with 'Error' (Error, TypeError, RangeError, etc.)
      final name = obj.getProperty('name');
      if (!name.isUndefined && name.isString) {
        final nameStr = name.toString();
        if (nameStr.endsWith('Error')) {
          // Also verify it has a 'message' property (all Error instances do)
          final message = obj.getProperty('message');
          if (!message.isUndefined) {
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Converts an error object to a Map with all details
  static Map<String, dynamic> _errorObjectToDartMap(JSObject obj) {
    final map = <String, dynamic>{};

    try {
      // Recuperer les propertes principales de l'erreur
      final name = obj.getProperty('name');
      if (!name.isUndefined) {
        map['name'] = toDartValue(name);
      }

      final message = obj.getProperty('message');
      if (!message.isUndefined) {
        map['message'] = toDartValue(message);
      }

      final stack = obj.getProperty('stack');
      if (!stack.isUndefined) {
        map['stack'] = toDartValue(stack);
      }

      final code = obj.getProperty('code');
      if (!code.isUndefined) {
        map['code'] = toDartValue(code);
      }

      // Add the complete error character string
      final errorString = obj.toString();
      if (errorString.isNotEmpty && errorString != '[object Object]') {
        map['toString'] = errorString;
      } else {
        // If toString() returns [object Object], build manually
        final namePart = map['name'] ?? 'Error';
        final msgPart = map['message'] ?? '';
        map['toString'] = msgPart.isNotEmpty
            ? '$namePart: $msgPart'
            : namePart.toString();
      }
    } catch (e) {
      // Fallback if something fails
      map['error'] = 'Failed to convert error object';
    }

    return map;
  }

  /// Converts a JSArray to a List
  static List<dynamic> _arrayToDartList(JSArray array) {
    return array.elements.map((element) => toDartValue(element)).toList();
  }

  /// Converts a JSObject to a Map (iterates over all actual properties)
  static Map<String, dynamic> _objectToDartMap(JSObject obj, {int depth = 0}) {
    // Guard against overly deep recursion (circular references)
    if (depth > 10) {
      return {'__toString__': obj.toString()};
    }

    final map = <String, dynamic>{};

    try {
      // Get all own enumerable property names from the object
      final keys = obj.getPropertyNames(enumerableOnly: true);

      for (final key in keys) {
        try {
          final value = obj.getProperty(key);
          if (value.isUndefined) continue;

          // Skip functions (methods like toString, valueOf, etc.)
          if (value.isFunction) continue;

          // Convert value recursively
          if (value is JSNull) {
            map[key] = null;
          } else if (value is JSBoolean) {
            map[key] = value.toBoolean();
          } else if (value is JSNumber) {
            final num = value.toNumber();
            map[key] = (num == num.toInt()) ? num.toInt() : num;
          } else if (value is JSString) {
            map[key] = value.toString();
          } else if (value is JSArray) {
            map[key] = _arrayToDartList(value);
          } else if (value is JSObject) {
            // Recurse into nested objects
            if (_isErrorObject(value)) {
              map[key] = _errorObjectToDartMap(value);
            } else {
              map[key] = _objectToDartMap(value, depth: depth + 1);
            }
          } else if (value is JSBigInt) {
            map[key] = value.value.toInt();
          }
        } catch (e) {
          // Ignore inaccessible properties
        }
      }
    } catch (e) {
      // Fallback: return a map with the string representation
      map['__error__'] = 'Failed to convert object';
      map['__toString__'] = obj.toString();
    }

    return map;
  }

  /// Converts multiple JSValues to a list of Dart values
  static List<dynamic> toDartValues(List<JSValue> values) {
    return values.map((v) => toDartValue(v)).toList();
  }

  /// Converts a JSValue to String (with special error handling)
  static String toDartString(JSValue value) {
    // Special handling for error objects
    if (value is JSObject && _isErrorObject(value)) {
      try {
        final name = value.getProperty('name');
        final message = value.getProperty('message');

        final nameStr = !name.isUndefined ? name.toString() : 'Error';
        final msgStr = !message.isUndefined ? message.toString() : '';

        return msgStr.isNotEmpty ? '$nameStr: $msgStr' : nameStr;
      } catch (e) {
        return value.toString();
      }
    }

    // For other objects
    final converted = toDartValue(value);
    if (converted is Map && converted.containsKey('__toString__')) {
      return converted['__toString__'].toString();
    }

    return converted.toString();
  }

  /// Converts a JSValue to int (with automatic conversion)
  static int toDartInt(JSValue value) {
    if (value is JSNumber) {
      return value.toNumber().toInt();
    }
    if (value is JSString) {
      return int.tryParse(value.toString()) ?? 0;
    }
    if (value is JSBoolean) {
      return value.toBoolean() ? 1 : 0;
    }
    return 0;
  }

  /// Converts a JSValue to double (with automatic conversion)
  static double toDartDouble(JSValue value) {
    if (value is JSNumber) {
      return value.toNumber();
    }
    if (value is JSString) {
      return double.tryParse(value.toString()) ?? 0.0;
    }
    if (value is JSBoolean) {
      return value.toBoolean() ? 1.0 : 0.0;
    }
    return 0.0;
  }

  /// Converts a JSValue to bool
  static bool toDartBool(JSValue value) {
    if (value is JSBoolean) {
      return value.toBoolean();
    }
    if (value is JSNumber) {
      final num = value.toNumber();
      return num != 0 && !num.isNaN;
    }
    if (value is JSString) {
      return value.toString().isNotEmpty;
    }
    if (value is JSNull || value is JSUndefined) {
      return false;
    }
    if (value is JSArray || value is JSObject) {
      return true;
    }
    return false;
  }
}
