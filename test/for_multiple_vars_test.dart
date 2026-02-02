import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('For loop with multiple variable declarations', () {
    test('for loop with comma-separated var declarations', () {
      final js = JSInterpreter();
      expect(
        () => js.eval('''
        var result = 0;
        for (var i = 0, j = 10, k = 20; i < 3; i++) {
          result += i + j + k;
        }
      '''),
        returnsNormally,
      );

      // result = (0+10+20) + (1+10+20) + (2+10+20) = 30 + 31 + 32 = 93
      final result = js.eval('result');
      expect(result.toNumber(), equals(93));
    });

    test('for loop with some initialized and some not', () {
      final js = JSInterpreter();
      expect(
        () => js.eval('''
        var sum = 0;
        for (var s, i = 1, n = 5; i <= n; i++) {
          s = i * 2;
          sum += s;
        }
      '''),
        returnsNormally,
      );

      // sum = 2 + 4 + 6 + 8 + 10 = 30
      final result = js.eval('sum');
      expect(result.toNumber(), equals(30));
    });

    test('for loop ', () {
      final js = JSInterpreter();
      expect(
        () => js.eval('''
        var result = [];
        var args = [10, 20, 30];
        for (var s, i = 1, n = args.length; i < n; i++) {
          s = args[i];
          result.push(s);
        }
      '''),
        returnsNormally,
      );

      final result = js.eval('result');
      // Check the array contents rather than its output format
      final arr = result.toObject() as JSArray;
      expect(arr.elements.length, equals(2));
      expect(arr.elements[0].toNumber(), equals(20));
      expect(arr.elements[1].toNumber(), equals(30));
    });
  });
}
