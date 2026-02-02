import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Array.prototype.at() Implementation', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Array.prototype.at() with positive indices', () {
      final result = interpreter.eval('''
        const arr = [10, 20, 30, 40, 50];
        [arr.at(0), arr.at(2), arr.at(4)]
      ''');

      final results = (result as JSArray).elements;
      expect(results[0].toString(), equals('10'));
      expect(results[1].toString(), equals('30'));
      expect(results[2].toString(), equals('50'));
    });

    test('Array.prototype.at() with negative indices', () {
      final result = interpreter.eval('''
        const arr = [10, 20, 30, 40, 50];
        [arr.at(-1), arr.at(-2), arr.at(-5)]
      ''');

      final results = (result as JSArray).elements;
      expect(results[0].toString(), equals('50')); // -1 = last element
      expect(results[1].toString(), equals('40')); // -2 = second to last
      expect(results[2].toString(), equals('10')); // -5 = first element
    });

    test('Array.prototype.at() with out of bounds indices', () {
      final result = interpreter.eval('''
        const arr = [10, 20, 30];
        [arr.at(10), arr.at(-10)]
      ''');

      final results = (result as JSArray).elements;
      expect(
        results[0].toString(),
        equals('undefined'),
      ); // index 10 is out of bounds
      expect(
        results[1].toString(),
        equals('undefined'),
      ); // index -10 is out of bounds
    });

    test('Array.prototype.at() handles non-numeric index via ToNumber', () {
      // Per ES spec, at() calls ToInteger which converts non-numeric to number
      // "invalid" -> NaN -> 0
      final result = interpreter.eval('[1, 2, 3].at("invalid")');
      expect(
        result.toNumber(),
        equals(1),
      ); // NaN converts to 0, returns first element
    });

    test('Array.prototype.at() works when no argument provided', () {
      // Per ES spec, undefined -> NaN -> 0
      final result = interpreter.eval('[1, 2, 3].at()');
      expect(
        result.toNumber(),
        equals(1),
      ); // undefined -> NaN -> 0, returns first element
    });
  });
}
