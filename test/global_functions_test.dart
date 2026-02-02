import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Global Functions Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('parseInt()', () {
      test('basic integer parsing', () {
        expect(interpreter.eval('parseInt("123")').toNumber(), equals(123));
        expect(interpreter.eval('parseInt("123.45")').toNumber(), equals(123));
        expect(interpreter.eval('parseInt("123abc")').toNumber(), equals(123));
      });

      test('with radix parameter', () {
        expect(interpreter.eval('parseInt("10", 2)').toNumber(), equals(2));
        expect(interpreter.eval('parseInt("10", 8)').toNumber(), equals(8));
        expect(interpreter.eval('parseInt("10", 16)').toNumber(), equals(16));
        expect(interpreter.eval('parseInt("ff", 16)').toNumber(), equals(255));
      });

      test('hex auto-detection', () {
        expect(interpreter.eval('parseInt("0xff")').toNumber(), equals(255));
        expect(interpreter.eval('parseInt("0x10")').toNumber(), equals(16));
      });

      test('invalid inputs', () {
        expect(interpreter.eval('parseInt("abc")').toNumber().isNaN, isTrue);
        expect(interpreter.eval('parseInt("")').toNumber().isNaN, isTrue);
        expect(interpreter.eval('parseInt()').toNumber().isNaN, isTrue);
      });

      test('negative numbers', () {
        expect(interpreter.eval('parseInt("-123")').toNumber(), equals(-123));
        expect(interpreter.eval('parseInt("+123")').toNumber(), equals(123));
      });
    });

    group('parseFloat()', () {
      test('basic float parsing', () {
        expect(
          interpreter.eval('parseFloat("123.45")').toNumber(),
          equals(123.45),
        );
        expect(interpreter.eval('parseFloat("123")').toNumber(), equals(123));
        expect(
          interpreter.eval('parseFloat("123.45abc")').toNumber(),
          equals(123.45),
        );
      });

      test('scientific notation', () {
        expect(interpreter.eval('parseFloat("1e2")').toNumber(), equals(100));
        expect(interpreter.eval('parseFloat("1.5e2")').toNumber(), equals(150));
        expect(interpreter.eval('parseFloat("1e-2")').toNumber(), equals(0.01));
      });

      test('special values', () {
        expect(
          interpreter.eval('parseFloat("Infinity")').toNumber(),
          equals(double.infinity),
        );
        expect(
          interpreter.eval('parseFloat("-Infinity")').toNumber(),
          equals(double.negativeInfinity),
        );
      });

      test('invalid inputs', () {
        expect(interpreter.eval('parseFloat("abc")').toNumber().isNaN, isTrue);
        expect(interpreter.eval('parseFloat("")').toNumber().isNaN, isTrue);
        expect(interpreter.eval('parseFloat()').toNumber().isNaN, isTrue);
      });
    });

    group('isNaN()', () {
      test('detects NaN correctly', () {
        expect(interpreter.eval('isNaN(NaN)').toBoolean(), isTrue);
        expect(interpreter.eval('isNaN("abc")').toBoolean(), isTrue);
        expect(interpreter.eval('isNaN(undefined)').toBoolean(), isTrue);
      });

      test('valid numbers return false', () {
        expect(interpreter.eval('isNaN(123)').toBoolean(), isFalse);
        expect(interpreter.eval('isNaN("123")').toBoolean(), isFalse);
        expect(interpreter.eval('isNaN(123.45)').toBoolean(), isFalse);
        expect(interpreter.eval('isNaN(Infinity)').toBoolean(), isFalse);
      });

      test('empty parameter', () {
        expect(interpreter.eval('isNaN()').toBoolean(), isTrue);
      });
    });

    group('isFinite()', () {
      test('detects finite numbers', () {
        expect(interpreter.eval('isFinite(123)').toBoolean(), isTrue);
        expect(interpreter.eval('isFinite(123.45)').toBoolean(), isTrue);
        expect(interpreter.eval('isFinite(-123)').toBoolean(), isTrue);
        expect(interpreter.eval('isFinite("123")').toBoolean(), isTrue);
      });

      test('detects infinite values', () {
        expect(interpreter.eval('isFinite(Infinity)').toBoolean(), isFalse);
        expect(interpreter.eval('isFinite(-Infinity)').toBoolean(), isFalse);
        expect(interpreter.eval('isFinite(NaN)').toBoolean(), isFalse);
      });

      test('empty parameter', () {
        expect(interpreter.eval('isFinite()').toBoolean(), isFalse);
      });
    });

    group('URI functions', () {
      test('encodeURI and decodeURI', () {
        final encoded = interpreter.eval('encodeURI("hello world")').toString();
        expect(encoded, equals('hello%20world'));

        final decoded = interpreter
            .eval('decodeURI("hello%20world")')
            .toString();
        expect(decoded, equals('hello world'));
      });

      test('encodeURIComponent and decodeURIComponent', () {
        final encoded = interpreter
            .eval('encodeURIComponent("hello@world.com")')
            .toString();
        expect(encoded, contains('%40')); // @ should be encoded

        final decoded = interpreter
            .eval('decodeURIComponent("hello%40world.com")')
            .toString();
        expect(decoded, equals('hello@world.com'));
      });
    });

    group('eval()', () {
      test('evaluates simple expressions', () {
        expect(interpreter.eval('eval("2 + 3")').toNumber(), equals(5));
        expect(interpreter.eval('eval("true")').toBoolean(), isTrue);
        expect(
          interpreter.eval('eval("\\"hello\\"")').toString(),
          equals('hello'),
        );
      });

      test('evaluates variable declarations', () {
        final result = interpreter.eval('''
          eval("var x = 42;");
          x;
        ''');
        expect(result.toNumber(), equals(42));
      });

      test('evaluates function calls', () {
        final result = interpreter.eval('''
          function add(a, b) { return a + b; }
          eval("add(10, 20)");
        ''');
        expect(result.toNumber(), equals(30));
      });

      test('returns undefined for empty input', () {
        expect(interpreter.eval('eval()').type.name, equals('undefined'));
      });
    });
  });
}
