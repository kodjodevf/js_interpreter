import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Assignment Operators', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('Variable Assignment Operators', () {
      test('addition assignment (+=) with numbers', () {
        final result = interpreter.eval('''
          var x = 10;
          x += 5;
          x;
        ''');
        expect(result.toNumber(), equals(15));
      });

      test('addition assignment (+=) with strings', () {
        final result = interpreter.eval('''
          var str = "Hello";
          str += " World";
          str;
        ''');
        expect(result.toString(), equals('Hello World'));
      });

      test('addition assignment (+=) string concatenation with number', () {
        final result = interpreter.eval('''
          var str = "Count: ";
          str += 42;
          str;
        ''');
        expect(result.toString(), equals('Count: 42'));
      });

      test('subtraction assignment (-=)', () {
        final result = interpreter.eval('''
          var x = 20;
          x -= 8;
          x;
        ''');
        expect(result.toNumber(), equals(12));
      });

      test('multiplication assignment (*=)', () {
        final result = interpreter.eval('''
          var x = 6;
          x *= 7;
          x;
        ''');
        expect(result.toNumber(), equals(42));
      });

      test('division assignment (/=)', () {
        final result = interpreter.eval('''
          var x = 50;
          x /= 10;
          x;
        ''');
        expect(result.toNumber(), equals(5));
      });

      test('modulo assignment (%=)', () {
        final result = interpreter.eval('''
          var x = 17;
          x %= 5;
          x;
        ''');
        expect(result.toNumber(), equals(2));
      });

      test('chained assignment operations', () {
        final result = interpreter.eval('''
          var x = 10;
          x += 5;  // x = 15
          x *= 2;  // x = 30
          x -= 10; // x = 20
          x /= 4;  // x = 5
          x %= 3;  // x = 2
          x;
        ''');
        expect(result.toNumber(), equals(2));
      });

      test('assignment with complex expressions', () {
        final result = interpreter.eval('''
          var a = 5;
          var b = 3;
          a += b * 2; // a = 5 + (3 * 2) = 11
          a;
        ''');
        expect(result.toNumber(), equals(11));
      });
    });

    group('Object Property Assignment Operators', () {
      test('object property addition assignment', () {
        final result = interpreter.eval('''
          var obj = {count: 10};
          obj.count += 5;
          obj.count;
        ''');
        expect(result.toNumber(), equals(15));
      });

      test('object property subtraction assignment', () {
        final result = interpreter.eval('''
          var obj = {value: 100};
          obj.value -= 25;
          obj.value;
        ''');
        expect(result.toNumber(), equals(75));
      });

      test('object property string concatenation assignment', () {
        final result = interpreter.eval('''
          var obj = {message: "Hello"};
          obj.message += " World";
          obj.message;
        ''');
        expect(result.toString(), equals('Hello World'));
      });

      test('computed property assignment', () {
        final result = interpreter.eval('''
          var obj = {x: 20, y: 30};
          var prop = "x";
          obj[prop] += 10;
          obj.x;
        ''');
        expect(result.toNumber(), equals(30));
      });

      test('nested object property assignment', () {
        final result = interpreter.eval('''
          var obj = {nested: {value: 5}};
          obj.nested.value *= 4;
          obj.nested.value;
        ''');
        expect(result.toNumber(), equals(20));
      });
    });

    group('Array Element Assignment Operators', () {
      test('array element addition assignment', () {
        final result = interpreter.eval('''
          var arr = [10, 20, 30];
          arr[1] += 5;
          arr[1];
        ''');
        expect(result.toNumber(), equals(25));
      });

      test('array element multiplication assignment', () {
        final result = interpreter.eval('''
          var arr = [2, 4, 6];
          arr[0] *= 3;
          arr[0];
        ''');
        expect(result.toNumber(), equals(6));
      });

      test('array element string concatenation', () {
        final result = interpreter.eval('''
          var arr = ["Hello", "World"];
          arr[0] += "!";
          arr[0];
        ''');
        expect(result.toString(), equals('Hello!'));
      });

      test('dynamic array index assignment', () {
        final result = interpreter.eval('''
          var arr = [1, 2, 3, 4, 5];
          var index = 2;
          arr[index] += 7;
          arr[2];
        ''');
        expect(result.toNumber(), equals(10));
      });
    });

    group('Return Values and Side Effects', () {
      test('assignment operators return the assigned value', () {
        final result = interpreter.eval('''
          var x = 10;
          var y = (x += 5); // Should return 15
          y;
        ''');
        expect(result.toNumber(), equals(15));
      });

      test('assignment in expression context', () {
        final result = interpreter.eval('''
          var a = 5;
          var b = 10;
          var sum = (a *= 2) + (b += 3); // (5*2) + (10+3) = 10 + 13 = 23
          sum;
        ''');
        expect(result.toNumber(), equals(23));
      });

      test('multiple variables with same operation', () {
        final result = interpreter.eval('''
          var x = 10, y = 20, z = 30;
          x += 5;
          y += 5;
          z += 5;
          x + y + z;
        ''');
        expect(result.toNumber(), equals(75)); // 15 + 25 + 35
      });
    });

    group('Type Coercion and Edge Cases', () {
      test('number with string in +=', () {
        final result = interpreter.eval('''
          var x = 42;
          x += "0";
          x;
        ''');
        expect(result.toString(), equals('420'));
      });

      test('boolean in arithmetic assignment', () {
        final result = interpreter.eval('''
          var x = 10;
          x += true; // true coerces to 1
          x;
        ''');
        expect(result.toNumber(), equals(11));
      });

      test('null in arithmetic assignment', () {
        final result = interpreter.eval('''
          var x = 5;
          x += null; // null coerces to 0
          x;
        ''');
        expect(result.toNumber(), equals(5));
      });

      test('undefined in assignment produces NaN', () {
        final result = interpreter.eval('''
          var x = 10;
          x += undefined; // undefined coerces to NaN
          x;
        ''');
        expect(result.toNumber().isNaN, equals(true));
      });

      test('division by zero', () {
        final result = interpreter.eval('''
          var x = 10;
          x /= 0;
          x;
        ''');
        expect(result.toNumber(), equals(double.infinity));
      });

      test('modulo with zero produces NaN', () {
        final result = interpreter.eval('''
          var x = 10;
          x %= 0;
          x;
        ''');
        expect(result.toNumber().isNaN, equals(true));
      });
    });

    group('Performance and Complex Scenarios', () {
      test('assignment in loop', () {
        final result = interpreter.eval('''
          var sum = 0;
          for (var i = 1; i <= 10; i++) {
            sum += i;
          }
          sum;
        ''');
        expect(result.toNumber(), equals(55)); // sum of 1 to 10
      });

      test('assignment with function calls', () {
        final result = interpreter.eval('''
          function getValue() {
            return 5;
          }
          var x = 10;
          x += getValue() * 2;
          x;
        ''');
        expect(result.toNumber(), equals(20)); // 10 + (5 * 2)
      });

      test('assignment with complex object access', () {
        final result = interpreter.eval('''
          var data = {
            items: [
              {value: 10},
              {value: 20},
              {value: 30}
            ]
          };
          data.items[1].value += 5;
          data.items[1].value;
        ''');
        expect(result.toNumber(), equals(25));
      });
    });
  });
}
