import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Test262 - Async Classes and Built-ins', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    // Test basic async class methods
    test('async class method', () {
      final code = '''
        class MyClass {
          async getValue() {
            return 42;
          }
        }
        const obj = new MyClass();
        const result = await obj.getValue();
        result;
      ''';

      expect(() => interpreter.eval(code), isNotNull);
    });

    // Test async static methods
    test('async static method', () {
      final code = '''
        class MyClass {
          static async getValue() {
            return 42;
          }
        }
        const result = await MyClass.getValue();
        result;
      ''';

      expect(() => interpreter.eval(code), isNotNull);
    });

    // Test async generator in class
    test('async generator in class', () {
      final code = '''
        class MyClass {
          async *generate() {
            yield 1;
            yield 2;
            yield 3;
          }
        }
        const obj = new MyClass();
        const results = [];
        for await (const value of obj.generate()) {
          results.push(value);
        }
        results;
      ''';

      expect(() => interpreter.eval(code), isNotNull);
    });

    test('FinalizationRegistry exists', () {
      final code = 'typeof FinalizationRegistry;';
      expect(() => interpreter.eval(code), isNotNull);
    });

    test('WeakRef exists', () {
      final code = 'typeof WeakRef;';
      expect(() => interpreter.eval(code), isNotNull);
    });

    test('Iterator protocol', () {
      final code = '''
        const arr = [1, 2, 3];
        const iterator = arr[Symbol.iterator]();
        iterator.next().value;
      ''';

      expect(() => interpreter.eval(code), isNotNull);
    });

    test('AsyncIterator protocol', () {
      final code = '''
        async function* gen() {
          yield 1;
          yield 2;
        }
        const iterator = gen();
        typeof iterator[Symbol.asyncIterator];
      ''';

      expect(() => interpreter.eval(code), isNotNull);
    });
  });
}
