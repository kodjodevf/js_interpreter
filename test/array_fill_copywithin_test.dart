import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Array.prototype.fill() Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('fill() with single value', () {
      final code = '''
        var arr = [1, 2, 3, 4, 5];
        arr.fill(0);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(5));
      for (int i = 0; i < 5; i++) {
        expect(result.elements[i].toNumber(), equals(0));
      }
    });

    test('fill() with start index', () {
      final code = '''
        var arr = [1, 2, 3, 4, 5];
        arr.fill(0, 2);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(5));
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(2));
      expect(result.elements[2].toNumber(), equals(0));
      expect(result.elements[3].toNumber(), equals(0));
      expect(result.elements[4].toNumber(), equals(0));
    });

    test('fill() with start and end indices', () {
      final code = '''
        var arr = [1, 2, 3, 4, 5];
        arr.fill(0, 1, 3);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(5));
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(0));
      expect(result.elements[2].toNumber(), equals(0));
      expect(result.elements[3].toNumber(), equals(4));
      expect(result.elements[4].toNumber(), equals(5));
    });

    test('fill() with negative start index', () {
      final code = '''
        var arr = [1, 2, 3, 4, 5];
        arr.fill(0, -3);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(5));
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(2));
      expect(result.elements[2].toNumber(), equals(0));
      expect(result.elements[3].toNumber(), equals(0));
      expect(result.elements[4].toNumber(), equals(0));
    });

    test('fill() with negative end index', () {
      final code = '''
        var arr = [1, 2, 3, 4, 5];
        arr.fill(0, 1, -1);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(5));
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(0));
      expect(result.elements[2].toNumber(), equals(0));
      expect(result.elements[3].toNumber(), equals(0));
      expect(result.elements[4].toNumber(), equals(5));
    });

    test('fill() returns the array', () {
      final code = '''
        var arr = [1, 2, 3];
        var result = arr.fill(0);
        result === arr
      ''';

      final result = interpreter.eval(code);
      expect(result.toBoolean(), equals(true));
    });

    test('fill() with string value', () {
      final code = '''
        var arr = [1, 2, 3, 4, 5];
        arr.fill('a', 1, 4);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toString(), equals('a'));
      expect(result.elements[2].toString(), equals('a'));
      expect(result.elements[3].toString(), equals('a'));
      expect(result.elements[4].toNumber(), equals(5));
    });

    test('fill() with object value', () {
      final code = '''
        var arr = [1, 2, 3];
        var obj = {value: 42};
        arr.fill(obj);
        [arr[0] === arr[1], arr[1] === arr[2], arr[0].value]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toBoolean(), equals(true)); // Same reference
      expect(result.elements[1].toBoolean(), equals(true)); // Same reference
      expect(result.elements[2].toNumber(), equals(42));
    });

    test('fill() with empty array', () {
      final code = '''
        var arr = [];
        arr.fill(1, 0, 0);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(0));
    });

    test('fill() with start > end does nothing', () {
      final code = '''
        var arr = [1, 2, 3];
        arr.fill(0, 2, 1);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(2));
      expect(result.elements[2].toNumber(), equals(3));
    });
  });

  group('Array.prototype.copyWithin() Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('copyWithin() basic copy', () {
      final code = '''
        var arr = [1, 2, 3, 4, 5];
        arr.copyWithin(0, 3);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(5));
      expect(result.elements[0].toNumber(), equals(4));
      expect(result.elements[1].toNumber(), equals(5));
      expect(result.elements[2].toNumber(), equals(3));
      expect(result.elements[3].toNumber(), equals(4));
      expect(result.elements[4].toNumber(), equals(5));
    });

    test('copyWithin() with start and end', () {
      final code = '''
        var arr = [1, 2, 3, 4, 5];
        arr.copyWithin(0, 3, 4);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(5));
      expect(result.elements[0].toNumber(), equals(4));
      expect(result.elements[1].toNumber(), equals(2));
      expect(result.elements[2].toNumber(), equals(3));
      expect(result.elements[3].toNumber(), equals(4));
      expect(result.elements[4].toNumber(), equals(5));
    });

    test('copyWithin() copy to middle', () {
      final code = '''
        var arr = [1, 2, 3, 4, 5];
        arr.copyWithin(2, 0, 2);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(2));
      expect(result.elements[2].toNumber(), equals(1));
      expect(result.elements[3].toNumber(), equals(2));
      expect(result.elements[4].toNumber(), equals(5));
    });

    test('copyWithin() with negative target', () {
      final code = '''
        var arr = [1, 2, 3, 4, 5];
        arr.copyWithin(-2, 0);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(5));
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(2));
      expect(result.elements[2].toNumber(), equals(3));
      expect(result.elements[3].toNumber(), equals(1));
      expect(result.elements[4].toNumber(), equals(2));
    });

    test('copyWithin() with negative start', () {
      final code = '''
        var arr = [1, 2, 3, 4, 5];
        arr.copyWithin(0, -2);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(4));
      expect(result.elements[1].toNumber(), equals(5));
      expect(result.elements[2].toNumber(), equals(3));
      expect(result.elements[3].toNumber(), equals(4));
      expect(result.elements[4].toNumber(), equals(5));
    });

    test('copyWithin() with negative end', () {
      final code = '''
        var arr = [1, 2, 3, 4, 5];
        arr.copyWithin(0, 1, -1);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(2));
      expect(result.elements[1].toNumber(), equals(3));
      expect(result.elements[2].toNumber(), equals(4));
      expect(result.elements[3].toNumber(), equals(4));
      expect(result.elements[4].toNumber(), equals(5));
    });

    test('copyWithin() overlapping copy forward', () {
      final code = '''
        var arr = [1, 2, 3, 4, 5];
        arr.copyWithin(2, 0);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(2));
      expect(result.elements[2].toNumber(), equals(1));
      expect(result.elements[3].toNumber(), equals(2));
      expect(result.elements[4].toNumber(), equals(3));
    });

    test('copyWithin() overlapping copy backward', () {
      final code = '''
        var arr = [1, 2, 3, 4, 5];
        arr.copyWithin(0, 2);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(3));
      expect(result.elements[1].toNumber(), equals(4));
      expect(result.elements[2].toNumber(), equals(5));
      expect(result.elements[3].toNumber(), equals(4));
      expect(result.elements[4].toNumber(), equals(5));
    });

    test('copyWithin() returns the array', () {
      final code = '''
        var arr = [1, 2, 3];
        var result = arr.copyWithin(0, 1);
        result === arr
      ''';

      final result = interpreter.eval(code);
      expect(result.toBoolean(), equals(true));
    });

    test('copyWithin() with empty array', () {
      final code = '''
        var arr = [];
        arr.copyWithin(0, 0);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(0));
    });

    test('copyWithin() single element copy', () {
      final code = '''
        var arr = [1, 2, 3, 4, 5];
        arr.copyWithin(1, 3, 4);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(4));
      expect(result.elements[2].toNumber(), equals(3));
      expect(result.elements[3].toNumber(), equals(4));
      expect(result.elements[4].toNumber(), equals(5));
    });
  });

  group('Array.prototype fill() and copyWithin() Combined Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('fill() then copyWithin()', () {
      final code = '''
        var arr = [1, 2, 3, 4, 5];
        arr.fill(0, 2, 4);
        arr.copyWithin(0, 2);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      // After fill(0, 2, 4): [1, 2, 0, 0, 5]
      // After copyWithin(0, 2): copies [0, 0, 5] to position 0 => [0, 0, 5, 0, 5]
      expect(result.elements[0].toNumber(), equals(0));
      expect(result.elements[1].toNumber(), equals(0));
      expect(result.elements[2].toNumber(), equals(5));
      expect(result.elements[3].toNumber(), equals(0));
      expect(result.elements[4].toNumber(), equals(5));
    });

    test('copyWithin() then fill()', () {
      final code = '''
        var arr = [1, 2, 3, 4, 5];
        arr.copyWithin(2, 0, 2);
        arr.fill(9, 1, 3);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(1));
      expect(result.elements[1].toNumber(), equals(9));
      expect(result.elements[2].toNumber(), equals(9));
      expect(result.elements[3].toNumber(), equals(2));
      expect(result.elements[4].toNumber(), equals(5));
    });

    test('Chaining fill() and copyWithin()', () {
      final code = '''
        var arr = Array(10);
        arr.fill(1).fill(2, 3, 7).copyWithin(0, 3, 7);
        arr
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements.length, equals(10));
      expect(result.elements[0].toNumber(), equals(2));
      expect(result.elements[1].toNumber(), equals(2));
      expect(result.elements[2].toNumber(), equals(2));
      expect(result.elements[3].toNumber(), equals(2));
    });
  });
}
