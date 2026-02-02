/// Implementation of JavaScript generators (ES6)
library;

import 'js_value.dart';
import 'native_functions.dart';
import 'js_symbol.dart';

/// Possible generator states
enum GeneratorState {
  suspendedStart, // Created but not yet executed
  suspendedYield, // Suspended after a yield
  executing, // Currently executing
  completed, // Completed (return or end of function)
}

/// JavaScript generator
class JSGenerator extends JSObject {
  /// The current state of the generator
  GeneratorState state;

  /// The generator function to execute
  /// Ifgnature: (JSValue inputValue, GeneratorState previousState) -> Map&lt;String, dynamic&gt;
  /// Returns {'value': JSValue, 'done': bool}
  final Map<String, dynamic> Function(JSValue, GeneratorState)
  generatorFunction;

  /// The last yielded value
  JSValue? lastYieldedValue;

  /// The value returned by the generator (if terminated with return)
  JSValue? returnValue;

  JSGenerator({required this.generatorFunction})
    : state = GeneratorState.suspendedStart {
    // Expose next(), return(), throw() methods
    setProperty(
      'next',
      JSNativeFunction(
        functionName: 'next',
        nativeImpl: (args) =>
            next(args.isNotEmpty ? args[0] : JSValueFactory.undefined()),
      ),
    );

    setProperty(
      'return',
      JSNativeFunction(
        functionName: 'return',
        nativeImpl: (args) => returnMethod(
          args.isNotEmpty ? args[0] : JSValueFactory.undefined(),
        ),
      ),
    );

    setProperty(
      'throw',
      JSNativeFunction(
        functionName: 'throw',
        nativeImpl: (args) =>
            throwMethod(args.isNotEmpty ? args[0] : JSValueFactory.undefined()),
      ),
    );

    // Generators are iterable: Symbol.iterator returns this
    // Per ES6 spec: generators are their own iterators
    setProperty(
      JSSymbol.iterator.toString(),
      JSNativeFunction(
        functionName: '[Symbol.iterator]',
        nativeImpl: (args) => this,
      ),
    );

    // Override toString to return [object Generator]
    setProperty(
      'toString',
      JSNativeFunction(
        functionName: 'toString',
        nativeImpl: (args) => JSValueFactory.string('[object Generator]'),
      ),
    );
  }

  /// Method next([value])
  /// Resumes execution of the generator and returns {value, done}
  JSValue next(JSValue value) {
    if (state == GeneratorState.completed) {
      // Generator already terminated
      return _createIteratorResult(JSValueFactory.undefined(), true);
    }

    if (state == GeneratorState.executing) {
      throw JSError('Generator is already executing');
    }

    // Switch to executing state
    final previousState = state;
    state = GeneratorState.executing;

    try {
      final result = _executeGenerator(value, previousState);

      if (result['done'] == true) {
        state = GeneratorState.completed;
        returnValue = result['value'];
      } else {
        state = GeneratorState.suspendedYield;
        lastYieldedValue = result['value'];
      }

      return _createIteratorResult(result['value'], result['done']);
    } catch (e) {
      state = GeneratorState.completed;
      rethrow;
    }
  }

  /// Method return([value])
  /// Terminates the generator and returns {value, done: true}
  JSValue returnMethod(JSValue value) {
    if (state == GeneratorState.completed) {
      return _createIteratorResult(value, true);
    }

    state = GeneratorState.completed;
    returnValue = value;

    return _createIteratorResult(value, true);
  }

  /// Method throw(exception)
  /// Throws an exception in the generator
  JSValue throwMethod(JSValue exception) {
    if (state == GeneratorState.completed) {
      throw exception;
    }

    if (state == GeneratorState.executing) {
      throw JSError('Generator is already executing');
    }

    state = GeneratorState.executing;

    try {
      // The exception will be thrown in the generator
      // We pass the exception as input value with a special state
      final result = _executeGenerator(
        exception,
        GeneratorState.suspendedYield,
      );

      if (result['done'] == true) {
        state = GeneratorState.completed;
      } else {
        state = GeneratorState.suspendedYield;
      }

      return _createIteratorResult(result['value'], result['done']);
    } catch (e) {
      state = GeneratorState.completed;
      rethrow;
    }
  }

  /// Executes the generator and returns the next result
  Map<String, dynamic> _executeGenerator(
    JSValue inputValue,
    GeneratorState previousState,
  ) {
    // Appelle la fonction generateur fournie par l'evaluateur
    return generatorFunction(inputValue, previousState);
  }

  /// Creates an iterator result object {value, done}
  JSValue _createIteratorResult(JSValue value, bool done) {
    final result = JSObject();
    result.setProperty('value', value);
    result.setProperty('done', JSValueFactory.boolean(done));
    return result;
  }

  @override
  JSValueType get type => JSValueType.object;

  @override
  String toString() => '[object Generator]';
}

/// Async generator JavaScript (ES2018)
/// Similar to JSGenerator but .next() returns a Promise that resolves to {value, done}
class JSAsyncGenerator extends JSObject {
  /// The current state of the async generator
  GeneratorState state;

  /// The generator function to execute
  /// Ifgnature: (JSValue inputValue, GeneratorState previousState) -> Map&lt;String, dynamic&gt;
  /// Returns {'value': JSValue, 'done': bool}
  final Map<String, dynamic> Function(JSValue, GeneratorState)
  generatorFunction;

  /// The last value yielded
  JSValue? lastYieldedValue;

