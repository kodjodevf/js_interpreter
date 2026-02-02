/// Token system for JavaScript lexical analysis
library;

/// JavaScript token types
enum TokenType {
  // End of file
  eof,

  // Literals
  number,
  bigint,
  legacyOctal, // 010, 077 - legacy octals (forbidden in strict mode)
  string,
  booleanLiteral,
  nullLiteral,
  undefinedLiteral,
  regex, // /pattern/flags
  // Template literals
  templateString, // `text` or `text${
  templateExpression, // }text` ou }text${
  templateEnd, // }text`
  // Identifiers and keywords
  identifier,
  privateIdentifier, // #privateField
  // JavaScript keywords
  // Declarations
  keywordVar,
  keywordLet,
  keywordConst,
  keywordFunction,
  keywordClass,
  keywordImport,
  keywordExport,
  keywordFrom,
  keywordAs,
  keywordExtends,
  keywordStatic,
  keywordGet,
  keywordSet,
  keywordNew,
  keywordThis,
  keywordSuper,

  // Control flow
  keywordIf,
  keywordElse,
  keywordFor,
  keywordWhile,
  keywordDo,
  keywordSwitch,
  keywordCase,
  keywordDefault,
  keywordBreak,
  keywordContinue,
  keywordReturn,
  keywordThrow,
  keywordTry,
  keywordCatch,
  keywordFinally,

  // Special values
  keywordTrue,
  keywordFalse,
  keywordNull,
  keywordUndefined,

  // Other keywords
  keywordTypeof,
  keywordInstanceof,
  keywordIn,
  keywordOf,
  keywordDelete,
  keywordVoid,
  keywordWith, // with statement (interdit en strict mode)
  keywordAsync,
  keywordAwait,
  keywordYield,

  // Arithmetic operators
  plus, // +
  minus, // -
  multiply, // *
  divide, // /
  modulo, // %
  exponent, // **
  // Assignment operators
  assign, // =
  plusAssign, // +=
  minusAssign, // -=
  multiplyAssign, // *=
  divideAssign, // /=
  moduloAssign, // %=
  exponentAssign, // **=
  andAssign, // &&=
  orAssign, // ||=
  nullishCoalescingAssign, // ??=
  bitwiseAndAssign, // &=
  bitwiseOrAssign, // |=
  bitwiseXorAssign, // ^=
  leftShiftAssign, // <<=
  rightShiftAssign, // >>=
  unsignedRightShiftAssign, // >>>=
  // Comparison operators
  equal, // ==
  notEqual, // !=
  strictEqual, // ===
  strictNotEqual, // !==
  lessThan, // <
  lessThanEqual, // <=
  greaterThan, // >
  greaterThanEqual, // >=
  // Logical operators
  logicalAnd, // &&
  logicalOr, // ||
  logicalNot, // !
  // Bitwise operators
  bitwiseAnd, // &
  bitwiseOr, // |
  bitwiseXor, // ^
  bitwiseNot, // ~
  leftShift, // <<
  rightShift, // >>
  unsignedRightShift, // >>>
  // Increment/decrement operators
  increment, // ++
  decrement, // --
  // Delimiters
  leftParen, // (
  rightParen, // )
  leftBrace, // {
  rightBrace, // }
  leftBracket, // [
  rightBracket, // ]
  // Punctuation
  semicolon, // ;
  comma, // ,
  dot, // .
  colon, // :
  question, // ?
  // Special operators
  arrow, // =>
  spread, // ...
  optionalChaining, // ?.
  nullishCoalescing, // ??
  // Comments
  singleLineComment,
  multiLineComment,

  // Whitespace characters
  whitespace,
  newline,

  // Invalid characters
  invalid,
}

/// Represents a token with its position in the source code
class Token {
  final TokenType type;
  final String lexeme;
  final dynamic literal; // Literal value for numbers, strings, etc.
  final int line;
  final int column;
  final int start;
  final int end;
  final bool hasUnicodeEscape; // True if identifier contains \uXXXX escapes

  const Token({
    required this.type,
    required this.lexeme,
    this.literal,
    required this.line,
    required this.column,
    required this.start,
    required this.end,
    this.hasUnicodeEscape = false,
  });

  /// Creates a simple token without a literal value
  factory Token.simple(
    TokenType type,
    String lexeme,
    int line,
    int column,
    int start,
    int end,
  ) {
    return Token(
      type: type,
      lexeme: lexeme,
      line: line,
      column: column,
      start: start,
      end: end,
    );
  }

  /// Creates a token with a literal value
  factory Token.withLiteral(
    TokenType type,
    String lexeme,
    dynamic literal,
    int line,
    int column,
    int start,
    int end,
  ) {
    return Token(
      type: type,
      lexeme: lexeme,
      literal: literal,
      line: line,
      column: column,
      start: start,
      end: end,
    );
  }

