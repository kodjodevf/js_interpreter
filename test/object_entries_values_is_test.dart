import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Object.entries() Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Object.entries() with simple object', () {
      final code = '''
        var obj = {a: 1, b: 2, c: 3};
        var result = Object.entries(obj);
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(3));

      // Each element is [key, value]
      final entry0 = result.elements[0] as JSArray;
      expect(entry0.elements[0].toString(), equals('a'));
      expect(entry0.elements[1].toNumber(), equals(1));

      final entry1 = result.elements[1] as JSArray;
      expect(entry1.elements[0].toString(), equals('b'));
      expect(entry1.elements[1].toNumber(), equals(2));

      final entry2 = result.elements[2] as JSArray;
      expect(entry2.elements[0].toString(), equals('c'));
      expect(entry2.elements[1].toNumber(), equals(3));
    });

    test('Object.entries() with mixed types', () {
      final code = '''
        var obj = {
          name: 'Alice',
          age: 30,
          active: true
        };
        var result = Object.entries(obj);
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(3));
    });

    test('Object.entries() with empty object', () {
      final code = '''
        var obj = {};
        var result = Object.entries(obj);
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(0));
    });

    test('Object.entries() with non-object returns empty array', () {
      final code = '''
        var result = Object.entries(42);
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(0));
    });
  });

  group('Object.values() Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Object.values() with simple object', () {
      final code = '''
        var obj = {a: 1, b: 2, c: 3};
        var result = Object.values(obj);
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(3));
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(2));
      expect(result.elements[2].toNumber(), equals(3));
    });

    test('Object.values() with mixed types', () {
      final code = '''
        var obj = {
          name: 'Bob',
          age: 25,
          active: false
        };
        var result = Object.values(obj);
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(3));
      expect(result.elements[0].toString(), equals('Bob'));
      expect(result.elements[1].toNumber(), equals(25));
      expect(result.elements[2].toBoolean(), equals(false));
    });

    test('Object.values() with empty object', () {
      final code = '''
        var obj = {};
        var result = Object.values(obj);
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(0));
    });

    test('Object.values() with non-object returns empty array', () {
      final code = '''
        var result = Object.values('string');
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(0));
    });
  });

  group('Object.is() Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Object.is() with same values', () {
      final code = '''
        [
          Object.is(1, 1),
          Object.is('hello', 'hello'),
          Object.is(true, true),
          Object.is(false, false)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toBoolean(), equals(true));
      expect(result.elements[1].toBoolean(), equals(true));
      expect(result.elements[2].toBoolean(), equals(true));
      expect(result.elements[3].toBoolean(), equals(true));
    });

    test('Object.is() with different values', () {
      final code = '''
        [
          Object.is(1, 2),
          Object.is('hello', 'world'),
          Object.is(true, false),
          Object.is(1, '1')
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toBoolean(), equals(false));
      expect(result.elements[1].toBoolean(), equals(false));
      expect(result.elements[2].toBoolean(), equals(false));
      expect(result.elements[3].toBoolean(), equals(false));
    });

    test('Object.is() with NaN (different from ===)', () {
      final code = '''
        var nan = 0 / 0;
        [
          Object.is(nan, nan),
          nan === nan
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      // Object.is(NaN, NaN) should be true
      expect(result.elements[0].toBoolean(), equals(true));
      // NaN === NaN should be false
      expect(result.elements[1].toBoolean(), equals(false));
    });

    test('Object.is() with +0 and -0 (different from ===)', () {
      final code = '''
        [
          Object.is(0, -0),
          Object.is(+0, -0),
          0 === -0
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      // Object.is(0, -0) should be false
      expect(result.elements[0].toBoolean(), equals(false));
      expect(result.elements[1].toBoolean(), equals(false));
      // 0 === -0 should be true
      expect(result.elements[2].toBoolean(), equals(true));
    });

    test('Object.is() with null and undefined', () {
      final code = '''
        [
          Object.is(null, null),
          Object.is(undefined, undefined),
          Object.is(null, undefined)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toBoolean(), equals(true));
      expect(result.elements[1].toBoolean(), equals(true));
      expect(result.elements[2].toBoolean(), equals(false));
    });

    test('Object.is() with objects (reference comparison)', () {
      final code = '''
        var obj1 = {a: 1};
        var obj2 = {a: 1};
        var obj3 = obj1;
        [
          Object.is(obj1, obj1),
          Object.is(obj1, obj2),
          Object.is(obj1, obj3)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toBoolean(), equals(true)); // Same reference
      expect(
        result.elements[1].toBoolean(),
        equals(false),
      ); // Different objects
      expect(result.elements[2].toBoolean(), equals(true)); // Same reference
    });

    test('Object.is() with less than 2 arguments', () {
      final code = '''
        [
          Object.is(1),
          Object.is()
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      // Object.is(1) compare 1 to undefined
      expect(result.elements[0].toBoolean(), equals(false));
      // Object.is() compare undefined to undefined
      expect(result.elements[1].toBoolean(), equals(true));
    });
  });

  group('Object methods Combined Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Using Object.entries() and Object.values() together', () {
      final code = '''
        var obj = {x: 10, y: 20, z: 30};
        var entries = Object.entries(obj);
        var values = Object.values(obj);
        var keys = Object.keys(obj);
        
        [entries.length, values.length, keys.length]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(3));
      expect(result.elements[1].toNumber(), equals(3));
      expect(result.elements[2].toNumber(), equals(3));
    });

    test('Converting Object.entries() back to object', () {
      final code = '''
        var original = {a: 1, b: 2};
        var entries = Object.entries(original);
        
        // Reconstruire l'objet manuellement
        var reconstructed = {};
        for (var i = 0; i < entries.length; i++) {
          var entry = entries[i];
          reconstructed[entry[0]] = entry[1];
        }
        
        [reconstructed.a, reconstructed.b]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(2));
    });

    test('Object.is() vs === comparison', () {
      final code = '''
        var tests = [];
        
        // Cases where Object.is and === give the same result
        tests.push(Object.is(1, 1) === (1 === 1));
        tests.push(Object.is('a', 'a') === ('a' === 'a'));
        
        // Cases where they differ
        var nan = 0 / 0;
        tests.push(Object.is(nan, nan) === (nan === nan));
        tests.push(Object.is(0, -0) === (0 === -0));
        
        tests
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(
        result.elements[0].toBoolean(),
        equals(true),
      ); // Same for regular values
      expect(result.elements[1].toBoolean(), equals(true)); // Same for strings
      expect(
        result.elements[2].toBoolean(),
        equals(false),
      ); // Different for NaN
      expect(
        result.elements[3].toBoolean(),
        equals(false),
      ); // Different for +0/-0
    });

    test('Iterating over Object.entries()', () {
      final code = '''
        var obj = {name: 'Alice', age: 30, city: 'Paris'};
        var result = [];
        var entries = Object.entries(obj);
        
        for (var i = 0; i < entries.length; i++) {
          var key = entries[i][0];
          var value = entries[i][1];
          result.push(key + ': ' + value);
        }
        
        result
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(3));
      expect(result.elements[0].toString(), contains('name'));
      expect(result.elements[0].toString(), contains('Alice'));
    });

    test('Object.values() with nested objects', () {
      final code = '''
        var obj = {
          person1: {name: 'Alice'},
          person2: {name: 'Bob'}
        };
        var values = Object.values(obj);
        [values.length, values[0].name, values[1].name]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(2));
      expect(result.elements[1].toString(), equals('Alice'));
      expect(result.elements[2].toString(), equals('Bob'));
    });
  });
}
