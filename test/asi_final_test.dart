import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });
  test('proper test with defined variable', () {
    const code = '''
var email = "TEST@EXAMPLE.COM"
var cleaned = email.trim().toLowerCase()
console.log(cleaned)
''';

    expect(() => interpreter.eval(code), returnsNormally);
  });

  test('single line without semicolon', () {
    const code = 'var x = 5';

    final result = interpreter.eval(code);
    expect(result.isUndefined, isTrue);
  });
}
