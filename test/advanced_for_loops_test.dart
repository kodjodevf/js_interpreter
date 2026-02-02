import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Advanced for..in and for..of Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('for..in Advanced Features', () {
      test('for..in with array properties', () {
        final result = interpreter.eval('''
          var obj = {a: [1, 2], b: [3, 4], c: [5, 6]};
          var sum = 0;
          for (var key in obj) {
            var arr = obj[key];
            sum += arr[0] + arr[1];
          }
          sum;
        ''');
        expect(result.toNumber(), equals(21)); // (1+2) + (3+4) + (5+6)
      });

      test('for..in with simple object properties', () {
        final result = interpreter.eval('''
          var obj = {x: 10, y: 20, z: 30};
          var keys = [];
          for (var key in obj) {
            keys.push(key);
          }
          keys.length;
        ''');
        expect(result.toNumber(), equals(3));
      });

      test('for..in with nested objects', () {
        final result = interpreter.eval('''
          var nested = {
            outer: {inner1: 1, inner2: 2},
            another: {inner3: 3, inner4: 4}
          };
          var total = 0;
          for (var outerKey in nested) {
            for (var innerKey in nested[outerKey]) {
              total += nested[outerKey][innerKey];
            }
          }
          total;
        ''');
        expect(result.toNumber(), equals(10)); // 1+2+3+4
      });

      test('for..in with simple nested iteration', () {
        final result = interpreter.eval('''
          var obj = {x: 1, y: 2};
          var count = 0;
          for (var key in obj) {
            count += obj[key];
          }
          count;
        ''');
        expect(result.toNumber(), equals(3)); // 1+2
      });
    });

    group('for..of Advanced Features', () {
      test('for..of with array elements access', () {
        final result = interpreter.eval('''
          var pairs = [[1, 2], [3, 4], [5, 6]];
          var sum = 0;
          for (var pair of pairs) {
            sum += pair[0] + pair[1];
          }
          sum;
        ''');
        expect(result.toNumber(), equals(21)); // (1+2) + (3+4) + (5+6)
      });

      test('for..of with var declarations', () {
        final result = interpreter.eval('''
          var arr = [10, 20, 30];
          var total = 0;
          for (var value of arr) {
            total += value;
          }
          total;
        ''');
        expect(result.toNumber(), equals(60));
      });

      test('for..of with object properties access', () {
        final result = interpreter.eval('''
          var data = [
            {name: "Alice", score: 85},
            {name: "Bob", score: 92},
            {name: "Charlie", score: 78}
          ];
          var totalScore = 0;
          for (var student of data) {
            totalScore += student.score;
          }
          totalScore;
        ''');
        expect(result.toNumber(), equals(255)); // 85+92+78
      });

      test('for..of with spread in array', () {
        final result = interpreter.eval('''
          var arr1 = [1, 2];
          var arr2 = [3, 4];
          var combined = [...arr1, ...arr2];
          var product = 1;
          for (var num of combined) {
            product *= num;
          }
          product;
        ''');
        expect(result.toNumber(), equals(24)); // 1*2*3*4
      });

      test('for..of with function return array', () {
        final result = interpreter.eval('''
          function getNumbers() {
            return [5, 10, 15];
          }
          var sum = 0;
          for (var num of getNumbers()) {
            sum += num;
          }
          sum;
        ''');
        expect(result.toNumber(), equals(30)); // 5+10+15
      });
    });

    group('Edge Cases and Error Handling', () {
      test('for..in with simple iteration count', () {
        final result = interpreter.eval('''
          var count = 0;
          var obj = null;
          for (var key in obj) {
            count++;
          }
          count;
        ''');
        expect(result.toNumber(), equals(0));
      });

      test('for..of throws error for non-iterables', () {
        expect(
          () => interpreter.eval('''
            for (var x of null) {
              // should throw
            }
          '''),
          throwsA(isA<JSTypeError>()),
        );
      });

      test('for..of with simple arrays', () {
        final result = interpreter.eval('''
          var sparse = [1, 2, 3, 4];
          var values = [];
          for (var value of sparse) {
            values.push(value);
          }
          values.length;
        ''');
        expect(result.toNumber(), equals(4));
      });

      test('nested for..in and for..of mixing', () {
        final result = interpreter.eval('''
          var data = {
            group1: [1, 2, 3],
            group2: [4, 5, 6]
          };
          var total = 0;
          for (var groupName in data) {
            for (var value of data[groupName]) {
              total += value;
            }
          }
          total;
        ''');
        expect(result.toNumber(), equals(21)); // 1+2+3+4+5+6
      });
    });

    group('Performance and Complex Scenarios', () {
      test('large array iteration with for..of', () {
        final result = interpreter.eval('''
          var largeArray = [];
          for (var i = 0; i < 100; i++) {
            largeArray.push(i);
          }
          var sum = 0;
          for (var num of largeArray) {
            sum += num;
          }
          sum;
        ''');
        expect(result.toNumber(), equals(4950)); // sum of 0..99
      });

      test('complex object with for..in', () {
        final result = interpreter.eval('''
          var complex = {};
          for (var i = 0; i < 50; i++) {
            complex['key' + i] = i * 2;
          }
          var total = 0;
          var keyCount = 0;
          for (var key in complex) {
            total += complex[key];
            keyCount++;
          }
          keyCount === 50 && total === 2450; // sum of (0*2 + 1*2 + ... + 49*2)
        ''');
        expect(result.toBoolean(), equals(true));
      });
    });
  });
}
