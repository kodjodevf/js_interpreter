import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Generator Execution Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Simple yield returns value', () {
      final code = '''
        function* gen() {
          yield 1;
          yield 2;
          yield 3;
        }
        
        var g = gen();
        var r1 = g.next();
        var r2 = g.next();
        var r3 = g.next();
        var r4 = g.next();
        
        [r1.value, r1.done, r2.value, r2.done, r3.value, r3.done, r4.value, r4.done]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(1)); // r1.value
      expect(result.elements[1].toBoolean(), equals(false)); // r1.done
      expect(result.elements[2].toNumber(), equals(2)); // r2.value
      expect(result.elements[3].toBoolean(), equals(false)); // r2.done
      expect(result.elements[4].toNumber(), equals(3)); // r3.value
      expect(result.elements[5].toBoolean(), equals(false)); // r3.done
      expect(result.elements[6].toString(), equals('undefined')); // r4.value
      expect(result.elements[7].toBoolean(), equals(true)); // r4.done
    });

    test('Generator with return statement', () {
      final code = '''
        function* gen() {
          yield 1;
          yield 2;
          return 42;
        }
        
        var g = gen();
        var r1 = g.next();
        var r2 = g.next();
        var r3 = g.next();
        
        [r1.value, r1.done, r2.value, r2.done, r3.value, r3.done]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(1)); // r1.value
      expect(result.elements[1].toBoolean(), equals(false)); // r1.done
      expect(result.elements[2].toNumber(), equals(2)); // r2.value
      expect(result.elements[3].toBoolean(), equals(false)); // r2.done
      expect(
        result.elements[4].toNumber(),
        equals(42),
      ); // r3.value (return value)
      expect(result.elements[5].toBoolean(), equals(true)); // r3.done
    });

    test('Generator with no yields completes immediately', () {
      final code = '''
        function* gen() {
          return 100;
        }
        
        var g = gen();
        var r = g.next();
        
        [r.value, r.done]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(100));
      expect(result.elements[1].toBoolean(), equals(true));
    });

    test('Generator with expressions in yield', () {
      final code = '''
        function* gen() {
          yield 1 + 1;
          yield 2 * 3;
          yield 10 - 5;
        }
        
        var g = gen();
        [g.next().value, g.next().value, g.next().value]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(2));
      expect(result.elements[1].toNumber(), equals(6));
      expect(result.elements[2].toNumber(), equals(5));
    });

    test('Generator with local variables', () {
      final code = '''
        function* gen() {
          var x = 10;
          yield x;
          x = 20;
          yield x;
          x = 30;
          yield x;
        }
        
        var g = gen();
        [g.next().value, g.next().value, g.next().value]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(10));
      expect(result.elements[1].toNumber(), equals(20));
      expect(result.elements[2].toNumber(), equals(30));
    });

    test('Generator with parameters', () {
      final code = '''
        function* gen(start, end) {
          var i = start;
          while (i <= end) {
            yield i;
            i++;
          }
        }
        
        var g = gen(5, 7);
        [g.next().value, g.next().value, g.next().value, g.next().done]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(5));
      expect(result.elements[1].toNumber(), equals(6));
      expect(result.elements[2].toNumber(), equals(7));
      expect(result.elements[3].toBoolean(), equals(true));
    });

    test('Calling next() on completed generator returns done:true', () {
      final code = '''
        function* gen() {
          yield 1;
        }
        
        var g = gen();
        g.next(); // yield 1
        g.next(); // complete
        var r = g.next(); // already completed
        
        [r.value, r.done]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toString(), equals('undefined'));
      expect(result.elements[1].toBoolean(), equals(true));
    });

    test('Multiple generator instances are independent', () {
      final code = '''
        function* gen() {
          yield 1;
          yield 2;
        }
        
        var g1 = gen();
        var g2 = gen();
        
        var r1 = g1.next();
        var r2 = g2.next();
        var r3 = g1.next();
        var r4 = g2.next();
        
        [r1.value, r2.value, r3.value, r4.value]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(1));
      expect(result.elements[2].toNumber(), equals(2));
      expect(result.elements[3].toNumber(), equals(2));
    });
  });

  group('Generator Return Method Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('return() method completes generator early', () {
      final code = '''
        function* gen() {
          yield 1;
          yield 2;
          yield 3;
        }
        
        var g = gen();
        var r1 = g.next();
        var r2 = g['return'](100);
        var r3 = g.next();
        
        [r1.value, r1.done, r2.value, r2.done, r3.value, r3.done]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(1)); // r1.value
      expect(result.elements[1].toBoolean(), equals(false)); // r1.done
      expect(
        result.elements[2].toNumber(),
        equals(100),
      ); // r2.value (return value)
      expect(result.elements[3].toBoolean(), equals(true)); // r2.done
      expect(result.elements[4].toString(), equals('undefined')); // r3.value
      expect(result.elements[5].toBoolean(), equals(true)); // r3.done
    });
  });

  group('Generator Edge Cases', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Generator with yield but no value', () {
      final code = '''
        function* gen() {
          yield;
          yield;
        }
        
        var g = gen();
        [g.next().value, g.next().value]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toString(), equals('undefined'));
      expect(result.elements[1].toString(), equals('undefined'));
    });

    test('Generator with conditional yield', () {
      final code = '''
        function* gen(flag) {
          if (flag) {
            yield 1;
          }
          yield 2;
        }
        
        var g1 = gen(true);
        var g2 = gen(false);
        
        [g1.next().value, g1.next().value, g2.next().value]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(2));
      expect(result.elements[2].toNumber(), equals(2));
    });

    test('Generator in a loop', () {
      final code = '''
        function* gen(n) {
          for (var i = 0; i < n; i++) {
            yield i;
          }
        }
        
        var g = gen(3);
        [g.next().value, g.next().value, g.next().value, g.next().done]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(0));
      expect(result.elements[1].toNumber(), equals(1));
      expect(result.elements[2].toNumber(), equals(2));
      expect(result.elements[3].toBoolean(), equals(true));
    });
  });
}
