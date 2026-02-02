import 'package:test/test.dart';
import 'package:js_interpreter/src/evaluator/evaluator.dart';

void main() {
  test('comments with ASI', () {
    const code = '''
function test() {
  // Commentaire
  var x = 5
  return x
}

var result = test()
console.log(result)
''';

    expect(() => JSEvaluator.evaluateString(code), returnsNormally);
  });

  test('complex case from original test', () {
    const code = '''
function processEmail(email) {
  var cleaned = email.trim().toLowerCase()
  var atIndex = cleaned.indexOf("@")
  return cleaned
}

var result = processEmail("test@example.com")
result
''';

    final result = JSEvaluator.evaluateString(code);
    expect(result.toString(), equals('test@example.com'));
  });
}
