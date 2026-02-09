/// JavaScript Parser
/// Syntax analysis to transform tokens into AST
library;

import '../lexer/token.dart';
import '../lexer/lexer.dart';
import 'ast_nodes.dart';

/// Info about a label for break/continue validation
class _LabelInfo {
  final bool isLoop; // true if targets a loop (for/while/do-while)
  final bool isSwitch; // true if targets a switch
  final int functionDepth; // function nesting depth when label was registered

  bool get isLoopOrSwitch => isLoop || isSwitch;

  _LabelInfo({
    required this.isLoop,
    required this.isSwitch,
    required this.functionDepth,
  });
}

/// Exception raised during syntax analysis errors
class ParseError extends Error {
  final String message;
  final Token token;

  ParseError(this.message, this.token);

  @override
  String toString() =>
      'SyntaxError: ParseError at ${token.line}:${token.column}: $message';
}

/// JavaScript Syntax Analyzer (Recursive Descent Parser)
class JSParser {
  final List<Token> tokens;
  int _current = 0;
  bool _initialStrictMode =
      false; // Initial strict mode context (e.g., from eval caller)

  // Context tracking for contextual keywords (await/yield)
  bool _inAsyncContext = false;
  bool _inGeneratorContext = false;
  int _functionDepth = 0; // Track function nesting (0 = top-level)
  bool _inClassContext = false; // Track if we're parsing class-related code

  // Context tracking for break/continue validation
  int _loopDepth = 0; // Count of nested loops (for/while/do-while)
  int _switchDepth = 0; // Count of nested switch statements
  // Map of label -> label info (isLoopOrSwitch, functionDepth)
  final Map<String, _LabelInfo> _labelStack = {};

  JSParser(this.tokens, {bool initialStrictMode = false})
    : _initialStrictMode = initialStrictMode;

  /// Check if parameters are "simple" (no destructuring, defaults, or rest)
  /// ES6 14.1.2: Cannot have "use strict" in body if params are non-simple
  static bool _isSimpleParameterList(List<Parameter> params) {
    for (final param in params) {
      if (param.isDestructuring || param.defaultValue != null || param.isRest) {
        return false;
      }
    }
    return true;
  }

  /// Validate async function parameters - no 'await' allowed
  void _validateAsyncFunctionParameters(
    List<Parameter> params,
    int line,
    int column,
  ) {
    final seenNames = <String>{};

    for (final param in params) {
      // Get all bound names from this parameter
      final boundNames = _getParameterBoundNames(param);

      for (final paramName in boundNames) {
        // Check for duplicate parameter names
        if (seenNames.contains(paramName)) {
          throw ParseError(
            'Identifier \'$paramName\' has already been declared',
            _peek(),
          );
        }
        seenNames.add(paramName);

        // 'await' is never allowed in async function parameters
        if (paramName == 'await') {
          throw ParseError(
            'await is not a valid parameter name in async functions',
            _peek(),
          );
        }

        // 'arguments' and 'eval' are not allowed in strict mode parameters
        if (_isInStrictMode() &&
            (paramName == 'arguments' || paramName == 'eval')) {
          throw ParseError(
            'The identifier \'$paramName\' cannot be used as a parameter in strict mode',
            _peek(),
          );
        }
      }

      // Check default values for await identifier references
      if (param.defaultValue != null) {
        _validateAwaitInExpression(param.defaultValue!, isAsync: true);
        // Check for super() calls in parameter defaults
        if (_containsSuperCall(param.defaultValue!)) {
          throw ParseError(
            'super() calls are not allowed in parameter default values',
            _peek(),
          );
        }
        // Check for super.property access in parameter defaults
        if (_containsSuperProperty(param.defaultValue!)) {
          throw ParseError(
            'super property access is not allowed in parameter default values',
            _peek(),
          );
        }
      }

      // Check destructuring patterns
      if (param.isDestructuring && param.pattern != null) {
        // The pattern contains await references which we need to validate
        _validateAwaitInPattern(param.pattern!);
      }
    }
  }

  /// Validate function parameters for duplicate names (works for all function types)
  void _validateFunctionParameters(
    List<Parameter> params,
    int line,
    int column,
  ) {
    final seenNames = <String>{};

    for (final param in params) {
      // Get all bound names from this parameter
      final boundNames = _getParameterBoundNames(param);

      for (final paramName in boundNames) {
        // Check for duplicate parameter names
        if (seenNames.contains(paramName)) {
          throw ParseError(
            'Identifier \'$paramName\' has already been declared',
            _peek(),
          );
        }
        seenNames.add(paramName);

        // 'arguments' and 'eval' are not allowed in strict mode parameters
        if (_isInStrictMode() &&
            (paramName == 'arguments' || paramName == 'eval')) {
          throw ParseError(
            'The identifier \'$paramName\' cannot be used as a parameter in strict mode',
            _peek(),
          );
        }
      }

      // Check default values for super() and super.property
      if (param.defaultValue != null) {
        // Check for super() calls in parameter defaults
        if (_containsSuperCall(param.defaultValue!)) {
          throw ParseError(
            'super() calls are not allowed in parameter default values',
            _peek(),
          );
        }
        // Check for super.property access in parameter defaults
        if (_containsSuperProperty(param.defaultValue!)) {
          throw ParseError(
            'super property access is not allowed in parameter default values',
            _peek(),
          );
        }
      }
    }
  }

  /// Helper to check for await in expressions (used in async function validation)
  void _validateAwaitInExpression(Expression expr, {bool isAsync = false}) {
    if (expr is IdentifierExpression && expr.name == 'await' && isAsync) {
      throw ParseError(
        'await is not a valid identifier reference in async function parameters',
        _peek(),
      );
    }
    // Could recursively check nested expressions if needed
  }

  /// Helper to check for await in patterns
  void _validateAwaitInPattern(Pattern pattern) {
    // This would need to recursively check patterns for await identifiers
    // For now, basic implementation
  }

  /// Check if block body starts with "use strict" directive
  static bool _hasUseStrictDirective(BlockStatement body) {
    if (body.body.isEmpty) return false;
    final firstStmt = body.body.first;
    if (firstStmt is! ExpressionStatement) return false;
    final expr = firstStmt.expression;
    if (expr is! LiteralExpression) return false;
    return expr.value == 'use strict';
  }

  /// Validate that function doesn't combine non-simple params with "use strict"
  void _validateStrictModeWithParams(
    List<Parameter> params,
    BlockStatement body,
    int line,
    int column,
  ) {
    if (!_isSimpleParameterList(params) && _hasUseStrictDirective(body)) {
      throw LexerError(
        'SyntaxError: Illegal \'use strict\' directive in function with non-simple parameter list',
        line,
        column,
      );
    }
  }

  /// Validate async arrow function parameters for early errors
  void _validateAsyncArrowParameters(
    List<Parameter> params,
    int line,
    int column,
    bool isStrict,
  ) {
    final seenNames = <String>{};

    for (final param in params) {
      final names = _getParameterBoundNames(param);
      for (final name in names) {
        // Check for duplicate parameter names (always error in arrow functions)
        if (seenNames.contains(name)) {
          throw LexerError(
            'SyntaxError: Duplicate parameter name not allowed in this context',
            line,
            column,
          );
        }
        seenNames.add(name);

        // Check for 'await' as parameter name in async function
        if (name == 'await') {
          throw LexerError(
            'SyntaxError: Unexpected reserved word',
            line,
            column,
          );
        }

        // Check for 'arguments' or 'eval' in strict mode
        if (isStrict && (name == 'arguments' || name == 'eval')) {
          throw LexerError(
            'SyntaxError: Unexpected eval or arguments in strict mode',
            line,
            column,
          );
        }
      }
    }
  }

  /// Validate that parameter names don't conflict with lexically declared names in body
  void _validateParamsVsLexicalDeclarations(
    List<Parameter> params,
    BlockStatement body,
    int line,
    int column,
  ) {
    final paramNames = <String>{};
    for (final param in params) {
      paramNames.addAll(_getParameterBoundNames(param));
    }

    final lexicalNames = _getLexicallyDeclaredNames(body);

    for (final name in paramNames) {
      if (lexicalNames.contains(name)) {
        throw LexerError(
          'SyntaxError: Identifier \'$name\' has already been declared',
          line,
          column,
        );
      }
    }
  }

  /// Get all bound names from a parameter
  Set<String> _getParameterBoundNames(Parameter param) {
    final names = <String>{};

    if (param.name != null) {
      names.add(param.name!.name);
    }

    if (param.pattern != null) {
      names.addAll(_getBoundNamesFromPattern(param.pattern!));
    }

    return names;
  }

  /// Get bound names from a destructuring pattern
  List<String> _getBoundNamesFromPattern(Pattern pattern) {
    final names = <String>[];

    if (pattern is IdentifierPattern) {
      names.add(pattern.name);
    } else if (pattern is ArrayPattern) {
      for (final elem in pattern.elements) {
        if (elem != null) {
          names.addAll(_getBoundNamesFromPattern(elem));
        }
      }
      // Also handle rest element
      if (pattern.restElement != null) {
        names.addAll(_getBoundNamesFromPattern(pattern.restElement!));
      }
    } else if (pattern is ObjectPattern) {
      for (final prop in pattern.properties) {
        final propValue = prop.value;
        names.addAll(_getBoundNamesFromPattern(propValue));
      }
      // Also handle rest element
      if (pattern.restElement != null) {
        names.addAll(_getBoundNamesFromPattern(pattern.restElement!));
      }
    } else if (pattern is AssignmentPattern) {
      names.addAll(_getBoundNamesFromPattern(pattern.left));
    }
    // Note: RestElement/SpreadElement are handled differently in our AST
    // For array patterns with rest, the rest element is an IdentifierPattern

    return names;
  }

  /// Get lexically declared names (let, const) from a block statement
  Set<String> _getLexicallyDeclaredNames(BlockStatement body) {
    final names = <String>{};

    for (final stmt in body.body) {
      if (stmt is VariableDeclaration &&
          (stmt.kind == 'let' || stmt.kind == 'const')) {
        for (final decl in stmt.declarations) {
          if (decl.id is IdentifierPattern) {
            names.add((decl.id as IdentifierPattern).name);
          }
          // Also handle destructuring patterns in let/const
          if (decl.id is ArrayPattern || decl.id is ObjectPattern) {
            names.addAll(_getBoundNamesFromPattern(decl.id));
          }
        }
      }
    }

    return names;
  }

  /// Extract a single name from a pattern (for variable declarations)
  String _extractNameFromPattern(Pattern pattern) {
    if (pattern is IdentifierPattern) {
      return pattern.name;
    } else if (pattern is ArrayPattern) {
      // For array patterns, get all names and return as comma-separated
      // (This is for error messages, should not happen in simple var declarations)
      final names = _getBoundNamesFromPattern(pattern).toList();
      return names.isNotEmpty ? names.first : 'unknown';
    } else if (pattern is ObjectPattern) {
      // Similarly for object patterns
      final names = _getBoundNamesFromPattern(pattern).toList();
      return names.isNotEmpty ? names.first : 'unknown';
    } else if (pattern is AssignmentPattern) {
      return _extractNameFromPattern(pattern.left);
    }
    return 'unknown';
  }

  /// Validate await in default parameter values (not allowed in async functions)
  void _validateNoAwaitInDefaults(
    List<Parameter> params,
    int line,
    int column,
  ) {
    for (final param in params) {
      if (param.defaultValue != null) {
        if (_containsAwait(param.defaultValue!)) {
          throw LexerError(
            'SyntaxError: await is not valid in this context',
            line,
            column,
          );
        }
      }
    }
  }

  /// Check if an expression contains 'await'
  bool _containsAwait(Expression expr) {
    if (expr is AwaitExpression) {
      return true;
    }
    if (expr is BinaryExpression) {
      return _containsAwait(expr.left) || _containsAwait(expr.right);
    }
    if (expr is UnaryExpression) {
      return _containsAwait(expr.operand);
    }
    if (expr is ConditionalExpression) {
      return _containsAwait(expr.test) ||
          _containsAwait(expr.consequent) ||
          _containsAwait(expr.alternate);
    }
    if (expr is CallExpression) {
      if (_containsAwait(expr.callee)) return true;
      for (final arg in expr.arguments) {
        if (_containsAwait(arg)) return true;
      }
    }
    if (expr is MemberExpression) {
      if (_containsAwait(expr.object)) return true;
      final prop = expr.property;
      if (_containsAwait(prop)) return true;
    }
    if (expr is ArrayExpression) {
      for (final elem in expr.elements) {
        if (elem is Expression) {
          if (_containsAwait(elem)) return true;
        }
      }
    }
    if (expr is ObjectExpression) {
      for (final prop in expr.properties) {
        if (prop.value is Expression &&
            _containsAwait(prop.value as Expression)) {
          return true;
        }
      }
    }
    if (expr is SequenceExpression) {
      for (final e in expr.expressions) {
        if (_containsAwait(e)) return true;
      }
    }
    if (expr is AssignmentExpression) {
      return _containsAwait(expr.right);
    }
    // IdentifierExpression named 'await' is valid as a reference,
    // but we catch actual AwaitExpression above
    if (expr is IdentifierExpression && expr.name == 'await') {
      // This is referencing a variable named 'await', which should have been
      // caught as a syntax error in async context during parsing
      return false;
    }
    return false;
  }

  /// Check if an expression or statement contains super() call
  bool _containsSuperCall(dynamic node) {
    if (node == null) return false;

    if (node is CallExpression) {
      // Check if callee is 'super'
      if (node.callee is SuperExpression) {
        return true;
      }
      // Check callee and arguments
      if (_containsSuperCall(node.callee)) return true;
      for (final arg in node.arguments) {
        if (_containsSuperCall(arg)) return true;
      }
    }
    if (node is SuperExpression) {
      return false; // SuperExpression alone (super.foo) is not a call
    }
    if (node is MemberExpression) {
      return _containsSuperCall(node.object);
    }
    if (node is BinaryExpression) {
      return _containsSuperCall(node.left) || _containsSuperCall(node.right);
    }
    if (node is UnaryExpression) {
      return _containsSuperCall(node.operand);
    }
    if (node is AssignmentExpression) {
      return _containsSuperCall(node.right);
    }
    if (node is ConditionalExpression) {
      return _containsSuperCall(node.test) ||
          _containsSuperCall(node.consequent) ||
          _containsSuperCall(node.alternate);
    }
    if (node is BlockStatement) {
      for (final stmt in node.body) {
        if (_containsSuperCall(stmt)) return true;
      }
    }
    if (node is ExpressionStatement) {
      return _containsSuperCall(node.expression);
    }
    if (node is ReturnStatement) {
      return _containsSuperCall(node.argument);
    }
    if (node is IfStatement) {
      return _containsSuperCall(node.test) ||
          _containsSuperCall(node.consequent) ||
          _containsSuperCall(node.alternate);
    }
    if (node is ArrayExpression) {
      for (final elem in node.elements) {
        if (_containsSuperCall(elem)) return true;
      }
    }
    if (node is ObjectExpression) {
      for (final prop in node.properties) {
        if (_containsSuperCall(prop.value)) return true;
      }
    }
    if (node is AwaitExpression) {
      return _containsSuperCall(node.argument);
    }
    return false;
  }

  /// Check if an expression or statement contains super.property access
  bool _containsSuperProperty(dynamic node) {
    if (node == null) return false;

    if (node is MemberExpression) {
      if (node.object is SuperExpression) {
        return true;
      }
      return _containsSuperProperty(node.object);
    }
    if (node is CallExpression) {
      // super() is handled separately
      if (node.callee is SuperExpression) return false;
      if (_containsSuperProperty(node.callee)) return true;
      for (final arg in node.arguments) {
        if (_containsSuperProperty(arg)) return true;
      }
    }
    if (node is BinaryExpression) {
      return _containsSuperProperty(node.left) ||
          _containsSuperProperty(node.right);
    }
    if (node is UnaryExpression) {
      return _containsSuperProperty(node.operand);
    }
    if (node is AssignmentExpression) {
      return _containsSuperProperty(node.right);
    }
    if (node is ConditionalExpression) {
      return _containsSuperProperty(node.test) ||
          _containsSuperProperty(node.consequent) ||
          _containsSuperProperty(node.alternate);
    }
    if (node is BlockStatement) {
      for (final stmt in node.body) {
        if (_containsSuperProperty(stmt)) return true;
      }
    }
    if (node is ExpressionStatement) {
      return _containsSuperProperty(node.expression);
    }
    if (node is ReturnStatement) {
      return _containsSuperProperty(node.argument);
    }
    if (node is IfStatement) {
      return _containsSuperProperty(node.test) ||
          _containsSuperProperty(node.consequent) ||
          _containsSuperProperty(node.alternate);
    }
    if (node is ArrayExpression) {
      for (final elem in node.elements) {
        if (_containsSuperProperty(elem)) return true;
      }
    }
    if (node is ObjectExpression) {
      for (final prop in node.properties) {
        if (_containsSuperProperty(prop.value)) return true;
      }
    }
    if (node is AwaitExpression) {
      return _containsSuperProperty(node.argument);
    }
    return false;
  }

  /// Check if a token is 'await' with Unicode escape (which is an error in async context)
  void _checkAwaitAsIdentifierInAsyncContext(Token token) {
    // In async context, 'await' (even with escapes) cannot be used as identifier
    if (_inAsyncContext && token.lexeme == 'await' && token.hasUnicodeEscape) {
      throw LexerError(
        'SyntaxError: Unexpected reserved word',
        token.line,
        token.column,
      );
    }
    // Also check for regular 'await' as identifier in async context
    if (_inAsyncContext && token.lexeme == 'await') {
      if (token.type == TokenType.identifier ||
          token.type == TokenType.keywordAwait) {
        throw LexerError(
          'SyntaxError: Unexpected reserved word',
          token.line,
          token.column,
        );
      }
    }
  }

  // Track strict mode
  bool _strictMode = false;

  /// Check if we're currently in strict mode
  bool _isInStrictMode() {
    return _strictMode;
  }

  /// Parse a string of JavaScript code with optional initial strict mode
  static Program parseString(String source, {bool initialStrictMode = false}) {
    final lexer = JSLexer(source);
    final tokens = lexer.tokenize();
    final parser = JSParser(tokens, initialStrictMode: initialStrictMode);
    return parser.parse();
  }

  /// Parse a simple JavaScript expression
  static Expression parseExpression(String source) {
    final lexer = JSLexer(source);
    final tokens = lexer.tokenize();
    final parser = JSParser(tokens, initialStrictMode: false);
    return parser._expression();
  }

  /// Parse tokens and return the AST
  Program parse() {
    final statements = <Statement>[];

    // Initialize strict mode from context (e.g., from eval caller)
    _strictMode = _initialStrictMode;

    // Check for "use strict" directive at the start of the program
    if (!_isAtEnd()) {
      // Peek at the first statement to check for "use strict"
      final firstTokenIndex = _current;
      if (_check(TokenType.string) &&
          (_peek().lexeme == "'use strict'" ||
              _peek().lexeme == '"use strict"')) {
        _strictMode = true;
      }
      _current = firstTokenIndex; // Reset to start
    }

    while (!_isAtEnd()) {
      try {
        final stmt = _statement();
        statements.add(stmt);

        // After parsing the first statement, check if it was "use strict"
        if (statements.length == 1) {
          if (stmt is ExpressionStatement &&
              stmt.expression is LiteralExpression) {
            final lit = stmt.expression as LiteralExpression;
            if (lit.value == 'use strict') {
              _strictMode = true;
            }
          }
        }
      } catch (e) {
        if (e is ParseError) {
          // In error recovery mode, we could try to continue
          rethrow;
        }
        rethrow;
      }
    }

    return Program(
      body: statements,
      line: tokens.isNotEmpty ? tokens.first.line : 1,
      column: tokens.isNotEmpty ? tokens.first.column : 1,
    );
  }

  /// Helper to parse a statement body within a loop context
  Statement _loopBody() {
    _loopDepth++;
    try {
      return _statement(
        allowDeclaration: false,
        allowFunctionDeclaration: false,
      );
    } finally {
      _loopDepth--;
    }
  }

  // ===== STATEMENTS =====

