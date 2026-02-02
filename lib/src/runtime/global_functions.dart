/// Global functions for JavaScript runtime
/// Provides eval, parseInt, parseFloat, isNaN, isFinite and other global functions
library;

import 'dart:async';
import 'js_value.dart';
import 'native_functions.dart';
import '../evaluator/evaluator.dart';
import '../parser/parser.dart';
import 'message_system.dart';
import 'dart_value_converter.dart';

/// Helper function to convert Dart values to JSValue
JSValue _dartToJSValue(dynamic value) {
  if (value == null) return JSNull.instance;
  if (value is bool) return JSBoolean(value);
  if (value is int) return JSNumber(value.toDouble());
  if (value is double) return JSNumber(value);
  if (value is String) return JSString(value);
  if (value is JSValue) return value;

  // Handle Dart Map -> JSObject
  if (value is Map) {
    final jsObj = JSObject();
    value.forEach((key, val) {
      final keyStr = key.toString();
      final jsVal = _dartToJSValue(val);
      jsObj.setProperty(keyStr, jsVal);
    });
    return jsObj;
  }

  // Handle Dart List -> JSArray
  if (value is List) {
    final jsElements = value.map((item) => _dartToJSValue(item)).toList();
    return JSValueFactory.array(jsElements);
  }

  // For other types, convert to string
  return JSString(value.toString());
}

/// Helper function to convert JSValue to Dart values
/// JSObject is converted to Map, JSArray to List, etc.
dynamic _jsToDartValue(dynamic value) {
  if (value == null) return null;

  // Use the interpreter's robust converter
  if (value is JSValue) {
    return DartValueConverter.toDartValue(value);
  }

  // For native Dart values that come from elsewhere
  if (value is bool) return value;
  if (value is int) return value;
  if (value is double) {
    // Convert double to int if it's an integer number
    if (value == value.toInt()) {
      return value.toInt();
    }
    return value;
  }
  if (value is String) return value;
  if (value is List) return value.map((item) => _jsToDartValue(item)).toList();
  if (value is Map) return value.map((k, v) => MapEntry(k, _jsToDartValue(v)));

  // Fallback
  return value;
}

/// Manages active timeouts for setTimeout/clearTimeout functionality
class TimeoutManager {
  static final TimeoutManager _instance = TimeoutManager._internal();
  static TimeoutManager get instance => _instance;

  TimeoutManager._internal();

  final Map<int, Timer> _activeTimeouts = {};
  int _nextTimeoutId = 1;

  /// Schedules a timeout and returns its ID
  int setTimeout(void Function() callback, int delay) {
    final id = _nextTimeoutId++;
    final timer = Timer(Duration(milliseconds: delay), () {
      _activeTimeouts.remove(id);
      callback();
    });
    _activeTimeouts[id] = timer;
    return id;
  }

  /// Cancels a timeout by ID
  void clearTimeout(int id) {
    final timer = _activeTimeouts.remove(id);
    timer?.cancel();
  }

  /// Clears all active timeouts
  void clearAllTimeouts() {
    for (final timer in _activeTimeouts.values) {
      timer.cancel();
    }
    _activeTimeouts.clear();
  }
}