  @override
  String toString() {
    final literalStr = literal != null ? ' ($literal)' : '';
    return 'Token(${type.name}, "$lexeme"$literalStr, $line:$column)';
  }

  /// Checks if this token is of a given type
  bool isType(TokenType expectedType) => type == expectedType;

  /// Checks if this token is one of the given types
  bool isOneOf(List<TokenType> types) => types.contains(type);

  /// Checks if this token is a keyword
  bool get isKeyword => _keywordTypes.contains(type);

  /// Checks if this token is an operator
  bool get isOperator => _operatorTypes.contains(type);

  /// Checks if this token is a delimiter
  bool get isDelimiter => _delimiterTypes.contains(type);

  /// Checks if this token is a literal
  bool get isLiteral => _literalTypes.contains(type);
}

/// Sets of token types for checks
const Set<TokenType> _keywordTypes = {
  TokenType.keywordVar,
  TokenType.keywordLet,
  TokenType.keywordConst,
  TokenType.keywordFunction,
  TokenType.keywordClass,
  TokenType.keywordNew,
  TokenType.keywordThis,
  TokenType.keywordSuper,
  TokenType.keywordIf,
  TokenType.keywordElse,
  TokenType.keywordFor,
  TokenType.keywordWhile,
  TokenType.keywordDo,
  TokenType.keywordSwitch,
  TokenType.keywordCase,
  TokenType.keywordDefault,
  TokenType.keywordBreak,
  TokenType.keywordContinue,
  TokenType.keywordReturn,
  TokenType.keywordThrow,
  TokenType.keywordTry,
  TokenType.keywordCatch,
  TokenType.keywordFinally,
  TokenType.keywordTrue,
  TokenType.keywordFalse,
  TokenType.keywordNull,
  TokenType.keywordUndefined,
  TokenType.keywordTypeof,
  TokenType.keywordInstanceof,
  TokenType.keywordIn,
  TokenType.keywordOf,
  TokenType.keywordDelete,
  TokenType.keywordVoid,
};

const Set<TokenType> _operatorTypes = {
  TokenType.plus,
  TokenType.minus,
  TokenType.multiply,
  TokenType.divide,
  TokenType.modulo,
  TokenType.exponent,
  TokenType.assign,
  TokenType.plusAssign,
  TokenType.minusAssign,
  TokenType.multiplyAssign,
  TokenType.divideAssign,
  TokenType.moduloAssign,
  TokenType.bitwiseAndAssign,
  TokenType.bitwiseOrAssign,
  TokenType.bitwiseXorAssign,
  TokenType.leftShiftAssign,
  TokenType.rightShiftAssign,
  TokenType.unsignedRightShiftAssign,
  TokenType.equal,
  TokenType.notEqual,
  TokenType.strictEqual,
  TokenType.strictNotEqual,
  TokenType.lessThan,
  TokenType.lessThanEqual,
  TokenType.greaterThan,
  TokenType.greaterThanEqual,
  TokenType.logicalAnd,
  TokenType.logicalOr,
  TokenType.logicalNot,
  TokenType.bitwiseAnd,
  TokenType.bitwiseOr,
  TokenType.bitwiseXor,
  TokenType.bitwiseNot,
  TokenType.leftShift,
  TokenType.rightShift,
  TokenType.unsignedRightShift,
  TokenType.increment,
  TokenType.decrement,
  TokenType.arrow,
  TokenType.spread,
};

const Set<TokenType> _delimiterTypes = {
  TokenType.leftParen,
  TokenType.rightParen,
  TokenType.leftBrace,
  TokenType.rightBrace,
  TokenType.leftBracket,
  TokenType.rightBracket,
  TokenType.semicolon,
  TokenType.comma,
  TokenType.dot,
  TokenType.colon,
  TokenType.question,
};

const Set<TokenType> _literalTypes = {
  TokenType.number,
  TokenType.string,
  TokenType.booleanLiteral,
  TokenType.nullLiteral,
  TokenType.undefinedLiteral,
};

