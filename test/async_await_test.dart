import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('Async/Await Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Basic async function parsing', () {
      // Test que le parsing ne plante pas
      final result = interpreter.eval('''
        async function test() {
          return 42;
        }
      ''');

      // Function declarations now return the function
      // (necessary for ES2020 module exports)
      expect(result, isA<JSFunction>());
    });

    test('Async function expression parsing', () {
      final result = interpreter.eval('''
        const test = async function() {
          return 42;
        };
      ''');

      expect(result.isUndefined, equals(true));
    });

    test('Async function returns Promise', () {
      interpreter.eval('''
        async function test() {
          return 42;
        }
      ''');

      final result = interpreter.eval('test()');
      expect(result, isA<JSPromise>());
    });

    test('Async function resolves to correct value', () {
      interpreter.eval('''
        async function test() {
          return 42;
        }
      ''');

      final promise = interpreter.eval('test()') as JSPromise;
      // The Promise should be resolved immediately in our implementation
      expect(promise.state, equals(PromiseState.fulfilled));
      expect(promise.value?.toNumber(), equals(42.0));
    });

    test('Await with non-Promise value', () {
      final result = interpreter.eval('''
        async function test() {
          return await 42;
        }
        test();
      ''');

      expect(result, isA<JSPromise>());
      final promise = result as JSPromise;
      expect(promise.state, equals(PromiseState.fulfilled));
      expect(promise.value?.toNumber(), equals(42.0));
    });

    test('Async function with parameters', () {
      interpreter.eval('''
        async function add(a, b) {
          return a + b;
        }
      ''');

      final promise = interpreter.eval('add(10, 20)') as JSPromise;
      expect(promise.state, equals(PromiseState.fulfilled));
      expect(promise.value?.toNumber(), equals(30.0));
    });

    test('Async function with return statement', () {
      interpreter.eval('''
        async function test() {
          if (true) {
            return 123;
          }
          return 456;
        }
      ''');

      final promise = interpreter.eval('test()') as JSPromise;
      expect(promise.state, equals(PromiseState.fulfilled));
      expect(promise.value?.toNumber(), equals(123.0));
    });

    test('Async function with real await (Promise resolution)', () {
      // Create a Promise that resolves later
      interpreter.eval('''
        let resolveLater;
        const promise = new Promise((resolve) => {
          resolveLater = resolve;
        });

        async function test() {
          const result = await promise;
          return result * 2;
        }

        const asyncResult = test();
      ''');

      // La fonction async devrait retourner une Promise en attente
      final asyncResult = interpreter.eval('asyncResult') as JSPromise;
      expect(asyncResult.state, equals(PromiseState.pending));

      // Resolve the original Promise
      interpreter.eval('resolveLater(21)');

      // Execute pending tasks to allow resumption
      // Note: In a real implementation, this would be automatic
      interpreter.runPendingAsyncTasks();

      // Now the async Promise should be resolved
      expect(asyncResult.state, equals(PromiseState.fulfilled));
      expect(asyncResult.value?.toNumber(), equals(42.0));
    });
  });
}
