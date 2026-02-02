import 'package:test/test.dart';
import 'package:js_interpreter/src/evaluator/evaluator.dart';

void main() {
  group('String Chain Debug Tests', () {
    test('complex multiline chaining', () {
      const code = '''
        var text = "  Hello, World!  "
        var processed = text
          .trim()
          .toLowerCase()
        
        console.log("Result:", processed)
        processed
      ''';

      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('hello, world!'));
    });

    test('variable declaration with method chain', () {
      const code = '''
        function processEmail(email) {
          var cleaned = email.trim().toLowerCase()
          var atIndex = cleaned.indexOf("@")
          return cleaned
        }
        
        var result = processEmail("  JOHN@EXAMPLE.COM  ")
        result
      ''';

      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('john@example.com'));
    });
  });
}
