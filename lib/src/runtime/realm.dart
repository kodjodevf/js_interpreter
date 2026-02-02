/// JavaScript Realm implementation
/// A Realm represents a distinct global environment for JavaScript execution.
/// Each Realm has its own set of intrinsic objects (Object, Array, Error, etc.)
library;

import 'js_value.dart';
import 'native_functions.dart';
import '../evaluator/evaluator.dart';
import '../parser/parser.dart';

/// Represents a JavaScript Realm - an isolated execution environment
/// with its own global object and intrinsic objects.
class JSRealm {
  /// The evaluator for this realm
  late final JSEvaluator _evaluator;

  /// The global object for this realm
  late final JSObject _globalObject;

  /// Create a new Realm with fresh global environment
  JSRealm() {
    _evaluator = JSEvaluator();
    _globalObject = _createGlobalObject();
  }

  /// Get the global object for this realm
  JSObject get global => _globalObject;

  /// Get the evaluator for this realm
  JSEvaluator get evaluator => _evaluator;

  /// Evaluate code in this realm
  JSValue eval(String code) {
    // Save current instance
    final previousInstance = JSEvaluator.currentInstance;

    try {
      // Set this realm's evaluator as current
      JSEvaluator.setCurrentInstance(_evaluator);

      return _evaluator.evaluate(JSParser.parseString(code));
    } finally {
      // Restore previous instance
      if (previousInstance != null) {
        JSEvaluator.setCurrentInstance(previousInstance);
      }
    }
  }

  /// Creates the global object with all built-in constructors
  JSObject _createGlobalObject() {
    final globalObj = JSObject();

    // Get all the built-in constructors from the evaluator's global environment
    final env = _evaluator.globalEnvironment;

    // Standard built-in constructors
    final builtins = [
      'Object',
      'Array',
      'Function',
      'Boolean',
      'Number',
      'String',
      'Symbol',
      'Error',
      'TypeError',
      'ReferenceError',
      'SyntaxError',
      'RangeError',
      'EvalError',
      'URIError',
      'AggregateError',
      'Date',
      'RegExp',
      'Map',
      'Set',
      'WeakMap',
      'WeakSet',
      'Promise',
      'Proxy',
      'ArrayBuffer',
      'DataView',
      'Int8Array',
      'Uint8Array',
      'Uint8ClampedArray',
      'Int16Array',
      'Uint16Array',
      'Int32Array',
      'Uint32Array',
      'Float32Array',
      'Float64Array',
      'BigInt64Array',
      'BigUint64Array',
      'BigInt',
    ];

    for (final name in builtins) {
      try {
        final value = env.get(name);
        globalObj.setProperty(name, value);
      } catch (_) {
        // Skip if not defined
      }
    }

    // Standard built-in objects (not constructors)
    final objects = ['Math', 'JSON', 'Reflect', 'console', 'Intl'];

    for (final name in objects) {
      try {
        final value = env.get(name);
        globalObj.setProperty(name, value);
      } catch (_) {
        // Skip if not defined
      }
    }

    // Global functions
    final functions = [
      'eval',
      'parseInt',
      'parseFloat',
      'isNaN',
      'isFinite',
      'decodeURI',
      'decodeURIComponent',
      'encodeURI',
      'encodeURIComponent',
    ];

    for (final name in functions) {
      try {
        final value = env.get(name);
        globalObj.setProperty(name, value);
      } catch (_) {
        // Skip if not defined
      }
    }

    // Global values
    globalObj.setProperty('undefined', JSValueFactory.undefined());
    globalObj.setProperty('NaN', JSValueFactory.number(double.nan));
    globalObj.setProperty('Infinity', JSValueFactory.number(double.infinity));

    // Self-reference (globalThis)
    globalObj.setProperty('globalThis', globalObj);

    return globalObj;
  }
}

/// Factory for creating Realm-related JavaScript objects
class JSRealmFactory {
  /// Creates a createRealm function for test262 $262 object
  static JSNativeFunction createRealmFunction() {
    return JSNativeFunction(
      functionName: 'createRealm',
      nativeImpl: (args) {
        final realm = JSRealm();

        // Return an object with 'global' property as per test262 spec
        final result = JSObject();
        result.setProperty('global', realm.global);

        // Add evalScript method to evaluate code in this realm
        result.setProperty(
          'evalScript',
          JSNativeFunction(
            functionName: 'evalScript',
            nativeImpl: (evalArgs) {
              if (evalArgs.isEmpty) {
                return JSValueFactory.undefined();
              }
              final code = evalArgs[0].toString();
              return realm.eval(code);
            },
          ),
        );

        return result;
      },
    );
  }
}
