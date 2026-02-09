import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });

  group('Tail Call Optimization (TCO)', () {
    group('Basic TCO - strict mode', () {
      test('simple recursive countdown (100,000 iterations)', () {
        final result = interpreter.eval('''
          "use strict";
          var callCount = 0;
          (function f(n) {
            if (n === 0) {
              callCount += 1;
              return;
            }
            return f(n - 1);
          })(100000);
          callCount;
        ''');
        expect(result.toNumber(), equals(1));
      });

      test('recursive factorial in tail position', () {
        final result = interpreter.eval('''
          "use strict";
          function factorial(n, acc) {
            if (acc === undefined) acc = 1;
            if (n <= 1) return acc;
            return factorial(n - 1, n * acc);
          }
          factorial(20);
        ''');
        expect(result.toNumber(), equals(2432902008176640000));
      });

      test('mutual recursion with TCO', () {
        final result = interpreter.eval('''
          "use strict";
          function isEven(n) {
            if (n === 0) return true;
            return isOdd(n - 1);
          }
          function isOdd(n) {
            if (n === 0) return false;
            return isEven(n - 1);
          }
          isEven(100000);
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('TCO with conditional expression in tail position', () {
        final result = interpreter.eval('''
          "use strict";
          function countdown(n) {
            return n === 0 ? "done" : countdown(n - 1);
          }
          countdown(100000);
        ''');
        expect(result.toString(), equals('done'));
      });

      test('TCO with logical AND in tail position', () {
        final result = interpreter.eval('''
          "use strict";
          var count = 0;
          function f(n) {
            if (n === 0) { count++; return true; }
            return true && f(n - 1);
          }
          f(50000);
          count;
        ''');
        expect(result.toNumber(), equals(1));
      });

      test('TCO with logical OR in tail position', () {
        final result = interpreter.eval('''
          "use strict";
          var count = 0;
          function f(n) {
            if (n === 0) { count++; return "done"; }
            return false || f(n - 1);
          }
          f(50000);
          count;
        ''');
        expect(result.toNumber(), equals(1));
      });
    });

    group('TCO should NOT apply in sloppy mode', () {
      test(
        'sloppy mode does not use TCO (small depth to avoid stack overflow)',
        () {
          // In sloppy mode, TCO should not apply.
          // We test with a small depth to ensure it works normally.
          final result = interpreter.eval('''
          function f(n) {
            if (n === 0) return "done";
            return f(n - 1);
          }
          f(100);
        ''');
          expect(result.toString(), equals('done'));
        },
      );
    });

    group('TCO edge cases', () {
      test('non-tail call should not be optimized', () {
        // f(n-1) + 1 is NOT a tail call because addition happens after
        final result = interpreter.eval('''
          "use strict";
          function sum(n) {
            if (n === 0) return 0;
            return sum(n - 1) + n;
          }
          sum(100);
        ''');
        expect(result.toNumber(), equals(5050));
      });

      test('TCO works with arrow functions', () {
        final result = interpreter.eval('''
          "use strict";
          var count = 0;
          var f = (n) => {
            if (n === 0) { count++; return "done"; }
            return f(n - 1);
          };
          f(50000);
          count;
        ''');
        expect(result.toNumber(), equals(1));
      });

      test('return without argument does not TCO', () {
        final result = interpreter.eval('''
          "use strict";
          var count = 0;
          function f(n) {
            if (n === 0) { count++; return; }
            return f(n - 1);
          }
          f(100);
          count;
        ''');
        expect(result.toNumber(), equals(1));
      });

      test('TCO preserves correct return values', () {
        final result = interpreter.eval('''
          "use strict";
          function fib(n, a, b) {
            if (a === undefined) { a = 0; b = 1; }
            if (n === 0) return a;
            return fib(n - 1, b, a + b);
          }
          fib(50);
        ''');
        // fib(50) = 12586269025
        expect(result.toNumber(), equals(12586269025));
      });

      test('TCO works with method calls', () {
        final result = interpreter.eval('''
          "use strict";
          var obj = {
            count: 0,
            f: function(n) {
              if (n === 0) { this.count++; return this.count; }
              return obj.f(n - 1);
            }
          };
          obj.f(50000);
        ''');
        expect(result.toNumber(), equals(1));
      });

      test('TCO with comma/sequence expression in tail position', () {
        final result = interpreter.eval('''
          "use strict";
          var sideEffect = 0;
          function f(n) {
            if (n === 0) return "done";
            return (sideEffect++, f(n - 1));
          }
          var r = f(1000);
          r + ":" + sideEffect;
        ''');
        expect(result.toString(), equals('done:1000'));
      });

      test('TCO with nullish coalescing in tail position', () {
        final result = interpreter.eval('''
          "use strict";
          var count = 0;
          function f(n) {
            if (n === 0) { count++; return "done"; }
            return null ?? f(n - 1);
          }
          f(50000);
          count;
        ''');
        expect(result.toNumber(), equals(1));
      });
    });

    group('TCO stress tests', () {
      test('deep recursion: 200,000 calls', () {
        final result = interpreter.eval('''
          "use strict";
          function loop(n) {
            if (n === 0) return "complete";
            return loop(n - 1);
          }
          loop(200000);
        ''');
        expect(result.toString(), equals('complete'));
      });

      test('accumulator pattern with 100,000 iterations', () {
        final result = interpreter.eval('''
          "use strict";
          function sumTo(n, acc) {
            if (acc === undefined) acc = 0;
            if (n === 0) return acc;
            return sumTo(n - 1, acc + n);
          }
          sumTo(100000);
        ''');
        // Sum 1..100000 = 100000 * 100001 / 2 = 5000050000
        expect(result.toNumber(), equals(5000050000));
      });
    });
  });
}