  /// Parse a statement
  Statement _statement({
    bool allowDeclaration = true,
    bool allowFunctionDeclaration = true,
  }) {
    // Handle empty statement (standalone semicolon)
    if (_match([TokenType.semicolon])) {
      return EmptyStatement(line: _previous().line, column: _previous().column);
    }

    // Check if there's a label (identifier or contextual keyword followed by ':')
    // Contextual keywords allowed as labels:
    // - await: only when NOT in async context ([~Await])
    // - yield: only when NOT in generator context ([~Yield])
    // - let, const, async: allowed as labels in non-strict mode
    if ((_check(TokenType.identifier) ||
            (_check(TokenType.keywordAwait) && !_inAsyncContext) ||
            (_check(TokenType.keywordYield) && !_inGeneratorContext) ||
            _check(TokenType.keywordLet) ||
            _check(TokenType.keywordConst) ||
            _check(TokenType.keywordAsync)) &&
        _peekNext()?.type == TokenType.colon) {
      final labelToken = _advance();

      // Check for escaped await/yield used as label in async/generator context
      _checkAwaitAsIdentifierInAsyncContext(labelToken);

      _consume(TokenType.colon, "Expected ':' after label");

      // Peek ahead to determine if this will be a loop/switch label
      final nextTokenType = _peek().type;
      final isLoopLabel =
          nextTokenType == TokenType.keywordFor ||
          nextTokenType == TokenType.keywordWhile ||
          nextTokenType == TokenType.keywordDo;
      final isSwitchLabel = nextTokenType == TokenType.keywordSwitch;

      // Register label BEFORE parsing body so continue/break statements can find it
      _labelStack[labelToken.lexeme] = _LabelInfo(
        isLoop: isLoopLabel,
        isSwitch: isSwitchLabel,
        functionDepth: _functionDepth,
      );

      final body = _statement(
        allowDeclaration: false,
        allowFunctionDeclaration: allowDeclaration && !_isInStrictMode(),
      );

      return LabeledStatement(
        label: labelToken.lexeme,
        body: body,
        line: labelToken.line,
        column: labelToken.column,
      );
    }

    // Special case for 'do' statement (in case lexer doesn't recognize it as keyword)
    if (_check(TokenType.identifier) && _peek().lexeme == 'do') {
      _advance();
      return _doWhileStatement();
    }

    // Declarations
    // Special handling for 'let' which is contextual in non-strict mode
    if (_check(TokenType.keywordLet) && allowDeclaration) {
      // 'let' is a declaration if followed by identifier, [, or {
      // Otherwise, it's an identifier in an expression statement
      final nextToken = _peekNext();
      if (nextToken != null &&
          (nextToken.type == TokenType.identifier ||
              nextToken.type == TokenType.leftBracket ||
              nextToken.type == TokenType.leftBrace ||
              _isKeywordThatCanBeIdentifier(nextToken.type))) {
        _advance(); // consume 'let'
        return _variableDeclaration();
      }
      // Otherwise, fall through to expression statement
    } else if (_match([TokenType.keywordVar])) {
      return _variableDeclaration();
    } else if (_match([TokenType.keywordConst])) {
      if (!allowDeclaration) {
        throw ParseError(
          'Lexical declaration cannot appear in a single-statement context',
          _previous(),
        );
      }
      return _variableDeclaration();
    }

    if (_match([TokenType.keywordAsync])) {
      final asyncToken = _previous();
      // Check if it's followed by function (async function declaration)
      if (_check(TokenType.keywordFunction)) {
        if (!allowDeclaration) {
          throw ParseError(
            'Async function declaration cannot appear in a single-statement context',
            asyncToken,
          );
        }
        // Validate that 'async' doesn't contain Unicode escapes
        if (asyncToken.hasUnicodeEscape) {
          throw ParseError(
            'Contextual keyword "async" must not contain Unicode escape sequences',
            asyncToken,
          );
        }
        return _asyncFunctionDeclaration();
      } else {
        // async followed by something else (expressions, arrow functions)
        // are handled as expression statements
        // The async token is put back to be handled by _expressionStatement
        _current--;
        return _expressionStatement();
      }
    }

    if (_match([TokenType.keywordFunction])) {
      final functionToken = _previous();
      // Check if it's a generator (function*)
      if (_check(TokenType.multiply)) {
        if (!allowDeclaration) {
          throw ParseError(
            'Generator declaration cannot appear in a single-statement context',
            functionToken,
          );
        }
      } else if (!allowDeclaration && !allowFunctionDeclaration) {
        throw ParseError(
          'Function declaration cannot appear in a single-statement context',
          functionToken,
        );
      }
      return _functionDeclaration();
    }

    if (_match([TokenType.keywordClass])) {
      if (!allowDeclaration) {
        throw ParseError(
          'Class declaration cannot appear in a single-statement context',
          _previous(),
        );
      }
      return _classDeclaration();
    }

    if (_check(TokenType.keywordImport)) {
      // Lookahead to check if it's import.meta or import(...)
      // vs an import declaration
      final nextToken = _peekNext();
      if (nextToken?.type == TokenType.dot) {
        // Could be import.meta, which is an expression
        // Let it be parsed as expression statement
        return _expressionStatement();
      } else if (nextToken?.type == TokenType.leftParen) {
        // dynamic import is an expression
        return _expressionStatement();
      } else if (nextToken?.type == TokenType.leftBrace ||
          nextToken?.type == TokenType.multiply) {
        if (!allowDeclaration) {
          throw ParseError(
            'Import declaration cannot appear in a single-statement context',
            _peek(),
          );
        }
        _advance(); // consume 'import'
        return _importDeclaration();
      }
    }

    if (_match([TokenType.keywordExport])) {
      if (!allowDeclaration) {
        throw ParseError(
          'Export declaration cannot appear in a single-statement context',
          _previous(),
        );
      }
      return _exportDeclaration();
    }

    // Control statements
    if (_match([TokenType.keywordIf])) return _ifStatement();
    if (_match([TokenType.keywordWhile])) return _whileStatement();
    if (_check(TokenType.keywordDo) ||
        (_check(TokenType.identifier) && _peek().lexeme == 'do')) {
      _advance();
      return _doWhileStatement();
    }
    if (_match([TokenType.keywordFor])) return _forStatement();
    if (_match([TokenType.keywordReturn])) return _returnStatement();
    if (_match([TokenType.keywordBreak])) return _breakStatement();
    if (_match([TokenType.keywordContinue])) return _continueStatement();
    if (_match([TokenType.keywordTry])) return _tryStatement();
    if (_match([TokenType.keywordThrow])) return _throwStatement();
    if (_match([TokenType.keywordSwitch])) return _switchStatement();
    if (_match([TokenType.keywordWith])) return _withStatement();

    // Bloc vs destructuring assignment vs object literal
    if (_check(TokenType.leftBrace)) {
      // Lookahead to distinguish:
      // - {} = expr -> destructuring assignment (try to parse as expression first)
      // - {...} alone -> block statement
      // - {...} in expression context -> object literal

      // Peek ahead to see if this looks like a destructuring assignment
      // by checking if we have a pattern followed by '='
      final savedCurrent = _current;
      bool isDestructuring = false;

      try {
        _advance(); // consume '{'
        // Simple heuristic: if we see }, ;, or another token that indicates
        // this is a block or destructuring, decide accordingly

        // Empty braces {} is always a block statement
        if (_check(TokenType.rightBrace)) {
          isDestructuring = false;
        } else if (_check(TokenType.semicolon) ||
            _check(TokenType.keywordVar) ||
            _check(TokenType.keywordLet) ||
            _check(TokenType.keywordConst) ||
            _check(TokenType.keywordFunction) ||
            _check(TokenType.keywordIf) ||
            _check(TokenType.keywordFor) ||
            _check(TokenType.keywordWhile) ||
            _check(TokenType.keywordDo) ||
            _check(TokenType.keywordReturn) ||
            _check(TokenType.keywordBreak) ||
            _check(TokenType.keywordContinue) ||
            _check(TokenType.keywordThrow) ||
            _check(TokenType.keywordTry)) {
          isDestructuring = false;
        } else {
          // Look for pattern that ends with } followed by =
          // This is a heuristic - try to scan ahead
          int depth = 1;
          while (depth > 0 && !_isAtEnd()) {
            if (_check(TokenType.leftBrace)) {
              depth++;
            } else if (_check(TokenType.rightBrace)) {
              depth--;
            }
            if (depth > 0) _advance();
          }

          if (depth == 0) {
            _advance(); // consume the }
            // Check if next is =
            if (_check(TokenType.assign)) {
              isDestructuring = true;
            }
          }
        }
      } catch (e) {
        isDestructuring = false;
      }

      // Restore position
      _current = savedCurrent;

      if (isDestructuring) {
        return _expressionStatement();
      } else {
        return _blockStatement();
      }
    }

    // Instruction d'expression
    return _expressionStatement();
  }

  /// Parse a variable declaration
  VariableDeclaration _variableDeclaration() {
    final previous = _previous();
    final kind = previous.lexeme; // var, let, const

    final declarations = <VariableDeclarator>[];

    do {
      // Try to parse a destructuring pattern or simple identifier
      Pattern id;
      if (_match([TokenType.leftBracket])) {
        // It's an array destructuring pattern
        final expr = _parseArrayExpression();
        id = _expressionToPattern(expr);
      } else if (_match([TokenType.leftBrace])) {
        // It's an object destructuring pattern
        final expr = _parseObjectExpression();
        id = _expressionToPattern(expr);
      } else {
        // It's a simple identifier
        // Allow contextual keywords as variable names in declarations
        Token name;
        if (_check(TokenType.identifier)) {
          name = _advance();
          // Check for escaped await/yield in async/generator context
          _checkAwaitAsIdentifierInAsyncContext(name);
        } else if (_check(TokenType.keywordAwait)) {
          // 'await' cannot be used as binding identifier in async context
          name = _advance();
          _checkAwaitAsIdentifierInAsyncContext(name);
        } else if (_check(TokenType.keywordYield)) {
          // 'yield' cannot be used as binding identifier in generator context
          name = _advance();
          if (_inGeneratorContext) {
            throw LexerError(
              'SyntaxError: Unexpected reserved word',
              name.line,
              name.column,
            );
          }
        } else if (_check(TokenType.keywordUndefined)) {
          // 'undefined' is allowed as a variable name in non-strict mode (ES5+)
          name = _advance();
        } else if (_checkContextualKeyword()) {
          // Accept other contextual keywords (let, async, static, get, set, etc.)
          name = _advance();
        } else if (_check(TokenType.keywordAs)) {
          // 'as' is allowed as a variable name (only reserved in import context)
          name = _advance();
        } else {
          throw ParseError('Expected variable name', _peek());
        }

        id = IdentifierPattern(
          name: name.lexeme,
          line: name.line,
          column: name.column,
        );
      }

      Expression? init;
      if (_match([TokenType.assign])) {
        init = _assignmentExpression();
      }

      declarations.add(VariableDeclarator(id: id, init: init));
    } while (_match([TokenType.comma]));

    _consumeSemicolonOrASI('Expected \';\' after variable declaration');

    return VariableDeclaration(
      kind: kind,
      declarations: declarations,
      line: previous.line,
      column: previous.column,
    );
  }

  /// Parse an if statement
  IfStatement _ifStatement() {
    final previous = _previous();

    _consume(TokenType.leftParen, 'Expected \'(\' after \'if\'');
    final test = _expression();
    _consume(TokenType.rightParen, 'Expected \')\' after if condition');

    final consequent = _statement(
      allowDeclaration: false,
      allowFunctionDeclaration: !_isInStrictMode(),
    );
    Statement? alternate;

    if (_match([TokenType.keywordElse])) {
      alternate = _statement(
        allowDeclaration: false,
        allowFunctionDeclaration: !_isInStrictMode(),
      );
    }

    return IfStatement(
      test: test,
      consequent: consequent,
      alternate: alternate,
      line: previous.line,
      column: previous.column,
    );
  }

  /// Parse a while statement
  WhileStatement _whileStatement() {
    final previous = _previous();

    _consume(TokenType.leftParen, 'Expected \'(\' after \'while\'');
    final test = _expression();
    _consume(TokenType.rightParen, 'Expected \')\' after while condition');

    final body = _loopBody();

    return WhileStatement(
      test: test,
      body: body,
      line: previous.line,
      column: previous.column,
    );
  }

  /// Parse a do-while statement
  DoWhileStatement _doWhileStatement() {
    final previous = _previous();

    final body = _loopBody();

    _consume(TokenType.keywordWhile, 'Expected \'while\' after do body');
    _consume(TokenType.leftParen, 'Expected \'(\' after \'while\'');
    final test = _expression();
    _consume(TokenType.rightParen, 'Expected \')\' after while condition');
    _consumeDoWhileSemicolon('Expected \';\' after do-while statement');

    return DoWhileStatement(
      body: body,
      test: test,
      line: previous.line,
      column: previous.column,
    );
  }

  /// Parse a for statement (classic, for-in, or for-of)
  Statement _forStatement() {
    final previous = _previous();

    // ES2018: Check if it's for await...of (before consuming '(')
    bool isAwait = false;
    if (_match([TokenType.keywordAwait])) {
      isAwait = true;
    }

    _consume(
      TokenType.leftParen,
      'Expected \'(\' after \'for${isAwait ? ' await' : ''}\'',
    );

    // We must analyze the start to determine the loop type
    // First analysis : variable or expression ?
    ASTNode? leftSide;

    // Special case: 'let', 'yield', 'await' can be identifiers in certain contexts
    // In for loops, they're only declarations if followed by [ or {
    bool shouldParseAsDeclaration = false;
    if (_match([TokenType.keywordVar, TokenType.keywordConst])) {
      shouldParseAsDeclaration = true;
    } else if (_check(TokenType.keywordLet)) {
      // 'let' in for loop is a declaration if:
      // 1. Followed by [{ (destructuring), OR
      // 2. Followed by an identifier or keyword that could be a variable name (for-in/for-of)
      final nextToken = _peekNext();
      if (nextToken != null &&
          (nextToken.type == TokenType.leftBracket ||
              nextToken.type == TokenType.leftBrace ||
              nextToken.type == TokenType.identifier ||
              _isKeywordThatCanBeIdentifier(nextToken.type))) {
        _advance(); // consume 'let'
        shouldParseAsDeclaration = true;
      }
    } else if (_check(TokenType.keywordYield)) {
      // 'yield' in for loop can be a declaration if:
      // 1. Followed by [ or { (destructuring), OR
      // 2. Followed by identifier (for-in/for-of in non-generator context)
      final nextToken = _peekNext();
      if (nextToken != null &&
          (nextToken.type == TokenType.leftBracket ||
              nextToken.type == TokenType.leftBrace ||
              (nextToken.type == TokenType.identifier &&
                  !_inGeneratorContext))) {
        _advance(); // consume 'yield'
        shouldParseAsDeclaration = true;
      }
    } else if (_check(TokenType.keywordAwait)) {
      // 'await' in for loop can be a declaration if:
      // 1. Followed by [ or { (destructuring), OR
      // 2. Followed by identifier (for-in/for-of in non-async context)
      final nextToken = _peekNext();
      if (nextToken != null &&
          (nextToken.type == TokenType.leftBracket ||
              nextToken.type == TokenType.leftBrace ||
              (nextToken.type == TokenType.identifier && !_inAsyncContext))) {
        _advance(); // consume 'await'
        shouldParseAsDeclaration = true;
      }
    }

    if (shouldParseAsDeclaration) {
      // Variable declaration
      final kind = _previous().lexeme;
      final kindToken = _previous();

      // Parse the first pattern (can be a simple identifier or destructuring pattern)
      Pattern id;
      if (_match([TokenType.leftBracket])) {
        // It's an array destructuring pattern: for (const [a, b] of arr)
        final expr = _parseArrayExpression();
        id = _expressionToPattern(expr);
      } else if (_match([TokenType.leftBrace])) {
        // It's an object destructuring pattern: for (const {x, y} of arr)
        final expr = _parseObjectExpression();
        id = _expressionToPattern(expr);
      } else {
        // It's a simple identifier: for (const x of arr)
        // Can also be a keyword that serves as identifier (let, yield, await, undefined, as)
        Token name;
        if (_check(TokenType.identifier)) {
          name = _advance();
        } else if (_check(TokenType.keywordLet)) {
          name = _advance();
        } else if (_check(TokenType.keywordYield)) {
          name = _advance();
        } else if (_check(TokenType.keywordAwait)) {
          name = _advance();
        } else if (_check(TokenType.keywordUndefined)) {
          name = _advance();
        } else if (_check(TokenType.keywordAs)) {
          name = _advance();
        } else {
          throw ParseError('Expected variable name', _peek());
        }

        id = IdentifierPattern(
          name: name.lexeme,
          line: name.line,
          column: name.column,
        );
      }

      // Check if it's for-in or for-of (before parsing additional declarations)
      if (_check(TokenType.keywordIn)) {
        _advance(); // consume 'in'
        final right = _expression();
        _consume(
          TokenType.rightParen,
          'Expected \')\' after for-in expression',
        );
        final body = _loopBody();

        leftSide = VariableDeclaration(
          kind: kind,
          declarations: [VariableDeclarator(id: id, init: null)],
          line: kindToken.line,
          column: kindToken.column,
        );

        return ForInStatement(
          left: leftSide,
          right: right,
          body: body,
          line: previous.line,
          column: previous.column,
        );
      } else if (_check(TokenType.keywordOf)) {
        _advance(); // consume 'of'
        final right = _expression();
        _consume(
          TokenType.rightParen,
          'Expected \')\' after for-of expression',
        );
        final body = _loopBody();

        leftSide = VariableDeclaration(
          kind: kind,
          declarations: [VariableDeclarator(id: id, init: null)],
          line: kindToken.line,
          column: kindToken.column,
        );

        return ForOfStatement(
          left: leftSide,
          right: right,
          body: body,
          await: isAwait,
          line: previous.line,
          column: previous.column,
        );
      }

      // If it's neither in nor of, c'est un for classique avec initialisation
      // We can have multiple declarations separated by commas: for (var s, i = 1, n = 10; ...)
      final declarations = <VariableDeclarator>[];

      // First declaration
      Expression? initExpr;
      if (_match([TokenType.assign])) {
        // Use assignmentExpression instead of _expression to avoid parsing commas
        // as sequence operators (we want commas to separate declarations)
        initExpr = _assignmentExpression();
      }
      declarations.add(VariableDeclarator(id: id, init: initExpr));

      // Additional declarations (separated by commas)
      while (_match([TokenType.comma])) {
        // Support contextual keywords (let, undefined, as, etc.) as variable names
        Token varName;
        if (_check(TokenType.identifier)) {
          varName = _advance();
        } else if (_check(TokenType.keywordLet) ||
            _check(TokenType.keywordYield) ||
            _check(TokenType.keywordAwait) ||
            _check(TokenType.keywordUndefined) ||
            _check(TokenType.keywordAs) ||
            _checkContextualKeyword()) {
          varName = _advance();
        } else {
          throw ParseError('Expected variable name', _peek());
        }

        final varId = IdentifierPattern(
          name: varName.lexeme,
          line: varName.line,
          column: varName.column,
        );

        Expression? varInit;
        if (_match([TokenType.assign])) {
          // Use assignmentExpression au lieu de _expression
          varInit = _assignmentExpression();
        }

        declarations.add(VariableDeclarator(id: varId, init: varInit));
      }

      leftSide = VariableDeclaration(
        kind: kind,
        declarations: declarations,
        line: kindToken.line,
        column: kindToken.column,
      );

      _consume(
        TokenType.semicolon,
        'Expected \';\' after for loop initializer',
      );
    } else if (!_check(TokenType.semicolon)) {
      // First check if it's a simple identifier followed by 'in' or 'of'
      // before parsing a complete expression (which could include assignments)
      if ((_check(TokenType.identifier) ||
              _isKeywordThatCanBeIdentifier(_peek().type)) &&
          (_peekNext()?.type == TokenType.keywordIn ||
              _peekNext()?.type == TokenType.keywordOf)) {
        // It's a simple 'identifier in/of expression', pas une expression complexe
        final nameToken = _advance();
        final left = IdentifierExpression(
          name: nameToken.lexeme,
          line: nameToken.line,
          column: nameToken.column,
        );

        if (_match([TokenType.keywordIn])) {
          // for-in avec identifiant simple (pas de var/const/let)
          final right = _expression();
          _consume(
            TokenType.rightParen,
            'Expected \')\' after for-in expression',
          );
          final body = _loopBody();

          return ForInStatement(
            left: left,
            right: right,
            body: body,
            line: previous.line,
            column: previous.column,
          );
        } else if (_match([TokenType.keywordOf])) {
          // for-of avec identifiant simple (pas de var/const/let)
          final right = _expression();
          _consume(
            TokenType.rightParen,
            'Expected \')\' after for-of expression',
          );
          final body = _loopBody();

          return ForOfStatement(
            left: left,
            right: right,
            body: body,
            await: isAwait,
            line: previous.line,
            column: previous.column,
          );
        }
      }

      // Parse a complete expression (if it's not a simple identifier in/of)
      final expr = _expression();

      // Check if it's for-in or for-of
      if (_check(TokenType.keywordIn)) {
        _advance(); // consume 'in'
        final right = _expression();
        _consume(
          TokenType.rightParen,
          'Expected \')\' after for-in expression',
        );
        final body = _loopBody();

        return ForInStatement(
          left: expr,
          right: right,
          body: body,
          line: previous.line,
          column: previous.column,
        );
      } else if (_check(TokenType.keywordOf)) {
        _advance(); // consume 'of'
        final right = _expression();
        _consume(
          TokenType.rightParen,
          'Expected \')\' after for-of expression',
        );
        final body = _loopBody();

        return ForOfStatement(
          left: expr,
          right: right,
          body: body,
          await: isAwait,
          line: previous.line,
          column: previous.column,
        );
      } else if (expr is BinaryExpression && expr.operator == 'in') {
        // Special case: l'expression est 'left in right', c'est for-in
        _consume(
          TokenType.rightParen,
          'Expected \')\' after for-in expression',
        );
        final body = _loopBody();

        return ForInStatement(
          left: expr.left,
          right: expr.right,
          body: body,
          line: previous.line,
          column: previous.column,
        );
      } else if (expr is SequenceExpression &&
          expr.expressions.isNotEmpty &&
          expr.expressions.first is BinaryExpression &&
          (expr.expressions.first as BinaryExpression).operator == 'in') {
        // Sequence with for-in: (x in null, obj) is for (x in (null, obj))
        final binExpr = expr.expressions.first as BinaryExpression;
        // Reconstruct: left = binExpr.left, right = (binExpr.right, ...rest)
        final rightExprs = [binExpr.right, ...expr.expressions.skip(1)];
        final right = rightExprs.length == 1
            ? rightExprs[0]
            : SequenceExpression(
                expressions: rightExprs,
                line: binExpr.right.line,
                column: binExpr.right.column,
              );

        _consume(
          TokenType.rightParen,
          'Expected \')\' after for-in expression',
        );
        final body = _loopBody();

        return ForInStatement(
          left: binExpr.left,
          right: right,
          body: body,
          line: previous.line,
          column: previous.column,
        );
      } else if (expr is BinaryExpression && expr.operator == 'of') {
        // Special case: l'expression est 'left of right', c'est for-of
        _consume(
          TokenType.rightParen,
          'Expected \')\' after for-of expression',
        );
        final body = _loopBody();

        return ForOfStatement(
          left: expr.left,
          right: expr.right,
          body: body,
          await: isAwait,
          line: previous.line,
          column: previous.column,
        );
      } else if (expr is SequenceExpression &&
          expr.expressions.isNotEmpty &&
          expr.expressions.first is BinaryExpression &&
          (expr.expressions.first as BinaryExpression).operator == 'of') {
        // Sequence with for-of: (x of arr, obj) is for (x of (arr, obj))
        final binExpr = expr.expressions.first as BinaryExpression;
        final rightExprs = [binExpr.right, ...expr.expressions.skip(1)];
        final right = rightExprs.length == 1
            ? rightExprs[0]
            : SequenceExpression(
                expressions: rightExprs,
                line: binExpr.right.line,
                column: binExpr.right.column,
              );

        _consume(
          TokenType.rightParen,
          'Expected \')\' after for-of expression',
        );
        final body = _loopBody();

        return ForOfStatement(
          left: binExpr.left,
          right: right,
          body: body,
          await: isAwait,
          line: previous.line,
          column: previous.column,
        );
      } else {
        // C'est un for classique
        leftSide = ExpressionStatement(
          expression: expr,
          line: expr.line,
          column: expr.column,
        );
        _consume(
          TokenType.semicolon,
          'Expected \';\' after for loop initializer',
        );
      }
    } else {
      // No initialization
      leftSide = null;
      _advance(); // consume ';'
    }

    // Classic for : continuer avec test et update
    Expression? test;
    if (!_check(TokenType.semicolon)) {
      test = _expression();
    }
    _consume(TokenType.semicolon, 'Expected \';\' after for loop condition');

    // Update
    Expression? update;
    if (!_check(TokenType.rightParen)) {
      update = _expression();
    }
    _consume(TokenType.rightParen, 'Expected \')\' after for clauses');

    final body = _loopBody();

    return ForStatement(
      init: leftSide,
      test: test,
      update: update,
      body: body,
      line: previous.line,
      column: previous.column,
    );
  }

  /// Parse a return statement
  ReturnStatement _returnStatement() {
    final previous = _previous();

    // Check if return is inside a function
    if (_functionDepth == 0) {
      throw ParseError('Return statement outside function', previous);
    }

    Expression? argument;
    if (!_check(TokenType.semicolon) && !_isAtEnd() && !_canInsertSemicolon()) {
      argument = _expression();
    }

    _consumeSemicolonOrASI('Expected \';\' after return value');

    return ReturnStatement(
      argument: argument,
      line: previous.line,
      column: previous.column,
    );
  }

  /// Parse a break statement
  BreakStatement _breakStatement() {
    final previous = _previous();
    String? label;

    // Check if there's a label on the SAME line
    // If the identifier is on a new line, ASI applies before
    if (_check(TokenType.identifier) && _peek().line == previous.line) {
      label = _advance().lexeme;
    }

    // Validation: break must be in a loop or switch statement (unlabeled)
    // or must have a valid label target (labeled)
    if (label == null) {
      // Unlabeled break: must be in loop or switch
      if (_loopDepth == 0 && _switchDepth == 0) {
        throw ParseError('Illegal break statement', previous);
      }
    } else {
      // Labeled break: label must exist
      if (!_labelStack.containsKey(label)) {
        throw ParseError('Label "$label" is not defined', previous);
      }
      final labelInfo = _labelStack[label]!;

      // Break can only target IterationStatement or SwitchStatement
      // ES5 strict requirement (test262 validates this)
      if (!labelInfo.isLoopOrSwitch) {
        throw ParseError(
          'Illegal break statement: label must target a loop or switch statement',
          previous,
        );
      }

      // Break cannot escape a function boundary
      if (labelInfo.functionDepth < _functionDepth) {
        throw ParseError(
          'Illegal break statement: cannot break to a label outside the current function',
          previous,
        );
      }
    }

    // Support for ASI (Automatic Semicolon Insertion)
    _consumeSemicolonOrASI('Expected \';\' after \'break\'');

    return BreakStatement(
      label: label,
      line: previous.line,
      column: previous.column,
    );
  }

  /// Parse a continue statement
  ContinueStatement _continueStatement() {
    final previous = _previous();
    String? label;

    // Check if there's a label on the SAME line
    // If the identifier is on a new line, ASI applies before
    if (_check(TokenType.identifier) && _peek().line == previous.line) {
      label = _advance().lexeme;
    }

    // Validation: continue must be in a loop
    if (label == null) {
      // Unlabeled continue: must be in loop
      if (_loopDepth == 0) {
        throw ParseError('Illegal continue statement', previous);
      }
    } else {
      // Labeled continue: must target a loop label (NOT switch)
      if (!_labelStack.containsKey(label)) {
        throw ParseError('Label "$label" is not defined', previous);
      }
      final labelInfo = _labelStack[label]!;
      // ES5 12.7: continue requires label to target IterationStatement
      if (!labelInfo.isLoop) {
        throw ParseError(
          'Continue target must be an iteration statement',
          previous,
        );
      }
      // Continue cannot escape a function boundary
      if (labelInfo.functionDepth < _functionDepth) {
        throw ParseError(
          'Illegal continue statement: cannot continue to a label outside the current function',
          previous,
        );
      }
    }

    // Support for ASI (Automatic Semicolon Insertion)
    _consumeSemicolonOrASI('Expected \';\' after \'continue\'');

    return ContinueStatement(
      label: label,
      line: previous.line,
      column: previous.column,
    );
  }

