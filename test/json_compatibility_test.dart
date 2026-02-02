library;

import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('JSON Compatibility Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('JSON.stringify() edge cases', () {
      test('should handle NaN and Infinity as null', () {
        expect(interpreter.eval('JSON.stringify(NaN)').toString(), 'null');
        expect(interpreter.eval('JSON.stringify(Infinity)').toString(), 'null');
        expect(
          interpreter.eval('JSON.stringify(-Infinity)').toString(),
          'null',
        );
      });

      test('should omit function properties', () {
        final result = interpreter.eval('''
          JSON.stringify({
            a: 1,
            b: function() { return 2; },
            c: 3
          });
        ''');
        final str = result.toString();
        // ES2019: Integers formatted without .0
        expect(str, contains('"a":1'));
        expect(str, contains('"c":3'));
        expect(str, isNot(contains('"b"')));
      });

      test('should handle Date objects as strings', () {
        final result = interpreter.eval('''
          var date = new Date('2023-01-01T12:00:00.000Z');
          JSON.stringify(date);
        ''');
        expect(result.toString(), contains('2023-01-01'));
      });

      test('should handle arrays with gaps', () {
        final result = interpreter.eval('''
          var arr = [1, , 3];
          JSON.stringify(arr);
        ''');
        // ES2019: Integers formatted without .0
        expect(result.toString(), '[1,null,3]');
      });
    });

    group('JSON.parse() edge cases', () {
      test('should handle whitespace in JSON', () {
        final result = interpreter.eval('''
          JSON.parse('  { "name" : "John" }  ');
        ''');
        expect(result, isA<JSObject>());

        final name = interpreter.eval('''
          JSON.parse('  { "name" : "John" }  ').name;
        ''');
        expect(name.toString(), 'John');
      });

      test('should handle unicode sequences', () {
        final result = interpreter.eval(r'''
          JSON.parse('{"unicode": "\u0048\u0065\u006c\u006c\u006f"}');
        ''');
        expect(result, isA<JSObject>());

        final unicode = interpreter.eval(r'''
          JSON.parse('{"unicode": "\u0048\u0065\u006c\u006c\u006f"}').unicode;
        ''');
        expect(unicode.toString(), 'Hello');
      });
    });

    group('JSON standards compliance', () {
      test('should stringify and parse numbers correctly', () {
        final testNumbers = [
          '0',
          '42',
          '-17',
          '3.14159',
          '1.23e-4',
          '1.79e+308',
        ];

        for (final numStr in testNumbers) {
          final result = interpreter.eval('''
            var original = $numStr;
            var stringified = JSON.stringify(original);
            var parsed = JSON.parse(stringified);
            original === parsed;
          ''');
          expect(
            result.toBoolean(),
            isTrue,
            reason: 'Number $numStr failed roundtrip test',
          );
        }
      });

      test('should handle nested structures deeply', () {
        final result = interpreter.eval('''
          var deep = {
            level1: {
              level2: {
                level3: {
                  level4: {
                    value: "deep"
                  }
                }
              }
            }
          };
          var restored = JSON.parse(JSON.stringify(deep));
          restored.level1.level2.level3.level4.value;
        ''');
        expect(result.toString(), 'deep');
      });

      test('should maintain property order (when possible)', () {
        final result = interpreter.eval('''
          var obj = {c: 3, a: 1, b: 2};
          JSON.stringify(obj);
        ''');
        // Note: Property order is not guaranteed in older JS engines
        // but modern engines tend to preserve it
        final str = result.toString();
        // ES2019: Integers formatted without .0
        expect(str, contains('"c":3'));
        expect(str, contains('"a":1'));
        expect(str, contains('"b":2'));
      });
    });

    group('Error handling', () {
      test('should throw SyntaxError on malformed JSON', () {
        final malformedCases = [
          '{name: "John"}', // unquoted keys
          '{"name": }', // missing value
          '[1, 2, 3,]', // trailing comma
          'undefined', // undefined literal
          '{"a": 1 "b": 2}', // missing comma
        ];

        for (final malformed in malformedCases) {
          expect(
            () => interpreter.eval('JSON.parse(\'$malformed\')'),
            throwsA(isA<JSError>()),
            reason: 'Should throw error for: $malformed',
          );
        }
      });

      test('should handle empty string gracefully', () {
        expect(
          () => interpreter.eval('JSON.parse("")'),
          throwsA(isA<JSError>()),
        );
      });
    });

    group('Performance and memory', () {
      test('should handle moderately large objects', () {
        final result = interpreter.eval('''
          var large = {};
          for (var i = 0; i < 100; i++) {
            large['key' + i] = 'value' + i;
          }
          var json = JSON.stringify(large);
          var parsed = JSON.parse(json);
          parsed.key50;
        ''');
        expect(result.toString(), 'value50');
      });

      test('should handle arrays with many elements', () {
        final result = interpreter.eval('''
          var arr = [];
          for (var i = 0; i < 100; i++) {
            arr.push(i);
          }
          var json = JSON.stringify(arr);
          var parsed = JSON.parse(json);
          parsed.length;
        ''');
        expect(result.toNumber(), 100.0);
      });
    });
  });
}
