import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('JavaScript Async/Await Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('await Promise.resolve', () async {
      const source = '''
        async function main() {
          const result = await Promise.resolve(42);
          return result;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('42'));
    });

    test('await setTimeout (simulated delay)', () async {
      const source = '''
        async function main() {
          await new Promise(resolve => setTimeout(resolve, 10));
          return "Done";
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('Done'));
    });

    test('Assign await result to variable', () async {
      const source = '''
        async function fetchValue() {
          await new Promise(resolve => setTimeout(resolve, 5));
          return 100;
        }

        async function main() {
          const x = await fetchValue();
          return x + 5;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('105'));
    });

    test('Return await result directly', () async {
      const source = '''
        async function fetchMessage() {
          await new Promise(resolve => setTimeout(resolve, 5));
          return "Returned Message";
        }

        async function main() {
          return await fetchMessage();
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals("Returned Message"));
    });

    test('Multiple awaits in sequence', () async {
      const source = '''
        async function step1() {
          await new Promise(resolve => setTimeout(resolve, 5));
          return 10;
        }

        async function step2(prev) {
          await new Promise(resolve => setTimeout(resolve, 5));
          return prev + 20;
        }

        async function main() {
          const r1 = await step1();
          const r2 = await step2(r1);
          return r2 + 30;
        }
        main();
      ''';
      // 10 -> 10+20=30 -> 30+30=60
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('60'));
    });

    test('Nested async function calls', () async {
      const source = '''
        async function inner() {
          await new Promise(resolve => setTimeout(resolve, 1));
          return 50;
        }

        async function middle() {
          const val = await inner();
          await new Promise(resolve => setTimeout(resolve, 1));
          return val + 50;
        }

        async function main() {
          const result = await middle();
          return result + 50;
        }
        main();
      ''';
      // 50 -> 50+50=100 -> 100+50=150
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('150'));
    });

    test('Sync code between awaits', () async {
      const source = '''
        async function part1() { return "A"; }
        async function part3() { return "C"; }

        async function main() {
          const r1 = await part1();
          const r2 = r1 + "B"; // Sync operation
          const r3 = await part3();
          return r2 + r3; // Sync operation
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals("ABC"));
    });

    test('Return non-Promise from async function', () async {
      const source = '''
        async function getValue() {
          // No await needed here
          return 99;
        }

        async function main() {
          return await getValue();
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('99'));
    });

    test('await in if condition', () async {
      const source = '''
        async function checkCondition() {
          await new Promise(resolve => setTimeout(resolve, 1));
          return true;
        }

        async function main() {
          let result = "Initial";
          if (await checkCondition()) {
            result = "Condition True";
          }
          return result;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals("Condition True"));
    });

    test('await in for loop', () async {
      const source = '''
        async function processItem(i) {
          await new Promise(resolve => setTimeout(resolve, 1));
          return i * 10;
        }

        async function main() {
          let total = 0;
          for (let i = 0; i < 3; i++) {
            total += await processItem(i);
          }
          return total; // 0*10 + 1*10 + 2*10 = 30
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('30'));
    });

    test('await in try/catch (success)', () async {
      const source = '''
        async function successfulFuture() {
          await new Promise(resolve => setTimeout(resolve, 1));
          return "Success";
        }

        async function main() {
          let result = "Failed";
          try {
            result = await successfulFuture();
          } catch (e) {
            result = "Caught Error";
          }
          return result;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals("Success"));
    });

    test('await Promise.reject in try/catch', () async {
      const source = '''
        async function failingFuture() {
          await new Promise(resolve => setTimeout(resolve, 1));
          throw "Future Failed";
        }

        async function main() {
          let result = "Initial";
          try {
            result = await failingFuture();
            result = "Future Succeeded Unexpectedly"; // Should not reach here
          } catch (e) {
            result = "Caught: " + e;
          }
          return result;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals("Caught: Future Failed"));
    });

    test('await Promise.reject without try/catch', () async {
      const source = '''
        async function failingFuture() {
          await new Promise(resolve => setTimeout(resolve, 1));
          throw "Deliberate Error";
        }

        async function main() {
          await failingFuture();
        }
        main();
      ''';
      // This should throw an error
      expect(
        () async => await interpreter.evalAsync(source),
        throwsA(anything),
      );
    });
  });

  group('Async Control Flow Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('async while loop with await in body', () async {
      const source = '''
        async function waitABit() {
          await Promise.resolve(null);
        }

        async function counter(limit) {
          let i = 0;
          let sum = 0;
          while (i < limit) {
            sum = sum + i;
            i = i + 1;
            await waitABit();
          }
          return sum;
        }

        async function main() {
          return await counter(5); // Expect 0+1+2+3+4 = 10
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(10));
    });

    test('async while loop with await in condition', () async {
      const source = '''
        async function shouldContinue(currentVal) {
          await Promise.resolve(null);
          return currentVal < 3;
        }

        async function looper() {
          let i = 0;
          while (await shouldContinue(i)) {
            i = i + 1;
          }
          return i; // Expect i to be 3 when loop terminates
        }

        async function main() {
          return await looper();
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(3));
    });

    test('async do-while loop with await in body', () async {
      const source = '''
        async function waitABit() {
          await Promise.resolve(null);
        }

        async function looper() {
          let i = 0;
          let sum = 0;
          do {
            sum = sum + i;
            await waitABit();
            i = i + 1;
          } while (i < 4);
          return sum; // 0 + 1 + 2 + 3 = 6
        }

        async function main() {
          return await looper();
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(6));
    });

    test('async do-while loop with await in condition', () async {
      const source = '''
        async function shouldContinue(currentVal) {
          await Promise.resolve(null);
          return currentVal < 3;
        }

        async function looper() {
          let i = 0;
          do {
            i = i + 1;
          } while (await shouldContinue(i));
          return i; // Expect 3
        }

        async function main() {
          return await looper();
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(3));
    });

    test('async for loop with await in body', () async {
      const source = '''
        async function waitABit() {
          await Promise.resolve(null);
        }

        async function looper() {
          let sum = 0;
          for (let i = 0; i < 4; i++) {
            sum = sum + i;
            await waitABit();
          }
          return sum; // Expect 0+1+2+3 = 6
        }

        async function main() {
          return await looper();
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(6));
    });

    test('async for loop with await in initializer', () async {
      const source = '''
        async function getStart() {
          await new Promise(resolve => setTimeout(resolve, 1));
          return 1;
        }

        async function looper() {
          let sum = 0;
          for (let i = await getStart(); i < 4; i++) {
            sum = sum + i;
          }
          return sum; // 1+2+3 = 6
        }

        async function main() {
          return await looper();
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(6));
    });

    test('async for loop with await assignment in body', () async {
      const source = '''
        async function getValue(iteration) {
          await new Promise(resolve => setTimeout(resolve, 1));
          return iteration * 10;
        }

        async function looper() {
          let total = 0;
          let lastAwaitedValue = -1;
          for (let i = 0; i < 3; i++) {
            const awaitedValue = await getValue(i);
            lastAwaitedValue = await getValue(i);
            total += i;
          }
          return total + lastAwaitedValue; // 0+1+2 + 20 = 23
        }

        async function main() {
          return await looper();
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(23));
    });

    test('async for loop with await in assignment operator', () async {
      const source = '''
        async function getValue(iteration) {
          await new Promise(resolve => setTimeout(resolve, 1));
          return iteration * 10;
        }

        async function looper() {
          let total = 0;
          for (let i = 0; i < 3; i++) {
            total += await getValue(i);
          }
          return total; // 0 + 10 + 20 = 30
        }

        async function main() {
          return await looper();
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(30));
    });

    test('async for-of loop with await in body', () async {
      const source = '''
        async function getValue(iteration) {
          await new Promise(resolve => setTimeout(resolve, 1));
          return iteration * 10;
        }

        async function testAsyncForOfWithAwaitInBody() {
          const syncList = [1, 2, 3];
          let total = 0;
          for (const item of syncList) {
            const awaitedValue = await getValue(item);
            total += awaitedValue;
            await new Promise(resolve => setTimeout(resolve, 1));
          }
          return total; // 10 + 20 + 30 = 60
        }

        async function main() {
          return await testAsyncForOfWithAwaitInBody();
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(60));
    });

    test('async try-catch-finally with await throwing error', () async {
      const source = '''
        async function operationThatThrows() {
          await new Promise(resolve => setTimeout(resolve, 1));
          throw new Error('Something went wrong asynchronously');
        }

        async function testTryCatch() {
          let status = "Initial";
          let finallyStatus = "Not Executed";
          try {
            status = "In Try";
            await operationThatThrows();
            status = "Try Completed (Should not happen)";
          } catch (e) {
            status = "Caught Error";
          } finally {
            finallyStatus = "Finally Executed";
          }
          return status + ":" + finallyStatus;
        }

        async function main() {
          return await testTryCatch();
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals("Caught Error:Finally Executed"));
    });

    test('async if statement with await in condition', () async {
      const source = '''
        async function checkCondition(value) {
          await new Promise(resolve => setTimeout(resolve, 1));
          return value;
        }

        async function main() {
          let result = 'Initial';
          if (await checkCondition(true)) {
            result = 'First If True';
          } else {
            result = 'First If False (Error)';
          }

          if (await checkCondition(false)) {
            result = 'Second If True (Error)';
          } else {
            result = 'Second If False';
          }
          return result;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('Second If False'));
    });

    test('async try-catch with rethrow and await error', () async {
      const source = '''
        async function operationThatThrows() {
          await new Promise(resolve => setTimeout(resolve, 1));
          throw new Error('Something went wrong asynchronously');
        }

        async function testTryCatch() {
          let status = "Initial";
          try {
            status = "In Try";
            await operationThatThrows();
            status = "Try Completed (Should not happen)";
          } catch (e) {
            throw e; // rethrow
          }
          return "ok";
        }

        async function main() {
          await testTryCatch();
        }
        main();
      ''';
      expect(
        () async => await interpreter.evalAsync(source),
        throwsA(anything),
      );
    });

    test('nested for-of loops with array processing', () async {
      const source = '''
        async function main() {
          const resultList = [];
          for (const element of [
            [1, 2, 3, 4],
            [5, 6, 7, 8]
          ]) {
            const currentElement = element;
            for (const item of currentElement) {
              resultList.push(item);
            }
          }
          return resultList;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      final resultList = (result as JSArray).toList();
      expect(resultList, equals([1, 2, 3, 4, 5, 6, 7, 8]));
    });

    test(
      'nested for loops with array processing using indexed access',
      () async {
        const source = '''
        async function main() {
          const resultList = [];
          const dddd = [
            [1, 2, 3, 4],
            [5, 6, 7, 8]
          ];
          for (let i = 0; i < dddd.length; i++) {
            const currentElement = dddd[i];
            for (let j = 0; j < currentElement.length; j++) {
              resultList.push(currentElement[j]);
            }
          }
          return resultList;
        }
        main();
      ''';
        final result = await interpreter.evalAsync(source);
        final resultList = (result as JSArray).toList();
        expect(resultList, equals([1, 2, 3, 4, 5, 6, 7, 8]));
      },
    );
  });

  group('Advanced Async/Await Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Promise.all with multiple async operations', () async {
      const source = '''
        async function task1() {
          await new Promise(resolve => setTimeout(resolve, 5));
          return 10;
        }

        async function task2() {
          await new Promise(resolve => setTimeout(resolve, 3));
          return 20;
        }

        async function task3() {
          await new Promise(resolve => setTimeout(resolve, 7));
          return 30;
        }

        async function main() {
          const results = await Promise.all([task1(), task2(), task3()]);
          return results[0] + results[1] + results[2];
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(60));
    });

    test('Promise.race with multiple async operations', () async {
      const source = '''
        async function slowTask() {
          await new Promise(resolve => setTimeout(resolve, 50));
          return "slow";
        }

        async function fastTask() {
          await new Promise(resolve => setTimeout(resolve, 1));
          return "fast";
        }

        async function main() {
          const result = await Promise.race([slowTask(), fastTask()]);
          return result;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('fast'));
    });

    test('Async function returning another async function result', () async {
      const source = '''
        async function innerAsync() {
          await new Promise(resolve => setTimeout(resolve, 5));
          return 42;
        }

        async function outerAsync() {
          const result = await innerAsync();
          return result * 2;
        }

        async function main() {
          return await outerAsync();
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(84));
    });

    test('Multiple awaits in sequence with transformations', () async {
      const source = '''
        async function step1(value) {
          await new Promise(resolve => setTimeout(resolve, 3));
          return value + 10;
        }

        async function step2(value) {
          await new Promise(resolve => setTimeout(resolve, 3));
          return value * 2;
        }

        async function step3(value) {
          await new Promise(resolve => setTimeout(resolve, 3));
          return value - 5;
        }

        async function main() {
          let result = 5;
          result = await step1(result);  // 5 + 10 = 15
          result = await step2(result);  // 15 * 2 = 30
          result = await step3(result);  // 30 - 5 = 25
          return result;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(25));
    });

    test('Async function with conditional await', () async {
      const source = '''
        async function conditionalFetch(shouldFetch) {
          if (shouldFetch) {
            await new Promise(resolve => setTimeout(resolve, 5));
            return "fetched";
          } else {
            return "cached";
          }
        }

        async function main() {
          const result1 = await conditionalFetch(true);
          const result2 = await conditionalFetch(false);
          return result1 + ":" + result2;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('fetched:cached'));
    });

    test('Async function with array reduce', () async {
      const source = '''
        async function asyncAdd(acc, value) {
          await new Promise(resolve => setTimeout(resolve, 1));
          return acc + value;
        }

        async function main() {
          const numbers = [1, 2, 3, 4, 5];
          let sum = 0;
          for (let i = 0; i < numbers.length; i++) {
            sum = await asyncAdd(sum, numbers[i]);
          }
          return sum;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(15));
    });

    test('Nested try-catch in async function', () async {
      const source = '''
        async function riskyOperation(id, shouldFail) {
          await new Promise(resolve => setTimeout(resolve, 3));
          if (shouldFail) {
            throw "Operation " + id + " failed";
          }
          return "Success " + id;
        }

        async function main() {
          let results = [];
          
          try {
            const result1 = await riskyOperation(1, false);
            results.push(result1);
          } catch (e) {
            results.push("Error1: " + e);
          }

          try {
            const result2 = await riskyOperation(2, true);
            results.push(result2);
          } catch (e) {
            results.push("Error2: " + e);
          }

          return results.join(",");
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('Success 1,Error2: Operation 2 failed'));
    });

    test('Async function with object property access', () async {
      const source = '''
        async function fetchUser() {
          await new Promise(resolve => setTimeout(resolve, 5));
          return { name: "Alice", age: 30, city: "Paris" };
        }

        async function main() {
          const user = await fetchUser();
          return user.name + " is " + user.age + " years old";
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('Alice is 30 years old'));
    });

    test('Async generator-like pattern with yield simulation', () async {
      const source = '''
        async function processItems(items) {
          const results = [];
          for (let i = 0; i < items.length; i++) {
            await new Promise(resolve => setTimeout(resolve, 2));
            results.push(items[i] * 2);
          }
          return results;
        }

        async function main() {
          const input = [1, 2, 3, 4, 5];
          const output = await processItems(input);
          return output.reduce((a, b) => a + b, 0);
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(30)); // (1+2+3+4+5)*2 = 30
    });

    test('Async function with conditional paths', () async {
      const source = '''
        async function checkValue(value) {
          await new Promise(resolve => setTimeout(resolve, 2));
          
          if (value < 0) {
            return "negative";
          }
          
          await new Promise(resolve => setTimeout(resolve, 2));
          
          if (value === 0) {
            return "zero";
          }
          
          await new Promise(resolve => setTimeout(resolve, 2));
          
          return "positive";
        }

        async function main() {
          const r1 = await checkValue(-5);
          const r2 = await checkValue(0);
          const r3 = await checkValue(10);
          return r1 + "," + r2 + "," + r3;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('negative,zero,positive'));
    });

    test('Async function with ternary operator and await', () async {
      const source = '''
        async function getValue(flag) {
          await new Promise(resolve => setTimeout(resolve, 3));
          return flag ? 100 : 200;
        }

        async function main() {
          const a = await getValue(true);
          const b = await getValue(false);
          return a + b;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(300));
    });

    test('Async function with switch-case', () async {
      const source = '''
        async function processCommand(cmd) {
          await new Promise(resolve => setTimeout(resolve, 2));
          
          switch(cmd) {
            case "start":
              return "Starting...";
            case "stop":
              return "Stopping...";
            case "restart":
              return "Restarting...";
            default:
              return "Unknown command";
          }
        }

        async function main() {
          const results = [];
          results.push(await processCommand("start"));
          results.push(await processCommand("stop"));
          results.push(await processCommand("unknown"));
          return results.join("|");
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(
        result.toString(),
        equals('Starting...|Stopping...|Unknown command'),
      );
    });

    test('Chained Promise.then with async/await', () async {
      const source = '''
        function createPromise(value) {
          return new Promise(resolve => {
            setTimeout(() => resolve(value * 2), 5);
          });
        }

        async function main() {
          const result = await createPromise(5)
            .then(x => x + 10)
            .then(x => x * 3);
          return result;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(60)); // (5*2 + 10) * 3 = 60
    });

    test('Async function with recursive-like pattern', () async {
      const source = '''
        async function countdown(n) {
          if (n <= 0) {
            return "Done!";
          }
          await new Promise(resolve => setTimeout(resolve, 2));
          return await countdown(n - 1);
        }

        async function main() {
          return await countdown(5);
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('Done!'));
    });

    test('Async function with array mapping simulation', () async {
      const source = '''
        async function asyncMap(arr, fn) {
          const results = [];
          for (let i = 0; i < arr.length; i++) {
            results.push(await fn(arr[i]));
          }
          return results;
        }

        async function double(x) {
          await new Promise(resolve => setTimeout(resolve, 1));
          return x * 2;
        }

        async function main() {
          const input = [1, 2, 3, 4];
          const output = await asyncMap(input, double);
          return output.join(",");
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('2,4,6,8'));
    });

    test('Multiple async functions with interdependencies', () async {
      const source = '''
        async function fetchUserId() {
          await new Promise(resolve => setTimeout(resolve, 3));
          return 123;
        }

        async function fetchUserName(id) {
          await new Promise(resolve => setTimeout(resolve, 3));
          return "User_" + id;
        }

        async function fetchUserScore(name) {
          await new Promise(resolve => setTimeout(resolve, 3));
          return name.length * 10;
        }

        async function main() {
          const id = await fetchUserId();
          const name = await fetchUserName(id);
          const score = await fetchUserScore(name);
          return score;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(80)); // "User_123".length * 10 = 80
    });

    test('Async function with while loop and await', () async {
      const source = '''
        async function waitUntilReady() {
          let count = 0;
          while (count < 5) {
            await new Promise(resolve => setTimeout(resolve, 2));
            count++;
          }
          return count;
        }

        async function main() {
          const result = await waitUntilReady();
          return result;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(5));
    });

    test('Async function with do-while loop and await', () async {
      const source = '''
        async function processUntilDone() {
          let sum = 0;
          let i = 1;
          do {
            await new Promise(resolve => setTimeout(resolve, 1));
            sum += i;
            i++;
          } while (i <= 5);
          return sum;
        }

        async function main() {
          return await processUntilDone();
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(15)); // 1+2+3+4+5 = 15
    });

    test('Async function with Promise.resolve in loop', () async {
      const source = '''
        async function main() {
          let sum = 0;
          for (let i = 1; i <= 5; i++) {
            const value = await Promise.resolve(i);
            sum += value;
          }
          return sum;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(15));
    });

    test('Async function with nested objects and await', () async {
      const source = '''
        async function fetchData() {
          await new Promise(resolve => setTimeout(resolve, 5));
          return {
            user: {
              profile: {
                name: "Bob",
                age: 25
              },
              settings: {
                theme: "dark"
              }
            }
          };
        }

        async function main() {
          const data = await fetchData();
          return data.user.profile.name + ":" + data.user.settings.theme;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('Bob:dark'));
    });

    test('Async error handling with multiple catch blocks', () async {
      const source = '''
        async function operation(id) {
          await new Promise(resolve => setTimeout(resolve, 2));
          throw "Error" + id;
        }

        async function main() {
          let errors = [];
          
          try {
            await operation(1);
          } catch (e) {
            errors.push(e);
          }

          try {
            await operation(2);
          } catch (e) {
            errors.push(e);
          }

          return errors.join("+");
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('Error1+Error2'));
    });
  });

  group('Async Methods in Classes Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Simple async method in class', () async {
      const source = '''
        class TestClass {
          async simpleAsync() {
            return "Hello from async method";
          }
        }

        async function main() {
          const instance = new TestClass();
          return await instance.simpleAsync();
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('Hello from async method'));
    });

    test('Async method with parameters', () async {
      const source = '''
        class Calculator {
          async add(a, b) {
            await new Promise(resolve => setTimeout(resolve, 1));
            return a + b;
          }

          async multiply(x, y) {
            await new Promise(resolve => setTimeout(resolve, 1));
            return x * y;
          }
        }

        async function main() {
          const calc = new Calculator();
          const sum = await calc.add(5, 3);
          const product = await calc.multiply(4, 7);
          return sum + "," + product;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('8,28'));
    });

    test('Async method calling another async method', () async {
      const source = '''
        class DataProcessor {
          async fetchData() {
            await new Promise(resolve => setTimeout(resolve, 2));
            return [1, 2, 3, 4, 5];
          }

          async processData() {
            const data = await this.fetchData();
            await new Promise(resolve => setTimeout(resolve, 2));
            return data.map(x => x * 2);
          }

          async getSum() {
            const processed = await this.processData();
            await new Promise(resolve => setTimeout(resolve, 2));
            return processed.reduce((a, b) => a + b, 0);
          }
        }

        async function main() {
          const processor = new DataProcessor();
          return await processor.getSum();
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toNumber(), equals(30)); // (1+2+3+4+5)*2 = 30
    });

    test('Static async methods', () async {
      const source = '''
        class StaticHelper {
          static async createInstance() {
            await new Promise(resolve => setTimeout(resolve, 1));
            return new StaticHelper();
          }

          static async compute(value) {
            await new Promise(resolve => setTimeout(resolve, 1));
            return value * value;
          }

          async instanceMethod() {
            return "instance";
          }
        }

        async function main() {
          const squared = await StaticHelper.compute(6);
          const instance = await StaticHelper.createInstance();
          const instanceResult = await instance.instanceMethod();
          return squared + "," + instanceResult;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('36,instance'));
    });

    test('Async methods with inheritance', () async {
      const source = '''
        class BaseService {
          async baseOperation() {
            await new Promise(resolve => setTimeout(resolve, 1));
            return "base";
          }
        }

        class DerivedService extends BaseService {
          async derivedOperation() {
            const baseResult = await this.baseOperation();
            await new Promise(resolve => setTimeout(resolve, 1));
            return baseResult + "_derived";
          }

          async combinedOperation() {
            const derived = await this.derivedOperation();
            await new Promise(resolve => setTimeout(resolve, 1));
            return derived + "_combined";
          }
        }

        async function main() {
          const service = new DerivedService();
          return await service.combinedOperation();
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('base_derived_combined'));
    });

    test('Async methods with error handling', () async {
      const source = '''
        class ErrorProneService {
          async riskyOperation(shouldFail) {
            await new Promise(resolve => setTimeout(resolve, 1));
            if (shouldFail) {
              throw "Operation failed";
            }
            return "Success";
          }

          async safeOperation() {
            try {
              return await this.riskyOperation(false);
            } catch (e) {
              return "Error caught: " + e;
            }
          }

          async unsafeOperation() {
            return await this.riskyOperation(true);
          }
        }

        async function main() {
          const service = new ErrorProneService();
          const safeResult = await service.safeOperation();
          
          let unsafeResult;
          try {
            unsafeResult = await service.unsafeOperation();
          } catch (e) {
            unsafeResult = "Error: " + e;
          }
          
          return safeResult + "|" + unsafeResult;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('Success|Error: Operation failed'));
    });

    test('Async methods in loops', () async {
      const source = '''
        class BatchProcessor {
          async processItem(item, index) {
            await new Promise(resolve => setTimeout(resolve, 1));
            return item + "_processed_" + index;
          }

          async processBatch(items) {
            const results = [];
            for (let i = 0; i < items.length; i++) {
              const result = await this.processItem(items[i], i);
              results.push(result);
            }
            return results;
          }
        }

        async function main() {
          const processor = new BatchProcessor();
          const items = ["A", "B", "C"];
          const results = await processor.processBatch(items);
          return results.join(",");
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(
        result.toString(),
        equals('A_processed_0,B_processed_1,C_processed_2'),
      );
    });

    test('Async methods with conditional logic', () async {
      const source = '''
        class ConditionalService {
          async processBasedOnType(value, type) {
            await new Promise(resolve => setTimeout(resolve, 1));
            
            if (type === "double") {
              return value * 2;
            } else if (type === "square") {
              return value * value;
            } else {
              return value;
            }
          }

          async processMultiple(items) {
            const results = [];
            for (const item of items) {
              const result = await this.processBasedOnType(item.value, item.type);
              results.push(result);
            }
            return results;
          }
        }

        async function main() {
          const service = new ConditionalService();
          const items = [
            { value: 5, type: "double" },
            { value: 3, type: "square" },
            { value: 10, type: "unknown" }
          ];
          const results = await service.processMultiple(items);
          return results.join(",");
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('10,9,10'));
    });

    test('Async methods with Promise.all', () async {
      const source = '''
        class ParallelProcessor {
          async slowOperation(id, delay) {
            await new Promise(resolve => setTimeout(resolve, delay));
            return "Result_" + id;
          }

          async processInParallel() {
            const promises = [
              this.slowOperation(1, 5),
              this.slowOperation(2, 3),
              this.slowOperation(3, 7)
            ];
            return await Promise.all(promises);
          }
        }

        async function main() {
          const processor = new ParallelProcessor();
          const results = await processor.processInParallel();
          return results.join(",");
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('Result_1,Result_2,Result_3'));
    });

    test('Async methods with complex object manipulation', () async {
      const source = '''
        class DataTransformer {
          async transformObject(obj) {
            await new Promise(resolve => setTimeout(resolve, 1));
            
            return {
              id: obj.id,
              name: obj.name.toUpperCase(),
              processed: true,
              timestamp: Date.now()
            };
          }

          async transformArray(objects) {
            const results = [];
            for (const obj of objects) {
              const transformed = await this.transformObject(obj);
              results.push(transformed);
            }
            return results;
          }
        }

        async function main() {
          const transformer = new DataTransformer();
          const data = [
            { id: 1, name: "alice" },
            { id: 2, name: "bob" }
          ];
          const results = await transformer.transformArray(data);
          return results[0].name + "," + results[1].name;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('ALICE,BOB'));
    });

    test('Async methods with recursion', () async {
      const source = '''
        class RecursiveProcessor {
          async processRecursive(n) {
            await new Promise(resolve => setTimeout(resolve, 1));
            
            if (n <= 0) {
              return 0;
            }
            
            const next = await this.processRecursive(n - 1);
            return n + next;
          }

          async factorial(n) {
            await new Promise(resolve => setTimeout(resolve, 1));
            
            if (n <= 1) {
              return 1;
            }
            
            const next = await this.factorial(n - 1);
            return n * next;
          }
        }

        async function main() {
          const processor = new RecursiveProcessor();
          const sum = await processor.processRecursive(5); // 5+4+3+2+1+0 = 15
          const fact = await processor.factorial(4); // 4*3*2*1 = 24
          return sum + "," + fact;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('15,24'));
    });

    test('Async methods with getters and setters', () async {
      const source = '''
        class AsyncPropertyManager {
          constructor() {
            this._data = null;
          }

          async setData(value) {
            await new Promise(resolve => setTimeout(resolve, 1));
            this._data = value;
          }

          async getData() {
            await new Promise(resolve => setTimeout(resolve, 1));
            return this._data;
          }

          async processData() {
            const current = await this.getData();
            await new Promise(resolve => setTimeout(resolve, 1));
            const processed = current + "_processed";
            await this.setData(processed);
            return processed;
          }
        }

        async function main() {
          const manager = new AsyncPropertyManager();
          await manager.setData("test");
          const processed = await manager.processData();
          const finalData = await manager.getData();
          return processed + "," + finalData;
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('test_processed,test_processed'));
    });

    test('Mixed sync and async methods in class', () async {
      const source = '''
        class MixedService {
          syncMethod(value) {
            return value + "_sync";
          }

          async asyncMethod(value) {
            await new Promise(resolve => setTimeout(resolve, 1));
            return value + "_async";
          }

          async combinedMethod(value) {
            const syncResult = this.syncMethod(value);
            const asyncResult = await this.asyncMethod(value);
            return syncResult + "|" + asyncResult;
          }
        }

        async function main() {
          const service = new MixedService();
          return await service.combinedMethod("test");
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('test_sync|test_async'));
    });

    test('Async methods with array operations', () async {
      const source = '''
        class ArrayProcessor {
          async filterEvens(arr) {
            const results = [];
            for (const item of arr) {
              await new Promise(resolve => setTimeout(resolve, 1));
              if (item % 2 === 0) {
                results.push(item);
              }
            }
            return results;
          }

          async doubleValues(arr) {
            const results = [];
            for (const item of arr) {
              await new Promise(resolve => setTimeout(resolve, 1));
              results.push(item * 2);
            }
            return results;
          }

          async processNumbers(numbers) {
            const evens = await this.filterEvens(numbers);
            const doubled = await this.doubleValues(evens);
            return doubled;
          }
        }

        async function main() {
          const processor = new ArrayProcessor();
          const numbers = [1, 2, 3, 4, 5, 6];
          const result = await processor.processNumbers(numbers);
          return result.join(",");
        }
        main();
      ''';
      final result = await interpreter.evalAsync(source);
      expect(
        result.toString(),
        equals('4,8,12'),
      ); // Even numbers (2,4,6) doubled
    });

    test('Async methods with message system - API calls', () async {
      // Register API handler
      interpreter.onMessage('api', (dynamic message) async {
        final args = message as List;
        final endpoint = args[0] as String;

        await Future.delayed(
          Duration(milliseconds: 10),
        ); // Reduced from 1 second to 10ms

        if (endpoint == 'users') {
          return '[{"id": 1, "name": "John"}, {"id": 2, "name": "Jane"}]';
        } else if (endpoint == 'posts') {
          return '[{"id": 1, "title": "Hello World"}]';
        }

        return '[]';
      });

      const source = '''
        class ApiService {
          async fetchUsers() {
            const response = await sendMessageAsync('api', 'users');
            return JSON.parse(response);
          }

          async fetchPosts() {
            const response = await sendMessageAsync('api', 'posts');
            return JSON.parse(response);
          }

          async fetchAllData() {
            const users = await this.fetchUsers();
            const posts = await this.fetchPosts();
            return { users: users.length, posts: posts.length };
          }
        }

        async function main() {
          const api = new ApiService();
          const data = await api.fetchAllData();
          return data.users + ',' + data.posts;
        }
        main();
      ''';

      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('2,1'));
    });

    test('Async methods with message system - Database operations', () async {
      // Register database handler
      interpreter.onMessage('db', (dynamic message) async {
        final args = message as List;
        final operation = args[0] as String;

        await Future.delayed(Duration(milliseconds: 1));

        if (operation == 'find') {
          final category = args[1] as String;
          if (category == 'electronics') {
            return '[{"id": 1, "name": "Laptop", "price": 999}]';
          } else if (category == 'books') {
            return '[{"id": 2, "name": "Book", "price": 20}]';
          }
        } else if (operation == 'insert') {
          return 123; // insertedId
        } else if (operation == 'update') {
          return 1; // modifiedCount
        }

        return null;
      });

      const source = '''
        class DatabaseService {
          async findProducts(category) {
            const result = await sendMessageAsync('db', 'find', category);
            return JSON.parse(result);
          }

          async insertProduct(product) {
            const result = await sendMessageAsync('db', 'insert', product);
            return result;
          }

          async updateProductPrice(productId, newPrice) {
            const result = await sendMessageAsync('db', 'update', productId, newPrice);
            return result;
          }

          async getTotalValue(category) {
            const products = await this.findProducts(category);
            let total = 0;
            for (const product of products) {
              total += product.price;
            }
            return total;
          }
        }

        async function main() {
          const db = new DatabaseService();
          const electronics = await db.getTotalValue('electronics');
          const bookId = await db.insertProduct('New Book');
          const updated = await db.updateProductPrice(1, 899);
          return electronics + ',' + bookId + ',' + updated;
        }
        main();
      ''';

      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('999,123,1'));
    });

    test('Async methods with message system - File operations', () async {
      // Register file system message handlers
      interpreter.onMessage('fs', (dynamic message) async {
        final args = message as List;
        final operation = args[0] as String;

        await Future.delayed(
          Duration(milliseconds: 2),
        ); // Simulate file I/O delay

        if (operation == 'read') {
          final filename = args[1] as String;
          if (filename == 'config.json') {
            return '{"database": "localhost", "port": 5432}';
          } else if (filename == 'data.txt') {
            return 'Hello World\nLine 2\nLine 3';
          }
        } else if (operation == 'write') {
          return true; // success
        } else if (operation == 'list') {
          return '["file1.txt", "file2.json", "config.json"]';
        }

        return null;
      });

      const source = '''
        class FileService {
          async readFile(filename) {
            const content = await sendMessageAsync('fs', 'read', filename);
            return content;
          }

          async writeFile(filename, content) {
            const result = await sendMessageAsync('fs', 'write', filename, content);
            return result;
          }

          async listDirectory(directory) {
            const files = await sendMessageAsync('fs', 'list', directory);
            return JSON.parse(files);
          }

          async processConfig() {
            const configContent = await this.readFile('config.json');
            const config = JSON.parse(configContent);
            const dataContent = await this.readFile('data.txt');
            const lines = dataContent.split('\\n');
            return config.database + ':' + lines.length;
          }
        }

        async function main() {
          const fs = new FileService();
          const config = await fs.processConfig();
          const files = await fs.listDirectory('/');
          const writeResult = await fs.writeFile('output.txt', 'Processed data');
          return config + ',' + files.length + ',' + writeResult;
        }
        main();
      ''';

      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('localhost:3,3,true'));
    });

    test('Async methods with message system - Error handling', () async {
      // Register message handlers that can throw errors
      interpreter.onMessage('service', (dynamic message) async {
        final args = message as List;
        final operation = args[0] as String;

        await Future.delayed(Duration(milliseconds: 1));

        if (operation == 'success') {
          return 'Operation successful';
        } else if (operation == 'error') {
          throw Exception('Service error occurred');
        } else if (operation == 'timeout') {
          await Future.delayed(Duration(milliseconds: 100)); // Simulate timeout
          return 'Timeout result';
        } else if (operation == 'unknown') {
          return 'Unknown result';
        }

        throw Exception('Unknown operation: $operation');
      });

      const source = '''
        class ServiceClient {
          async callService(operation) {
            try {
              const result = await sendMessageAsync('service', operation);
              return { success: true, data: result };
            } catch (error) {
              return { success: false, error: error.message };
            }
          }

          async executeOperations() {
            const results = [];
            results.push(await this.callService('success'));
            results.push(await this.callService('error'));
            results.push(await this.callService('unknown'));
            return results;
          }

          async safeBatchOperations(operations) {
            const results = [];
            for (const op of operations) {
              try {
                const result = await this.callService(op);
                results.push(result);
              } catch (e) {
                results.push({ success: false, error: 'Batch operation failed' });
              }
            }
            return results;
          }
        }

        async function main() {
          const client = new ServiceClient();
          const results = await client.executeOperations();
          const successCount = results.filter(r => r.success).length;
          const errorCount = results.length - successCount;
          return successCount + ',' + errorCount;
        }
        main();
      ''';

      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('2,1')); // 2 successes, 1 error
    });

    test('Async methods with message system - Event handling', () async {
      // Register event handlers
      interpreter.onMessage('events', (dynamic message) async {
        final args = message as List;
        final eventType = args[0] as String;
        final eventData = args[1];

        await Future.delayed(
          Duration(milliseconds: 10),
        ); // Reduced from 1 second to 10ms

        if (eventType == 'user_login') {
          return {
            'event': 'user_login',
            'userId': eventData,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
        } else if (eventType == 'data_update') {
          return {
            'event': 'data_update',
            'recordId': eventData,
            'changes': 'updated',
          };
        }

        return {'event': 'unknown', 'data': eventData};
      });

      const source = '''
        class EventProcessor {
          async processLoginEvent(userId) {
            const event = await sendMessageAsync('events', 'user_login', userId);
            return event;
          }

          async processDataUpdate(recordId, changes) {
            const event = await sendMessageAsync('events', 'data_update', recordId);
            return event;
          }

          async processMultipleEvents(events) {
            const results = [];
            for (const event of events) {
              if (event.type === 'login') {
                results.push(await this.processLoginEvent(event.userId));
              } else if (event.type === 'update') {
                results.push(await this.processDataUpdate(event.recordId, event.changes));
              }
            }
            return results;
          }

          async getEventSummary(events) {
            const processedEvents = await this.processMultipleEvents(events);
            const loginCount = processedEvents.filter(e => e.event === 'user_login').length;
            const updateCount = processedEvents.filter(e => e.event === 'data_update').length;
            return { logins: loginCount, updates: updateCount, total: processedEvents.length };
          }
        }

        async function main() {
          const processor = new EventProcessor();
          const events = [
            { type: 'login', userId: 123 },
            { type: 'update', recordId: 456, changes: 'status: active' },
            { type: 'login', userId: 789 }
          ];
          const summary = await processor.getEventSummary(events);
          return summary.logins + ',' + summary.updates + ',' + summary.total;
        }
        main();
      ''';

      final result = await interpreter.evalAsync(source);
      expect(result.toString(), equals('2,1,3'));
    });

    test('Async methods with message system - Chained operations', () async {
      // Register workflow handlers
      interpreter.onMessage('workflow', (dynamic message) async {
        final args = message as List;
        final step = args[0] as String;
        final data = args[1] as Map;

        await Future.delayed(
          Duration(milliseconds: 10),
        ); // Reduced from 1 second to 10ms
        print('object');
        if (step == 'validate') {
          final dataMap = data;
          final value = dataMap['value'] as num;
          return (value > 0)
              ? (Map.from(dataMap)..addAll({'valid': true}))
              : (Map.from(dataMap)..addAll({'valid': false}));
        } else if (step == 'process') {
          final dataMap = data;
          final value = dataMap['value'] as num;
          final result = value * 2;
          return Map.from(dataMap)
            ..addAll({'processed': true, 'result': result});
        } else if (step == 'save') {
          final dataMap = data;
          return Map.from(dataMap)..addAll({'saved': true, 'id': 12345});
        }

        return data;
      });

      const source = '''
        class WorkflowService {
          async validateData(data) {
            const result = await sendMessageAsync('workflow', 'validate', data);
            console.log('result');
            if (!result.valid) {
              throw new Error('Validation failed');
            }
            return result;
          }

          async processData(data) {
            const result = await sendMessageAsync('workflow', 'process', data);
            return result;
          }

          async saveData(data) {
            const result = await sendMessageAsync('workflow', 'save', data);
            return result;
          }

          async executeWorkflow(inputData) {
            try {
              const validated = await this.validateData(inputData);
              const processed = await this.processData(validated);
              const saved = await this.saveData(processed);
              return { success: true, id: saved.id, finalValue: saved.result };
            } catch (error) {
            console.log(error);
              return { success: false, error: error.message };
            }
          }

          async executeMultipleWorkflows(inputs) {
            const results = [];
            for (const input of inputs) {
              const result = await this.executeWorkflow(input);
              results.push(result);
            }
            return results;
          }
        }

        async function main() {
          const workflow = new WorkflowService();
          const inputs = [
            { value: 5 },
            { value: -1 },
            { value: 10 }
          ];
          const results = await workflow.executeMultipleWorkflows(inputs);
          const successCount = results.filter(r => r.success).length;
          const failureCount = results.filter(r => !r.success).length;
          return successCount + ',' + failureCount;
        }
        main();
      ''';

      final result = await interpreter.evalAsync(source);
      expect(
        result.toString(),
        equals('2,1'),
      ); // 2 successes, 1 failure (negative value)
    });
  });
}
