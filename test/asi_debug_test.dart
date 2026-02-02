import 'package:test/test.dart';
import 'package:js_interpreter/src/evaluator/evaluator.dart';

void main() {
  group('ASI Debug Tests', () {
    test('simple multiline expression', () {
      const code = '''
        var x = 5
        var y = 10
      ''';

      expect(() => JSEvaluator.evaluateString(code), returnsNormally);
    });

    test('method chaining simple', () {
      const code = '''
        var str = "hello"
        var result = str.toUpperCase()
        result
      ''';

      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('HELLO'));
    });

    test('method chaining multiline', () {
      const code = '''
        var str = "hello"
        var result = str
          .toUpperCase()
        result
      ''';

      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('HELLO'));
    });
  });
}
