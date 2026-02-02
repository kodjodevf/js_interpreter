import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });

  group('ES5 Complete Features Tests', () {
    test('Increment/Decrement Operators', () {
      final code = '''
        var x = 5;
        var y = 10;
        var result = [];

        // Pre-increment
        result.push(++x);  // x devient 6, result[0] = 6

        // Post-increment
        result.push(x++);  // result[1] = 6, x devient 7

        // Pre-decrement
        result.push(--y);  // y devient 9, result[2] = 9

        // Post-decrement
        result.push(y--);  // result[3] = 9, y devient 8

        // Utilisation dans expressions
        var z = ++x + y--;  // z = 8 + 8 = 16, y devient 7

        result.push(x);  // 8
        result.push(y);  // 7
        result.push(z);  // 16

        result;
      ''';

      final result = interpreter.eval(code);
      final resultList = (result as JSArray).toList();

      expect(resultList.length, equals(7));
      expect(resultList[0], equals(6.0)); // ++x
      expect(resultList[1], equals(6.0)); // x++
      expect(resultList[2], equals(9.0)); // --y
      expect(resultList[3], equals(9.0)); // y--
      expect(resultList[4], equals(8.0)); // x final
      expect(resultList[5], equals(7.0)); // y final
      expect(resultList[6], equals(16.0)); // z
    });

    test('Switch Statement - Basic Cases', () {
      final code = '''
        var x = 2;
        var result = 0;

        switch (x) {
          case 1:
            result = 10;
            break;
          case 2:
            result = 20;
            break;
          case 3:
            result = 30;
            break;
          default:
            result = 99;
        }

        result;
      ''';

      final result = interpreter.eval(code);
      expect(result.primitiveValue, equals(20.0));
    });

    test('Switch Statement - Fallthrough', () {
      final code = '''
        var x = 1;
        var result = '';

        switch (x) {
          case 1:
            result += 'one';
          case 2:
            result += 'two';
            break;
          case 3:
            result += 'three';
            break;
        }

        result;
      ''';

      final result = interpreter.eval(code);
      expect(result.primitiveValue, equals('onetwo'));
    });

    test('Switch Statement - Default Case', () {
      final code = '''
        var x = 5;
        var result = 0;

        switch (x) {
          case 1:
            result = 10;
            break;
          case 2:
            result = 20;
            break;
          default:
            result = 100;
        }

        result;
      ''';

      final result = interpreter.eval(code);
      expect(result.primitiveValue, equals(100.0));
    });

    test('Switch Statement - String Cases', () {
      final code = '''
        var fruit = 'apple';
        var color = '';

        switch (fruit) {
          case 'banana':
            color = 'yellow';
            break;
          case 'apple':
            color = 'red';
            break;
          case 'orange':
            color = 'orange';
            break;
          default:
            color = 'unknown';
        }

        color;
      ''';

      final result = interpreter.eval(code);
      expect(result.primitiveValue, equals('red'));
    });

    test('Try/Catch - Basic Exception Handling', () {
      final code = '''
        var result = 0;

        try {
          throw "test error";
        } catch (e) {
          result = 42;
        }

        result;
      ''';

      final result = interpreter.eval(code);
      expect(result.primitiveValue, equals(42.0));
    });

    test('Try/Catch/Finally - Complete Flow', () {
      final code = '''
        var result = '';

        try {
          result += 'try';
          throw "error";
        } catch (e) {
          result += 'catch';
        } finally {
          result += 'finally';
        }

        result;
      ''';

      final result = interpreter.eval(code);
      expect(result.primitiveValue, equals('trycatchfinally'));
    });

    test('Try/Finally - Without Catch', () {
      final code = '''
        var result = '';

        try {
          result += 'try';
        } finally {
          result += 'finally';
        }

        result;
      ''';

      final result = interpreter.eval(code);
      expect(result.primitiveValue, equals('tryfinally'));
    });

    test('Try/Catch - Exception Propagation', () {
      final code = '''
        try {
          throw "unhandled error";
        } catch (e) {
          // Exception handled
        }

        "success";
      ''';

      final result = interpreter.eval(code);
      expect(result.primitiveValue, equals('success'));
    });

    test('Array Methods - Splice', () {
      final code = '''
        var arr = [1, 2, 3, 4, 5];

        // Remove an element
        var removed = arr.splice(2, 1);  // Removes the element at index 2

        // Add elements
        arr.splice(2, 0, 10, 20);  // Adds 10, 20 at index 2

        // Replace elements
        arr.splice(1, 2, 100);  // Replaces elements 1 and 2 with 100

        [arr.length, removed[0], arr[0], arr[1], arr[2]];
      ''';

      final result = interpreter.eval(code);
      final resultList = (result as JSArray).toList();

      expect(resultList.length, equals(5));
      expect(resultList[0], equals(5.0)); // arr.length
      expect(resultList[1], equals(3.0)); // removed[0]
      expect(resultList[2], equals(1.0)); // arr[0]
      expect(resultList[3], equals(100.0)); // arr[1]
      expect(resultList[4], equals(20.0)); // arr[2]
    });

    test('Array Methods - Sort with Comparator', () {
      final code = '''
        var arr = [3, 1, 4, 1, 5, 9, 2, 6];

        // Tri croissant
        arr.sort(function(a, b) {
          return a - b;
        });

        var ascending = arr.slice();  // Copie du tableau

        // Descending sort
        arr.sort(function(a, b) {
          return b - a;
        });

        [ascending[0], ascending[ascending.length-1], arr[0], arr[arr.length-1]];
      ''';

      final result = interpreter.eval(code);
      final resultList = (result as JSArray).toList();

      expect(resultList.length, equals(4));
      expect(resultList[0], equals(1.0)); // ascending[0]
      expect(resultList[1], equals(9.0)); // ascending[last]
      expect(resultList[2], equals(9.0)); // descending[0]
      expect(resultList[3], equals(1.0)); // descending[last]
    });

    test('Array Methods - Complex Sort', () {
      final code = '''
        var people = [
          {name: 'Alice', age: 25},
          {name: 'Bob', age: 30},
          {name: 'Charlie', age: 20}
        ];

        // Sort by ascending age
        people.sort(function(a, b) {
          return a.age - b.age;
        });

        [people[0].name, people[1].name, people[2].name];
      ''';

      final result = interpreter.eval(code);
      final resultList = (result as JSArray).toList();

      expect(resultList.length, equals(3));
      expect(resultList[0], equals('Charlie')); // 20 ans
      expect(resultList[1], equals('Alice')); // 25 ans
      expect(resultList[2], equals('Bob')); // 30 ans
    });

    test('Combined ES5 Features - Complex Scenario', () {
      final code = '''
        var score = 0;
        var results = [];

        // Test increment operators
        var x = 5;
        ++x;  // x = 6
        x++;  // x = 7

        // Test switch avec les nouvelles valeurs
        switch (x) {
          case 5:
            score += 10;
            break;
          case 6:
            score += 20;
            break;
          case 7:
            score += 30;
            break;
          default:
            score += 0;
        }

        results.push(score);  // 30

        // Test try/catch with operators
        try {
          var y = 10;
          if (++y > 10) {
            throw "Test exception";
          }
        } catch (e) {
          score += 5;  // Bonus for handled exception
        }

        results.push(score);  // 35

        // Test array methods
        var arr = [3, 1, 4, 1, 5];
        arr.splice(2, 1, 9, 2);  // [3, 1, 9, 2, 5]
        arr.sort(function(a, b) { return b - a; });  // Descending sort

        results.push(arr.length);  // 5
        results.push(arr[0]);      // 9 (plus grand)

        results;
      ''';

      final result = interpreter.eval(code);
      final resultList = (result as JSArray).toList();

      expect(resultList.length, equals(4));
      expect(resultList[0], equals(30.0)); // score after switch
      expect(resultList[1], equals(35.0)); // score after try/catch
      expect(resultList[2], equals(6.0)); // arr.length
      expect(resultList[3], equals(9.0)); // arr[0] after sort
    });

    test('Switch with Break and Continue in Loops', () {
      final code = '''
        var result = '';
        var numbers = [1, 2, 3, 4, 5];

        for (var i = 0; i < numbers.length; i++) {
          switch (numbers[i]) {
            case 1:
              result += 'one';
              break;
            case 2:
              result += 'two';
              continue;
            case 3:
              result += 'three';
              break;
            case 4:
              result += 'four';
              break;
            default:
              result += 'other';
          }
          result += '-';
        }

        result;
      ''';

      final result = interpreter.eval(code);
      expect(result.primitiveValue, equals('one-twothree-four-other-'));
    });

    test('Nested Try/Catch with Switch', () {
      final code = '''
        var result = '';

        try {
          result += 'outer-try';

          try {
            result += '-inner-try';
            throw 'inner-error';
          } catch (innerE) {
            result += '-inner-catch';

            var x = 2;
            switch (x) {
              case 1:
                result += '-case1';
                break;
              case 2:
                result += '-case2';
                break;
              default:
                result += '-default';
            }

            throw 'outer-error';
          }

        } catch (outerE) {
          result += '-outer-catch';
        } finally {
          result += '-finally';
        }

        result;
      ''';

      final result = interpreter.eval(code);
      expect(
        result.primitiveValue,
        equals('outer-try-inner-try-inner-catch-case2-outer-catch-finally'),
      );
    });
  });
}
