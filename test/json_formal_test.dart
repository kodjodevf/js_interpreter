/// Tests formels Dart pour l'objet JSON
/// Tests unitaires complets pour JSON.parse() et JSON.stringify()
library;

import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('JSON Object Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('JSON.stringify()', () {
      test('should stringify primitive values', () {
        // ES2019: Integers are formatted without .0
        expect(interpreter.eval('JSON.stringify(42)').toString(), '42');
        expect(
          interpreter.eval('JSON.stringify("hello")').toString(),
          '"hello"',
        );
        expect(interpreter.eval('JSON.stringify(true)').toString(), 'true');
        expect(interpreter.eval('JSON.stringify(false)').toString(), 'false');
        expect(interpreter.eval('JSON.stringify(null)').toString(), 'null');
      });

      test('should stringify undefined as undefined', () {
        // JSON.stringify(undefined) should return undefined, not a string
        final result = interpreter.eval('JSON.stringify(undefined)');
        expect(result.isUndefined, isTrue);
      });

      test('should stringify simple objects', () {
        final result = interpreter.eval(
          'JSON.stringify({name: "John", age: 30})',
        );
        final str = result.toString();
        expect(str, contains('"name":"John"'));
        // ES2019: Integers are formatted without .0
        expect(str, contains('"age":30'));
      });

      test('should stringify arrays', () {
        // ES2019: Integers are formatted without .0
        expect(
          interpreter.eval('JSON.stringify([1, 2, 3])').toString(),
          '[1,2,3]',
        );
      });

      test('should stringify nested objects', () {
        final result = interpreter.eval('''
          JSON.stringify({
            person: {
              name: "John",
              details: { age: 30, city: "NYC" }
            }
          })
        ''');
        final str = result.toString();
        expect(str, contains('"person"'));
        expect(str, contains('"details"'));
        // ES2019: Integers are formatted without .0
        expect(str, contains('"age":30'));
      });

      test('should stringify with spacing', () {
        final result = interpreter.eval(
          'JSON.stringify({a: 1, b: 2}, null, 2)',
        );
        final str = result.toString();
        expect(str, contains('{\n  '));
        expect(str, contains(',\n  '));
      });

      test('should handle circular references gracefully', () {
        // Note: This should not cause infinite recursion but should throw TypeError
        expect(() {
          interpreter.eval('''
            var obj = {a: 1};
            obj.self = obj;
            JSON.stringify(obj);
          ''');
        }, throwsA(isA<JSError>()));
      });
    });

    group('JSON.parse()', () {
      test('should parse primitive values', () {
        expect(interpreter.eval('JSON.parse("42")').toNumber(), 42.0);
        expect(interpreter.eval('JSON.parse(\'"hello"\')').toString(), 'hello');
        expect(interpreter.eval('JSON.parse("true")').toBoolean(), isTrue);
        expect(interpreter.eval('JSON.parse("false")').toBoolean(), isFalse);
        expect(interpreter.eval('JSON.parse("null")').isNull, isTrue);
      });

      test('should parse simple objects', () {
        final result = interpreter.eval(
          'JSON.parse(\'{"name": "John", "age": 30}\')',
        );
        expect(result, isA<JSObject>());

        final name = interpreter.eval('''
          var obj = JSON.parse('{"name": "John", "age": 30}');
          obj.name;
        ''');
        expect(name.toString(), 'John');

        final age = interpreter.eval('''
          var obj = JSON.parse('{"name": "John", "age": 30}');
          obj.age;
        ''');
        expect(age.toNumber(), 30.0);
      });

      test('should parse arrays', () {
        final result = interpreter.eval('JSON.parse("[1, 2, 3]")');
        expect(result, isA<JSArray>());

        final length = interpreter.eval('JSON.parse("[1, 2, 3]").length');
        expect(length.toNumber(), 3.0);

        final firstElement = interpreter.eval('''
          var arr = JSON.parse("[1, 2, 3]");
          arr[0];
        ''');
        expect(firstElement.toNumber(), 1.0);
      });

      test('should parse nested structures', () {
        final result = interpreter.eval('''
          var parsed = JSON.parse('{"person": {"name": "John", "age": 30}}');
          parsed.person.name;
        ''');
        expect(result.toString(), 'John');
      });

      test('should handle invalid JSON gracefully', () {
        expect(() {
          interpreter.eval('JSON.parse("{invalid json}")');
        }, throwsA(isA<JSError>()));

        expect(() {
          interpreter.eval('JSON.parse("")');
        }, throwsA(isA<JSError>()));
      });
    });

    group('JSON roundtrip tests', () {
      test('should maintain data integrity in roundtrip', () {
        final result = interpreter.eval('''
          var original = {
            name: "John",
            age: 30,
            active: true,
            hobbies: ["reading", "coding"],
            address: null
          };
          var json = JSON.stringify(original);
          var restored = JSON.parse(json);
          restored.name + ":" + restored.age + ":" + restored.active + ":" + restored.hobbies.length;
        ''');
        expect(result.toString(), 'John:30:true:2');
      });

      test('should preserve types after roundtrip', () {
        final result = interpreter.eval('''
          var original = {str: "hello", num: 42, bool: true};
          var restored = JSON.parse(JSON.stringify(original));
          typeof restored.str + "," + typeof restored.num + "," + typeof restored.bool;
        ''');
        expect(result.toString(), 'string,number,boolean');
      });

      test('should handle complex nested structures', () {
        final result = interpreter.eval('''
          var complex = {
            users: [
              {name: "John", scores: [85, 90, 78]},
              {name: "Jane", scores: [92, 88, 95]}
            ],
            meta: {
              count: 2,
              average: 86.5
            }
          };
          var restored = JSON.parse(JSON.stringify(complex));
          restored.users[1].scores[2] + restored.meta.average;
        ''');
        expect(result.toNumber(), 181.5); // 95 + 86.5
      });
    });

    group('JSON edge cases', () {
      test('should ignore undefined properties in objects', () {
        final result = interpreter.eval('''
          JSON.stringify({a: 1, b: undefined, c: 3});
        ''');
        final str = result.toString();
        // ES2019: Integers are formatted without .0
        expect(str, contains('"a":1'));
        expect(str, contains('"c":3'));
        expect(str, isNot(contains('"b"')));
      });

      test('should handle empty objects and arrays', () {
        expect(interpreter.eval('JSON.stringify({})').toString(), '{}');
        expect(interpreter.eval('JSON.stringify([])').toString(), '[]');

        final emptyObj = interpreter.eval('JSON.parse("{}")');
        expect(emptyObj, isA<JSObject>());

        final emptyArr = interpreter.eval('JSON.parse("[]")');
        expect(emptyArr, isA<JSArray>());
        expect(interpreter.eval('JSON.parse("[]").length').toNumber(), 0.0);
      });

      test('should handle mixed data types in arrays', () {
        final result = interpreter.eval('''
          var mixed = [1, "hello", true, null, {name: "test"}];
          var restored = JSON.parse(JSON.stringify(mixed));
          typeof restored[0] + "," + typeof restored[1] + "," + typeof restored[4];
        ''');
        expect(result.toString(), 'number,string,object');
      });
    });
  });
}
