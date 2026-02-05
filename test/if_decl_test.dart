import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('If statement declaration tests', () {
    test('should reject class declaration in if statement', () {
      final code = "if (true) class C {}";
      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      expect(() => parser.parse(), throwsA(isA<ParseError>()));
    });

    test('should reject const declaration in if statement', () {
      final code = "if (true) const x = null;";
      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      expect(() => parser.parse(), throwsA(isA<ParseError>()));
    });

    test('should reject let declaration in if statement', () {
      final code = "if (true) let x;";
      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      expect(() => parser.parse(), throwsA(isA<ParseError>()));
    });
  });
}
