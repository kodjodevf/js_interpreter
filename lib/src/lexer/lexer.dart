/// JavaScript Lexer
/// Lexical analysis to convert source code into tokens
library;

import 'token.dart';

/// Exception thrown during lexical analysis errors
class LexerError extends Error {
  final String message;
  final int line;
  final int column;

  LexerError(this.message, this.line, this.column);

  @override
  String toString() => 'LexerError at $line:$column: $message';
}

/// JavaScript Lexical Analyzer
class JSLexer {
  final String source;
  int _current = 0;
  int _line = 1;
  int _column = 1;
  final List<Token> _tokens = [];
  int _lastTokenLine =
      0; // Track line of last non-whitespace token for HTML comments

  /// Determines if a regex can be present in the current context
  bool get _canHaveRegex {
    if (_tokens.isEmpty) return true;

    final lastToken = _tokens.last;
    final regexContextTokens = {
      TokenType.assign,
      TokenType.leftParen,
      TokenType.leftBracket,
      TokenType.comma,
      TokenType.colon,
      TokenType.semicolon,
      TokenType.logicalNot,
      TokenType.logicalAnd,
      TokenType.logicalOr,
      TokenType.bitwiseAnd,
      TokenType.bitwiseOr,
      TokenType.question,
      TokenType.plus,
      TokenType.minus,
      TokenType.multiply,
      TokenType.divide,
      TokenType.modulo,
      TokenType.leftBrace,
      TokenType.keywordReturn,
      TokenType.keywordThrow,
      TokenType.keywordIf,
      TokenType.keywordFor,
      TokenType.keywordWhile,
      TokenType.equal,
      TokenType.notEqual,
      TokenType.strictEqual,
      TokenType.strictNotEqual,
      TokenType.keywordYield,
      TokenType.keywordAwait,
    };

    return regexContextTokens.contains(lastToken.type);
  }

  JSLexer(this.source);

  /// Analyzes the source code and returns the list of tokens
  List<Token> tokenize() {
    _tokens.clear();
    _current = 0;
    _line = 1;
    _column = 1;
    _lastTokenLine = 0; // Initialize to 0 so first line is considered "new"

    // ES2023: Hashbang Grammar - Skip hashbang/shebang at the start of the file
    // Format: #!/path/to/interpreter or #!/usr/bin/env node
    if (_current == 0 && _peek() == '#' && _peekNext() == '!') {
      // Skip the entire hashbang line (until any line terminator)
      while (!_isAtEnd()) {
        final ch = _peek();
        // Line terminators: LF, CR, LS (U+2028), PS (U+2029)
        if (ch == '\n' || ch == '\r' || ch == '\u{2028}' || ch == '\u{2029}') {
          break;
        }
        _advance();
      }
      // Skip the line terminator
      if (!_isAtEnd()) {
        final ch = _peek();
        if (ch == '\r' && _peekNext() == '\n') {
          // CRLF sequence
          _advance();
          _advance();
        } else {
          _advance(); // Single line terminator
        }
        _line++;
        _column = 1;
      }
    }

    while (!_isAtEnd()) {
      _scanToken();
    }

    _tokens.add(_makeToken(TokenType.eof, ''));
    return List.unmodifiable(_tokens);
  }

