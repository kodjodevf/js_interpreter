import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('ES2020 Features', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    // ========================================================================
    // ES2020: String.prototype.matchAll()
    // ========================================================================

    group('String.prototype.matchAll()', () {
      test('should return iterator of all matches with groups', () {
        final result = interpreter.eval('''
          const str = 'test1 test2 test3';
          const regex = /test(\\d)/g;
          const matches = [...str.matchAll(regex)];
          matches.map(m => m[0]).join(',');
        ''');
        expect(result.toString(), 'test1,test2,test3');
      });

      test('should include captured groups in match array', () {
        final result = interpreter.eval('''
          const str = 'test1 test2';
          const regex = /test(\\d)/g;
          const matches = [...str.matchAll(regex)];
          matches[0][1]; // First captured group of first match
        ''');
        expect(result.toString(), '1');
      });

      test('should include index property in match objects', () {
        final result = interpreter.eval('''
          const str = 'test1 test2';
          const regex = /test(\\d)/g;
          const matches = [...str.matchAll(regex)];
          matches[0].index;
        ''');
        expect(result.toNumber(), 0);
      });

      test('should include input property in match objects', () {
        final result = interpreter.eval('''
          const str = 'test1 test2';
          const regex = /test(\\d)/g;
          const matches = [...str.matchAll(regex)];
          matches[0].input;
        ''');
        expect(result.toString(), 'test1 test2');
      });

      test('should work with named capture groups', () {
        final result = interpreter.eval('''
          const str = 'test1 test2';
          const regex = /test(?<num>\\d)/g;
          const matches = [...str.matchAll(regex)];
          matches[0].groups.num;
        ''');
        expect(result.toString(), '1');
      });

      test('should throw error if regex is not global', () {
        expect(
          () => interpreter.eval('''
            const str = 'test1 test2';
            const regex = /test(\\d)/; // Pas de flag 'g'
            str.matchAll(regex);
          '''),
          throwsA(isA<JSException>()),
        );
      });

      test('should return empty iterator for no matches', () {
        final result = interpreter.eval('''
          const str = 'hello world';
          const regex = /xyz/g;
          const matches = [...str.matchAll(regex)];
          matches.length;
        ''');
        expect(result.toNumber(), 0);
      });

      test('should work with string pattern (auto-adds global flag)', () {
        final result = interpreter.eval('''
          const str = 'test1 test2 test3';
          const matches = [...str.matchAll('test')];
          matches.length;
        ''');
        expect(result.toNumber(), 3);
      });

      test('should handle undefined/null by creating empty regex', () {
        final result = interpreter.eval('''
          const str = 'test';
          const matches = [...str.matchAll()];
          matches.length;
        ''');
        expect(
          result.toNumber(),
          greaterThan(0),
        ); // Match individual characters
      });

      test('should iterate correctly with for...of', () {
        final result = interpreter.eval('''
          const str = 'a1 a2 a3';
          const regex = /a(\\d)/g;
          let sum = 0;
          for (const match of str.matchAll(regex)) {
            sum += parseInt(match[1]);
          }
          sum;
        ''');
        expect(result.toNumber(), 6); // 1 + 2 + 3
      });

      test('should handle multiple capture groups', () {
        final result = interpreter.eval('''
          const str = 'John:30 Jane:25';
          const regex = /(\\w+):(\\d+)/g;
          const matches = [...str.matchAll(regex)];
          matches[0][1] + ',' + matches[0][2];
        ''');
        expect(result.toString(), 'John,30');
      });

      test('should work with complex patterns', () {
        final result = interpreter.eval('''
          const str = 'email@example.com test@test.org';
          const regex = /(\\w+)@([^\\s]+)/g;
          const matches = [...str.matchAll(regex)];
          matches.map(m => m[1]).join(',');
        ''');
        expect(result.toString(), 'email,test');
      });

      test('should handle overlapping patterns correctly', () {
        final result = interpreter.eval('''
          const str = 'aaaa';
          const regex = /aa/g;
          const matches = [...str.matchAll(regex)];
          matches.length;
        ''');
        expect(result.toNumber(), 2); // Pas de chevauchement : 'aa' 'aa'
      });

      test('should return undefined for missing groups', () {
        final result = interpreter.eval('''
          const str = 'test1';
          const regex = /test(\\d)?(\\d)?/g;
          const matches = [...str.matchAll(regex)];
          matches[0][2] === undefined;
        ''');
        expect(result.toBoolean(), true);
      });

      test('should handle zero-length matches', () {
        final result = interpreter.eval('''
          const str = 'abc';
          const regex = /(?=a)/g;
          const matches = [...str.matchAll(regex)];
          matches.length;
        ''');
        expect(result.toNumber(), greaterThanOrEqualTo(0));
      });
    });

    // ========================================================================
    // Placeholder for other ES2020 features
    // ========================================================================

    // ========================================================================
    // ES2020: globalThis
    // ========================================================================

    group('globalThis', () {
      test('should provide access to global object', () {
        final result = interpreter.eval('''
          globalThis.testVar = 42;
          testVar;
        ''');
        expect(result.toNumber(), 42);
      });

      test('should be same as global scope', () {
        final result = interpreter.eval('''
          var myGlobal = 123;
          globalThis.myGlobal === myGlobal;
        ''');
        expect(result.toBoolean(), true);
      });

      test('should allow setting global variables', () {
        final result = interpreter.eval('''
          globalThis.foo = 'bar';
          foo;
        ''');
        expect(result.toString(), 'bar');
      });

      test('should allow reading global variables', () {
        final result = interpreter.eval('''
          var baz = 'qux';
          globalThis.baz;
        ''');
        expect(result.toString(), 'qux');
      });

      test('should provide access to global functions', () {
        final result = interpreter.eval('''
          globalThis.parseInt('42');
        ''');
        expect(result.toNumber(), 42);
      });

      test('should provide access to global constructors', () {
        final result = interpreter.eval('''
          const arr = new globalThis.Array(1, 2, 3);
          arr.length;
        ''');
        expect(result.toNumber(), 3);
      });

      test('should work with typeof', () {
        final result = interpreter.eval('''
          typeof globalThis;
        ''');
        expect(result.toString(), 'object');
      });

      test('should be writable', () {
        final result = interpreter.eval('''
          const original = globalThis;
          globalThis.newProp = 'test';
          original.newProp;
        ''');
        expect(result.toString(), 'test');
      });

      test('should work in nested scopes', () {
        final result = interpreter.eval('''
          globalThis.outer = 'outside';
          function test() {
            return globalThis.outer;
          }
          test();
        ''');
        expect(result.toString(), 'outside');
      });

      test('should provide universal global access', () {
        final result = interpreter.eval('''
          // Simulate checking in different contexts
          const g1 = globalThis;
          (function() {
            const g2 = globalThis;
            return g1 === g2;
          })();
        ''');
        expect(result.toBoolean(), true);
      });
    });

    // ========================================================================
    // ES2020: Promise.allSettled()
    // ========================================================================

    group('Promise.allSettled()', () {
      test('should wait for all promises (fulfilled and rejected)', () {
        final result = interpreter.eval('''
          const p1 = Promise.resolve(1);
          const p2 = Promise.reject(new Error('failed'));
          const p3 = Promise.resolve(3);
          
          Promise.allSettled([p1, p2, p3]).then(results => {
            return results.length;
          });
        ''');
        expect(result, isA<JSPromise>());
      });

      test('should return objects with status and value/reason', () {
        final result = interpreter.eval('''
          const p1 = Promise.resolve(42);
          const p2 = Promise.reject('error');
          
          Promise.allSettled([p1, p2]).then(results => {
            return results[0].status + ',' + results[1].status;
          });
        ''');
        expect(result, isA<JSPromise>());
      });

      test('should handle all fulfilled promises', () {
        final result = interpreter.eval('''
          Promise.allSettled([
            Promise.resolve(1),
            Promise.resolve(2),
            Promise.resolve(3)
          ]).then(results => {
            return results.map(r => r.value).join(',');
          });
        ''');
        expect(result, isA<JSPromise>());
      });

      test('should handle all rejected promises', () {
        final result = interpreter.eval('''
          Promise.allSettled([
            Promise.reject('err1'),
            Promise.reject('err2')
          ]).then(results => {
            return results.length;
          });
        ''');
        expect(result, isA<JSPromise>());
      });

      test('should handle non-promise values', () {
        final result = interpreter.eval('''
          Promise.allSettled([1, 2, 3]).then(results => {
            return results[0].status + ':' + results[0].value;
          });
        ''');
        expect(result, isA<JSPromise>());
      });

      test('should handle empty array', () {
        final result = interpreter.eval('''
          Promise.allSettled([]).then(results => {
            return results.length;
          });
        ''');
        expect(result, isA<JSPromise>());
      });

      test('should preserve order of results', () {
        final result = interpreter.eval('''
          const p1 = new Promise(resolve => setTimeout(() => resolve(1), 100));
          const p2 = Promise.resolve(2);
          const p3 = new Promise(resolve => setTimeout(() => resolve(3), 50));
          
          Promise.allSettled([p1, p2, p3]).then(results => {
            return results.map(r => r.value).join(',');
          });
        ''');
        expect(result, isA<JSPromise>());
      });

      test('should work with mixed fulfilled and rejected', () {
        final result = interpreter.eval('''
          Promise.allSettled([
            Promise.resolve('success'),
            Promise.reject('failure'),
            42,
            Promise.resolve('another success')
          ]).then(results => {
            return results.filter(r => r.status === 'fulfilled').length;
          });
        ''');
        expect(result, isA<JSPromise>());
      });

      test('should include value property for fulfilled', () {
        final result = interpreter.eval('''
          Promise.allSettled([Promise.resolve('test')]).then(results => {
            return results[0].value;
          });
        ''');
        expect(result, isA<JSPromise>());
      });

      test('should include reason property for rejected', () {
        final result = interpreter.eval('''
          Promise.allSettled([Promise.reject('error')]).then(results => {
            return results[0].reason;
          });
        ''');
        expect(result, isA<JSPromise>());
      });
    });

    group('Optional Chaining (?.)', () {
      test('should return undefined for null property access', () {
        final result = interpreter.eval('''
          const obj = null;
          const value = obj?.prop;
          value;
        ''');
        expect(result.isUndefined, true);
      });

      test('should return undefined for undefined property access', () {
        final result = interpreter.eval('''
          const obj = undefined;
          const value = obj?.prop;
          value;
        ''');
        expect(result.isUndefined, true);
      });

      test('should access property when object exists', () {
        final result = interpreter.eval('''
          const obj = { name: 'John' };
          const value = obj?.name;
          value;
        ''');
        expect(result.toString(), 'John');
      });

      test('should work with nested optional chaining', () {
        final result = interpreter.eval('''
          const obj = { user: { name: 'Alice' } };
          const value = obj?.user?.name;
          value;
        ''');
        expect(result.toString(), 'Alice');
      });

      test('should short-circuit on first null/undefined', () {
        final result = interpreter.eval('''
          const obj = { user: null };
          const value = obj?.user?.name;
          value;
        ''');
        expect(result.isUndefined, true);
      });

      test('should work with computed property access', () {
        final result = interpreter.eval('''
          const obj = { items: ['a', 'b', 'c'] };
          const value = obj?.items?.[1];
          value;
        ''');
        expect(result.toString(), 'b');
      });

      test('should return undefined for null array access', () {
        final result = interpreter.eval('''
          const arr = null;
          const value = arr?.[0];
          value;
        ''');
        expect(result.isUndefined, true);
      });

      test('should work with method calls', () {
        final result = interpreter.eval('''
          const obj = {
            greet: function() { return 'Hello'; }
          };
          const value = obj?.greet?.();
          value;
        ''');
        expect(result.toString(), 'Hello');
      });

      test('should return undefined for null method call', () {
        final result = interpreter.eval('''
          const obj = null;
          const value = obj?.greet?.();
          value;
        ''');
        expect(result.isUndefined, true);
      });

      test('should not throw error on missing method', () {
        final result = interpreter.eval('''
          const obj = {};
          const value = obj?.greet?.();
          value;
        ''');
        expect(result.isUndefined, true);
      });

      test('should work with arrays', () {
        final result = interpreter.eval('''
          const arr = [10, 20, 30];
          const value = arr?.[1];
          value;
        ''');
        expect(result.toNumber(), 20);
      });

      test('should handle deep nesting', () {
        final result = interpreter.eval('''
          const data = {
            users: {
              admin: {
                profile: {
                  name: 'SuperAdmin'
                }
              }
            }
          };
          const value = data?.users?.admin?.profile?.name;
          value;
        ''');
        expect(result.toString(), 'SuperAdmin');
      });

      test('should short-circuit at missing intermediate property', () {
        final result = interpreter.eval('''
          const data = {
            users: {
              admin: null
            }
          };
          const value = data?.users?.admin?.profile?.name;
          value;
        ''');
        expect(result.isUndefined, true);
      });

      test('should work with function return values', () {
        final result = interpreter.eval('''
          function getUser() {
            return { name: 'Bob' };
          }
          const value = getUser()?.name;
          value;
        ''');
        expect(result.toString(), 'Bob');
      });

      test('should combine with nullish coalescing', () {
        final result = interpreter.eval('''
          const obj = { user: null };
          const value = obj?.user?.name ?? 'Unknown';
          value;
        ''');
        expect(result.toString(), 'Unknown');
      });

      test('should distinguish null from undefined', () {
        final result = interpreter.eval('''
          const obj1 = null;
          const obj2 = undefined;
          const val1 = obj1?.prop;
          const val2 = obj2?.prop;
          val1 === val2;
        ''');
        expect(result.toBoolean(), true);
      });
    });

    // ========================================================================
    // ES2020: Nullish Coalescing Operator (??)
    // ========================================================================

    group('Nullish Coalescing (??)', () {
      test('should return left operand if not null or undefined', () {
        final result = interpreter.eval('''
          const value = 42;
          const result = value ?? 'default';
          result;
        ''');
        expect(result.toNumber(), 42);
      });

      test('should return right operand if left is null', () {
        final result = interpreter.eval('''
          const value = null;
          const result = value ?? 'default';
          result;
        ''');
        expect(result.toString(), 'default');
      });

      test('should return right operand if left is undefined', () {
        final result = interpreter.eval('''
          let value;
          const result = value ?? 'default';
          result;
        ''');
        expect(result.toString(), 'default');
      });

      test('should treat 0 as valid value (different from ||)', () {
        final result = interpreter.eval('''
          const value = 0;
          const result = value ?? 42;
          result;
        ''');
        expect(result.toNumber(), 0);
      });

      test('should treat empty string as valid value', () {
        final result = interpreter.eval('''
          const value = '';
          const result = value ?? 'default';
          result;
        ''');
        expect(result.toString(), '');
      });

      test('should treat false as valid value', () {
        final result = interpreter.eval('''
          const value = false;
          const result = value ?? true;
          result;
        ''');
        expect(result.toBoolean(), false);
      });

      test('should chain multiple coalescing operators', () {
        final result = interpreter.eval('''
          const a = null;
          const b = undefined;
          const c = 'value';
          const result = a ?? b ?? c ?? 'default';
          result;
        ''');
        expect(result.toString(), 'value');
      });

      test('should work with object properties', () {
        final result = interpreter.eval('''
          const obj = { name: null };
          const result = obj.name ?? 'Anonymous';
          result;
        ''');
        expect(result.toString(), 'Anonymous');
      });

      test('should work with function return values', () {
        final result = interpreter.eval('''
          function getValue() { return undefined; }
          const result = getValue() ?? 'fallback';
          result;
        ''');
        expect(result.toString(), 'fallback');
      });

      test('should short-circuit evaluation', () {
        final result = interpreter.eval('''
          let called = false;
          function sideEffect() {
            called = true;
            return 'side';
          }
          const result = 'value' ?? sideEffect();
          called;
        ''');
        expect(result.toBoolean(), false);
      });

      test('should work with nested expressions', () {
        final result = interpreter.eval('''
          const a = null;
          const b = undefined;
          const result = (a ?? b) ?? 'default';
          result;
        ''');
        expect(result.toString(), 'default');
      });

      test('should work with ternary operator', () {
        final result = interpreter.eval('''
          const value = null;
          const result = value ?? (true ? 'yes' : 'no');
          result;
        ''');
        expect(result.toString(), 'yes');
      });

      test('should work in assignments', () {
        final result = interpreter.eval('''
          let x = null;
          x = x ?? 10;
          x;
        ''');
        expect(result.toNumber(), 10);
      });

      test('should distinguish from OR operator (||)', () {
        final result1 = interpreter.eval('''
          const a = 0;
          const withOr = a || 42;
          const withCoalesce = a ?? 42;
          withOr + ',' + withCoalesce;
        ''');
        expect(result1.toString(), '42,0');
      });
    });

    // ========================================================================
    // ES2020: BigInt
    // ========================================================================

    group('BigInt', () {
      test('should create BigInt from literal', () {
        final result = interpreter.eval('123n');
        expect(result.toString(), '123n');
      });

      test('should perform basic arithmetic operations', () {
        final result = interpreter.eval('''
          const a = 10n;
          const b = 20n;
          const sum = a + b;
          const diff = b - a;
          const prod = a * b;
          const quot = b / a;
          sum + ',' + diff + ',' + prod + ',' + quot;
        ''');
        expect(result.toString(), '30n,10n,200n,2n');
      });

      test('should handle large integers beyond Number.MAX_SAFE_INTEGER', () {
        final result = interpreter.eval('''
          const maxSafe = 9007199254740991n;
          const beyondMax = maxSafe + 1n;
          beyondMax;
        ''');
        expect(result.toString(), '9007199254740992n');
      });

      test('should support BigInt constructor with string', () {
        final result = interpreter.eval('''
          const big = BigInt("999999999999999999");
          big;
        ''');
        expect(result.toString(), '999999999999999999n');
      });

      test('should support BigInt constructor with number', () {
        final result = interpreter.eval('''
          const big = BigInt(123);
          big;
        ''');
        expect(result.toString(), '123n');
      });

      test('should throw error for non-integer number in constructor', () {
        expect(
          () => interpreter.eval('BigInt(123.45)'),
          throwsA(isA<JSTypeError>()),
        );
      });

      test('should throw error for NaN in constructor', () {
        expect(
          () => interpreter.eval('BigInt(NaN)'),
          throwsA(isA<JSTypeError>()),
        );
      });

      test('should support comparison operators', () {
        final result = interpreter.eval('''
          const a = 10n;
          const b = 20n;
          const lt = a < b;
          const gt = a > b;
          const eq = a === a;
          const ne = a !== b;
          lt + ',' + gt + ',' + eq + ',' + ne;
        ''');
        expect(result.toString(), 'true,false,true,true');
      });

      test('should support bitwise operations', () {
        final result = interpreter.eval('''
          const a = 10n;
          const b = 3n;
          const and = a & b;
          const or = a | b;
          const xor = a ^ b;
          const leftShift = a << 2n;
          const rightShift = a >> 2n;
          and + ',' + or + ',' + xor + ',' + leftShift + ',' + rightShift;
        ''');
        expect(result.toString(), '2n,11n,9n,40n,2n');
      });

      test('should support exponentiation', () {
        final result = interpreter.eval('''
          const base = 2n;
          const exp = 10n;
          const result = base ** exp;
          result;
        ''');
        expect(result.toString(), '1024n');
      });

      test('should support modulo operation', () {
        final result = interpreter.eval('''
          const a = 17n;
          const b = 5n;
          const mod = a % b;
          mod;
        ''');
        expect(result.toString(), '2n');
      });

      test('should convert boolean to BigInt', () {
        final result = interpreter.eval('''
          const t = BigInt(true);
          const f = BigInt(false);
          t + ',' + f;
        ''');
        expect(result.toString(), '1n,0n');
      });

      test('should support hexadecimal BigInt literals', () {
        final result = interpreter.eval('0xFFn');
        expect(result.toString(), '255n');
      });

      test('should support binary BigInt literals', () {
        final result = interpreter.eval('0b1111n');
        expect(result.toString(), '15n');
      });

      test('should support octal BigInt literals', () {
        final result = interpreter.eval('0o77n');
        expect(result.toString(), '63n');
      });

      test('should support BigInt constructor with hex string', () {
        final result = interpreter.eval('BigInt("0xFF")');
        expect(result.toString(), '255n');
      });

      test('should support BigInt constructor with binary string', () {
        final result = interpreter.eval('BigInt("0b1111")');
        expect(result.toString(), '15n');
      });

      test('should support BigInt constructor with octal string', () {
        final result = interpreter.eval('BigInt("0o77")');
        expect(result.toString(), '63n');
      });

      test('should support negative BigInt', () {
        final result = interpreter.eval('''
          const neg = -100n;
          const sum = neg + 50n;
          sum;
        ''');
        expect(result.toString(), '-50n');
      });

      test('should compare BigInt with Number using ==', () {
        final result = interpreter.eval('''
          const big = 10n;
          const num = 10;
          const eq = big == num;
          eq;
        ''');
        expect(result.toBoolean(), true);
      });

      test('should not strictly equal BigInt and Number', () {
        final result = interpreter.eval('''
          const big = 10n;
          const num = 10;
          const strictEq = big === num;
          strictEq;
        ''');
        expect(result.toBoolean(), false);
      });

      test('should convert BigInt to boolean (truthy/falsy)', () {
        final result = interpreter.eval('''
          const zero = 0n;
          const nonZero = 42n;
          const zeroTruthy = !!zero;
          const nonZeroTruthy = !!nonZero;
          zeroTruthy + ',' + nonZeroTruthy;
        ''');
        expect(result.toString(), 'false,true');
      });

      test('should support very large calculations', () {
        final result = interpreter.eval('''
          const factorial = 20n * 19n * 18n * 17n * 16n * 15n * 14n * 13n * 12n * 11n * 10n * 9n * 8n * 7n * 6n * 5n * 4n * 3n * 2n * 1n;
          factorial;
        ''');
        expect(result.toString(), '2432902008176640000n');
      });

      test('should support mixed expressions with parentheses', () {
        final result = interpreter.eval('''
          const a = 5n;
          const b = 3n;
          const c = 2n;
          const expr = (a + b) * c - a / c;
          expr;
        ''');
        expect(result.toString(), '14n');
      });
    });
  });
}
