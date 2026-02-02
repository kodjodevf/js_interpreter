import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('Map Object Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Basic Map operations', () {
      interpreter.eval('''
        const map = new Map();
        map.set('a', 1);
        map.set('b', 2);
        map.set('c', 3);
      ''');

      expect(interpreter.eval('map.get("a")').primitiveValue, equals(1));
      expect(interpreter.eval('map.get("b")').primitiveValue, equals(2));
      expect(interpreter.eval('map.has("c")').primitiveValue, equals(true));
      expect(interpreter.eval('map.has("d")').primitiveValue, equals(false));
      expect(interpreter.eval('map.size').primitiveValue, equals(3));
    });

    test('Map delete operation', () {
      interpreter.eval('''
        const map = new Map();
        map.set('x', 10);
        map.set('y', 20);
        const deleted = map['delete']('x');
      ''');

      expect(interpreter.eval('deleted').primitiveValue, equals(true));
      expect(interpreter.eval('map.has("x")').primitiveValue, equals(false));
      expect(interpreter.eval('map.size').primitiveValue, equals(1));
    });

    test('Map clear operation', () {
      interpreter.eval('''
        const map = new Map();
        map.set('a', 1);
        map.set('b', 2);
        map['clear']();
      ''');

      expect(interpreter.eval('map.size').primitiveValue, equals(0));
      expect(interpreter.eval('map.get("a")').isUndefined, equals(true));
    });

    test('Map with object keys', () {
      interpreter.eval('''
        const map = new Map();
        const key1 = {};
        const key2 = {name: 'test'};
        map.set(key1, 'object1');
        map.set(key2, 'object2');
      ''');

      expect(
        interpreter.eval('map.get(key1)').primitiveValue,
        equals('object1'),
      );
      expect(
        interpreter.eval('map.get(key2)').primitiveValue,
        equals('object2'),
      );
      expect(interpreter.eval('map.size').primitiveValue, equals(2));
    });

    test('Map with array keys', () {
      interpreter.eval('''
        const map = new Map();
        const arr1 = [1, 2, 3];
        const arr2 = ['a', 'b'];
        map.set(arr1, 'array1');
        map.set(arr2, 'array2');
      ''');

      expect(
        interpreter.eval('map.get(arr1)').primitiveValue,
        equals('array1'),
      );
      expect(
        interpreter.eval('map.get(arr2)').primitiveValue,
        equals('array2'),
      );
      expect(interpreter.eval('map.size').primitiveValue, equals(2));
    });

    test('Map with number keys', () {
      interpreter.eval('''
        const map = new Map();
        map.set(42, 'forty-two');
        map.set(3.14, 'pi');
        map.set(0, 'zero');
      ''');

      expect(
        interpreter.eval('map.get(42)').primitiveValue,
        equals('forty-two'),
      );
      expect(interpreter.eval('map.get(3.14)').primitiveValue, equals('pi'));
      expect(interpreter.eval('map.get(0)').primitiveValue, equals('zero'));
      expect(interpreter.eval('map.size').primitiveValue, equals(3));
    });

    test('Map initialization with iterable', () {
      interpreter.eval('''
        const map = new Map([
          ['key1', 'value1'],
          ['key2', 'value2'],
          [42, 'number key']
        ]);
      ''');

      expect(
        interpreter.eval('map.get("key1")').primitiveValue,
        equals('value1'),
      );
      expect(
        interpreter.eval('map.get("key2")').primitiveValue,
        equals('value2'),
      );
      expect(
        interpreter.eval('map.get(42)').primitiveValue,
        equals('number key'),
      );
      expect(interpreter.eval('map.size').primitiveValue, equals(3));
    });

    test('Map chaining (set returns undefined)', () {
      interpreter.eval('''
        const map = new Map();
        const result = map.set('a', 1);
      ''');

      // set should return undefined, not the map itself
      expect(interpreter.eval('result').isUndefined, equals(true));
      expect(interpreter.eval('map.get("a")').primitiveValue, equals(1));
    });

    test('Map.groupBy with array', () {
      interpreter.eval('''
        const items = [1, 2, 3, 4, 5, 6];
        const grouped = Map.groupBy(items, (item) => item % 2 === 0 ? 'even' : 'odd');
      ''');

      expect(
        interpreter.eval('grouped.get("even").length').primitiveValue,
        equals(3),
      );
      expect(
        interpreter.eval('grouped.get("odd").length').primitiveValue,
        equals(3),
      );
      expect(
        interpreter.eval('grouped.get("even")[0]').primitiveValue,
        equals(2),
      );
      expect(
        interpreter.eval('grouped.get("odd")[0]').primitiveValue,
        equals(1),
      );
    });

    test('Map.groupBy with different key types', () {
      interpreter.eval('''
        const items = ['apple', 'banana', 'cherry', 'date'];
        const grouped = Map.groupBy(items, (item) => item.length);
      ''');

      expect(
        interpreter.eval('grouped.get(5).length').primitiveValue,
        equals(1),
      ); // apple
      expect(
        interpreter.eval('grouped.get(6).length').primitiveValue,
        equals(2),
      ); // banana, cherry
      expect(
        interpreter.eval('grouped.get(4).length').primitiveValue,
        equals(1),
      ); // date
    });

    test('Map.groupBy with Set', () {
      interpreter.eval('''
        const items = new Set([1, 2, 3, 4, 5, 6]);
        const grouped = Map.groupBy(items, (item) => item % 2 === 0 ? 'even' : 'odd');
      ''');

      expect(
        interpreter.eval('grouped.get("even").length').primitiveValue,
        equals(3),
      );
      expect(
        interpreter.eval('grouped.get("odd").length').primitiveValue,
        equals(3),
      );
    });

    test('Map.groupBy with string', () {
      interpreter.eval('''
        const str = 'hello world';
        const grouped = Map.groupBy(str, (char) => char === ' ' ? 'space' : 'letter');
      ''');

      expect(
        interpreter.eval('grouped.get("letter").length').primitiveValue,
        equals(10),
      ); // h,e,l,l,o,w,o,r,l,d
      expect(
        interpreter.eval('grouped.get("space").length').primitiveValue,
        equals(1),
      ); // space
    });

    test('Map.groupBy with plain object (property iteration)', () {
      interpreter.eval('''
        const obj = {a: 1, b: 2, c: 3, d: 4};
        const grouped = Map.groupBy(obj, (value) => value % 2 === 0 ? 'even' : 'odd');
      ''');

      expect(
        interpreter.eval('grouped.get("odd").length').primitiveValue,
        equals(2),
      ); // 1, 3
      expect(
        interpreter.eval('grouped.get("even").length').primitiveValue,
        equals(2),
      ); // 2, 4
    });
  });
}