  /// Analyzes a token at the current position
  void _scanToken() {
    final start = _current;
    final startLine = _line;
    final startColumn = _column;

    final char = _advance();

    switch (char) {
      // Whitespace
      case ' ':
      case '\t':
      case '\v': // Vertical tab (U+000B)
      case '\f': // Form feed (U+000C)
        // Ignore whitespace
        break;

      case '\r':
        // CR (U+000D) is a line terminator per ECMAScript spec.
        // If followed by LF (U+000A), consume it as a single CRLF line terminator.
        if (!_isAtEnd() && source[_current] == '\n') {
          _current++;
        }
        _line++;
        _column = 1;
        break;

      case '\n':
        _line++;
        _column = 1;
        // Reset for new line
        break;

      // Simple operators
      case '+':
        if (_match('+')) {
          _addToken(TokenType.increment, '++', start, startLine, startColumn);
        } else if (_match('=')) {
          _addToken(TokenType.plusAssign, '+=', start, startLine, startColumn);
        } else {
          _addToken(TokenType.plus, '+', start, startLine, startColumn);
        }
        break;

      case '-':
        // Check for HTML close comment --> (Annex B feature)
        // Can ONLY appear at line start or after whitespace/comment on a NEW line
        // Do NOT treat --> as comment if it's on the same line as a previous token
        // (e.g., "j --> 0" should be "j--" followed by "> 0")
        if (_peek() == '-' && _peekNext() == '>' && _line > _lastTokenLine) {
          _current--; // Back up to start of -
          _column--;
          _scanHTMLCloseComment(start, startLine, startColumn);
        } else if (_match('-')) {
          _addToken(TokenType.decrement, '--', start, startLine, startColumn);
        } else if (_match('=')) {
          _addToken(TokenType.minusAssign, '-=', start, startLine, startColumn);
        } else {
          _addToken(TokenType.minus, '-', start, startLine, startColumn);
        }
        break;

      case '*':
        if (_match('*')) {
          // Check if it's **= or **
          if (_match('=')) {
            _addToken(
              TokenType.exponentAssign,
              '**=',
              start,
              startLine,
              startColumn,
            );
          } else {
            _addToken(TokenType.exponent, '**', start, startLine, startColumn);
          }
        } else if (_match('=')) {
          _addToken(
            TokenType.multiplyAssign,
            '*=',
            start,
            startLine,
            startColumn,
          );
        } else {
          _addToken(TokenType.multiply, '*', start, startLine, startColumn);
        }
        break;

      case '/':
        if (_match('/')) {
          _scanSingleLineComment(start, startLine, startColumn);
        } else if (_match('*')) {
          _scanMultiLineComment(start, startLine, startColumn);
        } else if (_canHaveRegex) {
          _scanRegexLiteral(start, startLine, startColumn);
        } else if (_match('=')) {
          _addToken(
            TokenType.divideAssign,
            '/=',
            start,
            startLine,
            startColumn,
          );
        } else {
          _addToken(TokenType.divide, '/', start, startLine, startColumn);
        }
        break;

      case '%':
        if (_match('=')) {
          _addToken(
            TokenType.moduloAssign,
            '%=',
            start,
            startLine,
            startColumn,
          );
        } else {
          _addToken(TokenType.modulo, '%', start, startLine, startColumn);
        }
        break;

      // Comparison operators
      case '=':
        if (_match('=')) {
          if (_match('=')) {
            _addToken(
              TokenType.strictEqual,
              '===',
              start,
              startLine,
              startColumn,
            );
          } else {
            _addToken(TokenType.equal, '==', start, startLine, startColumn);
          }
        } else if (_match('>')) {
          _addToken(TokenType.arrow, '=>', start, startLine, startColumn);
        } else {
          _addToken(TokenType.assign, '=', start, startLine, startColumn);
        }
        break;

      case '!':
        if (_match('=')) {
          if (_match('=')) {
            _addToken(
              TokenType.strictNotEqual,
              '!==',
              start,
              startLine,
              startColumn,
            );
          } else {
            _addToken(TokenType.notEqual, '!=', start, startLine, startColumn);
          }
        } else {
          _addToken(TokenType.logicalNot, '!', start, startLine, startColumn);
        }
        break;

      case '<':
        // Check for HTML open comment <!--  (Annex B feature)
        // Can appear at line start or after whitespace on any line
        if (_peek() == '!' && _peekAhead(1) == '-' && _peekAhead(2) == '-') {
          _current--; // Back up to start of <
          _column--;
          _scanHTMLOpenComment(start, startLine, startColumn);
        } else if (_match('<')) {
          if (_match('=')) {
            _addToken(
              TokenType.leftShiftAssign,
              '<<=',
              start,
              startLine,
              startColumn,
            );
          } else {
            _addToken(TokenType.leftShift, '<<', start, startLine, startColumn);
          }
        } else if (_match('=')) {
          _addToken(
            TokenType.lessThanEqual,
            '<=',
            start,
            startLine,
            startColumn,
          );
        } else {
          _addToken(TokenType.lessThan, '<', start, startLine, startColumn);
        }
        break;

      case '>':
        if (_match('>')) {
          if (_match('>')) {
            if (_match('=')) {
              _addToken(
                TokenType.unsignedRightShiftAssign,
                '>>>=',
                start,
                startLine,
                startColumn,
              );
            } else {
              _addToken(
                TokenType.unsignedRightShift,
                '>>>',
                start,
                startLine,
                startColumn,
              );
            }
          } else if (_match('=')) {
            _addToken(
              TokenType.rightShiftAssign,
              '>>=',
              start,
              startLine,
              startColumn,
            );
          } else {
            _addToken(
              TokenType.rightShift,
              '>>',
              start,
              startLine,
              startColumn,
            );
          }
        } else if (_match('=')) {
          _addToken(
            TokenType.greaterThanEqual,
            '>=',
            start,
            startLine,
            startColumn,
          );
        } else {
          _addToken(TokenType.greaterThan, '>', start, startLine, startColumn);
        }
        break;

      // Logical and bitwise operators
      case '&':
        if (_match('&')) {
          if (_match('=')) {
            _addToken(
              TokenType.andAssign,
              '&&=',
              start,
              startLine,
              startColumn,
            );
          } else {
            _addToken(
              TokenType.logicalAnd,
              '&&',
              start,
              startLine,
              startColumn,
            );
          }
        } else if (_match('=')) {
          _addToken(
            TokenType.bitwiseAndAssign,
            '&=',
            start,
            startLine,
            startColumn,
          );
        } else {
          _addToken(TokenType.bitwiseAnd, '&', start, startLine, startColumn);
        }
        break;

      case '|':
        if (_match('|')) {
          if (_match('=')) {
            _addToken(TokenType.orAssign, '||=', start, startLine, startColumn);
          } else {
            _addToken(TokenType.logicalOr, '||', start, startLine, startColumn);
          }
        } else if (_match('=')) {
          _addToken(
            TokenType.bitwiseOrAssign,
            '|=',
            start,
            startLine,
            startColumn,
          );
        } else {
          _addToken(TokenType.bitwiseOr, '|', start, startLine, startColumn);
        }
        break;

      case '^':
        if (_match('=')) {
          _addToken(
            TokenType.bitwiseXorAssign,
            '^=',
            start,
            startLine,
            startColumn,
          );
        } else {
          _addToken(TokenType.bitwiseXor, '^', start, startLine, startColumn);
        }
        break;

      case '~':
        _addToken(TokenType.bitwiseNot, '~', start, startLine, startColumn);
        break;

      // Delimiters
      case '(':
        _addToken(TokenType.leftParen, '(', start, startLine, startColumn);
        break;
      case ')':
        _addToken(TokenType.rightParen, ')', start, startLine, startColumn);
        break;
      case '{':
        _addToken(TokenType.leftBrace, '{', start, startLine, startColumn);
        break;
      case '}':
        _addToken(TokenType.rightBrace, '}', start, startLine, startColumn);
        break;
      case '[':
        _addToken(TokenType.leftBracket, '[', start, startLine, startColumn);
        break;
      case ']':
        _addToken(TokenType.rightBracket, ']', start, startLine, startColumn);
        break;

      // Punctuation
      case ';':
        _addToken(TokenType.semicolon, ';', start, startLine, startColumn);
        break;
      case ',':
        _addToken(TokenType.comma, ',', start, startLine, startColumn);
        break;
      case '.':
        if (_match('.') && _match('.')) {
          _addToken(TokenType.spread, '...', start, startLine, startColumn);
        } else if (_isDigit(_peek())) {
          // Decimal number starting with dot: .12345
          _current--; // Back up to process as number
          _scanNumber(start, startLine, startColumn);
        } else {
          _addToken(TokenType.dot, '.', start, startLine, startColumn);
        }
        break;
      case ':':
        _addToken(TokenType.colon, ':', start, startLine, startColumn);
        break;
      case '?':
        if (_peek() == '.' && _isDigit(_peekNext())) {
          // Don't treat ?. as optional chaining if followed by decimal digit
          // e.g., in `true ?.30 : false`, the `?` is ternary operator, not optional chaining
          _addToken(TokenType.question, '?', start, startLine, startColumn);
        } else if (_match('.')) {
          _addToken(
            TokenType.optionalChaining,
            '?.',
            start,
            startLine,
            startColumn,
          );
        } else if (_match('?')) {
          if (_match('=')) {
            _addToken(
              TokenType.nullishCoalescingAssign,
              '??=',
              start,
              startLine,
              startColumn,
            );
          } else {
            _addToken(
              TokenType.nullishCoalescing,
              '??',
              start,
              startLine,
              startColumn,
            );
          }
        } else {
          _addToken(TokenType.question, '?', start, startLine, startColumn);
        }
        break;

      // Character strings
      case '"':
      case "'":
        _scanString(char, start, startLine, startColumn);
        break;

      // Template literals
      case '`':
        _scanTemplateString(start, startLine, startColumn);
        break;

      // Private identifiers
      case '#':
        _scanPrivateIdentifier(start, startLine, startColumn);
        break;

      // Potential Unicode escape at the start of an identifier
      case '\\':
        if (_peekAhead(0) == 'u') {
          // This might be a Unicode escape starting an identifier
          // We need to back up because _advance() already consumed the backslash
          _current--;
          _column--;
          _scanIdentifier(start, startLine, startColumn);
        } else {
          throw LexerError('Unexpected character: $char', _line, _column);
        }
        break;

      default:
        if (_isDigit(char)) {
          _scanNumber(start, startLine, startColumn);
        } else if (_isAlpha(char)) {
          _scanIdentifier(start, startLine, startColumn);
        } else if (_isUnicodeWhitespace(char)) {
          // Unicode whitespace characters should be ignored
          // (U+00A0, U+2028, U+2029, etc.)
          // Handle line separators specially
          if (char.codeUnitAt(0) == 0x2028 || char.codeUnitAt(0) == 0x2029) {
            _line++;
            _column = 1;
          }
          break;
        } else if (_isUnicodeIdentifierStart(char)) {
          // Allow Unicode characters that could be identifier starts
          _scanIdentifier(start, startLine, startColumn);
        } else {
          throw LexerError('Unexpected character: $char', _line, _column);
        }
        break;
    }
  }

