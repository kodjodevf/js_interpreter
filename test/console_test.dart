import 'package:test/test.dart';
import 'package:js_interpreter/src/evaluator/evaluator.dart';

void main() {
  group('Console Tests', () {
    test('console.log() with various types', () {
      const code = '''
        console.log("Hello, World!");
        console.log(42);
        console.log(true);
        console.log(null);
        console.log(undefined);
        
        var arr = [1, 2, 3];
        console.log(arr);
        
        console.log("Multiple", "arguments", 123, true);
      ''';

      // This test just verifies that console.log doesn't crash
      // L'output sera visible dans le terminal
      expect(() => JSEvaluator.evaluateString(code), returnsNormally);
    });

    test('console.error() and console.warn()', () {
      const code = '''
        console.error("This is an error");
        console.warn("This is a warning");
      ''';

      expect(() => JSEvaluator.evaluateString(code), returnsNormally);
    });

    test('console methods are functions', () {
      const code = '''
        typeof console.log;
      ''';

      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('function'));
    });

    test('console.log() returns undefined', () {
      const code = '''
        var result = console.log("test");
        result;
      ''';

      final result = JSEvaluator.evaluateString(code);
      expect(result.isUndefined, isTrue);
    });

    test('console.log() with array formatting', () {
      const code = '''
        var arr = [1, "hello", true, null, undefined];
        console.log(arr);
      ''';

      expect(() => JSEvaluator.evaluateString(code), returnsNormally);
    });

    test('console.log() complex example', () {
      const code = '''
        function factorial(n) {
          if (n <= 1) return 1;
          return n * factorial(n - 1);
        }
        
        var numbers = [1, 2, 3, 4, 5];
        for (var i = 0; i < numbers.length; i++) {
          var fact = factorial(numbers[i]);
          console.log("factorial(" + numbers[i] + ") =", fact);
        }
      ''';

      expect(() => JSEvaluator.evaluateString(code), returnsNormally);
    });
  });
}
