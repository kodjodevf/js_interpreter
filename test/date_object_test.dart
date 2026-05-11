import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Date Object Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Date constructor without arguments', () {
      final result = interpreter.eval('new Date()');
      expect(result.type.name, equals('object'));
      expect(result.toString(), contains('202')); // Should contain current year
    });

    test('Date.now() static method', () {
      final result = interpreter.eval('Date.now()');
      expect(result.type.name, equals('number'));
      expect(
        result.toNumber(),
        greaterThan(1000000000000),
      ); // Should be a recent timestamp
    });

    test('Date.parse() static method', () {
      final result = interpreter.eval('Date.parse("2023-01-01")');
      expect(result.type.name, equals('number'));
      expect(
        result.toNumber(),
        equals(DateTime.utc(2023, 1, 1).millisecondsSinceEpoch.toDouble()),
      );
    });

    test('Date.parse() date-only ISO strings use UTC semantics', () {
      final result = interpreter.eval('''
        Date.parse("2023-01-01") === Date.UTC(2023, 0, 1)
      ''');

      expect(result.toBoolean(), isTrue);
    });

    test('Date with timestamp constructor', () {
      final result = interpreter.eval('new Date(1672531200000)'); // 2023-01-01
      expect(result.toString(), contains('2023'));
    });

    test('Date instance methods', () {
      interpreter.eval(
        'var d = new Date(2023, 0, 15, 10, 30, 45);',
      ); // Note: month is 0-based in JS

      final year = interpreter.eval('d.getFullYear()');
      expect(year.toNumber(), equals(2023));

      final month = interpreter.eval('d.getMonth()');
      expect(month.toNumber(), equals(0)); // January = 0

      final date = interpreter.eval('d.getDate()');
      expect(date.toNumber(), equals(15));

      final hours = interpreter.eval('d.getHours()');
      expect(hours.toNumber(), equals(10));
    });

    test('Date.prototype.toString()', () {
      final result = interpreter.eval('new Date(2023, 0, 1).toString()');
      expect(result.toString(), contains('2023'));
    });

    test('Date.prototype.getTime()', () {
      final result = interpreter.eval('new Date(2023, 0, 1).getTime()');
      expect(result.type.name, equals('number'));
    });

    test('Date.prototype.toISOString()', () {
      final result = interpreter.eval(
        'new Date("2023-01-01T00:00:00.000Z").toISOString()',
      );
      expect(result.toString(), equals('2023-01-01T00:00:00.000Z'));
    });

    test('Date.prototype.toJSON()', () {
      final result = interpreter.eval(
        'new Date("2023-01-01T00:00:00.000Z").toJSON()',
      );
      expect(result.toString(), equals('2023-01-01T00:00:00.000Z'));
    });

    test('Date.UTC preserves floating-point cancellation precision', () {
      final result = interpreter.eval(
        'Date.UTC(1970, 0, 213503982336, 0, 0, 0, -18446744073709552000)',
      );
      expect(result.toNumber(), equals(34447360));
    });

    test('Date arithmetic', () {
      final result = interpreter.eval('''
        var d1 = new Date(2023, 0, 1);
        var d2 = new Date(2023, 0, 2);
        d2.getTime() - d1.getTime();
      ''');
      expect(result.toNumber(), equals(86400000)); // 1 day in milliseconds
    });

    test('Invalid Date', () {
      final result = interpreter.eval('new Date("invalid")');
      expect(result.toString(), equals('Invalid Date'));
    });

    test('Date.prototype.getYear is installed on the shared prototype', () {
      final result = interpreter.eval('''
        typeof Date.prototype.getYear === 'function' &&
        new Date(2001, 0, 1).getYear() === 101
      ''');

      expect(result.toBoolean(), isTrue);
    });

    test('Date.prototype.setYear uses MakeFullYear semantics', () {
      final result = interpreter.eval('''
        const d = new Date(0);
        const timestamp = d.setYear(1);
        d.getYear() === 1 && timestamp === d.getTime();
      ''');

      expect(result.toBoolean(), isTrue);
    });

    test('Date.prototype.getYear throws on incompatible receiver', () {
      final result = interpreter.eval('''
        try {
          Date.prototype.getYear.call({});
          false;
        } catch (error) {
          error instanceof TypeError;
        }
      ''');

      expect(result.toBoolean(), isTrue);
    });

    test('Date.prototype.toGMTString formats as GMT', () {
      final result = interpreter.eval('''
        new Date('2023-01-01T00:00:00.000Z').toGMTString()
      ''');

      expect(result.toString(), equals('Sun, 01 Jan 2023 00:00:00 GMT'));
    });
  });
}
