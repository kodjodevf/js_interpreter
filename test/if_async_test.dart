import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('If statement async function tests', () {
    test('should reject async function declaration in if statement', () {
      final code = "if (true) async function f() {}";
      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      expect(() => parser.parse(), throwsA(isA<ParseError>()));
    });

    test('should reject generator declaration in if statement', () {
      final code = "if (true) function* g() {}";
      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      expect(() => parser.parse(), throwsA(isA<ParseError>()));
    });
  });
}