  /// Parse a throw statement
  ThrowStatement _throwStatement() {
    final throwToken = _previous();

    // In JavaScript, there cannot be y avoir de nouvelle ligne entre throw et l'expression
    // For simplicity, on assume qu'il n'y en a pas

    final argument = _expression();
    _consumeSemicolonOrASI('Expected \';\' after throw statement');

    return ThrowStatement(
      argument: argument,
      line: throwToken.line,
      column: throwToken.column,
    );
  }

  /// Parse a try/catch/finally statement
  TryStatement _tryStatement() {
    final tryToken = _previous();

    // Parse the try block
    final block = _blockStatement();

    // Parse optional catch clause
    CatchClause? handler;
    if (_match([TokenType.keywordCatch])) {
      final catchToken = _previous();

      // Parse optional parameter (e) dans catch(e)
      IdentifierExpression? param;
      Pattern? paramPattern;

      if (_match([TokenType.leftParen])) {
        // When parentheses are present, they must contain a parameter
        // Optional-catch-binding allows catch {} but NOT catch ()
        if (_check(TokenType.rightParen)) {
          throw ParseError(
            'SyntaxError: catch must have a parameter or no parentheses',
            _peek(),
          );
        }

        // Parse the catch parameter (can be simple identifier or destructuring pattern)
        if (_check(TokenType.leftBracket)) {
          // Array destructuring pattern
          _advance(); // consume [
          final expr = _parseArrayExpression();
          paramPattern = _expressionToPattern(expr);
        } else if (_check(TokenType.leftBrace)) {
          // Object destructuring pattern
          _advance(); // consume {
          final expr = _parseObjectExpression();
          paramPattern = _expressionToPattern(expr);
        } else if (_check(TokenType.identifier) ||
            _check(TokenType.keywordAwait) ||
            _check(TokenType.keywordYield) ||
            _check(TokenType.keywordAsync)) {
          // Simple identifier parameter or contextual keyword
          final paramToken = _advance();
          param = IdentifierExpression(
            name: paramToken.lexeme,
            line: paramToken.line,
            column: paramToken.column,
          );
        } else {
          throw ParseError('Expected catch parameter', _peek());
        }
        _consume(TokenType.rightParen, 'Expected \')\' after catch parameter');
      }

      // Parse the catch body
      final catchBody = _blockStatement();

      // Validate early errors
      // 1. Check for duplicate names in destructuring pattern
      if (paramPattern != null) {
        final boundNames = _getBoundNamesFromPattern(paramPattern);
        final seen = <String>{};
        for (final name in boundNames) {
          if (seen.contains(name)) {
            throw ParseError(
              'Identifier \'$name\' has already been declared',
              _peek(),
            );
          }
          seen.add(name);
        }

        // Check for eval/arguments in strict mode
        if (_isInStrictMode()) {
          for (final name in boundNames) {
            if (name == 'eval' || name == 'arguments') {
              throw ParseError(
                'The identifier \'$name\' cannot be used as a catch parameter in strict mode',
                _peek(),
              );
            }
          }
        }
      }

      // Check simple identifier parameter for eval/arguments in strict mode
      if (param != null && _isInStrictMode()) {
        if (param.name == 'eval' || param.name == 'arguments') {
          throw ParseError(
            'The identifier \'${param.name}\' cannot be used as a catch parameter in strict mode',
            _peek(),
          );
        }
      }

      // 2. Check that catch parameter is not redeclared in the catch body
      // ES6: It is a Syntax Error if any element of the BoundNames of CatchParameter
      // also occurs in the LexicallyDeclaredNames of Block
      final catchParamNames = <String>{};
      if (param != null) {
        catchParamNames.add(param.name);
      } else if (paramPattern != null) {
        catchParamNames.addAll(_getBoundNamesFromPattern(paramPattern));
      }

      if (catchParamNames.isNotEmpty) {
        final lexicallyDeclaredInBody = <String>{};

        for (final stmt in catchBody.body) {
          if (stmt is FunctionDeclaration) {
            lexicallyDeclaredInBody.add(stmt.id.name);
          } else if (stmt is AsyncFunctionDeclaration) {
            lexicallyDeclaredInBody.add(stmt.id.name);
          } else if (stmt is ClassDeclaration) {
            if (stmt.id?.name != null) {
              lexicallyDeclaredInBody.add(stmt.id!.name);
            }
          } else if (stmt is VariableDeclaration &&
              (stmt.kind == 'let' || stmt.kind == 'const')) {
            for (final decl in stmt.declarations) {
              final names = _getBoundNamesFromPattern(decl.id);
              lexicallyDeclaredInBody.addAll(names);
            }
          }
        }

        // Check for intersection
        for (final paramName in catchParamNames) {
          if (lexicallyDeclaredInBody.contains(paramName)) {
            throw ParseError(
              'Identifier \'$paramName\' has already been declared',
              _peek(),
            );
          }
        }
      }

      handler = CatchClause(
        param: param,
        paramPattern: paramPattern,
        body: catchBody,
        line: catchToken.line,
        column: catchToken.column,
      );
    }

    // Parse optional finally clause
    BlockStatement? finalizer;
    if (_match([TokenType.keywordFinally])) {
      finalizer = _blockStatement();
    }

    // At least catch or finally must be present
    if (handler == null && finalizer == null) {
      throw ParseError('Missing catch or finally after try', tryToken);
    }

    return TryStatement(
      block: block,
      handler: handler,
      finalizer: finalizer,
      line: tryToken.line,
      column: tryToken.column,
    );
  }

  /// Parse a switch statement
  SwitchStatement _switchStatement() {
    final switchToken = _previous();

    _consume(TokenType.leftParen, 'Expected \'(\' after \'switch\'');
    final discriminant = _expression();
    _consume(TokenType.rightParen, 'Expected \')\' after switch discriminant');

    _consume(TokenType.leftBrace, 'Expected \'{\' after switch discriminant');

    final cases = <SwitchCase>[];
    bool hasDefault = false;

    _switchDepth++;
    try {
      while (!_check(TokenType.rightBrace) && !_isAtEnd()) {
        if (_match([TokenType.keywordCase])) {
          final caseToken = _previous();
          final test = _expression();
          _consume(TokenType.colon, 'Expected \':\' after case expression');

          final consequent = <Statement>[];
          while (!_check(TokenType.keywordCase) &&
              !_check(TokenType.keywordDefault) &&
              !_check(TokenType.rightBrace) &&
              !_isAtEnd()) {
            consequent.add(_statement());
          }

          cases.add(
            SwitchCase(
              test: test,
              consequent: consequent,
              line: caseToken.line,
              column: caseToken.column,
            ),
          );
        } else if (_match([TokenType.keywordDefault])) {
          final defaultToken = _previous();

          // Check for duplicate default clause
          if (hasDefault) {
            throw ParseError(
              'Duplicate default clause in switch statement',
              defaultToken,
            );
          }
          hasDefault = true;

          _consume(TokenType.colon, 'Expected \':\' after default');

          final consequent = <Statement>[];
          while (!_check(TokenType.keywordCase) &&
              !_check(TokenType.keywordDefault) &&
              !_check(TokenType.rightBrace) &&
              !_isAtEnd()) {
            consequent.add(_statement());
          }

          cases.add(
            SwitchCase(
              test: null, // null indique default case
              consequent: consequent,
              line: defaultToken.line,
              column: defaultToken.column,
            ),
          );
        } else {
          throw ParseError(
            'Expected case or default in switch statement',
            _peek(),
          );
        }
      }
    } finally {
      _switchDepth--;
    }

    _consume(TokenType.rightBrace, 'Expected \'}\' after switch body');

    // Validate no duplicate lexically declared names in switch cases
    // ES6: It is a Syntax Error if the LexicallyDeclaredNames of CaseBlock
    // contains any duplicate entries
    final declaredNames = <String, int>{}; // name -> case index
    for (int caseIdx = 0; caseIdx < cases.length; caseIdx++) {
      final switchCase = cases[caseIdx];
      for (final statement in switchCase.consequent) {
        final names = <String>[];

        if (statement is FunctionDeclaration) {
          names.add(statement.id.name);
        } else if (statement is AsyncFunctionDeclaration) {
          names.add(statement.id.name);
        } else if (statement is ClassDeclaration) {
          if (statement.id?.name != null) {
            names.add(statement.id!.name);
          }
        } else if (statement is VariableDeclaration) {
          // Extract names from let/const declarations
          for (final decl in statement.declarations) {
            names.add(_extractNameFromPattern(decl.id));
          }
        }

        for (final declName in names) {
          if (declaredNames.containsKey(declName)) {
            throw ParseError(
              'Identifier \'$declName\' has already been declared',
              _peek(),
            );
          }
          declaredNames[declName] = caseIdx;
        }
      }
    }

    return SwitchStatement(
      discriminant: discriminant,
      cases: cases,
      line: switchToken.line,
      column: switchToken.column,
    );
  }

  /// Parse un statement with (interdit en strict mode)
  WithStatement _withStatement() {
    final withToken = _previous();

    // In class context (which is always strict mode), 'with' is not allowed
    if (_inClassContext) {
      throw LexerError(
        'SyntaxError: \'with\' statement is not allowed in strict mode',
        withToken.line,
        withToken.column,
      );
    }

    _consume(TokenType.leftParen, "Expected '(' after 'with'");
    final object = _expression();
    _consume(TokenType.rightParen, "Expected ')' after with object");

    final body = _loopBody();

    return WithStatement(
      object: object,
      body: body,
      line: withToken.line,
      column: withToken.column,
    );
  }

  /// Parse a block of statements
  BlockStatement _blockStatement() {
    final start = _peek();
    _consume(TokenType.leftBrace, 'Expected \'{\'');

    final statements = <Statement>[];

    while (!_check(TokenType.rightBrace) && !_isAtEnd()) {
      statements.add(_statement());
    }

    _consume(TokenType.rightBrace, 'Expected \'}\'');

    return BlockStatement(
      body: statements,
      line: start.line,
      column: start.column,
    );
  }

  /// Parse an expression statement
  ExpressionStatement _expressionStatement() {
    // ES2015/ES2017 Lookahead restrictions for ExpressionStatement:
    // [lookahead ∉ { {, function, async [no LineTerminator here] function, class, let [ }]
    // Note: {, function, class, and async function are already handled by _statement()
    // choosing other statement types. We only need to check 'let [' here specifically.
    if (_check(TokenType.keywordLet) &&
        _peekNext()?.type == TokenType.leftBracket) {
      throw ParseError(
        'Lexical declaration cannot appear in a single-statement context',
        _peek(),
      );
    }

    final expr = _expression();
    _consumeSemicolonOrASI('Expected \';\' after expression');

    return ExpressionStatement(
      expression: expr,
      line: expr.line,
      column: expr.column,
    );
  }

  // ===== EXPRESSIONS =====

  /// Parse an expression (main entry point for expressions)
  Expression _expression() {
    return _sequence();
  }

  /// Parse an expression without sequence (for arguments, object properties, etc.)
  Expression _assignmentExpression() {
    return _assignment();
  }

  /// Parse a sequence expression (a, b, c)
  Expression _sequence() {
    final expr = _assignment();

    if (_match([TokenType.comma])) {
      final expressions = <Expression>[expr];

      do {
        // ES2017: Check for trailing comma (comma followed by closing paren)
        // This must be checked BEFORE trying to parse another expression
        if (_check(TokenType.rightParen)) {
          // Trailing comma detected, stop here
          break;
        }

        // Handle rest parameter in sequences: (a, b, ...rest) or (a, b, ...[x, y])
        // This is necessary for arrow functions with rest parameters
        if (_match([TokenType.spread])) {
          final spreadStart = _previous();
          Expression argument;
          // Support identifier, array pattern, or object pattern after ...
          if (_check(TokenType.identifier)) {
            final ident = _advance();
            argument = IdentifierExpression(
              name: ident.lexeme,
              line: ident.line,
              column: ident.column,
            );
          } else if (_check(TokenType.leftBracket)) {
            // Array destructuring pattern: ...[a, b]
            _advance(); // consume '['
            argument = _parseArrayExpression();
          } else if (_check(TokenType.leftBrace)) {
            // Object destructuring pattern: ...{a, b}
            _advance(); // consume '{'
            argument = _parseObjectExpression();
          } else {
            throw ParseError(
              'Expected identifier or pattern after ... in parameter list',
              _peek(),
            );
          }
          expressions.add(
            SpreadElement(
              argument: argument,
              line: spreadStart.line,
              column: spreadStart.column,
            ),
          );
        } else {
          expressions.add(_assignment());
        }

        // Continue parsing sequence
        if (!_match([TokenType.comma])) {
          break;
        }
      } while (true);

      return SequenceExpression(
        expressions: expressions,
        line: expr.line,
        column: expr.column,
      );
    }

    return expr;
  }

  /// Parse an assignment expression
  Expression _assignment() {
    final expr = _conditional();

    if (_match([
      TokenType.assign,
      TokenType.plusAssign,
      TokenType.minusAssign,
      TokenType.multiplyAssign,
      TokenType.divideAssign,
      TokenType.moduloAssign,
      TokenType.exponentAssign,
      TokenType.andAssign,
      TokenType.orAssign,
      TokenType.nullishCoalescingAssign,
      TokenType.bitwiseAndAssign,
      TokenType.bitwiseOrAssign,
      TokenType.bitwiseXorAssign,
      TokenType.leftShiftAssign,
      TokenType.rightShiftAssign,
      TokenType.unsignedRightShiftAssign,
    ])) {
      final operator = _previous();
      final right = _assignment();

      // Check if it's a destructuring assignment
      if (operator.lexeme == '=' && _isDestructuringPattern(expr)) {
        final pattern = _expressionToPattern(expr);
        return DestructuringAssignmentExpression(
          left: pattern,
          right: right,
          line: operator.line,
          column: operator.column,
        );
      }

      return AssignmentExpression(
        left: expr,
        operator: operator.lexeme,
        right: right,
        line: operator.line,
        column: operator.column,
      );
    }

    // Check if it's an arrow function
    if (_check(TokenType.arrow)) {
      return _parseArrowFunction(expr);
    }

    return expr;
  }

  /// Verify if an expression can be a destructuring pattern
  bool _isDestructuringPattern(Expression expr) {
    return expr is ArrayExpression || expr is ObjectExpression;
  }

  /// Convertit une expression en pattern de destructuring
  Pattern _expressionToPattern(Expression expr) {
    switch (expr) {
      case IdentifierExpression identExpr:
        return IdentifierPattern(
          name: identExpr.name,
          line: identExpr.line,
          column: identExpr.column,
        );
      case AssignmentExpression assignExpr when assignExpr.operator == '=':
        // Pattern with default value: a = 10
        final leftPattern = _expressionToPattern(assignExpr.left);
        return AssignmentPattern(
          left: leftPattern,
          right: assignExpr.right,
          line: assignExpr.line,
          column: assignExpr.column,
        );
      case ArrayExpression arrayExpr:
        return _arrayExpressionToPattern(arrayExpr);
      case ObjectExpression objectExpr:
        return _objectExpressionToPattern(objectExpr);
      case MemberExpression memberExpr:
        // Member expressions are valid assignment targets in destructuring
        return ExpressionPattern(
          expression: memberExpr,
          line: memberExpr.line,
          column: memberExpr.column,
        );
      default:
        throw ParseError('Invalid destructuring pattern', _peek());
    }
  }

  /// Convert an ArrayExpression en ArrayPattern
  ArrayPattern _arrayExpressionToPattern(ArrayExpression expr) {
    final elements = <Pattern?>[];
    Pattern? restElement;
    bool hasRestElement = false;

    for (int i = 0; i < expr.elements.length; i++) {
      final element = expr.elements[i];

      if (element == null) {
        if (hasRestElement) {
          // Syntax error: elements after rest element
          throw ParseError(
            'Rest element must be last element in destructuring pattern',
            _peek(),
          );
        }
        elements.add(null); // Trou dans l'array [a, , c]
      } else if (element is AssignmentExpression && element.operator == '=') {
        if (hasRestElement) {
          throw ParseError(
            'Rest element must be last element in destructuring pattern',
            _peek(),
          );
        }
        // Default value: a = 10
        final leftPattern = _expressionToPattern(element.left);
        elements.add(
          AssignmentPattern(
            left: leftPattern,
            right: element.right,
            line: element.line,
            column: element.column,
          ),
        );
      } else if (element is IdentifierExpression) {
        if (hasRestElement) {
          throw ParseError(
            'Rest element must be last element in destructuring pattern',
            _peek(),
          );
        }
        elements.add(
          IdentifierPattern(
            name: element.name,
            line: element.line,
            column: element.column,
          ),
        );
      } else if (element is SpreadElement) {
        if (hasRestElement) {
          throw ParseError(
            'Rest element must be last element in destructuring pattern',
            _peek(),
          );
        }
        // Rest pattern: ...rest or ...obj.prop or ...obj[expr], etc.
        // Convert the argument expression to a pattern (can be identifier, member expr, etc.)
        if (element.argument is IdentifierExpression) {
          final identifier = element.argument as IdentifierExpression;
          restElement = IdentifierPattern(
            name: identifier.name,
            line: element.line,
            column: element.column,
          );
        } else if (element.argument is MemberExpression) {
          // Rest element can be a member expression like ...obj['key'] or ...obj.prop
          restElement = ExpressionPattern(
            expression: element.argument,
            line: element.line,
            column: element.column,
          );
        } else if (element.argument is ArrayExpression ||
            element.argument is ObjectExpression) {
          // Rest element can be a destructuring pattern like ...[a, b] or ...{x, y}
          restElement = _expressionToPattern(element.argument);
        } else {
          throw ParseError(
            'Invalid rest pattern in array destructuring',
            _peek(),
          );
        }
        hasRestElement = true;
      } else if (element is DestructuringAssignmentExpression) {
        if (hasRestElement) {
          throw ParseError(
            'Rest element must be last element in destructuring pattern',
            _peek(),
          );
        }
        // Handle destructuring assignment in array pattern: [[a, b] = default]
        elements.add(
          AssignmentPattern(
            left: element.left,
            right: element.right,
            line: element.line,
            column: element.column,
          ),
        );
      } else if (_isDestructuringPattern(element)) {
        if (hasRestElement) {
          throw ParseError(
            'Rest element must be last element in destructuring pattern',
            _peek(),
          );
        }
        elements.add(_expressionToPattern(element));
      } else if (element is MemberExpression) {
        if (hasRestElement) {
          throw ParseError(
            'Rest element must be last element in destructuring pattern',
            _peek(),
          );
        }
        // Member expressions are valid assignment targets: obj.prop or arr[index]
        elements.add(
          ExpressionPattern(
            expression: element,
            line: element.line,
            column: element.column,
          ),
        );
      } else {
        throw ParseError(
          'Invalid destructuring pattern element (got ${element.runtimeType})',
          _peek(),
        );
      }
    }

    return ArrayPattern(
      elements: elements,
      restElement: restElement,
      line: expr.line,
      column: expr.column,
    );
  }

  /// Convert an ObjectExpression en ObjectPattern
  ObjectPattern _objectExpressionToPattern(ObjectExpression expr) {
    final properties = <ObjectPatternProperty>[];
    Pattern? restElement;

    for (final prop in expr.properties) {
      if (prop is SpreadElement) {
        // Rest pattern: ...rest or ...obj.prop or ...obj[expr], etc.
        if (prop.argument is IdentifierExpression) {
          final identifier = prop.argument as IdentifierExpression;
          restElement = IdentifierPattern(
            name: identifier.name,
            line: prop.line,
            column: prop.column,
          );
        } else if (prop.argument is MemberExpression) {
          // Rest element can be a member expression like ...obj['key'] or ...obj.prop
          restElement = ExpressionPattern(
            expression: prop.argument,
            line: prop.line,
            column: prop.column,
          );
        } else if (prop.argument is ArrayExpression ||
            prop.argument is ObjectExpression) {
          // Rest element can be a destructuring pattern like ...[a, b] or ...{x, y}
          restElement = _expressionToPattern(prop.argument);
        } else {
          throw ParseError(
            'Invalid rest pattern in object destructuring',
            _peek(),
          );
        }
        continue;
      }

      if (prop is! ObjectProperty) {
        throw ParseError('Invalid object property in destructuring', _peek());
      }

      String key;
      Pattern value;
      bool shorthand = false;

      // Extract the key
      if (prop.key is IdentifierExpression) {
        key = (prop.key as IdentifierExpression).name;
      } else if (prop.key is LiteralExpression) {
        final literal = prop.key as LiteralExpression;
        if (literal.type == 'string' ||
            literal.type == 'number' ||
            literal.type == 'bigint') {
          key = literal.value.toString();
        } else {
          throw ParseError('Invalid property key in destructuring', _peek());
        }
      } else {
        // Computed property keys: {[expr]: pattern}
        // Use a placeholder since the key will be evaluated at runtime
        key = '[computed]';
      }

      // Extraire la valeur/pattern
      if (prop.value is IdentifierExpression) {
        final identifier = prop.value as IdentifierExpression;
        value = IdentifierPattern(
          name: identifier.name,
          line: identifier.line,
          column: identifier.column,
        );
        // Check if it's a shorthand {x} au lieu de {x: x}
        shorthand = key == identifier.name;
      } else if (prop.value is AssignmentExpression) {
        // Default value: {x = default} or {w: {x, y} = default}
        final assignment = prop.value as AssignmentExpression;
        if (assignment.operator == '=') {
          Pattern leftPattern;

          if (assignment.left is IdentifierExpression) {
            final identifier = assignment.left as IdentifierExpression;
            leftPattern = IdentifierPattern(
              name: identifier.name,
              line: identifier.line,
              column: identifier.column,
            );
          } else if (assignment.left is ArrayExpression) {
            // Nested destructuring: {w: [a, b] = default}
            leftPattern = _convertArrayExpressionToPattern(
              assignment.left as ArrayExpression,
            );
          } else if (assignment.left is ObjectExpression) {
            // Nested destructuring: {w: {x, y} = default}
            leftPattern = _convertObjectExpressionToPattern(
              assignment.left as ObjectExpression,
            );
          } else if (assignment.left is MemberExpression) {
            // Member expression with default: {w: obj.prop = default} or {w: arr[index] = default}
            leftPattern = ExpressionPattern(
              expression: assignment.left as MemberExpression,
              line: assignment.left.line,
              column: assignment.left.column,
            );
          } else {
            throw ParseError(
              'Invalid default value in destructuring pattern',
              _peek(),
            );
          }

          value = leftPattern;
          // Create the property with the default value
          properties.add(
            ObjectPatternProperty(
              key: key,
              value: value,
              shorthand:
                  key ==
                  (assignment.left is IdentifierExpression
                      ? (assignment.left as IdentifierExpression).name
                      : ''),
              defaultValue: assignment.right,
              line: expr.line,
              column: expr.column,
            ),
          );
          continue; // Skip the final properties.add below
        } else {
          throw ParseError(
            'Invalid default value in destructuring pattern',
            _peek(),
          );
        }
      } else if (prop.value is DestructuringAssignmentExpression) {
        // Destructuring assignment in object property: {w: [a] = []} or {w: {x} = {}}
        final assignment = prop.value as DestructuringAssignmentExpression;
        value = assignment.left;
        // Create the property with the default value
        properties.add(
          ObjectPatternProperty(
            key: key,
            value: value,
            shorthand: false,
            defaultValue: assignment.right,
            line: expr.line,
            column: expr.column,
          ),
        );
        continue; // Skip the final properties.add below
      } else if (_isDestructuringPattern(prop.value)) {
        value = _expressionToPattern(prop.value);
      } else if (prop.value is MemberExpression) {
        // Member expressions are valid assignment targets: obj.prop or arr[index]
        value = ExpressionPattern(
          expression: prop.value as MemberExpression,
          line: prop.value.line,
          column: prop.value.column,
        );
      } else {
        throw ParseError('Invalid destructuring pattern value', _peek());
      }

      properties.add(
        ObjectPatternProperty(
          key: key,
          value: value,
          shorthand: shorthand,
          line: expr.line,
          column: expr.column,
        ),
      );
    }

    return ObjectPattern(
      properties: properties,
      restElement: restElement,
      line: expr.line,
      column: expr.column,
    );
  }

