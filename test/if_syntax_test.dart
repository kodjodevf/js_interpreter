import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('If statement syntax tests', () {
    test('should reject "if true" without parentheses', () {
      final code = "if true;";
      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      expect(() => parser.parse(), throwsA(isA<ParseError>()));
    });

    test('should reject "if false" without parentheses', () {
      final code = "if false;";
      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      expect(() => parser.parse(), throwsA(isA<ParseError>()));
    });

    test('should reject "if()" with empty parentheses', () {
      final code = "if();";
      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      expect(() => parser.parse(), throwsA(isA<ParseError>()));
    });

    test('should reject "if({1})" with object literal in condition', () {
      final code = "if({1});";
      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      expect(() => parser.parse(), throwsA(isA<ParseError>()));
    });
  });
}
