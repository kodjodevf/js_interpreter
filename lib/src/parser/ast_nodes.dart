/// Abstract Syntax Tree (AST) nodes for JavaScript
library;

/// Base class for all AST nodes
abstract class ASTNode {
  /// Position in the source code
  final int line;
  final int column;

  const ASTNode({required this.line, required this.column});

  /// Methode pour le visitor pattern
  T accept<T>(ASTVisitor<T> visitor);

  @override
  String toString() => '$runtimeType($line:$column)';
}

/// Interface for the Visitor pattern
abstract class ASTVisitor<T> {
  // Expressions
  T visitLiteralExpression(LiteralExpression node);
  T visitRegexLiteralExpression(RegexLiteralExpression node);
  T visitTemplateLiteralExpression(TemplateLiteralExpression node);
  T visitTaggedTemplateExpression(TaggedTemplateExpression node);
  T visitIdentifierExpression(IdentifierExpression node);
  T visitPrivateIdentifierExpression(PrivateIdentifierExpression node);
  T visitThisExpression(ThisExpression node);
  T visitSuperExpression(SuperExpression node);
  T visitBinaryExpression(BinaryExpression node);
  T visitUnaryExpression(UnaryExpression node);
  T visitAssignmentExpression(AssignmentExpression node);
  T visitCallExpression(CallExpression node);
  T visitNewExpression(NewExpression node);
  T visitMemberExpression(MemberExpression node);
  T visitArrayExpression(ArrayExpression node);
  T visitObjectExpression(ObjectExpression node);
  T visitConditionalExpression(ConditionalExpression node);
  T visitSequenceExpression(SequenceExpression node);
  T visitArrowFunctionExpression(ArrowFunctionExpression node);
  T visitAsyncArrowFunctionExpression(AsyncArrowFunctionExpression node);
  T visitFunctionExpression(FunctionExpression node);
  T visitAsyncFunctionExpression(AsyncFunctionExpression node);
  T visitOptionalChainingExpression(OptionalChainingExpression node);
  T visitNullishCoalescingExpression(NullishCoalescingExpression node);
  T visitAwaitExpression(AwaitExpression node);
  T visitYieldExpression(YieldExpression node);
  T visitSpreadElement(SpreadElement node);

  // Declarations
  T visitVariableDeclaration(VariableDeclaration node);
  T visitFunctionDeclaration(FunctionDeclaration node);
  T visitAsyncFunctionDeclaration(AsyncFunctionDeclaration node);
  T visitClassDeclaration(ClassDeclaration node);
  T visitClassExpression(ClassExpression node);
  T visitFieldDeclaration(FieldDeclaration node);
  T visitStaticBlockDeclaration(StaticBlockDeclaration node);

  // Instructions
  T visitExpressionStatement(ExpressionStatement node);
  T visitBlockStatement(BlockStatement node);
  T visitIfStatement(IfStatement node);
  T visitWhileStatement(WhileStatement node);
  T visitDoWhileStatement(DoWhileStatement node);
  T visitForStatement(ForStatement node);
  T visitForInStatement(ForInStatement node);
  T visitForOfStatement(ForOfStatement node);
  T visitLabeledStatement(LabeledStatement node);
  T visitReturnStatement(ReturnStatement node);
  T visitBreakStatement(BreakStatement node);
  T visitContinueStatement(ContinueStatement node);
  T visitTryStatement(TryStatement node);
  T visitCatchClause(CatchClause node);
  T visitThrowStatement(ThrowStatement node);
  T visitSwitchStatement(SwitchStatement node);
  T visitSwitchCase(SwitchCase node);
  T visitWithStatement(WithStatement node);
  T visitEmptyStatement(EmptyStatement node);

  // Patterns de destructuring
  T visitIdentifierPattern(IdentifierPattern node);
  T visitExpressionPattern(ExpressionPattern node);
  T visitAssignmentPattern(AssignmentPattern node);
  T visitArrayPattern(ArrayPattern node);
  T visitObjectPattern(ObjectPattern node);
  T visitObjectPatternProperty(ObjectPatternProperty node);
  T visitDestructuringAssignmentExpression(
    DestructuringAssignmentExpression node,
  );

  // Programme
  T visitProgram(Program node);

  // Modules ES6
  T visitImportDeclaration(ImportDeclaration node);
  T visitImportSpecifier(ImportSpecifier node);
  T visitImportDefaultSpecifier(ImportDefaultSpecifier node);
  T visitImportNamespaceSpecifier(ImportNamespaceSpecifier node);
  T visitExportDeclaration(ExportDeclaration node);
  T visitExportSpecifier(ExportSpecifier node);
  T visitExportDefaultDeclaration(ExportDefaultDeclaration node);
  T visitExportNamedDeclaration(ExportNamedDeclaration node);
  T visitExportAllDeclaration(ExportAllDeclaration node);
  T visitImportExpression(ImportExpression node);
  T visitMetaProperty(MetaProperty node);
}

