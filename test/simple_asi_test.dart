import 'package:test/test.dart';
import 'package:js_interpreter/src/evaluator/evaluator.dart';

void main() {
  test('simple case that should work', () {
    const code = '''
var x = 5
console.log(x)
''';

    expect(() => JSEvaluator.evaluateString(code), returnsNormally);
  });

  test('method chain single line', () {
    const code = '''
var result = "hello".toUpperCase()
console.log(result)
''';

    expect(() => JSEvaluator.evaluateString(code), returnsNormally);
  });

  test('method chain multi line - the problematic case', () {
    const code = '''
var str = "hello"
var result = str
  .toUpperCase()
console.log(result)
''';

    expect(() => JSEvaluator.evaluateString(code), returnsNormally);
  });
}
