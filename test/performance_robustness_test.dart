import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });

  group('Performance and Robustness Tests', () {
    test('Large Array Operations Performance', () {
      final code = '''
        // Create large array
        const largeArray = [];
        for (let i = 0; i < 1000; i++) {
          largeArray.push(i);
        }

        // Test various array operations
        const sum = largeArray.reduce(function(acc, val) {
          return acc + val;
        }, 0);

        const filtered = largeArray.filter(function(val) {
          return val % 2 === 0;
        });

        const mapped = largeArray.map(function(val) {
          return val * 2;
        });

        const found = largeArray.find(function(val) {
          return val > 500;
        });

        [largeArray.length, sum, filtered.length, mapped[0], found];
      ''';

      final result = interpreter.eval(code);
      final results = (result as JSArray).toList();

      expect(results[0], equals(1000.0)); // array length
      expect(results[1], equals(499500.0)); // sum of 0-999
      expect(results[2], equals(500.0)); // even numbers count
      expect(results[3], equals(0.0)); // first mapped value
      expect(results[4], equals(501.0)); // first value > 500
    });

    test('Deep Recursion Handling', () {
      final code = '''
        // Test deep recursion
        function factorial(n) {
          if (n <= 1) {
            return 1;
          }
          return n * factorial(n - 1);
        }

        function fibonacci(n) {
          if (n <= 1) {
            return n;
          }
          return fibonacci(n - 1) + fibonacci(n - 2);
        }

        // Test with reasonable values to avoid stack overflow
        const fact10 = factorial(10);  // 3,628,800
        const fib15 = fibonacci(15);   // 610

        [fact10, fib15];
      ''';

      final result = interpreter.eval(code);
      final results = (result as JSArray).toList();

      expect(results[0], equals(3628800.0)); // 10!
      expect(results[1], equals(610.0)); // fibonacci(15)
    });

    test('Memory Management with Large Objects', () {
      final code = '''
        // Create many objects
        const objects = [];
        for (let i = 0; i < 10; i++) {
          const obj = {
            id: i,
            name: 'Object_' + i,
            data: [i, i + 1, i + 2]
          };
          objects.push(obj);
        }

        // Simple processing
        let totalDataSum = 0;
        for (let i = 0; i < objects.length; i++) {
          const obj = objects[i];
          for (let j = 0; j < obj.data.length; j++) {
            totalDataSum += obj.data[j];
          }
        }

        const firstName = objects[0].name;
        const lastName = objects[objects.length - 1].name;

        [objects.length, totalDataSum, firstName, lastName];
      ''';

      final result = interpreter.eval(code);
      final results = (result as JSArray).toList();

      expect(results[0], equals(10.0)); // objects count
      expect(results[1] > 0, isTrue); // total data sum
      expect(results[2], equals('Object_0')); // first name
      expect(results[3], equals('Object_9')); // last name
    });

    test('Complex String Operations', () {
      final code = '''
        // Large string operations
        let largeString = '';
        for (let i = 0; i < 100; i++) {
          largeString += 'Word' + i + ' ';
        }

        const words = largeString.trim().split(' ');
        const reversed = words.reverse().join(' ');
        const upper = largeString.toUpperCase();
        const substring = largeString.substring(10, 30);

        [words.length, reversed.length > 0, upper.length > 0, substring.length];
      ''';

      final result = interpreter.eval(code);
      final results = (result as JSArray).toList();

      expect(results[0], equals(100.0)); // word count
      expect(results[1], equals(true)); // reversed string exists
      expect(results[2], equals(true)); // uppercase string exists
      expect(results[3], equals(20.0)); // substring length
    });

    test('Error Recovery and Exception Handling', () {
      final code = '''
        let errorCount = 0;
        let successCount = 0;

        function riskyOperation(value) {
          if (value < 0) {
            throw new Error('Negative value: ' + value);
          }
          if (value === 0) {
            throw new TypeError('Zero not allowed');
          }
          return 100 / value;
        }

        // Test multiple error scenarios
        const testValues = [10, 0, -5, 2, 0, 20];

        for (let i = 0; i < testValues.length; i++) {
          try {
            const result = riskyOperation(testValues[i]);
            successCount++;
          } catch (error) {
            errorCount++;
          }
        }

        [errorCount, successCount, testValues.length];
      ''';

      final result = interpreter.eval(code);
      final results = (result as JSArray).toList();

      expect(results[0], equals(3.0)); // error count (0, -5, 0)
      expect(results[1], equals(3.0)); // success count (10, 2, 20)
      expect(results[2], equals(6.0)); // total test values
    });

    test('Complex Object Property Access', () {
      final code = '''
        // Deep nested object
        const data = {
          users: {
            active: [
              { id: 1, profile: { name: 'Alice', age: 25 } },
              { id: 2, profile: { name: 'Bob', age: 30 } }
            ],
            inactive: [
              { id: 3, profile: { name: 'Charlie', age: 35 } }
            ]
          },
          settings: {
            theme: 'dark',
            notifications: {
              email: true,
              push: false
            }
          }
        };

        // Complex property access
        const activeUsers = data.users.active;
        const firstUserName = data.users.active[0].profile.name;
        const settings = data.settings;
        const emailNotifications = data.settings.notifications.email;

        // Dynamic property access
        const propertyPath = ['users', 'active', '1', 'profile', 'age'];
        let current = data;
        for (let i = 0; i < propertyPath.length; i++) {
          current = current[propertyPath[i]];
        }
        const dynamicAge = current;

        [activeUsers.length, firstUserName, emailNotifications, dynamicAge];
      ''';

      final result = interpreter.eval(code);
      final results = (result as JSArray).toList();

      expect(results[0], equals(2.0)); // active users count
      expect(results[1], equals('Alice')); // first user name
      expect(results[2], equals(true)); // email notifications
      expect(results[3], equals(30.0)); // dynamic property access result
    });

    test('Function Overloading and Method Dispatch', () {
      final code = '''
        // Simple function with different behaviors
        function calculate(operation, a, b, c) {
          switch (operation) {
            case 'sum':
              return a + b + c;
            case 'multiply':
              return a * b * c;
            case 'average':
              return (a + b + c) / 3;
            default:
              return 0;
          }
        }

        // Simple calculator object
        const calculator = {
          add: function(a, b) {
            if (b === undefined) {
              return function(b) { return a + b; };
            }
            return a + b;
          },

          subtract: function(a, b) {
            return a - b;
          }
        };

        const sum = calculate('sum', 1, 2, 3);        // 6
        const product = calculate('multiply', 2, 3, 4); // 24
        const avg = calculate('average', 10, 20, 30);   // 20
        const add5 = calculator.add(5);                  // partial application
        const result1 = add5(10);                        // 15
        const result2 = calculator.add(7, 3);            // 10

        [sum, product, avg, result1, result2];
      ''';

      final result = interpreter.eval(code);
      final results = (result as JSArray).toList();

      expect(results[0], equals(6.0)); // sum
      expect(results[1], equals(24.0)); // product
      expect(results[2], equals(20.0)); // average
      expect(results[3], equals(15.0)); // partial application result
      expect(results[4], equals(10.0)); // direct addition
    });

    test('Scope Chain and Variable Resolution', () {
      final code = '''
        // Global scope
        var globalVar = 'global';

        function outer() {
          var outerVar = 'outer';

          function middle() {
            var middleVar = 'middle';

            function inner() {
              var innerVar = 'inner';

              // Access all scopes
              return globalVar + '-' + outerVar + '-' + middleVar + '-' + innerVar;
            }

            return inner;
          }

          return middle;
        }

        // Test scope chain
        const innerFn = outer()();
        const scopeChain = innerFn();

        // Variable shadowing
        var shadowed = 'global_value';
        function testShadowing() {
          var shadowed = 'local_value';
          return shadowed;
        }

        const shadowedResult = testShadowing();

        // Closure capturing
        function createCounter() {
          var count = 0;
          return function() {
            count++;
            return count;
          };
        }

        const counter1 = createCounter();
        const counter2 = createCounter();

        const count1_1 = counter1();  // 1
        const count1_2 = counter1();  // 2
        const count2_1 = counter2();  // 1

        [scopeChain, shadowedResult, count1_1, count1_2, count2_1];
      ''';

      final result = interpreter.eval(code);
      final results = (result as JSArray).toList();

      expect(results[0], equals('global-outer-middle-inner')); // scope chain
      expect(results[1], equals('local_value')); // shadowing
      expect(results[2], equals(1.0)); // counter1 first call
      expect(results[3], equals(2.0)); // counter1 second call
      expect(results[4], equals(1.0)); // counter2 first call
    });
  });
}