  /// Parse a conditional (ternaire) et nullish coalescing
  Expression _conditional() {
    final expr = _nullishCoalescing();

    if (_match([TokenType.question])) {
      final consequent = _expression();
      _consume(TokenType.colon, 'Expected \':\' after ternary condition');
      // IMPORTANT: Call _assignment() here to allow arrow functions
      // dans la partie alternate du ternaire
      final alternate = _assignment();

      return ConditionalExpression(
        test: expr,
        consequent: consequent,
        alternate: alternate,
        line: expr.line,
        column: expr.column,
      );
    }

    return expr;
  }

  /// Parse a nullish coalescing coalescing (??)
  Expression _nullishCoalescing() {
    final expr = _logicalOr();

    if (_match([TokenType.nullishCoalescing])) {
      final right = _nullishCoalescing();
      return NullishCoalescingExpression(
        left: expr,
        right: right,
        line: expr.line,
        column: expr.column,
      );
    }

    return expr;
  }

  /// Parse a logical OR
  Expression _logicalOr() {
    final expr = _logicalAnd();
    return _logicalBinary(expr, [TokenType.logicalOr], _logicalAnd);
  }

  /// Parse a logical AND expression
  Expression _logicalAnd() {
    final expr = _bitwiseOr();
    return _logicalBinary(expr, [TokenType.logicalAnd], _bitwiseOr);
  }

  /// Parse a bitwise OR expression (|)
  Expression _bitwiseOr() {
    final expr = _bitwiseXor();
    return _logicalBinary(expr, [TokenType.bitwiseOr], _bitwiseXor);
  }

  /// Parse a bitwise XOR expression (^)
  Expression _bitwiseXor() {
    final expr = _bitwiseAnd();
    return _logicalBinary(expr, [TokenType.bitwiseXor], _bitwiseAnd);
  }

  /// Parse a bitwise AND expression (&)
  Expression _bitwiseAnd() {
    final expr = _equality();
    return _logicalBinary(expr, [TokenType.bitwiseAnd], _equality);
  }

  /// Parse an equality
  Expression _equality() {
    final expr = _comparison();
    return _logicalBinary(expr, [
      TokenType.equal,
      TokenType.notEqual,
      TokenType.strictEqual,
      TokenType.strictNotEqual,
    ], _comparison);
  }

  /// Parse a comparison
  Expression _comparison() {
    final expr = _shift();
    return _logicalBinary(expr, [
      TokenType.lessThan,
      TokenType.lessThanEqual,
      TokenType.greaterThan,
      TokenType.greaterThanEqual,
      TokenType.keywordInstanceof,
      TokenType.keywordIn,
    ], _shift);
  }

  /// Parse a bitwise shift bitwise (<<, >>, >>>)
  Expression _shift() {
    final expr = _addition();
    return _logicalBinary(expr, [
      TokenType.leftShift,
      TokenType.rightShift,
      TokenType.unsignedRightShift,
    ], _addition);
  }

  /// Parse an addition/subtraction/soustraction
  Expression _addition() {
    final expr = _multiplication();
    return _logicalBinary(expr, [
      TokenType.plus,
      TokenType.minus,
    ], _multiplication);
  }

  /// Parse a multiplication/division/division
  Expression _multiplication() {
    final expr = _exponentiation();
    return _logicalBinary(expr, [
      TokenType.multiply,
      TokenType.divide,
      TokenType.modulo,
    ], _exponentiation);
  }

  /// Parse an exponentiation (**)
  /// Exponentiation has right associativity droite: 2 ** 3 ** 2 = 2 ** (3 ** 2) = 512
  Expression _exponentiation() {
    final expr = _unary();

    if (_match([TokenType.exponent])) {
      final operator = _previous();
      // Right associativity: recursive call to _exponentiation (not _unary)
      final right = _exponentiation();
      return BinaryExpression(
        left: expr,
        operator: operator.lexeme,
        right: right,
        line: operator.line,
        column: operator.column,
      );
    }

    return expr;
  }

  /// Helper for binary expressions with precedence
  Expression _logicalBinary(
    Expression left,
    List<TokenType> operators,
    Expression Function() nextLevel,
  ) {
    var expr = left;

    while (_match(operators)) {
      final operator = _previous();
      final right = nextLevel();
      expr = BinaryExpression(
        left: expr,
        operator: operator.lexeme,
        right: right,
        line: operator.line,
        column: operator.column,
      );
    }

    return expr;
  }

  /// Parse a unary
  Expression _unary() {
    // Handle await - can be used as:
    // 1. Unary expression when in an async context
    // 2. Operator at top-level in module mode (ES2022 top-level await)
    // 3. Identifier when outside async context (for other contexts)
    if (_check(TokenType.keywordAwait)) {
      final nextToken = _peekNext();

      // Treat as unary operator if:
      // - We're in async context, OR
      // - Next token is not '(' - if it's '(', then await is being used as identifier (function call)
      if (_inAsyncContext || nextToken?.type != TokenType.leftParen) {
        // Also exclude other terminators where await should be an identifier
        if (nextToken?.type == TokenType.semicolon ||
            nextToken?.type == TokenType.comma ||
            nextToken?.type == TokenType.rightBrace ||
            nextToken?.type == TokenType.rightParen ||
            nextToken?.type == TokenType.rightBracket ||
            nextToken?.type == TokenType.colon ||
            nextToken?.type == TokenType.eof) {
          // Fall through to let _primary() handle as identifier
        } else {
          // Treat as unary operator (await expression)
          _advance();
          final awaitToken = _previous();
          final argument = _unary(); // Recursive for chained awaits

          return AwaitExpression(
            argument: argument,
            line: awaitToken.line,
            column: awaitToken.column,
          );
        }
      }
      // Otherwise, fall through to let _primary() handle it as identifier
    }

    // Handle yield and yield* - only if we are in a generator context
    if (_check(TokenType.keywordYield) && _inGeneratorContext) {
      _advance();
      final yieldToken = _previous();

      // Check if it's yield* (delegation)
      final bool delegate = _match([TokenType.multiply]);

      // The argument is optional for yield (but mandatory for yield*)
      // yield sans argument est valide quand suivi de: ; } ] ) , :
      Expression? argument;
      if (delegate ||
          (!_check(TokenType.semicolon) &&
              !_check(TokenType.rightBrace) &&
              !_check(TokenType.rightBracket) &&
              !_check(TokenType.rightParen) &&
              !_check(TokenType.comma) &&
              !_check(TokenType.colon))) {
        argument = _assignmentExpression();
      }

      return YieldExpression(
        argument: argument,
        delegate: delegate,
        line: yieldToken.line,
        column: yieldToken.column,
      );
    }

    if (_match([
      TokenType.logicalNot,
      TokenType.minus,
      TokenType.plus,
      TokenType.increment,
      TokenType.decrement,
      TokenType.bitwiseNot,
      TokenType.keywordTypeof,
      TokenType.keywordVoid,
      TokenType.keywordDelete,
    ])) {
      final operator = _previous();
      final right = _unary();

      return UnaryExpression(
        operator: operator.lexeme,
        operand: right,
        prefix: true,
        line: operator.line,
        column: operator.column,
      );
    }

    return _postfix();
  }

  /// Parse a postfix (++ et --)
  Expression _postfix() {
    var expr = _call();

    if (_match([TokenType.increment, TokenType.decrement])) {
      final operator = _previous();
      expr = UnaryExpression(
        operator: operator.lexeme,
        operand: expr,
        prefix: false,
        line: operator.line,
        column: operator.column,
      );
    }

    return expr;
  }

  /// Finalize function call analysis

  /// Parse a call and member access (merged for chaining)
  Expression _call() {
    var expr = _primary();

    while (true) {
      if (_match([TokenType.leftParen])) {
        // Function call: func()
        expr = _finishCall(expr);
      } else if (_match([TokenType.dot])) {
        // Member access: obj.prop or obj.#privateProp
        Expression property;
        if (_check(TokenType.identifier) || _check(TokenType.keywordFor)) {
          final name = _advance();
          property = IdentifierExpression(
            name: name.lexeme,
            line: name.line,
            column: name.column,
          );
        } else if (_check(TokenType.privateIdentifier)) {
          final name = _advance();
          property = PrivateIdentifierExpression(
            name: name.lexeme,
            line: name.line,
            column: name.column,
          );
        } else if (_checkGet() ||
            _checkSet() ||
            _isKeywordAllowedAsMethodName()) {
          // Allow 'get', 'set' and other keywords as property names (ex: obj.from)
          final name = _advance();
          property = IdentifierExpression(
            name: name.lexeme,
            line: name.line,
            column: name.column,
          );
        } else {
          throw ParseError('Expected property name after \'.\'', _peek());
        }

        expr = MemberExpression(
          object: expr,
          property: property,
          computed: false,
          line: expr.line,
          column: expr.column,
        );
      } else if (_match([TokenType.optionalChaining])) {
        // Optional chaining: obj?.prop ou obj?.[key] ou obj?.method()
        if (_match([TokenType.leftParen])) {
          // Optional method call: obj?.method()
          expr = _finishOptionalCall(expr);
        } else if (_match([TokenType.leftBracket])) {
          // Optional computed access: obj?.[key]
          final property = _expression();
          _consume(
            TokenType.rightBracket,
            'Expected \']\' after optional computed property',
          );
          expr = OptionalChainingExpression(
            object: expr,
            property: property,
            isCall: false,
            line: expr.line,
            column: expr.column,
          );
        } else {
          // Optional property access: obj?.prop
          Expression property;
          if (_check(TokenType.identifier)) {
            final name = _advance();
            property = IdentifierExpression(
              name: name.lexeme,
              line: name.line,
              column: name.column,
            );
          } else if (_check(TokenType.privateIdentifier)) {
            final name = _advance();
            property = PrivateIdentifierExpression(
              name: name.lexeme,
              line: name.line,
              column: name.column,
            );
          } else {
            throw ParseError('Expected property name after \'?.\'', _peek());
          }

          expr = OptionalChainingExpression(
            object: expr,
            property: property,
            isCall: false,
            line: expr.line,
            column: expr.column,
          );
        }
      } else if (_match([TokenType.leftBracket])) {
        // Computed access: obj[key]
        final property = _expression();
        _consume(
          TokenType.rightBracket,
          'Expected \']\' after computed property',
        );
        expr = MemberExpression(
          object: expr,
          property: property,
          computed: true,
          line: expr.line,
          column: expr.column,
        );
      } else if (_check(TokenType.templateString)) {
        // Tagged template literal: func`template` or obj.method`template`
        final template = _advance();
        final content = template.literal as String?;

        if (content?.contains('\${') ?? false) {
          expr = TaggedTemplateExpression(
            tag: expr,
            quasi:
                _parseTemplateLiteralWithInterpolation(content ?? '', template)
                    as TemplateLiteralExpression,
            line: expr.line,
            column: expr.column,
          );
        } else {
          // Simple template sans interpolation: just the template content as one quasi
          expr = TaggedTemplateExpression(
            tag: expr,
            quasi: TemplateLiteralExpression(
              quasis: [content ?? ''],
              expressions: [],
              line: template.line,
              column: template.column,
            ),
            line: expr.line,
            column: expr.column,
          );
        }
      } else {
        break;
      }
    }

    return expr;
  }

  /// Finalise l'analyse d'un appel de fonction
  Expression _finishCall(Expression callee) {
    // Parser les arguments avec support trailing comma (ES2017)
    final arguments = _parseFunctionArguments();

    _consume(TokenType.rightParen, 'Expected \')\' after arguments');

    // Special handling for method calls with optional chaining
    // If callee is an OptionalChainingExpression with isCall: false,
    // this means that it's obj?.method() which should be treated as an optional call
    if (callee is OptionalChainingExpression && !callee.isCall) {
      // Create a CallExpression for the arguments
      final callExpr = CallExpression(
        callee: callee
            .property, // <-- callee.property is the identifier of the method
        arguments: arguments,
        line: callee.line,
        column: callee.column,
      );

      // Transformer en OptionalChainingExpression avec isCall: true
      return OptionalChainingExpression(
        object: callee.object,
        property: callExpr,
        isCall: true,
        line: callee.line,
        column: callee.column,
      );
    }

    return CallExpression(
      callee: callee,
      arguments: arguments,
      line: callee.line,
      column: callee.column,
    );
  }

  /// Finalise l'analyse d'un appel de fonction avec optional chaining
  Expression _finishOptionalCall(Expression object) {
    // Parser les arguments avec support trailing comma (ES2017)
    final arguments = _parseFunctionArguments();

    _consume(TokenType.rightParen, 'Expected \')\' after arguments');

    // For optional call f?.(), the evaluator needs to know that it's a direct call
    // Not a method call. Create a special CallExpression that will be handled
    // differently in the evaluator.
    // NOTE: The callee must be null or a special marker because the evaluator
    // will use the object as the function to call

    // Solution: Create a CallExpression with a special marker (empty IdentifierExpression)
    // which tells the evaluator that it's a direct call on the object
    final callExpr = CallExpression(
      callee: IdentifierExpression(
        name: '__optionalCallMarker__',
        line: object.line,
        column: object.column,
      ),
      arguments: arguments,
      line: object.line,
      column: object.column,
    );

    return OptionalChainingExpression(
      object: object,
      property: callExpr,
      isCall: true,
      line: object.line,
      column: object.column,
    );
  }

  /// Parse member access (obj.prop, obj[key]) mais pas les appels de fonctions
  Expression _memberAccess() {
    var expr = _primary();

    while (true) {
      if (_match([TokenType.dot])) {
        // Member access: obj.prop or obj.#privateProp
        Expression property;
        if (_check(TokenType.identifier)) {
          final name = _advance();
          property = IdentifierExpression(
            name: name.lexeme,
            line: name.line,
            column: name.column,
          );
        } else if (_check(TokenType.privateIdentifier)) {
          final name = _advance();
          property = PrivateIdentifierExpression(
            name: name.lexeme,
            line: name.line,
            column: name.column,
          );
        } else if (_checkGet() || _checkSet()) {
          // Allow 'get' and 'set' as property names (e.g: desc.get)
          final name = _advance();
          property = IdentifierExpression(
            name: name.lexeme,
            line: name.line,
            column: name.column,
          );
        } else if (_isKeywordAllowedAsMethodNameToken(_peek())) {
          // Allow keywords as property names (e.g., obj.with, obj.delete)
          final name = _advance();
          property = IdentifierExpression(
            name: name.lexeme,
            line: name.line,
            column: name.column,
          );
        } else {
          throw ParseError('Expected property name after \'.\'', _peek());
        }

        expr = MemberExpression(
          object: expr,
          property: property,
          computed: false,
          line: expr.line,
          column: expr.column,
        );
      } else if (_match([TokenType.leftBracket])) {
        // Computed access: obj[key]
        final property = _expression();
        _consume(
          TokenType.rightBracket,
          'Expected \']\' after computed property',
        );
        expr = MemberExpression(
          object: expr,
          property: property,
          computed: true,
          line: expr.line,
          column: expr.column,
        );
      } else if (_match([TokenType.optionalChaining])) {
        // Optional chaining: obj?.prop or obj?.[key]
        if (_match([TokenType.leftBracket])) {
          // Computed optional: obj?.[key]
          final property = _expression();
          _consume(
            TokenType.rightBracket,
            'Expected \']\' after optional computed property',
          );
          expr = OptionalChainingExpression(
            object: expr,
            property: property,
            isCall: false,
            line: expr.line,
            column: expr.column,
          );
        } else if (_check(TokenType.identifier) ||
            _check(TokenType.privateIdentifier) ||
            _checkGet() ||
            _checkSet() ||
            _isKeywordAllowedAsMethodNameToken(_peek())) {
          // Property optional: obj?.prop
          Expression property;
          if (_check(TokenType.identifier)) {
            final name = _advance();
            property = IdentifierExpression(
              name: name.lexeme,
              line: name.line,
              column: name.column,
            );
          } else if (_check(TokenType.privateIdentifier)) {
            final name = _advance();
            property = PrivateIdentifierExpression(
              name: name.lexeme,
              line: name.line,
              column: name.column,
            );
          } else if (_checkGet() || _checkSet()) {
            final name = _advance();
            property = IdentifierExpression(
              name: name.lexeme,
              line: name.line,
              column: name.column,
            );
          } else {
            final name = _advance();
            property = IdentifierExpression(
              name: name.lexeme,
              line: name.line,
              column: name.column,
            );
          }

          expr = OptionalChainingExpression(
            object: expr,
            property: property,
            isCall: false,
            line: expr.line,
            column: expr.column,
          );
        } else {
          throw ParseError('Expected property or call after \'?.\'', _peek());
        }
      } else {
        break;
      }
    }

    return expr;
  }

  /// Parse a primary (literals, identifiers, groupings)
  Expression _primary() {
    // Expression new: new Constructor() or new.target
    if (_match([TokenType.keywordNew])) {
      final newToken = _previous();

      // Check for new.target meta property
      if (_match([TokenType.dot])) {
        if (_check(TokenType.identifier) && _peek().lexeme == 'target') {
          _advance(); // Consume 'target'
          return MetaProperty(
            meta: 'new',
            property: 'target',
            line: newToken.line,
            column: newToken.column,
          );
        }
        throw ParseError('Expected "target" after "new."', _peek());
      }

      final constructor =
          _memberAccess(); // Parse the expression including member accesses but not calls

      // If it's followed by parentheses, treat it as a call
      List<Expression> arguments = [];
      if (_check(TokenType.leftParen)) {
        _advance(); // consommer '('

        // ES2017: Use helper method that supports trailing commas
        arguments = _parseFunctionArguments();

        _consume(TokenType.rightParen, "Expected ')' after arguments");
      }

      return NewExpression(
        callee: constructor,
        arguments: arguments,
        line: newToken.line,
        column: newToken.column,
      );
    }

    // Literals
    if (_match([TokenType.keywordTrue])) {
      final token = _previous();
      return LiteralExpression(
        value: true,
        type: 'boolean',
        line: token.line,
        column: token.column,
      );
    }

    if (_match([TokenType.keywordFalse])) {
      final token = _previous();
      return LiteralExpression(
        value: false,
        type: 'boolean',
        line: token.line,
        column: token.column,
      );
    }

    if (_match([TokenType.keywordNull])) {
      final token = _previous();
      return LiteralExpression(
        value: null,
        type: 'null',
        line: token.line,
        column: token.column,
      );
    }

    if (_match([TokenType.keywordUndefined])) {
      final token = _previous();
      return LiteralExpression(
        value: null,
        type: 'undefined',
        line: token.line,
        column: token.column,
      );
    }

    if (_match([TokenType.number])) {
      final token = _previous();
      return LiteralExpression(
        value: token.literal,
        type: 'number',
        line: token.line,
        column: token.column,
      );
    }

    // Legacy octal literals (010, 077, etc.)
    // These literals are treated as numbers but marked specially
    // to allow error detection in strict mode
    if (_match([TokenType.legacyOctal])) {
      final token = _previous();
      return LiteralExpression(
        value: token.literal,
        type: 'legacyOctal', // Special type for strict mode detection
        line: token.line,
        column: token.column,
      );
    }

    if (_match([TokenType.bigint])) {
      final token = _previous();
      return LiteralExpression(
        value: token.literal,
        type: 'bigint',
        line: token.line,
        column: token.column,
      );
    }

    if (_match([TokenType.string])) {
      final token = _previous();
      return LiteralExpression(
        value: token.literal,
        type: 'string',
        line: token.line,
        column: token.column,
      );
    }

    // Regex literals
    if (_match([TokenType.regex])) {
      final token = _previous();
      final regexValue = token.lexeme; // '/pattern/flags'

      // Extraire le pattern et les flags
      final match = RegExp(r'^/(.*)/(.*?)$').firstMatch(regexValue);
      if (match != null) {
        final pattern = match.group(1)!;
        final flags = match.group(2)!;

        return RegexLiteralExpression(
          pattern: pattern,
          flags: flags,
          line: token.line,
          column: token.column,
        );
      } else {
        throw ParseError('Invalid regex literal: $regexValue', token);
      }
    }

    // Template literals
    if (_match([TokenType.templateString])) {
      final token = _previous();
      final content = token.literal as String;

      // Check if there are interpolations
      if (content.contains('\${')) {
        return _parseTemplateLiteralWithInterpolation(content, token);
      } else {
        // Template simple sans interpolation
        return LiteralExpression(
          value: content,
          type: 'template',
          line: token.line,
          column: token.column,
        );
      }
    }

    // Identifiants
    if (_match([TokenType.identifier])) {
      final token = _previous();

      // Check for escaped await/yield used as identifier reference in async/generator context
      _checkAwaitAsIdentifierInAsyncContext(token);

      return IdentifierExpression(
        name: token.lexeme,
        line: token.line,
        column: token.column,
      );
    }

    // Contextual keywords as identifiers
    // await is reserved in async function bodies (always, even in sloppy mode)
    // Outside async context, await can be used as an identifier
    if (_match([TokenType.keywordAwait])) {
      final token = _previous();

      // Check if we're in an async function context
      if (_inAsyncContext) {
        throw ParseError(
          'await is not a valid identifier reference in async function context',
          token,
        );
      }

      return IdentifierExpression(
        name: token.lexeme,
        line: token.line,
        column: token.column,
      );
    }

    // yield is an identifier outside generator context
    // In sloppy mode, it can even be used inside generator functions
    if (_match([TokenType.keywordYield])) {
      final token = _previous();
      return IdentifierExpression(
        name: token.lexeme,
        line: token.line,
        column: token.column,
      );
    }

    // 'let' can be an identifier in non-strict mode
    // This handles cases like: let; (when used as expression) or if (false) let
    if (_check(TokenType.keywordLet) && !_isInStrictMode()) {
      final token = _advance();
      return IdentifierExpression(
        name: token.lexeme,
        line: token.line,
        column: token.column,
      );
    }

    // 'static', 'get', 'set' can be identifiers in general contexts
    // (not used as keywords outside of class methods)
    if (_match([TokenType.keywordStatic]) ||
        _match([TokenType.keywordGet]) ||
        _match([TokenType.keywordSet]) ||
        _match([TokenType.keywordOf]) ||
        _match([TokenType.keywordIn])) {
      final token = _previous();
      return IdentifierExpression(
        name: token.lexeme,
        line: token.line,
        column: token.column,
      );
    }

    // Private identifiers
    if (_match([TokenType.privateIdentifier])) {
      final token = _previous();
      return PrivateIdentifierExpression(
        name: token.lexeme,
        line: token.line,
        column: token.column,
      );
    }

    // This expression
    if (_match([TokenType.keywordThis])) {
      final token = _previous();
      return ThisExpression(line: token.line, column: token.column);
    }

    // Super expression
    if (_match([TokenType.keywordSuper])) {
      final token = _previous();
      return SuperExpression(line: token.line, column: token.column);
    }

    // Function expressions
    if (_match([TokenType.keywordAsync])) {
      final asyncToken = _previous();
      if (_match([TokenType.keywordFunction])) {
        // Validate that 'async' doesn't contain Unicode escapes (only when used as async function keyword)
        if (asyncToken.hasUnicodeEscape) {
          throw ParseError(
            'Contextual keyword "async" must not contain Unicode escape sequences',
            asyncToken,
          );
        }
        return _asyncFunctionExpression();
      } else {
        // Async arrow function: async (params) => body ou async param => body
        // But per spec: async [no LineTerminator here] AsyncArrowBindingIdentifier
        // If there's a line terminator after async, treat async as identifier
        final nextToken = _peek();

        // Check for line terminator between async and next token
        if (asyncToken.line != nextToken.line) {
          // There's a line terminator - treat async as an identifier (not validating escapes)
          return IdentifierExpression(
            name: 'async',
            line: asyncToken.line,
            column: asyncToken.column,
          );
        }

        // If 'async' has Unicode escapes and is followed by 'of' or 'in', treat as identifier
        // (for-of/for-in loops allow escaped async as identifier: for (\u0061sync of [...]))
        if (asyncToken.hasUnicodeEscape &&
            (nextToken.type == TokenType.keywordOf ||
                nextToken.type == TokenType.keywordIn)) {
          return IdentifierExpression(
            name: 'async',
            line: asyncToken.line,
            column: asyncToken.column,
          );
        }

        // Now we know async is being used as keyword (not followed by line terminator)
        // Validate that it doesn't contain Unicode escapes
        if (asyncToken.hasUnicodeEscape) {
          throw ParseError(
            'Contextual keyword "async" must not contain Unicode escape sequences',
            asyncToken,
          );
        }

        // Parse arrow function parameters
        Expression params;

        if (_match([TokenType.leftParen])) {
          // async (param1, param2) => body or async () => body
          if (_check(TokenType.rightParen)) {
            // Special case for async () =>
            _advance(); // consume ')'
            params = SequenceExpression(
              expressions: [],
              line: asyncToken.line,
              column: asyncToken.column,
            );
          } else {
            // Grouped expression for parameters
            params = _expression();
            _consume(TokenType.rightParen, 'Expected \')\' after parameters');
          }
        } else if (_check(TokenType.identifier)) {
          // async param => body (single parameter without parentheses)
          final paramToken = _advance();
          params = IdentifierExpression(
            name: paramToken.lexeme,
            line: paramToken.line,
            column: paramToken.column,
          );
        } else if (_checkContextualKeywordForArrowParam()) {
          // async keywordParam => body (contextual keyword as parameter)
          // Keywords like 'of', 'in', 'let', etc. can be arrow parameters
          final paramToken = _advance();
          params = IdentifierExpression(
            name: paramToken.lexeme,
            line: paramToken.line,
            column: paramToken.column,
          );
        } else {
          // Not an async arrow function, treat async as identifier
          return IdentifierExpression(
            name: 'async',
            line: asyncToken.line,
            column: asyncToken.column,
          );
        }

        // Maintenant on doit avoir '=>'
        if (!_check(TokenType.arrow)) {
          throw ParseError('Expected \'=>\' for async arrow function', _peek());
        }

        return _parseAsyncArrowFunction(params, asyncToken);
      }
    }

    if (_match([TokenType.keywordFunction])) {
      return _functionExpression();
    }

    // Class expressions: const MyClass = class { ... }
    if (_match([TokenType.keywordClass])) {
      return _classExpression();
    }

    // Grouping of expressions or arrow function with empty parameters
    if (_match([TokenType.leftParen])) {
      // Look ahead to detect () =>
      if (_check(TokenType.rightParen)) {
        // Special case for () =>
        final nextIndex = _current + 1;
        if (nextIndex < tokens.length &&
            tokens[nextIndex].type == TokenType.arrow) {
          // It's an arrow function without parameters
          _advance(); // consume ')'
          return _parseArrowFunction(
            SequenceExpression(
              expressions: [],
              line: _previous().line,
              column: _previous().column,
            ),
          );
        }
      }

      // Detect (...rest) => for arrow function with rest parameter
      if (_check(TokenType.spread)) {
        // It's probably an arrow function with rest parameter
        // Parse as function parameters
        _advance(); // consume ...

        // Rest parameter can be:
        // 1. A simple identifier: ..._
        // 2. A destructuring: ...[a, b] or ...{x, y}

        Expression restExpr;

        if (_check(TokenType.leftBracket) || _check(TokenType.leftBrace)) {
          // Destructuring: parse as expression first, will be converted to pattern
          restExpr = _assignmentExpression();
        } else {
          // Simple identifier
          final restParam = _consume(
            TokenType.identifier,
            'Expected parameter name or destructuring pattern after ...',
          );
          restExpr = IdentifierExpression(
            name: restParam.lexeme,
            line: restParam.line,
            column: restParam.column,
          );
        }

        _consume(TokenType.rightParen, 'Expected \')\' after rest parameter');

        // Check if there's =>
        if (_check(TokenType.arrow)) {
          // Create a SpreadElement to represent the rest parameter temporarily
          final spreadExpr = SpreadElement(
            argument: restExpr,
            line: restExpr.line,
            column: restExpr.column,
          );
          return _parseArrowFunction(spreadExpr);
        } else {
          throw ParseError(
            'Expected \'=>\' after arrow function parameters',
            _peek(),
          );
        }
      }

      // Normal grouped expression
      final expr = _expression();

      // ES2017: Support trailing comma before ')' in arrow function parameters
      // If we have a comma after the expression(s), check if ')' follows
      if (_match([TokenType.comma])) {
        if (!_check(TokenType.rightParen)) {
          throw ParseError('Unexpected token after trailing comma', _peek());
        }
        // Trailing comma is allowed, continue to consume ')'
      }

      _consume(TokenType.rightParen, 'Expected \')\' after expression');
      return expr;
    }

    // Tableaux
    if (_match([TokenType.leftBracket])) {
      return _parseArrayExpression();
    }

    // Objets
    if (_match([TokenType.leftBrace])) {
      return _parseObjectExpression();
    }

    // Import dynamique: import('module') ou import.meta
    if (_check(TokenType.keywordImport)) {
      final importToken = _peek();

      // Lookahead to check if this is import.meta or import(...)
      // vs import used as an identifier
      final nextToken = _peekNext();

      if (nextToken?.type != TokenType.dot &&
          nextToken?.type != TokenType.leftParen) {
        // 'import' is being used as an identifier (not import.meta or import(...))
        // This is valid in expression context
        _advance();
        return IdentifierExpression(
          name: importToken.lexeme,
          line: importToken.line,
          column: importToken.column,
        );
      }

      _advance(); // consume 'import'

      // Check if it's import.meta
      if (_match([TokenType.dot])) {
        if (_check(TokenType.identifier) && _peek().lexeme == 'meta') {
          _advance(); // Consume 'meta'
          return MetaProperty(
            meta: 'import',
            property: 'meta',
            line: importToken.line,
            column: importToken.column,
          );
        }
        throw ParseError('Expected "meta" after "import."', _peek());
      }

      // Sinon c'est import('module')
      _consume(TokenType.leftParen, "Expected '(' after import");
      final source = _expression();
      _consume(TokenType.rightParen, "Expected ')' after import source");

      return ImportExpression(
        source: source,
        line: importToken.line,
        column: importToken.column,
      );
    }

    throw ParseError('Expected expression', _peek());
  }