  /// Helper to check character at offset from current position
  String _peekAhead(int offset) {
    final pos = _current + offset;
    if (pos >= source.length) return '\u0000';
    return source[pos];
  }

  /// Analyzes a character string
  void _scanString(String quote, int start, int startLine, int startColumn) {
    final buffer = StringBuffer();

    while (!_isAtEnd() && _peek() != quote) {
      if (_peek() == '\n') {
        _line++;
        _column = 1;
      } else if (_peek() == '\r') {
        // CR is a line terminator; consume CRLF as single terminator
        _advance();
        if (!_isAtEnd() && _peek() == '\n') {
          _advance();
        }
        _line++;
        _column = 1;
        continue;
      }

      if (_peek() == '\\') {
        _advance(); // Consume the backslash
        final escaped = _advance();
        switch (escaped) {
          case 'n':
            buffer.write('\n');
            break;
          case 't':
            buffer.write('\t');
            break;
          case 'r':
            buffer.write('\r');
            break;
          case 'b':
            buffer.write('\b');
            break;
          case 'f':
            buffer.write('\f');
            break;
          case 'v':
            buffer.write('\v');
            break;
          case '0':
            buffer.write('\x00');
            break;
          case '\\':
            buffer.write('\\');
            break;
          case '"':
          case "'":
            buffer.write(escaped);
            break;
          case 'u':
            // Unicode escape sequence: \uXXXX or \u{XXXXXX}
            if (_peek() == '{') {
              // \u{XXXXXX} format
              _advance(); // consume '{'
              final hex = StringBuffer();
              while (!_isAtEnd() && _peek() != '}') {
                final ch = _advance();
                if (_isHexDigit(ch)) {
                  hex.write(ch);
                } else {
                  // Invalid unicode escape - treat as literal
                  buffer.write('u{');
                  buffer.write(hex.toString());
                  buffer.write(ch);
                  break;
                }
              }
              if (!_isAtEnd() && _peek() == '}') {
                _advance(); // consume '}'
                if (hex.isNotEmpty) {
                  final codePoint = int.parse(hex.toString(), radix: 16);
                  if (codePoint > 0x10FFFF) {
                    // Invalid code point - treat as literal
                    buffer.write('u{');
                    buffer.write(hex.toString());
                    buffer.write('}');
                  } else {
                    // Handle surrogate pairs for code points > 0xFFFF
                    if (codePoint > 0xFFFF) {
                      final high = ((codePoint - 0x10000) >> 10) + 0xD800;
                      final low = ((codePoint - 0x10000) & 0x3FF) + 0xDC00;
                      buffer.writeCharCode(high);
                      buffer.writeCharCode(low);
                    } else {
                      buffer.writeCharCode(codePoint);
                    }
                  }
                }
              } else {
                // Missing closing brace - treat as literal
                buffer.write('u{');
                buffer.write(hex.toString());
              }
            } else {
              // \uXXXX format
              final hex = StringBuffer();
              for (int i = 0; i < 4; i++) {
                if (_isAtEnd()) break;
                final ch = _advance();
                if (_isHexDigit(ch)) {
                  hex.write(ch);
                } else {
                  // Invalid unicode escape - treat as literal
                  buffer.write('u');
                  buffer.write(hex.toString());
                  buffer.write(ch);
                  break;
                }
              }
              if (hex.length == 4) {
                final codePoint = int.parse(hex.toString(), radix: 16);
                buffer.writeCharCode(codePoint);
              }
            }
            break;
          case 'x':
            // Hex escape sequence: \xXX
            final hex = StringBuffer();
            for (int i = 0; i < 2; i++) {
              if (_isAtEnd()) break;
              final ch = _advance();
              if (_isHexDigit(ch)) {
                hex.write(ch);
              } else {
                // Invalid hex escape - treat as literal
                buffer.write('x');
                buffer.write(hex.toString());
                buffer.write(ch);
                break;
              }
            }
            if (hex.length == 2) {
              final codePoint = int.parse(hex.toString(), radix: 16);
              buffer.writeCharCode(codePoint);
            }
            break;
          default:
            buffer.write(escaped);
            break;
        }
      } else {
        buffer.write(_advance());
      }
    }

    if (_isAtEnd()) {
      throw LexerError('Unterminated string', startLine, startColumn);
    }

    // Consume the closing quote
    _advance();

    final value = buffer.toString();
    final lexeme = '$quote$value$quote';
    _addTokenWithLiteral(
      TokenType.string,
      lexeme,
      value,
      start,
      startLine,
      startColumn,
    );
  }

