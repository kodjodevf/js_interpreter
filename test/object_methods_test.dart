/// Tests for JavaScript Object methods
///
/// Tests all static methods of the global Object
library;

import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Object methods tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('Object.keys', () {
      test('Object.keys with simple object', () {
        final result = interpreter.eval('''
          let obj = {a: 1, b: 2, c: 3};
          Object.keys(obj);
        ''');
        expect(result.toString(), contains('a'));
        expect(result.toString(), contains('b'));
        expect(result.toString(), contains('c'));
      });

      test('Object.keys with empty object', () {
        final result = interpreter.eval('''
          Object.keys({});
        ''');
        expect(result.toString(), equals(''));
      });

      test('Object.keys with primitive returns empty array', () {
        final result = interpreter.eval('''
          Object.keys(42);
        ''');
        expect(result.toString(), equals(''));
      });
    });

    group('Object.values', () {
      test('Object.values with simple object', () {
        final result = interpreter.eval('''
          let obj = {a: 1, b: 2, c: 3};
          Object.values(obj);
        ''');
        expect(result.toString(), contains('1'));
        expect(result.toString(), contains('2'));
        expect(result.toString(), contains('3'));
      });

      test('Object.values with empty object', () {
        final result = interpreter.eval('''
          Object.values({});
        ''');
        expect(result.toString(), equals(''));
      });
    });

    group('Object.entries', () {
      test('Object.entries with simple object', () {
        final result = interpreter.eval('''
          let obj = {a: 1, b: 2};
          Object.entries(obj);
        ''');
        final str = result.toString();
        // Verify that the result contains key-value pairs
        expect(str, contains('a'));
        expect(str, contains('1'));
        expect(str, contains('b'));
        expect(str, contains('2'));
      });

      test('Object.entries with empty object', () {
        final result = interpreter.eval('''
          Object.entries({});
        ''');
        expect(result.toString(), equals(''));
      });
    });

    group('Object.assign', () {
      test('Object.assign basic usage', () {
        final result = interpreter.eval('''
          let target = {a: 1};
          let source = {b: 2};
          Object.assign(target, source);
          target.b;
        ''');
        expect(result.toString(), equals('2'));
      });

      test('Object.assign with multiple sources', () {
        final result = interpreter.eval('''
          let target = {a: 1};
          let source1 = {b: 2};
          let source2 = {c: 3};
          Object.assign(target, source1, source2);
          target.c;
        ''');
        expect(result.toString(), equals('3'));
      });

      test('Object.assign overwrites properties', () {
        final result = interpreter.eval('''
          let target = {a: 1};
          let source = {a: 2};
          Object.assign(target, source);
          target.a;
        ''');
        expect(result.toString(), equals('2'));
      });
    });

    group('Object.create', () {
      test('Object.create creates new object', () {
        final result = interpreter.eval('''
          let obj = Object.create(null);
          typeof obj;
        ''');
        expect(result.toString(), equals('object'));
      });
    });

    group('Object.freeze', () {
      test('Object.freeze returns same object', () {
        final result = interpreter.eval('''
          let obj = {a: 1};
          let frozen = Object.freeze(obj);
          frozen === obj;
        ''');
        expect(result.toString(), equals('true'));
      });
    });

    group('Object.seal', () {
      test('Object.seal returns same object', () {
        final result = interpreter.eval('''
          let obj = {a: 1};
          let sealed = Object.seal(obj);
          sealed === obj;
        ''');
        expect(result.toString(), equals('true'));
      });
    });

    group('Object.isFrozen', () {
      test('Object.isFrozen on regular object', () {
        final result = interpreter.eval('''
          let obj = {a: 1};
          Object.isFrozen(obj);
        ''');
        expect(result.toString(), equals('false'));
      });

      test('Object.isFrozen on primitive', () {
        final result = interpreter.eval('''
          Object.isFrozen(42);
        ''');
        expect(result.toString(), equals('true'));
      });
    });

    group('Object.isSealed', () {
      test('Object.isSealed on regular object', () {
        final result = interpreter.eval('''
          let obj = {a: 1};
          Object.isSealed(obj);
        ''');
        expect(result.toString(), equals('false'));
      });

      test('Object.isSealed on primitive', () {
        final result = interpreter.eval('''
          Object.isSealed(42);
        ''');
        expect(result.toString(), equals('true'));
      });
    });

    group('Object.getPrototypeOf', () {
      test(
        'Object.getPrototypeOf returns Object.prototype for object literals',
        () {
          final result = interpreter.eval('''
          let obj = {a: 1};
          Object.getPrototypeOf(obj) === Object.prototype;
        ''');
          expect(result.toString(), equals('true'));
        },
      );
    });

    group('Object.setPrototypeOf', () {
      test('Object.setPrototypeOf returns same object', () {
        final result = interpreter.eval('''
          let obj = {a: 1};
          let result = Object.setPrototypeOf(obj, null);
          result === obj;
        ''');
        expect(result.toString(), equals('true'));
      });
    });

    group('Object.hasOwn', () {
      test('Object.hasOwn with existing property', () {
        final result = interpreter.eval('''
          let obj = {a: 1};
          Object.hasOwn(obj, 'a');
        ''');
        expect(result.toString(), equals('true'));
      });

      test('Object.hasOwn with non-existing property', () {
        final result = interpreter.eval('''
          let obj = {a: 1};
          Object.hasOwn(obj, 'b');
        ''');
        expect(result.toString(), equals('false'));
      });
    });

    group('Complex Object operations', () {
      test('Chaining Object methods', () {
        final result = interpreter.eval('''
          let obj = {a: 1, b: 2, c: 3};
          let keys = Object.keys(obj);
          let values = Object.values(obj);
          keys.length === values.length;
        ''');
        expect(result.toString(), equals('true'));
      });

      test('Object methods with arrays', () {
        final result = interpreter.eval('''
          let arr = [1, 2, 3];
          let keys = Object.keys(arr);
          // Arrays have numeric indices as properties
          keys.length >= 3;
        ''');
        expect(result.toString(), equals('true'));
      });

      test('Object.assign chain', () {
        final result = interpreter.eval('''
          let result = Object.assign({}, {a: 1}, {b: 2}, {c: 3});
          Object.keys(result).length;
        ''');
        expect(result.toString(), equals('3'));
      });
    });

    group('Error cases', () {
      test('Object.keys with null throws error', () {
        expect(() {
          interpreter.eval('Object.keys(null);');
        }, throwsA(isA<Exception>()));
      });

      test('Object.keys with undefined throws error', () {
        expect(() {
          interpreter.eval('Object.keys(undefined);');
        }, throwsA(isA<Exception>()));
      });

      test('Object.assign with non-object target throws error', () {
        expect(() {
          interpreter.eval('Object.assign(42, {a: 1});');
        }, throwsA(isA<Exception>()));
      });
    });
  });
}
