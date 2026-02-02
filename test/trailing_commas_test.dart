import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

/// Tests complets pour Trailing commas in function parameter lists - ECMAScript 2017 (ES8)
///
/// ES2017 permet les virgules terminales (trailing commas) dans :
/// - Function parameters
/// - Les appels de fonctions
/// - Les arrow functions
void main() {
  group('Trailing Commas - ES2017', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('Function declarations', () {
      test('should accept trailing comma in parameters', () {
        const code = '''
          function add(a, b,) {
            return a + b;
          }
          add(1, 2);
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(3));
      });

      test('should work with single parameter and trailing comma', () {
        const code = '''
          function double(x,) {
            return x * 2;
          }
          double(5);
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(10));
      });

      test('should work with multiple parameters and trailing comma', () {
        const code = '''
          function sum(a, b, c,) {
            return a + b + c;
          }
          sum(1, 2, 3);
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(6));
      });

      test('should work with default parameters and trailing comma', () {
        const code = '''
          function greet(name, greeting = "Hello",) {
            return greeting + " " + name;
          }
          greet("World");
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('Hello World'));
      });

      test('should NOT allow trailing comma after rest parameter', () {
        // ES2017: Rest parameter must be last, no comma allowed after it
        const code = '''
          function sum(first, ...rest,) {
            let total = first;
            for (let i = 0; i < rest.length; i++) {
              total += rest[i];
            }
            return total;
          }
        ''';
        expect(() => interpreter.eval(code), throwsA(isA<dynamic>()));
      });

      test('should work with rest parameters WITHOUT trailing comma', () {
        const code = '''
          function sum(first, ...rest) {
            let total = first;
            for (let i = 0; i < rest.length; i++) {
              total += rest[i];
            }
            return total;
          }
          sum(1, 2, 3, 4);
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(10));
      });
    });

    group('Function expressions', () {
      test('should accept trailing comma in function expression', () {
        const code = '''
          const multiply = function(x, y,) {
            return x * y;
          };
          multiply(3, 4);
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(12));
      });

      test('should work with named function expression', () {
        const code = '''
          const factorial = function fact(n,) {
            if (n <= 1) return 1;
            return n * fact(n - 1);
          };
          factorial(5);
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(120));
      });
    });

    group('Arrow functions', () {
      test('should accept trailing comma in arrow function parameters', () {
        const code = '''
          const add = (a, b,) => a + b;
          add(10, 20);
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(30));
      });

      test(
        'should work with single parameter (no parens, no trailing comma)',
        () {
          const code = '''
          const double = x => x * 2;
          double(7);
        ''';
          final result = interpreter.eval(code);
          expect(result.toNumber(), equals(14));
        },
      );

      test('should work with multiple parameters and trailing comma', () {
        const code = '''
          const sum = (a, b, c,) => a + b + c;
          sum(1, 2, 3);
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(6));
      });

      test('should work with arrow function and block body', () {
        const code = '''
          const compute = (x, y,) => {
            const result = x + y;
            return result * 2;
          };
          compute(5, 3);
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(16));
      });

      test('should NOT allow trailing comma after rest parameter', () {
        // ES2017: Rest parameter MUST be the last parameter, no comma after it
        const code = '''
          const sum = (...numbers,) => {
            let total = 0;
            for (let num of numbers) {
              total += num;
            }
            return total;
          };
        ''';
        expect(() => interpreter.eval(code), throwsA(isA<dynamic>()));
      });

      test('should work with rest parameters WITHOUT trailing comma', () {
        const code = '''
          const sum = (...numbers) => {
            let total = 0;
            for (let num of numbers) {
              total += num;
            }
            return total;
          };
          sum(1, 2, 3, 4, 5);
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(15));
      });
    });

    group('Function calls', () {
      test('should accept trailing comma in function call', () {
        const code = '''
          function multiply(x, y) {
            return x * y;
          }
          multiply(6, 7,);
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(42));
      });

      test('should work with single argument and trailing comma', () {
        const code = '''
          function square(x) {
            return x * x;
          }
          square(9,);
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(81));
      });

      test('should work with multiple arguments and trailing comma', () {
        const code = '''
          function sum(a, b, c) {
            return a + b + c;
          }
          sum(10, 20, 30,);
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(60));
      });

      test('should work with nested function calls', () {
        const code = '''
          function add(a, b) {
            return a + b;
          }
          function multiply(x, y) {
            return x * y;
          }
          multiply(add(1, 2,), add(3, 4,),);
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(21));
      });

      test('should work with method calls', () {
        const code = '''
          const obj = {
            add: function(a, b) {
              return a + b;
            }
          };
          obj.add(5, 10,);
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(15));
      });
    });

    group('Async functions', () {
      test('should accept trailing comma in async function', () async {
        const code = '''
          async function fetchData(url, options,) {
            return url + " with options";
          }
          fetchData("test.com", {},);
        ''';
        final result = await interpreter.evalAsync(code);
        expect(result.toString(), contains('test.com'));
      });

      test('should work with async arrow function', () async {
        const code = '''
          const process = async (data,) => {
            return data * 2;
          };
          process(50);
        ''';
        final result = await interpreter.evalAsync(code);
        // Result will be a Promise, but we can check it doesn't throw
        expect(result, isNotNull);
      });
    });

    group('Edge cases', () {
      test('should work with empty parameter list (no comma)', () {
        const code = '''
          function noParams() {
            return 42;
          }
          noParams();
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(42));
      });

      test('should work without trailing comma (backward compatibility)', () {
        const code = '''
          function add(a, b) {
            return a + b;
          }
          add(1, 2);
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(3));
      });

      test('should work in constructor calls', () {
        const code = '''
          class Point {
            constructor(x, y) {
              this.x = x;
              this.y = y;
            }
          }
          const p = new Point(10, 20,);
          p.x + p.y;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(30));
      });

      test('should work with spread operator in calls', () {
        const code = '''
          function sum(a, b, c) {
            return a + b + c;
          }
          const numbers = [1, 2, 3];
          sum(...numbers,);
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(6));
      });

      test('should work in higher-order functions', () {
        const code = '''
          function apply(fn, a, b,) {
            return fn(a, b);
          }
          function multiply(x, y) {
            return x * y;
          }
          apply(multiply, 4, 5,);
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(20));
      });
    });

    group('Real-world patterns', () {
      test('should improve code formatting in multiline parameters', () {
        const code = '''
          function createUser(
            name,
            email,
            age,
          ) {
            return name + ":" + email + ":" + age;
          }
          createUser(
            "Alice",
            "alice@example.com",
            30,
          );
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('Alice:alice@example.com:30'));
      });

      test('should work in array methods with callbacks', () {
        const code = '''
          const numbers = [1, 2, 3, 4, 5];
          const doubled = numbers.map(function(x,) {
            return x * 2;
          },);
          doubled[2];
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(6));
      });

      test('should work with event handlers pattern', () {
        const code = '''
          function addEventListener(event, callback,) {
            return callback(event);
          }
          addEventListener("click", function(e,) {
            return e + " handled";
          },);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('click handled'));
      });

      test('should work in promise chains', () {
        const code = '''
          function then(callback,) {
            return callback(42);
          }
          then(function(value,) {
            return value * 2;
          },);
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(84));
      });
    });

    group('Combining features', () {
      test(
        'should work with default params and trailing comma, rest without',
        () {
          // ES2017: Trailing comma is NOT allowed after rest parameter
          const code = '''
          function complex(a, b = 10, ...rest) {
            let sum = a + b;
            for (let val of rest) {
              sum += val;
            }
            return sum;
          }
          complex(5, 15, 20, 25,);
        ''';
          final result = interpreter.eval(code);
          expect(result.toNumber(), equals(65));
        },
      );

      test('should work with destructuring and trailing comma', () {
        const code = '''
          function process({x, y},) {
            return x + y;
          }
          process({x: 10, y: 20},);
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(30));
      });
    });
  });
}
