import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('If statement function declarations in strict mode', () {
    test('should allow function declaration in if in non-strict mode', () {
      final code = "if (true) function f() {} else function _f() {}";
      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      expect(() => parser.parse(), returnsNormally);
    });

    test('should reject function declaration in if in strict mode', () {
      final code =
          "'use strict'; if (true) function f() {} else function _f() {}";
      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      expect(() => parser.parse(), throwsA(isA<ParseError>()));
    });

    test(
      'should reject function declaration in if consequent in strict mode',
      () {
        final code = "'use strict'; if (true) function f() {}";
        final lexer = JSLexer(code);
        final tokens = lexer.tokenize();
        final parser = JSParser(tokens);
        expect(() => parser.parse(), throwsA(isA<ParseError>()));
      },
    );

    test(
      'should reject function declaration in if alternate in strict mode',
      () {
        final code = "'use strict'; if (false) {} else function f() {}";
        final lexer = JSLexer(code);
        final tokens = lexer.tokenize();
        final parser = JSParser(tokens);
        expect(() => parser.parse(), throwsA(isA<ParseError>()));
      },
    );
  });
}
