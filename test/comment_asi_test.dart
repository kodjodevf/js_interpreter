import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });
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

    expect(() => interpreter.eval(code), returnsNormally);
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

    final result = interpreter.eval(code);
    expect(result.toString(), equals('test@example.com'));
  });
}
