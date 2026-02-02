import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('JavaScript Loops Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('For Loop', () {
      test('classic for loop', () {
        final result = interpreter.eval('''
          var sum = 0;
          for (var i = 1; i <= 5; i++) {
            sum += i;
          }
          sum;
        ''');
        expect(result.toNumber(), equals(15)); // 1+2+3+4+5 = 15
      });

      test('for loop with break', () {
        final result = interpreter.eval('''
          var sum = 0;
          for (var i = 1; i <= 10; i++) {
            if (i > 5) break;
            sum += i;
          }
          sum;
        ''');
        expect(result.toNumber(), equals(15)); // 1+2+3+4+5 = 15
      });

      test('for loop with continue', () {
        final result = interpreter.eval('''
          var sum = 0;
          for (var i = 1; i <= 5; i++) {
            if (i === 3) continue;
            sum += i;
          }
          sum;
        ''');
        expect(result.toNumber(), equals(12)); // 1+2+4+5 = 12
      });
    });

    group('Do-While Loop', () {
      test('basic do-while loop', () {
        final result = interpreter.eval('''
          var i = 0;
          var sum = 0;
          do {
            sum += i;
            i++;
          } while (i < 5);
          sum;
        ''');
        expect(result.toNumber(), equals(10)); // 0+1+2+3+4 = 10
      });

      test('do-while executes at least once', () {
        final result = interpreter.eval('''
          var executed = false;
          do {
            executed = true;
          } while (false);
          executed;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('do-while with break', () {
        final result = interpreter.eval('''
          var i = 0;
          var sum = 0;
          do {
            if (i > 3) break;
            sum += i;
            i++;
          } while (i < 10);
          sum;
        ''');
        expect(result.toNumber(), equals(6)); // 0+1+2+3 = 6
      });
    });

    group('For-In Loop', () {
      test('for-in with object', () {
        final result = interpreter.eval('''
          var obj = {a: 1, b: 2, c: 3};
          var keys = [];
          for (var key in obj) {
            keys.push(key);
          }
          keys.length;
        ''');
        expect(result.toNumber(), equals(3));
      });

      test('for-in with object values sum', () {
        final result = interpreter.eval('''
          var obj = {a: 10, b: 20, c: 30};
          var sum = 0;
          for (var key in obj) {
            sum += obj[key];
          }
          sum;
        ''');
        expect(result.toNumber(), equals(60)); // 10+20+30 = 60
      });
    });

    group('For-Of Loop', () {
      test('for-of with array', () {
        final result = interpreter.eval('''
          var arr = [1, 2, 3, 4, 5];
          var sum = 0;
          for (var value of arr) {
            sum += value;
          }
          sum;
        ''');
        expect(result.toNumber(), equals(15)); // 1+2+3+4+5 = 15
      });

      test('for-of with array and break', () {
        final result = interpreter.eval('''
          var arr = [1, 2, 3, 4, 5];
          var sum = 0;
          for (var value of arr) {
            if (value > 3) break;
            sum += value;
          }
          sum;
        ''');
        expect(result.toNumber(), equals(6)); // 1+2+3 = 6
      });

      test('for-of with array and continue', () {
        final result = interpreter.eval('''
          var arr = [1, 2, 3, 4, 5];
          var sum = 0;
          for (var value of arr) {
            if (value === 3) continue;
            sum += value;
          }
          sum;
        ''');
        expect(result.toNumber(), equals(12)); // 1+2+4+5 = 12
      });
    });

    group('Nested Loops', () {
      test('nested for loops', () {
        final result = interpreter.eval('''
          var sum = 0;
          for (var i = 1; i <= 3; i++) {
            for (var j = 1; j <= 3; j++) {
              sum += i * j;
            }
          }
          sum;
        ''');
        expect(
          result.toNumber(),
          equals(36),
        ); // (1*1+1*2+1*3)+(2*1+2*2+2*3)+(3*1+3*2+3*3) = 6+12+18 = 36
      });

      test('nested loops with break', () {
        final result = interpreter.eval('''
          var sum = 0;
          outer: for (var i = 1; i <= 5; i++) {
            for (var j = 1; j <= 5; j++) {
              if (i * j > 6) break outer;
              sum += i * j;
            }
          }
          sum;
        ''');
        expect(
          result.toNumber(),
          equals(27),
        ); // 1*1+1*2+1*3+1*4+1*5 + 2*1+2*2+2*3 = 15+12 = 27 (break when i=2,j=4 as 8>6)
      });
    });

    group('Loop Variable Scoping', () {
      test('for loop variable scope with var', () {
        final result = interpreter.eval('''
          var i = 100;
          for (var i = 1; i <= 3; i++) {
            // inner scope with var - same scope as outer
          }
          i; // should be 4 (last value of loop variable + 1)
        ''');
        expect(
          result.toNumber(),
          equals(4),
        ); // var has function scope, not block scope
      });

      test('for-in variable scope', () {
        final result = interpreter.eval('''
          var key = 'outer';
          var obj = {a: 1, b: 2};
          for (var key in obj) {
            // inner scope with var - same scope as outer
          }
          key; // should be the last key from the loop
        ''');
        expect(result.toString(), equals('b')); // var has function scope
      });
    });
  });
}
