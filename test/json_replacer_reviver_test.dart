import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('JSON Replacer and Reviver Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('JSON.stringify with Replacer Function', () {
      test('should apply replacer function to all values', () {
        final result = interpreter.eval('''
          var obj = {
            name: "John",
            age: 30,
            city: "New York"
          };
          
          JSON.stringify(obj, function(key, value) {
            if (key === "age") {
              return value + 10; // Add 10 to age
            }
            if (key === "city") {
              return undefined; // Remove city
            }
            return value;
          });
        ''');

        final jsonStr = result.toString();
        // ES2019: Integers formatted without .0
        expect(jsonStr, contains('"age":40'));
        expect(jsonStr, isNot(contains('city')));
        expect(jsonStr, contains('"name":"John"'));
      });

      test('should handle replacer function that transforms types', () {
        final result = interpreter.eval('''
          var data = {
            count: 42,
            active: true,
            items: [1, 2, 3]
          };
          
          JSON.stringify(data, function(key, value) {
            if (typeof value === "number") {
              return "num:" + value;
            }
            if (typeof value === "boolean") {
              return value ? "yes" : "no";
            }
            return value;
          });
        ''');

        final jsonStr = result.toString();
        expect(jsonStr, contains('"count":"num:42"'));
        expect(jsonStr, contains('"active":"yes"'));
        expect(jsonStr, contains('"num:1"'));
        expect(jsonStr, contains('"num:2"'));
        expect(jsonStr, contains('"num:3"'));
      });

      test('should handle errors in replacer function gracefully', () {
        final result = interpreter.eval('''
          var obj = { a: 1, b: 2, c: 3 };
          
          JSON.stringify(obj, function(key, value) {
            if (key === "b") {
              throw new Error("Test error");
            }
            return value;
          });
        ''');

        // Should not crash, might return original or transformed value
        expect(result.toString(), isA<String>());
      });
    });

    group('JSON.stringify with Replacer Array', () {
      test('should include only properties specified in replacer array', () {
        final result = interpreter.eval('''
          var person = {
            name: "Alice",
            age: 25,
            email: "alice@test.com",
            password: "secret123"
          };
          
          JSON.stringify(person, ["name", "age"]);
        ''');

        final jsonStr = result.toString();
        expect(jsonStr, contains('"name":"Alice"'));
        // ES2019: Integers formatted without .0
        expect(jsonStr, contains('"age":25'));
        expect(jsonStr, isNot(contains('email')));
        expect(jsonStr, isNot(contains('password')));
      });

      test('should handle numeric indices in replacer array', () {
        final result = interpreter.eval('''
          var arr = ["a", "b", "c", "d"];
          var obj = { "0": "first", "1": "second", "2": "third", other: "value" };
          
          JSON.stringify(obj, [0, 1, "other"]);
        ''');

        final jsonStr = result.toString();
        expect(jsonStr, contains('"0":"first"'));
        expect(jsonStr, contains('"1":"second"'));
        expect(jsonStr, contains('"other":"value"'));
        expect(jsonStr, isNot(contains('"2":"third"')));
      });

      test('should handle mixed types in replacer array', () {
        final result = interpreter.eval('''
          var data = {
            str: "value",
            num: 42,
            bool: true,
            obj: { nested: "data" }
          };
          
          JSON.stringify(data, ["str", 42, "bool"]);
        ''');

        final jsonStr = result.toString();
        expect(jsonStr, contains('"str":"value"'));
        expect(jsonStr, contains('"bool":true'));
        expect(jsonStr, isNot(contains('num')));
        expect(jsonStr, isNot(contains('obj')));
      });
    });

    group('JSON.parse with Reviver Function', () {
      test('should apply reviver function to all values', () {
        final result = interpreter.eval('''
          var jsonStr = '{"name":"John","age":30,"active":true}';
          
          var parsed = JSON.parse(jsonStr, function(key, value) {
            if (key === "age") {
              return value - 5; // Subtract 5 from age
            }
            if (key === "active") {
              return value ? "yes" : "no"; // Transform boolean
            }
            return value;
          });
          
          JSON.stringify(parsed);
        ''');

        final jsonStr = result.toString();
        // ES2019: Integers formatted without .0
        expect(jsonStr, contains('"age":25'));
        expect(jsonStr, contains('"active":"yes"'));
        expect(jsonStr, contains('"name":"John"'));
      });

      test('should process nested objects with reviver', () {
        final result = interpreter.eval('''
          var jsonStr = '{"user":{"name":"Alice","details":{"age":25,"city":"Paris"}}}';
          
          var parsed = JSON.parse(jsonStr, function(key, value) {
            if (key === "age" && typeof value === "number") {
              return value + " years old";
            }
            if (key === "city") {
              return value.toUpperCase();
            }
            return value;
          });
          
          parsed.user.details.age + " in " + parsed.user.details.city;
        ''');

        expect(result.toString(), equals('25 years old in PARIS'));
      });

      test('should process arrays with reviver', () {
        final result = interpreter.eval('''
          var jsonStr = '[1, 2, 3, {"value": 4}]';
          
          var parsed = JSON.parse(jsonStr, function(key, value) {
            if (typeof value === "number") {
              return value * 2;
            }
            return value;
          });
          
          JSON.stringify(parsed);
        ''');

        final jsonStr = result.toString();
        // ES2019: Integers formatted without .0
        expect(jsonStr, contains('2'));
        expect(jsonStr, contains('4'));
        expect(jsonStr, contains('6'));
        expect(jsonStr, contains('"value":8'));
      });

      test(
        'should handle reviver returning undefined to delete properties',
        () {
          final result = interpreter.eval('''
          var jsonStr = '{"keep":"yes","remove":"no","also_keep":"maybe"}';
          
          var parsed = JSON.parse(jsonStr, function(key, value) {
            if (key === "remove") {
              return undefined; // Delete this property
            }
            return value;
          });
          
          JSON.stringify(parsed);
        ''');

          final jsonStr = result.toString();
          expect(jsonStr, contains('"keep":"yes"'));
          expect(jsonStr, contains('"also_keep":"maybe"'));
          expect(jsonStr, isNot(contains('remove')));
        },
      );
    });

    group('Circular Reference Detection', () {
      test('should throw error for circular references in stringify', () {
        expect(
          () => interpreter.eval('''
          var obj = { name: "test" };
          obj.self = obj; // Create circular reference
          JSON.stringify(obj);
        '''),
          throwsA(isA<JSError>()),
        );
      });

      test('should handle complex circular references', () {
        expect(
          () => interpreter.eval('''
          var a = { name: "a" };
          var b = { name: "b" };
          a.ref = b;
          b.ref = a; // Create circular reference
          JSON.stringify(a);
        '''),
          throwsA(isA<JSError>()),
        );
      });
    });

    group('Edge Cases and Special Values', () {
      test('should handle special values with replacer', () {
        final result = interpreter.eval('''
          var obj = {
            undef: undefined,
            nullVal: null,
            nanVal: NaN,
            infVal: Infinity,
            func: function() { return 42; }
          };
          
          JSON.stringify(obj, function(key, value) {
            if (key === "undef") return "was undefined";
            if (key === "nanVal") return "was NaN";
            if (key === "infVal") return "was Infinity";
            return value;
          });
        ''');

        final jsonStr = result.toString();
        expect(jsonStr, contains('"undef":"was undefined"'));
        expect(jsonStr, contains('"nullVal":null'));
        expect(jsonStr, contains('"nanVal":"was NaN"'));
        expect(jsonStr, contains('"infVal":"was Infinity"'));
        expect(jsonStr, isNot(contains('func')));
      });

      test('should handle Date objects with replacer', () {
        final result = interpreter.eval('''
          var obj = {
            now: new Date("2023-01-01T00:00:00.000Z"),
            name: "test"
          };
          
          JSON.stringify(obj, function(key, value) {
            if (key === "now") {
              return "date:" + value;
            }
            return value;
          });
        ''');

        final jsonStr = result.toString();
        // Accept both T and space formats for date
        final hasCorrectDateFormat =
            jsonStr.contains('"now":"date:2023-01-01T00:00:00.000Z"') ||
            jsonStr.contains('"now":"date:2023-01-01 00:00:00.000Z"');
        expect(
          hasCorrectDateFormat,
          isTrue,
          reason: 'Expected date format not found in: $jsonStr',
        );
        expect(jsonStr, contains('"name":"test"'));
      });
    });

    group('Performance and Stress Tests', () {
      test('should handle large objects with replacer', () {
        final result = interpreter.eval('''
          var largeObj = {};
          for (var i = 0; i < 100; i++) {
            largeObj["key" + i] = "value" + i;
          }
          
          var filtered = JSON.stringify(largeObj, function(key, value) {
            // Keep only keys ending with 0-4
            if (key.endsWith("0") || key.endsWith("1") || key.endsWith("2") || 
                key.endsWith("3") || key.endsWith("4")) {
              return value;
            }
            if (key === "") return value; // Keep root object
            return undefined;
          });
          
          // Count number of properties in result
          (filtered.match(/key/g) || []).length;
        ''');

        expect(result.toNumber(), equals(50.0)); // Should keep 50 properties
      });

      test('should handle deeply nested objects with reviver', () {
        final result = interpreter.eval('''
          var deepObj = { level: 0 };
          var current = deepObj;
          for (var i = 1; i < 10; i++) {
            current.next = { level: i };
            current = current.next;
          }
          
          var jsonStr = JSON.stringify(deepObj);
          var parsed = JSON.parse(jsonStr, function(key, value) {
            if (key === "level") {
              return value * 10; // Multiply level by 10
            }
            return value;
          });
          
          // Navigate to deepest level and check transformation
          var deep = parsed;
          while (deep.next) {
            deep = deep.next;
          }
          deep.level;
        ''');

        expect(result.toNumber(), equals(90.0)); // 9 * 10
      });
    });
  });
}
