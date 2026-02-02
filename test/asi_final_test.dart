import 'package:test/test.dart';
import 'package:js_interpreter/src/evaluator/evaluator.dart';

void main() {
  test('proper test with defined variable', () {
    const code = '''
var email = "TEST@EXAMPLE.COM"
var cleaned = email.trim().toLowerCase()
console.log(cleaned)
''';

    expect(() => JSEvaluator.evaluateString(code), returnsNormally);
  });

  test('single line without semicolon', () {
    const code = 'var x = 5';

    final result = JSEvaluator.evaluateString(code);
    expect(result.isUndefined, isTrue);
  });
}
