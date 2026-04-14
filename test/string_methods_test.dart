import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('String Methods Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });
    test('string length property', () {
      const code = '''
        var str = "Hello World";
        str.length;
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('11'));
    });

    test('string charAt method', () {
      const code = '''
        var str = "JavaScript";
        str.charAt(0) + str.charAt(4);
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('JS'));
    });

    test('string substring method', () {
      const code = '''
        var str = "Hello World";
        str.substring(0, 5);
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('Hello'));
    });

    test('string indexOf method', () {
      const code = '''
        var str = "Hello World";
        str.indexOf("World");
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('6'));
    });

    test('string example', () {
      const code = '''
        function processText(text) {
          var result = {
            length: text.length,
            firstChar: text.charAt(0),
            lastChar: text.charAt(text.length - 1),
            hasSpace: text.indexOf(" ") !== -1
          };
          return result;
        }
        
        var info = processText("Hello World");
        console.log("Length:", info.length);
        console.log("First:", info.firstChar, "Last:", info.lastChar);
        console.log("Has space:", info.hasSpace);
        
        info.length;
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('11'));
    });
  });
}
