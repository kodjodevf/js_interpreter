import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });
  test('simple case that should work', () {
    const code = '''
var x = 5
console.log(x)
''';

    expect(() => interpreter.eval(code), returnsNormally);
  });

  test('method chain single line', () {
    const code = '''
var result = "hello".toUpperCase()
console.log(result)
''';

    expect(() => interpreter.eval(code), returnsNormally);
  });

  test('method chain multi line - the problematic case', () {
    const code = '''
var str = "hello"
var result = str
  .toUpperCase()
console.log(result)
''';

    expect(() => interpreter.eval(code), returnsNormally);
  });
}