  /// Parse an array (consomme le token ouvrant)
  ArrayExpression _parseArrayExpression() {
    final start = _previous(); // The token '[' has already been consumed
    final elements = <Expression?>[];

    while (!_check(TokenType.rightBracket)) {
      if (_match([TokenType.comma])) {
        // Empty element: we add null to represent the hole
        elements.add(null);
      } else if (_match([TokenType.spread])) {
        // Spread element: ...expression
        final spreadStart = _previous();
        final argument = _assignmentExpression();
        elements.add(
          SpreadElement(
            argument: argument,
            line: spreadStart.line,
            column: spreadStart.column,
          ),
        );
        // After a spread, we must have a comma or the end
        if (!_check(TokenType.rightBracket)) {
          _consume(TokenType.comma, 'Expected \',\' after spread element');
        }
      } else {
        // Normal expression
        elements.add(_assignmentExpression());
        // After an expression, we must have a comma or the end
        if (!_check(TokenType.rightBracket)) {
          _consume(TokenType.comma, 'Expected \',\' after array element');
        }
      }
    }

    _consume(TokenType.rightBracket, 'Expected \']\' after array elements');

    return ArrayExpression(
      elements: elements,
      line: start.line,
      column: start.column,
    );
  }

  /// Parse an object (consumes the opening token)
  ObjectExpression _parseObjectExpression() {
    final start = _previous(); // The token '{' has already been consumed
    final properties = <dynamic>[]; // ObjectProperty or SpreadElement

    if (!_check(TokenType.rightBrace)) {
      do {
        // Check if it's a spread element: ...obj
        if (_match([TokenType.spread])) {
          final spreadStart = _previous();
          final argument = _assignmentExpression();
          properties.add(
            SpreadElement(
              argument: argument,
              line: spreadStart.line,
              column: spreadStart.column,
            ),
          );
          continue;
        }

        // Check if it's a getter or setter
        if (_checkGet()) {
          final next = _peekNext();
          bool isGetter = false;

          if (next != null) {
            if (next.type == TokenType.leftBracket) {
              // Computed property: get [expr]()
              isGetter = true;
            } else if (next.type == TokenType.identifier ||
                next.type == TokenType.string ||
                next.type == TokenType.number ||
                next.type == TokenType.bigint ||
                _isKeywordAllowedAsMethodNameToken(next)) {
              // Simple property: get prop(), get return(), etc.
              // Need to look ahead to make sure next token after prop is (
              final afterNext = _current + 2 < tokens.length
                  ? tokens[_current + 2]
                  : null;
              if (afterNext != null && afterNext.type == TokenType.leftParen) {
                isGetter = true;
              }
            }
          }

          if (isGetter) {
            _advance(); // consume 'get'
            final getToken = _previous();

            // Validate that 'get' doesn't contain Unicode escapes
            if (getToken.hasUnicodeEscape) {
              throw ParseError(
                'Contextual keyword "get" must not contain Unicode escape sequences',
                getToken,
              );
            }

            // Create the appropriate key according to the type
            Expression key;
            bool computed = false;

            if (_match([TokenType.leftBracket])) {
              // Computed property
              computed = true;
              key = _assignmentExpression();
              _consume(
                TokenType.rightBracket,
                'Expected \']\' after computed property',
              );
            } else {
              final propertyToken = _advance();

              if (propertyToken.type == TokenType.string) {
                key = LiteralExpression(
                  value: propertyToken.literal,
                  type: 'string',
                  line: propertyToken.line,
                  column: propertyToken.column,
                );
              } else if (propertyToken.type == TokenType.number) {
                key = LiteralExpression(
                  value: propertyToken.literal,
                  type: 'number',
                  line: propertyToken.line,
                  column: propertyToken.column,
                );
              } else if (propertyToken.type == TokenType.bigint) {
                key = LiteralExpression(
                  value: propertyToken.literal,
                  type: 'bigint',
                  line: propertyToken.line,
                  column: propertyToken.column,
                );
              } else {
                key = IdentifierExpression(
                  name: propertyToken.lexeme,
                  line: propertyToken.line,
                  column: propertyToken.column,
                );
              }
            }

            _consume(TokenType.leftParen, 'Expected \'(\' after getter name');

            // Getters have no parameters
            _consume(
              TokenType.rightParen,
              'Expected \')\' after getter parameters',
            );

            final oldFunctionDepth = _functionDepth;
            _functionDepth++; // Increment for getter body parsing

            final body = _blockStatement();

            _functionDepth = oldFunctionDepth; // Restore

            final functionExpr = FunctionExpression(
              params: [],
              body: body,
              line: getToken.line,
              column: getToken.column,
            );

            properties.add(
              ObjectProperty(
                key: key,
                value: functionExpr,
                computed: computed,
                kind: 'get',
              ),
            );
            continue; // Move to next property
          }
        } else if (_checkSet()) {
          final next = _peekNext();
          bool isSetter = false;

          if (next != null) {
            if (next.type == TokenType.leftBracket) {
              // Computed property: set [expr](param)
              isSetter = true;
            } else if (next.type == TokenType.identifier ||
                next.type == TokenType.string ||
                next.type == TokenType.number ||
                next.type == TokenType.bigint ||
                _isKeywordAllowedAsMethodNameToken(next)) {
              // Simple property: set prop(param), set return(v), etc.
              // Need to look ahead to make sure next token after prop is (
              final afterNext = _current + 2 < tokens.length
                  ? tokens[_current + 2]
                  : null;
              if (afterNext != null && afterNext.type == TokenType.leftParen) {
                isSetter = true;
              }
            }
          }

          if (isSetter) {
            _advance(); // consume 'set'
            final setToken = _previous();

            // Validate that 'set' doesn't contain Unicode escapes
            if (setToken.hasUnicodeEscape) {
              throw ParseError(
                'Contextual keyword "set" must not contain Unicode escape sequences',
                setToken,
              );
            }

            // Create the appropriate key according to the type
            Expression key;
            bool computed = false;

            if (_match([TokenType.leftBracket])) {
              // Computed property
              computed = true;
              key = _assignmentExpression();
              _consume(
                TokenType.rightBracket,
                'Expected \']\' after computed property',
              );
            } else {
              final propertyToken = _advance();

              if (propertyToken.type == TokenType.string) {
                key = LiteralExpression(
                  value: propertyToken.literal,
                  type: 'string',
                  line: propertyToken.line,
                  column: propertyToken.column,
                );
              } else if (propertyToken.type == TokenType.number) {
                key = LiteralExpression(
                  value: propertyToken.literal,
                  type: 'number',
                  line: propertyToken.line,
                  column: propertyToken.column,
                );
              } else if (propertyToken.type == TokenType.bigint) {
                key = LiteralExpression(
                  value: propertyToken.literal,
                  type: 'bigint',
                  line: propertyToken.line,
                  column: propertyToken.column,
                );
              } else {
                key = IdentifierExpression(
                  name: propertyToken.lexeme,
                  line: propertyToken.line,
                  column: propertyToken.column,
                );
              }
            }

            _consume(TokenType.leftParen, 'Expected \'(\' after setter name');

            // Setters have one parameter - can be destructuring or with default value
            dynamic nameOrPattern;
            Expression? defaultValue;

            if (_check(TokenType.leftBrace) || _check(TokenType.leftBracket)) {
              // Destructuring pattern
              final expr = _primary();
              nameOrPattern = _expressionToPattern(expr);

              // Support pour default value
              if (_match([TokenType.assign])) {
                defaultValue = _assignmentExpression();
              }
            } else if (_check(TokenType.identifier) ||
                _check(TokenType.keywordAwait) ||
                _check(TokenType.keywordYield)) {
              final param = _advance();
              nameOrPattern = IdentifierExpression(
                name: param.lexeme,
                line: param.line,
                column: param.column,
              );

              // Support pour default value
              if (_match([TokenType.assign])) {
                defaultValue = _assignmentExpression();
              }
            } else {
              throw ParseError(
                'Expected parameter name or destructuring pattern',
                _peek(),
              );
            }

            _consume(
              TokenType.rightParen,
              'Expected \')\' after setter parameter',
            );

            final oldFunctionDepth = _functionDepth;
            _functionDepth++; // Increment for setter body parsing

            final body = _blockStatement();

            _functionDepth = oldFunctionDepth; // Restore

            final functionExpr = FunctionExpression(
              params: [
                Parameter(
                  nameOrPattern: nameOrPattern,
                  defaultValue: defaultValue,
                ),
              ],
              body: body,
              line: setToken.line,
              column: setToken.column,
            );

            properties.add(
              ObjectProperty(
                key: key,
                value: functionExpr,
                computed: computed,
                kind: 'set',
              ),
            );
            continue; // Move to next property
          }
        }

        // Check for generator method: *methodName() { }
        if (_match([TokenType.multiply])) {
          // Generator method: *foo() { yield ... }
          Expression methodKey;
          bool methodComputed = false;

          if (_match([TokenType.leftBracket])) {
            // Computed generator method: *[expr]() {}
            methodKey = _assignmentExpression();
            _consume(
              TokenType.rightBracket,
              'Expected \']\' after computed method name',
            );
            methodComputed = true;
          } else if (_check(TokenType.identifier) ||
              _isKeywordAllowedAsMethodName()) {
            // Named generator method: *foo() {}
            final methodToken = _advance();
            methodKey = IdentifierExpression(
              name: methodToken.lexeme,
              line: methodToken.line,
              column: methodToken.column,
            );
          } else if (_match([TokenType.string])) {
            // String method name: *"method"() {}
            final methodToken = _previous();
            methodKey = LiteralExpression(
              value: methodToken.literal,
              type: 'string',
              line: methodToken.line,
              column: methodToken.column,
            );
          } else if (_match([TokenType.number])) {
            // Number method name: *42() {}
            final methodToken = _previous();
            methodKey = LiteralExpression(
              value: methodToken.literal,
              type: 'number',
              line: methodToken.line,
              column: methodToken.column,
            );
          } else if (_match([TokenType.bigint])) {
            // BigInt method name: *123n() {}
            final methodToken = _previous();
            methodKey = LiteralExpression(
              value: methodToken.literal,
              type: 'bigint',
              line: methodToken.line,
              column: methodToken.column,
            );
          } else {
            throw ParseError('Expected generator method name', _peek());
          }

          _consume(
            TokenType.leftParen,
            'Expected \'(\' after generator method name',
          );

          // Parse parameters
          final oldGeneratorContext = _inGeneratorContext;
          _inGeneratorContext = true;

          final params = _parseFunctionParameters();

          _consume(
            TokenType.rightParen,
            'Expected \')\' after generator method parameters',
          );

          final oldFunctionDepth = _functionDepth;
          _functionDepth++; // Increment for method body parsing

          final body = _blockStatement();
          _inGeneratorContext = oldGeneratorContext;
          _functionDepth = oldFunctionDepth;

          final functionExpr = FunctionExpression(
            params: params,
            body: body,
            isGenerator: true,
            line: _previous().line,
            column: _previous().column,
          );

          properties.add(
            ObjectProperty(
              key: methodKey,
              value: functionExpr,
              computed: methodComputed,
              kind: 'method',
            ),
          );
          continue;
        }

        // Check for async method: async foo() {} or async *foo() {}
        if (_check(TokenType.keywordAsync)) {
          final asyncToken = _peek();
          final next = _peekNext();
          // Check if this is async method (not async: value or async shorthand)
          if (next != null &&
              (next.type == TokenType.identifier ||
                  next.type == TokenType.multiply ||
                  next.type == TokenType.leftBracket ||
                  next.type == TokenType.string ||
                  next.type == TokenType.number ||
                  next.type == TokenType.bigint ||
                  _isKeywordAllowedAsMethodNameToken(next))) {
            // Validate that 'async' doesn't contain Unicode escapes
            if (asyncToken.hasUnicodeEscape) {
              throw ParseError(
                'Contextual keyword "async" must not contain Unicode escape sequences',
                asyncToken,
              );
            }
            _advance(); // consume 'async'

            // Check for async generator: async *foo() {}
            final bool isAsyncGenerator = _match([TokenType.multiply]);

            Expression methodKey;
            bool methodComputed = false;

            if (_match([TokenType.leftBracket])) {
              // Computed async method: async [expr]() {}
              methodKey = _assignmentExpression();
              _consume(
                TokenType.rightBracket,
                'Expected \']\' after computed method name',
              );
              methodComputed = true;
            } else if (_check(TokenType.identifier) ||
                _isKeywordAllowedAsMethodName()) {
              // Named async method: async foo() {}
              final methodToken = _advance();
              methodKey = IdentifierExpression(
                name: methodToken.lexeme,
                line: methodToken.line,
                column: methodToken.column,
              );
            } else if (_match([TokenType.string])) {
              // String method name: async "method"() {}
              final methodToken = _previous();
              methodKey = LiteralExpression(
                value: methodToken.literal,
                type: 'string',
                line: methodToken.line,
                column: methodToken.column,
              );
            } else if (_match([TokenType.number])) {
              // Number method name: async 42() {}
              final methodToken = _previous();
              methodKey = LiteralExpression(
                value: methodToken.literal,
                type: 'number',
                line: methodToken.line,
                column: methodToken.column,
              );
            } else if (_match([TokenType.bigint])) {
              // BigInt method name: async 123n() {}
              final methodToken = _previous();
              methodKey = LiteralExpression(
                value: methodToken.literal,
                type: 'bigint',
                line: methodToken.line,
                column: methodToken.column,
              );
            } else {
              throw ParseError('Expected async method name', _peek());
            }

            _consume(
              TokenType.leftParen,
              'Expected \'(\' after async method name',
            );

            // Parse parameters
            final oldAsyncContext = _inAsyncContext;
            final oldGeneratorContext = _inGeneratorContext;
            _inAsyncContext = true;
            if (isAsyncGenerator) _inGeneratorContext = true;

            final params = _parseFunctionParameters();

            _consume(
              TokenType.rightParen,
              'Expected \')\' after async method parameters',
            );

            final oldFunctionDepth = _functionDepth;
            _functionDepth++; // Increment for method body parsing

            final body = _blockStatement();
            _inAsyncContext = oldAsyncContext;
            _inGeneratorContext = oldGeneratorContext;
            _functionDepth = oldFunctionDepth;

            Expression functionExpr;
            if (isAsyncGenerator) {
              // Async generator method
              functionExpr = AsyncFunctionExpression(
                params: params,
                body: body,
                isGenerator: true,
                line: _previous().line,
                column: _previous().column,
              );
            } else {
              // Regular async method
              functionExpr = AsyncFunctionExpression(
                params: params,
                body: body,
                line: _previous().line,
                column: _previous().column,
              );
            }

            properties.add(
              ObjectProperty(
                key: methodKey,
                value: functionExpr,
                computed: methodComputed,
                kind: 'method',
              ),
            );
            continue;
          }
        }

        // Normal property key
        Expression key;
        bool computed = false;
        String? kind; // 'get', 'set', or null

        if (_match([TokenType.leftBracket])) {
          // Computed property [key]
          key = _assignmentExpression();
          _consume(
            TokenType.rightBracket,
            'Expected \']\' after computed property key',
          );
          computed = true;

          // Check if it's a computed method: {[key]() {}}
          if (_match([TokenType.leftParen])) {
            // Method with computed name
            final params = _parseFunctionParameters();

            _consume(TokenType.rightParen, 'Expected \')\' after parameters');
            final oldFunctionDepth = _functionDepth;
            _functionDepth++;
            final body = _blockStatement();
            _functionDepth = oldFunctionDepth;

            final functionExpr = FunctionExpression(
              id: null,
              params: params,
              body: body,
              line: start.line,
              column: start.column,
            );

            properties.add(
              ObjectProperty(
                key: key,
                value: functionExpr,
                computed: computed,
                kind: 'method',
              ),
            );
          } else {
            // Normal computed property: {[key]: value}
            _consume(TokenType.colon, 'Expected \':\' after property key');
            final value = _assignmentExpression();

            properties.add(
              ObjectProperty(
                key: key,
                value: value,
                computed: computed,
                kind: kind,
              ),
            );
          }
        } else if (_match([
          TokenType.identifier,
          // 'get' et 'set' sont maintenant des identifiers normaux
          TokenType.keywordAsync,
          TokenType.keywordFunction,
          TokenType.keywordClass,
          TokenType.keywordIf,
          TokenType.keywordElse,
          TokenType.keywordFor,
          TokenType.keywordWhile,
          TokenType.keywordDo,
          TokenType.keywordReturn,
          TokenType.keywordBreak,
          TokenType.keywordContinue,
          TokenType.keywordSwitch,
          TokenType.keywordCase,
          TokenType.keywordDefault,
          TokenType.keywordTry,
          TokenType.keywordCatch,
          TokenType.keywordFinally,
          TokenType.keywordThrow,
          TokenType.keywordNew,
          TokenType.keywordThis,
          TokenType.keywordSuper,
          TokenType.keywordVar,
          TokenType.keywordLet,
          TokenType.keywordConst,
          TokenType.keywordExtends,
          TokenType.keywordStatic,
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
          TokenType.keywordAwait,
          TokenType.keywordYield,
          TokenType.keywordExport,
          TokenType.keywordImport,
          TokenType.keywordWith,
        ])) {
          final token = _previous();
          key = IdentifierExpression(
            name: token.lexeme,
            line: token.line,
            column: token.column,
          );

          // Check if it's a shorthand method {method() {}}, shorthand {x}, default value {x = default}, or normal property {x: value}
          if (_match([TokenType.leftParen])) {
            // Shorthand method: {method() { ... }}
            final params = _parseFunctionParameters();

            _consume(TokenType.rightParen, 'Expected \')\' after parameters');
            final oldFunctionDepth = _functionDepth;
            _functionDepth++;
            final body = _blockStatement();
            _functionDepth = oldFunctionDepth;

            final functionExpr = FunctionExpression(
              id: null,
              params: params,
              body: body,
              line: token.line,
              column: token.column,
            );

            properties.add(
              ObjectProperty(
                key: key,
                value: functionExpr,
                computed: computed,
                kind: 'method',
              ),
            );
          } else if (_match([TokenType.assign])) {
            // Default value: {x = default}
            final defaultValue = _assignmentExpression();
            // For patterns, we create an expression that represents x = default
            final value = AssignmentExpression(
              left: IdentifierExpression(
                name: token.lexeme,
                line: token.line,
                column: token.column,
              ),
              operator: '=',
              right: defaultValue,
              line: token.line,
              column: token.column,
            );
            properties.add(
              ObjectProperty(
                key: key,
                value: value,
                computed: computed,
                kind: kind,
              ),
            );
          } else if (_match([TokenType.colon])) {
            // Normal property: {x: value}
            final value = _assignmentExpression();
            properties.add(
              ObjectProperty(
                key: key,
                value: value,
                computed: computed,
                kind: kind,
              ),
            );
          } else {
            // Shorthand {x} is equivalent to {x: x}
            final value = IdentifierExpression(
              name: token.lexeme,
              line: token.line,
              column: token.column,
            );
            properties.add(
              ObjectProperty(
                key: key,
                value: value,
                computed: computed,
                kind: kind,
              ),
            );
          }
        } else if (_match([TokenType.string])) {
          final token = _previous();
          key = LiteralExpression(
            value: token.literal,
            type: 'string',
            line: token.line,
            column: token.column,
          );

          // Check for method shorthand: "method"() {}
          if (_match([TokenType.leftParen])) {
            final params = _parseFunctionParameters();
            _consume(TokenType.rightParen, 'Expected \')\' after parameters');
            final oldFunctionDepth = _functionDepth;
            _functionDepth++; // Increment for method body parsing
            final body = _blockStatement();
            _functionDepth = oldFunctionDepth;

            final functionExpr = FunctionExpression(
              id: null,
              params: params,
              body: body,
              line: token.line,
              column: token.column,
            );

            properties.add(
              ObjectProperty(
                key: key,
                value: functionExpr,
                computed: computed,
                kind: 'method',
              ),
            );
          } else {
            _consume(TokenType.colon, 'Expected \':\' after property key');
            final value = _assignmentExpression();

            properties.add(
              ObjectProperty(
                key: key,
                value: value,
                computed: computed,
                kind: kind,
              ),
            );
          }
        } else if (_match([TokenType.number])) {
          // Support for numeric properties: {1: "one", 2: "two"}
          final token = _previous();
          key = LiteralExpression(
            value: token.literal,
            type: 'number',
            line: token.line,
            column: token.column,
          );

          // Check for method shorthand: 1() {}
          if (_match([TokenType.leftParen])) {
            final params = _parseFunctionParameters();
            _consume(TokenType.rightParen, 'Expected \')\' after parameters');
            final oldFunctionDepth = _functionDepth;
            _functionDepth++; // Increment for method body parsing
            final body = _blockStatement();
            _functionDepth = oldFunctionDepth;

            final functionExpr = FunctionExpression(
              id: null,
              params: params,
              body: body,
              line: token.line,
              column: token.column,
            );

            properties.add(
              ObjectProperty(
                key: key,
                value: functionExpr,
                computed: computed,
                kind: 'method',
              ),
            );
          } else {
            _consume(TokenType.colon, 'Expected \':\' after property key');
            final value = _assignmentExpression();

            properties.add(
              ObjectProperty(
                key: key,
                value: value,
                computed: computed,
                kind: kind,
              ),
            );
          }
        } else if (_match([TokenType.bigint])) {
          // Support for BigInt properties: {123n: "value"}
          final token = _previous();
          key = LiteralExpression(
            value: token.literal,
            type: 'bigint',
            line: token.line,
            column: token.column,
          );

          // Check for method shorthand: 1n() {}
          if (_match([TokenType.leftParen])) {
            final params = _parseFunctionParameters();
            _consume(TokenType.rightParen, 'Expected \')\' after parameters');
            final oldFunctionDepth = _functionDepth;
            _functionDepth++; // Increment for method body parsing
            final body = _blockStatement();
            _functionDepth = oldFunctionDepth;

            final functionExpr = FunctionExpression(
              id: null,
              params: params,
              body: body,
              line: token.line,
              column: token.column,
            );

            properties.add(
              ObjectProperty(
                key: key,
                value: functionExpr,
                computed: computed,
                kind: 'method',
              ),
            );
          } else {
            _consume(TokenType.colon, 'Expected \':\' after property key');
            final value = _assignmentExpression();

            properties.add(
              ObjectProperty(
                key: key,
                value: value,
                computed: computed,
                kind: kind,
              ),
            );
          }
        } else {
          throw ParseError('Expected property name', _peek());
        }
      } while (_match([TokenType.comma]) &&
          !_check(TokenType.rightBrace)); // Support for trailing comma
    }

    _consume(TokenType.rightBrace, 'Expected \'}\' after object properties');

    return ObjectExpression(
      properties: properties,
      line: start.line,
      column: start.column,
    );
  }