  /// Analyzes a template literal (template string)
  void _scanTemplateString(int start, int startLine, int startColumn) {
    final buffer = StringBuffer();
    int interpolationDepth = 0; // Track nesting depth of ${...}

    while (!_isAtEnd()) {
      final char = _peek();

      // Check for interpolation start ${
      if (char == '\$' && _peekNext() == '{') {
        buffer.write(_advance()); // $
        buffer.write(_advance()); // {
        interpolationDepth++;
        continue;
      }

      // Track braces inside interpolations
      if (interpolationDepth > 0) {
        if (char == '{') {
          interpolationDepth++;
        } else if (char == '}') {
          interpolationDepth--;
        }

        // Don't end template on backticks inside interpolations
        buffer.write(_advance());

        // Handle newlines even inside interpolations
        if (char == '\n') {
          _line++;
          _column = 0; // Will be incremented to 1 by _advance()
        } else if (char == '\r') {
          // CR is a line terminator; consume CRLF as single terminator
          if (!_isAtEnd() && _peek() == '\n') {
            buffer.write(_advance());
          }
          _line++;
          _column = 0;
        }
        continue;
      }

      // End of template literal (only when not inside interpolation)
      if (char == '`') {
        _advance(); // Consume the `
        final value = buffer.toString();
        final lexeme = '`$value`';
        _addTokenWithLiteral(
          TokenType.templateString,
          lexeme,
          value,
          start,
          startLine,
          startColumn,
        );
        return;
      }

      // Handle new lines
      if (char == '\n') {
        _line++;
        _column = 1;
      } else if (char == '\r') {
        // CR is a line terminator; consume CRLF as single terminator
        if (!_isAtEnd() && _peek() == '\n') {
          buffer.write(_advance());
        }
        _line++;
        _column = 1;
      }

      // Handle escape sequences
      if (char == '\\') {
        _advance(); // Consume the backslash
        if (_isAtEnd()) {
          throw LexerError(
            'Unterminated template literal',
            startLine,
            startColumn,
          );
        }
        final escaped = _advance();
        switch (escaped) {
          case 'n':
            buffer.write('\n');
            break;
          case 't':
            buffer.write('\t');
            break;
          case 'r':
            buffer.write('\r');
            break;
          case '\\':
            buffer.write('\\');
            break;
          case '`':
            buffer.write('`');
            break;
          case '\$':
            buffer.write('\$');
            break;
          default:
            buffer.write(escaped);
            break;
        }
      } else {
        buffer.write(_advance());
      }
    }

    throw LexerError('Unterminated template literal', startLine, startColumn);
  }

  /// Analyzes the continuation of a template literal after an expression (after })
  void scanTemplateExpression() {
    if (_isAtEnd()) {
      throw LexerError(
        'Unexpected end of input in template literal',
        _line,
        _column,
      );
    }

    final start = _current;
    final startLine = _line;
    final startColumn = _column;
    final buffer = StringBuffer();

    while (!_isAtEnd()) {
      final char = _peek();

      // End of template literal
      if (char == '`') {
        _advance(); // Consume the `
        final value = buffer.toString();
        final lexeme = '}$value`';
        _addTokenWithLiteral(
          TokenType.templateEnd,
          lexeme,
          value,
          start,
          startLine,
          startColumn,
        );
        return;
      }

      // Start of a new interpolation expression
      if (char == '\$' && _peekNext() == '{') {
        // Create a token for the part before the new expression
        final value = buffer.toString();
        final lexeme = '}$value\${';
        _addTokenWithLiteral(
          TokenType.templateExpression,
          lexeme,
          value,
          start,
          startLine,
          startColumn,
        );

        // Consume ${
        _advance(); // $
        _advance(); // {
        return;
      }

      // Handle new lines
      if (char == '\n') {
        _line++;
        _column = 1;
      } else if (char == '\r') {
        // CR is a line terminator; consume CRLF as single terminator
        if (!_isAtEnd() && _peek() == '\n') {
          buffer.write(_advance());
        }
        _line++;
        _column = 1;
      }

      // Handle escape sequences
      if (char == '\\') {
        _advance(); // Consume the backslash
        if (_isAtEnd()) {
          throw LexerError(
            'Unterminated template literal',
            startLine,
            startColumn,
          );
        }
        final escaped = _advance();
        switch (escaped) {
          case 'n':
            buffer.write('\n');
            break;
          case 't':
            buffer.write('\t');
            break;
          case 'r':
            buffer.write('\r');
            break;
          case '\\':
            buffer.write('\\');
            break;
          case '`':
            buffer.write('`');
            break;
          case '\$':
            buffer.write('\$');
            break;
          default:
            buffer.write(escaped);
            break;
        }
      } else {
        buffer.write(_advance());
      }
    }

    throw LexerError('Unterminated template literal', startLine, startColumn);
  }

