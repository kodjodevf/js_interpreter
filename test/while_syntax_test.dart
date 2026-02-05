import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('While statement syntax tests', () {
    test('should reject "while 1" without parentheses', () {
      final code = "while 1 break;";
      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      expect(() => parser.parse(), throwsA(isA<ParseError>()));
    });

    test('should reject "while()" with empty parentheses', () {
      final code = "while();";
      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      expect(() => parser.parse(), throwsA(isA<ParseError>()));
    });

    test('should allow "while(true)" with parentheses', () {
      final code = "while(true) break;";
      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      expect(() => parser.parse(), returnsNormally);
    });
  });
}
