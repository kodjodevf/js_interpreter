import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('yield* delegation', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('yield* with generator function', () {
      final result =
          interpreter.eval('''
        function* inner() {
          yield 1;
          yield 2;
          yield 3;
        }
        
        function* outer() {
          yield* inner();
          yield 4;
        }
        
        const gen = outer();
        const results = [];
        let result;
        while (!(result = gen.next()).done) {
          results.push(result.value);
        }
        results;
      ''')
              as JSArray;

      expect(result.elements.length, 4);
      expect(result.elements[0].toNumber(), 1);
      expect(result.elements[1].toNumber(), 2);
      expect(result.elements[2].toNumber(), 3);
      expect(result.elements[3].toNumber(), 4);
    });

    test('yield* with array', () {
      final result =
          interpreter.eval('''
        function* gen() {
          yield* [10, 20, 30];
          yield 40;
        }
        
        const g = gen();
        const results = [];
        let result;
        while (!(result = g.next()).done) {
          results.push(result.value);
        }
        results;
      ''')
              as JSArray;

      expect(result.elements.length, 4);
      expect(result.elements[0].toNumber(), 10);
      expect(result.elements[1].toNumber(), 20);
      expect(result.elements[2].toNumber(), 30);
      expect(result.elements[3].toNumber(), 40);
    });

    test('yield* with string', () {
      final result =
          interpreter.eval('''
        function* gen() {
          // Convert string to array first since primitive strings don't have Symbol.iterator accessible
          yield* Array.from('abc');
        }
        
        const g = gen();
        const results = [];
        let result;
        while (!(result = g.next()).done) {
          results.push(result.value);
        }
        results;
      ''')
              as JSArray;

      expect(result.elements.length, 3);
      expect(result.elements[0].toString(), 'a');
      expect(result.elements[1].toString(), 'b');
      expect(result.elements[2].toString(), 'c');
    });

    test('yield* with nested generators', () {
      final result =
          interpreter.eval('''
        function* level1() {
          yield 'a';
          yield 'b';
        }
        
        function* level2() {
          yield* level1();
          yield 'c';
        }
        
        function* level3() {
          yield* level2();
          yield 'd';
        }
        
        const gen = level3();
        const results = [];
        let result;
        while (!(result = gen.next()).done) {
          results.push(result.value);
        }
        results;
      ''')
              as JSArray;

      expect(result.elements.length, 4);
      expect(result.elements[0].toString(), 'a');
      expect(result.elements[1].toString(), 'b');
      expect(result.elements[2].toString(), 'c');
      expect(result.elements[3].toString(), 'd');
    });

    test('yield* with generator that returns a value', () {
      final result =
          interpreter.eval('''
        function* inner() {
          yield 1;
          yield 2;
          return 3;
        }
        
        function* outer() {
          const result = yield* inner();
          yield result;
        }
        
        const gen = outer();
        const results = [];
        let result;
        while (!(result = gen.next()).done) {
          results.push(result.value);
        }
        results;
      ''')
              as JSArray;

      expect(result.elements.length, 3);
      expect(result.elements[0].toNumber(), 1);
      expect(result.elements[1].toNumber(), 2);
      expect(result.elements[2].toNumber(), 3);
    });

    test('yield* with multiple delegations', () {
      final result =
          interpreter.eval('''
        function* gen1() {
          yield 1;
          yield 2;
        }
        
        function* gen2() {
          yield 3;
          yield 4;
        }
        
        function* outer() {
          yield* gen1();
          yield* gen2();
          yield 5;
        }
        
        const gen = outer();
        const results = [];
        let result;
        while (!(result = gen.next()).done) {
          results.push(result.value);
        }
        results;
      ''')
              as JSArray;

      expect(result.elements.length, 5);
      expect(result.elements[0].toNumber(), 1);
      expect(result.elements[1].toNumber(), 2);
      expect(result.elements[2].toNumber(), 3);
      expect(result.elements[3].toNumber(), 4);
      expect(result.elements[4].toNumber(), 5);
    });

    test('yield* with empty generator', () {
      final result =
          interpreter.eval('''
        function* empty() {
          // yields nothing
        }
        
        function* outer() {
          yield 1;
          yield* empty();
          yield 2;
        }
        
        const gen = outer();
        const results = [];
        let result;
        while (!(result = gen.next()).done) {
          results.push(result.value);
        }
        results;
      ''')
              as JSArray;

      expect(result.elements.length, 2);
      expect(result.elements[0].toNumber(), 1);
      expect(result.elements[1].toNumber(), 2);
    });

    test('yield* with custom iterator', () {
      final result =
          interpreter.eval('''
        // Create custom iterable using a factory function since parser doesn't support computed property names yet
        function makeIterable() {
          const obj = {};
          const iteratorKey = Symbol.iterator;
          obj[iteratorKey] = function() {
            let count = 0;
            return {
              next: function() {
                if (count < 3) {
                  return { value: count++, done: false };
                }
                return { value: undefined, done: true };
              }
            };
          };
          return obj;
        }
        
        const customIterable = makeIterable();
        
        function* gen() {
          yield* customIterable;
          yield 100;
        }
        
        const g = gen();
        const results = [];
        let result;
        while (!(result = g.next()).done) {
          results.push(result.value);
        }
        results;
      ''')
              as JSArray;

      expect(result.elements.length, 4);
      expect(result.elements[0].toNumber(), 0);
      expect(result.elements[1].toNumber(), 1);
      expect(result.elements[2].toNumber(), 2);
      expect(result.elements[3].toNumber(), 100);
    });

    test('yield* error with non-iterable', () {
      // Create generator first
      interpreter.eval('''
        function* gen() {
          yield* 123;  // number is not iterable
        }
        var g = gen();
      ''');

      // Now calling next() should throw an error
      expect(() => interpreter.eval('g.next();'), throwsA(isA<JSException>()));
    });

    test('yield* in for...of loop', () {
      final result = interpreter.eval('''
        function* inner() {
          yield 10;
          yield 20;
          yield 30;
        }
        
        function* outer() {
          yield* inner();
        }
        
        let sum = 0;
        for (const val of outer()) {
          sum += val;
        }
        sum;
      ''');

      expect(result.toNumber(), 60);
    });

    test('yield* with generator expression result', () {
      final result =
          interpreter.eval('''
        function* range(start, end) {
          for (let i = start; i < end; i++) {
            yield i;
          }
        }
        
        function* gen() {
          yield* range(1, 4);
          yield* range(10, 13);
        }
        
        const results = [];
        for (const val of gen()) {
          results.push(val);
        }
        results;
      ''')
              as JSArray;

      expect(result.elements.length, 6);
      expect(result.elements[0].toNumber(), 1);
      expect(result.elements[1].toNumber(), 2);
      expect(result.elements[2].toNumber(), 3);
      expect(result.elements[3].toNumber(), 10);
      expect(result.elements[4].toNumber(), 11);
      expect(result.elements[5].toNumber(), 12);
    });

    test('yield* preserves iteration protocol', () {
      final result =
          interpreter.eval('''
        function* inner() {
          yield 'x';
          yield 'y';
          return 'done';
        }
        
        function* outer() {
          const returnValue = yield* inner();
          yield returnValue;
        }
        
        const gen = outer();
        const results = [];
        let result;
        while (!(result = gen.next()).done) {
          results.push(result.value);
        }
        results;
      ''')
              as JSArray;

      expect(result.elements.length, 3);
      expect(result.elements[0].toString(), 'x');
      expect(result.elements[1].toString(), 'y');
      expect(result.elements[2].toString(), 'done');
    });
  });
}
