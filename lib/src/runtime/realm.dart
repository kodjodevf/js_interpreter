/// JavaScript Realm implementation
/// A Realm represents a distinct global environment for JavaScript execution.
/// Each Realm has its own set of intrinsic objects (Object, Array, Error, etc.)
library;

import '../bytecode/compiler.dart';
import '../bytecode/vm.dart';
import '../parser/parser.dart';
import 'js_value.dart';
import 'native_functions.dart';
import 'runtime_bootstrap.dart';

/// Represents a JavaScript Realm - an isolated execution environment
/// with its own global object and intrinsic objects.
class JSRealm {
  late final BytecodeVM _vm;

  /// The global object for this realm
  late final JSObject _globalObject;

  /// Create a new Realm with fresh global environment
  JSRealm() {
    _vm = BytecodeVM();
    RuntimeBootstrap.populateGlobals(_vm.globals);
    _globalObject =
        (_vm.globals['globalThis'] as JSObject?) ?? _createGlobalObject();
  }

  /// Get the global object for this realm
  JSObject get global => _globalObject;

  /// Evaluate code in this realm
  JSValue eval(String code) {
    final program = JSParser.parseString(code);
    final compiler = BytecodeCompiler();
    final bytecode = compiler.compile(program);
    return _vm.execute(bytecode);
  }

  /// Creates the global object with all built-in constructors
  JSObject _createGlobalObject() {
    final globalObj = JSObject();
    for (final entry in _vm.globals.entries) {
      globalObj.setProperty(entry.key, entry.value);
    }
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
