import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('TypedArray Array-like Methods Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('forEach method', () {
      final code = '''
        const arr = new Uint8Array([1, 2, 3, 4, 5]);
        let sum = 0;
        arr.forEach(function(value, index) {
          sum += value;
        });
        sum;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(15.0));
    });

    test('forEach with thisArg', () {
      final code = '''
        const arr = new Int8Array([1, 2, 3]);
        const context = { multiplier: 2 };
        let result = 0;
        arr.forEach(function(value) {
          result += value * this.multiplier;
        }, context);
        result;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(12.0)); // (1+2+3) * 2
    });

    test('map method', () {
      final code = '''
        const arr = new Int16Array([1, 2, 3, 4]);
        const doubled = arr.map(function(x) {
          return x * 2;
        });
        const result = [];
        for (let i = 0; i < doubled.length; i++) {
          result.push(doubled[i]);
        }
        result;
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements.length, equals(4));
      expect(arr.elements[0].toNumber(), equals(2.0));
      expect(arr.elements[1].toNumber(), equals(4.0));
      expect(arr.elements[2].toNumber(), equals(6.0));
      expect(arr.elements[3].toNumber(), equals(8.0));
    });

    test('filter method', () {
      final code = '''
        const arr = new Uint16Array([1, 2, 3, 4, 5, 6, 7, 8]);
        const evens = arr.filter(function(x) {
          return x % 2 === 0;
        });
        const result = [];
        for (let i = 0; i < evens.length; i++) {
          result.push(evens[i]);
        }
        result;
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements.length, equals(4));
      expect(arr.elements[0].toNumber(), equals(2.0));
      expect(arr.elements[1].toNumber(), equals(4.0));
      expect(arr.elements[2].toNumber(), equals(6.0));
      expect(arr.elements[3].toNumber(), equals(8.0));
    });

    test('reduce method with initial value', () {
      final code = '''
        const arr = new Int32Array([1, 2, 3, 4, 5]);
        const sum = arr.reduce(function(acc, val) {
          return acc + val;
        }, 0);
        sum;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(15.0));
    });

    test('reduce method without initial value', () {
      final code = '''
        const arr = new Uint32Array([10, 20, 30]);
        const sum = arr.reduce(function(acc, val) {
          return acc + val;
        });
        sum;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(60.0));
    });

    test('reduce method for product', () {
      final code = '''
        const arr = new Float32Array([2, 3, 4]);
        const product = arr.reduce(function(acc, val) {
          return acc * val;
        }, 1);
        product;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(24.0));
    });

    test('find method', () {
      final code = '''
        const arr = new Float64Array([1.5, 2.5, 3.5, 4.5, 5.5]);
        const found = arr.find(function(x) {
          return x > 3;
        });
        found;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(3.5));
    });

    test('find method returns undefined when not found', () {
      final code = '''
        const arr = new Int8Array([1, 2, 3]);
        const found = arr.find(function(x) {
          return x > 10;
        });
        found;
      ''';

      final result = interpreter.eval(code);
      expect(result.isUndefined, isTrue);
    });

    test('findIndex method', () {
      final code = '''
        const arr = new Uint8Array([10, 20, 30, 40, 50]);
        const index = arr.findIndex(function(x) {
          return x === 30;
        });
        index;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(2.0));
    });

    test('findIndex method returns -1 when not found', () {
      final code = '''
        const arr = new Int16Array([1, 2, 3]);
        const index = arr.findIndex(function(x) {
          return x > 10;
        });
        index;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(-1.0));
    });

    test('every method returns true when all match', () {
      final code = '''
        const arr = new Uint8Array([2, 4, 6, 8]);
        const allEven = arr.every(function(x) {
          return x % 2 === 0;
        });
        allEven;
      ''';

      final result = interpreter.eval(code);
      expect(result.toBoolean(), isTrue);
    });

    test('every method returns false when one does not match', () {
      final code = '''
        const arr = new Int8Array([2, 4, 5, 8]);
        const allEven = arr.every(function(x) {
          return x % 2 === 0;
        });
        allEven;
      ''';

      final result = interpreter.eval(code);
      expect(result.toBoolean(), isFalse);
    });

    test('some method returns true when at least one matches', () {
      final code = '''
        const arr = new Uint16Array([1, 3, 5, 8]);
        const hasEven = arr.some(function(x) {
          return x % 2 === 0;
        });
        hasEven;
      ''';

      final result = interpreter.eval(code);
      expect(result.toBoolean(), isTrue);
    });

    test('some method returns false when none match', () {
      final code = '''
        const arr = new Int16Array([1, 3, 5, 7]);
        const hasEven = arr.some(function(x) {
          return x % 2 === 0;
        });
        hasEven;
      ''';

      final result = interpreter.eval(code);
      expect(result.toBoolean(), isFalse);
    });

    test('slice method with positive indices', () {
      final code = '''
        const arr = new Uint8Array([0, 1, 2, 3, 4, 5]);
        const sliced = arr.slice(2, 5);
        const result = [];
        for (let i = 0; i < sliced.length; i++) {
          result.push(sliced[i]);
        }
        result;
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements.length, equals(3));
      expect(arr.elements[0].toNumber(), equals(2.0));
      expect(arr.elements[1].toNumber(), equals(3.0));
      expect(arr.elements[2].toNumber(), equals(4.0));
    });

    test('slice method with negative indices', () {
      final code = '''
        const arr = new Int8Array([0, 1, 2, 3, 4, 5]);
        const sliced = arr.slice(-3, -1);
        const result = [];
        for (let i = 0; i < sliced.length; i++) {
          result.push(sliced[i]);
        }
        result;
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements.length, equals(2));
      expect(arr.elements[0].toNumber(), equals(3.0));
      expect(arr.elements[1].toNumber(), equals(4.0));
    });

    test('slice method without arguments', () {
      final code = '''
        const arr = new Uint16Array([1, 2, 3, 4]);
        const sliced = arr.slice();
        const result = [];
        for (let i = 0; i < sliced.length; i++) {
          result.push(sliced[i]);
        }
        result;
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements.length, equals(4));
      expect(arr.elements[0].toNumber(), equals(1.0));
      expect(arr.elements[1].toNumber(), equals(2.0));
      expect(arr.elements[2].toNumber(), equals(3.0));
      expect(arr.elements[3].toNumber(), equals(4.0));
    });

    test('fill method with value only', () {
      final code = '''
        const arr = new Int32Array(5);
        arr.fill(42);
        const result = [];
        for (let i = 0; i < arr.length; i++) {
          result.push(arr[i]);
        }
        result;
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements.length, equals(5));
      for (var i = 0; i < 5; i++) {
        expect(arr.elements[i].toNumber(), equals(42.0));
      }
    });

    test('fill method with value and start', () {
      final code = '''
        const arr = new Uint32Array([1, 2, 3, 4, 5]);
        arr.fill(99, 2);
        const result = [];
        for (let i = 0; i < arr.length; i++) {
          result.push(arr[i]);
        }
        result;
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements.length, equals(5));
      expect(arr.elements[0].toNumber(), equals(1.0));
      expect(arr.elements[1].toNumber(), equals(2.0));
      expect(arr.elements[2].toNumber(), equals(99.0));
      expect(arr.elements[3].toNumber(), equals(99.0));
      expect(arr.elements[4].toNumber(), equals(99.0));
    });

    test('fill method with value, start, and end', () {
      final code = '''
        const arr = new Float32Array([1, 2, 3, 4, 5]);
        arr.fill(7.5, 1, 4);
        const result = [];
        for (let i = 0; i < arr.length; i++) {
          result.push(arr[i]);
        }
        result;
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements.length, equals(5));
      expect(arr.elements[0].toNumber(), equals(1.0));
      expect(arr.elements[1].toNumber(), equals(7.5));
      expect(arr.elements[2].toNumber(), equals(7.5));
      expect(arr.elements[3].toNumber(), equals(7.5));
      expect(arr.elements[4].toNumber(), equals(5.0));
    });

    test('reverse method', () {
      final code = '''
        const arr = new Float64Array([1, 2, 3, 4, 5]);
        arr.reverse();
        const result = [];
        for (let i = 0; i < arr.length; i++) {
          result.push(arr[i]);
        }
        result;
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements.length, equals(5));
      expect(arr.elements[0].toNumber(), equals(5.0));
      expect(arr.elements[1].toNumber(), equals(4.0));
      expect(arr.elements[2].toNumber(), equals(3.0));
      expect(arr.elements[3].toNumber(), equals(2.0));
      expect(arr.elements[4].toNumber(), equals(1.0));
    });

    test('chaining methods', () {
      final code = '''
        const arr = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
        const result = arr
          .filter(function(x) { return x % 2 === 0; })
          .map(function(x) { return x * x; });
        
        const output = [];
        for (let i = 0; i < result.length; i++) {
          output.push(result[i]);
        }
        output;
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements.length, equals(5));
      expect(arr.elements[0].toNumber(), equals(4.0));   // 2²
      expect(arr.elements[1].toNumber(), equals(16.0));  // 4²
      expect(arr.elements[2].toNumber(), equals(36.0));  // 6²
      expect(arr.elements[3].toNumber(), equals(64.0));  // 8²
      expect(arr.elements[4].toNumber(), equals(100.0)); // 10²
    });

    test('complex data processing with multiple methods', () {
      final code = '''
        const data = new Float32Array([1.5, 2.7, 3.2, 4.8, 5.1, 6.3, 7.9, 8.4]);
        
        // Calculate the average of even values (rounded to integer)
        const evenIntegers = data.filter(function(x) {
          return Math.floor(x) % 2 === 0;
        });
        
        const sum = evenIntegers.reduce(function(acc, val) {
          return acc + val;
        }, 0);
        
        const count = evenIntegers.length;
        const average = sum / count;
        
        average;
      ''';

      final result = interpreter.eval(code);
      // evenIntegers: 2.7, 4.8, 6.3, 8.4 (floor values: 2, 4, 6, 8)
      // sum: 22.2, count: 4, average: 5.55
      expect(result.toNumber(), closeTo(5.55, 0.01));
    });

    test('index access in callbacks', () {
      final code = '''
        const arr = new Int8Array([10, 20, 30]);
        const indices = [];
        arr.forEach(function(value, index) {
          indices.push(index);
        });
        indices;
      ''';

      final result = interpreter.eval(code);
      final arr = result as JSArray;
      expect(arr.elements.length, equals(3));
      expect(arr.elements[0].toNumber(), equals(0.0));
      expect(arr.elements[1].toNumber(), equals(1.0));
      expect(arr.elements[2].toNumber(), equals(2.0));
    });

    test('array parameter in callbacks', () {
      final code = '''
        const arr = new Uint8Array([5, 10, 15]);
        let arrayRef = null;
        arr.forEach(function(value, index, array) {
          if (index === 0) {
            arrayRef = array;
          }
        });
        arrayRef.length;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(3.0));
    });

    test('error handling - callback not a function', () {
      final code = '''
        const arr = new Uint8Array([1, 2, 3]);
        try {
          arr.forEach(42);
          false;
        } catch (e) {
          true;
        }
      ''';

      final result = interpreter.eval(code);
      expect(result.toBoolean(), isTrue);
    });

    test('error handling - reduce empty array without initial value', () {
      final code = '''
        const arr = new Int8Array([]);
        try {
          arr.reduce(function(a, b) { return a + b; });
          false;
        } catch (e) {
          true;
        }
      ''';

      final result = interpreter.eval(code);
      expect(result.toBoolean(), isTrue);
    });
  });
}
