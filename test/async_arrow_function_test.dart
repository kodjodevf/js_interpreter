import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Async Arrow Function Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Simple async arrow function with expression', () async {
      final result = await interpreter.evalAsync('''
        const asyncDouble = async (x) => x * 2;
        asyncDouble(21);
      ''');
      expect(result.toString(), equals('42'));
    });

    test('Async arrow function with block body', () async {
      final result = await interpreter.evalAsync('''
        const asyncSum = async (a, b) => {
          return a + b;
        };
        asyncSum(10, 32);
      ''');
      expect(result.toString(), equals('42'));
    });

    test(
      'Async arrow function with single parameter (no parentheses)',
      () async {
        final result = await interpreter.evalAsync('''
        const asyncSquare = async x => x * x;
        asyncSquare(7);
      ''');
        expect(result.toString(), equals('49'));
      },
    );

    test('Async arrow function with no parameters', () async {
      final result = await interpreter.evalAsync('''
        const getAnswer = async () => 42;
        getAnswer();
      ''');
      expect(result.toString(), equals('42'));
    });

    test('Async arrow function with await inside', () async {
      final result = await interpreter.evalAsync('''
        const delay = async (value) => Promise.resolve(value);
        
        const processValue = async (x) => {
          const result = await delay(x);
          return result * 2;
        };
        
        processValue(21);
      ''');
      expect(result.toString(), equals('42'));
    });

    test('Chain async arrow functions', () async {
      final result = await interpreter.evalAsync('''
        const step1 = async (x) => x + 1;
        const step2 = async (x) => x * 2;
        const step3 = async (x) => x - 3;
        
        async function process(value) {
          let result = await step1(value);
          result = await step2(result);
          result = await step3(result);
          return result;
        }
        
        process(10);
      ''');
      expect(result.toString(), equals('19')); // (10 + 1) * 2 - 3 = 19
    });

    test('Async arrow function with error handling', () async {
      try {
        await interpreter.evalAsync('''
          const mayFail = async (shouldFail) => {
            if (shouldFail) {
              throw new Error('Failed on purpose');
            }
            return 'Success';
          };
          mayFail(true);
        ''');
        fail('Should have thrown an error');
      } catch (e) {
        expect(e, isNotNull);
      }
    });

    test('Async arrow function with try/catch inside', () async {
      final result = await interpreter.evalAsync('''
        const safeFunction = async (x) => {
          try {
            if (x < 0) {
              throw new Error('Negative number');
            }
            return x * 2;
          } catch (e) {
            return 0;
          }
        };
        
        safeFunction(-5);
      ''');
      expect(result.toString(), equals('0'));
    });

    test('Async arrow function returning Promise.resolve', () async {
      final result = await interpreter.evalAsync('''
        const getValue = async () => Promise.resolve(100);
        getValue();
      ''');
      expect(result.toString(), equals('100'));
    });

    test('Async arrow function returning Promise.reject', () async {
      try {
        await interpreter.evalAsync('''
          const getError = async () => Promise.reject('Error message');
          getError();
        ''');
        fail('Should have thrown an error');
      } catch (e) {
        expect(e, isNotNull);
      }
    });

    test(
      'Multiple async arrow functions with different param counts',
      () async {
        final result = await interpreter.evalAsync('''
        const noParams = async () => 1;
        const oneParam = async (x) => x + 1;
        const twoParams = async (x, y) => x + y;
        const threeParams = async (x, y, z) => x + y + z;
        
        async function test() {
          const a = await noParams();
          const b = await oneParam(a);
          const c = await twoParams(b, 3);
          const d = await threeParams(c, 5, 7);
          return d;
        }
        
        test();
      ''');
        expect(
          result.toString(),
          equals('17'),
        ); // 1 -> 1+1=2 -> 2+3=5 -> 5+5+7=17
      },
    );

    test('Async arrow function with conditional logic', () async {
      final result = await interpreter.evalAsync('''
        const checkValue = async (x) => {
          if (x > 10) {
            return 'big';
          } else {
            return 'small';
          }
        };
        
        checkValue(15);
      ''');
      expect(result.toString(), equals('big'));
    });

    test('Async arrow function with ternary operator', () async {
      final result = await interpreter.evalAsync('''
        const isEven = async (x) => x % 2 === 0 ? 'even' : 'odd';
        isEven(8);
      ''');
      expect(result.toString(), equals('even'));
    });

    test('Async arrow function in array map', () async {
      final result = await interpreter.evalAsync('''
        const numbers = [1, 2, 3, 4, 5];
        const asyncDouble = async (x) => x * 2;
        
        async function processAll() {
          const results = [];
          for (const num of numbers) {
            const doubled = await asyncDouble(num);
            results.push(doubled);
          }
          return results;
        }
        
        processAll();
      ''');

      final resultObj = result as JSArray;
      expect(resultObj.length, equals(5));
      expect(resultObj.get(0).toString(), equals('2'));
      expect(resultObj.get(4).toString(), equals('10'));
    });

    test('Async arrow function nested in regular function', () async {
      final result = await interpreter.evalAsync('''
        function createAsyncMultiplier(factor) {
          return async (x) => x * factor;
        }
        
        const multiplyByTen = createAsyncMultiplier(10);
        multiplyByTen(4);
      ''');
      expect(result.toString(), equals('40'));
    });

    test('Async arrow function with closure', () async {
      final result = await interpreter.evalAsync('''
        function makeCounter() {
          let count = 0;
          return async () => ++count;
        }
        
        const counter = makeCounter();
        
        async function test() {
          const a = await counter();
          const b = await counter();
          const c = await counter();
          return a + b + c;
        }
        
        test();
      ''');
      expect(result.toString(), equals('6')); // 1 + 2 + 3
    });

    test('Async arrow function with object return', () async {
      final result = await interpreter.evalAsync('''
        const createUser = async (name, age) => {
          return { name: name, age: age };
        };
        
        async function test() {
          const user = await createUser('Alice', 30);
          return user.name + ' is ' + user.age;
        }
        
        test();
      ''');
      expect(result.toString(), equals('Alice is 30'));
    });

    test('Async arrow function with array destructuring', () async {
      final result = await interpreter.evalAsync('''
        const getValues = async () => [1, 2, 3];
        
        async function test() {
          const [a, b, c] = await getValues();
          return a + b + c;
        }
        
        test();
      ''');
      expect(result.toString(), equals('6'));
    });

    test('Async arrow function with object destructuring', () async {
      final result = await interpreter.evalAsync('''
        const getUser = async () => ({ name: 'Bob', age: 25 });
        
        async function test() {
          const { name, age } = await getUser();
          return name + ' is ' + age;
        }
        
        test();
      ''');
      expect(result.toString(), equals('Bob is 25'));
    });

    test('Mix of async arrow and async regular functions', () async {
      final result = await interpreter.evalAsync('''
        const arrowFunc = async (x) => x * 2;
        
        async function regularFunc(x) {
          return x + 10;
        }
        
        async function test() {
          const a = await arrowFunc(5);
          const b = await regularFunc(a);
          return b;
        }
        
        test();
      ''');
      expect(result.toString(), equals('20')); // (5 * 2) + 10
    });

    test('Async arrow function with setTimeout', () async {
      final result = await interpreter.evalAsync('''
        const delayedValue = async (value, delay) => {
          return new Promise((resolve) => {
            setTimeout(() => {
              resolve(value * 2);
            }, delay);
          });
        };
        
        async function test() {
          const result = await delayedValue(21, 10);
          return result;
        }
        
        test();
      ''');
      expect(result.toString(), equals('42'));
    });

    test('Async arrow function as setTimeout callback', () async {
      final result = await interpreter.evalAsync('''
        let capturedValue = 0;
        
        const captureValue = async (x) => {
          capturedValue = x * 3;
          return capturedValue;
        };
        
        async function test() {
          return new Promise((resolve) => {
            setTimeout(async () => {
              const result = await captureValue(14);
              resolve(result);
            }, 10);
          });
        }
        
        test();
      ''');
      expect(result.toString(), equals('42'));
    });

    test('Multiple async arrow functions with setTimeout chaining', () async {
      final result = await interpreter.evalAsync('''
        const step1 = async (x) => {
          return new Promise((resolve) => {
            setTimeout(() => resolve(x + 10), 5);
          });
        };
        
        const step2 = async (x) => {
          return new Promise((resolve) => {
            setTimeout(() => resolve(x * 2), 5);
          });
        };
        
        const step3 = async (x) => {
          return new Promise((resolve) => {
            setTimeout(() => resolve(x - 2), 5);
          });
        };
        
        async function process() {
          let result = await step1(5);
          result = await step2(result);
          result = await step3(result);
          return result;
        }
        
        process();
      ''');
      expect(result.toString(), equals('30')); // (5 + 10) * 2 - 2 = 30
    });

    test('Async arrow function with setTimeout and error handling', () async {
      try {
        await interpreter.evalAsync('''
          const mayFail = async (shouldFail) => {
            return new Promise((resolve, reject) => {
              setTimeout(() => {
                if (shouldFail) {
                  reject(new Error('Timeout error'));
                } else {
                  resolve('Success');
                }
              }, 10);
            });
          };
          
          mayFail(true);
        ''');
        fail('Should have thrown an error');
      } catch (e) {
        expect(e, isNotNull);
      }
    });

    test('Async arrow function with clearTimeout', () async {
      final result = await interpreter.evalAsync('''
        let executed = false;
        
        const testClearTimeout = async () => {
          const timeoutId = setTimeout(() => {
            executed = true;
          }, 10);
          
          // Cancel the timeout immediately
          clearTimeout(timeoutId);
          
          // Return a promise that resolves after enough time to verify timeout was cancelled
          return new Promise((resolve) => {
            setTimeout(() => {
              resolve('cancelled:' + executed);
            }, 50);
          });
        };
        
        testClearTimeout();
      ''');
      expect(result.toString(), equals('cancelled:false'));
    });

    test('Async arrow function race condition with setTimeout', () async {
      final result = await interpreter.evalAsync('''
        const fast = async () => {
          return new Promise((resolve) => {
            setTimeout(() => resolve('fast'), 5);
          });
        };
        
        const slow = async () => {
          return new Promise((resolve) => {
            setTimeout(() => resolve('slow'), 50);
          });
        };
        
        async function race() {
          const result = await Promise.race([fast(), slow()]);
          return result;
        }
        
        race();
      ''');
      expect(result.toString(), equals('fast'));
    });

    test('Async arrow function with nested setTimeout', () async {
      final result = await interpreter.evalAsync('''
        const nested = async (value) => {
          return new Promise((resolve) => {
            setTimeout(() => {
              setTimeout(() => {
                setTimeout(() => {
                  resolve(value * 3);
                }, 5);
              }, 5);
            }, 5);
          });
        };
        
        nested(14);
      ''');
      expect(result.toString(), equals('42'));
    });

    test('Async arrow function returning another async arrow', () async {
      final result = await interpreter.evalAsync('''
        const createMultiplier = async (factor) => {
          return async (value) => value * factor;
        };
        
        async function test() {
          const multiply = await createMultiplier(6);
          const result = await multiply(7);
          return result;
        }
        
        test();
      ''');
      expect(result.toString(), equals('42'));
    });

    test('Async arrow function with Promise.all and setTimeout', () async {
      final result = await interpreter.evalAsync('''
        const task1 = async () => {
          return new Promise((resolve) => {
            setTimeout(() => resolve(10), 10);
          });
        };
        
        const task2 = async () => {
          return new Promise((resolve) => {
            setTimeout(() => resolve(20), 15);
          });
        };
        
        const task3 = async () => {
          return new Promise((resolve) => {
            setTimeout(() => resolve(12), 5);
          });
        };
        
        async function runAll() {
          const results = await Promise.all([task1(), task2(), task3()]);
          return results[0] + results[1] + results[2];
        }
        
        runAll();
      ''');
      expect(result.toString(), equals('42'));
    });
  });
}
