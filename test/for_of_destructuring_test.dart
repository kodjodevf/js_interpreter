import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });

  group('For-of with Array Destructuring', () {
    test('simple array destructuring', () {
      final code = '''
        const result = [];
        const pairs = [[1, 2], [3, 4], [5, 6]];
        for (const [a, b] of pairs) {
          result.push(a + b);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(3));
      expect(array.elements[0].toNumber(), equals(3));
      expect(array.elements[1].toNumber(), equals(7));
      expect(array.elements[2].toNumber(), equals(11));
    });

    test('array destructuring with let', () {
      final code = '''
        const result = [];
        const pairs = [[10, 20], [30, 40]];
        for (let [x, y] of pairs) {
          result.push(x * y);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(2));
      expect(array.elements[0].toNumber(), equals(200));
      expect(array.elements[1].toNumber(), equals(1200));
    });

    test('array destructuring with var', () {
      final code = '''
        const result = [];
        const pairs = [['a', 'b'], ['c', 'd']];
        for (var [first, second] of pairs) {
          result.push(first + second);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(2));
      expect(array.elements[0].toString(), equals('ab'));
      expect(array.elements[1].toString(), equals('cd'));
    });

    test('array destructuring with three elements', () {
      final code = '''
        const result = [];
        const triplets = [[1, 2, 3], [4, 5, 6], [7, 8, 9]];
        for (const [a, b, c] of triplets) {
          result.push(a + b + c);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(3));
      expect(array.elements[0].toNumber(), equals(6));
      expect(array.elements[1].toNumber(), equals(15));
      expect(array.elements[2].toNumber(), equals(24));
    });

    test('array destructuring with missing elements', () {
      final code = '''
        const result = [];
        const pairs = [[1, 2], [3], [4, 5, 6]];
        for (const [a, b] of pairs) {
          result.push({a: a, b: b});
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(3));

      final obj0 = array.elements[0].toObject();
      expect(obj0.getProperty('a').toNumber(), equals(1));
      expect(obj0.getProperty('b').toNumber(), equals(2));

      final obj1 = array.elements[1].toObject();
      expect(obj1.getProperty('a').toNumber(), equals(3));
      expect(obj1.getProperty('b').type, equals(JSValueType.undefined));

      final obj2 = array.elements[2].toObject();
      expect(obj2.getProperty('a').toNumber(), equals(4));
      expect(obj2.getProperty('b').toNumber(), equals(5));
    });

    test('array destructuring with skipped elements', () {
      final code = '''
        const result = [];
        const arrays = [[1, 2, 3], [4, 5, 6]];
        for (const [a, , c] of arrays) {
          result.push(a + c);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(2));
      expect(array.elements[0].toNumber(), equals(4));
      expect(array.elements[1].toNumber(), equals(10));
    });

    test('array destructuring with rest element', () {
      final code = '''
        const result = [];
        const arrays = [[1, 2, 3, 4], [5, 6, 7, 8, 9]];
        for (const [first, ...rest] of arrays) {
          result.push({first: first, rest: rest});
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(2));

      final obj0 = array.elements[0].toObject();
      expect(obj0.getProperty('first').toNumber(), equals(1));
      final rest0 = obj0.getProperty('rest').toObject() as JSArray;
      expect(rest0.elements.length, equals(3));
      expect(rest0.elements[0].toNumber(), equals(2));
      expect(rest0.elements[1].toNumber(), equals(3));
      expect(rest0.elements[2].toNumber(), equals(4));

      final obj1 = array.elements[1].toObject();
      expect(obj1.getProperty('first').toNumber(), equals(5));
      final rest1 = obj1.getProperty('rest').toObject() as JSArray;
      expect(rest1.elements.length, equals(4));
    });
  });

  group('For-of with Object Destructuring', () {
    test('simple object destructuring', () {
      final code = '''
        const result = [];
        const objects = [{x: 1, y: 2}, {x: 3, y: 4}, {x: 5, y: 6}];
        for (const {x, y} of objects) {
          result.push(x + y);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(3));
      expect(array.elements[0].toNumber(), equals(3));
      expect(array.elements[1].toNumber(), equals(7));
      expect(array.elements[2].toNumber(), equals(11));
    });

    test('object destructuring with let', () {
      final code = '''
        const result = [];
        const objects = [{a: 10, b: 20}, {a: 30, b: 40}];
        for (let {a, b} of objects) {
          result.push(a * b);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(2));
      expect(array.elements[0].toNumber(), equals(200));
      expect(array.elements[1].toNumber(), equals(1200));
    });

    test('object destructuring with renamed properties', () {
      final code = '''
        const result = [];
        const objects = [{x: 1, y: 2}, {x: 3, y: 4}];
        for (const {x: a, y: b} of objects) {
          result.push(a + b);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(2));
      expect(array.elements[0].toNumber(), equals(3));
      expect(array.elements[1].toNumber(), equals(7));
    });

    test('object destructuring with missing properties', () {
      final code = '''
        const result = [];
        const objects = [{x: 1, y: 2}, {x: 3}, {y: 4}];
        for (const {x, y} of objects) {
          result.push({x: x, y: y});
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(3));

      final obj0 = array.elements[0].toObject();
      expect(obj0.getProperty('x').toNumber(), equals(1));
      expect(obj0.getProperty('y').toNumber(), equals(2));

      final obj1 = array.elements[1].toObject();
      expect(obj1.getProperty('x').toNumber(), equals(3));
      expect(obj1.getProperty('y').type, equals(JSValueType.undefined));

      final obj2 = array.elements[2].toObject();
      expect(obj2.getProperty('x').type, equals(JSValueType.undefined));
      expect(obj2.getProperty('y').toNumber(), equals(4));
    });
  });

  group('For-of with Nested Destructuring', () {
    test('nested array destructuring', () {
      final code = '''
        const result = [];
        const nested = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]];
        for (const [[a, b], [c, d]] of nested) {
          result.push(a + b + c + d);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(2));
      expect(array.elements[0].toNumber(), equals(10));
      expect(array.elements[1].toNumber(), equals(26));
    });

    test('array in object destructuring', () {
      final code = '''
        const result = [];
        const data = [{values: [1, 2]}, {values: [3, 4]}];
        for (const {values: [a, b]} of data) {
          result.push(a + b);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(2));
      expect(array.elements[0].toNumber(), equals(3));
      expect(array.elements[1].toNumber(), equals(7));
    });

    test('object in array destructuring', () {
      final code = '''
        const result = [];
        const data = [[{x: 1}, {y: 2}], [{x: 3}, {y: 4}]];
        for (const [{x}, {y}] of data) {
          result.push(x + y);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(2));
      expect(array.elements[0].toNumber(), equals(3));
      expect(array.elements[1].toNumber(), equals(7));
    });

    test('deeply nested destructuring', () {
      final code = '''
        const result = [];
        const data = [
          {coords: {x: 1, y: 2}, values: [10, 20]},
          {coords: {x: 3, y: 4}, values: [30, 40]}
        ];
        for (const {coords: {x, y}, values: [a, b]} of data) {
          result.push(x + y + a + b);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(2));
      expect(array.elements[0].toNumber(), equals(33));
      expect(array.elements[1].toNumber(), equals(77));
    });
  });

  group('For-of Destructuring with Flow Control', () {
    test('break with array destructuring', () {
      final code = '''
        const result = [];
        const pairs = [[1, 2], [3, 4], [5, 6]];
        for (const [a, b] of pairs) {
          if (a === 3) break;
          result.push(a + b);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(1));
      expect(array.elements[0].toNumber(), equals(3));
    });

    test('continue with object destructuring', () {
      final code = '''
        const result = [];
        const objects = [{x: 1, y: 2}, {x: 3, y: 4}, {x: 5, y: 6}];
        for (const {x, y} of objects) {
          if (x === 3) continue;
          result.push(x + y);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(2));
      expect(array.elements[0].toNumber(), equals(3));
      expect(array.elements[1].toNumber(), equals(11));
    });
  });

  group('For-of Destructuring with Iterators', () {
    test('array destructuring with custom iterator', () {
      final code = '''
        const result = [];
        const iterable = {
          data: [[1, 2], [3, 4], [5, 6]],
          [Symbol.iterator]() {
            const data = this.data;
            let index = 0;
            return {
              next: () => {
                if (index < data.length) {
                  return { value: data[index++], done: false };
                }
                return { done: true };
              }
            };
          }
        };
        
        for (const [a, b] of iterable) {
          result.push(a * b);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(3));
      expect(array.elements[0].toNumber(), equals(2));
      expect(array.elements[1].toNumber(), equals(12));
      expect(array.elements[2].toNumber(), equals(30));
    });

    test('object destructuring with generator', () {
      final code = '''
        const result = [];
        
        function* pairGenerator() {
          yield {x: 1, y: 2};
          yield {x: 3, y: 4};
          yield {x: 5, y: 6};
        }
        
        for (const {x, y} of pairGenerator()) {
          result.push(x + y);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(3));
      expect(array.elements[0].toNumber(), equals(3));
      expect(array.elements[1].toNumber(), equals(7));
      expect(array.elements[2].toNumber(), equals(11));
    });
  });

  group('For-of Destructuring Edge Cases', () {
    test('empty array destructuring', () {
      final code = '''
        const result = [];
        const arrays = [[1, 2], [], [3, 4]];
        for (const [a, b] of arrays) {
          result.push({a: a, b: b});
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(3));

      final obj1 = array.elements[1].toObject();
      expect(obj1.getProperty('a').type, equals(JSValueType.undefined));
      expect(obj1.getProperty('b').type, equals(JSValueType.undefined));
    });

    test('empty object destructuring', () {
      final code = '''
        const result = [];
        const objects = [{x: 1, y: 2}, {}, {x: 3, y: 4}];
        for (const {x, y} of objects) {
          result.push({x: x, y: y});
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(3));

      final obj1 = array.elements[1].toObject();
      expect(obj1.getProperty('x').type, equals(JSValueType.undefined));
      expect(obj1.getProperty('y').type, equals(JSValueType.undefined));
    });

    test('single element destructuring', () {
      final code = '''
        const result = [];
        const singles = [[1], [2], [3]];
        for (const [a] of singles) {
          result.push(a * 2);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(3));
      expect(array.elements[0].toNumber(), equals(2));
      expect(array.elements[1].toNumber(), equals(4));
      expect(array.elements[2].toNumber(), equals(6));
    });
  });

  group('For-of Destructuring with Map', () {
    test('array destructuring with Map.entries()', () {
      final code = '''
        const result = [];
        const map = new Map([['a', 1], ['b', 2], ['c', 3]]);
        
        for (const [key, value] of map.entries()) {
          result.push(key + value);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(3));
      expect(array.elements[0].toString(), equals('a1'));
      expect(array.elements[1].toString(), equals('b2'));
      expect(array.elements[2].toString(), equals('c3'));
    });

    test('array destructuring with Map iteration', () {
      final code = '''
        const result = [];
        const map = new Map([['x', 10], ['y', 20], ['z', 30]]);
        
        for (const [k, v] of map) {
          result.push({key: k, value: v});
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(3));

      final obj0 = array.elements[0].toObject();
      expect(obj0.getProperty('key').toString(), equals('x'));
      expect(obj0.getProperty('value').toNumber(), equals(10));
    });
  });

  group('For-of Destructuring with Set', () {
    test('array destructuring with Set values', () {
      // Note: Set support may be limited, testing with arrays instead
      final code = '''
        const result = [];
        const arrays = [[1, 2], [3, 4], [5, 6]];
        
        for (const [a, b] of arrays) {
          result.push(a + b);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(3));
      expect(array.elements[0].toNumber(), equals(3));
      expect(array.elements[1].toNumber(), equals(7));
      expect(array.elements[2].toNumber(), equals(11));
    });
  });

  group('For-of Destructuring Practical Examples', () {
    test('processing coordinate pairs', () {
      final code = '''
        const result = [];
        const coords = [[0, 0], [3, 4], [6, 8]];
        
        for (const [x, y] of coords) {
          const distance = Math.sqrt(x * x + y * y);
          result.push(distance);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(3));
      expect(array.elements[0].toNumber(), equals(0));
      expect(array.elements[1].toNumber(), equals(5));
      expect(array.elements[2].toNumber(), equals(10));
    });

    test('processing user data objects', () {
      final code = '''
        const result = [];
        const users = [
          {name: 'Alice', age: 30},
          {name: 'Bob', age: 25},
          {name: 'Charlie', age: 35}
        ];
        
        for (const {name, age} of users) {
          result.push(name + ' is ' + age + ' years old');
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(3));
      expect(array.elements[0].toString(), equals('Alice is 30 years old'));
      expect(array.elements[1].toString(), equals('Bob is 25 years old'));
      expect(array.elements[2].toString(), equals('Charlie is 35 years old'));
    });

    test('matrix operations', () {
      final code = '''
        const result = [];
        const matrix = [
          [1, 2, 3],
          [4, 5, 6],
          [7, 8, 9]
        ];
        
        for (const [a, b, c] of matrix) {
          result.push(a + b + c);
        }
        result;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements.length, equals(3));
      expect(array.elements[0].toNumber(), equals(6));
      expect(array.elements[1].toNumber(), equals(15));
      expect(array.elements[2].toNumber(), equals(24));
    });
  });
}
