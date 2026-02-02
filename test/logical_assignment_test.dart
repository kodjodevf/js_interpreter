import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Logical Assignment Operators (ES2021)', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('AND Assignment (&&=)', () {
      test('&&= assigns only if left is truthy', () {
        final result = interpreter.eval('''
          let a = true;
          let b = false;
          let c = 0;
          let d = 1;
          
          a &&= 'assigned';
          b &&= 'not assigned';
          c &&= 'not assigned';
          d &&= 'assigned';
          
          [a, b, c, d]
        ''');
        expect(result.toString(), 'assigned,false,0,assigned');
      });

      test('&&= does not evaluate right side if left is falsy', () {
        final result = interpreter.eval('''
          let called = false;
          let x = 0;
          
          x &&= (called = true, 'value');
          
          [x, called]
        ''');
        expect(result.toString(), '0,false');
      });

      test('&&= works with object properties', () {
        final result = interpreter.eval('''
          const obj = { a: 1, b: 0 };
          obj.a &&= 100;
          obj.b &&= 100;
          [obj.a, obj.b]
        ''');
        expect(result.toString(), '100,0');
      });

      test('&&= works with array elements', () {
        final result = interpreter.eval('''
          const arr = [1, 0, '', 'hello'];
          arr[0] &&= 99;
          arr[1] &&= 99;
          arr[2] &&= 99;
          arr[3] &&= 'world';
          arr
        ''');
        expect(result.toString(), '99,0,,world');
      });
    });

    group('OR Assignment (||=)', () {
      test('||= assigns only if left is falsy', () {
        final result = interpreter.eval('''
          let a = false;
          let b = true;
          let c = 0;
          let d = '';
          let e = 'hello';
          
          a ||= 'assigned';
          b ||= 'not assigned';
          c ||= 'assigned';
          d ||= 'assigned';
          e ||= 'not assigned';
          
          [a, b, c, d, e]
        ''');
        expect(result.toString(), 'assigned,true,assigned,assigned,hello');
      });

      test('||= does not evaluate right side if left is truthy', () {
        final result = interpreter.eval('''
          let called = false;
          let x = 1;
          
          x ||= (called = true, 'value');
          
          [x, called]
        ''');
        expect(result.toString(), '1,false');
      });

      test('||= works with default values pattern', () {
        final result = interpreter.eval('''
          const config = {
            port: 0,
            host: null
          };
          
          config.port ||= 8080;
          config.host ||= 'localhost';
          
          [config.port, config.host]
        ''');
        // Note: port is 0 which is falsy, so it gets replaced
        expect(result.toString(), '8080,localhost');
      });

      test('||= works with array elements', () {
        final result = interpreter.eval('''
          const arr = [0, 1, false, true, ''];
          arr[0] ||= 'zero';
          arr[1] ||= 'one';
          arr[2] ||= 'was false';
          arr[3] ||= 'was true';
          arr[4] ||= 'empty';
          arr
        ''');
        expect(result.toString(), 'zero,1,was false,true,empty');
      });
    });

    group('Nullish Coalescing Assignment (??=)', () {
      test('??= assigns only if left is null or undefined', () {
        final result = interpreter.eval('''
          let a = null;
          let b = undefined;
          let c = 0;
          let d = false;
          let e = '';
          let f = 'hello';
          
          a ??= 'assigned';
          b ??= 'assigned';
          c ??= 'not assigned';
          d ??= 'not assigned';
          e ??= 'not assigned';
          f ??= 'not assigned';
          
          [a, b, c, d, e, f]
        ''');
        expect(result.toString(), 'assigned,assigned,0,false,,hello');
      });

      test('??= does not evaluate right side if left is not nullish', () {
        final result = interpreter.eval('''
          let called = false;
          let x = 0;
          
          x ??= (called = true, 'value');
          
          [x, called]
        ''');
        expect(result.toString(), '0,false');
      });

      test('??= is perfect for default values that should allow falsy', () {
        final result = interpreter.eval('''
          const config = {
            port: 0,
            debug: false,
            host: null
          };
          
          config.port ??= 8080;     // 0 is preserved
          config.debug ??= true;    // false is preserved
          config.host ??= 'localhost'; // null is replaced
          
          [config.port, config.debug, config.host]
        ''');
        expect(result.toString(), '0,false,localhost');
      });

      test('??= works with object properties', () {
        final result = interpreter.eval('''
          const obj = { a: null, b: undefined, c: 0 };
          obj.a ??= 'default';
          obj.b ??= 'default';
          obj.c ??= 'default';
          [obj.a, obj.b, obj.c]
        ''');
        expect(result.toString(), 'default,default,0');
      });

      test('??= works with array elements', () {
        final result = interpreter.eval('''
          const arr = [null, undefined, 0, false, ''];
          arr[0] ??= 'null';
          arr[1] ??= 'undefined';
          arr[2] ??= 'zero';
          arr[3] ??= 'false';
          arr[4] ??= 'empty';
          arr
        ''');
        expect(result.toString(), 'null,undefined,0,false,');
      });
    });

    group('Complex scenarios', () {
      test('Chaining different logical assignments', () {
        final result = interpreter.eval('''
          let a = null;
          let b = 0;
          let c = false;
          
          a ??= 10;  // null -> 10
          b ||= 20;  // 0 (falsy) -> 20
          c &&= 30;  // false (falsy) -> stays false
          
          [a, b, c]
        ''');
        expect(result.toString(), '10,20,false');
      });

      test('Using all three operators together', () {
        final result = interpreter.eval('''
          const data = {
            value: undefined,
            count: 0,
            enabled: true
          };
          
          data.value ??= 'default';  // undefined -> 'default'
          data.count ||= 1;           // 0 (falsy) -> 1
          data.enabled &&= false;     // true (truthy) -> false
          
          [data.value, data.count, data.enabled]
        ''');
        expect(result.toString(), 'default,1,false');
      });

      test('Logical assignment returns the final value', () {
        final result = interpreter.eval('''
          let x = null;
          const result = (x ??= 42);
          [x, result]
        ''');
        expect(result.toString(), '42,42');
      });

      test('Logical assignment with computed property names', () {
        final result = interpreter.eval('''
          const obj = { foo: null, bar: 0 };
          const key1 = 'foo';
          const key2 = 'bar';
          
          obj[key1] ??= 'replaced';
          obj[key2] ||= 'replaced';
          
          [obj.foo, obj.bar]
        ''');
        expect(result.toString(), 'replaced,replaced');
      });

      test('Nested logical assignments', () {
        final result = interpreter.eval('''
          const outer = { inner: { value: null } };
          outer.inner.value ??= 'nested';
          outer.inner.value
        ''');
        expect(result.toString(), 'nested');
      });
    });
  });
}
