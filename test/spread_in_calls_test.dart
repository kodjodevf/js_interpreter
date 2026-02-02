import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });

  group('Spread in Function Calls - Basic', () {
    test('spread single array', () {
      final code = '''
        function sum(a, b, c) {
          return a + b + c;
        }
        const numbers = [1, 2, 3];
        sum(...numbers);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(6));
    });

    test('spread with additional arguments before', () {
      final code = '''
        function sum(a, b, c, d) {
          return a + b + c + d;
        }
        const numbers = [2, 3];
        sum(1, ...numbers, 4);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(10));
    });

    test('spread with additional arguments after', () {
      final code = '''
        function sum(a, b, c, d) {
          return a + b + c + d;
        }
        const numbers = [1, 2];
        sum(...numbers, 3, 4);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(10));
    });

    test('spread multiple arrays', () {
      final code = '''
        function sum(a, b, c, d, e, f) {
          return a + b + c + d + e + f;
        }
        const arr1 = [1, 2];
        const arr2 = [3, 4];
        const arr3 = [5, 6];
        sum(...arr1, ...arr2, ...arr3);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(21));
    });

    test('spread with mixed arguments', () {
      final code = '''
        function concat(a, b, c, d, e) {
          return '' + a + b + c + d + e;
        }
        const arr1 = ['b', 'c'];
        const arr2 = ['e'];
        concat('a', ...arr1, 'd', ...arr2);
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('abcde'));
    });
  });

  group('Spread in Function Calls - Strings', () {
    test('spread string into function', () {
      final code = '''
        function concat(a, b, c) {
          return a + b + c;
        }
        concat(...'abc');
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('abc'));
    });

    test('spread string with other arguments', () {
      final code = '''
        function makeString(a, b, c, d, e) {
          return a + b + c + d + e;
        }
        makeString('a', ...'bc', 'd', 'e');
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('abcde'));
    });
  });

  group('Spread in Function Calls - Math Functions', () {
    test('Math.max with spread', () {
      final code = '''
        const numbers = [5, 2, 8, 1, 9, 3];
        Math.max(...numbers);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(9));
    });

    test('Math.min with spread', () {
      final code = '''
        const numbers = [5, 2, 8, 1, 9, 3];
        Math.min(...numbers);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(1));
    });

    test('Math.max with spread and additional args', () {
      final code = '''
        const numbers = [5, 2, 8];
        Math.max(...numbers, 10, 1);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(10));
    });
  });

  group('Spread in Function Calls - Array Methods', () {
    test('Array.push with spread', () {
      final code = '''
        const arr1 = [1, 2];
        const arr2 = [3, 4, 5];
        arr1.push(...arr2);
        arr1;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(5));
      expect(
        array.elements.map((e) => e.toNumber()).toList(),
        equals([1, 2, 3, 4, 5]),
      );
    });

    test('Array.unshift with spread', () {
      final code = '''
        const arr1 = [4, 5];
        const arr2 = [1, 2, 3];
        arr1.unshift(...arr2);
        arr1;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(5));
      expect(
        array.elements.map((e) => e.toNumber()).toList(),
        equals([1, 2, 3, 4, 5]),
      );
    });

    test('Array.concat with spread', () {
      final code = '''
        const arr1 = [1, 2];
        const arr2 = [3, 4];
        const arr3 = [5, 6];
        const result = arr1.concat(...arr2, ...arr3);
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(6));
      expect(
        array.elements.map((e) => e.toNumber()).toList(),
        equals([1, 2, 3, 4, 5, 6]),
      );
    });
  });

  group('Spread in Function Calls - Constructor Calls', () {
    test('Date constructor with spread', () {
      final code = '''
        const dateArgs = [2024, 0, 15]; // Jan 15, 2024
        const date = new Date(...dateArgs);
        date.getFullYear();
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(2024));
    });

    test('Array constructor with spread', () {
      final code = '''
        const sizes = [5];
        const arr = new Array(...sizes);
        arr.length;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(5));
    });
  });

  group('Spread in Function Calls - Rest Parameters', () {
    test('spread with rest parameters', () {
      final code = '''
        function sum(first, ...rest) {
          let total = first;
          for (const num of rest) {
            total += num;
          }
          return total;
        }
        const numbers = [2, 3, 4, 5];
        sum(1, ...numbers);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(15));
    });

    test('spread with rest and default parameters', () {
      final code = '''
        function greet(greeting = 'Hello', ...names) {
          return greeting + ' ' + names.join(' and ');
        }
        const people = ['Alice', 'Bob'];
        greet('Hi', ...people);
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('Hi Alice and Bob'));
    });
  });

  group('Spread in Function Calls - Arrow Functions', () {
    test('arrow function with spread', () {
      final code = '''
        const sum = (...nums) => nums.reduce((a, b) => a + b, 0);
        const numbers = [1, 2, 3, 4, 5];
        sum(...numbers);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(15));
    });

    test('arrow function with spread and other args', () {
      final code = '''
        const multiply = (factor, ...nums) => nums.map(n => n * factor);
        const numbers = [2, 3, 4];
        const result = multiply(10, ...numbers);
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(
        array.elements.map((e) => e.toNumber()).toList(),
        equals([20, 30, 40]),
      );
    });
  });

  group('Spread in Function Calls - Method Calls', () {
    test('object method with spread', () {
      final code = '''
        const obj = {
          sum: function(...nums) {
            return nums.reduce((a, b) => a + b, 0);
          }
        };
        const numbers = [10, 20, 30];
        obj.sum(...numbers);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(60));
    });

    test('class method with spread', () {
      final code = '''
        class Calculator {
          add(...nums) {
            return nums.reduce((a, b) => a + b, 0);
          }
        }
        const calc = new Calculator();
        const numbers = [5, 10, 15];
        calc.add(...numbers);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(30));
    });
  });

  group('Spread in Function Calls - Edge Cases', () {
    test('spread empty array', () {
      final code = '''
        function test() {
          return arguments.length;
        }
        const arr = [];
        test(...arr);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(0));
    });

    test('spread with undefined', () {
      final code = '''
        function test(a, b, c) {
          return [a, b, c];
        }
        const arr = [1];
        const result = test(...arr);
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(3));
      expect(array.elements[0].toNumber(), equals(1));
      expect(array.elements[1].type, equals(JSValueType.undefined));
      expect(array.elements[2].type, equals(JSValueType.undefined));
    });

    test('multiple spreads of same array', () {
      final code = '''
        function concat(...args) {
          return args.join('');
        }
        const arr = ['a', 'b'];
        concat(...arr, ...arr, ...arr);
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('ababab'));
    });

    test('spread in nested function calls', () {
      final code = '''
        function outer(a, b, c) {
          function inner(x, y, z) {
            return x + y + z;
          }
          return inner(...[a, b, c]);
        }
        outer(1, 2, 3);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(6));
    });
  });

  group('Spread in Function Calls - Console Log', () {
    test('console.log with spread', () {
      final code = '''
        const messages = ['Hello', 'World', 'from', 'JS'];
        console.log(...messages);
      ''';
      // This should not throw
      expect(() => interpreter.eval(code), returnsNormally);
    });

    test('console.log with spread and other args', () {
      final code = '''
        const values = [42, true, null];
        console.log('Values:', ...values, 'end');
      ''';
      // This should not throw
      expect(() => interpreter.eval(code), returnsNormally);
    });
  });

  group('Spread in Function Calls - Practical Examples', () {
    test('merge arrays with spread in function', () {
      final code = '''
        function merge(...arrays) {
          const result = [];
          for (const arr of arrays) {
            result.push(...arr);
          }
          return result;
        }
        const arr1 = [1, 2];
        const arr2 = [3, 4];
        const arr3 = [5, 6];
        merge(arr1, arr2, arr3);
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(
        array.elements.map((e) => e.toNumber()).toList(),
        equals([1, 2, 3, 4, 5, 6]),
      );
    });

    test('find maximum in multiple arrays', () {
      final code = '''
        function findMax(...arrays) {
          const allNumbers = [];
          for (const arr of arrays) {
            allNumbers.push(...arr);
          }
          return Math.max(...allNumbers);
        }
        findMax([1, 5, 3], [2, 8, 4], [6, 9, 7]);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(9));
    });

    test('apply function to array elements', () {
      final code = '''
        function transform(fn, ...values) {
          return values.map(fn);
        }
        const double = x => x * 2;
        const numbers = [1, 2, 3, 4];
        const result = transform(double, ...numbers);
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(
        array.elements.map((e) => e.toNumber()).toList(),
        equals([2, 4, 6, 8]),
      );
    });
  });
}
