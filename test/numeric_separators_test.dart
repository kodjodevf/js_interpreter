import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Numeric Separators (ES2021)', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('Decimal numbers with separators', () {
      test('Basic decimal with underscores', () {
        final result = interpreter.eval('1_000_000');
        expect(result.toNumber(), 1000000);
      });

      test('Decimal with float part', () {
        final result = interpreter.eval('1_000_000.50');
        expect(result.toNumber(), 1000000.50);
      });

      test('Multiple separators in different positions', () {
        final result = interpreter.eval('1_2_3_4_5');
        expect(result.toNumber(), 12345);
      });

      test('Separators in decimal part', () {
        final result = interpreter.eval('0.123_456_789');
        expect(result.toNumber(), 0.123456789);
      });

      test('Scientific notation with separators', () {
        final result = interpreter.eval('1_000e3');
        expect(result.toNumber(), 1000000);
      });

      test('Scientific notation in exponent', () {
        final result = interpreter.eval('1e1_000');
        expect(result.toNumber(), double.parse('1e1000'));
      });

      test('Arithmetic operations with separated numbers', () {
        final result = interpreter.eval('1_000 + 2_000');
        expect(result.toNumber(), 3000);
      });

      test('Complex expression', () {
        final result = interpreter.eval('''
          const price = 1_000_000;
          const tax = 0.15;
          const total = price * (1 + tax);
          total
        ''');
        expect(result.toNumber(), 1150000);
      });
    });

    group('Binary numbers with separators', () {
      test('Binary with underscores', () {
        final result = interpreter.eval('0b1010_0001');
        expect(result.toNumber(), 161); // 0b10100001 = 161
      });

      test('Binary with multiple separators', () {
        final result = interpreter.eval('0b1111_1111_1111_1111');
        expect(result.toNumber(), 65535); // 0xFFFF
      });

      test('Binary nibbles', () {
        final result = interpreter.eval('0b1111_0000_1010_0101');
        expect(result.toNumber(), 61605); // 0xF0A5
      });

      test('Binary arithmetic', () {
        final result = interpreter.eval('0b1111 + 0b0001');
        expect(result.toNumber(), 16); // 15 + 1
      });
    });

    group('Octal numbers with separators', () {
      test('Octal with underscores', () {
        final result = interpreter.eval('0o2_3_5_7');
        expect(result.toNumber(), 1263); // 2*512 + 3*64 + 5*8 + 7
      });

      test('Octal permission style', () {
        final result = interpreter.eval('0o755');
        expect(result.toNumber(), 493); // rwxr-xr-x
      });

      test('Octal with separator', () {
        final result = interpreter.eval('0o7_7_7');
        expect(result.toNumber(), 511);
      });
    });

    group('Hexadecimal numbers with separators', () {
      test('Hex with underscores', () {
        final result = interpreter.eval('0xA0_B0_C0');
        expect(result.toNumber(), 10531008); // 0xA0B0C0
      });

      test('Hex color code style', () {
        final result = interpreter.eval('0xFF_00_FF');
        expect(result.toNumber(), 16711935); // Magenta
      });

      test('Hex byte pairs', () {
        final result = interpreter.eval('0xDE_AD_BE_EF');
        expect(result.toNumber(), 3735928559); // 0xDEADBEEF
      });

      test('Hex lowercase with separators', () {
        final result = interpreter.eval('0xa_b_c_d');
        expect(result.toNumber(), 43981); // 0xABCD
      });

      test('Mixed case hex', () {
        final result = interpreter.eval('0xAb_Cd_Ef');
        expect(result.toNumber(), 11259375); // 0xABCDEF
      });
    });

    group('BigInt with separators', () {
      test('Decimal BigInt with separators', () {
        final result = interpreter.eval('1_000_000n');
        expect(result.toString(), '1000000n');
      });

      test('Binary BigInt with separators', () {
        final result = interpreter.eval('0b1111_1111n');
        expect(result.toString(), '255n');
      });

      test('Octal BigInt with separators', () {
        final result = interpreter.eval('0o777_777n');
        expect(result.toString(), '262143n');
      });

      test('Hex BigInt with separators', () {
        final result = interpreter.eval('0xFF_FF_FFn');
        expect(result.toString(), '16777215n');
      });

      test('Very large BigInt with separators', () {
        final result = interpreter.eval('1_234_567_890_123_456_789n');
        expect(result.toString(), '1234567890123456789n');
      });
    });

    group('Edge cases and mixed usage', () {
      test('Array of separated numbers', () {
        final result = interpreter.eval('[1_000, 0b1010, 0o777, 0xFF]');
        expect(result.toString(), '1000,10,511,255');
      });

      test('Object with separated numbers', () {
        final result = interpreter.eval('''
          const obj = {
            decimal: 1_000_000,
            binary: 0b1111_0000,
            octal: 0o755,
            hex: 0xDEAD_BEEF
          };
          [obj.decimal, obj.binary, obj.octal, obj.hex]
        ''');
        expect(result.toString(), '1000000,240,493,3735928559');
      });

      test('Separators in function parameters', () {
        final result = interpreter.eval('''
          function calculate(a, b) {
            return a + b;
          }
          calculate(1_000, 2_000)
        ''');
        expect(result.toNumber(), 3000);
      });

      test('Comparison with separated numbers', () {
        final result = interpreter.eval('1_000 === 1000');
        expect(result.isTruthy, true);
      });

      test('All formats together', () {
        final result = interpreter.eval('''
          const sum = 1_000 + 0b1111_1111 + 0o777 + 0xFF_FF;
          sum
        ''');
        expect(result.toNumber(), 1000 + 255 + 511 + 65535);
      });
    });

    group('Real-world examples', () {
      test('Financial calculations', () {
        final result = interpreter.eval('''
          const salary = 100_000;
          const bonus = 15_000;
          const taxRate = 0.25;
          const netIncome = (salary + bonus) * (1 - taxRate);
          netIncome
        ''');
        expect(result.toNumber(), 86250);
      });

      test('Memory sizes', () {
        final result = interpreter.eval('''
          const kilobyte = 1_024;
          const megabyte = kilobyte * 1_024;
          const gigabyte = megabyte * 1_024;
          gigabyte
        ''');
        expect(result.toNumber(), 1073741824);
      });

      test('RGB to hex conversion simulation', () {
        final result = interpreter.eval('''
          const r = 255;
          const g = 128;
          const b = 64;
          const hex = (r << 16) + (g << 8) + b;
          hex === 0xFF_80_40
        ''');
        expect(result.isTruthy, true);
      });

      test('Bit manipulation with readable constants', () {
        final result = interpreter.eval('''
          const READ = 0b100;
          const WRITE = 0b010;
          const EXECUTE = 0b001;
          const permissions = READ | WRITE;
          permissions === 0b110
        ''');
        expect(result.isTruthy, true);
      });

      test('Hex color constants', () {
        final result = interpreter.eval('''
          const red = 0xFF_00_00;
          const green = 0x00_FF_00;
          const blue = 0x00_00_FF;
          [red, green, blue]
        ''');
        expect(result.toString(), '16711680,65280,255');
      });
    });
  });
}