  /// Analyzes a number
  void _scanNumber(int start, int startLine, int startColumn) {
    // Handle numbers starting with a dot (e.g., .12345)
    final firstChar = source[start];
    if (firstChar == '.') {
      // Number starts with '.', just consume digits
      _advance(); // Consume the dot
      while (_isDigit(_peek()) || _peek() == '_') {
        _advance();
      }
      // No more decimal point handling, skip to scientific notation
    } else {
      // The first digit has already been consumed by _advance() in _scanToken()

      // Check for prefixes for different bases (0x, 0b, 0o)
      if (firstChar == '0' && _current < source.length) {
        final nextChar = _peek();

        // Hexadecimal: 0x or 0X
        if (nextChar == 'x' || nextChar == 'X') {
          _advance(); // Consume 'x'
          _scanHexNumber(start, startLine, startColumn);
          return;
        }

        // Binary: 0b or 0B
        if (nextChar == 'b' || nextChar == 'B') {
          _advance(); // Consume 'b'
          _scanBinaryNumber(start, startLine, startColumn);
          return;
        }

        // Octal: 0o or 0O
        if (nextChar == 'o' || nextChar == 'O') {
          _advance(); // Consume 'o'
          _scanOctalNumber(start, startLine, startColumn);
          return;
        }

        // Detect legacy octal literals (010, 077, etc.)
        // These are numbers starting with 0 followed by digits 0-7
        if (_isOctalDigit(nextChar)) {
          _scanLegacyOctalNumber(start, startLine, startColumn);
          return;
        }
      }

      // Normal decimal number
      // The first digit has already been consumed by _advance() in _scanToken()
      while (_isDigit(_peek()) || _peek() == '_') {
        _advance();
      }

      // Decimal part
      if (_peek() == '.') {
        // In JavaScript, 1. is valid (it's 1.0)
        // Just ensure it's not a property access (but that would apply to the next token)
        _advance(); // Consume the dot
        // Continue reading digits after the dot if present
        while (_isDigit(_peek()) || _peek() == '_') {
          _advance();
        }
      }
    }

    // Scientific notation
    if (_peek() == 'e' || _peek() == 'E') {
      _advance();
      if (_peek() == '+' || _peek() == '-') {
        _advance();
      }
      while (_isDigit(_peek()) || _peek() == '_') {
        _advance();
      }
    }

    // Suffixe BigInt
    bool isBigInt = false;
    if (_peek() == 'n') {
      _advance();
      isBigInt = true;
    }

    final lexeme = source.substring(start, _current);

    if (isBigInt) {
      // For BigInt, keep the string without 'n' and without underscores
      final numberPart = lexeme
          .substring(0, lexeme.length - 1)
          .replaceAll('_', '');
      final value = BigInt.parse(numberPart);
      _addTokenWithLiteral(
        TokenType.bigint,
        lexeme,
        value,
        start,
        startLine,
        startColumn,
      );
    } else {
      // Remove underscores before parsing
      final cleanLexeme = lexeme.replaceAll('_', '');
      final value = double.parse(cleanLexeme);
      _addTokenWithLiteral(
        TokenType.number,
        lexeme,
        value,
        start,
        startLine,
        startColumn,
      );
    }
  }

  /// Scans a hexadecimal number (0x...)
  void _scanHexNumber(int start, int startLine, int startColumn) {
    // Read hexadecimal digits (0-9, a-f, A-F) and underscores
    while (_isHexDigit(_peek()) || _peek() == '_') {
      _advance();
    }

    // BigInt suffix
    bool isBigInt = false;
    if (_peek() == 'n') {
      _advance();
      isBigInt = true;
    }

    final lexeme = source.substring(start, _current);
    // Remove the 0x prefix and underscores
    final hexPart = lexeme
        .substring(2, isBigInt ? lexeme.length - 1 : lexeme.length)
        .replaceAll('_', '');

    if (isBigInt) {
      final value = BigInt.parse(hexPart, radix: 16);
      _addTokenWithLiteral(
        TokenType.bigint,
        lexeme,
        value,
        start,
        startLine,
        startColumn,
      );
    } else {
      final value = int.parse(hexPart, radix: 16).toDouble();
      _addTokenWithLiteral(
        TokenType.number,
        lexeme,
        value,
        start,
        startLine,
        startColumn,
      );
    }
  }

  /// Scans a binary number (0b...)
  void _scanBinaryNumber(int start, int startLine, int startColumn) {
    // Read binary digits (0-1) and underscores
    while ((_peek() == '0' || _peek() == '1' || _peek() == '_')) {
      _advance();
    }

    // BigInt suffix
    bool isBigInt = false;
    if (_peek() == 'n') {
      _advance();
      isBigInt = true;
    }

    final lexeme = source.substring(start, _current);
    // Remove the 0b prefix and underscores
    final binaryPart = lexeme
        .substring(2, isBigInt ? lexeme.length - 1 : lexeme.length)
        .replaceAll('_', '');

    if (isBigInt) {
      final value = BigInt.parse(binaryPart, radix: 2);
      _addTokenWithLiteral(
        TokenType.bigint,
        lexeme,
        value,
        start,
        startLine,
        startColumn,
      );
    } else {
      final value = int.parse(binaryPart, radix: 2).toDouble();
      _addTokenWithLiteral(
        TokenType.number,
        lexeme,
        value,
        start,
        startLine,
        startColumn,
      );
    }
  }

  /// Scans an octal number (0o...)
  void _scanOctalNumber(int start, int startLine, int startColumn) {
    // Read octal digits (0-7) and underscores
    while (_isOctalDigit(_peek()) || _peek() == '_') {
      _advance();
    }

    // BigInt suffix
    bool isBigInt = false;
    if (_peek() == 'n') {
      _advance();
      isBigInt = true;
    }

    final lexeme = source.substring(start, _current);
    // Remove the 0o prefix and underscores
    final octalPart = lexeme
        .substring(2, isBigInt ? lexeme.length - 1 : lexeme.length)
        .replaceAll('_', '');

    if (isBigInt) {
      final value = BigInt.parse(octalPart, radix: 8);
      _addTokenWithLiteral(
        TokenType.bigint,
        lexeme,
        value,
        start,
        startLine,
        startColumn,
      );
    } else {
      final value = int.parse(octalPart, radix: 8).toDouble();
      _addTokenWithLiteral(
        TokenType.number,
        lexeme,
        value,
        start,
        startLine,
        startColumn,
      );
    }
  }

