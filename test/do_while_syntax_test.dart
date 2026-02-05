import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Do-while statement syntax tests', () {
    test('should reject multiple statements in do-while without braces', () {
      final code = "do var x=1; var y=2; while (0);";
      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      expect(() => parser.parse(), throwsA(isA<ParseError>()));
    });

    test('should allow single statement in do-while without braces', () {
      final code = "do var x=1; while (0);";
      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      expect(() => parser.parse(), returnsNormally);
    });

    test('should allow multiple statements in do-while with braces', () {
      final code = "do { var x=1; var y=2; } while (0);";
      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      expect(() => parser.parse(), returnsNormally);
    });
  });
}