  /// Parse a function
  FunctionExpression _functionExpression() {
    final functionToken = _previous();

    // Check for generator function (function*)
    final bool isGenerator = _match([TokenType.multiply]);

    // Optional name for function expressions
    // Allow keywords as function names (e.g., yield, async, await in non-strict mode)
    IdentifierExpression? id;
    if (_check(TokenType.identifier)) {
      final nameToken = _advance();
      id = IdentifierExpression(
        name: nameToken.lexeme,
        line: nameToken.line,
        column: nameToken.column,
      );
    } else if (_check(TokenType.keywordYield) ||
        _check(TokenType.keywordAwait) ||
        _check(TokenType.keywordAsync)) {
      final nameToken = _advance();
      id = IdentifierExpression(
        name: nameToken.lexeme,
        line: nameToken.line,
        column: nameToken.column,
      );
    }

    _consume(TokenType.leftParen, 'Expected \'(\' after function keyword');

    // Parse parameters with trailing comma support (ES2017)
    final params = _parseFunctionParameters();

    _consume(TokenType.rightParen, 'Expected \')\' after parameters');

    // Validate function parameters for duplicates and reserved names
    _validateFunctionParameters(
      params,
      functionToken.line,
      functionToken.column,
    );

    // Set generator context and increment function depth for body parsing
    final oldGeneratorContext = _inGeneratorContext;
    final oldFunctionDepth = _functionDepth;
    _inGeneratorContext =
        isGenerator; // Always set to correct value for this function
    _functionDepth++;

    // Parser le corps de la fonction
    final body = _blockStatement();

    // Restore context
    _inGeneratorContext = oldGeneratorContext;
    _functionDepth = oldFunctionDepth;

    // ES6 14.1.2: Illegal to have "use strict" directive with non-simple parameters
    _validateStrictModeWithParams(
      params,
      body,
      functionToken.line,
      functionToken.column,
    );

    return FunctionExpression(
      id: id,
      params: params,
      body: body,
      line: functionToken.line,
      column: functionToken.column,
      isGenerator: isGenerator,
    );
  }

  /// Parse a function async
  AsyncFunctionExpression _asyncFunctionExpression() {
    final asyncToken = _previous(); // async has already been consumed

    // function has already been consumed as well

    // Check for async generator function (async function*)
    final bool isGenerator = _match([TokenType.multiply]);

    // Optional name for function expressions
    IdentifierExpression? id;
    if (_check(TokenType.identifier)) {
      final nameToken = _advance();
      id = IdentifierExpression(
        name: nameToken.lexeme,
        line: nameToken.line,
        column: nameToken.column,
      );
    }

    _consume(TokenType.leftParen, 'Expected \'(\' after async function');

    // Parse parameters with trailing comma support (ES2017)
    final params = _parseFunctionParameters();

    _consume(TokenType.rightParen, 'Expected \')\' after parameters');

    // Validate async function parameters - 'await' is not allowed
    _validateAsyncFunctionParameters(
      params,
      asyncToken.line,
      asyncToken.column,
    );

    // Set async/generator context and increment function depth for body parsing
    final oldAsyncContext = _inAsyncContext;
    final oldGeneratorContext = _inGeneratorContext;
    final oldFunctionDepth = _functionDepth;
    _inAsyncContext = true;
    _inGeneratorContext =
        isGenerator; // Always set to correct value for this function
    _functionDepth++;

    // Parser le corps de la fonction
    final body = _blockStatement();

    // Restore context
    _inAsyncContext = oldAsyncContext;
    _inGeneratorContext = oldGeneratorContext;
    _functionDepth = oldFunctionDepth;

    // ES6 14.1.2: Illegal to have "use strict" directive with non-simple parameters
    _validateStrictModeWithParams(
      params,
      body,
      asyncToken.line,
      asyncToken.column,
    );

    return AsyncFunctionExpression(
      id: id,
      params: params,
      body: body,
      line: asyncToken.line,
      column: asyncToken.column,
      isGenerator: isGenerator,
    );
  }

  /// Parse a function declaration
  FunctionDeclaration _functionDeclaration() {
    final functionToken = _previous();

    // Check if it's a generator function (function*)
    final bool isGenerator = _match([TokenType.multiply]);

    // Mandatory name for function declarations
    // Allow keywords as function names (e.g., yield, async, await in non-strict mode)
    Token nameToken;
    if (_check(TokenType.identifier)) {
      nameToken = _advance();
    } else if (_check(TokenType.keywordYield) ||
        _check(TokenType.keywordAwait) ||
        _check(TokenType.keywordAsync)) {
      nameToken = _advance();
    } else {
      throw ParseError('Expected function name', _peek());
    }

    // Validate function name in strict mode
    if (_isInStrictMode()) {
      if (nameToken.lexeme == 'eval' || nameToken.lexeme == 'arguments') {
        throw ParseError(
          'The identifier \'${nameToken.lexeme}\' cannot be used as a function name in strict mode',
          nameToken,
        );
      }
    }

    final id = IdentifierExpression(
      name: nameToken.lexeme,
      line: nameToken.line,
      column: nameToken.column,
    );

    _consume(TokenType.leftParen, 'Expected \'(\' after function name');

    // Parse parameters with trailing comma support (ES2017)
    final params = _parseFunctionParameters();

    _consume(TokenType.rightParen, 'Expected \')\' after parameters');

    // Validate function parameters for duplicates and reserved names
    _validateFunctionParameters(
      params,
      functionToken.line,
      functionToken.column,
    );

    // Set generator context and increment function depth for body parsing
    final oldGeneratorContext = _inGeneratorContext;
    final oldFunctionDepth = _functionDepth;
    _inGeneratorContext =
        isGenerator; // Always set to correct value for this function
    _functionDepth++;

    // Parser le corps de la fonction
    final body = _blockStatement();

    // Restore context
    _inGeneratorContext = oldGeneratorContext;
    _functionDepth = oldFunctionDepth;

    // ES6 14.1.2: Illegal to have "use strict" directive with non-simple parameters
    _validateStrictModeWithParams(
      params,
      body,
      functionToken.line,
      functionToken.column,
    );

    return FunctionDeclaration(
      id: id,
      params: params,
      body: body,
      line: functionToken.line,
      column: functionToken.column,
      isGenerator: isGenerator,
    );
  }

  /// Parse an async function declaration
  AsyncFunctionDeclaration _asyncFunctionDeclaration() {
    final asyncToken =
        _previous(); // The 'async' token has already been consumed

    // Consume 'function'
    _consume(
      TokenType.keywordFunction,
      'Expected \'function\' after \'async\'',
    );

    // Check for async generator function (async function*)
    final bool isGenerator = _match([TokenType.multiply]);

    // Mandatory name for function declarations
    // Allow keywords as function names (e.g., yield, async, await in non-strict mode)
    Token nameToken;
    if (_check(TokenType.identifier)) {
      nameToken = _advance();
    } else if (_check(TokenType.keywordYield) ||
        _check(TokenType.keywordAwait) ||
        _check(TokenType.keywordAsync)) {
      nameToken = _advance();
    } else {
      throw ParseError('Expected function name', _peek());
    }

    // Validate function name in strict mode
    if (_isInStrictMode()) {
      if (nameToken.lexeme == 'eval' || nameToken.lexeme == 'arguments') {
        throw ParseError(
          'The identifier \'${nameToken.lexeme}\' cannot be used as a function name in strict mode',
          nameToken,
        );
      }
    }

    final id = IdentifierExpression(
      name: nameToken.lexeme,
      line: nameToken.line,
      column: nameToken.column,
    );

    _consume(TokenType.leftParen, 'Expected \'(\' after function name');

    // Parse parameters with trailing comma support (ES2017)
    final params = _parseFunctionParameters();

    _consume(TokenType.rightParen, 'Expected \')\' after parameters');

    // Validate async function parameters - 'await' is not allowed
    _validateAsyncFunctionParameters(
      params,
      asyncToken.line,
      asyncToken.column,
    );

    // Set async/generator context and increment function depth for body parsing
    final oldAsyncContext = _inAsyncContext;
    final oldGeneratorContext = _inGeneratorContext;
    final oldFunctionDepth = _functionDepth;
    _inAsyncContext = true;
    _inGeneratorContext =
        isGenerator; // Always set to correct value for this function
    _functionDepth++;

    // Parser le corps de la fonction
    final body = _blockStatement();

    // Restore context
    _inAsyncContext = oldAsyncContext;
    _inGeneratorContext = oldGeneratorContext;
    _functionDepth = oldFunctionDepth;

    // ES6 14.1.2: Illegal to have "use strict" directive with non-simple parameters
    _validateStrictModeWithParams(
      params,
      body,
      asyncToken.line,
      asyncToken.column,
    );

    return AsyncFunctionDeclaration(
      id: id,
      params: params,
      body: body,
      line: asyncToken.line,
      column: asyncToken.column,
      isGenerator: isGenerator,
    );
  }

  // ===== UTILITIES =====

  /// Check if we've reached the end of tokens
  bool _isAtEnd() => _peek().type == TokenType.eof;

  /// Return the current token sans l'avancer
  Token _peek() => tokens[_current];

  /// Return the next token sans l'avancer
  Token? _peekNext() =>
      _current + 1 < tokens.length ? tokens[_current + 1] : null;

  /// Check if a token type can be an identifier (keywords used as names)
  bool _isKeywordThatCanBeIdentifier(TokenType type) {
    return type == TokenType.identifier ||
        type == TokenType.keywordYield ||
        type == TokenType.keywordAwait ||
        type == TokenType.keywordLet ||
        type == TokenType.keywordAsync;
  }

  /// Return the previous token
  Token _previous() => tokens[_current - 1];

  /// Check if the current token is of a given type
  bool _check(TokenType type) {
    if (_isAtEnd()) return false;
    return _peek().type == type;
  }

  /// Check if the current token is a contextual keyword that can be an arrow parameter
  bool _checkContextualKeywordForArrowParam() {
    if (_isAtEnd()) return false;
    final type = _peek().type;
    // Keywords that can be used as arrow parameters
    return type == TokenType.keywordOf ||
        type == TokenType.keywordIn ||
        type == TokenType.keywordLet ||
        type == TokenType.keywordStatic ||
        type == TokenType.keywordGet ||
        type == TokenType.keywordSet ||
        type == TokenType.keywordYield ||
        type == TokenType.keywordAwait;
  }

  /// Check if the current token is a contextual keyword
  bool _checkContextualKeyword() {
    if (_isAtEnd()) return false;
    final type = _peek().type;
    // Contextual keywords that can be used as identifiers
    return type == TokenType.keywordLet ||
        type == TokenType.keywordAsync ||
        type == TokenType.keywordStatic ||
        type == TokenType.keywordGet ||
        type == TokenType.keywordSet ||
        type == TokenType.keywordOf ||
        type == TokenType.keywordIn;
  }

  /// Parse an identifier or keyword to be used as an export/import name
  /// In export/import contexts, any keyword can be used as a name
  Token _parseIdentifierOrKeyword() {
    if (_check(TokenType.identifier)) {
      return _advance();
    }

    // In export/import contexts, allow keywords as names
    final token = _peek();
    if (token.type.toString().startsWith('TokenType.keyword')) {
      _advance();
      return token;
    }

    throw ParseError('Expected identifier', token);
  }

  /// Check the type of a token at a relative position
  bool _checkAhead(TokenType type, int offset) {
    final index = _current + offset;
    if (index >= tokens.length) return false;
    return tokens[index].type == type;
  }

  /// Advance and return le token courant
  Token _advance() {
    if (!_isAtEnd()) _current++;
    return _previous();
  }

  /// Check if the current token corresponds to one of the types and advance if so
  bool _match(List<TokenType> types) {
    for (final type in types) {
      if (_check(type)) {
        _advance();
        return true;
      }
    }
    return false;
  }

  /// Check if the current token is an identifier with the given lexeme
  bool _matchIdentifier(String lexeme) {
    if (_check(TokenType.identifier) && _peek().lexeme == lexeme) {
      _advance();
      return true;
    }
    return false;
  }

  /// Consume an identifier with the given lexeme or raise an error
  Token _consumeIdentifier(String lexeme, String message) {
    if (_check(TokenType.identifier) && _peek().lexeme == lexeme) {
      return _advance();
    }
    throw ParseError(message, _peek());
  }

  /// Check if the current token est l'identifiant 'get'
  bool _checkGet() {
    return _check(TokenType.identifier) && _peek().lexeme == 'get';
  }

  /// Check if the current token est l'identifiant 'set'
  bool _checkSet() {
    return _check(TokenType.identifier) && _peek().lexeme == 'set';
  }

  /// Consume a token of the expected type or raise an error
  Token _consume(TokenType type, String message) {
    if (_check(type)) return _advance();
    throw ParseError(message, _peek());
  }

  /// Automatic Semicolon Insertion (ASI)
  /// Check if a semicolon can be automatically inserted
  bool _canInsertSemicolon() {
    // 1. At the end of the file
    if (_isAtEnd()) return true;

    // 2. Before a closing brace
    if (_check(TokenType.rightBrace)) return true;

    // 3. If the next token est sur une nouvelle ligne
    final current = _peek();
    final previous = _previous();
    if (current.line > previous.line) {
      // BUT don't insert if the next line starts with a dot (chaining)
      // or other tokens that continue the expression
      if (_check(TokenType.dot) ||
          _check(TokenType.leftBracket) ||
          _check(TokenType.leftParen)) {
        return false; // No ASI, it's a continuation
      }
      return true;
    }

    return false;
  }

  /// Consume a semicolon ou utilise l'ASI
  void _consumeSemicolonOrASI(String message) {
    if (_match([TokenType.semicolon])) {
      return; // Explicit semicolon found
    }

    if (_canInsertSemicolon()) {
      return; // ASI applied
    }

    throw ParseError(message, _peek());
  }

  /// Consume semicolon or apply ASI with special handling for do-while
  /// After ) of do-while condition, ASI applies even on same line if next token
  /// would be an "offending token" (e.g., start of new statement)
  void _consumeDoWhileSemicolon(String message) {
    if (_match([TokenType.semicolon])) {
      return; // Explicit semicolon found
    }

    if (_canInsertSemicolon()) {
      return; // Standard ASI applies
    }

    // Special do-while ASI: if next token is an offending token that can't
    // follow ) without a semicolon, apply ASI
    // Offending tokens include: identifiers, keywords that start statements, etc.
    final nextToken = _peek();

    // These tokens can legitimately follow ) in an expression context
    // So they don't trigger ASI
    final continuationTokens = {
      TokenType.leftParen, // Function call
      TokenType.leftBracket, // Array access
      TokenType.dot, // Property access
      TokenType.question, // Optional chaining / ternary
      TokenType.increment, // Postfix ++
      TokenType.decrement, // Postfix --
    };

    if (!continuationTokens.contains(nextToken.type)) {
      // This token breaks the expression, so ASI applies
      return;
    }

    throw ParseError(message, _peek());
  }

  /// Parse an arrow from already parsed parameters
  ArrowFunctionExpression _parseArrowFunction(Expression params) {
    final token = _advance(); // Consomme '=>'

    List<Parameter> parameters = [];

    // Convert the parameter expression into a Parameter list
    if (params is IdentifierExpression) {
      // Simple case: param => expr
      parameters.add(Parameter(nameOrPattern: params));
    } else {
      // Handle (param1, param2) => expr
      parameters = _extractParametersFromExpression(params);
    }

    // Increment function depth for body parsing
    final oldFunctionDepth = _functionDepth;
    _functionDepth++;

    // Parser le body de la fonction
    dynamic body;
    bool isExpression = true;

    if (_check(TokenType.leftBrace)) {
      // Arrow function avec block: () => { statements }
      isExpression = false;
      body = _blockStatement();

      // ES6: Validate strict mode + non-simple parameters
      if (body is BlockStatement) {
        _validateStrictModeWithParams(
          parameters,
          body,
          token.line,
          token.column,
        );
      }
    } else {
      // Arrow function avec expression: () => expression
      body = _assignment();
    }

    // Restore context
    _functionDepth = oldFunctionDepth;

    return ArrowFunctionExpression(
      params: parameters,
      body: body,
      isExpression: isExpression,
      line: token.line,
      column: token.column,
    );
  }

  /// Parse an async arrow from already parsed parameters
  AsyncArrowFunctionExpression _parseAsyncArrowFunction(
    Expression params,
    Token asyncToken,
  ) {
    _advance(); // Consomme '=>'

    List<Parameter> parameters = [];

    // Convert the parameter expression into a Parameter list
    if (params is IdentifierExpression) {
      // Simple case: async param => expr
      parameters.add(Parameter(nameOrPattern: params));
    } else {
      // Handle async (param1, param2) => expr
      parameters = _extractParametersFromExpression(params);
    }

    // Early error validation for async arrow function parameters
    // Check for duplicates, 'await' as param, 'arguments'/'eval' in strict mode
    final isStrict = _isInStrictMode();
    _validateAsyncArrowParameters(
      parameters,
      asyncToken.line,
      asyncToken.column,
      isStrict,
    );

    // Validate no 'await' expressions in default values
    _validateNoAwaitInDefaults(parameters, asyncToken.line, asyncToken.column);

    // Set async context and increment function depth for body parsing
    final oldAsyncContext = _inAsyncContext;
    final oldFunctionDepth = _functionDepth;
    _inAsyncContext = true;
    _functionDepth++;

    // Parser le body de la fonction
    dynamic body;
    bool isExpression = true;

    if (_check(TokenType.leftBrace)) {
      // Async arrow function avec block: async () => { statements }
      isExpression = false;
      body = _blockStatement();

      // ES6: Validate strict mode + non-simple parameters
      if (body is BlockStatement) {
        _validateStrictModeWithParams(
          parameters,
          body,
          asyncToken.line,
          asyncToken.column,
        );

        // Validate params don't conflict with let/const in body
        _validateParamsVsLexicalDeclarations(
          parameters,
          body,
          asyncToken.line,
          asyncToken.column,
        );

        // ES6: Arrow functions cannot have super() call outside of class methods
        if (!_inClassContext && _containsSuperCall(body)) {
          throw LexerError(
            'SyntaxError: \'super\' keyword unexpected here',
            asyncToken.line,
            asyncToken.column,
          );
        }

        // ES6: Arrow functions cannot have super.property outside of class methods
        if (!_inClassContext && _containsSuperProperty(body)) {
          throw LexerError(
            'SyntaxError: \'super\' keyword unexpected here',
            asyncToken.line,
            asyncToken.column,
          );
        }
      }
    } else {
      // Async arrow function avec expression: async () => expression
      body = _assignment();

      // ES6: Check super in expression body
      if (!_inClassContext && _containsSuperCall(body)) {
        throw LexerError(
          'SyntaxError: \'super\' keyword unexpected here',
          asyncToken.line,
          asyncToken.column,
        );
      }
      if (!_inClassContext && _containsSuperProperty(body)) {
        throw LexerError(
          'SyntaxError: \'super\' keyword unexpected here',
          asyncToken.line,
          asyncToken.column,
        );
      }
    }

    // Also check super in parameter default values
    for (final param in parameters) {
      if (param.defaultValue != null) {
        if (!_inClassContext && _containsSuperCall(param.defaultValue!)) {
          throw LexerError(
            'SyntaxError: \'super\' keyword unexpected here',
            asyncToken.line,
            asyncToken.column,
          );
        }
        if (!_inClassContext && _containsSuperProperty(param.defaultValue!)) {
          throw LexerError(
            'SyntaxError: \'super\' keyword unexpected here',
            asyncToken.line,
            asyncToken.column,
          );
        }
      }
    }

    // Restore context
    _inAsyncContext = oldAsyncContext;
    _functionDepth = oldFunctionDepth;

    return AsyncArrowFunctionExpression(
      params: parameters,
      body: body,
      isExpression: isExpression,
      line: asyncToken.line,
      column: asyncToken.column,
    );
  }

