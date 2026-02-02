import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Enhanced for...in and for...of Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('for...in tests', () {
      test('iterates over object properties', () {
        final result = interpreter.eval('''
          var obj = {name: "Alice", age: 30, city: "Paris"};
          var props = [];
          for (var prop in obj) {
            props.push(prop);
          }
          props.sort().join(',');
        ''');
        expect(result.toString(), equals('age,city,name'));
      });

      test('iterates over array indices', () {
        final result = interpreter.eval('''
          var arr = ['a', 'b', 'c'];
          var indices = [];
          for (var i in arr) {
            indices.push(i);
          }
          indices.join(',');
        ''');
        expect(result.toString(), equals('0,1,2'));
      });

      test('works with break and continue', () {
        final result = interpreter.eval('''
          var obj = {a: 1, b: 2, c: 3, d: 4};
          var result = [];
          for (var key in obj) {
            if (key === 'b') continue;
            if (key === 'd') break;
            result.push(key);
          }
          result.join(',');
        ''');
        expect(result.toString(), equals('a,c'));
      });
    });

    group('for...of tests', () {
      test('iterates over array values', () {
        final result = interpreter.eval('''
          var arr = [10, 20, 30];
          var sum = 0;
          for (var value of arr) {
            sum += value;
          }
          sum;
        ''');
        expect(result.toNumber(), equals(60));
      });

      test('iterates over string characters', () {
        final result = interpreter.eval('''
          var str = "JS";
          var chars = [];
          for (var char of str) {
            chars.push(char);
          }
          chars.join('-');
        ''');
        expect(result.toString(), equals('J-S'));
      });

      test('works with break and continue', () {
        final result = interpreter.eval('''
          var arr = [1, 2, 3, 4, 5, 6];
          var evenSum = 0;
          for (var num of arr) {
            if (num > 5) break;
            if (num % 2 !== 0) continue;
            evenSum += num;
          }
          evenSum;
        ''');
        expect(result.toNumber(), equals(6)); // 2 + 4
      });

      test('supports nested loops', () {
        final result = interpreter.eval('''
          var matrix = [[1, 2], [3, 4], [5, 6]];
          var total = 0;
          for (var row of matrix) {
            for (var value of row) {
              total += value;
            }
          }
          total;
        ''');
        expect(result.toNumber(), equals(21)); // 1+2+3+4+5+6
      });

      test('throws error for non-iterable', () {
        expect(
          () => interpreter.eval('''
            var num = 42;
            for (var x of num) {
              // should throw
            }
          '''),
          throwsA(isA<Error>()),
        );
      });
    });

    group('edge cases', () {
      test('empty array for...of', () {
        final result = interpreter.eval('''
          var arr = [];
          var count = 0;
          for (var value of arr) {
            count++;
          }
          count;
        ''');
        expect(result.toNumber(), equals(0));
      });

      test('empty object for...in', () {
        final result = interpreter.eval('''
          var obj = {};
          var count = 0;
          for (var key in obj) {
            count++;
          }
          count;
        ''');
        expect(result.toNumber(), equals(0));
      });

      test('empty string for...of', () {
        final result = interpreter.eval('''
          var str = "";
          var count = 0;
          for (var char of str) {
            count++;
          }
          count;
        ''');
        expect(result.toNumber(), equals(0));
      });

      test('variable scoping in loops', () {
        final result = interpreter.eval('''
          var outer = "outer";
          var arr = [1, 2, 3];
          for (var outer of arr) {
            // inner scope
          }
          outer; // should be 3 (last value) because var has function scope
        ''');
        expect(result.toNumber(), equals(3));
      });
    });

    group('practical examples', () {
      test('object property transformation', () {
        final result = interpreter.eval('''
          var person = {firstName: "John", lastName: "Doe", age: 30};
          var result = {};
          for (var key in person) {
            result[key.toUpperCase()] = person[key];
          }
          result.FIRSTNAME + " " + result.LASTNAME;
        ''');
        expect(result.toString(), equals('John Doe'));
      });

      test('array filtering and summing', () {
        final result = interpreter.eval('''
          var numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
          var evenSum = 0;
          var oddCount = 0;
          
          for (var num of numbers) {
            if (num % 2 === 0) {
              evenSum += num;
            } else {
              oddCount++;
            }
          }
          
          "Even sum: " + evenSum + ", Odd count: " + oddCount;
        ''');
        expect(result.toString(), equals('Even sum: 30, Odd count: 5'));
      });

      test('string analysis', () {
        final result = interpreter.eval('''
          var text = "Hello World";
          var vowels = 0;
          var consonants = 0;
          
          for (var char of text.toLowerCase()) {
            if ("aeiou".indexOf(char) !== -1) {
              vowels++;
            } else if (char >= 'a' && char <= 'z') {
              consonants++;
            }
          }
          
          "Vowels: " + vowels + ", Consonants: " + consonants;
        ''');
        expect(result.toString(), equals('Vowels: 3, Consonants: 7'));
      });
    });
  });
}
