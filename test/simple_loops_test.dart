import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Simple Loop Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('basic for loop', () {
      final result = interpreter.eval('''
        var sum = 0;
        for (var i = 1; i <= 3; i++) {
          sum += i;
        }
        sum;
      ''');
      expect(result.toNumber(), equals(6)); // 1+2+3 = 6
    });

    test('for loop with continue', () {
      final result = interpreter.eval('''
        var sum = 0;
        for (var i = 1; i <= 5; i++) {
          if (i === 3) continue;
          sum += i;
        }
        sum;
      ''');
      expect(result.toNumber(), equals(12)); // 1+2+4+5 = 12
    });

    test('do-while basic', () {
      final result = interpreter.eval('''
        var i = 0;
        var sum = 0;
        do {
          sum += i;
          i++;
        } while (i < 3);
        sum;
      ''');
      expect(result.toNumber(), equals(3)); // 0+1+2 = 3
    });

    test('array creation', () {
      final result = interpreter.eval('''
        var arr = [1, 2, 3];
        arr.length;
      ''');
      expect(result.toNumber(), equals(3));
    });

    test('array access', () {
      final result = interpreter.eval('''
        var arr = [10, 20, 30];
        arr[1];
      ''');
      expect(result.toNumber(), equals(20));
    });

    test('for-of simple', () {
      final result = interpreter.eval('''
        var arr = [1, 2, 3];
        var sum = 0;
        for (var value of arr) {
          sum += value;
        }
        sum;
      ''');
      expect(result.toNumber(), equals(6)); // 1+2+3 = 6
    });
  });
}