  /// Scans a legacy octal literal (010, 077, etc.) - DEPRECATED in strict mode
  /// These literals are allowed in non-strict mode but forbidden in strict mode
  void _scanLegacyOctalNumber(int start, int startLine, int startColumn) {
    // The initial '0' has already been consumed
    // Read all following octal digits
    while (_isOctalDigit(_peek())) {
      _advance();
    }

    // Check if a digit 8 or 9 follows (which would invalidate the octal)
    if (_isDigit(_peek())) {
      // This is not a valid octal, treat as decimal
      while (_isDigit(_peek()) || _peek() == '_') {
        _advance();
      }

      // Treat as a normal decimal number
      final lexeme = source.substring(start, _current);
      final cleanLexeme = lexeme.replaceAll('_', '');
      final value = double.parse(cleanLexeme);
      _addTokenWithLiteral(
        TokenType.number,
        lexeme,
        value,
        start,
        startLine,
        startColumn,
      );
      return;
    }

    final lexeme = source.substring(start, _current);
    final octalPart = lexeme; // The entire number without prefix

    // Parse as octal
    final value = int.parse(octalPart, radix: 8).toDouble();

    // Create a LEGACY_OCTAL token to allow detection in strict mode
    _addTokenWithLiteral(
      TokenType.legacyOctal,
      lexeme,
      value,
      start,
      startLine,
      startColumn,
    );
  }

  /// Checks if a character is a hexadecimal digit
  bool _isHexDigit(String char) {
    return _isDigit(char) ||
        (char.codeUnitAt(0) >= 'a'.codeUnitAt(0) &&
            char.codeUnitAt(0) <= 'f'.codeUnitAt(0)) ||
        (char.codeUnitAt(0) >= 'A'.codeUnitAt(0) &&
            char.codeUnitAt(0) <= 'F'.codeUnitAt(0));
  }

