import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Array.from() Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Array.from() with array', () {
      final code = '''
        var arr = [1, 2, 3];
        var result = Array.from(arr);
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(3));
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(2));
      expect(result.elements[2].toNumber(), equals(3));
    });

    test('Array.from() with string', () {
      final code = '''
        var result = Array.from('hello');
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(5));
      expect(result.elements[0].toString(), equals('h'));
      expect(result.elements[1].toString(), equals('e'));
      expect(result.elements[2].toString(), equals('l'));
      expect(result.elements[3].toString(), equals('l'));
      expect(result.elements[4].toString(), equals('o'));
    });

    test('Array.from() with Set', () {
      interpreter.eval('var testSet = new Set()');
      interpreter.eval('testSet.add(1)');
      interpreter.eval('testSet.add(2)');
      interpreter.eval('testSet.add(3)');
      interpreter.eval('testSet.add(2)');
      interpreter.eval('testSet.add(1)');

      final result = interpreter.eval('Array.from(testSet)') as JSArray;
      expect(result.elements.length, equals(3));
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(2));
      expect(result.elements[2].toNumber(), equals(3));
    });

    test('Array.from() with Map', () {
      final code = '''
        var map = new Map();
        map.set('a', 1);
        map.set('b', 2);
        var result = Array.from(map);
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(2));

      // Each element must be a [key, value] array
      final first = result.elements[0] as JSArray;
      expect(first.elements[0].toString(), equals('a'));
      expect(first.elements[1].toNumber(), equals(1));

      final second = result.elements[1] as JSArray;
      expect(second.elements[0].toString(), equals('b'));
      expect(second.elements[1].toNumber(), equals(2));
    });

    test('Array.from() with array-like object', () {
      final code = '''
        var arrayLike = {};
        arrayLike["0"] = 'a';
        arrayLike["1"] = 'b';
        arrayLike["2"] = 'c';
        arrayLike.length = 3;
        var result = Array.from(arrayLike);
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(3));
      expect(result.elements[0].toString(), equals('a'));
      expect(result.elements[1].toString(), equals('b'));
      expect(result.elements[2].toString(), equals('c'));
    });

    test('Array.from() with mapFn', () {
      final code = '''
        var result = Array.from([1, 2, 3], function(x) { return x * 2; });
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(3));
      expect(result.elements[0].toNumber(), equals(2));
      expect(result.elements[1].toNumber(), equals(4));
      expect(result.elements[2].toNumber(), equals(6));
    });

    test('Array.from() with mapFn and index', () {
      final code = '''
        var result = Array.from([10, 20, 30], function(x, i) { return x + i; });
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(3));
      expect(result.elements[0].toNumber(), equals(10)); // 10 + 0
      expect(result.elements[1].toNumber(), equals(21)); // 20 + 1
      expect(result.elements[2].toNumber(), equals(32)); // 30 + 2
    });

    test('Array.from() with mapFn and thisArg', () {
      final code = '''
        var multiplier = {
          factor: 3,
          multiply: function(x) { return x * this.factor; }
        };
        var result = Array.from([1, 2, 3], multiplier.multiply, multiplier);
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(3));
      expect(result.elements[0].toNumber(), equals(3));
      expect(result.elements[1].toNumber(), equals(6));
      expect(result.elements[2].toNumber(), equals(9));
    });

    test('Array.from() with arrow function', () {
      final code = '''
        var result = Array.from([1, 2, 3], x => x * x);
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(3));
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(4));
      expect(result.elements[2].toNumber(), equals(9));
    });

    test('Array.from() throws error when mapFn is not a function', () {
      final code = '''
        Array.from([1, 2, 3], "not a function");
      ''';

      expect(() => interpreter.eval(code), throwsA(isA<JSException>()));
    });

    test('Array.from() requires at least one argument', () {
      final code = '''
        Array.from();
      ''';

      expect(() => interpreter.eval(code), throwsA(isA<JSException>()));
    });
  });

  group('Array.of() Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Array.of() with multiple arguments', () {
      final code = '''
        var result = Array.of(1, 2, 3);
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(3));
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(2));
      expect(result.elements[2].toNumber(), equals(3));
    });

    test('Array.of() with single number argument', () {
      final code = '''
        var result1 = Array.of(7);
        var result2 = Array(7);
        [result1.length, result2.length]
      ''';

      final result = interpreter.eval(code) as JSArray;
      // Array.of(7) creates [7] (length 1)
      // Array(7) creates an array with length 7 empty
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(7));
    });

    test('Array.of() with no arguments', () {
      final code = '''
        var result = Array.of();
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(0));
    });

    test('Array.of() with mixed types', () {
      final code = '''
        var result = Array.of(1, 'hello', true, null, undefined);
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(5));
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toString(), equals('hello'));
      expect(result.elements[2].toBoolean(), equals(true));
      expect(result.elements[3].isNull, equals(true));
      expect(result.elements[4].isUndefined, equals(true));
    });

    test('Array.of() with objects and arrays', () {
      final code = '''
        var obj = { name: 'test' };
        var arr = [1, 2, 3];
        var result = Array.of(obj, arr, 'string');
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(3));
      expect(result.elements[0].isObject, equals(true));
      expect(result.elements[1] is JSArray, equals(true));
      expect(result.elements[2].toString(), equals('string'));
    });

    test('Array.of() vs Array constructor difference', () {
      final code = '''
        // Array.of() creates an array with the provided elements
        var of1 = Array.of(1);
        var of2 = Array.of(1, 2, 3);
        
        // Array() with a number creates an empty array of that size
        var arr1 = Array(1);
        var arr2 = Array(1, 2, 3);
        
        [of1.length, of2.length, arr1.length, arr2.length]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(
        result.elements[0].toNumber(),
        equals(1),
      ); // Array.of(1) length = 1
      expect(
        result.elements[1].toNumber(),
        equals(3),
      ); // Array.of(1,2,3) length = 3
      expect(result.elements[2].toNumber(), equals(1)); // Array(1) length = 1
      expect(
        result.elements[3].toNumber(),
        equals(3),
      ); // Array(1,2,3) length = 3
    });
  });

  group('Array.from() and Array.of() Combined Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Chaining Array.from() and Array.of()', () {
      final code = '''
        var arr1 = Array.of(1, 2, 3);
        var arr2 = Array.from(arr1, x => x * 2);
        arr2
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(3));
      expect(result.elements[0].toNumber(), equals(2));
      expect(result.elements[1].toNumber(), equals(4));
      expect(result.elements[2].toNumber(), equals(6));
    });

    test('Complex transformation with Array.from()', () {
      final code = '''
        var users = [
          { name: 'Alice', age: 25 },
          { name: 'Bob', age: 30 },
          { name: 'Charlie', age: 35 }
        ];
        
        var names = Array.from(users, user => user.name);
        names
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(3));
      expect(result.elements[0].toString(), equals('Alice'));
      expect(result.elements[1].toString(), equals('Bob'));
      expect(result.elements[2].toString(), equals('Charlie'));
    });

    test('Creating range with Array.from()', () {
      final code = '''
        // Create a range from 1 to 5
        var range = Array.from({length: 5}, function(_, i) { return i + 1; });
        range
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(5));
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(2));
      expect(result.elements[2].toNumber(), equals(3));
      expect(result.elements[3].toNumber(), equals(4));
      expect(result.elements[4].toNumber(), equals(5));
    });

    test('Array.from() with string manipulation', () {
      final code = '''
        var str = "abc";
        var result = Array.from(str, c => c.toUpperCase());
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(3));
      expect(result.elements[0].toString(), equals('A'));
      expect(result.elements[1].toString(), equals('B'));
      expect(result.elements[2].toString(), equals('C'));
    });
  });
}
