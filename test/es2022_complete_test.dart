import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

/// ES2022 (ES13) Complete Features Test Suite
///
/// Tests for all ES2022 features:
/// 1. String.prototype.at() - NEW
/// 2. Array.prototype.at() - EXISTING (verify works)
/// 3. Object.hasOwn() - EXISTING (verify works)
/// 4. Error.cause - NEW
/// 5. RegExp Match Indices (/d flag) - NEW
/// 6. Class Static Initialization Blocks - EXISTING (verify works)
/// 7. Private Methods & Fields - EXISTING (already tested in separate file)
void main() {
  group('ES2022 Complete Features', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    // ========================================
    // 1. String.prototype.at() - ES2022
    // ========================================
    group('String.prototype.at()', () {
      test('positive index', () {
        final result = interpreter.eval('"hello".at(0)');
        expect(result.toString(), 'h');
      });

      test('positive index middle', () {
        final result = interpreter.eval('"hello".at(2)');
        expect(result.toString(), 'l');
      });

      test('negative index (last character)', () {
        final result = interpreter.eval('"hello".at(-1)');
        expect(result.toString(), 'o');
      });

      test('negative index (second to last)', () {
        final result = interpreter.eval('"hello".at(-2)');
        expect(result.toString(), 'l');
      });

      test('negative index (full negative)', () {
        final result = interpreter.eval('"hello".at(-5)');
        expect(result.toString(), 'h');
      });

      test('out of bounds positive returns undefined', () {
        final result = interpreter.eval('"hello".at(10)');
        expect(result.isUndefined, isTrue);
      });

      test('out of bounds negative returns undefined', () {
        final result = interpreter.eval('"hello".at(-10)');
        expect(result.isUndefined, isTrue);
      });

      test('empty string returns undefined', () {
        final result = interpreter.eval('"".at(0)');
        expect(result.isUndefined, isTrue);
      });

      test('with unicode characters', () {
        final result = interpreter.eval('"🎉hello".at(0)');
        // Unicode character might take 2 positions
        expect(result.toString().isNotEmpty, isTrue);
      });

      test('last character of long string', () {
        final result = interpreter.eval('"abcdefghijk".at(-1)');
        expect(result.toString(), 'k');
      });
    });

    // ========================================
    // 2. Array.prototype.at() - Verify existing
    // ========================================
    group('Array.prototype.at() - Verification', () {
      test('positive index', () {
        final result = interpreter.eval('[1, 2, 3].at(0)');
        expect(result.toNumber(), 1);
      });

      test('negative index', () {
        final result = interpreter.eval('[1, 2, 3].at(-1)');
        expect(result.toNumber(), 3);
      });

      test('negative index (second to last)', () {
        final result = interpreter.eval('[10, 20, 30, 40].at(-2)');
        expect(result.toNumber(), 30);
      });

      test('out of bounds returns undefined', () {
        final result = interpreter.eval('[1, 2, 3].at(10)');
        expect(result.isUndefined, isTrue);
      });
    });

    // ========================================
    // 3. Object.hasOwn() - Verify existing
    // ========================================
    group('Object.hasOwn() - Verification', () {
      test('has own property', () {
        final result = interpreter.eval('''
          const obj = { a: 1, b: 2 };
          Object.hasOwn(obj, 'a')
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('does not have property', () {
        final result = interpreter.eval('''
          const obj = { a: 1 };
          Object.hasOwn(obj, 'b')
        ''');
        expect(result.toBoolean(), isFalse);
      });

      test('inherited property returns false', () {
        final result = interpreter.eval('''
          const obj = Object.create({ inherited: true });
          obj.own = true;
          Object.hasOwn(obj, 'inherited')
        ''');
        expect(result.toBoolean(), isFalse);
      });

      test('safer than hasOwnProperty', () {
        final result = interpreter.eval('''
          const obj = { hasOwnProperty: 'not a function' };
          obj.a = 1;
          Object.hasOwn(obj, 'a')
        ''');
        expect(result.toBoolean(), isTrue);
      });
    });

    // ========================================
    // 4. Error.cause - ES2022
    // ========================================
    group('Error.cause', () {
      test('Error with cause', () {
        final result = interpreter.eval('''
          const original = new Error('Original error');
          const wrapped = new Error('Wrapped error', { cause: original });
          wrapped.cause.message
        ''');
        expect(result.toString(), 'Original error');
      });

      test('TypeError with cause', () {
        final result = interpreter.eval('''
          const cause = new Error('Cause');
          const err = new TypeError('Type error', { cause: cause });
          err.cause.message
        ''');
        expect(result.toString(), 'Cause');
      });

      test('ReferenceError with cause', () {
        final result = interpreter.eval('''
          const cause = new Error('Not found');
          const err = new ReferenceError('Reference error', { cause: cause });
          err.cause.message
        ''');
        expect(result.toString(), 'Not found');
      });

      test('SyntaxError with cause', () {
        final result = interpreter.eval('''
          const cause = new Error('Parse failed');
          const err = new SyntaxError('Syntax error', { cause: cause });
          err.cause.message
        ''');
        expect(result.toString(), 'Parse failed');
      });

      test('cause can be any value', () {
        final result = interpreter.eval('''
          const err = new Error('Error', { cause: 'string cause' });
          err.cause
        ''');
        expect(result.toString(), 'string cause');
      });

      test('cause can be a number', () {
        final result = interpreter.eval('''
          const err = new Error('Error', { cause: 42 });
          err.cause
        ''');
        expect(result.toNumber(), 42);
      });

      test('cause can be an object', () {
        final result = interpreter.eval('''
          const cause = { code: 404, message: 'Not found' };
          const err = new Error('Error', { cause: cause });
          err.cause.code
        ''');
        expect(result.toNumber(), 404);
      });

      test('error without cause has no cause property', () {
        final result = interpreter.eval('''
          const err = new Error('Error');
          typeof err.cause
        ''');
        expect(result.toString(), 'undefined');
      });

      test('chained errors', () {
        final result = interpreter.eval('''
          const root = new Error('Root cause');
          const middle = new Error('Middle error', { cause: root });
          const top = new Error('Top error', { cause: middle });
          top.cause.cause.message
        ''');
        expect(result.toString(), 'Root cause');
      });

      test('error chain depth 3', () {
        final result = interpreter.eval('''
          const e1 = new Error('Level 1');
          const e2 = new TypeError('Level 2', { cause: e1 });
          const e3 = new ReferenceError('Level 3', { cause: e2 });
          e3.cause.name + '|' + e3.cause.cause.message
        ''');
        expect(result.toString(), 'TypeError|Level 1');
      });
    });

    // ========================================
    // 5. RegExp Match Indices (/d flag) - ES2022
    // ========================================
    group('RegExp Match Indices (/d flag)', () {
      test('hasIndices property is true with /d flag', () {
        final result = interpreter.eval('/abc/d.hasIndices');
        expect(result.toBoolean(), isTrue);
      });

      test('hasIndices property is false without /d flag', () {
        final result = interpreter.eval('/abc/.hasIndices');
        expect(result.toBoolean(), isFalse);
      });

      test('match result has indices property with /d', () {
        final result = interpreter.eval('''
          const match = /abc/d.exec('xyzabcdef');
          typeof match.indices
        ''');
        expect(result.toString(), 'object');
      });

      test('indices[0] contains match start and end', () {
        final result = interpreter.eval('''
          const match = /abc/d.exec('xyzabcdef');
          match.indices[0][0] + ',' + match.indices[0][1]
        ''');
        expect(result.toString(), '3,6');
      });

      test('indices for captured group', () {
        final result = interpreter.eval('''
          const match = /a(bc)/d.exec('xyzabcdef');
          match.indices[1][0] + ',' + match.indices[1][1]
        ''');
        expect(result.toString(), '4,6');
      });

      test('indices for multiple groups', () {
        final result = interpreter.eval('''
          const match = /(a)(b)(c)/d.exec('xyzabcdef');
          const i1 = match.indices[1][0] + ',' + match.indices[1][1];
          const i2 = match.indices[2][0] + ',' + match.indices[2][1];
          const i3 = match.indices[3][0] + ',' + match.indices[3][1];
          i1 + '|' + i2 + '|' + i3
        ''');
        expect(result.toString(), '3,4|4,5|5,6');
      });

      test('without /d flag, indices is undefined', () {
        final result = interpreter.eval('''
          const match = /abc/.exec('xyzabcdef');
          typeof match.indices
        ''');
        expect(result.toString(), 'undefined');
      });

      test('indices with global flag', () {
        final result = interpreter.eval('''
          const regex = /a/dg;
          const match = regex.exec('abcabc');
          match.indices[0][0] + ',' + match.indices[0][1]
        ''');
        expect(result.toString(), '0,1');
      });

      test('indices for non-matching group is undefined', () {
        final result = interpreter.eval('''
          const match = /(a)|(b)/d.exec('a');
          typeof match.indices[2]
        ''');
        expect(result.toString(), 'undefined');
      });

      test('match at beginning of string', () {
        final result = interpreter.eval('''
          const match = /abc/d.exec('abcdef');
          match.indices[0][0] + ',' + match.indices[0][1]
        ''');
        expect(result.toString(), '0,3');
      });

      test('match at end of string', () {
        final result = interpreter.eval('''
          const match = /def/d.exec('abcdef');
          match.indices[0][0] + ',' + match.indices[0][1]
        ''');
        expect(result.toString(), '3,6');
      });
    });

    // ========================================
    // 6. Class Static Initialization Blocks - Verify existing
    // ========================================
    group('Class Static Initialization Blocks - Verification', () {
      test('basic static block', () {
        final result = interpreter.eval('''
          class MyClass {
            static value;
            
            static {
              this.value = 42;
            }
          }
          
          MyClass.value
        ''');
        expect(result.toNumber(), 42);
      });

      test('static block with computation', () {
        final result = interpreter.eval('''
          class Calculator {
            static result;
            
            static {
              let sum = 0;
              for (let i = 1; i <= 5; i++) {
                sum += i;
              }
              this.result = sum;
            }
          }
          
          Calculator.result
        ''');
        expect(result.toNumber(), 15);
      });

      test('multiple static blocks', () {
        final result = interpreter.eval('''
          class Multi {
            static a;
            static b;
            
            static {
              this.a = 10;
            }
            
            static {
              this.b = this.a * 2;
            }
          }
          
          Multi.a + Multi.b
        ''');
        expect(result.toNumber(), 30);
      });

      test('static block with private static field', () {
        final result = interpreter.eval('''
          class Private {
            static #secret = 0;
            static value;
            
            static {
              this.#secret = 100;
              this.value = this.#secret + 50;
            }
          }
          
          Private.value
        ''');
        expect(result.toNumber(), 150);
      });

      test('static block runs before constructor', () {
        final result = interpreter.eval('''
          class Order {
            static initialized = false;
            
            static {
              this.initialized = true;
            }
            
            constructor() {
              this.wasInitialized = Order.initialized;
            }
          }
          
          const obj = new Order();
          obj.wasInitialized
        ''');
        expect(result.toBoolean(), isTrue);
      });
    });

    // ========================================
    // 7. Integration Tests - Multiple ES2022 features together
    // ========================================
    group('ES2022 Integration', () {
      test('String.at() with Array.at()', () {
        final result = interpreter.eval('''
          const arr = ['hello', 'world'];
          const str = arr.at(-1);
          str.at(-1)
        ''');
        expect(result.toString(), 'd');
      });

      test('Error.cause with Object.hasOwn()', () {
        final result = interpreter.eval('''
          const cause = new Error('Cause');
          const err = new Error('Error', { cause: cause });
          Object.hasOwn(err, 'cause')
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('RegExp /d with String.at()', () {
        final result = interpreter.eval('''
          const match = /test/d.exec('abctestxyz');
          const start = match.indices[0][0];
          'abctestxyz'.at(start)
        ''');
        expect(result.toString(), 't');
      });

      test('Static block with Array.at()', () {
        final result = interpreter.eval('''
          class ArrayProcessor {
            static values = [10, 20, 30, 40, 50];
            static last;
            
            static {
              this.last = this.values.at(-1);
            }
          }
          
          ArrayProcessor.last
        ''');
        expect(result.toNumber(), 50);
      });

      test('Complete ES2022 feature combination', () {
        final result = interpreter.eval('''
          class DataProcessor {
            static data = ['a', 'b', 'c', 'd', 'e'];
            static pattern = /[bd]/dg;
            static result;
            
            static {
              const matches = [];
              let match;
              while ((match = this.pattern.exec(this.data.join(''))) !== null) {
                const index = match.indices[0][0];
                const char = this.data.join('').at(index);
                matches.push(char);
              }
              this.result = matches.join(',');
            }
          }
          
          DataProcessor.result
        ''');
        expect(result.toString(), 'b,d');
      });

      test('Error chain with RegExp indices', () {
        final result = interpreter.eval('''
          try {
            const pattern = /error/d;
            const text = 'no match here';
            const match = pattern.exec(text);
            if (!match) {
              const parseError = new Error('Parse failed');
              throw new TypeError('Match failed', { cause: parseError });
            }
          } catch (e) {
            Object.hasOwn(e, 'cause') && e.cause.message
          }
        ''');
        expect(result.toString(), 'Parse failed');
      });
    });

    // ========================================
    // 8. Edge Cases and Error Handling
    // ========================================
    group('ES2022 Edge Cases', () {
      test('String.at() with NaN index', () {
        final result = interpreter.eval('"hello".at(NaN)');
        expect(result.isUndefined, isTrue);
      });

      test('Array.at() with non-integer index', () {
        final result = interpreter.eval('[1, 2, 3].at(1.7)');
        expect(result.toNumber(), 2);
      });

      test('Object.hasOwn() with non-object', () {
        final result = interpreter.eval('Object.hasOwn(null, "prop")');
        expect(result.toBoolean(), isFalse);
      });

      test('Error.cause with null', () {
        final result = interpreter.eval('''
          const err = new Error('Error', { cause: null });
          err.cause
        ''');
        expect(result.isNull, isTrue);
      });

      test('RegExp /d with no match', () {
        final result = interpreter.eval('''
          const match = /xyz/d.exec('abc');
          match
        ''');
        expect(result.isNull, isTrue);
      });

      test('Static block with exception', () {
        expect(
          () => interpreter.eval('''
            class BadInit {
              static {
                throw new Error('Init failed');
              }
            }
          '''),
          throwsA(isA<Error>()),
        );
      });
    });
  });
}
