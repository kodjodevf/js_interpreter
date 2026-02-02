import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Bitwise Operators', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('Bitwise AND (&)', () {
      test('Basic AND operation', () {
        final result = interpreter.eval('12 & 10');
        expect(result.toNumber(), 8); // 1100 & 1010 = 1000
      });

      test('AND with zero', () {
        final result = interpreter.eval('255 & 0');
        expect(result.toNumber(), 0);
      });

      test('AND with all ones', () {
        final result = interpreter.eval('42 & 0xFFFFFFFF');
        expect(result.toNumber(), 42);
      });

      test('AND in expression', () {
        final result = interpreter.eval('''
          const flags = 0b1111;
          const mask = 0b1010;
          const result = flags & mask;
          result
        ''');
        expect(result.toNumber(), 10); // 0b1010
      });
    });

    group('Bitwise OR (|)', () {
      test('Basic OR operation', () {
        final result = interpreter.eval('12 | 10');
        expect(result.toNumber(), 14); // 1100 | 1010 = 1110
      });

      test('OR with zero', () {
        final result = interpreter.eval('42 | 0');
        expect(result.toNumber(), 42);
      });

      test('OR for combining flags', () {
        final result = interpreter.eval('''
          const READ = 0b100;
          const WRITE = 0b010;
          const EXECUTE = 0b001;
          const permissions = READ | WRITE | EXECUTE;
          permissions
        ''');
        expect(result.toNumber(), 7); // 0b111
      });

      test('OR in conditional', () {
        final result = interpreter.eval('''
          const a = 0b0001;
          const b = 0b0010;
          (a | b) === 0b0011
        ''');
        expect(result.isTruthy, true);
      });
    });

    group('Bitwise XOR (^)', () {
      test('Basic XOR operation', () {
        final result = interpreter.eval('12 ^ 10');
        expect(result.toNumber(), 6); // 1100 ^ 1010 = 0110
      });

      test('XOR with self returns zero', () {
        final result = interpreter.eval('42 ^ 42');
        expect(result.toNumber(), 0);
      });

      test('XOR toggle bits', () {
        final result = interpreter.eval('''
          let value = 0b1010;
          value = value ^ 0b1111; // Toggle all 4 bits
          value
        ''');
        expect(result.toNumber(), 5); // 0b0101
      });

      test('XOR swap without temp variable', () {
        final result = interpreter.eval('''
          let a = 5;
          let b = 10;
          a = a ^ b;
          b = a ^ b; // b = (a ^ b) ^ b = a
          a = a ^ b; // a = (a ^ b) ^ a = b
          [a, b]
        ''');
        expect(result.toString(), '10,5');
      });
    });

    group('Bitwise NOT (~)', () {
      test('Basic NOT operation', () {
        final result = interpreter.eval('~5');
        expect(result.toNumber(), -6);
      });

      test('Double NOT', () {
        final result = interpreter.eval('~~3.7');
        expect(result.toNumber(), 3); // Truncates to integer
      });

      test('NOT inverts all bits', () {
        final result = interpreter.eval('~0');
        expect(result.toNumber(), -1);
      });

      test('NOT with positive number', () {
        final result = interpreter.eval('~255');
        expect(result.toNumber(), -256);
      });

      test('NOT with negative number', () {
        final result = interpreter.eval('~(-1)');
        expect(result.toNumber(), 0);
      });
    });

    group('Left Shift (<<)', () {
      test('Basic left shift', () {
        final result = interpreter.eval('5 << 2');
        expect(result.toNumber(), 20); // 0101 << 2 = 10100
      });

      test('Shift by zero', () {
        final result = interpreter.eval('42 << 0');
        expect(result.toNumber(), 42);
      });

      test('Shift creating power of 2', () {
        final result = interpreter.eval('1 << 8');
        expect(result.toNumber(), 256);
      });

      test('RGB color composition', () {
        final result = interpreter.eval('''
          const r = 255;
          const g = 128;
          const b = 64;
          const color = (r << 16) | (g << 8) | b;
          color
        ''');
        expect(result.toNumber(), 16744512); // 0xFF8040
      });

      test('Shift amount modulo 32', () {
        final result = interpreter.eval('5 << 33');
        expect(result.toNumber(), 10); // Same as 5 << 1
      });
    });

    group('Right Shift (>>)', () {
      test('Basic right shift', () {
        final result = interpreter.eval('20 >> 2');
        expect(result.toNumber(), 5); // 10100 >> 2 = 00101
      });

      test('Shift by zero', () {
        final result = interpreter.eval('42 >> 0');
        expect(result.toNumber(), 42);
      });

      test('Shift preserves sign (arithmetic)', () {
        final result = interpreter.eval('-8 >> 2');
        expect(result.toNumber(), -2); // Sign-extended
      });

      test('Divide by power of 2', () {
        final result = interpreter.eval('100 >> 2');
        expect(result.toNumber(), 25); // 100 / 4
      });
    });

    group('Unsigned Right Shift (>>>)', () {
      test('Basic unsigned right shift', () {
        final result = interpreter.eval('20 >>> 2');
        expect(result.toNumber(), 5);
      });

      test('Unsigned shift of negative number', () {
        final result = interpreter.eval('-1 >>> 0');
        expect(result.toNumber(), 4294967295); // 0xFFFFFFFF
      });

      test('Unsigned shift fills with zeros', () {
        final result = interpreter.eval('-8 >>> 2');
        expect(result.toNumber(), 1073741822); // No sign extension
      });

      test('Convert to unsigned 32-bit', () {
        final result = interpreter.eval('-100 >>> 0');
        expect(result.toNumber(), 4294967196);
      });
    });

    group('Complex expressions', () {
      test('Mixed bitwise operations', () {
        final result = interpreter.eval('(5 & 3) | (2 << 1)');
        expect(result.toNumber(), 5); // (1 | 4) = 5
      });

      test('Bitwise with arithmetic', () {
        final result = interpreter.eval('(10 + 5) & 7');
        expect(result.toNumber(), 7); // 15 & 7
      });

      test('Bit manipulation mask', () {
        final result = interpreter.eval('''
          const value = 0b11010110;
          const mask = 0b00001111;
          const lower = value & mask;
          const upper = (value >> 4) & mask;
          [lower, upper]
        ''');
        expect(result.toString(), '6,13');
      });

      test('Check if bit is set', () {
        final result = interpreter.eval('''
          function isBitSet(num, bit) {
            return (num & (1 << bit)) !== 0;
          }
          [isBitSet(0b1010, 0), isBitSet(0b1010, 1), isBitSet(0b1010, 2), isBitSet(0b1010, 3)]
        ''');
        expect(result.toString(), 'false,true,false,true');
      });

      test('Set specific bit', () {
        final result = interpreter.eval('''
          function setBit(num, bit) {
            return num | (1 << bit);
          }
          setBit(0b1000, 1)
        ''');
        expect(result.toNumber(), 10); // 0b1010
      });

      test('Clear specific bit', () {
        final result = interpreter.eval('''
          function clearBit(num, bit) {
            return num & ~(1 << bit);
          }
          clearBit(0b1111, 2)
        ''');
        expect(result.toNumber(), 11); // 0b1011
      });

      test('Toggle specific bit', () {
        final result = interpreter.eval('''
          function toggleBit(num, bit) {
            return num ^ (1 << bit);
          }
          [toggleBit(0b1010, 0), toggleBit(0b1010, 1)]
        ''');
        expect(result.toString(), '11,8'); // [0b1011, 0b1000]
      });
    });

    group('Operator precedence', () {
      test('Shift has higher precedence than comparison', () {
        final result = interpreter.eval('2 << 3 > 10');
        expect(result.isTruthy, true); // (2 << 3) > 10 = 16 > 10
      });

      test('Bitwise AND higher than bitwise OR', () {
        final result = interpreter.eval('1 | 2 & 4');
        expect(result.toNumber(), 1); // 1 | (2 & 4) = 1 | 0
      });

      test('Bitwise operators lower than arithmetic', () {
        final result = interpreter.eval('3 + 5 & 4');
        expect(result.toNumber(), 0); // (3 + 5) & 4 = 8 & 4
      });

      test('XOR between AND and OR', () {
        final result = interpreter.eval('8 | 4 ^ 2 & 3');
        expect(
          result.toNumber(),
          14,
        ); // 8 | (4 ^ (2 & 3)) = 8 | (4 ^ 2) = 8 | 6 = 14
      });
    });

    group('BigInt bitwise operations', () {
      test('BigInt AND', () {
        final result = interpreter.eval('0b1111n & 0b1010n');
        expect(result.toString(), '10n'); // 0b1010n
      });

      test('BigInt OR', () {
        final result = interpreter.eval('0b1100n | 0b0011n');
        expect(result.toString(), '15n'); // 0b1111n
      });

      test('BigInt XOR', () {
        final result = interpreter.eval('0b1100n ^ 0b1010n');
        expect(result.toString(), '6n'); // 0b0110n
      });

      test('BigInt NOT', () {
        final result = interpreter.eval('~5n');
        expect(result.toString(), '-6n');
      });

      test('BigInt left shift', () {
        final result = interpreter.eval('5n << 10n');
        expect(result.toString(), '5120n'); // 5 * 1024
      });

      test('BigInt right shift', () {
        final result = interpreter.eval('1024n >> 2n');
        expect(result.toString(), '256n');
      });

      test('BigInt large shift', () {
        final result = interpreter.eval('1n << 100n');
        expect(result.toString(), '1267650600228229401496703205376n');
      });
    });

    group('Edge cases', () {
      test('NaN becomes 0', () {
        final result = interpreter.eval('NaN & 0xFF');
        expect(result.toNumber(), 0);
      });

      test('Infinity becomes 0', () {
        final result = interpreter.eval('Infinity | 0');
        expect(result.toNumber(), 0);
      });

      test('Float truncated to int', () {
        final result = interpreter.eval('3.7 | 0');
        expect(result.toNumber(), 3);
      });

      test('Negative float truncated', () {
        final result = interpreter.eval('-3.7 | 0');
        expect(result.toNumber(), -3);
      });

      test('Very large number wrapped', () {
        final result = interpreter.eval('0xFFFFFFFF | 0');
        expect(result.toNumber(), -1);
      });
    });

    group('Real-world patterns', () {
      test('Extract RGB components', () {
        final result = interpreter.eval('''
          const color = 0xFF8040;
          const r = (color >> 16) & 0xFF;
          const g = (color >> 8) & 0xFF;
          const b = color & 0xFF;
          [r, g, b]
        ''');
        expect(result.toString(), '255,128,64');
      });

      test('Flags management', () {
        final result = interpreter.eval('''
          const FLAG_READ = 1 << 0;
          const FLAG_WRITE = 1 << 1;
          const FLAG_EXECUTE = 1 << 2;
          
          let permissions = 0;
          permissions |= FLAG_READ;
          permissions |= FLAG_WRITE;
          
          const canRead = (permissions & FLAG_READ) !== 0;
          const canWrite = (permissions & FLAG_WRITE) !== 0;
          const canExecute = (permissions & FLAG_EXECUTE) !== 0;
          
          [canRead, canWrite, canExecute]
        ''');
        expect(result.toString(), 'true,true,false');
      });

      test('Fast integer division by 2', () {
        final result = interpreter.eval('100 >> 1');
        expect(result.toNumber(), 50);
      });

      test('Fast modulo power of 2', () {
        final result = interpreter.eval('27 & 7');
        expect(result.toNumber(), 3); // 27 % 8
      });

      test('Check if number is power of 2', () {
        final result = interpreter.eval('''
          function isPowerOf2(n) {
            return n > 0 && (n & (n - 1)) === 0;
          }
          [isPowerOf2(16), isPowerOf2(15), isPowerOf2(64), isPowerOf2(63)]
        ''');
        expect(result.toString(), 'true,false,true,false');
      });
    });
  });
}
