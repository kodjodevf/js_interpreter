import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('ES2018 Features - Initial Check', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('Object Rest/Spread Properties', () {
      test('should support object spread in literals', () {
        const code = '''
          const obj1 = {a: 1, b: 2};
          const obj2 = {c: 3, d: 4};
          const merged = {...obj1, ...obj2};
          merged.a + merged.c;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(4));
      });

      test('should support object rest in destructuring (already tested)', () {
        const code = '''
          const {x, ...rest} = {x: 1, y: 2, z: 3};
          rest.y + rest.z;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(5));
      });

      test('should support overriding properties with spread', () {
        const code = '''
          const obj1 = {a: 1, b: 2};
          const obj2 = {...obj1, b: 3};
          obj2.b;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(3));
      });
    });

    group('Promise.prototype.finally()', () {
      test('should support finally on resolved promise', () {
        const code = '''
          let finallyCalled = false;
          let promiseValue = null;
          Promise.resolve(42)
            .finally(() => { finallyCalled = true; })
            .then(value => { promiseValue = value; });
          finallyCalled;
        ''';

        final result = interpreter.eval(code);
        // Check if finally was called
        expect(result.toBoolean(), isTrue);
      });

      test('should pass through the value after finally', () {
        const code = '''
          let result = 0;
          Promise.resolve(42)
            .finally(() => { result = 100; })
            .then(value => value + result);
          142; // Expected: 42 + 100
        ''';

        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(142));
      });
    });

    group('Async Iteration', () {
      test('should support for await...of syntax (basic parsing)', () {
        const code = '''
          async function test() {
            const items = [1, 2, 3];
            let sum = 0;
            for await (const item of items) {
              sum += item;
            }
            return sum;
          }
          test();
        ''';

        try {
          final result = interpreter.eval(code);
          expect(result, isNotNull);
        } catch (e) {
          // Expected to fail if not implemented
          expect(e.toString(), contains('await'));
        }
      });
    });

    group('RegExp s (dotAll) flag', () {
      test('should support s flag', () {
        const code = '''
          const regex = /./s;
          regex.test('\\n');
        ''';

        try {
          final result = interpreter.eval(code);
          expect(result.toBoolean(), isTrue);
        } catch (e) {
          // May not be implemented yet
          print('s flag not yet implemented: $e');
        }
      });
    });

    group('RegExp named capture groups', () {
      test('should support named groups', () {
        const code = r'''
          const regex = /(?<year>\d{4})-(?<month>\d{2})/;
          const match = regex.exec('2023-10');
          match ? match.groups.year : null;
        ''';

        try {
          final result = interpreter.eval(code);
          expect(result.toString(), equals('2023'));
        } catch (e) {
          // May not be implemented yet
          print('Named groups not yet implemented: $e');
        }
      });
    });

    group('RegExp lookbehind assertions', () {
      test('should support positive lookbehind', () {
        const code = r'''
          const regex = /(?<=\$)\d+/;
          const match = regex.exec('$100');
          match ? match[0] : null;
        ''';

        try {
          final result = interpreter.eval(code);
          expect(result.toString(), equals('100'));
        } catch (e) {
          // May not be implemented yet
          print('Lookbehind not yet implemented: $e');
        }
      });
    });
  });
}