// ===== EXPRESSIONS =====

/// Base class for all expressions
abstract class Expression extends ASTNode {
  const Expression({required super.line, required super.column});
}

/// Literal expression (numbers, strings, booleans, null, undefined)
class LiteralExpression extends Expression {
  final dynamic value;
  final String type; // 'number', 'string', 'boolean', 'null', 'undefined'

  const LiteralExpression({
    required this.value,
    required this.type,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitLiteralExpression(this);

  @override
  String toString() {
    // ES2019: Generate proper JavaScript source
    switch (type) {
      case 'string':
        return "'$value'"; // Simple quotes - should handle escapes properly
      case 'number':
        // Remove .0 from integers
        if (value is num && value == value.toInt()) {
          return value.toInt().toString();
        }
        return value.toString();
      case 'boolean':
      case 'null':
        return value.toString();
      case 'undefined':
        return 'undefined';
      default:
        return value.toString();
    }
  }
}

/// Regular expression literal (/pattern/flags)
class RegexLiteralExpression extends Expression {
  final String pattern;
  final String flags;

  const RegexLiteralExpression({
    required this.pattern,
    required this.flags,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) =>
      visitor.visitRegexLiteralExpression(this);

  @override
  String toString() => 'RegexLiteral(/$pattern/$flags)';
}

/// Template literal with interpolation (`Hello ${name}!`)
class TemplateLiteralExpression extends Expression {
  final List<String> quasis; // Text parts of the template
  final List<Expression> expressions; // Interpolated expressions

  const TemplateLiteralExpression({
    required this.quasis,
    required this.expressions,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) =>
      visitor.visitTemplateLiteralExpression(this);

  @override
  String toString() =>
      'TemplateLiteral(${quasis.length} parts, ${expressions.length} expressions)';
}

/// Tagged template literal: tag`template` or tag`Hello ${name}!`
class TaggedTemplateExpression extends Expression {
  final Expression tag; // Expression before the backtick
  final TemplateLiteralExpression quasi; // Template content

  const TaggedTemplateExpression({
    required this.tag,
    required this.quasi,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) =>
      visitor.visitTaggedTemplateExpression(this);

  @override
  String toString() => 'TaggedTemplate($tag, $quasi)';
}

/// Identifier expression (variables, function names)
class IdentifierExpression extends Expression {
  final String name;

  const IdentifierExpression({
    required this.name,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitIdentifierExpression(this);

  @override
  String toString() => name;
}

/// Private identifier expression (#privateField)
class PrivateIdentifierExpression extends Expression {
  final String name; // Includes the # at the beginning

  const PrivateIdentifierExpression({
    required this.name,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) =>
      visitor.visitPrivateIdentifierExpression(this);

  @override
  String toString() => 'PrivateIdentifier($name)';
}

/// 'this' expression
class ThisExpression extends Expression {
  const ThisExpression({required super.line, required super.column});

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitThisExpression(this);

  @override
  String toString() => 'This()';
}

/// 'super' expression
class SuperExpression extends Expression {
  const SuperExpression({required super.line, required super.column});

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitSuperExpression(this);

  @override
  String toString() => 'Super()';
}

/// Binary expression (a + b, a == b, etc.)
class BinaryExpression extends Expression {
  final Expression left;
  final String operator;
  final Expression right;

  const BinaryExpression({
    required this.left,
    required this.operator,
    required this.right,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitBinaryExpression(this);

  @override
  String toString() => '$left $operator $right';
}

/// Unary expression (!a, -b, typeof x)
class UnaryExpression extends Expression {
  final String operator;
  final Expression operand;
  final bool prefix; // true for prefix operators, false for postfix

  const UnaryExpression({
    required this.operator,
    required this.operand,
    required this.prefix,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitUnaryExpression(this);

  @override
  String toString() =>
      prefix ? 'Unary($operator$operand)' : 'Unary($operand$operand)';
}

/// Assignment expression (a = b, x += 5)
class AssignmentExpression extends Expression {
  final Expression left;
  final String operator; // '=', '+=', '-=', etc.
  final Expression right;

  const AssignmentExpression({
    required this.left,
    required this.operator,
    required this.right,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitAssignmentExpression(this);

  @override
  String toString() => 'Assignment($left $operator $right)';
}

/// Function call expression (foo(), obj.method(a, b))
class CallExpression extends Expression {
  final Expression callee;
  final List<Expression> arguments;

  const CallExpression({
    required this.callee,
    required this.arguments,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitCallExpression(this);

  @override
  String toString() => 'Call($callee(${arguments.join(', ')}))';
}

/// New expression (new Foo(), new Array(1, 2, 3))
class NewExpression extends Expression {
  final Expression callee;
  final List<Expression> arguments;

  const NewExpression({
    required this.callee,
    required this.arguments,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitNewExpression(this);

  @override
  String toString() => 'New($callee(${arguments.join(', ')}))';
}

/// Member access expression (obj.prop, obj[key])
class MemberExpression extends Expression {
  final Expression object;
  final Expression property;
  final bool computed; // true for obj[key], false for obj.prop

  const MemberExpression({
    required this.object,
    required this.property,
    required this.computed,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitMemberExpression(this);

  @override
  String toString() =>
      computed ? 'Member($object[$property])' : 'Member($object.$property)';
}

/// Array expression ([1, 2, 3])
class ArrayExpression extends Expression {
  final List<Expression?> elements; // null for empty elements

  const ArrayExpression({
    required this.elements,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitArrayExpression(this);

  @override
  String toString() => 'Array([${elements.join(', ')}])';
}

/// Object literal property
class ObjectProperty {
  final Expression key; // Can be Identifier or Literal
  final Expression value;
  final bool computed; // true for [key]: value
  final String? kind; // 'get', 'set', or null for normal property

  const ObjectProperty({
    required this.key,
    required this.value,
    required this.computed,
    this.kind,
  });

  @override
  String toString() {
    final prefix = kind != null ? '$kind ' : '';

    // ES2019: For method shorthand, format as: method() { body }
    if (value is FunctionExpression && kind == null && !computed) {
      final funcExpr = value as FunctionExpression;
      final keyName = key is IdentifierExpression
          ? (key as IdentifierExpression).name
          : key.toString();

      final paramStr = funcExpr.params
          .map((p) {
            if (p.isRest) return '...${p.name?.name ?? 'param'}';
            return p.name?.name ?? 'param';
          })
          .join(', ');

      return '$keyName($paramStr) ${funcExpr.body}';
    }

    return computed ? '$prefix[$key]: $value' : '$prefix$key: $value';
  }
}

/// Object literal expression ({a: 1, b: 2, ...other})
class ObjectExpression extends Expression {
  final List<dynamic> properties; // ObjectProperty or SpreadElement

  const ObjectExpression({
    required this.properties,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitObjectExpression(this);

  @override
  String toString() => 'Object({${properties.join(', ')}})';
}

/// Ternary conditional expression (a ? b : c)
class ConditionalExpression extends Expression {
  final Expression test;
  final Expression consequent;
  final Expression alternate;

  const ConditionalExpression({
    required this.test,
    required this.consequent,
    required this.alternate,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) =>
      visitor.visitConditionalExpression(this);

  @override
  String toString() => 'Conditional($test ? $consequent : $alternate)';
}

/// Sequence expression: (expr1, expr2, expr3)
class SequenceExpression extends Expression {
  final List<Expression> expressions;

  const SequenceExpression({
    required this.expressions,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitSequenceExpression(this);

  @override
  String toString() => 'Sequence(${expressions.join(', ')})';
}

/// Spread element: ...expression (used in arrays, objects, function calls)
class SpreadElement extends Expression {
  final Expression argument;

  const SpreadElement({
    required this.argument,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitSpreadElement(this);

  @override
  String toString() => 'Spread(...$argument)';
}

/// Arrow function expression (param) => expr or (param1, param2) => { body }
class ArrowFunctionExpression extends Expression {
  final List<Parameter> params;
  final dynamic
  body; // Expression for expression arrow, BlockStatement for block arrow
  final bool isExpression; // true if () => expr, false if () => { block }

  const ArrowFunctionExpression({
    required this.params,
    required this.body,
    required this.isExpression,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) =>
      visitor.visitArrowFunctionExpression(this);

  @override
  String toString() {
    // ES2019: Generate proper JavaScript source
    final paramStr = params
        .map((p) {
          if (p.isRest) return '...${p.name?.name ?? 'param'}';
          return p.name?.name ?? 'param';
        })
        .join(', ');
    final paramPart = params.length == 1 && !params[0].isRest
        ? paramStr
        : '($paramStr)';
    final bodyStr = body is BlockStatement ? body.toString() : '($body)';
    return '$paramPart => $bodyStr';
  }
}

/// Async arrow function expression: async (param1, param2) => body
class AsyncArrowFunctionExpression extends ArrowFunctionExpression {
  const AsyncArrowFunctionExpression({
    required super.params,
    required super.body,
    required super.isExpression,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) =>
      visitor.visitAsyncArrowFunctionExpression(this);

  @override
  String toString() => 'async ArrowFunction(${params.join(', ')}) => $body';
}

/// Function expression: function(param1, param2) { body }
class FunctionExpression extends Expression {
  final IdentifierExpression? id; // can be null for anonymous functions
  final List<Parameter> params;
  final BlockStatement body;
  final bool isGenerator;

  const FunctionExpression({
    this.id,
    required this.params,
    required this.body,
    required super.line,
    required super.column,
    this.isGenerator = false,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitFunctionExpression(this);

  @override
  String toString() {
    // ES2019: Generate proper JavaScript source
    final paramStr = params
        .map((p) {
          if (p.isRest) return '...${p.name?.name ?? 'param'}';
          return p.name?.name ?? 'param';
        })
        .join(', ');
    final bodyStr = body.toString();
    final genStr = isGenerator ? '*' : '';
    return 'function$genStr${id != null ? ' ${id!.name}' : ''}($paramStr) $bodyStr';
  }
}

/// Async function expression
class AsyncFunctionExpression extends FunctionExpression {
  const AsyncFunctionExpression({
    super.id,
    required super.params,
    required super.body,
    required super.line,
    required super.column,
    super.isGenerator = false,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) =>
      visitor.visitAsyncFunctionExpression(this);

  @override
  String toString() {
    final genStr = isGenerator ? '*' : '';
    return 'async function$genStr${id != null ? ' ${id!.name}' : ''}(${params.join(', ')}) $body';
  }
}

/// Optional chaining expression: obj?.prop or obj?.method()
class OptionalChainingExpression extends Expression {
  final Expression object;
  final Expression property;
  final bool isCall; // true for method call: obj?.method()

  const OptionalChainingExpression({
    required this.object,
    required this.property,
    this.isCall = false,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) =>
      visitor.visitOptionalChainingExpression(this);

  @override
  String toString() =>
      '$object?.${isCall ? 'call(' : ''}$property${isCall ? ')' : ''}';
}

/// Nullish coalescing expression: left ?? right
class NullishCoalescingExpression extends Expression {
  final Expression left;
  final Expression right;

  const NullishCoalescingExpression({
    required this.left,
    required this.right,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) =>
      visitor.visitNullishCoalescingExpression(this);

  @override
  String toString() => '$left ?? $right';
}

/// Await expression: await promise
class AwaitExpression extends Expression {
  final Expression argument;

  const AwaitExpression({
    required this.argument,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitAwaitExpression(this);

  @override
  String toString() => 'await $argument';
}

/// Yield expression (used in generators)
class YieldExpression extends Expression {
  final Expression? argument;
  final bool delegate; // true for yield*, false for yield

  const YieldExpression({
    this.argument,
    required this.delegate,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitYieldExpression(this);

  @override
  String toString() => delegate ? 'yield* $argument' : 'yield $argument';
}

// ===== DECLARATIONS =====

/// Base class for all declarations
/// Note: Declarations are also statements in JavaScript
abstract class Declaration extends Statement {
  const Declaration({required super.line, required super.column});
}

/// Variable declarator (for var a = 1, b = 2)
class VariableDeclarator {
  final Pattern id;
  final Expression? init;

  const VariableDeclarator({required this.id, this.init});

  @override
  String toString() => init != null ? '$id = $init' : '$id';
}

/// Variable declaration (var, let, const)
class VariableDeclaration extends Declaration {
  final String kind; // 'var', 'let', 'const'
  final List<VariableDeclarator> declarations;

  const VariableDeclaration({
    required this.kind,
    required this.declarations,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitVariableDeclaration(this);

  @override
  String toString() => 'VarDecl($kind ${declarations.join(', ')})';
}

/// Function parameter
class Parameter {
  // Can be either an IdentifierExpression (simple param) or a Pattern (destructuring)
  final dynamic nameOrPattern; // IdentifierExpression or Pattern
  final Expression? defaultValue;
  final bool isRest; // true for rest parameters (...args)

  const Parameter({
    required this.nameOrPattern,
    this.defaultValue,
    this.isRest = false,
  });

  // Helper to get simple name
  IdentifierExpression? get name {
    if (nameOrPattern is IdentifierExpression) {
      return nameOrPattern as IdentifierExpression;
    }
    return null;
  }

  // Helper to get the pattern
  Pattern? get pattern {
    if (nameOrPattern is Pattern) {
      return nameOrPattern as Pattern;
    }
    return null;
  }

  // Check if it's a destructuring parameter
  bool get isDestructuring => nameOrPattern is Pattern;

  @override
  String toString() {
    final restPrefix = isRest ? '...' : '';
    final defaultStr = defaultValue != null ? ' = $defaultValue' : '';
    return '$restPrefix$nameOrPattern$defaultStr';
  }
}

/// Function declaration
class FunctionDeclaration extends Declaration {
  final IdentifierExpression id;
  final List<Parameter> params;
  final BlockStatement body;
  final bool isGenerator;

  const FunctionDeclaration({
    required this.id,
    required this.params,
    required this.body,
    required super.line,
    required super.column,
    this.isGenerator = false,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitFunctionDeclaration(this);

  @override
  String toString() {
    // ES2019: Generate proper JavaScript source
    final paramStr = params
        .map((p) {
          if (p.isRest) return '...${p.name?.name ?? 'param'}';
          return p.name?.name ?? 'param';
        })
        .join(', ');
    final bodyStr = body.toString();
    return 'function ${id.name}($paramStr) $bodyStr';
  }
}

/// Async function declaration
class AsyncFunctionDeclaration extends FunctionDeclaration {
  const AsyncFunctionDeclaration({
    required super.id,
    required super.params,
    required super.body,
    required super.line,
    required super.column,
    super.isGenerator = false,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) =>
      visitor.visitAsyncFunctionDeclaration(this);

  @override
  String toString() {
    final genStr = isGenerator ? '*' : '';
    return 'async function$genStr $id(${params.join(', ')}) $body';
  }
}

/// Class declaration
class ClassDeclaration extends Declaration {
  final IdentifierExpression? id; // Nullable for class expressions
  final Expression? superClass;
  final ClassBody body;

  const ClassDeclaration({
    this.id, // Optional for class expressions
    this.superClass,
    required this.body,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitClassDeclaration(this);

  @override
  String toString() {
    final extendsClause = superClass != null ? ' extends $superClass' : '';
    return 'Class $id$extendsClause $body';
  }
}

/// Class expression (for use in expressions like: const MyClass = class { ... })
class ClassExpression extends Expression {
  final IdentifierExpression? id; // Nullable - anonymous class expressions
  final Expression? superClass;
  final ClassBody body;

  const ClassExpression({
    this.id,
    this.superClass,
    required this.body,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitClassExpression(this);

  @override
  String toString() {
    final name = id != null ? id.toString() : 'anonymous';
    final extendsClause = superClass != null ? ' extends $superClass' : '';
    return 'ClassExpression $name$extendsClause $body';
  }
}

/// Class body (contains methods, fields, and static blocks)
class ClassBody extends ASTNode {
  final List<ClassMember>
  members; // Can contain MethodDefinition, FieldDeclaration, StaticBlockDeclaration

  const ClassBody({
    required this.members,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) {
    // ClassBody n'a pas besoin d'une methode visitor separee
    // car elle est traitee directement dans ClassDeclaration
    throw UnimplementedError('ClassBody should not be visited directly');
  }

  @override
  String toString() => 'ClassBody(${members.length} members)';
}

/// Base class for all class members
abstract class ClassMember extends ASTNode {
  const ClassMember({required super.line, required super.column});
}

/// Method definition in a class
class MethodDefinition extends ClassMember {
  final Expression
  key; // Can be IdentifierExpression, PrivateIdentifierExpression, or ComputedMemberExpression
  final FunctionExpression value;
  final MethodKind kind; // constructor, method, get, set
  final bool isStatic;
  final bool isPrivate;
  final bool
  computed; // true si la cle est [expression], false si c'est un nom litteral

  const MethodDefinition({
    required this.key,
    required this.value,
    required this.kind,
    this.isStatic = false,
    this.isPrivate = false,
    this.computed = false,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) {
    // MethodDefinition n'a pas besoin d'une methode visitor separee
    // car elle est traitee directement dans ClassDeclaration
    throw UnimplementedError('MethodDefinition should not be visited directly');
  }

  @override
  String toString() {
    final staticStr = isStatic ? 'static ' : '';
    final privateStr = isPrivate ? 'private ' : '';
    final kindStr = kind == MethodKind.constructor ? 'constructor' : kind.name;
    return '$staticStr$privateStr$kindStr $key';
  }
}

/// Class field declaration
class FieldDeclaration extends ClassMember {
  final Expression
  key; // Can be IdentifierExpression or PrivateIdentifierExpression
  final Expression? initializer; // Default value
  final bool isStatic;
  final bool isPrivate;

  const FieldDeclaration({
    required this.key,
    this.initializer,
    this.isStatic = false,
    this.isPrivate = false,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitFieldDeclaration(this);

  @override
  String toString() {
    final staticStr = isStatic ? 'static ' : '';
    final privateStr = isPrivate ? 'private ' : '';
    final initStr = initializer != null ? ' = $initializer' : '';
    return '$staticStr${privateStr}field $key$initStr';
  }
}

/// Static block declaration for a class
class StaticBlockDeclaration extends ClassMember {
  final BlockStatement body;

  const StaticBlockDeclaration({
    required this.body,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) =>
      visitor.visitStaticBlockDeclaration(this);

  @override
  String toString() => 'static $body';
}

/// Types of methods in a class
enum MethodKind { constructor, method, get, set }

// ===== INSTRUCTIONS =====

/// Base class for all statements
abstract class Statement extends ASTNode {
  const Statement({required super.line, required super.column});
}

/// Expression statement (expression followed by semicolon)
class ExpressionStatement extends Statement {
  final Expression expression;

  const ExpressionStatement({
    required this.expression,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitExpressionStatement(this);

  @override
  String toString() => 'ExprStmt($expression)';
}

/// Empty statement (semicolon alone)
class EmptyStatement extends Statement {
  const EmptyStatement({required super.line, required super.column});

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitEmptyStatement(this);

  @override
  String toString() => 'EmptyStmt';
}

/// Block statement ({ ... })
class BlockStatement extends Statement {
  final List<Statement> body;

  const BlockStatement({
    required this.body,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitBlockStatement(this);

  @override
  String toString() {
    // ES2019: Generate proper JavaScript source
    if (body.isEmpty) return '{ }';
    // Single-line when possible for function toString()
    if (body.length == 1) return '{ ${body[0]} }';
    // For multiple statements, use single line with ; separator for function body
    final statements = body.map((s) => s.toString()).join('; ');
    return '{ $statements }';
  }
}

/// If/else statement
class IfStatement extends Statement {
  final Expression test;
  final Statement consequent;
  final Statement? alternate;

  const IfStatement({
    required this.test,
    required this.consequent,
    this.alternate,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitIfStatement(this);

  @override
  String toString() => alternate != null
      ? 'If($test) $consequent else $alternate'
      : 'If($test) $consequent';
}

/// While statement
class WhileStatement extends Statement {
  final Expression test;
  final Statement body;

  const WhileStatement({
    required this.test,
    required this.body,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitWhileStatement(this);

  @override
  String toString() => 'While($test) $body';
}

/// Do-while statement
class DoWhileStatement extends Statement {
  final Statement body;
  final Expression test;

  const DoWhileStatement({
    required this.body,
    required this.test,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitDoWhileStatement(this);

  @override
  String toString() => 'DoWhile($body) while($test)';
}

/// For statement
class ForStatement extends Statement {
  final ASTNode? init; // VariableDeclaration or Expression
  final Expression? test;
  final Expression? update;
  final Statement body;

  const ForStatement({
    this.init,
    this.test,
    this.update,
    required this.body,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitForStatement(this);

  @override
  String toString() => 'For($init; $test; $update) $body';
}

/// For-in statement
class ForInStatement extends Statement {
  final ASTNode left; // VariableDeclaration or Identifier
  final Expression right;
  final Statement body;

  const ForInStatement({
    required this.left,
    required this.right,
    required this.body,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitForInStatement(this);

  @override
  String toString() => 'ForIn($left in $right) $body';
}

/// For-of statement
class ForOfStatement extends Statement {
  final ASTNode left; // VariableDeclaration or Identifier
  final Expression right;
  final Statement body;
  final bool await; // ES2018: for await...of

  const ForOfStatement({
    required this.left,
    required this.right,
    required this.body,
    this.await = false,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitForOfStatement(this);

  @override
  String toString() => 'For${await ? 'Await' : ''}Of($left of $right) $body';
}

/// Labeled statement (label:)
class LabeledStatement extends Statement {
  final String label;
  final Statement body;

  const LabeledStatement({
    required this.label,
    required this.body,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitLabeledStatement(this);

  @override
  String toString() => 'Labeled($label: $body)';
}

/// Return statement
class ReturnStatement extends Statement {
  final Expression? argument;

  const ReturnStatement({
    this.argument,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitReturnStatement(this);

  @override
  String toString() => argument != null ? 'return $argument;' : 'return;';
}

/// Break statement
class BreakStatement extends Statement {
  final String? label;

  const BreakStatement({
    this.label,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitBreakStatement(this);

  @override
  String toString() => label != null ? 'Break($label)' : 'Break()';
}

/// Continue statement
class ContinueStatement extends Statement {
  final String? label;

  const ContinueStatement({
    this.label,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitContinueStatement(this);

  @override
  String toString() => label != null ? 'Continue($label)' : 'Continue()';
}

/// Throw statement for raising exceptions
class ThrowStatement extends Statement {
  final Expression argument;

  const ThrowStatement({
    required this.argument,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitThrowStatement(this);

  @override
  String toString() => 'Throw($argument)';
}

/// Try/catch/finally statement for exception handling
class TryStatement extends Statement {
  final BlockStatement block;
  final CatchClause? handler;
  final BlockStatement? finalizer;

  const TryStatement({
    required this.block,
    this.handler,
    this.finalizer,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitTryStatement(this);

  @override
  String toString() {
    final parts = ['Try($block)'];
    if (handler != null) parts.add('$handler');
    if (finalizer != null) parts.add('Finally($finalizer)');
    return parts.join(' ');
  }
}

/// Switch statement
class SwitchStatement extends Statement {
  final Expression discriminant;
  final List<SwitchCase> cases;

  const SwitchStatement({
    required this.discriminant,
    required this.cases,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitSwitchStatement(this);

  @override
  String toString() => 'Switch($discriminant) {${cases.join(', ')}}';
}

/// With statement (forbidden in strict mode)
class WithStatement extends Statement {
  final Expression object;
  final Statement body;

  const WithStatement({
    required this.object,
    required this.body,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitWithStatement(this);

  @override
  String toString() => 'With($object) $body';
}

/// Case in a switch statement
class SwitchCase extends ASTNode {
  final Expression? test; // null for default case
  final List<Statement> consequent;

  const SwitchCase({
    this.test,
    required this.consequent,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitSwitchCase(this);

  @override
  String toString() =>
      test != null ? 'Case($test: $consequent)' : 'Default($consequent)';
}

/// Catch clause of a try/catch
class CatchClause extends ASTNode {
  final IdentifierExpression?
  param; // can be null for catch() without parameter
  final Pattern? paramPattern; // for destructuring patterns
  final BlockStatement body;

  const CatchClause({
    this.param,
    this.paramPattern,
    required this.body,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitCatchClause(this);

  @override
  String toString() {
    if (param != null) return 'Catch($param, $body)';
    if (paramPattern != null) return 'Catch($paramPattern, $body)';
    return 'Catch($body)';
  }
}

// ===== DESTRUCTURING PATTERNS =====

/// Base class for destructuring patterns
abstract class Pattern extends ASTNode {
  const Pattern({required super.line, required super.column});
}

/// Identifier pattern (x in [x] = arr)
class IdentifierPattern extends Pattern {
  final String name;

  const IdentifierPattern({
    required this.name,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitIdentifierPattern(this);

  @override
  String toString() => 'IdentifierPattern($name)';
}

/// Pattern for an expression (like a member expression in rest patterns)
/// Example: ...obj.prop or ...obj[key]
class ExpressionPattern extends Pattern {
  final Expression expression;

  const ExpressionPattern({
    required this.expression,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitExpressionPattern(this);

  @override
  String toString() => 'ExpressionPattern($expression)';
}

/// Pattern with default value (a = 10 in [a = 10] = arr)
class AssignmentPattern extends Pattern {
  final Pattern
  left; // The pattern (IdentifierPattern, ArrayPattern, ObjectPattern)
  final Expression right; // The default value

  const AssignmentPattern({
    required this.left,
    required this.right,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitAssignmentPattern(this);

  @override
  String toString() => 'AssignmentPattern($left = $right)';
}

/// Array destructuring pattern ([a, b, ...rest] = arr)
class ArrayPattern extends Pattern {
  final List<Pattern?> elements; // null for ignored elements
  final Pattern? restElement; // For the rest operator

  const ArrayPattern({
    required this.elements,
    this.restElement,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitArrayPattern(this);

  @override
  String toString() =>
      'ArrayPattern($elements${restElement != null ? ', rest: $restElement' : ''})';
}

/// Object destructuring pattern ({a, b: newName, ...rest} = obj)
class ObjectPattern extends Pattern {
  final List<ObjectPatternProperty> properties;
  final Pattern? restElement; // For the rest operator

  const ObjectPattern({
    required this.properties,
    this.restElement,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitObjectPattern(this);

  @override
  String toString() =>
      'ObjectPattern($properties${restElement != null ? ', rest: $restElement' : ''})';
}

/// Property in an object pattern
class ObjectPatternProperty extends ASTNode {
  final String key; // Original key
  final Pattern value; // Destination pattern
  final bool shorthand; // true for {x} instead of {x: x}
  final Expression? defaultValue; // Default value

  const ObjectPatternProperty({
    required this.key,
    required this.value,
    this.shorthand = false,
    this.defaultValue,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) =>
      visitor.visitObjectPatternProperty(this);

  @override
  String toString() =>
      'ObjectPatternProperty($key: $value${shorthand ? ' [shorthand]' : ''}${defaultValue != null ? ' = $defaultValue' : ''})';
}

/// Assignment with destructuring ([a, b] = arr or {x, y} = obj)
class DestructuringAssignmentExpression extends Expression {
  final Pattern left; // Destructuring pattern
  final Expression right; // Expression to destructure

  const DestructuringAssignmentExpression({
    required this.left,
    required this.right,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) =>
      visitor.visitDestructuringAssignmentExpression(this);

  @override
  String toString() => 'DestructuringAssignment($left = $right)';
}

// ===== PROGRAMME =====

/// Root node of the program
class Program extends ASTNode {
  final List<Statement> body;

  const Program({
    required this.body,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitProgram(this);

  @override
  String toString() => 'Program([${body.join(', ')}])';
}

// ===== MODULES ES6 =====

/// Base class for module declarations
abstract class ModuleDeclaration extends Statement {
  const ModuleDeclaration({required super.line, required super.column});
}

/// Dynamic import (import('module'))
class ImportExpression extends Expression {
  final Expression source;

  const ImportExpression({
    required this.source,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitImportExpression(this);

  @override
  String toString() => 'ImportExpression($source)';
}

/// Meta property (import.meta)
class MetaProperty extends Expression {
  final String meta; // 'import'
  final String property; // 'meta'

  const MetaProperty({
    required this.meta,
    required this.property,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitMetaProperty(this);

  @override
  String toString() => 'MetaProperty($meta.$property)';
}

/// Named import specifier
class ImportSpecifier extends ASTNode {
  final IdentifierExpression imported; // name in the source module
  final IdentifierExpression? local; // local name (can be null if same name)

  const ImportSpecifier({
    required this.imported,
    this.local,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitImportSpecifier(this);

  @override
  String toString() =>
      'ImportSpecifier($imported${local != null ? ' as $local' : ''})';
}

/// Default import specifier
class ImportDefaultSpecifier extends ASTNode {
  final IdentifierExpression local;

  const ImportDefaultSpecifier({
    required this.local,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) =>
      visitor.visitImportDefaultSpecifier(this);

  @override
  String toString() => 'ImportDefaultSpecifier($local)';
}

/// Namespace import specifier (* as name)
class ImportNamespaceSpecifier extends ASTNode {
  final IdentifierExpression local;

  const ImportNamespaceSpecifier({
    required this.local,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) =>
      visitor.visitImportNamespaceSpecifier(this);

  @override
  String toString() => 'ImportNamespaceSpecifier($local)';
}

/// Import declaration
class ImportDeclaration extends ModuleDeclaration {
  final LiteralExpression source; // module path (always a string)
  final ImportDefaultSpecifier? defaultSpecifier;
  final List<ImportSpecifier> namedSpecifiers;
  final ImportNamespaceSpecifier? namespaceSpecifier;

  const ImportDeclaration({
    required this.source,
    this.defaultSpecifier,
    this.namedSpecifiers = const [],
    this.namespaceSpecifier,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitImportDeclaration(this);

  @override
  String toString() {
    final parts = <String>[];
    if (defaultSpecifier != null) parts.add(defaultSpecifier.toString());
    if (namedSpecifiers.isNotEmpty) {
      parts.add('{${namedSpecifiers.join(', ')}}');
    }
    if (namespaceSpecifier != null) parts.add(namespaceSpecifier.toString());
    return 'ImportDeclaration(${parts.join(', ')} from $source)';
  }
}

/// Export specifier
class ExportSpecifier extends ASTNode {
  final IdentifierExpression local; // local name
  final IdentifierExpression exported; // exported name (can be different)

  const ExportSpecifier({
    required this.local,
    required this.exported,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitExportSpecifier(this);

  @override
  String toString() =>
      'ExportSpecifier($local${local != exported ? ' as $exported' : ''})';
}

/// Base class for export declarations
abstract class ExportDeclaration extends ModuleDeclaration {
  const ExportDeclaration({required super.line, required super.column});
}

/// Named export (export { name })
class ExportNamedDeclaration extends ExportDeclaration {
  final List<ExportSpecifier> specifiers;
  final LiteralExpression? source; // for re-export from another module

  const ExportNamedDeclaration({
    required this.specifiers,
    this.source,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) =>
      visitor.visitExportNamedDeclaration(this);

  @override
  String toString() {
    final specifiersStr = specifiers.join(', ');
    if (source != null) {
      return 'ExportNamedDeclaration({$specifiersStr} from $source)';
    }
    return 'ExportNamedDeclaration({$specifiersStr})';
  }
}

/// Default export (export default expression)
class ExportDefaultDeclaration extends ExportDeclaration {
  final Expression declaration;

  const ExportDefaultDeclaration({
    required this.declaration,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) =>
      visitor.visitExportDefaultDeclaration(this);

  @override
  String toString() => 'ExportDefaultDeclaration($declaration)';
}

/// Export all exports of a module (export * from 'module')
class ExportAllDeclaration extends ExportDeclaration {
  final LiteralExpression source;
  final Expression?
  exported; // for export * as name from 'module' (can be identifier or string)

  const ExportAllDeclaration({
    required this.source,
    this.exported,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitExportAllDeclaration(this);

  @override
  String toString() {
    if (exported != null) {
      return 'ExportAllDeclaration(* as $exported from $source)';
    }
    return 'ExportAllDeclaration(* from $source)';
  }
}

/// Export of declaration (export const/let/var/function/class)
class ExportDeclarationStatement extends ExportDeclaration {
  final Statement declaration;

  const ExportDeclarationStatement({
    required this.declaration,
    required super.line,
    required super.column,
  });

  @override
  T accept<T>(ASTVisitor<T> visitor) => visitor.visitExportDeclaration(this);

  @override
  String toString() => 'ExportDeclarationStatement($declaration)';
}
