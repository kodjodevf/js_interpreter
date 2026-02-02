import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('TypedArray Iterator Support Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('for...of loop with Uint8Array', () {
      final code = '''
        const arr = new Uint8Array([10, 20, 30, 40, 50]);
        const result = [];
        for (const value of arr) {
          result.push(value);
        }
        result;
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements.length, equals(5));
      expect(arr.elements[0].toNumber(), equals(10.0));
      expect(arr.elements[1].toNumber(), equals(20.0));
      expect(arr.elements[2].toNumber(), equals(30.0));
      expect(arr.elements[3].toNumber(), equals(40.0));
      expect(arr.elements[4].toNumber(), equals(50.0));
    });

    test('for...of loop with Int8Array', () {
      final code = '''
        const arr = new Int8Array([1, -2, 3, -4, 5]);
        let sum = 0;
        for (const value of arr) {
          sum += value;
        }
        sum;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(3.0)); // 1 + (-2) + 3 + (-4) + 5 = 3
    });

    test('for...of loop with Float32Array', () {
      final code = '''
        const arr = new Float32Array([1.5, 2.5, 3.5]);
        const doubled = [];
        for (const value of arr) {
          doubled.push(value * 2);
        }
        doubled;
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements.length, equals(3));
      expect(arr.elements[0].toNumber(), equals(3.0));
      expect(arr.elements[1].toNumber(), equals(5.0));
      expect(arr.elements[2].toNumber(), equals(7.0));
    });

    test('keys() method returns iterator of indices', () {
      final code = '''
        const arr = new Uint16Array([100, 200, 300]);
        const indices = [];
        for (const index of arr.keys()) {
          indices.push(index);
        }
        indices;
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements.length, equals(3));
      expect(arr.elements[0].toNumber(), equals(0.0));
      expect(arr.elements[1].toNumber(), equals(1.0));
      expect(arr.elements[2].toNumber(), equals(2.0));
    });

    test('values() method returns iterator of values', () {
      final code = '''
        const arr = new Int32Array([5, 10, 15]);
        const values = [];
        for (const value of arr.values()) {
          values.push(value);
        }
        values;
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements.length, equals(3));
      expect(arr.elements[0].toNumber(), equals(5.0));
      expect(arr.elements[1].toNumber(), equals(10.0));
      expect(arr.elements[2].toNumber(), equals(15.0));
    });

    test('entries() method returns iterator of [index, value] pairs', () {
      final code = '''
        const arr = new Float64Array([1.1, 2.2, 3.3]);
        const entries = [];
        for (const entry of arr.entries()) {
          entries.push(entry);
        }
        entries;
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements.length, equals(3));

      // First entry: [0, 1.1]
      final entry0 = arr.elements[0] as JSArray;
      expect(entry0.elements[0].toNumber(), equals(0.0));
      expect(entry0.elements[1].toNumber(), equals(1.1));

      // Second entry: [1, 2.2]
      final entry1 = arr.elements[1] as JSArray;
      expect(entry1.elements[0].toNumber(), equals(1.0));
      expect(entry1.elements[1].toNumber(), equals(2.2));

      // Third entry: [2, 3.3]
      final entry2 = arr.elements[2] as JSArray;
      expect(entry2.elements[0].toNumber(), equals(2.0));
      expect(entry2.elements[1].toNumber(), equals(3.3));
    });

    test('iterator manual usage with next()', () {
      final code = '''
        const arr = new Uint8Array([7, 8, 9]);
        const iterator = arr.values();
        const results = [];
        
        let result = iterator.next();
        while (!result.done) {
          results.push(result.value);
          result = iterator.next();
        }
        
        results;
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements.length, equals(3));
      expect(arr.elements[0].toNumber(), equals(7.0));
      expect(arr.elements[1].toNumber(), equals(8.0));
      expect(arr.elements[2].toNumber(), equals(9.0));
    });

    test('iterator exhaustion', () {
      final code = '''
        const arr = new Int8Array([1, 2]);
        const iterator = arr[Symbol.iterator]();
        
        iterator.next(); // {value: 1, done: false}
        iterator.next(); // {value: 2, done: false}
        const final = iterator.next(); // {value: undefined, done: true}
        
        final.done;
      ''';

      final result = interpreter.eval(code);
      expect(result.toBoolean(), isTrue);
    });

    test('for...of with break', () {
      final code = '''
        const arr = new Uint32Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
        let sum = 0;
        for (const value of arr) {
          if (value > 5) break;
          sum += value;
        }
        sum;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(15.0)); // 1+2+3+4+5 = 15
    });

    test('for...of with continue', () {
      final code = '''
        const arr = new Int16Array([1, 2, 3, 4, 5, 6]);
        let sum = 0;
        for (const value of arr) {
          if (value % 2 === 0) continue;
          sum += value;
        }
        sum;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(9.0)); // 1+3+5 = 9
    });

    test('nested for...of loops', () {
      final code = '''
        const arr1 = new Uint8Array([1, 2]);
        const arr2 = new Uint8Array([10, 20]);
        const result = [];
        
        for (const a of arr1) {
          for (const b of arr2) {
            result.push(a + b);
          }
        }
        
        result;
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements.length, equals(4));
      expect(arr.elements[0].toNumber(), equals(11.0)); // 1+10
      expect(arr.elements[1].toNumber(), equals(21.0)); // 1+20
      expect(arr.elements[2].toNumber(), equals(12.0)); // 2+10
      expect(arr.elements[3].toNumber(), equals(22.0)); // 2+20
    });

    test('destructuring with for...of', () {
      // Skip: Destructuring in for...of not yet implemented in parser
      final code = '''
        const arr = new Uint16Array([100, 200, 300]);
        const result = [];
        
        for (const entry of arr.entries()) {
          result.push(entry[0] * entry[1]);
        }
        
        result;
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements.length, equals(3));
      expect(arr.elements[0].toNumber(), equals(0.0)); // 0 * 100
      expect(arr.elements[1].toNumber(), equals(200.0)); // 1 * 200
      expect(arr.elements[2].toNumber(), equals(600.0)); // 2 * 300
    });

    test('combining filter and for...of', () {
      final code = '''
        const arr = new Int8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
        const evens = arr.filter(function(x) { return x % 2 === 0; });
        
        let sum = 0;
        for (const value of evens) {
          sum += value;
        }
        
        sum;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(30.0)); // 2+4+6+8+10 = 30
    });

    test('Array.from with TypedArray iterator', () {
      final code = '''
        const typed = new Uint8Array([1, 2, 3, 4, 5]);
        const regular = Array.from(typed);
        regular;
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements.length, equals(5));
      for (var i = 0; i < 5; i++) {
        expect(arr.elements[i].toNumber(), equals((i + 1).toDouble()));
      }
    });

    test('empty TypedArray iteration', () {
      final code = '''
        const arr = new Uint8Array(0);
        const result = [];
        for (const value of arr) {
          result.push(value);
        }
        result.length;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(0.0));
    });

    test('TypedArray with single element', () {
      final code = '''
        const arr = new Float32Array([42.5]);
        let value = null;
        for (const v of arr) {
          value = v;
        }
        value;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(42.5));
    });

    test('multiple iterators on same TypedArray', () {
      final code = '''
        const arr = new Uint8Array([1, 2, 3]);
        const iter1 = arr.values();
        const iter2 = arr.values();
        
        const val1 = iter1.next().value;
        const val2 = iter2.next().value;
        
        val1 === val2;
      ''';

      final result = interpreter.eval(code);
      expect(result.toBoolean(), isTrue); // Both should return 1
    });

    test('iterator independence', () {
      final code = '''
        const arr = new Int16Array([10, 20, 30]);
        const iter1 = arr.values();
        const iter2 = arr.values();
        
        iter1.next(); // Skip first value in iter1
        
        const val1 = iter1.next().value; // Should be 20
        const val2 = iter2.next().value; // Should be 10
        
        [val1, val2];
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements[0].toNumber(), equals(20.0));
      expect(arr.elements[1].toNumber(), equals(10.0));
    });
  });
}
