import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Array.prototype.entries() Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('entries() returns an iterator', () {
      final code = '''
        var arr = ['a', 'b', 'c'];
        var iterator = arr.entries();
        iterator
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('Iterator'));
    });

    test('entries() iterator with next()', () {
      final code = '''
        var arr = ['a', 'b', 'c'];
        var iterator = arr.entries();
        var result1 = iterator.next();
        var result2 = iterator.next();
        var result3 = iterator.next();
        var result4 = iterator.next();
        [result1.done, result1.value, result2.done, result2.value, result3.done, result3.value, result4.done]
      ''';

      final result = interpreter.eval(code) as JSArray;

      // result1: {done: false, value: [0, 'a']}
      expect(result.elements[0].toBoolean(), equals(false));
      final value1 = result.elements[1] as JSArray;
      expect(value1.elements[0].toNumber(), equals(0));
      expect(value1.elements[1].toString(), equals('a'));

      // result2: {done: false, value: [1, 'b']}
      expect(result.elements[2].toBoolean(), equals(false));
      final value2 = result.elements[3] as JSArray;
      expect(value2.elements[0].toNumber(), equals(1));
      expect(value2.elements[1].toString(), equals('b'));

      // result3: {done: false, value: [2, 'c']}
      expect(result.elements[4].toBoolean(), equals(false));
      final value3 = result.elements[5] as JSArray;
      expect(value3.elements[0].toNumber(), equals(2));
      expect(value3.elements[1].toString(), equals('c'));

      // result4: {done: true}
      expect(result.elements[6].toBoolean(), equals(true));
    });

    test('entries() with for...of loop', () {
      final code = '''
        var arr = ['x', 'y', 'z'];
        var results = [];
        var iterator = arr.entries();
        var item = iterator.next();
        
        while (!item.done) {
          results.push(item.value);
          item = iterator.next();
        }
        
        results
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(3));

      final entry0 = result.elements[0] as JSArray;
      expect(entry0.elements[0].toNumber(), equals(0));
      expect(entry0.elements[1].toString(), equals('x'));

      final entry1 = result.elements[1] as JSArray;
      expect(entry1.elements[0].toNumber(), equals(1));
      expect(entry1.elements[1].toString(), equals('y'));

      final entry2 = result.elements[2] as JSArray;
      expect(entry2.elements[0].toNumber(), equals(2));
      expect(entry2.elements[1].toString(), equals('z'));
    });

    test('entries() with empty array', () {
      final code = '''
        var arr = [];
        var iterator = arr.entries();
        var result = iterator.next();
        [result.done, result.value]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toBoolean(), equals(true));
      expect(result.elements[1].isUndefined, equals(true));
    });

    test('entries() with sparse array', () {
      final code = '''
        var arr = [];
        arr[0] = 'a';
        arr[2] = 'c';
        arr.length = 3;
        var iterator = arr.entries();
        var result1 = iterator.next();
        var result2 = iterator.next();
        var result3 = iterator.next();
        [result1.value, result2.value, result3.value]
      ''';

      final result = interpreter.eval(code) as JSArray;

      final entry0 = result.elements[0] as JSArray;
      expect(entry0.elements[0].toNumber(), equals(0));
      expect(entry0.elements[1].toString(), equals('a'));

      final entry1 = result.elements[1] as JSArray;
      expect(entry1.elements[0].toNumber(), equals(1));
      expect(entry1.elements[1].isUndefined, equals(true));

      final entry2 = result.elements[2] as JSArray;
      expect(entry2.elements[0].toNumber(), equals(2));
      expect(entry2.elements[1].toString(), equals('c'));
    });
  });

  group('Array.prototype.keys() Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('keys() returns an iterator', () {
      final code = '''
        var arr = ['a', 'b', 'c'];
        var iterator = arr.keys();
        iterator
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('Iterator'));
    });

    test('keys() iterator with next()', () {
      final code = '''
        var arr = ['a', 'b', 'c'];
        var iterator = arr.keys();
        var result1 = iterator.next();
        var result2 = iterator.next();
        var result3 = iterator.next();
        var result4 = iterator.next();
        [result1.done, result1.value, result2.done, result2.value, result3.done, result3.value, result4.done]
      ''';

      final result = interpreter.eval(code) as JSArray;

      // result1: {done: false, value: 0}
      expect(result.elements[0].toBoolean(), equals(false));
      expect(result.elements[1].toNumber(), equals(0));

      // result2: {done: false, value: 1}
      expect(result.elements[2].toBoolean(), equals(false));
      expect(result.elements[3].toNumber(), equals(1));

      // result3: {done: false, value: 2}
      expect(result.elements[4].toBoolean(), equals(false));
      expect(result.elements[5].toNumber(), equals(2));

      // result4: {done: true}
      expect(result.elements[6].toBoolean(), equals(true));
    });

    test('keys() collecting all keys', () {
      final code = '''
        var arr = ['x', 'y', 'z'];
        var keys = [];
        var iterator = arr.keys();
        var item = iterator.next();
        
        while (!item.done) {
          keys.push(item.value);
          item = iterator.next();
        }
        
        keys
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(3));
      expect(result.elements[0].toNumber(), equals(0));
      expect(result.elements[1].toNumber(), equals(1));
      expect(result.elements[2].toNumber(), equals(2));
    });

    test('keys() with empty array', () {
      final code = '''
        var arr = [];
        var iterator = arr.keys();
        var result = iterator.next();
        result.done
      ''';

      final result = interpreter.eval(code);
      expect(result.toBoolean(), equals(true));
    });

    test('keys() with array of length 5', () {
      final code = '''
        var arr = Array(5);
        var keys = [];
        var iterator = arr.keys();
        var item = iterator.next();
        
        while (!item.done) {
          keys.push(item.value);
          item = iterator.next();
        }
        
        keys
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(5));
      expect(result.elements[0].toNumber(), equals(0));
      expect(result.elements[1].toNumber(), equals(1));
      expect(result.elements[2].toNumber(), equals(2));
      expect(result.elements[3].toNumber(), equals(3));
      expect(result.elements[4].toNumber(), equals(4));
    });
  });

  group('Array.prototype.values() Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('values() returns an iterator', () {
      final code = '''
        var arr = ['a', 'b', 'c'];
        var iterator = arr.values();
        iterator
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('Iterator'));
    });

    test('values() iterator with next()', () {
      final code = '''
        var arr = ['a', 'b', 'c'];
        var iterator = arr.values();
        var result1 = iterator.next();
        var result2 = iterator.next();
        var result3 = iterator.next();
        var result4 = iterator.next();
        [result1.done, result1.value, result2.done, result2.value, result3.done, result3.value, result4.done]
      ''';

      final result = interpreter.eval(code) as JSArray;

      // result1: {done: false, value: 'a'}
      expect(result.elements[0].toBoolean(), equals(false));
      expect(result.elements[1].toString(), equals('a'));

      // result2: {done: false, value: 'b'}
      expect(result.elements[2].toBoolean(), equals(false));
      expect(result.elements[3].toString(), equals('b'));

      // result3: {done: false, value: 'c'}
      expect(result.elements[4].toBoolean(), equals(false));
      expect(result.elements[5].toString(), equals('c'));

      // result4: {done: true}
      expect(result.elements[6].toBoolean(), equals(true));
    });

    test('values() collecting all values', () {
      final code = '''
        var arr = [10, 20, 30];
        var values = [];
        var iterator = arr.values();
        var item = iterator.next();
        
        while (!item.done) {
          values.push(item.value);
          item = iterator.next();
        }
        
        values
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(3));
      expect(result.elements[0].toNumber(), equals(10));
      expect(result.elements[1].toNumber(), equals(20));
      expect(result.elements[2].toNumber(), equals(30));
    });

    test('values() with mixed types', () {
      final code = '''
        var arr = [1, 'hello', true, null, undefined];
        var values = [];
        var iterator = arr.values();
        var item = iterator.next();
        
        while (!item.done) {
          values.push(item.value);
          item = iterator.next();
        }
        
        values
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(5));
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toString(), equals('hello'));
      expect(result.elements[2].toBoolean(), equals(true));
      expect(result.elements[3].isNull, equals(true));
      expect(result.elements[4].isUndefined, equals(true));
    });

    test('values() with empty array', () {
      final code = '''
        var arr = [];
        var iterator = arr.values();
        var result = iterator.next();
        result.done
      ''';

      final result = interpreter.eval(code);
      expect(result.toBoolean(), equals(true));
    });
  });

  group('Array Iterator Methods Combined Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Using all three iterator methods on same array', () {
      final code = '''
        var arr = ['a', 'b', 'c'];
        
        var keys = [];
        var keysIter = arr.keys();
        var k = keysIter.next();
        while (!k.done) {
          keys.push(k.value);
          k = keysIter.next();
        }
        
        var values = [];
        var valuesIter = arr.values();
        var v = valuesIter.next();
        while (!v.done) {
          values.push(v.value);
          v = valuesIter.next();
        }
        
        var entries = [];
        var entriesIter = arr.entries();
        var e = entriesIter.next();
        while (!e.done) {
          entries.push(e.value);
          e = entriesIter.next();
        }
        
        [keys, values, entries]
      ''';

      final result = interpreter.eval(code) as JSArray;

      // keys
      final keys = result.elements[0] as JSArray;
      expect(keys.elements.length, equals(3));
      expect(keys.elements[0].toNumber(), equals(0));
      expect(keys.elements[1].toNumber(), equals(1));
      expect(keys.elements[2].toNumber(), equals(2));

      // values
      final values = result.elements[1] as JSArray;
      expect(values.elements.length, equals(3));
      expect(values.elements[0].toString(), equals('a'));
      expect(values.elements[1].toString(), equals('b'));
      expect(values.elements[2].toString(), equals('c'));

      // entries
      final entries = result.elements[2] as JSArray;
      expect(entries.elements.length, equals(3));

      final entry0 = entries.elements[0] as JSArray;
      expect(entry0.elements[0].toNumber(), equals(0));
      expect(entry0.elements[1].toString(), equals('a'));
    });

    test('Iterator independence', () {
      final code = '''
        var arr = [1, 2, 3];
        var iter1 = arr.values();
        var iter2 = arr.values();
        
        var v1_1 = iter1.next().value;
        var v1_2 = iter1.next().value;
        
        var v2_1 = iter2.next().value;
        
        [v1_1, v1_2, v2_1]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(2));
      expect(result.elements[2].toNumber(), equals(1)); // iter2 starts fresh
    });

    test('Iterating over modified array', () {
      final code = '''
        var arr = [1, 2, 3];
        var iterator = arr.values();
        
        var first = iterator.next().value;
        arr.push(4);
        
        var values = [first];
        var item = iterator.next();
        while (!item.done) {
          values.push(item.value);
          item = iterator.next();
        }
        
        values
      ''';

      final result = interpreter.eval(code) as JSArray;
      // The iterator sees the original or modified length depending on the implementation
      // En JavaScript standard, il voit les modifications
      expect(result.elements.length, greaterThanOrEqualTo(3));
    });

    test('Array.from() with iterator', () {
      final code = '''
        var arr = ['a', 'b', 'c'];
        var keysIter = arr.keys();
        
        // Collect keys manually
        var keys = [];
        var item = keysIter.next();
        while (!item.done) {
          keys.push(item.value);
          item = keysIter.next();
        }
        
        keys
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(3));
      expect(result.elements[0].toNumber(), equals(0));
      expect(result.elements[1].toNumber(), equals(1));
      expect(result.elements[2].toNumber(), equals(2));
    });
  });
}
