import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Spread Operator Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('Array Spread', () {
      test('Spread array in array literal', () {
        final result = interpreter.eval('''
          var arr1 = [1, 2, 3];
          var arr2 = [4, 5, 6];
          var combined = [...arr1, ...arr2];
          combined;
        ''');

        expect(result.toString(), equals('1,2,3,4,5,6'));
      });

      test('Spread with mixed elements', () {
        final result = interpreter.eval('''
          var arr = [2, 3];
          var result = [1, ...arr, 4, 5];
          result;
        ''');

        expect(result.toString(), equals('1,2,3,4,5'));
      });

      test('Spread string in array', () {
        final result = interpreter.eval('''
          var chars = [..."hello"];
          chars;
        ''');

        expect(result.toString(), equals('h,e,l,l,o'));
      });

      test('Empty spread', () {
        final result = interpreter.eval('''
          var empty = [];
          var result = [1, ...empty, 2];
          result;
        ''');

        expect(result.toString(), equals('1,2'));
      });
    });

    group('Object Spread', () {
      test('Spread object in object literal', () {
        final result = interpreter.eval('''
          var obj1 = {a: 1, b: 2};
          var obj2 = {c: 3, d: 4};
          var combined = {...obj1, ...obj2};
          combined.a + combined.b + combined.c + combined.d;
        ''');

        expect(result.toNumber(), equals(10));
      });

      test('Spread with override', () {
        final result = interpreter.eval('''
          var obj1 = {a: 1, b: 2};
          var obj2 = {b: 3, c: 4};
          var combined = {...obj1, ...obj2};
          combined.b; // obj2.b should override obj1.b
        ''');

        expect(result.toNumber(), equals(3));
      });

      test('Spread with additional properties', () {
        final result = interpreter.eval('''
          var base = {a: 1, b: 2};
          var extended = {...base, c: 3, d: 4};
          extended.a + extended.c;
        ''');

        expect(result.toNumber(), equals(4));
      });
    });

    group('Function Call Spread', () {
      test('Spread array as function arguments', () {
        final result = interpreter.eval('''
          function sum(a, b, c) {
            return a + b + c;
          }
          
          var numbers = [1, 2, 3];
          sum(...numbers);
        ''');

        expect(result.toNumber(), equals(6));
      });

      test('Spread with mixed arguments', () {
        final result = interpreter.eval('''
          function test(a, b, c, d) {
            return a + b + c + d;
          }
          
          var arr = [2, 3];
          test(1, ...arr, 4);
        ''');

        expect(result.toNumber(), equals(10));
      });

      test('Spread string as arguments', () {
        final result = interpreter.eval('''
          function concat(a, b, c) {
            return a + b + c;
          }
          
          concat(..."abc");
        ''');

        expect(result.toString(), equals('abc'));
      });
    });

    group('Complex Spread Scenarios', () {
      test('Nested spread operations', () {
        final result = interpreter.eval('''
          var arr1 = [1, 2];
          var arr2 = [3, 4];
          var arr3 = [...arr1, ...arr2];
          var arr4 = [0, ...arr3, 5];
          arr4;
        ''');

        expect(result.toString(), equals('0,1,2,3,4,5'));
      });

      test('Spread in object with computed properties', () {
        final result = interpreter.eval('''
          var base = {a: 1, b: 2};
          var key = "c";
          var obj = {...base, [key]: 3};
          obj.c;
        ''');

        expect(result.toNumber(), equals(3));
      });

      test('Spread with function expression', () {
        final result = interpreter.eval('''
          var createArray = function() { return [1, 2, 3]; };
          var result = [0, ...createArray(), 4];
          result;
        ''');

        expect(result.toString(), equals('0,1,2,3,4'));
      });
    });

    group('Error Cases', () {
      test('Spread non-iterable in array', () {
        expect(() => interpreter.eval('[...42]'), throwsA(isA<JSTypeError>()));
      });

      test('Spread non-object in object literal', () {
        expect(() => interpreter.eval('{...42}'), throwsA(isA<Object>()));
      });

      test('Spread non-iterable in function call', () {
        expect(
          () => interpreter.eval('''
            function test() {}
            test(...42);
          '''),
          throwsA(isA<JSTypeError>()),
        );
      });
    });
  });
}
