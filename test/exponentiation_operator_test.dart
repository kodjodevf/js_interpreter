import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });

  group('Exponentiation Operator (**) - Basic Operations', () {
    test('basic exponentiation', () {
      final code = '''
        const result = 2 ** 3;
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(8));
    });

    test('exponentiation with variables', () {
      final code = '''
        const base = 5;
        const exp = 2;
        const result = base ** exp;
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(25));
    });

    test('exponentiation with decimals', () {
      final code = '''
        const result = 2.5 ** 2;
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(6.25));
    });

    test('exponentiation with zero exponent', () {
      final code = '''
        const result = 5 ** 0;
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(1));
    });

    test('exponentiation with negative base', () {
      final code = '''
        const result = (-2) ** 3;
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(-8));
    });

    test('exponentiation with negative exponent', () {
      final code = '''
        const result = 2 ** -3;
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), closeTo(0.125, 0.0001));
    });

    test('exponentiation with fractional exponent', () {
      final code = '''
        const result = 9 ** 0.5;
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(3.0));
    });

    test('zero to the power of zero', () {
      final code = '''
        const result = 0 ** 0;
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(1));
    });
  });

  group('Exponentiation Operator (**) - Right Associativity', () {
    test('right associativity basic', () {
      final code = '''
        const result = 2 ** 3 ** 2;
        result;
      ''';
      final result = interpreter.eval(code);
      // 2 ** (3 ** 2) = 2 ** 9 = 512, NOT (2 ** 3) ** 2 = 8 ** 2 = 64
      expect(result.toNumber(), equals(512));
    });

    test('right associativity complex', () {
      final code = '''
        const result = 2 ** 2 ** 3;
        result;
      ''';
      final result = interpreter.eval(code);
      // 2 ** (2 ** 3) = 2 ** 8 = 256
      expect(result.toNumber(), equals(256));
    });

    test('right associativity with parentheses', () {
      final code = '''
        const result = (2 ** 3) ** 2;
        result;
      ''';
      final result = interpreter.eval(code);
      // (2 ** 3) ** 2 = 8 ** 2 = 64
      expect(result.toNumber(), equals(64));
    });

    test('multiple exponentiations', () {
      final code = '''
        const result = 2 ** 2 ** 2 ** 2;
        result;
      ''';
      final result = interpreter.eval(code);
      // 2 ** (2 ** (2 ** 2)) = 2 ** (2 ** 4) = 2 ** 16 = 65536
      expect(result.toNumber(), equals(65536));
    });
  });

  group('Exponentiation Operator (**) - Precedence', () {
    test('precedence with multiplication', () {
      final code = '''
        const result = 2 * 3 ** 2;
        result;
      ''';
      final result = interpreter.eval(code);
      // 2 * (3 ** 2) = 2 * 9 = 18
      expect(result.toNumber(), equals(18));
    });

    test('precedence with division', () {
      final code = '''
        const result = 100 / 2 ** 2;
        result;
      ''';
      final result = interpreter.eval(code);
      // 100 / (2 ** 2) = 100 / 4 = 25
      expect(result.toNumber(), equals(25));
    });

    test('precedence with addition', () {
      final code = '''
        const result = 2 + 3 ** 2;
        result;
      ''';
      final result = interpreter.eval(code);
      // 2 + (3 ** 2) = 2 + 9 = 11
      expect(result.toNumber(), equals(11));
    });

    test('precedence with subtraction', () {
      final code = '''
        const result = 20 - 2 ** 3;
        result;
      ''';
      final result = interpreter.eval(code);
      // 20 - (2 ** 3) = 20 - 8 = 12
      expect(result.toNumber(), equals(12));
    });

    test('complex expression with mixed operators', () {
      final code = '''
        const result = 2 * 3 ** 2 + 4;
        result;
      ''';
      final result = interpreter.eval(code);
      // 2 * (3 ** 2) + 4 = 2 * 9 + 4 = 18 + 4 = 22
      expect(result.toNumber(), equals(22));
    });
  });

  group('Exponentiation Operator (**) - With Unary Operators', () {
    test('unary minus before base', () {
      final code = '''
        const result = (-2) ** 4;
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(16));
    });

    test('unary minus after exponent', () {
      final code = '''
        const result = 2 ** -2;
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(0.25));
    });

    test('unary plus with exponentiation', () {
      final code = '''
        const result = (+3) ** 2;
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(9));
    });
  });

  group('Exponentiation Assignment Operator (**=)', () {
    test('basic exponentiation assignment', () {
      final code = '''
        let x = 2;
        x **= 3;
        x;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(8));
    });

    test('exponentiation assignment with variables', () {
      final code = '''
        let base = 5;
        let exp = 2;
        base **= exp;
        base;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(25));
    });

    test('exponentiation assignment multiple times', () {
      final code = '''
        let x = 2;
        x **= 2;
        x **= 2;
        x;
      ''';
      final result = interpreter.eval(code);
      // x = 2, then x = 2 ** 2 = 4, then x = 4 ** 2 = 16
      expect(result.toNumber(), equals(16));
    });

    test('exponentiation assignment with decimals', () {
      final code = '''
        let x = 3;
        x **= 0.5;
        x;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), closeTo(1.732, 0.001));
    });

    test('exponentiation assignment returns value', () {
      final code = '''
        let x = 2;
        const result = (x **= 3);
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(8));
    });

    test('exponentiation assignment with object property', () {
      final code = '''
        const obj = { value: 2 };
        obj.value **= 3;
        obj.value;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(8));
    });

    test('exponentiation assignment with array element', () {
      final code = '''
        const arr = [2, 3, 4];
        arr[1] **= 2;
        arr[1];
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(9));
    });
  });

  group('Exponentiation Operator (**) - Edge Cases', () {
    test('Infinity to positive power', () {
      final code = '''
        const result = Infinity ** 2;
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(double.infinity));
    });

    test('Infinity to zero power', () {
      final code = '''
        const result = Infinity ** 0;
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(1));
    });

    test('NaN exponentiation', () {
      final code = '''
        const result = NaN ** 2;
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber().isNaN, isTrue);
    });

    test('any number to NaN power', () {
      final code = '''
        const result = 5 ** NaN;
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber().isNaN, isTrue);
    });

    test('1 to any power is 1', () {
      final code = '''
        const result = 1 ** 999999;
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(1));
    });

    test('large exponentiation', () {
      final code = '''
        const result = 10 ** 6;
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(1000000));
    });
  });

  group('Exponentiation Operator (**) - With Functions', () {
    test('exponentiation in function return', () {
      final code = '''
        function power(base, exp) {
          return base ** exp;
        }
        power(3, 4);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(81));
    });

    test('exponentiation in arrow function', () {
      final code = '''
        const power = (base, exp) => base ** exp;
        power(2, 8);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(256));
    });

    test('exponentiation with Math.pow comparison', () {
      final code = '''
        const a = 2 ** 10;
        const b = Math.pow(2, 10);
        a === b;
      ''';
      final result = interpreter.eval(code);
      expect(result.toBoolean(), isTrue);
    });
  });

  group('Exponentiation Operator (**) - In Expressions', () {
    test('exponentiation in ternary operator', () {
      final code = '''
        const x = 5;
        const result = x > 3 ? 2 ** x : x ** 2;
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(32));
    });

    test('exponentiation in array', () {
      final code = '''
        const arr = [2 ** 2, 3 ** 2, 4 ** 2];
        arr;
      ''';
      final result = interpreter.eval(code);
      final array = result.toObject() as JSArray;
      expect(array.elements[0].toNumber(), equals(4));
      expect(array.elements[1].toNumber(), equals(9));
      expect(array.elements[2].toNumber(), equals(16));
    });

    test('exponentiation in object literal', () {
      final code = '''
        const obj = {
          square: 5 ** 2,
          cube: 5 ** 3
        };
        obj.square + obj.cube;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(150)); // 25 + 125
    });

    test('exponentiation with comparison', () {
      final code = '''
        const result = 2 ** 3 > 5;
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toBoolean(), isTrue);
    });
  });

  group('Exponentiation Operator (**) - With BigInt', () {
    test('BigInt exponentiation', () {
      final code = '''
        const result = 2n ** 10n;
        result;
      ''';
      final result = interpreter.eval(code);
      expect((result as JSBigInt).value, equals(BigInt.from(1024)));
    });

    test('BigInt large exponentiation', () {
      final code = '''
        const result = 2n ** 100n;
        result > 1000000000000000000000000000000n;
      ''';
      final result = interpreter.eval(code);
      expect(result.toBoolean(), isTrue);
    });

    test('BigInt exponentiation assignment', () {
      final code = '''
        let x = 3n;
        x **= 5n;
        x;
      ''';
      final result = interpreter.eval(code);
      expect((result as JSBigInt).value, equals(BigInt.from(243)));
    });
  });

  group('Exponentiation Operator (**) - Practical Examples', () {
    test('calculate compound interest', () {
      final code = '''
        function compoundInterest(principal, rate, years) {
          return principal * (1 + rate) ** years;
        }
        compoundInterest(1000, 0.05, 10);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), closeTo(1628.89, 0.01));
    });

    test('calculate area of circle', () {
      final code = '''
        function circleArea(radius) {
          const pi = 3.14159;
          return pi * radius ** 2;
        }
        circleArea(5);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), closeTo(78.54, 0.01));
    });

    test('fibonacci using exponentiation', () {
      final code = '''
        function fibonacci(n) {
          const phi = (1 + 5 ** 0.5) / 2;
          return Math.round((phi ** n) / 5 ** 0.5);
        }
        fibonacci(10);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(55));
    });

    test('binary to decimal conversion', () {
      final code = '''
        function binaryToDecimal(binary) {
          let result = 0;
          const digits = binary.split('').reverse();
          for (let i = 0; i < digits.length; i++) {
            result += parseInt(digits[i]) * (2 ** i);
          }
          return result;
        }
        binaryToDecimal('1010');
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(10));
    });

    test('exponential growth simulation', () {
      final code = '''
        function exponentialGrowth(initial, rate, time) {
          return initial * (2 ** (rate * time));
        }
        exponentialGrowth(100, 0.5, 4);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(400));
    });
  });
}
