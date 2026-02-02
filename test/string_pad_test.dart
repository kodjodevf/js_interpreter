import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('String.prototype.padStart() Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('padStart() with default space padding', () {
      final code = '''
        var str = 'abc';
        str.padStart(10)
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('       abc'));
      expect(result.toString().length, equals(10));
    });

    test('padStart() with custom padding string', () {
      final code = '''
        var str = '5';
        str.padStart(3, '0')
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('005'));
    });

    test('padStart() with multi-character padding', () {
      final code = '''
        var str = 'abc';
        str.padStart(10, 'foo')
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('foofoofabc'));
      expect(result.toString().length, equals(10));
    });

    test('padStart() when string is already long enough', () {
      final code = '''
        var str = 'abc';
        str.padStart(2)
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('abc'));
    });

    test('padStart() with exact length match', () {
      final code = '''
        var str = 'abc';
        str.padStart(3)
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('abc'));
    });

    test('padStart() with empty padString', () {
      final code = '''
        var str = 'abc';
        str.padStart(10, '')
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('abc'));
    });

    test('padStart() with undefined padString (uses space)', () {
      final code = '''
        var str = 'abc';
        str.padStart(5, undefined)
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('  abc'));
    });

    test('padStart() for credit card formatting', () {
      final code = '''
        var last4 = '1234';
        last4.padStart(16, '*')
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('************1234'));
    });

    test('padStart() with long padding string', () {
      final code = '''
        var str = 'test';
        str.padStart(10, '0123456789')
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('012345test'));
      expect(result.toString().length, equals(10));
    });

    test('padStart() with non-string gets converted', () {
      final code = '''
        var str = '5';
        str.padStart(3, 0)
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('005'));
    });
  });

  group('String.prototype.padEnd() Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('padEnd() with default space padding', () {
      final code = '''
        var str = 'abc';
        str.padEnd(10)
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('abc       '));
      expect(result.toString().length, equals(10));
    });

    test('padEnd() with custom padding string', () {
      final code = '''
        var str = '5';
        str.padEnd(3, '0')
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('500'));
    });

    test('padEnd() with multi-character padding', () {
      final code = '''
        var str = 'abc';
        str.padEnd(10, 'foo')
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('abcfoofoof'));
      expect(result.toString().length, equals(10));
    });

    test('padEnd() when string is already long enough', () {
      final code = '''
        var str = 'abc';
        str.padEnd(2)
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('abc'));
    });

    test('padEnd() with exact length match', () {
      final code = '''
        var str = 'abc';
        str.padEnd(3)
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('abc'));
    });

    test('padEnd() with empty padString', () {
      final code = '''
        var str = 'abc';
        str.padEnd(10, '')
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('abc'));
    });

    test('padEnd() with undefined padString (uses space)', () {
      final code = '''
        var str = 'abc';
        str.padEnd(5, undefined)
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('abc  '));
    });

    test('padEnd() for table column formatting', () {
      final code = '''
        var name = 'John';
        name.padEnd(10, '.')
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('John......'));
    });

    test('padEnd() with long padding string', () {
      final code = '''
        var str = 'test';
        str.padEnd(10, '0123456789')
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('test012345'));
      expect(result.toString().length, equals(10));
    });

    test('padEnd() with non-string gets converted', () {
      final code = '''
        var str = '5';
        str.padEnd(3, 0)
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('500'));
    });
  });

  group('String padding Combined Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('padStart() and padEnd() chained', () {
      final code = '''
        var str = 'abc';
        str.padStart(6, '-').padEnd(10, '-')
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('---abc----'));
    });

    test('Formatting table with both pad methods', () {
      final code = '''
        var name = 'Alice';
        var age = '30';
        var line1 = name.padEnd(10, ' ') + age.padStart(5, ' ');
        var line2 = 'Bob'.padEnd(10, ' ') + '25'.padStart(5, ' ');
        [line1, line2]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toString(), equals('Alice        30'));
      expect(result.elements[1].toString(), equals('Bob          25'));
    });

    test('padStart with various targetLengths', () {
      final code = '''
        var str = 'test';
        [
          str.padStart(0, 'x'),
          str.padStart(1, 'x'),
          str.padStart(4, 'x'),
          str.padStart(5, 'x'),
          str.padStart(10, 'x')
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toString(), equals('test')); // 0: no padding
      expect(result.elements[1].toString(), equals('test')); // 1: too short
      expect(result.elements[2].toString(), equals('test')); // 4: exact
      expect(result.elements[3].toString(), equals('xtest')); // 5: one char
      expect(
        result.elements[4].toString(),
        equals('xxxxxxtest'),
      ); // 10: six chars
    });

    test('padEnd with various targetLengths', () {
      final code = '''
        var str = 'test';
        [
          str.padEnd(0, 'x'),
          str.padEnd(1, 'x'),
          str.padEnd(4, 'x'),
          str.padEnd(5, 'x'),
          str.padEnd(10, 'x')
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toString(), equals('test')); // 0: no padding
      expect(result.elements[1].toString(), equals('test')); // 1: too short
      expect(result.elements[2].toString(), equals('test')); // 4: exact
      expect(result.elements[3].toString(), equals('testx')); // 5: one char
      expect(
        result.elements[4].toString(),
        equals('testxxxxxx'),
      ); // 10: six chars
    });

    test('Real-world use case: formatting decimal numbers', () {
      final code = '''
        function formatDecimal(num, decimals) {
          var str = num.toString();
          var parts = str.split('.');
          var whole = parts[0];
          var decimal = parts[1] || '';
          
          // Pad the decimal part with zeros
          decimal = decimal.padEnd(decimals, '0');
          
          return whole + '.' + decimal;
        }
        
        [
          formatDecimal(3.14, 4),
          formatDecimal(10, 2),
          formatDecimal(2.5, 3)
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toString(), equals('3.1400'));
      expect(result.elements[1].toString(), equals('10.00'));
      expect(result.elements[2].toString(), equals('2.500'));
    });

    test('Empty string padding', () {
      final code = '''
        var empty = '';
        [
          empty.padStart(5, 'x'),
          empty.padEnd(5, 'y')
        ]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toString(), equals('xxxxx'));
      expect(result.elements[1].toString(), equals('yyyyy'));
    });
  });
}