  /// Extract a list of parameters from an expression
  List<Parameter> _extractParametersFromExpression(Expression expr) {
    final parameters = <Parameter>[];

    if (expr is IdentifierExpression) {
      // Single parameter
      parameters.add(Parameter(nameOrPattern: expr));
    } else if (expr is DestructuringAssignmentExpression) {
      // Destructuring with default value: ({a} = {}) => or ([a] = []) =>
      parameters.add(
        Parameter(nameOrPattern: expr.left, defaultValue: expr.right),
      );
    } else if (expr is AssignmentExpression) {
      // Parameter with default value: (a = 10) => or ({x} = {}) => or ([a] = []) =>
      if (expr.left is IdentifierExpression) {
        parameters.add(
          Parameter(
            nameOrPattern: expr.left as IdentifierExpression,
            defaultValue: expr.right,
          ),
        );
      } else if (expr.left is ArrayExpression) {
        // Destructuring with default: ([a, b] = []) =>
        final pattern = _convertArrayExpressionToPattern(
          expr.left as ArrayExpression,
        );
        parameters.add(
          Parameter(nameOrPattern: pattern, defaultValue: expr.right),
        );
      } else if (expr.left is ObjectExpression) {
        // Destructuring with default: ({x, y} = {}) =>
        final pattern = _convertObjectExpressionToPattern(
          expr.left as ObjectExpression,
        );
        parameters.add(
          Parameter(nameOrPattern: pattern, defaultValue: expr.right),
        );
      } else {
        throw ParseError(
          'Invalid default parameter in arrow function',
          _peek(),
        );
      }
    } else if (expr is ArrayExpression) {
      // Destructuration array: ([a, b]) => ou ([a, b], c) =>
      // Convert ArrayExpression to ArrayPattern
      final pattern = _convertArrayExpressionToPattern(expr);
      parameters.add(Parameter(nameOrPattern: pattern));
    } else if (expr is ObjectExpression) {
      // Destructuration object: ({a, b}) => ou ({a, b}, c) =>
      // Convert ObjectExpression to ObjectPattern
      final pattern = _convertObjectExpressionToPattern(expr);
      parameters.add(Parameter(nameOrPattern: pattern));
    } else if (expr is SpreadElement) {
      // Rest parameter: (...rest) => or (...[a, b]) =>
      if (expr.argument is IdentifierExpression) {
        parameters.add(
          Parameter(
            nameOrPattern: expr.argument as IdentifierExpression,
            isRest: true,
          ),
        );
      } else if (expr.argument is ArrayExpression) {
        // Destructuring rest: (...[a, b]) =>
        final pattern = _convertArrayExpressionToPattern(
          expr.argument as ArrayExpression,
        );
        parameters.add(Parameter(nameOrPattern: pattern, isRest: true));
      } else if (expr.argument is ObjectExpression) {
        // Destructuring rest: (...{a, b}) =>
        final pattern = _convertObjectExpressionToPattern(
          expr.argument as ObjectExpression,
        );
        parameters.add(Parameter(nameOrPattern: pattern, isRest: true));
      } else {
        throw ParseError('Invalid rest parameter in arrow function', _peek());
      }
    } else if (expr is SequenceExpression) {
      // Sequence expression (a, b, c) or empty for ()
      for (final subExpr in expr.expressions) {
        if (subExpr is IdentifierExpression) {
          parameters.add(Parameter(nameOrPattern: subExpr));
        } else if (subExpr is AssignmentExpression) {
          // Parameter with default value: (a, b = 10) => or (a = 5, b = a + 1) =>
          if (subExpr.left is IdentifierExpression) {
            parameters.add(
              Parameter(
                nameOrPattern: subExpr.left as IdentifierExpression,
                defaultValue: subExpr.right,
              ),
            );
          } else {
            throw ParseError(
              'Invalid default parameter in arrow function',
              _peek(),
            );
          }
        } else if (subExpr is ArrayExpression) {
          // Array destructuring in sequence: (a, [b, c]) =>
          final pattern = _convertArrayExpressionToPattern(subExpr);
          parameters.add(Parameter(nameOrPattern: pattern));
        } else if (subExpr is ObjectExpression) {
          // Object destructuring in sequence: (a, {b, c}) =>
          final pattern = _convertObjectExpressionToPattern(subExpr);
          parameters.add(Parameter(nameOrPattern: pattern));
        } else if (subExpr is SpreadElement) {
          // Rest parameter in a sequence: (a, b, ...rest) => or (a, ...[x, y]) =>
          if (subExpr.argument is IdentifierExpression) {
            parameters.add(
              Parameter(
                nameOrPattern: subExpr.argument as IdentifierExpression,
                isRest: true,
              ),
            );
          } else if (subExpr.argument is ArrayExpression) {
            // Destructuring rest: (a, ...[b, c]) =>
            final pattern = _convertArrayExpressionToPattern(
              subExpr.argument as ArrayExpression,
            );
            parameters.add(Parameter(nameOrPattern: pattern, isRest: true));
          } else if (subExpr.argument is ObjectExpression) {
            // Destructuring rest: (a, ...{b, c}) =>
            final pattern = _convertObjectExpressionToPattern(
              subExpr.argument as ObjectExpression,
            );
            parameters.add(Parameter(nameOrPattern: pattern, isRest: true));
          } else {
            throw ParseError(
              'Invalid rest parameter in arrow function',
              _peek(),
            );
          }
        } else {
          throw ParseError('Invalid parameter in arrow function', _peek());
        }
      }
      // If expressions is empty, return an empty list (case () =>)
    } else {
      throw ParseError('Invalid arrow function parameters', _peek());
    }

    return parameters;
  }

  /// Convert an ArrayExpression to ArrayPattern for destructuring
  ArrayPattern _convertArrayExpressionToPattern(ArrayExpression expr) {
    final elements = <Pattern?>[];
    Pattern? restElement;

    for (int i = 0; i < expr.elements.length; i++) {
      final element = expr.elements[i];

      if (element == null) {
        // Ignored element: [a, , c]
        elements.add(null);
      } else if (element is SpreadElement) {
        // Rest element: [...rest] or [...[a, b]] or ...{x}
        if (element.argument is IdentifierExpression) {
          restElement = IdentifierPattern(
            name: (element.argument as IdentifierExpression).name,
            line: element.line,
            column: element.column,
          );
        } else if (element.argument is ArrayExpression) {
          // Rest with nested array pattern: [...[a, b]]
          restElement = _convertArrayExpressionToPattern(
            element.argument as ArrayExpression,
          );
        } else if (element.argument is ObjectExpression) {
          // Rest with object pattern: ...{x}
          restElement = _convertObjectExpressionToPattern(
            element.argument as ObjectExpression,
          );
        } else {
          throw ParseError(
            'Invalid rest element in array destructuring',
            _peek(),
          );
        }
      } else if (element is IdentifierExpression) {
        elements.add(
          IdentifierPattern(
            name: element.name,
            line: element.line,
            column: element.column,
          ),
        );
      } else if (element is AssignmentExpression) {
        // Element with default value: [a = 10] or [__ = expr]
        if (element.left is IdentifierExpression) {
          elements.add(
            AssignmentPattern(
              left: IdentifierPattern(
                name: (element.left as IdentifierExpression).name,
                line: element.line,
                column: element.column,
              ),
              right: element.right,
              line: element.line,
              column: element.column,
            ),
          );
        } else if (element.left is ArrayExpression) {
          elements.add(
            AssignmentPattern(
              left: _convertArrayExpressionToPattern(
                element.left as ArrayExpression,
              ),
              right: element.right,
              line: element.line,
              column: element.column,
            ),
          );
        } else if (element.left is ObjectExpression) {
          elements.add(
            AssignmentPattern(
              left: _convertObjectExpressionToPattern(
                element.left as ObjectExpression,
              ),
              right: element.right,
              line: element.line,
              column: element.column,
            ),
          );
        } else {
          throw ParseError(
            'Invalid element with default value in array destructuring',
            _peek(),
          );
        }
      } else if (element is DestructuringAssignmentExpression) {
        // Destructuring assignment in array pattern: [[a] = []] =>
        // The left side is already a Pattern, not an Expression
        elements.add(
          AssignmentPattern(
            left: element.left,
            right: element.right,
            line: element.line,
            column: element.column,
          ),
        );
      } else if (element is ArrayExpression) {
        // Nested array destructuring: [[a, b], c]
        elements.add(_convertArrayExpressionToPattern(element));
      } else if (element is ObjectExpression) {
        // Nested object destructuring: [{a, b}, c]
        elements.add(_convertObjectExpressionToPattern(element));
      } else {
        throw ParseError(
          'Invalid element in array destructuring (got ${element.runtimeType})',
          _peek(),
        );
      }
    }

    return ArrayPattern(
      elements: elements,
      restElement: restElement,
      line: expr.line,
      column: expr.column,
    );
  }

  /// Convert an ObjectExpression to ObjectPattern for destructuring
  ObjectPattern _convertObjectExpressionToPattern(ObjectExpression expr) {
    final properties = <ObjectPatternProperty>[];
    Pattern? restElement;

    for (final prop in expr.properties) {
      if (prop is ObjectProperty) {
        final key = prop.key;
        final value = prop.value;

        String keyName;
        if (key is IdentifierExpression) {
          keyName = key.name;
        } else if (key is LiteralExpression) {
          keyName = key.value.toString();
        } else if (key is CallExpression || key is MemberExpression) {
          // Computed property keys: {[expr]: pattern}
          // Use a placeholder since the key will be evaluated at runtime
          keyName = '[computed]';
        } else {
          throw ParseError('Invalid property key in destructuring', _peek());
        }

        Pattern valuePattern;
        // Detect shorthand: {x} where key and value are the same identifier
        bool isShorthand = false;

        if (value is IdentifierExpression) {
          valuePattern = IdentifierPattern(
            name: value.name,
            line: value.line,
            column: value.column,
          );

          // Shorthand detection: key is IdentifierExpression with same name as value
          if (key is IdentifierExpression && key.name == value.name) {
            isShorthand = true;
          }
        } else if (value is ArrayExpression) {
          valuePattern = _convertArrayExpressionToPattern(value);
        } else if (value is ObjectExpression) {
          valuePattern = _convertObjectExpressionToPattern(value);
        } else if (value is AssignmentExpression) {
          // Handle default values: {x = 10}, {w: {x, y} = defaultValue}, {w: [a, b] = defaultValue}
          final assignment = value;

          if (assignment.left is IdentifierExpression) {
            // Simple default: {x = 10}
            final identifier = assignment.left as IdentifierExpression;
            final identifierPattern = IdentifierPattern(
              name: identifier.name,
              line: identifier.line,
              column: identifier.column,
            );

            valuePattern = AssignmentPattern(
              left: identifierPattern,
              right: assignment.right,
              line: assignment.line,
              column: assignment.column,
            );

            // Shorthand with default: {x = 10} where key and left side match
            if (key is IdentifierExpression && key.name == identifier.name) {
              isShorthand = true;
            }
          } else if (assignment.left is ObjectExpression) {
            // Nested object with default: {w: {x, y} = defaultValue}
            final objectPattern = _convertObjectExpressionToPattern(
              assignment.left as ObjectExpression,
            );
            valuePattern = AssignmentPattern(
              left: objectPattern,
              right: assignment.right,
              line: assignment.line,
              column: assignment.column,
            );
          } else if (assignment.left is ArrayExpression) {
            // Nested array with default: {w: [a, b] = defaultValue}
            final arrayPattern = _convertArrayExpressionToPattern(
              assignment.left as ArrayExpression,
            );
            valuePattern = AssignmentPattern(
              left: arrayPattern,
              right: assignment.right,
              line: assignment.line,
              column: assignment.column,
            );
          } else {
            throw ParseError(
              'Invalid assignment in object destructuring',
              _peek(),
            );
          }
        } else if (value is DestructuringAssignmentExpression) {
          // Handle nested destructuring with default: {w: {x, y} = defaultValue}
          // DestructuringAssignmentExpression.left is already a Pattern
          valuePattern = AssignmentPattern(
            left: value.left,
            right: value.right,
            line: value.line,
            column: value.column,
          );
        } else {
          throw ParseError(
            'Invalid property value in object destructuring',
            _peek(),
          );
        }

        properties.add(
          ObjectPatternProperty(
            key: keyName,
            value: valuePattern,
            shorthand: isShorthand,
            line: prop.key.line,
            column: prop.key.column,
          ),
        );
      } else if (prop is SpreadElement) {
        // Rest element: {...rest}
        if (prop.argument is IdentifierExpression) {
          restElement = IdentifierPattern(
            name: (prop.argument as IdentifierExpression).name,
            line: prop.line,
            column: prop.column,
          );
        } else {
          throw ParseError(
            'Invalid rest element in object destructuring',
            _peek(),
          );
        }
      }
    }

    return ObjectPattern(
      properties: properties,
      restElement: restElement,
      line: expr.line,
      column: expr.column,
    );
  }

  /// Parse a template literal avec interpolation
  Expression _parseTemplateLiteralWithInterpolation(
    String content,
    Token token,
  ) {
    final quasis = <String>[];
    final expressions = <Expression>[];

    int start = 0;
    while (start < content.length) {
      final interpolationStart = content.indexOf('\${', start);

      if (interpolationStart == -1) {
        // No interpolation found, add the rest
        quasis.add(content.substring(start));
        break;
      }

      // Add the part before the interpolation
      quasis.add(content.substring(start, interpolationStart));

      // Trouver la fin de l'interpolation
      // We must handle nested templates, strings, and regex to correctly count braces
      int braceCount = 1;
      int pos = interpolationStart + 2; // After ${

      while (pos < content.length && braceCount > 0) {
        final char = content[pos];

        // Skip strings (simple et double quotes)
        if (char == '"' || char == "'") {
          final quote = char;
          pos++;
          while (pos < content.length) {
            if (content[pos] == '\\') {
              pos += 2; // Skip escaped character
              continue;
            }
            if (content[pos] == quote) {
              pos++;
              break;
            }
            pos++;
          }
          continue;
        }

        // Skip nested template literals
        if (char == '`') {
          pos++;
          // Track depth: each ${ inside increases, each } decreases, and ` ends it
          int nestedBraceDepth = 0;
          while (pos < content.length) {
            if (content[pos] == '\\') {
              pos += 2; // Skip escaped character
              continue;
            }

            // Check for ${ which starts interpolation inside nested template
            if (pos + 1 < content.length &&
                content[pos] == '\$' &&
                content[pos + 1] == '{') {
              nestedBraceDepth++;
              pos += 2; // Skip ${
              continue;
            }

            // Check for } which ends interpolation inside nested template
            if (content[pos] == '}' && nestedBraceDepth > 0) {
              nestedBraceDepth--;
              pos++;
              continue;
            }

            // Check for ` which ends the nested template (only if not in interpolation)
            if (content[pos] == '`' && nestedBraceDepth == 0) {
              pos++; // Consume closing `
              break;
            }

            pos++;
          }
          continue;
        }

        // Skip regex literals (basic detection: /.../)
        if (char == '/' && pos > interpolationStart + 2) {
          // Very simple regex detection - could be improved
          final prevChar = pos > 0 ? content[pos - 1] : '';
          if (prevChar == '=' ||
              prevChar == '(' ||
              prevChar == ',' ||
              prevChar == ';' ||
              prevChar == '{' ||
              prevChar == '[') {
            pos++;
            while (pos < content.length) {
              if (content[pos] == '\\') {
                pos += 2;
                continue;
              }
              if (content[pos] == '/') {
                pos++;
                break;
              }
              pos++;
            }
            continue;
          }
        }

        // Count braces
        if (char == '{') {
          braceCount++;
        } else if (char == '}') {
          braceCount--;
        }
        pos++;
      }

      if (braceCount > 0) {
        throw ParseError('Unterminated template interpolation', token);
      }

      // Extraire l'expression
      final expressionCode = content.substring(interpolationStart + 2, pos - 1);

      // Parser l'expression
      try {
        final expression = JSParser.parseExpression(expressionCode);
        expressions.add(expression);
      } catch (e) {
        throw ParseError(
          'Invalid expression in template interpolation: $expressionCode',
          token,
        );
      }

      start = pos;
    }

    return TemplateLiteralExpression(
      quasis: quasis,
      expressions: expressions,
      line: token.line,
      column: token.column,
    );
  }

  /// Parse a class
  /// Parse a class expression: class { ... } or class Name { ... }
  ClassExpression _classExpression() {
    final classToken = _previous();

    // Class name is optional in expressions
    IdentifierExpression? className;
    // Allow 'await' as a contextual keyword in class names (but not in module context)
    // But NOT 'yield' since classes are always strict mode
    if (_check(TokenType.identifier) || _check(TokenType.keywordAwait)) {
      final id = _advance();

      // Check for reserved words that are never allowed as class names
      final forbiddenAsClassName = {
        'let',
        'static',
        'implements',
        'interface',
        'package',
        'private',
        'protected',
        'public',
        'yield', // Not allowed in strict mode (and classes are strict)
      };

      if (forbiddenAsClassName.contains(id.lexeme)) {
        throw ParseError(
          'SyntaxError: The keyword \'${id.lexeme}\' is not allowed as a class name',
          id,
        );
      }

      className = IdentifierExpression(
        name: id.lexeme,
        line: id.line,
        column: id.column,
      );
    }

    // Clause extends optionnelle
    Expression? superClass;
    if (_match([TokenType.keywordExtends])) {
      // Parse a complete expression to support dynamic extends
      // like: class extends Mixin(Base) or class extends getBaseClass()
      superClass = _primary();

      // If it's a function call, parse the arguments
      while (_match([TokenType.leftParen])) {
        final arguments = <Expression>[];

        if (!_check(TokenType.rightParen)) {
          do {
            if (_match([TokenType.spread])) {
              final spreadStart = _previous();
              final argument = _assignmentExpression();
              arguments.add(
                SpreadElement(
                  argument: argument,
                  line: spreadStart.line,
                  column: spreadStart.column,
                ),
              );
            } else {
              arguments.add(_assignmentExpression());
            }
          } while (_match([TokenType.comma]));
        }

        _consume(TokenType.rightParen, 'Expected \')\' after arguments');

        superClass = CallExpression(
          callee: superClass!,
          arguments: arguments,
          line: superClass.line,
          column: superClass.column,
        );
      }
    } // Corps de la classe
    _consume(TokenType.leftBrace, 'Expected \'{\' before class body');

    final members = <ClassMember>[];

    while (!_check(TokenType.rightBrace) && !_isAtEnd()) {
      final member = _parseClassMember();
      members.add(member);
    }

    _consume(TokenType.rightBrace, 'Expected \'}\' after class body');

    final classBody = ClassBody(
      members: members,
      line: classToken.line,
      column: classToken.column,
    );

    // Return a ClassExpression node (can be used as an expression)
    return ClassExpression(
      id: className,
      superClass: superClass,
      body: classBody,
      line: classToken.line,
      column: classToken.column,
    );
  }

  ClassDeclaration _classDeclaration() {
    final classToken = _previous();

    // Nom de la classe
    // Allow 'await' as a contextual keyword in class names (but not in module context)
    // But NOT 'yield' since classes are always strict mode
    if (!(_check(TokenType.identifier) || _check(TokenType.keywordAwait))) {
      throw ParseError('SyntaxError: Expected class name', _peek());
    }

    final id = _advance();

    // Check for reserved words that are never allowed as class names in strict mode
    final forbiddenAsClassName = {
      'let',
      'static',
      'implements',
      'interface',
      'package',
      'private',
      'protected',
      'public',
      'yield', // Not allowed in strict mode (and classes are strict)
    };

    if (forbiddenAsClassName.contains(id.lexeme)) {
      throw ParseError(
        'SyntaxError: The keyword \'${id.lexeme}\' is not allowed as a class name',
        id,
      );
    }

    final className = IdentifierExpression(
      name: id.lexeme,
      line: id.line,
      column: id.column,
    );

    // Save and set strict mode context for class parsing
    final previousInClassContext = _inClassContext;
    _inClassContext = true;

    try {
      // Clause extends optionnelle
      Expression? superClass;
      if (_match([TokenType.keywordExtends])) {
        // Parse a complete expression to support dynamic extends
        // comme: class extends Mixin(Base) ou class extends getBaseClass()
        // or class extends module.ClassName for module exports
        superClass = _memberAccess();

        // If it's a function call, parse the arguments
        while (_match([TokenType.leftParen])) {
          final arguments = <Expression>[];

          if (!_check(TokenType.rightParen)) {
            do {
              if (_match([TokenType.spread])) {
                final spreadStart = _previous();
                final argument = _assignmentExpression();
                arguments.add(
                  SpreadElement(
                    argument: argument,
                    line: spreadStart.line,
                    column: spreadStart.column,
                  ),
                );
              } else {
                arguments.add(_assignmentExpression());
              }
            } while (_match([TokenType.comma]));
          }

          _consume(TokenType.rightParen, 'Expected \')\' after arguments');

          superClass = CallExpression(
            callee: superClass!,
            arguments: arguments,
            line: superClass.line,
            column: superClass.column,
          );
        }
      }

      // Corps de la classe
      _consume(TokenType.leftBrace, 'Expected \'{\' before class body');

      final members = <ClassMember>[];

      while (!_check(TokenType.rightBrace) && !_isAtEnd()) {
        final member = _parseClassMember();
        members.add(member);
      }

      _consume(TokenType.rightBrace, 'Expected \'}\' after class body');

      final classBody = ClassBody(
        members: members,
        line: classToken.line,
        column: classToken.column,
      );

      return ClassDeclaration(
        id: className,
        superClass: superClass,
        body: classBody,
        line: classToken.line,
        column: classToken.column,
      );
    } finally {
      _inClassContext = previousInClassContext;
    }
  }

