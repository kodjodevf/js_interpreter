import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('ASI Debug Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });
    test('simple multiline expression', () {
      const code = '''
        var x = 5
        var y = 10
      ''';

      expect(() => interpreter.eval(code), returnsNormally);
    });

    test('method chaining simple', () {
      const code = '''
        var str = "hello"
        var result = str.toUpperCase()
        result
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('HELLO'));
    });

    test('method chaining multiline', () {
      const code = '''
        var str = "hello"
        var result = str
          .toUpperCase()
        result
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('HELLO'));
    });
  });
}
