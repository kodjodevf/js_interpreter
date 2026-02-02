import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Number Constants Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Number.EPSILON constant', () {
      final code = '''
        [
          Number.EPSILON,
          typeof Number.EPSILON,
          Number.EPSILON > 0,
          Number.EPSILON < 1
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(2.220446049250313e-16));
      expect(result.elements[1].toString(), equals('number'));
      expect(result.elements[2].toBoolean(), equals(true));
      expect(result.elements[3].toBoolean(), equals(true));
    });

    test('Number.MAX_SAFE_INTEGER constant', () {
      final code = '''
        [
          Number.MAX_SAFE_INTEGER,
          Number.MAX_SAFE_INTEGER === 9007199254740991,
          Number.MAX_SAFE_INTEGER === Math.pow(2, 53) - 1
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(9007199254740991));
      expect(result.elements[1].toBoolean(), equals(true));
      expect(result.elements[2].toBoolean(), equals(true));
    });

    test('Number.MIN_SAFE_INTEGER constant', () {
      final code = '''
        [
          Number.MIN_SAFE_INTEGER,
          Number.MIN_SAFE_INTEGER === -9007199254740991,
          Number.MIN_SAFE_INTEGER === -(Math.pow(2, 53) - 1)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(-9007199254740991));
      expect(result.elements[1].toBoolean(), equals(true));
      expect(result.elements[2].toBoolean(), equals(true));
    });

    test('All Number constants exist', () {
      final code = '''
        [
          typeof Number.EPSILON !== 'undefined',
          typeof Number.MAX_SAFE_INTEGER !== 'undefined',
          typeof Number.MIN_SAFE_INTEGER !== 'undefined',
          typeof Number.MAX_VALUE !== 'undefined',
          typeof Number.MIN_VALUE !== 'undefined',
          typeof Number.POSITIVE_INFINITY !== 'undefined',
          typeof Number.NEGATIVE_INFINITY !== 'undefined',
          typeof Number.NaN !== 'undefined'
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      for (var i = 0; i < result.elements.length; i++) {
        expect(
          result.elements[i].toBoolean(),
          equals(true),
          reason: 'Constant at index $i should exist',
        );
      }
    });
  });

  group('Number.isNaN() Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Number.isNaN() with NaN', () {
      final code = '''
        [
          Number.isNaN(NaN),
          Number.isNaN(0 / 0),
          Number.isNaN(Number.NaN)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toBoolean(), equals(true));
      expect(result.elements[1].toBoolean(), equals(true));
      expect(result.elements[2].toBoolean(), equals(true));
    });

    test('Number.isNaN() with numbers', () {
      final code = '''
        [
          Number.isNaN(0),
          Number.isNaN(1),
          Number.isNaN(-1),
          Number.isNaN(3.14),
          Number.isNaN(Infinity),
          Number.isNaN(-Infinity)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      for (var i = 0; i < result.elements.length; i++) {
        expect(
          result.elements[i].toBoolean(),
          equals(false),
          reason: 'Number at index $i should not be NaN',
        );
      }
    });

    test('Number.isNaN() with non-numbers (different from global isNaN)', () {
      final code = '''
        [
          Number.isNaN('NaN'),
          Number.isNaN(undefined),
          Number.isNaN({}),
          Number.isNaN('string'),
          Number.isNaN(true),
          Number.isNaN(null)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      // Number.isNaN does NOT convert, unlike global isNaN
      for (var i = 0; i < result.elements.length; i++) {
        expect(
          result.elements[i].toBoolean(),
          equals(false),
          reason: 'Non-number at index $i should return false',
        );
      }
    });
  });

  group('Number.isFinite() Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Number.isFinite() with finite numbers', () {
      final code = '''
        [
          Number.isFinite(0),
          Number.isFinite(1),
          Number.isFinite(-1),
          Number.isFinite(3.14),
          Number.isFinite(Number.MAX_VALUE),
          Number.isFinite(Number.MIN_VALUE)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      for (var i = 0; i < result.elements.length; i++) {
        expect(
          result.elements[i].toBoolean(),
          equals(true),
          reason: 'Number at index $i should be finite',
        );
      }
    });

    test('Number.isFinite() with infinite values', () {
      final code = '''
        [
          Number.isFinite(Infinity),
          Number.isFinite(-Infinity),
          Number.isFinite(Number.POSITIVE_INFINITY),
          Number.isFinite(Number.NEGATIVE_INFINITY),
          Number.isFinite(NaN)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      for (var i = 0; i < result.elements.length; i++) {
        expect(
          result.elements[i].toBoolean(),
          equals(false),
          reason: 'Value at index $i should not be finite',
        );
      }
    });

    test('Number.isFinite() with non-numbers', () {
      final code = '''
        [
          Number.isFinite('0'),
          Number.isFinite('123'),
          Number.isFinite(null),
          Number.isFinite(true),
          Number.isFinite(false)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      // Number.isFinite does NOT convert, unlike global isFinite
      for (var i = 0; i < result.elements.length; i++) {
        expect(
          result.elements[i].toBoolean(),
          equals(false),
          reason: 'Non-number at index $i should return false',
        );
      }
    });
  });

  group('Number.isInteger() Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Number.isInteger() with integers', () {
      final code = '''
        [
          Number.isInteger(0),
          Number.isInteger(1),
          Number.isInteger(-1),
          Number.isInteger(100),
          Number.isInteger(-100),
          Number.isInteger(1000000)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      for (var i = 0; i < result.elements.length; i++) {
        expect(
          result.elements[i].toBoolean(),
          equals(true),
          reason: 'Value at index $i should be integer',
        );
      }
    });

    test('Number.isInteger() with floats', () {
      final code = '''
        [
          Number.isInteger(0.1),
          Number.isInteger(1.5),
          Number.isInteger(-1.5),
          Number.isInteger(3.14),
          Number.isInteger(Math.PI)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      for (var i = 0; i < result.elements.length; i++) {
        expect(
          result.elements[i].toBoolean(),
          equals(false),
          reason: 'Value at index $i should not be integer',
        );
      }
    });

    test('Number.isInteger() with special values', () {
      final code = '''
        [
          Number.isInteger(NaN),
          Number.isInteger(Infinity),
          Number.isInteger(-Infinity)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toBoolean(), equals(false)); // NaN
      expect(result.elements[1].toBoolean(), equals(false)); // Infinity
      expect(result.elements[2].toBoolean(), equals(false)); // -Infinity
    });

    test('Number.isInteger() with non-numbers', () {
      final code = '''
        [
          Number.isInteger('1'),
          Number.isInteger(true),
          Number.isInteger(false),
          Number.isInteger(null)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      for (var i = 0; i < result.elements.length; i++) {
        expect(
          result.elements[i].toBoolean(),
          equals(false),
          reason: 'Non-number at index $i should return false',
        );
      }
    });

    test('Number.isInteger() with floats that look like integers', () {
      final code = '''
        [
          Number.isInteger(1.0),
          Number.isInteger(5.0),
          Number.isInteger(-3.0)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      // 1.0, 5.0, -3.0 SONT des entiers en JavaScript
      for (var i = 0; i < result.elements.length; i++) {
        expect(
          result.elements[i].toBoolean(),
          equals(true),
          reason: 'Value at index $i should be integer (x.0 === x)',
        );
      }
    });
  });

  group('Number.isSafeInteger() Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Number.isSafeInteger() with safe integers', () {
      final code = '''
        [
          Number.isSafeInteger(0),
          Number.isSafeInteger(1),
          Number.isSafeInteger(-1),
          Number.isSafeInteger(100),
          Number.isSafeInteger(Number.MAX_SAFE_INTEGER),
          Number.isSafeInteger(Number.MIN_SAFE_INTEGER)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      for (var i = 0; i < result.elements.length; i++) {
        expect(
          result.elements[i].toBoolean(),
          equals(true),
          reason: 'Value at index $i should be safe integer',
        );
      }
    });

    test('Number.isSafeInteger() with unsafe integers', () {
      final code = '''
        [
          Number.isSafeInteger(Number.MAX_SAFE_INTEGER + 1),
          Number.isSafeInteger(Number.MIN_SAFE_INTEGER - 1),
          Number.isSafeInteger(9007199254740992),
          Number.isSafeInteger(-9007199254740992)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      for (var i = 0; i < result.elements.length; i++) {
        expect(
          result.elements[i].toBoolean(),
          equals(false),
          reason: 'Value at index $i should not be safe integer',
        );
      }
    });

    test('Number.isSafeInteger() with floats', () {
      final code = '''
        [
          Number.isSafeInteger(1.5),
          Number.isSafeInteger(3.14),
          Number.isSafeInteger(0.1)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      for (var i = 0; i < result.elements.length; i++) {
        expect(
          result.elements[i].toBoolean(),
          equals(false),
          reason: 'Float at index $i should not be safe integer',
        );
      }
    });

    test('Number.isSafeInteger() with special values', () {
      final code = '''
        [
          Number.isSafeInteger(NaN),
          Number.isSafeInteger(Infinity),
          Number.isSafeInteger(-Infinity)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      for (var i = 0; i < result.elements.length; i++) {
        expect(
          result.elements[i].toBoolean(),
          equals(false),
          reason: 'Special value at index $i should not be safe integer',
        );
      }
    });

    test('Number.isSafeInteger() with non-numbers', () {
      final code = '''
        [
          Number.isSafeInteger('1'),
          Number.isSafeInteger(true),
          Number.isSafeInteger(null)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      for (var i = 0; i < result.elements.length; i++) {
        expect(
          result.elements[i].toBoolean(),
          equals(false),
          reason: 'Non-number at index $i should return false',
        );
      }
    });
  });

  group('Number methods Combined Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Comparing Number.isNaN vs global isNaN', () {
      final code = '''
        var tests = [];
        
        // Avec NaN, les deux retournent true
        tests.push(Number.isNaN(NaN) === isNaN(NaN));
        
        // With '123' they differ: Number.isNaN returns false (no conversion)
        tests.push(Number.isNaN('123'));
        tests.push(isNaN('123'));
        
        // Avec 'hello', Number.isNaN retourne false, isNaN retourne true
        tests.push(Number.isNaN('hello'));
        tests.push(isNaN('hello'));
        
        tests
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(
        result.elements[0].toBoolean(),
        equals(true),
      ); // Both return true for NaN
      expect(
        result.elements[1].toBoolean(),
        equals(false),
      ); // Number.isNaN('123') = false
      expect(
        result.elements[2].toBoolean(),
        equals(false),
      ); // isNaN('123') = false (converts to 123)
      expect(
        result.elements[3].toBoolean(),
        equals(false),
      ); // Number.isNaN('hello') = false
      expect(
        result.elements[4].toBoolean(),
        equals(true),
      ); // isNaN('hello') = true (converts to NaN)
    });

    test('Safe integer boundaries', () {
      final code = '''
        var maxSafe = Number.MAX_SAFE_INTEGER;
        var minSafe = Number.MIN_SAFE_INTEGER;
        
        [
          Number.isSafeInteger(maxSafe),
          Number.isSafeInteger(maxSafe + 1),
          Number.isSafeInteger(minSafe),
          Number.isSafeInteger(minSafe - 1),
          maxSafe === 9007199254740991,
          minSafe === -9007199254740991
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toBoolean(), equals(true)); // maxSafe is safe
      expect(
        result.elements[1].toBoolean(),
        equals(false),
      ); // maxSafe+1 is not safe
      expect(result.elements[2].toBoolean(), equals(true)); // minSafe is safe
      expect(
        result.elements[3].toBoolean(),
        equals(false),
      ); // minSafe-1 is not safe
      expect(
        result.elements[4].toBoolean(),
        equals(true),
      ); // Verify maxSafe value
      expect(
        result.elements[5].toBoolean(),
        equals(true),
      ); // Verify minSafe value
    });

    test('Practical use case: validating user input', () {
      final code = '''
        function isValidAge(value) {
          return Number.isInteger(value) && value >= 0 && value <= 150;
        }
        
        function isValidId(value) {
          return Number.isSafeInteger(value) && value > 0;
        }
        
        [
          isValidAge(25),
          isValidAge(25.5),
          isValidAge(-5),
          isValidAge(200),
          isValidId(12345),
          isValidId(1.5),
          isValidId(-1),
          isValidId(Number.MAX_SAFE_INTEGER)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toBoolean(), equals(true)); // 25 is valid age
      expect(
        result.elements[1].toBoolean(),
        equals(false),
      ); // 25.5 is not integer
      expect(result.elements[2].toBoolean(), equals(false)); // -5 is negative
      expect(result.elements[3].toBoolean(), equals(false)); // 200 is too old
      expect(result.elements[4].toBoolean(), equals(true)); // 12345 is valid ID
      expect(
        result.elements[5].toBoolean(),
        equals(false),
      ); // 1.5 is not integer
      expect(result.elements[6].toBoolean(), equals(false)); // -1 is negative
      expect(
        result.elements[7].toBoolean(),
        equals(true),
      ); // MAX_SAFE_INTEGER is valid
    });

    test('EPSILON usage for float comparison', () {
      final code = '''
        function almostEqual(a, b) {
          return Math.abs(a - b) < Number.EPSILON;
        }
        
        [
          almostEqual(0.1 + 0.2, 0.3),
          0.1 + 0.2 === 0.3,
          Number.EPSILON > 0,
          Number.EPSILON < 0.0001
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      // Note: 0.1 + 0.2 !== 0.3 in JavaScript due to floating point precision
      expect(
        result.elements[1].toBoolean(),
        equals(false),
      ); // Direct comparison fails
      expect(result.elements[2].toBoolean(), equals(true)); // EPSILON > 0
      expect(
        result.elements[3].toBoolean(),
        equals(true),
      ); // EPSILON is very small
    });
  });
}