  /// Parse a class member (method, field, static block)
  ClassMember _parseClassMember() {
    final startToken = _peek();

    // Handle empty semicolons (empty class elements)
    if (_match([TokenType.semicolon])) {
      // Return an empty statement wrapped in a special marker
      return FieldDeclaration(
        key: IdentifierExpression(
          name: '__empty__',
          line: startToken.line,
          column: startToken.column,
        ),
        initializer: null,
        isStatic: false,
        isPrivate: false,
        line: startToken.line,
        column: startToken.column,
      );
    }

    bool isStatic = false;

    // Check static (but not if it contains Unicode escapes, which makes it an identifier)
    if (_check(TokenType.keywordStatic)) {
      final staticToken = _peek();
      // Unicode escapes in 'static' make it an identifier, not a keyword
      if (!staticToken.hasUnicodeEscape) {
        // Look ahead to see if this is actually a static modifier or a field name
        // static is a modifier if followed by { (static block), a method name, get, set, async, *, or another keyword
        // static is a field name if followed by ; or =
        final next = _peekNext();
        final isStaticModifier =
            next != null &&
            (next.type == TokenType.leftBrace || // static { }
                next.type == TokenType.identifier ||
                next.type == TokenType.privateIdentifier ||
                next.type == TokenType.string ||
                next.type == TokenType.number ||
                next.type == TokenType.bigint ||
                next.type == TokenType.leftBracket || // computed property
                next.type == TokenType.keywordGet ||
                next.type == TokenType.keywordSet ||
                next.type == TokenType.keywordAsync ||
                next.type == TokenType.multiply || // generator
                _isKeywordAllowedAsMethodNameToken(next));

        if (isStaticModifier) {
          _advance(); // consume the static keyword
          // Bloc statique : static { ... }
          if (_check(TokenType.leftBrace)) {
            final body = _blockStatement();
            return StaticBlockDeclaration(
              body: body,
              line: startToken.line,
              column: startToken.column,
            );
          }
          isStatic = true;
        }
        // Otherwise, fall through - treat 'static' as a field/method name
      }
      // If static has Unicode escape or isn't a modifier, fall through - it will be parsed as a method/field name
    }

    // Check getter/setter
    // IMPORTANT: In JavaScript, "get" and "set" can also be method names!
    // If "get" or "set" is followed by "(", it's a method name, not a getter/setter.
    MethodKind? methodKind;
    if (_checkGet() && !_checkAhead(TokenType.leftParen, 1)) {
      final getToken = _advance(); // consommer 'get'
      // Validate that 'get' doesn't contain Unicode escapes
      if (getToken.hasUnicodeEscape) {
        throw ParseError(
          'Contextual keyword "get" must not contain Unicode escape sequences',
          getToken,
        );
      }
      methodKind = MethodKind.get;
    } else if (_checkSet() && !_checkAhead(TokenType.leftParen, 1)) {
      final setToken = _advance(); // consommer 'set'
      // Validate that 'set' doesn't contain Unicode escapes
      if (setToken.hasUnicodeEscape) {
        throw ParseError(
          'Contextual keyword "set" must not contain Unicode escape sequences',
          setToken,
        );
      }
      methodKind = MethodKind.set;
    }

    // Check async for async methods
    bool isAsync = false;
    if (_match([TokenType.keywordAsync])) {
      final asyncToken = _previous();
      // Validate that 'async' doesn't contain Unicode escapes
      if (asyncToken.hasUnicodeEscape) {
        throw ParseError(
          'Contextual keyword "async" must not contain Unicode escape sequences',
          asyncToken,
        );
      }
      isAsync = true;
    }

    // Check generator for generator methods (*)
    // This can also be async* for async generator
    bool isGenerator = false;
    if (_match([TokenType.multiply])) {
      isGenerator = true;
    }

    // Parse the key (member name)
    Expression key;
    bool isPrivate = false;
    bool computed = false;

    if (_check(TokenType.privateIdentifier)) {
      // Private identifier #field
      final privateToken = _advance();
      isPrivate = true;
      key = PrivateIdentifierExpression(
        name: privateToken.lexeme,
        line: privateToken.line,
        column: privateToken.column,
      );
    } else if (_check(TokenType.leftBracket)) {
      // Computed property [expr]
      _advance(); // consommer '['
      key = _expression();
      _consume(
        TokenType.rightBracket,
        'Expected \']\' after computed property',
      );
      computed = true;
    } else if (_check(TokenType.identifier) ||
        _isKeywordAllowedAsMethodName()) {
      // Identifiant normal or keyword used as method name (JavaScript allows this)
      final nameToken = _advance();
      key = IdentifierExpression(
        name: nameToken.lexeme,
        line: nameToken.line,
        column: nameToken.column,
      );

      // Check if it's 'constructor'
      if (nameToken.lexeme == 'constructor') {
        methodKind = MethodKind.constructor;
      }
    } else if (_check(TokenType.string)) {
      // Support for string properties: "method"() { ... }, get "prop"() { ... }, etc.
      final stringToken = _advance();
      key = LiteralExpression(
        value: stringToken.literal,
        type: 'string',
        line: stringToken.line,
        column: stringToken.column,
      );
    } else if (_check(TokenType.number)) {
      // Support for numeric properties: 1() { ... }, get 2() { ... }, etc.
      final numToken = _advance();
      key = LiteralExpression(
        value: numToken.literal,
        type: 'number',
        line: numToken.line,
        column: numToken.column,
      );
    } else if (_check(TokenType.bigint)) {
      // Support for BigInt properties: 128n() { ... }, get 256n() { ... }, etc.
      final bigintToken = _advance();
      key = LiteralExpression(
        value: bigintToken.literal,
        type: 'bigint',
        line: bigintToken.line,
        column: bigintToken.column,
      );
    } else {
      throw Exception('Expected property name');
    }

    // Check if it's a method (has parentheses) or a field
    if (_check(TokenType.leftParen)) {
      // It's a method
      _advance(); // consommer '('

      // Use the same parsing logic as for functions
      // to support destructuring patterns in parameters
      final params = _parseFunctionParameters();

      // Getters cannot have parameters, setters must have exactly one parameter
      if (methodKind == MethodKind.get && params.isNotEmpty) {
        throw LexerError(
          'SyntaxError: Getter must not have any formal parameters',
          _peek().line,
          _peek().column,
        );
      }
      if (methodKind == MethodKind.set && params.length != 1) {
        throw LexerError(
          'SyntaxError: Setter must have exactly one formal parameter',
          _peek().line,
          _peek().column,
        );
      }

      _consume(TokenType.rightParen, 'Expected \')\' after parameters');

      // Set async/generator context if this is an async/generator method
      final oldAsyncContext = _inAsyncContext;
      final oldGeneratorContext = _inGeneratorContext;
      final oldFunctionDepth = _functionDepth;
      _inAsyncContext = isAsync; // Always set to correct value for this method
      _inGeneratorContext =
          isGenerator; // Always set to correct value for this method
      _functionDepth++; // Increment for method body parsing

      // Method body
      final body = _blockStatement();

      // Restore context
      _inAsyncContext = oldAsyncContext;
      _inGeneratorContext = oldGeneratorContext;
      _functionDepth = oldFunctionDepth;

      // ES6 14.1.2: Illegal to have "use strict" directive with non-simple parameters
      _validateStrictModeWithParams(
        params,
        body,
        startToken.line,
        startToken.column,
      );

      return MethodDefinition(
        key: key,
        value: isAsync
            ? AsyncFunctionExpression(
                id: null,
                params: params,
                body: body,
                line: startToken.line,
                column: startToken.column,
                isGenerator: isGenerator,
              )
            : FunctionExpression(
                id: null,
                params: params,
                body: body,
                line: startToken.line,
                column: startToken.column,
                isGenerator: isGenerator,
              ),
        kind: methodKind ?? MethodKind.method,
        isStatic: isStatic,
        isPrivate: isPrivate,
        computed: computed,
        line: startToken.line,
        column: startToken.column,
      );
    } else {
      // C'est un champ
      Expression? initializer;
      if (_match([TokenType.assign])) {
        initializer = _assignment();
      }

      // ASI (Automatic Semicolon Insertion) for class fields
      // According to ES2022, class fields support ASI with newlines
      // On n'exige un semicolon explicite que s'il y en a un
      if (_check(TokenType.semicolon)) {
        _advance();
      }
      // Otherwise, we implicitly accept an ASI if:
      // - On est en fin de classe (rightBrace)
      // - We're at end of line (just for consistency with the parser)

      return FieldDeclaration(
        key: key,
        initializer: initializer,
        isStatic: isStatic,
        isPrivate: isPrivate,
        line: startToken.line,
        column: startToken.column,
      );
    }
  }

  /// Parse an import
  Statement _importDeclaration() {
    final startToken = _previous();

    // Import dynamique: import('module')
    // It's an expression, not a declaration
    // We must therefore put back the 'import' token and let _expressionStatement() handle it
    if (_check(TokenType.leftParen)) {
      // Back up so that _expression() can see the 'import'
      _current--;
      return _expressionStatement();
    }

    // Import statique
    ImportDefaultSpecifier? defaultSpecifier;
    final namedSpecifiers = <ImportSpecifier>[];
    ImportNamespaceSpecifier? namespaceSpecifier;

    // Import side-effect: import 'module'
    if (_check(TokenType.string)) {
      final sourceToken = _consume(
        TokenType.string,
        'Expected string literal for module source',
      );
      _skipImportAttributes(); // ES2024: skip import attributes if present
      _consumeSemicolonOrASI("Expected ';' after import declaration");

      return ImportDeclaration(
        source: LiteralExpression(
          value: sourceToken.literal,
          type: 'string',
          line: sourceToken.line,
          column: sourceToken.column,
        ),
        defaultSpecifier: null,
        namedSpecifiers: [],
        namespaceSpecifier: null,
        line: startToken.line,
        column: startToken.column,
      );
    }

    // Default import: import defaultExport from 'module'
    // ou import defaultExport, { named } from 'module'
    // ou import defaultExport, * as ns from 'module'
    if (_check(TokenType.identifier) &&
        !_check(TokenType.leftBrace) &&
        !_check(TokenType.multiply)) {
      final localName = _consume(
        TokenType.identifier,
        'Expected identifier',
      ).lexeme;
      defaultSpecifier = ImportDefaultSpecifier(
        local: IdentifierExpression(
          name: localName,
          line: _previous().line,
          column: _previous().column,
        ),
        line: _previous().line,
        column: _previous().column,
      );

      // If there's a comma, there are additional specifiers (named or namespace)
      // If no comma, we'll go straight to 'from'
      _match([TokenType.comma]);
    }

    // Named imports: import { a, b as c } from 'module'
    if (_match([TokenType.leftBrace])) {
      while (!_check(TokenType.rightBrace) && !_isAtEnd()) {
        // The imported name can be an identifier, keyword, or string literal
        String importedName;
        if (_check(TokenType.string)) {
          final stringToken = _advance();
          importedName = stringToken.literal as String;
        } else {
          // Allow keywords as imported names for arbitrary-module-namespace-names
          final nameToken = _parseIdentifierOrKeyword();
          importedName = nameToken.lexeme;
        }

        String localName = importedName;

        if (_match([TokenType.keywordAs])) {
          localName = _parseIdentifierOrKeyword().lexeme;
        }

        namedSpecifiers.add(
          ImportSpecifier(
            imported: IdentifierExpression(
              name: importedName,
              line: _previous().line,
              column: _previous().column,
            ),
            local: IdentifierExpression(
              name: localName,
              line: _previous().line,
              column: _previous().column,
            ),
            line: _previous().line,
            column: _previous().column,
          ),
        );

        if (!_match([TokenType.comma])) break;
      }
      _consume(TokenType.rightBrace, "Expected '}' after import specifiers");
    }

    // Import namespace: import * as name from 'module'
    if (_match([TokenType.multiply])) {
      _consume(TokenType.keywordAs, "Expected 'as' after '*'");
      final localName = _consume(
        TokenType.identifier,
        'Expected identifier',
      ).lexeme;
      namespaceSpecifier = ImportNamespaceSpecifier(
        local: IdentifierExpression(
          name: localName,
          line: _previous().line,
          column: _previous().column,
        ),
        line: _previous().line,
        column: _previous().column,
      );
    }

    // 'from' is no longer a keyword, it's a contextual identifier
    _consumeIdentifier('from', "Expected 'from' after import specifiers");
    final sourceToken = _consume(
      TokenType.string,
      'Expected string literal for module source',
    );
    _skipImportAttributes(); // ES2024: skip import attributes if present
    _consumeSemicolonOrASI("Expected ';' after import declaration");

    return ImportDeclaration(
      source: LiteralExpression(
        value: sourceToken.literal,
        type: 'string',
        line: sourceToken.line,
        column: sourceToken.column,
      ),
      defaultSpecifier: defaultSpecifier,
      namedSpecifiers: namedSpecifiers,
      namespaceSpecifier: namespaceSpecifier,
      line: startToken.line,
      column: startToken.column,
    );
  }

  /// Parse an export
  ExportDeclaration _exportDeclaration() {
    final startToken = _previous();

    // Default export: export default expression
    if (_match([TokenType.keywordDefault])) {
      Expression declaration;
      bool needsSemicolon = true;

      // export default function name() {} ou export default function() {}
      if (_check(TokenType.keywordFunction)) {
        _advance();
        declaration = _functionExpression();
        needsSemicolon = false;
      }
      // export default async function name() {} ou export default async function() {}
      else if (_check(TokenType.keywordAsync) &&
          _peekNext()?.type == TokenType.keywordFunction) {
        _advance(); // consume async
        _advance(); // consume function
        declaration = _asyncFunctionExpression();
        needsSemicolon = false;
      }
      // export default class name {} ou export default class {}
      // Note: Use ClassExpression to allow unnamed classes
      else if (_check(TokenType.keywordClass)) {
        _advance();
        declaration = _classExpression();
        needsSemicolon = false;
      }
      // export default expression;
      else {
        declaration = _expression();
      }

      if (needsSemicolon) {
        _consumeSemicolonOrASI("Expected ';' after export default");
      }

      return ExportDefaultDeclaration(
        declaration: declaration,
        line: startToken.line,
        column: startToken.column,
      );
    }

    // Export of declaration: export const/let/var/function/class
    if (_match([
      TokenType.keywordConst,
      TokenType.keywordLet,
      TokenType.keywordVar,
    ])) {
      final declaration = _variableDeclaration();
      return ExportDeclarationStatement(
        declaration: declaration,
        line: startToken.line,
        column: startToken.column,
      );
    }

    // Export async function
    if (_match([TokenType.keywordAsync])) {
      if (_check(TokenType.keywordFunction)) {
        final declaration = _asyncFunctionDeclaration();
        return ExportDeclarationStatement(
          declaration: declaration,
          line: startToken.line,
          column: startToken.column,
        );
      } else {
        throw ParseError('Unexpected token in export declaration', _peek());
      }
    }

    if (_match([TokenType.keywordFunction])) {
      final declaration = _functionDeclaration();
      return ExportDeclarationStatement(
        declaration: declaration,
        line: startToken.line,
        column: startToken.column,
      );
    }

    if (_match([TokenType.keywordClass])) {
      final declaration = _classDeclaration();
      return ExportDeclarationStatement(
        declaration: declaration,
        line: startToken.line,
        column: startToken.column,
      );
    }

    // Named export: export { a, b as c }
    if (_match([TokenType.leftBrace])) {
      final specifiers = <ExportSpecifier>[];

      while (!_check(TokenType.rightBrace) && !_isAtEnd()) {
        // The local name can be an identifier, keyword, or string literal (for re-exports)
        String localName;
        if (_check(TokenType.string)) {
          final stringToken = _advance();
          localName = stringToken.literal as String;
        } else {
          // Allow keywords as local names for re-exporting
          final nameToken = _parseIdentifierOrKeyword();
          localName = nameToken.lexeme;
        }

        String exportedName = localName;

        if (_match([TokenType.keywordAs])) {
          // The exported name can be an identifier or a string literal
          if (_check(TokenType.string)) {
            final stringToken = _advance();
            exportedName = stringToken.literal as String;
          } else {
            exportedName = _parseIdentifierOrKeyword().lexeme;
          }
        }

        specifiers.add(
          ExportSpecifier(
            local: IdentifierExpression(
              name: localName,
              line: _previous().line,
              column: _previous().column,
            ),
            exported: IdentifierExpression(
              name: exportedName,
              line: _previous().line,
              column: _previous().column,
            ),
            line: _previous().line,
            column: _previous().column,
          ),
        );

        if (!_match([TokenType.comma])) break;
      }

      _consume(TokenType.rightBrace, "Expected '}' after export specifiers");

      String? source;
      // 'from' is no longer a keyword, it's a contextual identifier
      if (_matchIdentifier('from')) {
        final sourceToken = _consume(
          TokenType.string,
          'Expected string literal for module source',
        );
        source = sourceToken.literal as String;
      }

      _consumeSemicolonOrASI("Expected ';' after export declaration");

      return ExportNamedDeclaration(
        specifiers: specifiers,
        source: source != null
            ? LiteralExpression(
                value: source,
                type: 'string',
                line: _previous().line,
                column: _previous().column,
              )
            : null,
        line: startToken.line,
        column: startToken.column,
      );
    }

    // Export de tout: export * from 'module' ou export * as name from 'module'
    if (_match([TokenType.multiply])) {
      Expression? exportedExpr;

      // Check for 'as name' (re-export with custom name)
      if (_match([TokenType.keywordAs])) {
        // The name can be an identifier or a string literal (for arbitrary-module-namespace-names)
        if (_check(TokenType.string)) {
          final nameToken = _advance();
          exportedExpr = LiteralExpression(
            value: nameToken.literal,
            type: 'string',
            line: nameToken.line,
            column: nameToken.column,
          );
        } else {
          final nameToken = _parseIdentifierOrKeyword();
          exportedExpr = IdentifierExpression(
            name: nameToken.lexeme,
            line: nameToken.line,
            column: nameToken.column,
          );
        }
      }

      // 'from' is no longer a keyword, it's a contextual identifier
      _consumeIdentifier('from', "Expected 'from' after '*'");
      final sourceToken = _consume(
        TokenType.string,
        'Expected string literal for module source',
      );
      _consumeSemicolonOrASI("Expected ';' after export all");

      return ExportAllDeclaration(
        source: LiteralExpression(
          value: sourceToken.literal,
          type: 'string',
          line: sourceToken.line,
          column: sourceToken.column,
        ),
        exported: exportedExpr,
        line: startToken.line,
        column: startToken.column,
      );
    }

    throw ParseError('Unexpected token in export declaration', _peek());
  }

  /// Check if current token is a keyword that can be used as a method/property name
  /// In JavaScript, many keywords can be used as property/method names in objects and classes
  bool _isKeywordAllowedAsMethodName() {
    final current = _peek();
    // Allow most keywords except those that would cause parsing ambiguity
    final allowedKeywordTypes = {
      // TokenType.keywordFrom, // 'from' is no longer a keyword
      // TokenType.keywordGet, // 'get' is no longer a keyword
      // TokenType.keywordSet, // 'set' is no longer a keyword
      TokenType.keywordAs,
      TokenType.keywordAsync,
      TokenType.keywordAwait,
      TokenType.keywordOf,
      TokenType.keywordIn,
      TokenType.keywordDefault,
      TokenType.keywordDelete, // 'delete' can be a method name: map.delete(key)
      TokenType
          .keywordFinally, // 'finally' for Promise.prototype.finally() (ES2018)
      TokenType.keywordWith, // 'with' for Array.prototype.with() (ES2023)
      TokenType.keywordLet, // 'let' can be a method name
      TokenType.keywordConst, // 'const' can be a method name
      TokenType.keywordFor, // 'for' can be a method name
      TokenType.keywordWhile, // 'while' can be a method name
      TokenType.keywordDo, // 'do' can be a method name
      TokenType.keywordIf, // 'if' can be a method name
      TokenType.keywordElse, // 'else' can be a method name
      TokenType.keywordTry, // 'try' can be a method name
      TokenType.keywordCatch, // 'catch' can be a method name
      TokenType.keywordThrow, // 'throw' can be a method name
      TokenType.keywordReturn, // 'return' can be a method name
      TokenType.keywordBreak, // 'break' can be a method name
      TokenType.keywordContinue, // 'continue' can be a method name
      TokenType.keywordSwitch, // 'switch' can be a method name
      TokenType.keywordCase, // 'case' can be a method name
      TokenType.keywordStatic, // 'static' can be a method name
      TokenType.keywordClass, // 'class' can be a method name
      TokenType.keywordExtends, // 'extends' can be a method name
      TokenType.keywordSuper, // 'super' can be a method name
      TokenType.keywordThis, // 'this' can be a method name
      TokenType.keywordNew, // 'new' can be a method name
      TokenType.keywordTrue, // 'true' can be a method name
      TokenType.keywordFalse, // 'false' can be a method name
      TokenType.keywordNull, // 'null' can be a method name
      TokenType.keywordUndefined, // 'undefined' can be a method name
      TokenType.keywordYield, // 'yield' can be a method name
      TokenType.keywordImport, // 'import' can be a method name
      TokenType.keywordExport, // 'export' can be a method name
      TokenType.keywordFunction, // 'function' can be a method name
      TokenType.keywordVar, // 'var' can be a method name
      TokenType.keywordTypeof, // 'typeof' can be a method name
      TokenType.keywordInstanceof, // 'instanceof' can be a method name
      TokenType.keywordVoid, // 'void' can be a method name
      // Could add more as needed
    };
    return allowedKeywordTypes.contains(current.type);
  }

  /// Check if a given token is a keyword that can be used as a method/property name
  bool _isKeywordAllowedAsMethodNameToken(Token token) {
    final allowedKeywordTypes = {
      TokenType.keywordAs,
      TokenType.keywordAsync,
      TokenType.keywordAwait,
      TokenType.keywordOf,
      TokenType.keywordIn,
      TokenType.keywordDefault,
      TokenType.keywordDelete,
      TokenType.keywordFinally,
      TokenType.keywordWith,
      TokenType.keywordLet,
      TokenType.keywordConst,
      TokenType.keywordFor,
      TokenType.keywordWhile,
      TokenType.keywordDo,
      TokenType.keywordIf,
      TokenType.keywordElse,
      TokenType.keywordTry,
      TokenType.keywordCatch,
      TokenType.keywordThrow,
      TokenType.keywordReturn,
      TokenType.keywordBreak,
      TokenType.keywordContinue,
      TokenType.keywordSwitch,
      TokenType.keywordCase,
      TokenType.keywordStatic,
      TokenType.keywordClass,
      TokenType.keywordExtends,
      TokenType.keywordSuper,
      TokenType.keywordThis,
      TokenType.keywordNew,
      TokenType.keywordTrue,
      TokenType.keywordFalse,
      TokenType.keywordNull,
      TokenType.keywordUndefined,
      TokenType.keywordYield,
      TokenType.keywordImport,
      TokenType.keywordExport,
      TokenType.keywordFunction,
      TokenType.keywordVar,
      TokenType.keywordTypeof,
      TokenType.keywordInstanceof,
      TokenType.keywordVoid,
    };
    return allowedKeywordTypes.contains(token.type);
  }

  /// Parse function parameters with ES2017 trailing comma support
  /// Returns a list of Parameter objects
  List<Parameter> _parseFunctionParameters() {
    final params = <Parameter>[];
    bool hasRestParam = false;

    if (!_check(TokenType.rightParen)) {
      do {
        // Check if it's a rest parameter
        bool isRest = false;
        if (_match([TokenType.spread])) {
          isRest = true;
          if (hasRestParam) {
            throw ParseError('Only one rest parameter allowed', _peek());
          }
          hasRestParam = true;
        }

        // Detect if it's a destructuring pattern or a simple parameter
        dynamic nameOrPattern;
        Expression? defaultValue;

        if (_check(TokenType.leftBrace) || _check(TokenType.leftBracket)) {
          // C'est un destructuring pattern: {x, y} ou [a, b]
          // ES6: Also valid with rest: ...[a, b] or ...{x, y}

          // Parse the pattern as an expression then convert it
          final expr = _primary();
          nameOrPattern = _expressionToPattern(expr);

          // Check if there's a default value
          if (_match([TokenType.assign])) {
            if (isRest) {
              throw ParseError(
                'Rest parameters cannot have default values',
                _peek(),
              );
            }
            defaultValue = _assignmentExpression();
          }
        } else {
          // Simple parameter
          Token paramName;
          if (_check(TokenType.identifier)) {
            paramName = _consume(
              TokenType.identifier,
              'Expected parameter name or destructuring pattern',
            );
          } else if (_check(TokenType.keywordAwait)) {
            paramName = _advance();
          } else if (_check(TokenType.keywordYield)) {
            paramName = _advance();
          } else {
            throw ParseError(
              'Expected parameter name or destructuring pattern',
              _peek(),
            );
          }
          nameOrPattern = IdentifierExpression(
            name: paramName.lexeme,
            line: paramName.line,
            column: paramName.column,
          );

          // Check if there's a default value
          if (_match([TokenType.assign])) {
            if (isRest) {
              throw ParseError(
                'Rest parameters cannot have default values',
                _peek(),
              );
            }
            defaultValue = _assignmentExpression();
          }
        }

        params.add(
          Parameter(
            nameOrPattern: nameOrPattern,
            defaultValue: defaultValue,
            isRest: isRest,
          ),
        );

        // ES2017: Support trailing comma
        if (_match([TokenType.comma])) {
          // Rest parameters cannot be followed by a comma (even trailing)
          if (isRest) {
            throw ParseError(
              'Rest parameter must be last formal parameter',
              _peek(),
            );
          }
          // If we find a comma followed by ')', it's a trailing comma (accepted)
          if (_check(TokenType.rightParen)) {
            break;
          }
          // Otherwise, we continue with the next parameter
        } else {
          break;
        }
      } while (true);
    }

    return params;
  }

  /// Parse function call arguments with ES2017 trailing comma support
  /// Returns a list of Expression objects
  List<Expression> _parseFunctionArguments() {
    final arguments = <Expression>[];

    if (!_check(TokenType.rightParen)) {
      do {
        if (_match([TokenType.spread])) {
          // Spread element: ...args
          final spreadStart = _previous();
          final argument = _assignmentExpression();
          arguments.add(
            SpreadElement(
              argument: argument,
              line: spreadStart.line,
              column: spreadStart.column,
            ),
          );
        } else {
          arguments.add(_assignmentExpression());
        }

        // ES2017: Support trailing comma
        if (_match([TokenType.comma])) {
          // If we find a comma followed by ')', it's a trailing comma (accepted)
          if (_check(TokenType.rightParen)) {
            break;
          }
          // Otherwise, we continue with the next argument
        } else {
          break;
        }
      } while (true);
    }

    return arguments;
  }

  /// Skip import attributes (with { ... }) if present
  /// Used for ES2024 import attributes: import x from 'y' with { type: 'json' }
  void _skipImportAttributes() {
    // Check for 'with' keyword
    if (_match([TokenType.keywordWith])) {
      // Expect opening brace
      if (_match([TokenType.leftBrace])) {
        // Skip the contents of the attributes object
        int braceDepth = 1;
        while (braceDepth > 0 && !_isAtEnd()) {
          if (_match([TokenType.leftBrace])) {
            braceDepth++;
          } else if (_match([TokenType.rightBrace])) {
            braceDepth--;
          } else {
            _advance();
          }
        }
      }
    }
  }
}