  /// The return value of the async generator (if completed with return)
  JSValue? returnValue;

  JSAsyncGenerator({required this.generatorFunction})
    : state = GeneratorState.suspendedStart {
    // Expose next(), return(), throw() methods
    setProperty(
      'next',
      JSNativeFunction(
        functionName: 'next',
        nativeImpl: (args) =>
            next(args.isNotEmpty ? args[0] : JSValueFactory.undefined()),
      ),
    );

    setProperty(
      'return',
      JSNativeFunction(
        functionName: 'return',
        nativeImpl: (args) => returnMethod(
          args.isNotEmpty ? args[0] : JSValueFactory.undefined(),
        ),
      ),
    );

    setProperty(
      'throw',
      JSNativeFunction(
        functionName: 'throw',
        nativeImpl: (args) =>
            throwMethod(args.isNotEmpty ? args[0] : JSValueFactory.undefined()),
      ),
    );

    // Async generators are async iterable: Symbol.asyncIterator returns this
    setProperty(
      JSSymbol.asyncIterator.toString(),
      JSNativeFunction(
        functionName: '[Symbol.asyncIterator]',
        nativeImpl: (args) => this,
      ),
    );

    // Override toString to return [object AsyncGenerator]
    setProperty(
      'toString',
      JSNativeFunction(
        functionName: 'toString',
        nativeImpl: (args) => JSValueFactory.string('[object AsyncGenerator]'),
      ),
    );
  }

  /// Method next([value])
  /// Resumes execution of the async generator and returns a Promise that resolves to {value, done}
  JSValue next(JSValue value) {
    if (state == GeneratorState.completed) {
      // Async generator already terminated
      // Return a resolved Promise with {value: undefined, done: true}
      return JSPromise(
        JSNativeFunction(
          functionName: 'resolveTerminated',
          nativeImpl: (args) {
            final resolve = args[0] as JSNativeFunction;
            final result = JSObject();
            result.setProperty('value', JSValueFactory.undefined());
            result.setProperty('done', JSValueFactory.boolean(true));
            resolve.call([result]);
            return JSValueFactory.undefined();
          },
        ),
      );
    }

    if (state == GeneratorState.executing) {
      throw JSError('Async generator is already executing');
    }

    // Switch to executing state
    final previousState = state;
    state = GeneratorState.executing;

    try {
      // Execute the generator function
      final result = generatorFunction(value, previousState);

      if (result['done'] == true) {
        state = GeneratorState.completed;
        returnValue = result['value'];
      } else {
        state = GeneratorState.suspendedYield;
        lastYieldedValue = result['value'];
      }

      // Return a Promise that resolves to the iterator result
      return _createAsyncIteratorResult(
        result['value'] as JSValue,
        result['done'] as bool,
      );
    } catch (e) {
      state = GeneratorState.completed;
      rethrow;
    }
  }

  /// Method return([value])
  /// Terminates the async generator and returns a Promise that resolves to {value, done: true}
  JSValue returnMethod(JSValue value) {
    if (state == GeneratorState.completed) {
      return _createAsyncIteratorResult(value, true);
    }

    state = GeneratorState.completed;
    returnValue = value;

    return _createAsyncIteratorResult(value, true);
  }

  /// Method throw(exception)
  /// Throws an exception in the async generator
  JSValue throwMethod(JSValue exception) {
    if (state == GeneratorState.completed) {
      // Return a rejected Promise
      return JSPromise(
        JSNativeFunction(
          functionName: 'rejectTerminated',
          nativeImpl: (args) {
            final reject = args[1] as JSNativeFunction;
            reject.call([exception]);
            return JSValueFactory.undefined();
          },
        ),
      );
    }

    if (state == GeneratorState.executing) {
      throw JSError('Async generator is already executing');
    }

    state = GeneratorState.executing;

    try {
      // The exception will be thrown in the async generator
      // We pass the exception as input value with a special state
      final result = generatorFunction(
        exception,
        GeneratorState.suspendedYield, // Use suspended state to indicate throw
      );

      if (result['done'] == true) {
        state = GeneratorState.completed;
        returnValue = result['value'];
      } else {
        state = GeneratorState.suspendedYield;
        lastYieldedValue = result['value'];
      }

      return _createAsyncIteratorResult(
        result['value'] as JSValue,
        result['done'] as bool,
      );
    } catch (e) {
      state = GeneratorState.completed;
      // Return a rejected Promise
      return JSPromise(
        JSNativeFunction(
          functionName: 'rejectError',
          nativeImpl: (args) {
            final reject = args[1] as JSNativeFunction;
            // Convert the error to a JSValue if needed
            final errorValue = e is JSValue
                ? e
                : JSValueFactory.string(e.toString());
            reject.call([errorValue]);
            return JSValueFactory.undefined();
          },
        ),
      );
    }
  }

  /// Helper to create an async iterator result {value, done}
  /// This is wrapped in a resolved Promise
  JSValue _createAsyncIteratorResult(JSValue value, bool done) {
    return JSPromise(
      JSNativeFunction(
        functionName: 'resolveIteratorResult',
        nativeImpl: (args) {
          final resolve = args[0] as JSNativeFunction;
          final result = JSObject();
          result.setProperty('value', value);
          result.setProperty('done', JSValueFactory.boolean(done));
          resolve.call([result]);
          return JSValueFactory.undefined();
        },
      ),
    );
  }

  @override
  JSValueType get type => JSValueType.object;

  @override
  String toString() => '[object AsyncGenerator]';
}
