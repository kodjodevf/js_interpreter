import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('BigInt Support', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('BigInt literals', () {
      final result = interpreter.eval('123n');
      expect(result.toString(), '123n');
      expect(result.type, JSValueType.bigint);
    });

    test('BigInt basic operations', () {
      final result = interpreter.eval('''
        const a = 123n;
        const b = 456n;
        [a + b, a * b, b - a]
      ''');
      expect(result.toString(), '579n,56088n,333n');
    });

    test('BigInt constructor with numbers', () {
      final result = interpreter.eval('BigInt(123)');
      expect(result.toString(), '123n');
      expect(result.type, JSValueType.bigint);
    });

    test('BigInt constructor with strings', () {
      final result = interpreter.eval('BigInt("456")');
      expect(result.toString(), '456n');
      expect(result.type, JSValueType.bigint);
    });

    test('BigInt constructor with binary string', () {
      final result = interpreter.eval('BigInt("0b1010")');
      expect(result.toString(), '10n');
      expect(result.type, JSValueType.bigint);
    });

    test('BigInt constructor with octal string', () {
      final result = interpreter.eval('BigInt("0o77")');
      expect(result.toString(), '63n');
      expect(result.type, JSValueType.bigint);
    });

    test('BigInt constructor with hex string', () {
      final result = interpreter.eval('BigInt("0xff")');
      expect(result.toString(), '255n');
      expect(result.type, JSValueType.bigint);
    });

    test('BigInt constructor with boolean', () {
      final result = interpreter.eval('[BigInt(true), BigInt(false)]');
      expect(result.toString(), '1n,0n');
    });

    test('BigInt constructor with existing BigInt', () {
      final result = interpreter.eval('BigInt(BigInt(789))');
      expect(result.toString(), '789n');
      expect(result.type, JSValueType.bigint);
    });

    test('BigInt constructor errors', () {
      expect(() => interpreter.eval('BigInt()'), throwsA(isA<JSTypeError>()));
      expect(
        () => interpreter.eval('BigInt(NaN)'),
        throwsA(isA<JSTypeError>()),
      );
      expect(
        () => interpreter.eval('BigInt(Infinity)'),
        throwsA(isA<JSTypeError>()),
      );
      expect(
        () => interpreter.eval('BigInt(1.5)'),
        throwsA(isA<JSTypeError>()),
      );
      expect(
        () => interpreter.eval('BigInt("invalid")'),
        throwsA(isA<JSTypeError>()),
      );
    });

    test('BigInt.asIntN', () {
      final result = interpreter.eval('BigInt.asIntN(8, 300n)');
      expect(result.toString(), '44n'); // 300 & 0xFF = 44
    });

    test('BigInt.asUintN', () {
      final result = interpreter.eval('BigInt.asUintN(8, BigInt(-1))');
      expect(result.toString(), '255n'); // -1 as unsigned 8-bit = 255
    });

    test('BigInt prototype methods on constructor instances', () {
      final result = interpreter.eval('''
        const big = BigInt("123");
        [big.toString(), big.toString(16)]
      ''');
      expect(result.toString(), '123,7b');
    });

    test('BigInt comparison operations', () {
      final result = interpreter.eval('''
        const a = BigInt(100);
        const b = BigInt(200);
        [a < b, a > b, a === BigInt(100), a !== b]
      ''');
      expect(result.toString(), 'true,false,true,true');
    });

    test('BigInt bitwise operations', () {
      final result = interpreter.eval('''
        const a = BigInt(12);
        const b = BigInt(10);
        a + b
      ''');
      expect(result.toString(), '22n');
    });

    test('BigInt division and modulo', () {
      final result = interpreter.eval('''
        const a = BigInt(17);
        const b = BigInt(5);
        [a / b, a % b]
      ''');
      expect(result.toString(), '3n,2n');
    });
  });
}
