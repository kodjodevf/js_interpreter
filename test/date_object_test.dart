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
        equals(DateTime.parse("2023-01-01").millisecondsSinceEpoch.toDouble()),
      );
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
  });
}