/// Map of JavaScript keywords
const Map<String, TokenType> keywords = {
  'var': TokenType.keywordVar,
  'let': TokenType.keywordLet,
  'const': TokenType.keywordConst,
  'function': TokenType.keywordFunction,
  'class': TokenType.keywordClass,
  'import': TokenType.keywordImport,
  'export': TokenType.keywordExport,
  // 'from' is NOT a reserved keyword in JavaScript!
  // It's a contextual keyword used only in import/export
  // 'from': TokenType.keywordFrom,
  'as': TokenType.keywordAs,
  'extends': TokenType.keywordExtends,
  'static': TokenType.keywordStatic,
  // 'get' and 'set' are NOT reserved keywords in JavaScript!
  // These are contextual keywords used only in getter/setter definitions
  // 'get': TokenType.keywordGet,
  // 'set': TokenType.keywordSet,
  'new': TokenType.keywordNew,
  'this': TokenType.keywordThis,
  'super': TokenType.keywordSuper,
  'if': TokenType.keywordIf,
  'else': TokenType.keywordElse,
  'for': TokenType.keywordFor,
  'while': TokenType.keywordWhile,
  'do': TokenType.keywordDo,
  'switch': TokenType.keywordSwitch,
  'case': TokenType.keywordCase,
  'default': TokenType.keywordDefault,
  'break': TokenType.keywordBreak,
  'continue': TokenType.keywordContinue,
  'return': TokenType.keywordReturn,
  'throw': TokenType.keywordThrow,
  'try': TokenType.keywordTry,
  'catch': TokenType.keywordCatch,
  'finally': TokenType.keywordFinally,
  'true': TokenType.keywordTrue,
  'false': TokenType.keywordFalse,
  'null': TokenType.keywordNull,
  'undefined': TokenType.keywordUndefined,
  'typeof': TokenType.keywordTypeof,
  'instanceof': TokenType.keywordInstanceof,
  'in': TokenType.keywordIn,
  'of': TokenType.keywordOf,
  'delete': TokenType.keywordDelete,
  'void': TokenType.keywordVoid,
  'with': TokenType.keywordWith,
  'async': TokenType.keywordAsync,
  'await': TokenType.keywordAwait,
  'yield': TokenType.keywordYield,
};

/// Utilities for tokens
class TokenUtils {
  /// Returns the display name of a token type
  static String getDisplayName(TokenType type) {
    switch (type) {
      case TokenType.eof:
        return 'end of file';
      case TokenType.identifier:
        return 'identifier';
      case TokenType.number:
        return 'number';
      case TokenType.string:
        return 'string';
      case TokenType.plus:
        return '+';
      case TokenType.minus:
        return '-';
      case TokenType.multiply:
        return '*';
      case TokenType.divide:
        return '/';
      case TokenType.assign:
        return '=';
      case TokenType.leftParen:
        return '(';
      case TokenType.rightParen:
        return ')';
      case TokenType.leftBrace:
        return '{';
      case TokenType.rightBrace:
        return '}';
      case TokenType.semicolon:
        return ';';
      default:
        return type.name;
    }
  }

  /// Returns the precedence of an operator (higher = more priority)
  static int getOperatorPrecedence(TokenType type) {
    switch (type) {
      case TokenType.dot:
        return 19;
      case TokenType.leftParen: // Function call
        return 19;
      case TokenType.leftBracket: // Member access
        return 19;
      case TokenType.increment:
      case TokenType.decrement:
        return 16; // Postfix
      case TokenType.logicalNot:
      case TokenType.bitwiseNot:
        return 15; // Unary
      case TokenType.exponent:
        return 14;
      case TokenType.multiply:
      case TokenType.divide:
      case TokenType.modulo:
        return 13;
      case TokenType.plus:
      case TokenType.minus:
        return 12;
      case TokenType.leftShift:
      case TokenType.rightShift:
      case TokenType.unsignedRightShift:
        return 11;
      case TokenType.lessThan:
      case TokenType.lessThanEqual:
      case TokenType.greaterThan:
      case TokenType.greaterThanEqual:
        return 10;
      case TokenType.equal:
      case TokenType.notEqual:
      case TokenType.strictEqual:
      case TokenType.strictNotEqual:
        return 9;
      case TokenType.bitwiseAnd:
        return 8;
      case TokenType.bitwiseXor:
        return 7;
      case TokenType.bitwiseOr:
        return 6;
      case TokenType.logicalAnd:
        return 5;
      case TokenType.logicalOr:
        return 4;
      case TokenType.question: // Ternary
        return 3;
      case TokenType.assign:
      case TokenType.plusAssign:
      case TokenType.minusAssign:
      case TokenType.multiplyAssign:
      case TokenType.divideAssign:
      case TokenType.moduloAssign:
        return 2;
      case TokenType.comma:
        return 1;
      default:
        return 0;
    }
  }

  /// Checks if an operator is right associative
  static bool isRightAssociative(TokenType type) {
    switch (type) {
      case TokenType.exponent:
      case TokenType.assign:
      case TokenType.plusAssign:
      case TokenType.minusAssign:
      case TokenType.multiplyAssign:
      case TokenType.divideAssign:
      case TokenType.moduloAssign:
      case TokenType.question:
        return true;
      default:
        return false;
    }
  }
}
