import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Destructuring Assignment Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('Array Destructuring', () {
      test('should destructure simple array', () {
        interpreter.eval('var arr = [1, 2, 3];');
        interpreter.eval('[a, b, c] = arr;');

        expect(interpreter.eval('a').toString(), equals('1'));
        expect(interpreter.eval('b').toString(), equals('2'));
        expect(interpreter.eval('c').toString(), equals('3'));
      });

      test('should handle missing elements', () {
        interpreter.eval('var arr = [1, 2];');
        interpreter.eval('[x, y, z] = arr;');

        expect(interpreter.eval('x').toString(), equals('1'));
        expect(interpreter.eval('y').toString(), equals('2'));
        expect(interpreter.eval('z').toString(), equals('undefined'));
      });

      test('should handle holes in array pattern', () {
        interpreter.eval('var arr = [1, 2, 3, 4];');
        interpreter.eval('[a, , c] = arr;');

        expect(interpreter.eval('a').toString(), equals('1'));
        expect(interpreter.eval('c').toString(), equals('3'));
      });

      test('should destructure nested arrays', () {
        interpreter.eval('var arr = [1, [2, 3], 4];');
        interpreter.eval('[a, [b, c], d] = arr;');

        expect(interpreter.eval('a').toString(), equals('1'));
        expect(interpreter.eval('b').toString(), equals('2'));
        expect(interpreter.eval('c').toString(), equals('3'));
        expect(interpreter.eval('d').toString(), equals('4'));
      });

      test('should destructure strings', () {
        interpreter.eval('[x, y, z] = "abc";');

        expect(interpreter.eval('x').toString(), equals('a'));
        expect(interpreter.eval('y').toString(), equals('b'));
        expect(interpreter.eval('z').toString(), equals('c'));
      });
    });

    group('Object Destructuring', () {
      test('should destructure simple object', () {
        interpreter.eval('var obj = {x: 1, y: 2, z: 3};');
        interpreter.eval('{x, y, z} = obj;');

        expect(interpreter.eval('x').toString(), equals('1'));
        expect(interpreter.eval('y').toString(), equals('2'));
        expect(interpreter.eval('z').toString(), equals('3'));
      });

      test('should handle renamed properties', () {
        interpreter.eval('var obj = {x: 1, y: 2};');
        interpreter.eval('{x: a, y: b} = obj;');

        expect(interpreter.eval('a').toString(), equals('1'));
        expect(interpreter.eval('b').toString(), equals('2'));
      });

      test('should handle missing properties', () {
        interpreter.eval('var obj = {x: 1};');
        interpreter.eval('{x, y, z} = obj;');

        expect(interpreter.eval('x').toString(), equals('1'));
        expect(interpreter.eval('y').toString(), equals('undefined'));
        expect(interpreter.eval('z').toString(), equals('undefined'));
      });

      test('should destructure nested objects', () {
        interpreter.eval('var obj = {a: 1, b: {c: 2, d: 3}};');
        interpreter.eval('{a, b: {c, d}} = obj;');

        expect(interpreter.eval('a').toString(), equals('1'));
        expect(interpreter.eval('c').toString(), equals('2'));
        expect(interpreter.eval('d').toString(), equals('3'));
      });
    });

    group('Mixed Destructuring', () {
      test('should destructure object containing arrays', () {
        interpreter.eval('var obj = {arr: [1, 2, 3], name: "test"};');
        interpreter.eval('{arr: [x, y, z], name} = obj;');

        expect(interpreter.eval('x').toString(), equals('1'));
        expect(interpreter.eval('y').toString(), equals('2'));
        expect(interpreter.eval('z').toString(), equals('3'));
        expect(interpreter.eval('name').toString(), equals('test'));
      });

      test('should destructure array containing objects', () {
        interpreter.eval('var arr = [{x: 1, y: 2}, {x: 3, y: 4}];');
        interpreter.eval('[{x: a, y: b}, {x: c, y: d}] = arr;');

        expect(interpreter.eval('a').toString(), equals('1'));
        expect(interpreter.eval('b').toString(), equals('2'));
        expect(interpreter.eval('c').toString(), equals('3'));
        expect(interpreter.eval('d').toString(), equals('4'));
      });
    });

    group('Error Cases', () {
      test('should throw error for non-iterable array destructuring', () {
        expect(() {
          interpreter.eval('[x, y] = 42;');
        }, throwsA(predicate((e) => e.toString().contains('is not iterable'))));
      });

      test('should throw error for non-object destructuring', () {
        expect(
          () {
            interpreter.eval('{x, y} = 42;');
          },
          throwsA(
            predicate(
              (e) => e.toString().contains('Cannot destructure non-object'),
            ),
          ),
        );
      });

      test('should throw error for null destructuring', () {
        expect(() {
          interpreter.eval('[x, y] = null;');
        }, throwsA(predicate((e) => e.toString().contains('is not iterable'))));
      });
    });
  });
}