  /// Checks if a character is an octal digit (0-7)
  bool _isOctalDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= '0'.codeUnitAt(0) && code <= '7'.codeUnitAt(0);
  }

  /// Analyzes an identifier or keyword
  void _scanIdentifier(int start, int startLine, int startColumn) {
    while (!_isAtEnd()) {
      final char = _peek();

      if (_isAlphaNumeric(char)) {
        _advance();
      } else if (char == '\\') {
        // Peek ahead to see if this is a Unicode escape
        if (_peekAhead(1) == 'u') {
          // This is likely a Unicode escape - consume it
          _advance(); // consume backslash
          _advance(); // consume 'u'

          // Handle the hex digits or braces
          if (_peek() == '{') {
            _advance(); // consume '{'
            while (!_isAtEnd() && _peek() != '}') {
              _advance();
            }
            if (!_isAtEnd()) _advance(); // consume '}'
          } else {
            // \uXXXX format (4 hex digits)
            for (int i = 0; i < 4 && !_isAtEnd() && _isHexDigit(_peek()); i++) {
              _advance();
            }
          }
        } else {
          // Not a Unicode escape, stop scanning identifier
          break;
        }
      } else if (_isUnicodeIdentifierStart(char)) {
        // Accept Unicode characters in identifiers
        _advance();
      } else {
        // ASCII non-identifier character, stop here
        break;
      }
    }

    // Now process the raw source, replacing Unicode escapes
    final rawLexeme = source.substring(start, _current);
    final hasUnicodeEscapes = rawLexeme.contains('\\u');
    final lexeme = _processUnicodeEscapes(rawLexeme);

    // Check if this matches a keyword
    final keywordType = keywords[lexeme];

    // For contextual keywords (async, await, yield, static, get, set),
    // keep the keyword type but flag the Unicode escape.
    // The parser will validate if they're used in contexts where escapes aren't allowed.
    final contextualKeywords = {
      TokenType.keywordAsync,
      TokenType.keywordAwait,
      TokenType.keywordYield,
      TokenType.keywordStatic,
      TokenType.keywordGet,
      TokenType.keywordSet,
    };

    final TokenType type;
    if (hasUnicodeEscapes) {
      if (keywordType != null && contextualKeywords.contains(keywordType)) {
        // Keep contextual keyword type with escape flag for parser validation
        type = keywordType;
      } else {
        // For reserved keywords with escapes, treat as identifier
        // This allows escaped reserved words to be used as property names: n\u0065w() { }
        type = TokenType.identifier;
      }
    } else {
      // No escapes - use keyword type if matches, otherwise identifier
      type = keywordType ?? TokenType.identifier;
    }

    // Handle special literals
    dynamic literal;
    if (type == TokenType.keywordTrue || type == TokenType.keywordFalse) {
      literal = type == TokenType.keywordTrue;
    }

    if (literal != null) {
      _addTokenWithLiteral(
        type,
        lexeme,
        literal,
        start,
        startLine,
        startColumn,
      );
    } else {
      // Use escape flag version for identifiers that might be contextual keywords
      _addTokenWithEscapeFlag(
        type,
        lexeme,
        start,
        startLine,
        startColumn,
        hasUnicodeEscapes,
      );
    }
  }

  /// Process Unicode escape sequences in a string
  String _processUnicodeEscapes(String input) {
    final buffer = StringBuffer();
    int i = 0;

    while (i < input.length) {
      if (i < input.length - 1 && input[i] == '\\' && input[i + 1] == 'u') {
        i += 2; // skip \u

        if (i < input.length && input[i] == '{') {
          // \u{XXXXXX} format
          i++; // skip '{'
          final hexStart = i;
          while (i < input.length && input[i] != '}') {
            i++;
          }
          final hex = input.substring(hexStart, i);
          if (i < input.length) i++; // skip '}'

          if (hex.isNotEmpty) {
            try {
              final codePoint = int.parse(hex, radix: 16);
              if (codePoint <= 0x10FFFF) {
                buffer.writeCharCode(codePoint);
              } else {
                // Invalid code point - keep as is
                buffer.write('\\u{$hex}');
              }
            } catch (e) {
              // Invalid hex - keep as is
              buffer.write('\\u{$hex}');
            }
          }
        } else {
          // \uXXXX format (4 hex digits)
          final hexStart = i;
          for (int j = 0; j < 4 && i < input.length; j++, i++) {}
          final hex = input.substring(hexStart, i);

          if (hex.length == 4) {
            try {
              final codePoint = int.parse(hex, radix: 16);
              buffer.writeCharCode(codePoint);
            } catch (e) {
              // Invalid hex - keep as is
              buffer.write('\\u$hex');
            }
          } else {
            // Not enough hex digits - keep as is
            buffer.write('\\u$hex');
          }
        }
      } else {
        buffer.write(input[i]);
        i++;
      }
    }

    return buffer.toString();
  }

  /// Analyzes a private identifier (#privateField)
  void _scanPrivateIdentifier(int start, int startLine, int startColumn) {
    // Check that the next character is a valid identifier
    // Accept any character that could start an identifier (including Unicode)
    // or a Unicode escape sequence
    final nextChar = _peek();

    if (nextChar.isEmpty || nextChar == String.fromCharCode(0)) {
      throw LexerError(
        'Invalid private identifier: expected letter after #',
        _line,
        _column,
      );
    }

    // Check for backslash (start of Unicode escape) or normal identifier start
    // For normal characters, we accept anything that's not whitespace/special syntax chars
    if (nextChar != '\\') {
      // Allow any non-whitespace, non-syntax character as identifier start
      final code = nextChar.codeUnitAt(0);
      // Block characters that are clearly wrong
      if (code == 32 ||
          code == 9 ||
          code == 10 ||
          code == 13 || // whitespace
          nextChar == '{' ||
          nextChar == '}' ||
          nextChar == '(' ||
          nextChar == ')' ||
          nextChar == '[' ||
          nextChar == ']' ||
          nextChar == ',' ||
          nextChar == ';' ||
          nextChar == ':' ||
          nextChar == '?' ||
          nextChar == '.' ||
          nextChar == '@') {
        throw LexerError(
          'Invalid private identifier: expected letter after #',
          _line,
          _column,
        );
      }
    }

    // Scan the identifier name with support for Unicode escapes
    while (!_isAtEnd()) {
      final char = _peek();

      if (char.isEmpty || char == String.fromCharCode(0)) {
        break;
      }

      if (char == '\\') {
        // Peek ahead to see if this is a Unicode escape
        if (_peekAhead(1) == 'u') {
          // This is likely a Unicode escape - consume it
          _advance(); // consume backslash
          _advance(); // consume 'u'

          // Handle the hex digits or braces
          if (_peek() == '{') {
            _advance(); // consume '{'
            while (!_isAtEnd() && _peek() != '}') {
              _advance();
            }
            if (!_isAtEnd()) _advance(); // consume '}'
          } else {
            // \uXXXX format (4 hex digits)
            for (int i = 0; i < 4 && !_isAtEnd() && _isHexDigit(_peek()); i++) {
              _advance();
            }
          }
        } else {
          // Not a Unicode escape, stop scanning identifier
          break;
        }
      } else if (_isAlphaNumeric(char)) {
        _advance();
      } else {
        // Check for other valid identifier characters (Unicode, ZWJ, ZWNJ, etc.)
        final code = char.codeUnitAt(0);
        // Allow identifier continue characters including ZWJ (U+200D) and ZWNJ (U+200C)
        if (code == 0x200D || code == 0x200C) {
          _advance();
        } else {
          // For other Unicode characters, try to advance anyway
          // This is permissive to support Unicode identifiers
          if (code > 127) {
            // Any non-ASCII character
            _advance();
          } else {
            // ASCII non-identifier character, stop here
            break;
          }
        }
      }
    }

    final lexeme = source.substring(start, _current);
    _addToken(
      TokenType.privateIdentifier,
      lexeme,
      start,
      startLine,
      startColumn,
    );
  }

  /// Analyzes a single line comment
  void _scanSingleLineComment(int start, int startLine, int startColumn) {
    while (!_isAtEnd() && _peek() != '\n') {
      _advance();
    }
    // Note: we could ignore comments or keep them for formatting
  }

  /// Analyzes a multi-line comment
  void _scanMultiLineComment(int start, int startLine, int startColumn) {
    while (!_isAtEnd()) {
      if (_peek() == '*' && _peekNext() == '/') {
        _advance(); // Consume *
        _advance(); // Consume /
        break;
      }
      if (_peek() == '\n') {
        _line++;
        _column = 1;
      } else if (_peek() == '\r') {
        // CR is a line terminator; consume CRLF as single terminator
        _advance();
        if (!_isAtEnd() && _peek() == '\n') {
          _advance();
        }
        _line++;
        _column = 1;
        continue; // Already advanced past the CR (and optional LF)
      }
      _advance();
    }
  }

  /// Analyzes a regex literal /pattern/flags
  void _scanRegexLiteral(int start, int startLine, int startColumn) {
    final buffer = StringBuffer();
    var inCharacterClass = false;

    // Scan the pattern (until the next unescaped '/' AND outside character class)
    while (!_isAtEnd()) {
      final current = _peek();

      if (current == '\\') {
        // Escape the next character
        buffer.write(_advance()); // Add the backslash
        if (!_isAtEnd()) {
          buffer.write(_advance()); // Add the escaped character
        }
      } else if (current == '[' && !inCharacterClass) {
        // Start of a character class
        inCharacterClass = true;
        buffer.write(_advance());
      } else if (current == ']' && inCharacterClass) {
        // End of a character class
        inCharacterClass = false;
        buffer.write(_advance());
      } else if (current == '/' && !inCharacterClass) {
        // End of the regex (only if not inside a character class)
        break;
      } else if (current == '\n') {
        throw LexerError(
          'Unterminated regular expression literal',
          _line,
          _column,
        );
      } else {
        buffer.write(_advance());
      }
    }

    if (_isAtEnd()) {
      throw LexerError(
        'Unterminated regular expression literal',
        _line,
        _column,
      );
    }

    // Consume the ending '/'
    _advance();

    // Scan the flags (letters that immediately follow)
    final flags = StringBuffer();
    while (!_isAtEnd() && _isAlpha(_peek())) {
      flags.write(_advance());
    }

    // Create the token value (pattern + flags)
    final regexValue = '/${buffer.toString()}/${flags.toString()}';

    _addToken(TokenType.regex, regexValue, start, startLine, startColumn);
  }

  /// Utilities for navigation in the source code
  bool _isAtEnd() => _current >= source.length;

  String _advance() {
    if (_isAtEnd()) return String.fromCharCode(0); // True NUL character
    _column++;
    return source[_current++];
  }

  bool _match(String expected) {
    if (_isAtEnd()) return false;
    if (source[_current] != expected) return false;
    _current++;
    _column++;
    return true;
  }

  String _peek() {
    if (_isAtEnd()) return String.fromCharCode(0); // True NUL character
    return source[_current];
  }

  String _peekNext() {
    if (_current + 1 >= source.length) {
      return String.fromCharCode(0); // True NUL character
    }
    return source[_current + 1];
  }

  /// Utilities for characters
  bool _isDigit(String char) {
    if (char.isEmpty) return false;
    final code = char.codeUnitAt(0);
    if (code == 0) return false; // True NUL character
    return code >= 48 && code <= 57;
  }

  bool _isAlpha(String char) {
    if (char.isEmpty) return false;
    final code = char.codeUnitAt(0);
    if (code == 0) return false; // True NUL character
    return (code >= 65 && code <= 90) || // A-Z
        (code >= 97 && code <= 122) || // a-z
        code == 95 || // _
        code == 36; // $ (dollar sign - valid in JavaScript)
  }

  bool _isAlphaNumeric(String char) => _isAlpha(char) || _isDigit(char);

  bool _isUnicodeWhitespace(String char) {
    if (char.isEmpty) return false;
    final code = char.codeUnitAt(0);

    // ES2024 Whitespace characters:
    // Tab, Vertical Tab, Form Feed, Space (ASCII)
    if (code == 0x0009 || code == 0x000B || code == 0x000C || code == 0x0020) {
      return true;
    }

    // No-break space
    if (code == 0x00A0) return true;

    // Ogham space mark
    if (code == 0x1680) return true;

    // Space Separator characters (U+2000-U+200A)
    // Includes: EN QUAD, EM QUAD, EN SPACE, EM SPACE, THREE-PER-EM SPACE,
    //           FOUR-PER-EM SPACE, SIX-PER-EM SPACE, FIGURE SPACE, PUNCTUATION SPACE,
    //           THIN SPACE, HAIR SPACE
    if (code >= 0x2000 && code <= 0x200A) return true;

    // Line Separator and Paragraph Separator
    if (code == 0x2028 || code == 0x2029) return true;

    // Narrow no-break space
    if (code == 0x202F) return true;

    // Medium mathematical space
    if (code == 0x205F) return true;

    // Ideographic space
    if (code == 0x3000) return true;

    // Zero-width no-break space (BOM character, also treated as whitespace per ES spec)
    if (code == 0xFEFF) return true;

    return false;
  }

  bool _isUnicodeIdentifierStart(String char) {
    if (char.isEmpty) return false;

    // Get the code point (handles surrogates properly in Dart)
    final runes = char.runes.toList();
    if (runes.isEmpty) return false;

    final codePoint = runes[0]; // Get the actual Unicode code point

    // ASCII letters, underscore, dollar sign (already covered by _isAlpha)
    if (codePoint >= 65 && codePoint <= 90) return true; // A-Z
    if (codePoint >= 97 && codePoint <= 122) return true; // a-z
    if (codePoint == 95 || codePoint == 36) return true; // _ or $

    // ASCII digits are not identifier starts
    if (codePoint >= 48 && codePoint <= 57) return false;

    // ASCII punctuation and control characters
    if (codePoint < 128) return false;

    // Non-ASCII characters: be permissive and accept them as potential identifiers
    // This includes Unicode letters, marks, and other identifier characters

    // Specific exclusions for control characters
    if (codePoint >= 0x0000 && codePoint <= 0x001F) return false; // C0 controls
    if (codePoint >= 0x007F && codePoint <= 0x009F) {
      return false; // DEL and C1 controls
    }
    // Line/Paragraph separators are line terminators, not identifiers
    if (codePoint == 0x2028 || codePoint == 0x2029) return false;
    if (codePoint >= 0xFDD0 && codePoint <= 0xFDEF) {
      return false; // Non-characters
    }
    if ((codePoint & 0xFFFE) == 0xFFFE) return false; // Non-characters

    return true; // Accept all other Unicode characters as potential identifier starts
  }

  /// Adds a token to the list
  void _addToken(
    TokenType type,
    String lexeme,
    int start,
    int line,
    int column,
  ) {
    _tokens.add(Token.simple(type, lexeme, line, column, start, _current));
    // Track line of last added token for HTML close comment detection
    _lastTokenLine = line;
  }

  /// Adds a token with hasUnicodeEscape flag
  void _addTokenWithEscapeFlag(
    TokenType type,
    String lexeme,
    int start,
    int line,
    int column,
    bool hasUnicodeEscape,
  ) {
    _tokens.add(
      Token(
        type: type,
        lexeme: lexeme,
        line: line,
        column: column,
        start: start,
        end: _current,
        hasUnicodeEscape: hasUnicodeEscape,
      ),
    );
  }

  void _addTokenWithLiteral(
    TokenType type,
    String lexeme,
    dynamic literal,
    int start,
    int line,
    int column,
  ) {
    _tokens.add(
      Token.withLiteral(type, lexeme, literal, line, column, start, _current),
    );
  }

  Token _makeToken(TokenType type, String lexeme) {
    return Token.simple(type, lexeme, _line, _column, _current, _current);
  }

  /// Analyzes an HTML open comment <!--
  /// Annex B feature: HTML-like comments
  /// SingleLineHTMLOpenComment :: <!--SingleLineCommentCharsopt
  void _scanHTMLOpenComment(int start, int startLine, int startColumn) {
    // Consume <!--
    _advance(); // <
    _advance(); // !
    _advance(); // -
    _advance(); // -

    // Rest of line is a comment
    while (!_isAtEnd() && _peek() != '\n') {
      _advance();
    }
    // Don't consume the newline - let the main loop handle it

    // HTML comments are ignored, no token added
  }

  /// Analyzes an HTML close comment -->
  /// Annex B feature: HTML-like comments
  /// SingleLineHTMLCloseComment :: LineTerminatorSequence HTMLCloseComment
  /// HTMLCloseComment :: WhiteSpaceSequence[opt] SingleLineDelimitedCommentSequence[opt] --> SingleLineCommentChars[opt]
  void _scanHTMLCloseComment(int start, int startLine, int startColumn) {
    // Consume -->
    _advance(); // -
    _advance(); // -
    _advance(); // >

    // Rest of line is a comment
    while (!_isAtEnd() && _peek() != '\n') {
      _advance();
    }
    // Don't consume the newline - let the main loop handle it

    // HTML comments are ignored, no token added
  }
}