/// Global JavaScript functions implementation
class GlobalFunctions {
  final String? getInterpreterInstanceId;
  GlobalFunctions(this.getInterpreterInstanceId);
  static JSNativeFunction createEval() {
    return JSNativeFunction(
      functionName: 'eval',
      expectedArgs: 1, // eval takes 1 parameter
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSValueFactory.undefined();
        }

        final code = args[0].toString();

        try {
          // Get current evaluator instance
          final evaluator = JSEvaluator.currentInstance;
          if (evaluator == null) {
            throw JSError('eval() called without evaluator context');
          }

          // Parse and evaluate the code in current context
          // This uses evaluateDirectEval which checks for var/let conflicts
          final program = JSParser.parseString(code);
          return evaluator.evaluateDirectEval(program);
        } on JSException {
          // Re-throw JavaScript exceptions (including SyntaxErrors from var redeclaration)
          rethrow;
        } catch (e) {
          throw JSError('SyntaxError: $e');
        }
      },
    );
  }

  /// Creates parseInt() function
  static JSNativeFunction createParseInt() {
    return JSNativeFunction(
      functionName: 'parseInt',
      expectedArgs: 2,
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSValueFactory.number(double.nan);
        }

        final str = args[0].toString().trim();
        if (str.isEmpty) {
          return JSValueFactory.number(double.nan);
        }

        // Handle radix parameter
        int radix = 10;
        if (args.length > 1) {
          final radixArg = args[1].toNumber();
          if (radixArg.isNaN || radixArg == 0) {
            radix = 10;
          } else {
            radix = radixArg.floor();
            if (radix < 2 || radix > 36) {
              return JSValueFactory.number(double.nan);
            }
          }
        }

        // Auto-detect hex (0x) and octal (0) prefixes for radix 10
        String processedStr = str;
        if (radix == 10) {
          if (str.toLowerCase().startsWith('0x')) {
            radix = 16;
            processedStr = str.substring(2);
          } else if (str.startsWith('0') &&
              str.length > 1 &&
              RegExp(r'^[0-7]+$').hasMatch(str.substring(1))) {
            // Octal detection (legacy behavior)
            radix = 8;
            processedStr = str.substring(1);
          }
        }

        // Parse the number
        try {
          // Extract valid digits for the given radix
          final validChars = '0123456789abcdefghijklmnopqrstuvwxyz'.substring(
            0,
            radix,
          );
          String validPart = '';

          bool negative = false;
          int start = 0;

          if (processedStr.startsWith('-')) {
            negative = true;
            start = 1;
          } else if (processedStr.startsWith('+')) {
            start = 1;
          }

          for (int i = start; i < processedStr.length; i++) {
            final char = processedStr[i].toLowerCase();
            if (validChars.contains(char)) {
              validPart += char;
            } else {
              break; // Stop at first invalid character
            }
          }

          if (validPart.isEmpty) {
            return JSValueFactory.number(double.nan);
          }

          final result = int.tryParse(validPart, radix: radix);
          if (result == null) {
            return JSValueFactory.number(double.nan);
          }

          return JSValueFactory.number(
            (negative ? -result : result).toDouble(),
          );
        } catch (e) {
          return JSValueFactory.number(double.nan);
        }
      },
    );
  }

  /// Creates parseFloat() function
  static JSNativeFunction createParseFloat() {
    return JSNativeFunction(
      functionName: 'parseFloat',
      expectedArgs: 1,
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSValueFactory.number(double.nan);
        }

        final str = args[0].toString().trim();
        if (str.isEmpty) {
          return JSValueFactory.number(double.nan);
        }

        // Handle special values
        if (str == 'Infinity' || str == '+Infinity') {
          return JSValueFactory.number(double.infinity);
        }
        if (str == '-Infinity') {
          return JSValueFactory.number(double.negativeInfinity);
        }

        // Extract valid float part
        final floatRegex = RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?');
        final match = floatRegex.firstMatch(str);

        if (match == null) {
          return JSValueFactory.number(double.nan);
        }

        final validPart = match.group(0)!;
        final result = double.tryParse(validPart);

        return JSValueFactory.number(result ?? double.nan);
      },
    );
  }

  /// Creates isNaN() function
  static JSNativeFunction createIsNaN() {
    return JSNativeFunction(
      functionName: 'isNaN',
      expectedArgs: 1,
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSValueFactory.boolean(true);
        }

        final num = args[0].toNumber();
        return JSValueFactory.boolean(num.isNaN);
      },
    );
  }

  /// Creates isFinite() function
  static JSNativeFunction createIsFinite() {
    return JSNativeFunction(
      functionName: 'isFinite',
      expectedArgs: 1,
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSValueFactory.boolean(false);
        }

        final num = args[0].toNumber();
        return JSValueFactory.boolean(num.isFinite);
      },
    );
  }

  /// Creates encodeURI() function
  static JSNativeFunction createEncodeURI() {
    return JSNativeFunction(
      functionName: 'encodeURI',
      expectedArgs: 1,
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSValueFactory.string('undefined');
        }

        final str = args[0].toString();
        return JSValueFactory.string(Uri.encodeFull(str));
      },
    );
  }

  /// Creates decodeURI() function
  static JSNativeFunction createDecodeURI() {
    return JSNativeFunction(
      functionName: 'decodeURI',
      expectedArgs: 1,
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSValueFactory.string('undefined');
        }

        final str = args[0].toString();
        try {
          return JSValueFactory.string(Uri.decodeFull(str));
        } catch (e) {
          throw JSURIError('$e');
        }
      },
    );
  }

  /// Creates encodeURIComponent() function
  static JSNativeFunction createEncodeURIComponent() {
    return JSNativeFunction(
      functionName: 'encodeURIComponent',
      expectedArgs: 1,
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSValueFactory.string('undefined');
        }

        final str = args[0].toString();
        return JSValueFactory.string(Uri.encodeComponent(str));
      },
    );
  }

  /// Creates decodeURIComponent() function
  static JSNativeFunction createDecodeURIComponent() {
    return JSNativeFunction(
      functionName: 'decodeURIComponent',
      expectedArgs: 1,
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSValueFactory.string('undefined');
        }

        final str = args[0].toString();
        try {
          return JSValueFactory.string(Uri.decodeComponent(str));
        } catch (e) {
          throw JSURIError('$e');
        }
      },
    );
  }

  /// Creates sendMessage() function - returns the result
  JSNativeFunction createSendMessage() {
    return JSNativeFunction(
      functionName: 'sendMessage',
      nativeImpl: (args) {
        if (args.length < 2) {
          throw JSError(
            'sendMessage() requires at least 2 arguments: channelName and message',
          );
        }

        final channelName = args[0].toString();
        // Convert all remaining arguments to Dart values (JSObject -> Map, etc.)
        final messageArgs = args
            .sublist(1)
            .map((arg) => _jsToDartValue(arg))
            .toList();

        try {
          // Send message and return first result
          final result = MessageSystem(
            getInterpreterInstanceId,
          ).sendMessage(channelName, messageArgs);

          // If the result is a Dart exception, throw it
          if (result is Exception && result is! FormatException) {
            throw result;
          }

          return JSValueFactory.fromDart(result);
        } catch (error) {
          // Convert Dart exceptions to JavaScript JSError
          if (error is JSError) {
            rethrow;
          }
          throw JSError('sendMessage error: $error');
        }
      },
    );
  }

  /// Creates sendMessageAsync() function - async version that returns the result as Promise
  JSNativeFunction createSendMessageAsync() {
    return JSNativeFunction(
      functionName: 'sendMessageAsync',
      nativeImpl: (args) {
        if (args.length < 2) {
          throw JSError(
            'sendMessageAsync() requires at least 2 arguments: channelName and message',
          );
        }

        final channelName = args[0].toString();
        // Convert all remaining arguments to Dart values (JSObject -> Map, etc.)
        final messageArgs = args
            .sublist(1)
            .map((arg) => _jsToDartValue(arg))
            .toList();

        return JSPromise(
          JSNativeFunction(
            functionName: 'sendMessageAsyncExecutor',
            nativeImpl: (executorArgs) {
              if (executorArgs.length >= 2) {
                final resolve = executorArgs[0] as JSNativeFunction;
                final reject = executorArgs[1] as JSNativeFunction;

                // Execute the async operation and resolve/reject the promise
                MessageSystem(getInterpreterInstanceId)
                    .sendMessageAsync(channelName, messageArgs)
                    .then((result) {
                      // If the result is an exception, reject the promise
                      if (result is Exception && result is! FormatException) {
                        reject.call([JSValueFactory.string(result.toString())]);
                      } else {
                        final jsValue = _dartToJSValue(result);
                        resolve.call([jsValue]);
                      }
                    })
                    .catchError((error) {
                      // Reject the promise with the error message
                      final errorMessage = error is JSError
                          ? error.message
                          : error.toString();
                      reject.call([JSValueFactory.string(errorMessage)]);
                    });
              }
              return JSValueFactory.undefined();
            },
          ),
        );
        // }
      },
    );
  }

  /// Creates setTimeout() function
  static JSNativeFunction createSetTimeout() {
    return JSNativeFunction(
      functionName: 'setTimeout',
      expectedArgs: 2,
      nativeImpl: (args) {
        if (args.isEmpty) {
          throw JSError(
            'setTimeout() requires at least 1 argument: callback function',
          );
        }

        final callback = args[0];
        if (callback is! JSFunction && callback is! JSNativeFunction) {
          throw JSTypeError('setTimeout() first argument must be a function');
        }

        final delay = args.length > 1 ? args[1].toNumber().toInt() : 0;
        final additionalArgs = args.length > 2 ? args.sublist(2) : <JSValue>[];

        // Get current evaluator for function calls
        final evaluator = JSEvaluator.currentInstance;
        if (evaluator == null) {
          throw JSError('setTimeout() called without evaluator context');
        }

        // Schedule the callback to run after the delay
        final timeoutId = TimeoutManager.instance.setTimeout(() {
          try {
            // Call the callback function with additional arguments
            evaluator.callFunction(callback, additionalArgs);
          } catch (e) {
            // Log error but don't crash
            print('setTimeout callback error: $e');
          }
        }, delay);

        // Return the timeout ID
        return JSValueFactory.number(timeoutId.toDouble());
      },
    );
  }

  /// Creates clearTimeout() function
  static JSNativeFunction createClearTimeout() {
    return JSNativeFunction(
      functionName: 'clearTimeout',
      expectedArgs: 1,
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSValueFactory.undefined();
        }

        final timeoutId = args[0].toNumber().toInt();
        TimeoutManager.instance.clearTimeout(timeoutId);

        return JSValueFactory.undefined();
      },
    );
  }
}
