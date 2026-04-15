/// Bytecode compiler: walks the AST and emits bytecode instructions.
///
/// Implements the ASTVisitor pattern to traverse AST nodes and produce
/// FunctionBytecode objects. The compilation is done per-function:
/// each function/script becomes its own FunctionBytecode with its own constant
/// pool, local variable table, and bytecode buffer.
library;

import '../runtime/js_value.dart';
import '../parser/ast_nodes.dart';
import 'bytecode.dart';
import 'opcodes.dart';

/// Scope tracking during compilation (for resolving variable access)
class _Scope {
  final _Scope? parent;

  /// Variables declared in this scope: name -> local slot index
  final Map<String, int> vars = {};

  /// Is this a function-level scope (vs block scope)?
  final bool isFunctionScope;

  /// Scope depth (0 = function scope, incremented for each block)
  final int depth;

  /// Tracked `using` declarations: (slot, isAsync) for disposal at scope exit
  final List<({int slot, bool isAsync})> usingDisposals = [];

  _Scope({this.parent, this.isFunctionScope = false, required this.depth});
}

/// Label target for break/continue in loops
class _LabelTarget {
  /// Label name (null for unlabeled loops)
  final String? label;

  /// Whether this target supports an unlabeled `break`.
  final bool isBreakTarget;

  /// Whether this target supports `continue`.
  final bool isLoopTarget;

  /// Bytecode offsets to patch for 'break' jumps
  final List<int> breakPatches = [];

  /// Bytecode offsets to patch for 'continue' jumps
  final List<int> continuePatches = [];

  /// Stack depth at the loop entry (for cleaning up)
  final int stackDepth;

  /// Number of active finally blocks at the jump target.
  final int finallyDepth;

  _LabelTarget({
    this.label,
    required this.stackDepth,
    required this.finallyDepth,
    this.isBreakTarget = false,
    this.isLoopTarget = false,
  });
}

/// Context for compiling one function (or the top-level script).
///
/// Each function gets its own _FunctionContext with its own bytecode builder,
/// constant pool, variable table, etc.
class _FunctionContext {
  /// The enclosing function context (null for top-level)
  final _FunctionContext? parent;

  /// Bytecode builder for this function
  final BytecodeBuilder builder = BytecodeBuilder();

  /// Constant pool: strings, numbers, nested FunctionBytecodes, etc.
  final List<Object> constantPool = [];

  /// Local variables: name -> slot index
  final List<VarDef> vars = [];

  /// Arguments: name -> slot index (separate from locals)
  final List<String> argNames = [];

  /// Closure variable definitions
  final List<ClosureVarDef> closureVars = [];

  /// Current scope
  late _Scope scope;

  /// Loop/label target stack
  final List<_LabelTarget> labelStack = [];

  /// Pending label for the next loop (set by visitLabeledStatement)
  String? pendingLabel;

  /// Name of the variable holding the super class reference (for class constructors/methods)
  String? superVarName;

  /// Maximum stack depth (tracked during compilation)
  int maxStackDepth = 0;
  int _currentStackDepth = 0;

  /// Function name
  final String name;

  /// Function kind
  final FunctionKind kind;

  /// Is strict mode?
  bool isStrict;

  /// Number of declared parameters
  final int argCount;

  /// Function.length value (params before first rest/default)
  int expectedArgCount;

  /// Has rest parameter?
  final bool hasRest;

  /// Whether this function is compiled within an outer dynamic with-scope.
  final bool capturesWithScope;

  /// Number of locals created before body var/function hoisting.
  int parameterVarCount = 0;

  /// Bytecode offset where the function body starts after parameter setup.
  int bodyStartPc = 0;

  _FunctionContext({
    this.parent,
    this.name = '',
    this.kind = FunctionKind.normal,
    this.isStrict = false,
    this.argCount = 0,
    this.expectedArgCount = 0,
    this.hasRest = false,
    this.capturesWithScope = false,
  }) {
    scope = _Scope(isFunctionScope: true, depth: 0);
  }

  /// Track stack depth changes for computing maxStackDepth
  void adjustStack(int delta) {
    _currentStackDepth += delta;
    if (_currentStackDepth > maxStackDepth) {
      maxStackDepth = _currentStackDepth;
    }
  }

  /// Add a constant to the pool, returns its index
  int addConstant(Object value) {
    // Deduplicate string and number constants
    for (var i = 0; i < constantPool.length; i++) {
      final existing = constantPool[i];
      if (existing is String && value is String && existing == value) return i;
      if (existing is double && value is double && identical(existing, value)) {
        return i;
      }
      if (existing is int && value is int && existing == value) return i;
    }
    constantPool.add(value);
    return constantPool.length - 1;
  }

  /// Declare a local variable, returns its slot index
  int declareLocal(
    String name, {
    VarScope scope = VarScope.blockScope,
    bool isConst = false,
    bool isLexical = false,
    int scopeLevel = 0,
  }) {
    var targetScope = this.scope;
    if (scope == VarScope.funcScope) {
      while (!targetScope.isFunctionScope && targetScope.parent != null) {
        targetScope = targetScope.parent!;
      }
    }

    final existing = targetScope.vars[name];
    if (existing != null) {
      return existing;
    }

    final index = vars.length;
    vars.add(
      VarDef(
        name: name,
        scope: scope,
        isConst: isConst,
        isLexical: isLexical,
        scopeLevel: scope == VarScope.funcScope
            ? targetScope.depth
            : scopeLevel,
      ),
    );
    targetScope.vars[name] = index;
    return index;
  }

  /// Declare an argument, returns its slot index
  int declareArg(String name) {
    final index = argNames.length;
    argNames.add(name);
    scope.vars[name] = -(index + 1); // Negative to distinguish from locals
    return index;
  }

  /// Resolve a variable name in current scope chain.
  /// Returns (kind, index) where kind indicates if it's local, arg, closure, or global.
  _VarResolution resolveVar(String name) {
    // Walk up scopes in this function
    var s = scope;
    while (true) {
      if (s.vars.containsKey(name)) {
        final idx = s.vars[name]!;
        if (idx < 0) {
          // Argument
          return _VarResolution(_VarKind.arg, -(idx + 1));
        } else {
          // Local
          return _VarResolution(_VarKind.local, idx);
        }
      }
      if (s.parent != null) {
        s = s.parent!;
      } else {
        break;
      }
    }

    // Check closure vars
    for (var i = 0; i < closureVars.length; i++) {
      if (closureVars[i].name == name) {
        return _VarResolution(_VarKind.closureVar, i);
      }
    }

    // Try to capture from parent function
    if (parent != null) {
      final parentRes = parent!.resolveVar(name);
      if (parentRes.kind != _VarKind.global) {
        return _captureFromParent(name, parentRes);
      }
    }

    // Global
    return _VarResolution(_VarKind.global, 0);
  }

  /// Capture a variable from the parent function as a closure variable
  _VarResolution _captureFromParent(String name, _VarResolution parentRes) {
    // Check if already captured
    for (var i = 0; i < closureVars.length; i++) {
      if (closureVars[i].name == name) {
        return _VarResolution(_VarKind.closureVar, i);
      }
    }

    // Create new closure variable definition
    final ClosureVarKind cvKind;
    var isConst = false;
    var isLexical = false;
    switch (parentRes.kind) {
      case _VarKind.local:
        cvKind = ClosureVarKind.local;
        // Mark the parent local as captured
        if (parentRes.index < parent!.vars.length) {
          parent!.vars[parentRes.index].isCaptured = true;
          isConst = parent!.vars[parentRes.index].isConst;
          isLexical = parent!.vars[parentRes.index].isLexical;
        }
      case _VarKind.arg:
        cvKind = ClosureVarKind.arg;
      case _VarKind.closureVar:
        cvKind = ClosureVarKind.varRef;
        if (parentRes.index < parent!.closureVars.length) {
          isConst = parent!.closureVars[parentRes.index].isConst;
          isLexical = parent!.closureVars[parentRes.index].isLexical;
        }
      case _VarKind.global:
        // Shouldn't happen (we checked above)
        return _VarResolution(_VarKind.global, 0);
    }

    final cvIndex = closureVars.length;
    closureVars.add(
      ClosureVarDef(
        name: name,
        kind: cvKind,
        index: parentRes.index,
        isConst: isConst,
        isLexical: isLexical,
      ),
    );
    return _VarResolution(_VarKind.closureVar, cvIndex);
  }

  /// Push a new block scope
  void pushScope() {
    scope = _Scope(parent: scope, depth: scope.depth + 1);
  }

  /// Pop a block scope
  void popScope() {
    scope = scope.parent!;
  }

  /// Build the final FunctionBytecode
  FunctionBytecode buildFunction() {
    final func = FunctionBytecode(
      name: name,
      kind: kind,
      isStrict: isStrict,
      argCount: argCount,
      argNames: List.of(argNames),
      expectedArgCount: expectedArgCount,
      parameterVarCount: parameterVarCount,
      bodyStartPc: bodyStartPc,
      hasRest: hasRest,
      vars: List.of(vars),
      stackSize: maxStackDepth + 4, // margin for safety
      constantPool: List.of(constantPool),
      closureVars: List.of(closureVars),
      moduleExportBindings: const {},
    );
    func.bytecode = builder.build();
    func.sourceMap = builder.sourceMappings.isEmpty
        ? null
        : List.of(builder.sourceMappings);
    return func;
  }
}

enum _VarKind { local, arg, closureVar, global }

class _VarResolution {
  final _VarKind kind;
  final int index;
  const _VarResolution(this.kind, this.index);
}

// ================================================================
// The Compiler (AST Visitor)
// ================================================================

/// Compiles an AST (Program) into bytecode.
///
/// Usage:
///   final compiler = BytecodeCompiler();
///   final bytecode = compiler.compile(program);
class BytecodeCompiler implements ASTVisitor<void> {
  /// Stack of function contexts (top = current function being compiled)
  final List<_FunctionContext> _funcStack = [];

  /// Stack of private names visible in the current enclosing class.
  /// Values are the unique storage keys used for brand separation per class.
  final List<Map<String, String>> _privateNameStack = [];

  /// Whether the current compiled class method is static.
  final List<bool> _staticMethodStack = [];

  /// Enclosing finally blocks for the current compile location.
  final List<BlockStatement> _finallyBlockStack = [];

  /// Function declarations instantiated in the current script/function prelude.
  final List<Set<Statement>> _hoistedFunctionDeclStack = [];

  /// Nesting depth of try/catch blocks. TCO is disabled when > 0.
  int _tryCatchDepth = 0;

  /// When true, the next call expression should emit Op.tailCall instead of
  /// Op.call, and the caller (visitReturnStatement) will skip emitting return_.
  bool _inTailPosition = false;

  /// Name for ES6 function name inference (e.g. `var f = function() {}` → name is 'f').
  String? _pendingFunctionName;

  /// Source text override for the next compiled function expression.
  String? _pendingFunctionSourceText;

  /// Module URL for import.meta (set when compiling a module)
  String? moduleUrl;

  /// Number of active with statements in the current function body.
  int _withDepth = 0;

  int _privateScopeCounter = 0;

  /// Collected export mappings: exportName -> localVarName
  /// Used during module compilation to create __export__X variables.
  final Map<String, String> _exportBindings = {};

  /// Name of the variable holding the super class in the current class scope.
  /// Set during class body compilation so constructor/method compilation can
  /// emit code to access the superclass.
  String? _superVarName;

  /// Whether [_superVarName] refers to an object-literal home object.
  /// In that case `super` resolves through the object's prototype instead of
  /// `superClass.prototype`.
  bool _superVarIsHomeObject = false;

  int _superHomeObjectCounter = 0;
  int _objectPatternTempCounter = 0;

  /// Extract a property name from an expression that can be IdentifierExpression
  /// or PrivateIdentifierExpression. Used for member access and class keys.
  static String _propName(Expression expr) {
    if (expr is IdentifierExpression) return expr.name;
    if (expr is PrivateIdentifierExpression) return expr.name;
    throw CompileError('Expected identifier property', expr.line);
  }

  Map<String, String>? get _currentPrivateNames =>
      _privateNameStack.isNotEmpty ? _privateNameStack.last : null;

  String _createPrivateStorageName(String name, int scopeId) =>
      '_private_${scopeId}_$name';

  String _getPrivateStorageName(String name) {
    final privateNames = _currentPrivateNames;
    final resolved = privateNames?[name];
    if (resolved == null) {
      throw CompileError(
        "Private field '#$name' must be declared in an enclosing class",
        0,
      );
    }
    return resolved;
  }

  bool get _isInStaticMethod =>
      _staticMethodStack.isNotEmpty && _staticMethodStack.last;

  bool _isAnonymousFunctionDefinition(Expression expr) {
    if (expr is ArrowFunctionExpression ||
        expr is AsyncArrowFunctionExpression) {
      return true;
    }
    if (expr is FunctionExpression) {
      return expr.id == null;
    }
    if (expr is ClassExpression) {
      return expr.id == null;
    }
    return false;
  }

  bool _classDefinesOwnNameProperty(ClassExpression expr) {
    for (final member in expr.body.members) {
      if (member is! MethodDefinition && member is! FieldDeclaration) {
        continue;
      }

      final isStatic = member is MethodDefinition
          ? member.isStatic
          : (member as FieldDeclaration).isStatic;
      if (!isStatic) {
        continue;
      }

      final key = member is MethodDefinition
          ? member.key
          : (member as FieldDeclaration).key;
      final computed = member is MethodDefinition ? member.computed : false;

      if (!computed && key is IdentifierExpression && key.name == 'name') {
        return true;
      }
      if (!computed && key is LiteralExpression && key.value == 'name') {
        return true;
      }
      if (computed && key is LiteralExpression && key.value == 'name') {
        return true;
      }
    }
    return false;
  }

  String? _destructuringTargetName(Pattern pattern) {
    if (pattern is IdentifierPattern) {
      return pattern.name;
    }
    if (pattern is ExpressionPattern &&
        pattern.expression is IdentifierExpression) {
      return (pattern.expression as IdentifierExpression).name;
    }
    return null;
  }

  void _compileWithInferredFunctionName(
    String? name,
    Expression expr,
    void Function() compile,
  ) {
    final suppressClassInference =
        expr is ClassExpression && _classDefinesOwnNameProperty(expr);
    final shouldInfer =
        name != null &&
        name.isNotEmpty &&
        _isAnonymousFunctionDefinition(expr) &&
        !suppressClassInference;
    final previousName = _pendingFunctionName;
    final previousSourceText = _pendingFunctionSourceText;

    if (shouldInfer) {
      _pendingFunctionName = name;
      _pendingFunctionSourceText = expr.toString();
    }

    try {
      compile();
    } finally {
      _pendingFunctionName = previousName;
      _pendingFunctionSourceText = previousSourceText;
    }
  }

  String? _resolveMemberPropertyName(Expression expr) {
    if (expr is IdentifierExpression) {
      return expr.name;
    }
    if (expr is PrivateIdentifierExpression) {
      final privateNames = _currentPrivateNames;
      if (privateNames != null) {
        return privateNames[expr.name];
      }
      return null;
    }
    throw CompileError('Expected identifier property', expr.line);
  }

  int _estimateExpressionEndColumn(Expression expr, int fallbackColumn) {
    if (expr is IdentifierExpression) {
      return expr.column + expr.name.length;
    }
    if (expr is LiteralExpression) {
      final raw = expr.raw;
      if (raw != null) {
        return expr.column + raw.length;
      }
      return expr.column + expr.value.toString().length;
    }
    if (expr is MemberExpression) {
      if (expr.computed) {
        return _estimateExpressionEndColumn(expr.property, fallbackColumn) + 1;
      }
      final name = _resolveMemberPropertyName(expr.property);
      if (name != null) {
        return expr.property.column + name.length;
      }
    }
    return fallbackColumn;
  }

  int _estimateBinaryOperatorColumn(BinaryExpression node) {
    final candidate = node.right.column - node.operator.length - 1;
    if (candidate >= 1) {
      return candidate;
    }
    return node.column;
  }

  int _estimateAssignmentOperatorColumn(AssignmentExpression node) {
    final candidate = node.right.column - node.operator.length - 1;
    if (candidate >= 1) {
      return candidate;
    }
    return node.column;
  }

  int _estimateMemberOperatorColumn(MemberExpression node) {
    final objectEnd = _estimateExpressionEndColumn(node.object, node.column);
    return node.computed ? objectEnd : objectEnd + 1;
  }

  void _emitInvalidPrivateAccess(String name, int line) {
    final atom = _ctx.addConstant(
      "Private field '#$name' must be declared in an enclosing class",
    );
    _bc.setLine(line);
    _bc.emitAtomU8(Op.throwError, atom, 2);
  }

  /// Quick access to current function context
  _FunctionContext get _ctx => _funcStack.last;

  /// Quick access to current bytecode builder
  BytecodeBuilder get _bc => _ctx.builder;

  void _compileInlineFinallyBlock(BlockStatement finalizer) {
    final isCurrent =
        _finallyBlockStack.isNotEmpty &&
        identical(_finallyBlockStack.last, finalizer);
    if (isCurrent) {
      _finallyBlockStack.removeLast();
    }
    try {
      for (final stmt in finalizer.body) {
        stmt.accept(this);
      }
    } finally {
      if (isCurrent) {
        _finallyBlockStack.add(finalizer);
      }
    }
  }

  void _emitPendingFinallyBlocks([int targetDepth = 0]) {
    for (var i = _finallyBlockStack.length - 1; i >= targetDepth; i--) {
      final finalizer = _finallyBlockStack.removeAt(i);
      try {
        for (final stmt in finalizer.body) {
          stmt.accept(this);
        }
      } finally {
        _finallyBlockStack.insert(i, finalizer);
      }
    }
  }

  // -----------------------------------------------------------
  // Public API
  // -----------------------------------------------------------

  /// Compile a parsed Program into a top-level FunctionBytecode.
  ///
  /// For eval semantics: if the last statement is an ExpressionStatement,
  /// its value is returned instead of undefined.
  FunctionBytecode compile(
    Program program, {
    bool? forcedStrictMode,
    String? forcedSuperVarName,
  }) {
    final body = program.body;
    final firstExpr = (body.isNotEmpty && body.first is ExpressionStatement)
        ? (body.first as ExpressionStatement).expression
        : null;
    final isStrictProgram =
        forcedStrictMode ??
        (firstExpr is LiteralExpression &&
            firstExpr.type == 'string' &&
            (() {
              final raw = firstExpr.raw;
              if (raw != null) {
                return raw == "'use strict'" || raw == '"use strict"';
              }
              return firstExpr.value == 'use strict';
            })());

    final savedSuperVarName = _superVarName;
    final savedSuperVarIsHomeObject = _superVarIsHomeObject;
    _superVarName = forcedSuperVarName;
    _superVarIsHomeObject =
        forcedSuperVarName?.startsWith('__super_home_') ?? false;

    _pushFunction(
      name: '<script>',
      kind: FunctionKind.normal,
      isStrict: isStrictProgram,
    );
    _hoistedFunctionDeclStack.add(<Statement>{});
    try {
      _predeclareClassNames(body);
      _hoistVarDeclarations(body);
      _hoistFunctionDeclarations(body);

      // Completion value accumulator: tracks the script's completion value
      // per ECMAScript UpdateEmpty semantics
      final completionSlot = _ctx.declareLocal(
        '#completion',
        scope: VarScope.funcScope,
      );
      _bc.emit(Op.pushUndefined);
      _ctx.adjustStack(1);
      _bc.emitU16(Op.putLoc, completionSlot);
      _ctx.adjustStack(-1);

      for (final stmt in body) {
        _compileStmtUpdatingCompletion(stmt, completionSlot);
      }

      // Return the completion value
      _bc.emitU16(Op.getLoc, completionSlot);
      _ctx.adjustStack(1);
      _bc.emit(Op.return_);
      _ctx.adjustStack(-1);

      return _popFunction();
    } finally {
      _hoistedFunctionDeclStack.removeLast();
      _superVarName = savedSuperVarName;
      _superVarIsHomeObject = savedSuperVarIsHomeObject;
    }
  }

  /// Compile a module Program into a FunctionBytecode.
  /// Export declarations create __export__X local variables.
  FunctionBytecode compileModule(Program program) {
    _exportBindings.clear();

    _pushFunction(
      name: '<module>',
      kind: FunctionKind.normal,
      isStrict: true, // modules are always strict
    );
    _hoistedFunctionDeclStack.add(<Statement>{});
    try {
      _predeclareClassNames(program.body);
      _hoistFunctionDeclarations(program.body);

      // First pass: pre-declare all exported variable names
      // so that export { x } can reference them
      for (final stmt in program.body) {
        _collectExportBindings(stmt);
      }

      // Compile all statements
      for (final stmt in program.body) {
        stmt.accept(this);
      }

      // Copy exported bindings to __export__X variables
      for (final entry in _exportBindings.entries) {
        final exportName = entry.key;
        final localName = entry.value;

        // Declare __export__X variable
        final exportSlot = _ctx.declareLocal(
          '__export__$exportName',
          scope: VarScope.funcScope,
        );

        // Load the local value
        final res = _ctx.resolveVar(localName);
        if (res.kind == _VarKind.local) {
          _bc.emitU16(Op.getLoc, res.index);
        } else if (res.kind == _VarKind.global) {
          final atom = _ctx.addConstant(localName);
          _bc.emitU32(Op.getVar, atom);
        } else {
          _bc.emit(Op.pushUndefined);
        }
        _ctx.adjustStack(1);

        _bc.emitU16(Op.putLoc, exportSlot);
        _ctx.adjustStack(-1);
      }

      _bc.emit(Op.returnUndef);
      _ctx.adjustStack(0);

      final function = _popFunction();
      function.moduleExportBindings = Map<String, String>.from(_exportBindings);
      return function;
    } finally {
      _hoistedFunctionDeclStack.removeLast();
    }
  }

  /// Compile a standalone AST-backed JSFunction into bytecode.
  ///
  /// This is used to lazily promote legacy AST functions to VM-executable
  /// functions when they don't rely on non-global lexical captures.
  FunctionBytecode compileJSFunction(JSFunction function) {
    final declaration = function.declaration;
    if (declaration is MethodDefinition) {
      final method = declaration.value;
      final methodKind = method is AsyncFunctionExpression
          ? (method.isGenerator
                ? FunctionKind.asyncGenerator
                : FunctionKind.asyncFunction)
          : (method.isGenerator ? FunctionKind.generator : FunctionKind.normal);
      return _compileFunction(
        name: function.functionName,
        kind: methodKind,
        params: method.params,
        body: method.body,
        isStrict: function.strictMode,
        sourceText: function.sourceText,
      );
    }
    if (declaration is FunctionDeclaration) {
      return _compileFunction(
        name: declaration.id.name,
        kind: declaration.isGenerator
            ? FunctionKind.generator
            : FunctionKind.normal,
        params: declaration.params,
        body: declaration.body,
        isStrict: function.strictMode,
        sourceText: function.sourceText,
      );
    }
    if (declaration is AsyncFunctionDeclaration) {
      return _compileFunction(
        name: declaration.id.name,
        kind: declaration.isGenerator
            ? FunctionKind.asyncGenerator
            : FunctionKind.asyncFunction,
        params: declaration.params,
        body: declaration.body,
        isStrict: function.strictMode,
        sourceText: function.sourceText,
      );
    }
    if (declaration is FunctionExpression) {
      return _compileFunction(
        name: declaration.id?.name ?? function.functionName,
        kind: declaration.isGenerator
            ? FunctionKind.generator
            : FunctionKind.normal,
        params: declaration.params,
        body: declaration.body,
        isStrict: function.strictMode,
        sourceText: function.sourceText,
      );
    }
    if (declaration is AsyncFunctionExpression) {
      return _compileFunction(
        name: declaration.id?.name ?? function.functionName,
        kind: declaration.isGenerator
            ? FunctionKind.asyncGenerator
            : FunctionKind.asyncFunction,
        params: declaration.params,
        body: declaration.body,
        isStrict: function.strictMode,
        sourceText: function.sourceText,
      );
    }
    if (declaration is ArrowFunctionExpression) {
      return _compileFunction(
        name: function.functionName == 'anonymous' ? '' : function.functionName,
        kind: FunctionKind.arrow,
        params: declaration.params,
        body: declaration.body,
        isStrict: function.strictMode,
        sourceText: function.sourceText,
      );
    }
    if (declaration is AsyncArrowFunctionExpression) {
      return _compileFunction(
        name: function.functionName == 'anonymous' ? '' : function.functionName,
        kind: FunctionKind.asyncArrow,
        params: declaration.params,
        body: declaration.body,
        isStrict: function.strictMode,
        sourceText: function.sourceText,
      );
    }
    throw ArgumentError(
      'Unsupported JSFunction declaration type: ${declaration.runtimeType}',
    );
  }

  /// Compile a standalone AST-backed JSFunction while modeling a set of
  /// outer bindings as the enclosing function scope.
  FunctionBytecode compileJSFunctionWithOuterBindings(
    JSFunction function,
    Iterable<String> outerBindings,
  ) {
    final bindingNames = outerBindings.toSet().toList()..sort();
    if (bindingNames.isEmpty) {
      return compileJSFunction(function);
    }

    _pushFunction(
      name: '<capture-analysis>',
      kind: FunctionKind.normal,
      isStrict: function.strictMode,
    );
    try {
      for (final name in bindingNames) {
        _ctx.declareLocal(name, scope: VarScope.funcScope);
      }
      return compileJSFunction(function);
    } finally {
      _popFunction();
    }
  }

  /// Returns true if compiling this function against the given outer bindings
  /// would create closure captures.
  bool capturesOuterBindings(
    JSFunction function,
    Iterable<String> outerBindings,
  ) {
    final bytecode = compileJSFunctionWithOuterBindings(
      function,
      outerBindings,
    );
    return bytecode.closureVars.isNotEmpty;
  }

  /// Collect export bindings from a statement.
  void _collectExportBindings(Statement stmt) {
    if (stmt is ExportDeclarationStatement) {
      final decl = stmt.declaration;
      if (decl is VariableDeclaration) {
        for (final d in decl.declarations) {
          final name = _getDeclaratorName(d);
          _exportBindings[name] = name;
        }
      } else if (decl is FunctionDeclaration) {
        _exportBindings[decl.id.name] = decl.id.name;
      } else if (decl is AsyncFunctionDeclaration) {
        _exportBindings[decl.id.name] = decl.id.name;
      } else if (decl is ClassDeclaration && decl.id != null) {
        _exportBindings[decl.id!.name] = decl.id!.name;
      }
    } else if (stmt is ExportDefaultDeclaration) {
      _exportBindings['default'] = 'default';
    } else if (stmt is ExportNamedDeclaration) {
      for (final spec in stmt.specifiers) {
        _exportBindings[spec.exported.name] = spec.local.name;
      }
    }
  }

  void _compileStatementForCompletion(Statement stmt) {
    if (stmt is ExpressionStatement) {
      stmt.expression.accept(this);
      return;
    }
    if (stmt is TryStatement) {
      _compileTryStatementForCompletion(stmt);
      return;
    }
    if (stmt is IfStatement) {
      _compileIfForCompletion(stmt);
      return;
    }
    if (stmt is BlockStatement) {
      _compileScopedBlockForCompletion(stmt);
      return;
    }

    stmt.accept(this);
    _bc.emit(Op.pushUndefined);
    _ctx.adjustStack(1);
  }

  /// Compile an IfStatement in "completion" mode: leaves exactly one value
  /// on the stack (the completion value of the taken branch).
  void _compileIfForCompletion(IfStatement node) {
    _bc.setLine(node.line);
    node.test.accept(this);

    if (node.alternate != null) {
      final elsePatch = _bc.emitJump(Op.ifFalse);
      _ctx.adjustStack(-1);
      _compileBranchForCompletion(node.consequent);
      final endPatch = _bc.emitJump(Op.goto_);
      _ctx.adjustStack(-1); // reset for else-branch analysis
      _bc.patchJump(elsePatch, _bc.offset);
      _compileBranchForCompletion(node.alternate!);
      _bc.patchJump(endPatch, _bc.offset);
    } else {
      final elsePatch = _bc.emitJump(Op.ifFalse);
      _ctx.adjustStack(-1);
      _compileBranchForCompletion(node.consequent);
      final endPatch = _bc.emitJump(Op.goto_);
      _ctx.adjustStack(-1); // reset for false-path analysis
      _bc.patchJump(elsePatch, _bc.offset);
      _bc.emit(Op.pushUndefined);
      _ctx.adjustStack(1);
      _bc.patchJump(endPatch, _bc.offset);
    }
  }

  /// Compile a branch (consequent or alternate of an if) for completion.
  void _compileBranchForCompletion(Statement branch) {
    if (branch is BlockStatement) {
      _compileScopedBlockForCompletion(branch);
    } else {
      _compileStatementForCompletion(branch);
    }
  }

  void _compileScopedBlockForCompletion(BlockStatement block) {
    _ctx.pushScope();
    _predeclareClassNames(block.body);
    _compileBlockForCompletion(block);
    _emitScopeDisposals();
    _ctx.popScope();
  }

  void _compileBlockForCompletion(BlockStatement block) {
    if (block.body.isEmpty) {
      _bc.emit(Op.pushUndefined);
      _ctx.adjustStack(1);
      return;
    }

    for (var i = 0; i < block.body.length; i++) {
      final stmt = block.body[i];
      final isLast = i == block.body.length - 1;
      if (isLast) {
        _compileStatementForCompletion(stmt);
      } else {
        stmt.accept(this);
      }
    }
  }

  /// Compile a statement updating the completion accumulator slot.
  /// Per ECMAScript UpdateEmpty: only expression statements, blocks containing
  /// expression statements, and control flow that reaches expression statements
  /// update the completion value; everything else preserves it.
  void _compileStmtUpdatingCompletion(Statement stmt, int slot) {
    if (stmt is ExpressionStatement) {
      stmt.expression.accept(this);
      _bc.emitU16(Op.putLoc, slot);
      _ctx.adjustStack(-1);
    } else if (stmt is BlockStatement) {
      _ctx.pushScope();
      _predeclareClassNames(stmt.body);
      for (final s in stmt.body) {
        _compileStmtUpdatingCompletion(s, slot);
      }
      _emitScopeDisposals();
      _ctx.popScope();
    } else if (stmt is LabeledStatement) {
      // Labeled non-loop: the body's completion updates the accumulator
      final body = stmt.body;
      final isLoop =
          body is WhileStatement ||
          body is DoWhileStatement ||
          body is ForStatement ||
          body is ForInStatement ||
          body is ForOfStatement;
      if (isLoop) {
        _ctx.pendingLabel = stmt.label;
        stmt.body.accept(this);
      } else {
        final target = _LabelTarget(
          label: stmt.label,
          stackDepth: _ctx._currentStackDepth,
          finallyDepth: _finallyBlockStack.length,
        );
        _ctx.labelStack.add(target);
        _compileStmtUpdatingCompletion(stmt.body, slot);
        _patchJumpsHere(target.breakPatches);
        _ctx.labelStack.removeLast();
      }
    } else if (stmt is IfStatement) {
      _bc.setLine(stmt.line);
      stmt.test.accept(this);
      if (stmt.alternate != null) {
        final elsePatch = _bc.emitJump(Op.ifFalse);
        _ctx.adjustStack(-1);
        _compileStmtUpdatingCompletion(stmt.consequent, slot);
        final endPatch = _bc.emitJump(Op.goto_);
        _bc.patchJump(elsePatch, _bc.offset);
        _compileStmtUpdatingCompletion(stmt.alternate!, slot);
        _bc.patchJump(endPatch, _bc.offset);
      } else {
        final endPatch = _bc.emitJump(Op.ifFalse);
        _ctx.adjustStack(-1);
        _compileStmtUpdatingCompletion(stmt.consequent, slot);
        _bc.patchJump(endPatch, _bc.offset);
      }
    } else if (stmt is TryStatement) {
      _compileTryStatementForCompletion(stmt);
      _bc.emitU16(Op.putLoc, slot);
      _ctx.adjustStack(-1);
    } else {
      // All other statements (including function declarations):
      // compile normally, don't update completion value.
      // Per spec, function declarations have completion value "empty".
      stmt.accept(this);
    }
  }

  void _compileTryStatementForCompletion(TryStatement node) {
    _bc.setLine(node.line);

    void emitFinallyBlock() {
      if (node.finalizer != null) {
        _compileInlineFinallyBlock(node.finalizer!);
      }
    }

    if (node.finalizer != null) {
      _finallyBlockStack.add(node.finalizer!);
    }
    try {
      if (node.handler != null && node.finalizer != null) {
        final catchPatch = _bc.emitJump(Op.catch_);

        _compileScopedBlockForCompletion(node.block);
        _bc.emit(Op.uncatch);

        emitFinallyBlock();
        final endPatch = _bc.emitJump(Op.goto_);

        _bc.patchJump(catchPatch, _bc.offset);

        final catchRethrowPatch = _bc.emitJump(Op.catch_);

        _ctx.pushScope();
        _ctx.adjustStack(1);
        if (node.handler!.param != null) {
          final name = node.handler!.param!.name;
          final slot = _ctx.declareLocal(name, scopeLevel: _ctx.scope.depth);
          _bc.emitU16(Op.putLoc, slot);
          _ctx.adjustStack(-1);
        } else {
          _bc.emit(Op.drop);
          _ctx.adjustStack(-1);
        }

        _compileScopedBlockForCompletion(node.handler!.body);
        _ctx.popScope();

        _bc.emit(Op.uncatch);
        emitFinallyBlock();
        final endPatch2 = _bc.emitJump(Op.goto_);

        _bc.patchJump(catchRethrowPatch, _bc.offset);
        _ctx.adjustStack(1);
        final tempSlot = _ctx.declareLocal(
          '__finally_exc_${_bc.offset}',
          scopeLevel: _ctx.scope.depth,
        );
        _bc.emitU16(Op.putLoc, tempSlot);
        _ctx.adjustStack(-1);

        emitFinallyBlock();

        _bc.emitU16(Op.getLoc, tempSlot);
        _ctx.adjustStack(1);
        _bc.emit(Op.throw_);
        _ctx.adjustStack(-1);

        _bc.patchJump(endPatch, _bc.offset);
        _bc.patchJump(endPatch2, _bc.offset);
        return;
      }

      if (node.handler != null) {
        final catchPatch = _bc.emitJump(Op.catch_);

        _compileScopedBlockForCompletion(node.block);
        _bc.emit(Op.uncatch);
        final endPatch = _bc.emitJump(Op.goto_);

        _bc.patchJump(catchPatch, _bc.offset);

        _ctx.pushScope();
        _ctx.adjustStack(1);
        if (node.handler!.param != null) {
          final name = node.handler!.param!.name;
          final slot = _ctx.declareLocal(name, scopeLevel: _ctx.scope.depth);
          _bc.emitU16(Op.putLoc, slot);
          _ctx.adjustStack(-1);
        } else {
          _bc.emit(Op.drop);
          _ctx.adjustStack(-1);
        }

        _compileScopedBlockForCompletion(node.handler!.body);
        _ctx.popScope();

        _bc.patchJump(endPatch, _bc.offset);
        return;
      }

      if (node.finalizer != null) {
        final catchPatch = _bc.emitJump(Op.catch_);

        _compileScopedBlockForCompletion(node.block);
        _bc.emit(Op.uncatch);

        emitFinallyBlock();
        final endPatch = _bc.emitJump(Op.goto_);

        _bc.patchJump(catchPatch, _bc.offset);
        _ctx.adjustStack(1);
        final tempSlot = _ctx.declareLocal(
          '__finally_exc_${_bc.offset}',
          scopeLevel: _ctx.scope.depth,
        );
        _bc.emitU16(Op.putLoc, tempSlot);
        _ctx.adjustStack(-1);

        emitFinallyBlock();

        _bc.emitU16(Op.getLoc, tempSlot);
        _ctx.adjustStack(1);
        _bc.emit(Op.throw_);
        _ctx.adjustStack(-1);

        _bc.patchJump(endPatch, _bc.offset);
        return;
      }

      _bc.emit(Op.pushUndefined);
      _ctx.adjustStack(1);
    } finally {
      if (node.finalizer != null) {
        _finallyBlockStack.removeLast();
      }
    }
  }

  // -----------------------------------------------------------
  // Function context management
  // -----------------------------------------------------------

  void _pushFunction({
    String name = '',
    FunctionKind kind = FunctionKind.normal,
    bool isStrict = false,
    int argCount = 0,
    int expectedArgCount = 0,
    bool hasRest = false,
  }) {
    _funcStack.add(
      _FunctionContext(
        parent: _funcStack.isEmpty ? null : _funcStack.last,
        name: name,
        kind: kind,
        isStrict: isStrict,
        argCount: argCount,
        expectedArgCount: expectedArgCount,
        hasRest: hasRest,
        capturesWithScope:
            _withDepth > 0 ||
            (_funcStack.isNotEmpty && _funcStack.last.capturesWithScope),
      ),
    );
  }

  FunctionBytecode _popFunction() {
    final ctx = _funcStack.removeLast();
    return ctx.buildFunction();
  }

  // -----------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------

  /// Emit a get-variable instruction for the given name
  void _emitGetVar(String name, int line, [int column = 0]) {
    _bc.setLine(line, column);
    final res = _ctx.resolveVar(name);
    if (_shouldUseWithLookup(res)) {
      final atom = _ctx.addConstant(name);
      _bc.emitU32(Op.withGetVar, atom);
      _ctx.adjustStack(1);
      return;
    }
    switch (res.kind) {
      case _VarKind.arg:
        if (res.index <= 3) {
          _bc.emit([Op.getArg0, Op.getArg1, Op.getArg2, Op.getArg3][res.index]);
        } else {
          _bc.emitU16(Op.getArg, res.index);
        }
      case _VarKind.local:
        if (res.index <= 3) {
          _bc.emit([Op.getLoc0, Op.getLoc1, Op.getLoc2, Op.getLoc3][res.index]);
        } else {
          _bc.emitU16(Op.getLoc, res.index);
        }
      case _VarKind.closureVar:
        _bc.emitU16(Op.getVarRef, res.index);
      case _VarKind.global:
        final atom = _ctx.addConstant(name);
        _bc.emitU32(Op.getVar, atom);
    }
    _ctx.adjustStack(1);
  }

  /// Emit a put-variable instruction (assigns and pops)
  void _emitPutVar(String name, int line, [int column = 0]) {
    _bc.setLine(line, column);
    final res = _ctx.resolveVar(name);
    if (_shouldUseWithLookup(res)) {
      final atom = _ctx.addConstant(name);
      _bc.emitU32(Op.captureVarRef, atom);
      _ctx.adjustStack(1);
      _bc.emit(Op.putCapturedVar);
      _ctx.adjustStack(-2);
      return;
    }
    switch (res.kind) {
      case _VarKind.arg:
        _bc.emitU16(Op.putArg, res.index);
      case _VarKind.local:
        if (res.index <= 3) {
          _bc.emit([Op.putLoc0, Op.putLoc1, Op.putLoc2, Op.putLoc3][res.index]);
        } else {
          _bc.emitU16(Op.putLoc, res.index);
        }
      case _VarKind.closureVar:
        _bc.emitU16(Op.putVarRef, res.index);
      case _VarKind.global:
        final atom = _ctx.addConstant(name);
        _bc.emitU32(Op.putVar, atom);
    }
    _ctx.adjustStack(-1);
  }

  /// Emit a set-variable instruction (assigns but keeps value on stack)
  void _emitSetVar(String name, int line, [int column = 0]) {
    _bc.setLine(line, column);
    final res = _ctx.resolveVar(name);
    if (_shouldUseWithLookup(res)) {
      final atom = _ctx.addConstant(name);
      _bc.emitU32(Op.captureVarRef, atom);
      _ctx.adjustStack(1);
      _bc.emit(Op.setCapturedVar);
      _ctx.adjustStack(-1);
      return;
    }
    switch (res.kind) {
      case _VarKind.arg:
        _bc.emitU16(Op.setArg, res.index);
      case _VarKind.local:
        _bc.emitU16(Op.setLoc, res.index);
      case _VarKind.closureVar:
        _bc.emitU16(Op.setVarRef, res.index);
      case _VarKind.global:
        // For globals, dup + put
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        final atom = _ctx.addConstant(name);
        _bc.emitU32(Op.putVar, atom);
        _ctx.adjustStack(-1);
    }
  }

  bool _shouldUseWithLookup(_VarResolution resolution) {
    if (_withDepth > 0) {
      return true;
    }
    if (!_ctx.capturesWithScope) {
      return false;
    }
    return resolution.kind == _VarKind.closureVar ||
        resolution.kind == _VarKind.global;
  }

  /// Emit pushing a number constant (optimized for common values)
  void _emitNumber(double value, int line, [int column = 0]) {
    _bc.setLine(line, column);
    // Optimize common integer values
    if (value == value.truncateToDouble() && value >= 0 && value <= 7) {
      final i = value.toInt();
      _bc.emit(
        [
          Op.push0,
          Op.push1,
          Op.push2,
          Op.push3,
          Op.push4,
          Op.push5,
          Op.push6,
          Op.push7,
        ][i],
      );
    } else if (value == value.truncateToDouble() &&
        value >= -2147483648 &&
        value <= 2147483647) {
      _bc.emitI32(Op.pushI32, value.toInt());
    } else {
      _bc.emitF64(Op.pushF64, value);
    }
    _ctx.adjustStack(1);
  }

  /// Emit pushing a string constant
  void _emitString(String value, int line, [int column = 0]) {
    _bc.setLine(line, column);
    if (value.isEmpty) {
      _bc.emit(Op.pushEmptyString);
    } else {
      final idx = _ctx.addConstant(value);
      _bc.emitU16(Op.pushConst, idx);
    }
    _ctx.adjustStack(1);
  }

  void _emitBigInt(BigInt value, int line, [int column = 0]) {
    _bc.setLine(line, column);
    final idx = _ctx.addConstant(value);
    _bc.emitU16(Op.pushConst, idx);
    _ctx.adjustStack(1);
  }

  void _emitSuperBase(int line) {
    _emitGetVar(_superVarName!, line);
    if (_superVarIsHomeObject) {
      final protoAtom = _ctx.addConstant('__proto__');
      _bc.emitU32(Op.getField, protoAtom);
    } else if (!_isInStaticMethod) {
      final protoAtom = _ctx.addConstant('prototype');
      _bc.emitU32(Op.getField, protoAtom);
    }
  }

  T _withSuperBinding<T>(
    String? superVarName,
    bool isHomeObject,
    T Function() callback,
  ) {
    final savedSuperVarName = _superVarName;
    final savedSuperVarIsHomeObject = _superVarIsHomeObject;
    _superVarName = superVarName;
    _superVarIsHomeObject = isHomeObject;
    try {
      return callback();
    } finally {
      _superVarName = savedSuperVarName;
      _superVarIsHomeObject = savedSuperVarIsHomeObject;
    }
  }

  /// Patch all jumps in a list to the current offset
  void _patchJumpsHere(List<int> patches) {
    final target = _bc.offset;
    for (final p in patches) {
      _bc.patchJump(p, target);
    }
  }

  // -----------------------------------------------------------
  // Compile a function body (used for function declarations/expressions)
  // -----------------------------------------------------------

  FunctionBytecode _compileFunction({
    String name = '',
    FunctionKind kind = FunctionKind.normal,
    required List<Parameter> params,
    required dynamic body, // BlockStatement or Expression
    bool isStrict = false,
    int? sourceLine,
    int? sourceColumn,
    String? sourceText,
  }) {
    // Save and restore tail-position flag so that an outer `return <funcExpr>`
    // does not leak _inTailPosition into the inner function's body.
    final savedTailPosition = _inTailPosition;
    _inTailPosition = false;

    final nonRestCount = params.where((p) => !p.isRest).length;
    final hasRest = params.any((p) => p.isRest);

    // Function.length: count params before the first rest or default param
    var expectedArgCount = 0;
    for (final param in params) {
      if (param.isRest || param.defaultValue != null) break;
      expectedArgCount++;
    }

    // Detect function-level 'use strict' directive
    bool funcIsStrict =
        isStrict ||
        (_funcStack.isNotEmpty && _ctx.isStrict); // inherit from parent
    if (!funcIsStrict && body is BlockStatement && body.body.isNotEmpty) {
      final first = body.body.first;
      if (first is ExpressionStatement &&
          first.expression is LiteralExpression) {
        final lit = first.expression as LiteralExpression;
        final raw = lit.raw;
        if (raw != null) {
          funcIsStrict = raw == "'use strict'" || raw == '"use strict"';
        } else {
          funcIsStrict = lit.value == 'use strict';
        }
      }
    }

    _pushFunction(
      name: name,
      kind: kind,
      isStrict: funcIsStrict,
      argCount: nonRestCount + (hasRest ? 1 : 0),
      expectedArgCount: expectedArgCount,
      hasRest: hasRest,
    );
    _hoistedFunctionDeclStack.add(<Statement>{});
    try {
      // Declare parameters as args
      for (final param in params) {
        if (param.isRest) {
          // Rest parameter is the last arg slot — VM will fill it with a JSArray
          final restName = param.name?.name ?? '_rest';
          _ctx.declareArg(restName);
          break;
        }
        final paramName = param.name?.name ?? '_p${_ctx.argNames.length}';
        _ctx.declareArg(paramName);
      }

      // Named functions need a self-binding so recursive references like
      // `function fact() { return fact(); }` resolve inside bytecode mode.
      if (name.isNotEmpty &&
          kind != FunctionKind.arrow &&
          kind != FunctionKind.asyncArrow) {
        _ctx.declareLocal(name, scope: VarScope.funcScope);
      }

      if (_superVarName != null && _ctx.parent != null) {
        // Keep the enclosing super binding visible to this frame even when the
        // only use is indirect (for example through direct eval in an arrow).
        _emitGetVar(_superVarName!, 0);
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
      }

      // Create 'arguments' object for non-arrow functions
      // Arrow functions inherit 'arguments' from their enclosing function
      if (kind != FunctionKind.arrow && kind != FunctionKind.asyncArrow) {
        final hasSimpleParameterList =
            !funcIsStrict &&
            !params.any(
              (param) =>
                  param.isRest ||
                  param.isDestructuring ||
                  param.defaultValue != null,
            );
        _ctx.declareLocal('arguments');
        _bc.emit(
          hasSimpleParameterList
              ? Op.createMappedArguments
              : Op.createArguments,
        );
        _ctx.adjustStack(1);
        _emitPutVar('arguments', 0);
      }

      // Handle default parameter values
      for (var i = 0; i < params.length; i++) {
        final param = params[i];
        if (param.isRest) break;
        if (param.defaultValue != null) {
          final paramName = param.name?.name ?? '_p$i';
          _emitGetVar(paramName, param.defaultValue!.line);
          _bc.emit(Op.pushUndefined);
          _ctx.adjustStack(1);
          _bc.emit(Op.strictEq);
          _ctx.adjustStack(-1);
          final skipPatch = _bc.emitJump(Op.ifFalse);
          _ctx.adjustStack(-1);
          param.defaultValue!.accept(this);
          _emitPutVar(paramName, param.defaultValue!.line);
          _bc.patchJump(skipPatch, _bc.offset);
        }
      }

      // Handle destructuring parameters
      for (var i = 0; i < params.length; i++) {
        final param = params[i];
        if (param.isRest) break;
        if (param.isDestructuring) {
          final paramName = '_p$i';
          _emitGetVar(paramName, param.pattern!.line);
          _compileDestructuringBinding(
            param.pattern!,
            declare: true,
            kind: 'let',
          );
        }
      }

      _ctx.parameterVarCount = _ctx.vars.length;
      _ctx.bodyStartPc = _bc.offset;

      if (body is BlockStatement) {
        _predeclareClassNames(body.body);
        _hoistVarDeclarations(body.body);
        _hoistFunctionDeclarations(body.body);
        for (final stmt in body.body) {
          stmt.accept(this);
        }
      } else if (body is Expression) {
        body.accept(this);
        _bc.emit(Op.return_);
        _ctx.adjustStack(-1);
      }

      if (body is BlockStatement) {
        if (kind == FunctionKind.asyncFunction ||
            kind == FunctionKind.asyncArrow) {
          _bc.emit(Op.pushUndefined);
          _ctx.adjustStack(1);
          _bc.emit(Op.returnAsync);
          _ctx.adjustStack(-1);
        } else {
          _bc.emit(Op.returnUndef);
        }
      }

      final result = _popFunction();
      result.sourceLine = sourceLine;
      result.sourceColumn = sourceColumn;
      result.sourceText = sourceText;
      return result;
    } finally {
      _hoistedFunctionDeclStack.removeLast();
      _inTailPosition = savedTailPosition;
    }
  }

  // ===================================================================
  // Visitor: Expressions
  // ===================================================================

  @override
  void visitLiteralExpression(LiteralExpression node) {
    _bc.setLine(node.line, node.column);

    if (node.type == 'legacyOctal') {
      if (_ctx.isStrict) {
        final atom = _ctx.addConstant(
          'Octal literals are not allowed in strict mode',
        );
        _bc.emitAtomU8(Op.throwError, atom, 2);
        return;
      }
      _emitNumber((node.value as num).toDouble(), node.line, node.column);
      return;
    }

    switch (node.type) {
      case 'number':
        _emitNumber((node.value as num).toDouble(), node.line, node.column);
      case 'bigint':
        _emitBigInt(node.value as BigInt, node.line, node.column);
      case 'string':
      case 'template':
        _emitString(node.value as String, node.line, node.column);
      case 'boolean':
        _bc.emit(node.value == true ? Op.pushTrue : Op.pushFalse);
        _ctx.adjustStack(1);
      case 'null':
        _bc.emit(Op.pushNull);
        _ctx.adjustStack(1);
      case 'undefined':
        _bc.emit(Op.pushUndefined);
        _ctx.adjustStack(1);
      default:
        _bc.emit(Op.pushUndefined);
        _ctx.adjustStack(1);
    }
  }

  @override
  void visitIdentifierExpression(IdentifierExpression node) {
    _emitGetVar(node.name, node.line, node.column);
  }

  @override
  void visitThisExpression(ThisExpression node) {
    _bc.setLine(node.line, node.column);
    _bc.emit(Op.getThis);
    _ctx.adjustStack(1);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    _bc.setLine(node.line, node.column);

    if (node.operator == 'in' && node.left is PrivateIdentifierExpression) {
      final privateIdentifier = node.left as PrivateIdentifierExpression;
      final privateName = _resolveMemberPropertyName(privateIdentifier);
      if (privateName == null) {
        node.right.accept(this);
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
        _emitInvalidPrivateAccess(privateIdentifier.name, node.line);
        return;
      }

      _emitString(
        privateName,
        privateIdentifier.line,
        privateIdentifier.column,
      );
      _inTailPosition = false;
      node.right.accept(this);
      _bc.setLine(node.line, _estimateBinaryOperatorColumn(node));
      _bc.emit(Op.inOp);
      _ctx.adjustStack(-1);
      return;
    }

    // Handle short-circuit operators specially
    switch (node.operator) {
      case '&&':
        final wasTailAnd = _inTailPosition;
        _inTailPosition = false;
        node.left.accept(this);
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        final skipPatch = _bc.emitJump(Op.ifFalse);
        _ctx.adjustStack(-1);
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
        _inTailPosition = wasTailAnd;
        node.right.accept(this);
        _inTailPosition = false;
        _bc.patchJump(skipPatch, _bc.offset);
        return;

      case '||':
        final wasTailOr = _inTailPosition;
        _inTailPosition = false;
        node.left.accept(this);
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        final skipPatch = _bc.emitJump(Op.ifTrue);
        _ctx.adjustStack(-1);
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
        _inTailPosition = wasTailOr;
        node.right.accept(this);
        _inTailPosition = false;
        _bc.patchJump(skipPatch, _bc.offset);
        return;

      case '??':
        final wasTailNc = _inTailPosition;
        _inTailPosition = false;
        node.left.accept(this);
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        _bc.emit(Op.isNullOrUndefined);
        final skipPatch = _bc.emitJump(Op.ifFalse);
        _ctx.adjustStack(-1);
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
        _inTailPosition = wasTailNc;
        node.right.accept(this);
        _inTailPosition = false;
        _bc.patchJump(skipPatch, _bc.offset);
        return;
    }

    // Normal binary: compile left, right, then operator
    // Neither operand is in tail position (result feeds into the binary op).
    _inTailPosition = false;
    node.left.accept(this);
    node.right.accept(this);

    final op = _binaryOpMap[node.operator];
    if (op != null) {
      _bc.setLine(node.line, _estimateBinaryOperatorColumn(node));
      _bc.emit(op);
      _ctx.adjustStack(-1); // 2 in, 1 out
    } else {
      throw CompileError(
        'Unknown binary operator: ${node.operator}',
        node.line,
      );
    }
  }

  static const _binaryOpMap = <String, Op>{
    '+': Op.add,
    '-': Op.sub,
    '*': Op.mul,
    '/': Op.div,
    '%': Op.mod,
    '**': Op.pow,
    '<<': Op.shl,
    '>>': Op.sar,
    '>>>': Op.shr,
    '&': Op.bitAnd,
    '|': Op.bitOr,
    '^': Op.bitXor,
    '<': Op.lt,
    '<=': Op.lte,
    '>': Op.gt,
    '>=': Op.gte,
    '==': Op.eq,
    '!=': Op.neq,
    '===': Op.strictEq,
    '!==': Op.strictNeq,
    'in': Op.inOp,
    'instanceof': Op.instanceOf,
  };

  @override
  void visitUnaryExpression(UnaryExpression node) {
    _bc.setLine(node.line, node.column);

    if (node.prefix) {
      // Special case: typeof on an identifier (must not throw ReferenceError)
      if (node.operator == 'typeof' && node.operand is IdentifierExpression) {
        final name = (node.operand as IdentifierExpression).name;
        final res = _ctx.resolveVar(name);
        if (res.kind == _VarKind.global) {
          // For globals, use typeOfVar to avoid ReferenceError
          final atom = _ctx.addConstant(name);
          _bc.emitU32(Op.typeOfVar, atom);
          _ctx.adjustStack(1);
        } else {
          // For local/arg/closureVar, just get value and apply typeof
          node.operand.accept(this);
          _bc.emit(Op.typeOf);
        }
        return;
      }

      // Special case: delete
      if (node.operator == 'delete') {
        _compileDelete(node.operand, node.line);
        return;
      }

      // Special case: prefix ++/-- on member expressions
      if ((node.operator == '++' || node.operator == '--') &&
          node.operand is MemberExpression) {
        _compilePrefixUpdateMember(
          node.operand as MemberExpression,
          node.operator == '++' ? Op.inc : Op.dec,
        );
        return;
      }

      // Normal prefix unary
      final savedTailPosition = _inTailPosition;
      _inTailPosition = false;
      node.operand.accept(this);
      _inTailPosition = savedTailPosition;
      _bc.setLine(node.line, node.column);
      switch (node.operator) {
        case '-':
          _bc.emit(Op.neg);
        case '+':
          _bc.emit(Op.plus);
        case '~':
          _bc.emit(Op.bitNot);
        case '!':
          _bc.emit(Op.not);
        case 'typeof':
          _bc.emit(Op.typeOf);
        case 'void':
          _bc.emit(Op.voidOp);
        case '++':
          _bc.emit(Op.inc);
          _emitSetVar(_getAssignTarget(node.operand), node.line, node.column);
        case '--':
          _bc.emit(Op.dec);
          _emitSetVar(_getAssignTarget(node.operand), node.line, node.column);
        default:
          throw CompileError(
            'Unknown unary operator: ${node.operator}',
            node.line,
          );
      }
    } else {
      // Postfix: ++/-- on member expressions
      if (node.operand is MemberExpression) {
        _compilePostfixUpdateMember(
          node.operand as MemberExpression,
          node.operator == '++' ? Op.inc : Op.dec,
        );
        return;
      }
      // Postfix: ++/-- on identifiers
      // We need the old numeric value on stack, then increment the variable
      node.operand.accept(this);
      _bc.setLine(
        node.line,
        _estimateExpressionEndColumn(node.operand, node.column) + 1,
      );
      // ToNumeric before saving old value: preserve BigInt, coerce others.
      _bc.emit(Op.toNumeric);
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      if (node.operator == '++') {
        _bc.emit(Op.inc);
      } else {
        _bc.emit(Op.dec);
      }
      _emitPutVar(_getAssignTarget(node.operand), node.line, node.column);
      // Numeric old value remains on stack
    }
  }

  /// Compile prefix ++/-- on member expression (e.g. ++obj.prop, ++arr[i])
  /// Result: new value on stack
  void _compilePrefixUpdateMember(MemberExpression target, Op incOrDec) {
    target.object.accept(this);
    if (target.computed) {
      target.property.accept(this);
      // Stack: [obj, key]
      _bc.emit(Op.dup2);
      _ctx.adjustStack(2);
      // Stack: [obj, key, obj, key]
      _bc.emit(Op.getElem);
      _ctx.adjustStack(-1);
      // Stack: [obj, key, oldValue]
      _bc.emit(incOrDec);
      // Stack: [obj, key, newValue]
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      // Stack: [obj, key, newValue, newValue]
      _bc.emit(Op.insert4);
      // Stack: [newValue, obj, key, newValue]
      _bc.emit(Op.putElem);
      _ctx.adjustStack(-3);
      // Stack: [newValue]
    } else {
      // Stack: [obj]
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      // Stack: [obj, obj]
      final propName = _resolveMemberPropertyName(target.property);
      if (propName == null) {
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
        _emitInvalidPrivateAccess(
          (target.property as PrivateIdentifierExpression).name,
          target.line,
        );
        return;
      }
      final atom = _ctx.addConstant(propName);
      _bc.emitU32(Op.getField, atom);
      // Stack: [obj, oldValue]
      _bc.emit(incOrDec);
      // Stack: [obj, newValue]
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      // Stack: [obj, newValue, newValue]
      _bc.emit(Op.insert3);
      // Stack: [newValue, obj, newValue]
      _bc.emitU32(Op.putField, atom);
      _ctx.adjustStack(-2);
      // Stack: [newValue]
    }
  }

  /// Compile postfix ++/-- on member expression (e.g. obj.prop++, arr[i]--)
  /// Result: old value on stack
  void _compilePostfixUpdateMember(MemberExpression target, Op incOrDec) {
    target.object.accept(this);
    if (target.computed) {
      target.property.accept(this);
      // Stack: [obj, key]
      _bc.emit(Op.dup2);
      _ctx.adjustStack(2);
      // Stack: [obj, key, obj, key]
      _bc.emit(Op.getElem);
      _ctx.adjustStack(-1);
      // Stack: [obj, key, oldValue]
      // ToNumeric before saving old value: preserve BigInt, coerce others.
      _bc.emit(Op.toNumeric);
      // Stack: [obj, key, numericOldValue]
      // We need to keep numericOldValue as result
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      // Stack: [obj, key, numericOldValue, numericOldValue]
      _bc.emit(Op.insert4);
      // Stack: [numericOldValue, obj, key, numericOldValue]
      _bc.emit(incOrDec);
      // Stack: [numericOldValue, obj, key, newValue]
      _bc.emit(Op.putElem);
      _ctx.adjustStack(-3);
      // Stack: [numericOldValue]
    } else {
      // Stack: [obj]
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      // Stack: [obj, obj]
      final propName = _resolveMemberPropertyName(target.property);
      if (propName == null) {
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
        _emitInvalidPrivateAccess(
          (target.property as PrivateIdentifierExpression).name,
          target.line,
        );
        return;
      }
      final atom = _ctx.addConstant(propName);
      _bc.emitU32(Op.getField, atom);
      // Stack: [obj, oldValue]
      // ToNumeric before saving old value: preserve BigInt, coerce others.
      _bc.emit(Op.toNumeric);
      // Stack: [obj, numericOldValue]
      // Keep numeric old value as result
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      // Stack: [obj, numericOldValue, numericOldValue]
      _bc.emit(Op.insert3);
      // Stack: [numericOldValue, obj, numericOldValue]
      _bc.emit(incOrDec);
      // Stack: [numericOldValue, obj, newValue]
      _bc.emitU32(Op.putField, atom);
      _ctx.adjustStack(-2);
      // Stack: [numericOldValue]
    }
  }

  void _compileDelete(Expression target, int line) {
    if (target is MemberExpression) {
      if (target.object is SuperExpression) {
        final atom = _ctx.addConstant('Cannot delete a property of super');
        _bc.setLine(line);
        _bc.emitAtomU8(Op.throwError, atom, 1);
        return;
      }
      if (target.computed) {
        target.object.accept(this);
        if (target.object is OptionalChainingExpression) {
          _bc.emit(Op.dup);
          _ctx.adjustStack(1);
          _bc.emit(Op.isNullOrUndefined);
          final shortCircuitPatch = _bc.emitJump(Op.ifTrue);
          _ctx.adjustStack(-1);

          target.property.accept(this);
          _bc.emit(Op.deleteElem);
          _ctx.adjustStack(-1); // 2 in, 1 out

          final endPatch = _bc.emitJump(Op.goto_);
          _bc.patchJump(shortCircuitPatch, _bc.offset);
          _bc.emit(Op.drop);
          _ctx.adjustStack(-1);
          _bc.emit(Op.pushTrue);
          _ctx.adjustStack(1);
          _bc.patchJump(endPatch, _bc.offset);
          return;
        }
        target.property.accept(this);
        _bc.emit(Op.deleteElem);
        _ctx.adjustStack(-1); // 2 in, 1 out
      } else {
        target.object.accept(this);
        if (target.object is OptionalChainingExpression) {
          _bc.emit(Op.dup);
          _ctx.adjustStack(1);
          _bc.emit(Op.isNullOrUndefined);
          final shortCircuitPatch = _bc.emitJump(Op.ifTrue);
          _ctx.adjustStack(-1);

          final name = _resolveMemberPropertyName(target.property);
          if (name == null) {
            _bc.emit(Op.drop);
            _ctx.adjustStack(-1);
            _emitInvalidPrivateAccess(
              (target.property as PrivateIdentifierExpression).name,
              line,
            );
            return;
          }
          final atom = _ctx.addConstant(name);
          _bc.emitU32(Op.deleteField, atom);

          final endPatch = _bc.emitJump(Op.goto_);
          _bc.patchJump(shortCircuitPatch, _bc.offset);
          _bc.emit(Op.drop);
          _ctx.adjustStack(-1);
          _bc.emit(Op.pushTrue);
          _ctx.adjustStack(1);
          _bc.patchJump(endPatch, _bc.offset);
          return;
        }
        final name = _resolveMemberPropertyName(target.property);
        if (name == null) {
          _bc.emit(Op.drop);
          _ctx.adjustStack(-1);
          _emitInvalidPrivateAccess(
            (target.property as PrivateIdentifierExpression).name,
            line,
          );
          return;
        }
        final atom = _ctx.addConstant(name);
        _bc.emitU32(Op.deleteField, atom);
        // 1 in, 1 out (no adjustment)
      }
    } else if (target is IdentifierExpression) {
      // Check if variable is locally resolved (local, arg, or closure)
      final res = _ctx.resolveVar(target.name);
      if (res.kind != _VarKind.global) {
        // Local/arg/closure variables are not deletable
        _bc.emit(Op.pushFalse);
        _ctx.adjustStack(1);
      } else {
        final atom = _ctx.addConstant(target.name);
        _bc.emitU32(Op.deleteVar, atom);
        _ctx.adjustStack(1);
      }
    } else {
      // delete on non-reference: always true
      target.accept(this);
      _bc.emit(Op.drop);
      _ctx.adjustStack(-1);
      _bc.emit(Op.pushTrue);
      _ctx.adjustStack(1);
    }
  }

  /// Get the variable name from an expression that's a simple identifier
  String _getAssignTarget(Expression expr) {
    if (expr is IdentifierExpression) return expr.name;
    throw CompileError('Invalid assignment target', expr.line);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    _bc.setLine(node.line, node.column);
    // Sub-expressions of assignment are not in tail position — the
    // assignment itself still needs to execute after the RHS is evaluated.
    final savedTail = _inTailPosition;
    _inTailPosition = false;

    if (node.operator == '=') {
      // Simple assignment
      if (node.left is IdentifierExpression) {
        final left = node.left as IdentifierExpression;
        final name = left.name;
        final res = _ctx.resolveVar(name);
        // In strict mode, check that the global exists before evaluating the RHS
        if (_ctx.isStrict) {
          if (res.kind == _VarKind.global) {
            final atom = _ctx.addConstant(name);
            _bc.setLine(left.line, left.column);
            _bc.emitU32(Op.checkVarStrict, atom);
          }
        }

        if (_shouldUseWithLookup(res)) {
          final atom = _ctx.addConstant(name);
          _bc.emitU32(Op.captureVarRef, atom);
          _ctx.adjustStack(1);

          _compileWithInferredFunctionName(name, node.right, () {
            node.right.accept(this);
          });
          _bc.emit(Op.swap);
          _bc.emit(Op.setCapturedVar);
          _ctx.adjustStack(-1);
          _inTailPosition = savedTail;
          return;
        }

        _compileWithInferredFunctionName(name, node.right, () {
          node.right.accept(this);
        });
        _emitSetVar(name, left.line, left.column);
      } else if (node.left is MemberExpression) {
        _compileMemberAssign(node.left as MemberExpression, node.right);
      } else {
        throw CompileError('Invalid assignment target', node.line);
      }
    } else if (node.operator == '??=' ||
        node.operator == '&&=' ||
        node.operator == '||=') {
      // Logical/nullish compound assignment with short-circuit
      _compileLogicalAssignment(node);
    } else {
      // Compound assignment (+=, -=, etc.)
      final baseOp = node.operator.substring(0, node.operator.length - 1);
      if (node.left is IdentifierExpression) {
        final left = node.left as IdentifierExpression;
        final name = left.name;
        _emitGetVar(name, left.line, left.column);
        node.right.accept(this);
        final op = _binaryOpMap[baseOp];
        if (op == null) {
          throw CompileError(
            'Unknown compound assignment: ${node.operator}',
            node.line,
          );
        }
        _bc.setLine(node.line, _estimateAssignmentOperatorColumn(node));
        _bc.emit(op);
        _ctx.adjustStack(-1);
        _emitSetVar(name, left.line, left.column);
      } else if (node.left is MemberExpression) {
        _compileCompoundMemberAssign(
          node.left as MemberExpression,
          baseOp,
          node.right,
        );
      } else {
        throw CompileError('Invalid assignment target', node.line);
      }
    }
    _inTailPosition = savedTail;
  }

  void _compileMemberAssign(MemberExpression target, Expression value) {
    target.object.accept(this);
    final memberColumn = _estimateMemberOperatorColumn(target);
    if (target.computed) {
      target.property.accept(this);
      value.accept(this);
      // Stack: [obj, key, value]
      // dup -> [obj, key, value, value]
      // insert4 -> [value, obj, key, value]
      // putElem pops [obj, key, value] -> leaves [value]
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      _bc.emit(Op.insert4);
      _bc.setLine(target.line, memberColumn);
      _bc.emit(Op.putElem);
      _ctx.adjustStack(-3);
    } else {
      value.accept(this);
      // Stack: [obj, value] — need to keep value as result after putField
      // dup -> [obj, value, value] -> insert3 -> [value, obj, value]
      // putField pops [obj, value], leaves value as assignment result
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      _bc.emit(Op.insert3);
      final propName = _resolveMemberPropertyName(target.property);
      if (propName == null) {
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
        _emitInvalidPrivateAccess(
          (target.property as PrivateIdentifierExpression).name,
          target.line,
        );
        return;
      }
      final atom = _ctx.addConstant(propName);
      _bc.setLine(target.line, memberColumn);
      _bc.emitU32(Op.putField, atom);
      _ctx.adjustStack(-2);
    }
  }

  void _compileCompoundMemberAssign(
    MemberExpression target,
    String baseOp,
    Expression rhs,
  ) {
    target.object.accept(this);
    final memberColumn = _estimateMemberOperatorColumn(target);

    if (target.computed) {
      // obj[key] op= rhs
      target.property.accept(this);
      // Stack: [obj, key]
      _bc.emit(Op.dup2);
      _ctx.adjustStack(2);
      // Stack: [obj, key, obj, key]
      _bc.emit(Op.getElem);
      _ctx.adjustStack(-1);
      // Stack: [obj, key, oldValue]
      rhs.accept(this);
      final op = _binaryOpMap[baseOp];
      if (op == null) {
        throw CompileError('Unknown operator: $baseOp', target.line);
      }
      _bc.setLine(target.line, rhs.column - baseOp.length - 2);
      _bc.emit(op);
      _ctx.adjustStack(-1);
      // Stack: [obj, key, result]
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      // Stack: [obj, key, result, result]
      _bc.emit(Op.insert4);
      // Stack: [result, obj, key, result]
      _bc.setLine(target.line, memberColumn);
      _bc.emit(Op.putElem);
      _ctx.adjustStack(-3);
      // Stack: [result]
    } else {
      // obj.prop op= rhs
      // Stack after object: [obj]
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      // Stack: [obj, obj]
      final propName = _resolveMemberPropertyName(target.property);
      if (propName == null) {
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
        _emitInvalidPrivateAccess(
          (target.property as PrivateIdentifierExpression).name,
          target.line,
        );
        return;
      }
      final atom = _ctx.addConstant(propName);
      _bc.emitU32(Op.getField, atom);
      // Stack: [obj, oldValue] (getField pops obj copy, pushes value)
      rhs.accept(this);
      final op = _binaryOpMap[baseOp];
      if (op == null) {
        throw CompileError('Unknown operator: $baseOp', target.line);
      }
      _bc.setLine(target.line, rhs.column - baseOp.length - 2);
      _bc.emit(op);
      _ctx.adjustStack(-1);
      // Stack: obj, result -> dup -> obj, result, result -> insert3 -> result, obj, result -> putField -> result
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      _bc.emit(Op.insert3);
      _bc.setLine(target.line, memberColumn);
      _bc.emitU32(Op.putField, atom);
      _ctx.adjustStack(-2);
    }
  }

  /// Compile logical/nullish compound assignments: ??=, &&=, ||=
  /// These require short-circuit evaluation.
  void _compileLogicalAssignment(AssignmentExpression node) {
    final op = node.operator; // '??=', '&&=', '||='

    if (node.left is IdentifierExpression) {
      final name = (node.left as IdentifierExpression).name;
      // Get current value
      _emitGetVar(name, node.line);

      // Check condition
      if (op == '??=') {
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        _bc.emit(Op.isNullOrUndefined);
        // If NOT null/undefined, skip assignment (keep original value)
        final skipPatch = _bc.emitJump(Op.ifFalse);
        _ctx.adjustStack(-1);
        // Drop old value, compile and assign rhs
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
        node.right.accept(this);
        _emitSetVar(name, node.line);
        final endPatch = _bc.emitJump(Op.goto_);
        _bc.patchJump(skipPatch, _bc.offset);
        _bc.patchJump(endPatch, _bc.offset);
      } else if (op == '&&=') {
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        // If falsy, skip assignment (keep original value)
        final skipPatch = _bc.emitJump(Op.ifFalse);
        _ctx.adjustStack(-1);
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
        node.right.accept(this);
        _emitSetVar(name, node.line);
        final endPatch = _bc.emitJump(Op.goto_);
        _bc.patchJump(skipPatch, _bc.offset);
        _bc.patchJump(endPatch, _bc.offset);
      } else {
        // ||=
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        // If truthy, skip assignment (keep original value)
        final skipPatch = _bc.emitJump(Op.ifTrue);
        _ctx.adjustStack(-1);
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
        node.right.accept(this);
        _emitSetVar(name, node.line);
        final endPatch = _bc.emitJump(Op.goto_);
        _bc.patchJump(skipPatch, _bc.offset);
        _bc.patchJump(endPatch, _bc.offset);
      }
    } else if (node.left is MemberExpression) {
      final target = node.left as MemberExpression;
      target.object.accept(this);

      if (target.computed) {
        target.property.accept(this);
        // Stack: obj, key
        _bc.emit(Op.dup2);
        _ctx.adjustStack(2);
        _bc.emit(Op.getElem);
        _ctx.adjustStack(-1);
        // Stack: obj, key, currentValue
      } else {
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        final propName = _resolveMemberPropertyName(target.property);
        if (propName == null) {
          _bc.emit(Op.drop);
          _ctx.adjustStack(-1);
          _emitInvalidPrivateAccess(
            (target.property as PrivateIdentifierExpression).name,
            node.line,
          );
          return;
        }
        final atom = _ctx.addConstant(propName);
        _bc.emitU32(Op.getField, atom);
        // Stack: obj, currentValue
      }

      if (op == '??=') {
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        _bc.emit(Op.isNullOrUndefined);
        final skipPatch = _bc.emitJump(Op.ifFalse);
        _ctx.adjustStack(-1);
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
        node.right.accept(this);
        _assignMemberResult(target);
        final endPatch = _bc.emitJump(Op.goto_);
        _bc.patchJump(skipPatch, _bc.offset);
        // Not null/undefined: drop obj/key, keep current value
        _dropMemberBase(target);
        _bc.patchJump(endPatch, _bc.offset);
      } else if (op == '&&=') {
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        final skipPatch = _bc.emitJump(Op.ifFalse);
        _ctx.adjustStack(-1);
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
        node.right.accept(this);
        _assignMemberResult(target);
        final endPatch = _bc.emitJump(Op.goto_);
        _bc.patchJump(skipPatch, _bc.offset);
        _dropMemberBase(target);
        _bc.patchJump(endPatch, _bc.offset);
      } else {
        // ||=
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        final skipPatch = _bc.emitJump(Op.ifTrue);
        _ctx.adjustStack(-1);
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
        node.right.accept(this);
        _assignMemberResult(target);
        final endPatch = _bc.emitJump(Op.goto_);
        _bc.patchJump(skipPatch, _bc.offset);
        _dropMemberBase(target);
        _bc.patchJump(endPatch, _bc.offset);
      }
    } else {
      throw CompileError('Invalid assignment target', node.line);
    }
  }

  /// After computing new value on stack with [obj, key?, newValue],
  /// assign to the member and leave newValue as result.
  void _assignMemberResult(MemberExpression target) {
    if (target.computed) {
      // Stack: obj, key, newValue
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      // Stack: obj, key, newValue, newValue
      _bc.emit(Op.insert4);
      // Stack: newValue, obj, key, newValue
      _bc.emit(Op.putElem);
      _ctx.adjustStack(-3);
      // Stack: newValue
    } else {
      // Stack: obj, newValue
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      _bc.emit(Op.insert3);
      final propName = _resolveMemberPropertyName(target.property);
      if (propName == null) {
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
        _emitInvalidPrivateAccess(
          (target.property as PrivateIdentifierExpression).name,
          target.line,
        );
        return;
      }
      final atom = _ctx.addConstant(propName);
      _bc.emitU32(Op.putField, atom);
      _ctx.adjustStack(-2);
    }
  }

  /// Drop the base object (and key if computed) beneath currentValue on stack.
  /// Stack before: [..., obj, key?, currentValue]
  /// Stack after:  [..., currentValue]
  void _dropMemberBase(MemberExpression target) {
    if (target.computed) {
      // Stack: obj, key, currentValue -> need to keep just currentValue
      // rot3l: key, currentValue, obj -> drop: key, currentValue -> swap, drop: currentValue
      _bc.emit(Op.rot3l);
      _bc.emit(Op.drop);
      _ctx.adjustStack(-1);
      _bc.emit(Op.swap);
      _bc.emit(Op.drop);
      _ctx.adjustStack(-1);
    } else {
      // Stack: obj, currentValue -> swap, drop: currentValue
      _bc.emit(Op.swap);
      _bc.emit(Op.drop);
      _ctx.adjustStack(-1);
    }
  }

  @override
  void visitCallExpression(CallExpression node) {
    var callColumn = _estimateExpressionEndColumn(node.callee, node.column);
    if (node.callee is LiteralExpression) {
      callColumn += 1;
    }
    _bc.setLine(node.line, callColumn);

    // Save and consume the tail position flag — sub-expressions (callee, args)
    // must not see it since they're not in tail position themselves.
    final isTailCall = _inTailPosition;
    _inTailPosition = false;

    final hasSpread = node.arguments.any((a) => a is SpreadElement);
    final isDirectEvalCall =
        node.callee is IdentifierExpression &&
        (node.callee as IdentifierExpression).name == 'eval';

    // super() call — call super constructor with this binding
    if (node.callee is SuperExpression && _superVarName != null) {
      // Stack: push this, push super constructor
      _bc.emit(Op.getThis);
      _ctx.adjustStack(1);
      _emitGetVar(_superVarName!, node.line, node.column);

      for (final arg in node.arguments) {
        arg.accept(this);
      }
      _bc.emitU16(Op.callMethod, node.arguments.length);
      _ctx.adjustStack(-(node.arguments.length + 1));
      // super() result is discarded — replace with this
      _bc.emit(Op.drop);
      _ctx.adjustStack(-1);
      _bc.emit(Op.getThis);
      _ctx.adjustStack(1);
      return;
    }

    if (node.callee is MemberExpression) {
      final member = node.callee as MemberExpression;

      // super.method() call — call method with this as receiver
      if (member.object is SuperExpression && _superVarName != null) {
        _bc.emit(Op.getThis);
        _ctx.adjustStack(1);
        _emitSuperBase(node.line);
        if (member.computed) {
          member.property.accept(this);
          _bc.emit(Op.getSuperField);
          _ctx.adjustStack(-1);
        } else {
          final name = _resolveMemberPropertyName(member.property);
          if (name == null) {
            _bc.emit(Op.drop);
            _ctx.adjustStack(-1);
            _bc.emit(Op.drop);
            _ctx.adjustStack(-1);
            _emitInvalidPrivateAccess(
              (member.property as PrivateIdentifierExpression).name,
              node.line,
            );
            return;
          }
          _emitString(name, node.line);
          _bc.emit(Op.getSuperField);
          _ctx.adjustStack(-1);
        }
        // Stack: [this, method]
        for (final arg in node.arguments) {
          arg.accept(this);
        }
        _bc.emitU16(Op.callMethod, node.arguments.length);
        _ctx.adjustStack(-(node.arguments.length + 1));
        return;
      }

      // Method call: obj.method(args)
      member.object.accept(this);
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);

      if (member.computed) {
        member.property.accept(this);
        _bc.emit(Op.getElem);
        _ctx.adjustStack(-1);
      } else {
        final name = _resolveMemberPropertyName(member.property);
        if (name == null) {
          _bc.emit(Op.drop);
          _ctx.adjustStack(-1);
          _bc.emit(Op.drop);
          _ctx.adjustStack(-1);
          _emitInvalidPrivateAccess(
            (member.property as PrivateIdentifierExpression).name,
            node.line,
          );
          return;
        }
        final atom = _ctx.addConstant(name);
        _bc.emitU32(Op.getField, atom);
      }

      if (hasSpread) {
        _compileArgsArray(node.arguments);
        _bc.setLine(node.line, callColumn);
        _bc.emit(Op.applyMethod);
        _ctx.adjustStack(-2); // obj + func + argsArray -> result
      } else {
        for (final arg in node.arguments) {
          arg.accept(this);
        }
        _bc.setLine(node.line, callColumn);
        if (isTailCall) {
          _bc.emitU16(Op.tailCallMethod, node.arguments.length);
        } else {
          _bc.emitU16(Op.callMethod, node.arguments.length);
        }
        _ctx.adjustStack(-(node.arguments.length + 1));
      }
    } else {
      // Regular call: func(args)
      node.callee.accept(this);

      if (hasSpread) {
        _compileArgsArray(node.arguments);
        _bc.setLine(node.line, callColumn);
        _bc.emit(isDirectEvalCall ? Op.applyDirectEval : Op.apply);
        _ctx.adjustStack(-1); // func + argsArray -> result
      } else {
        for (final arg in node.arguments) {
          arg.accept(this);
        }
        _bc.setLine(node.line, callColumn);
        if (isDirectEvalCall) {
          _bc.emitU16(Op.callDirectEval, node.arguments.length);
        } else if (isTailCall) {
          _bc.emitU16(Op.tailCall, node.arguments.length);
        } else {
          _bc.emitU16(Op.call, node.arguments.length);
        }
        _ctx.adjustStack(-node.arguments.length);
      }
    }
  }

  /// Compile arguments into an array (for spread calls).
  void _compileArgsArray(List<Expression> args) {
    _bc.emit(Op.array);
    _ctx.adjustStack(1);
    for (final arg in args) {
      if (arg is SpreadElement) {
        arg.argument.accept(this);
        _bc.emit(Op.spread);
        _ctx.adjustStack(-1);
      } else {
        arg.accept(this);
        _bc.emit(Op.arrayAppend);
        _ctx.adjustStack(-1);
      }
    }
  }

  @override
  void visitNewExpression(NewExpression node) {
    _bc.setLine(node.line, node.column);
    // Sub-expressions of `new` are never in tail position.
    final savedTail = _inTailPosition;
    _inTailPosition = false;

    final hasSpread = node.arguments.any((a) => a is SpreadElement);

    node.callee.accept(this);

    if (hasSpread) {
      _compileArgsArray(node.arguments);
      _bc.emit(Op.applyConstructor);
      _ctx.adjustStack(-1); // ctor + argsArray -> instance
    } else {
      for (final arg in node.arguments) {
        arg.accept(this);
      }
      _bc.emitU16(Op.callConstructor, node.arguments.length);
      _ctx.adjustStack(-node.arguments.length);
    }
    _inTailPosition = savedTail;
  }

  @override
  void visitMemberExpression(MemberExpression node) {
    _bc.setLine(node.line, node.column);

    // A member expression uses the result of its object, so
    // the object sub-expression is NOT in tail position.
    final savedTailPos = _inTailPosition;
    _inTailPosition = false;

    // super.property — access from SuperClass.prototype
    if (node.object is SuperExpression && _superVarName != null) {
      _emitSuperBase(node.line);
      if (node.computed) {
        node.property.accept(this);
        _bc.setLine(node.line, _estimateMemberOperatorColumn(node));
        _bc.emit(Op.getSuperField);
        _ctx.adjustStack(-1);
      } else {
        final name = _resolveMemberPropertyName(node.property);
        if (name == null) {
          _bc.emit(Op.drop);
          _ctx.adjustStack(-1);
          _emitInvalidPrivateAccess(
            (node.property as PrivateIdentifierExpression).name,
            node.line,
          );
          return;
        }
        _emitString(name, node.line);
        _bc.setLine(node.line, _estimateMemberOperatorColumn(node));
        _bc.emit(Op.getSuperField);
        _ctx.adjustStack(-1);
      }
      return;
    }

    node.object.accept(this);

    if (node.computed) {
      node.property.accept(this);
      _bc.setLine(node.line, _estimateMemberOperatorColumn(node));
      _bc.emit(Op.getElem);
      _ctx.adjustStack(-1);
    } else {
      final name = _resolveMemberPropertyName(node.property);
      if (name == null) {
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
        _emitInvalidPrivateAccess(
          (node.property as PrivateIdentifierExpression).name,
          node.line,
        );
        return;
      }
      final atom = _ctx.addConstant(name);
      _bc.setLine(node.line, _estimateMemberOperatorColumn(node));
      _bc.emitU32(Op.getField, atom);
      // 1 in (obj), 1 out (value): no stack change
    }
    _inTailPosition = savedTailPos;
  }

  @override
  void visitArrayExpression(ArrayExpression node) {
    _bc.setLine(node.line);
    // Sub-expressions inside an array literal are never in tail position.
    final savedTail = _inTailPosition;
    _inTailPosition = false;

    _bc.emit(Op.array);
    _ctx.adjustStack(1);

    for (final elem in node.elements) {
      if (elem == null) {
        // Hole in array — emit hole marker (preserves sparseness)
        _bc.emit(Op.arrayHole);
      } else if (elem is SpreadElement) {
        elem.argument.accept(this);
        _bc.emit(Op.spread);
        // spread consumes the iterable and appends all items to the array below it
        _ctx.adjustStack(-1);
      } else {
        elem.accept(this);
        _bc.emit(Op.arrayAppend);
        _ctx.adjustStack(-1);
      }
    }
    _inTailPosition = savedTail;
  }

  @override
  void visitObjectExpression(ObjectExpression node) {
    _bc.setLine(node.line);
    // Sub-expressions inside an object literal are never in tail position.
    final savedTail = _inTailPosition;
    _inTailPosition = false;

    _bc.emit(Op.object);
    _ctx.adjustStack(1);

    final homeObjectTemp = '__super_home_${_superHomeObjectCounter++}';
    final homeObjectSlot = _ctx.declareLocal(
      homeObjectTemp,
      scope: VarScope.blockScope,
      scopeLevel: _ctx.scope.depth,
    );
    _bc.emit(Op.dup);
    _ctx.adjustStack(1);
    _bc.emitU16(Op.putLoc, homeObjectSlot);
    _ctx.adjustStack(-1);

    for (final prop in node.properties) {
      if (prop is SpreadElement) {
        prop.argument.accept(this);
        _bc.emit(Op.copyDataProperties);
        _ctx.adjustStack(-1);
        continue;
      }

      final objProp = prop as ObjectProperty;

      if (objProp.kind == 'get') {
        if (objProp.computed) {
          _compileObjectComputedAccessor(
            objProp,
            isGetter: true,
            superVarName: homeObjectTemp,
          );
        } else {
          _compileObjectAccessor(
            objProp,
            isGetter: true,
            superVarName: homeObjectTemp,
          );
        }
        continue;
      }
      if (objProp.kind == 'set') {
        if (objProp.computed) {
          _compileObjectComputedAccessor(
            objProp,
            isGetter: false,
            superVarName: homeObjectTemp,
          );
        } else {
          _compileObjectAccessor(
            objProp,
            isGetter: false,
            superVarName: homeObjectTemp,
          );
        }
        continue;
      }

      // Regular property
      if (objProp.computed) {
        // Computed property: [expr]: value
        // Object is on stack; dup it so putElem doesn't consume it
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        objProp.key.accept(this);
        if (objProp.kind == 'method' && objProp.value is FunctionExpression) {
          _withSuperBinding(homeObjectTemp, true, () {
            objProp.value.accept(this);
          });
        } else {
          objProp.value.accept(this);
        }
        _bc.emit(Op.putElem);
        _ctx.adjustStack(-3);
      } else {
        // name: value
        if (objProp.value is FunctionExpression &&
            (objProp.kind == null || objProp.kind == 'method') &&
            !objProp.computed) {
          final funcExpr = objProp.value as FunctionExpression;
          final keyName = _getPropertyKeyName(objProp.key);
          final paramStr = funcExpr.params
              .map(
                (p) => p.isRest
                    ? '...${p.name?.name ?? 'param'}'
                    : (p.name?.name ?? 'param'),
              )
              .join(', ');
          _pendingFunctionName = _getPropertyKeyName(objProp.key);
          _pendingFunctionSourceText = '$keyName($paramStr) ${funcExpr.body}';
        }
        if (objProp.kind == 'method' && objProp.value is FunctionExpression) {
          _withSuperBinding(homeObjectTemp, true, () {
            objProp.value.accept(this);
          });
        } else {
          objProp.value.accept(this);
        }
        _pendingFunctionName = null;
        _pendingFunctionSourceText = null;
        final keyName = _getPropertyKeyName(objProp.key);
        final atom = _ctx.addConstant(keyName);
        _bc.emitAtomU8(
          Op.defineProp,
          atom,
          0x07,
        ); // writable | enumerable | configurable
        _ctx.adjustStack(-1);
      }
    }
    _inTailPosition = savedTail;
  }

  void _compileObjectAccessor(
    ObjectProperty prop, {
    required bool isGetter,
    String? superVarName,
  }) {
    final funcExpr = prop.value as FunctionExpression;
    final keyName = _getPropertyKeyName(prop.key);

    // Compile the getter/setter function
    final funcBytecode = _withSuperBinding(superVarName, true, () {
      return _compileFunction(
        name: '${isGetter ? "get" : "set"} $keyName',
        kind: isGetter ? FunctionKind.getter : FunctionKind.setter,
        params: funcExpr.params,
        body: funcExpr.body,
        sourceText: prop.toString(),
      );
    });

    final funcIdx = _ctx.addConstant(funcBytecode);
    _bc.emitU16(Op.fclosure, funcIdx);
    _ctx.adjustStack(1);

    final atom = _ctx.addConstant(keyName);
    if (isGetter) {
      _bc.emitU32(Op.defineGetterEnum, atom);
    } else {
      _bc.emitU32(Op.defineSetterEnum, atom);
    }
    _ctx.adjustStack(-1);
  }

  void _compileObjectComputedAccessor(
    ObjectProperty prop, {
    required bool isGetter,
    String? superVarName,
  }) {
    final funcExpr = prop.value as FunctionExpression;

    final funcBytecode = _withSuperBinding(superVarName, true, () {
      return _compileFunction(
        name: isGetter ? 'get' : 'set',
        kind: isGetter ? FunctionKind.getter : FunctionKind.setter,
        params: funcExpr.params,
        body: funcExpr.body,
        sourceText: prop.toString(),
      );
    });

    final funcIdx = _ctx.addConstant(funcBytecode);
    _bc.emitU16(Op.fclosure, funcIdx);
    _ctx.adjustStack(1);

    prop.key.accept(this);
    // Stack: [obj, func, key]
    if (isGetter) {
      _bc.emit(Op.defineGetterElem);
    } else {
      _bc.emit(Op.defineSetterElem);
    }
    _ctx.adjustStack(-2);
    // obj remains on stack via peek
  }

  String _getPropertyKeyName(Expression key) {
    if (key is IdentifierExpression) return key.name;
    if (key is LiteralExpression) {
      if (key.value is num) {
        final n = (key.value as num).toDouble();
        if (n == n.truncateToDouble() && n.abs() <= 9007199254740991) {
          return n.truncate().toString();
        }
        return n.toString();
      }
      return key.value.toString();
    }
    return key.toString();
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    _bc.setLine(node.line);
    final wasTailPos = _inTailPosition;
    _inTailPosition = false; // test is never in tail position

    node.test.accept(this);
    final elsePatch = _bc.emitJump(Op.ifFalse);
    _ctx.adjustStack(-1);

    _inTailPosition = wasTailPos;
    node.consequent.accept(this);
    _inTailPosition = false;
    final endPatch = _bc.emitJump(Op.goto_);
    _ctx.adjustStack(-1); // will be restored by alternate

    _bc.patchJump(elsePatch, _bc.offset);
    _inTailPosition = wasTailPos;
    node.alternate.accept(this);
    _inTailPosition = false;

    _bc.patchJump(endPatch, _bc.offset);
  }

  @override
  void visitSequenceExpression(SequenceExpression node) {
    final wasTailPos = _inTailPosition;
    for (var i = 0; i < node.expressions.length; i++) {
      // Only the last expression can be in tail position
      _inTailPosition = wasTailPos && (i == node.expressions.length - 1);
      node.expressions[i].accept(this);
      if (i < node.expressions.length - 1) {
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
      }
    }
    _inTailPosition = false;
  }

  @override
  void visitArrowFunctionExpression(ArrowFunctionExpression node) {
    _bc.setLine(node.line);
    final inferredName = _pendingFunctionName ?? '';
    final sourceText = _pendingFunctionSourceText ?? node.toString();
    _pendingFunctionName = null;
    _pendingFunctionSourceText = null;
    final funcBytecode = _compileFunction(
      name: inferredName,
      kind: FunctionKind.arrow,
      params: node.params,
      body: node.body,
      isStrict: _ctx.isStrict,
      sourceLine: node.line,
      sourceColumn: node.column,
      sourceText: sourceText,
    );
    final idx = _ctx.addConstant(funcBytecode);
    _bc.emitU16(Op.fclosure, idx);
    _ctx.adjustStack(1);
  }

  @override
  void visitAsyncArrowFunctionExpression(AsyncArrowFunctionExpression node) {
    _bc.setLine(node.line);
    final inferredName = _pendingFunctionName ?? '';
    final sourceText = _pendingFunctionSourceText ?? node.toString();
    _pendingFunctionName = null;
    _pendingFunctionSourceText = null;
    final funcBytecode = _compileFunction(
      name: inferredName,
      kind: FunctionKind.asyncArrow,
      params: node.params,
      body: node.body,
      isStrict: _ctx.isStrict,
      sourceLine: node.line,
      sourceColumn: node.column,
      sourceText: sourceText,
    );
    final idx = _ctx.addConstant(funcBytecode);
    _bc.emitU16(Op.fclosure, idx);
    _ctx.adjustStack(1);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    _bc.setLine(node.line);
    final inferredName = node.id?.name ?? _pendingFunctionName ?? '';
    final sourceText = _pendingFunctionSourceText ?? node.toString();
    _pendingFunctionName = null;
    _pendingFunctionSourceText = null;
    final funcBytecode = _compileFunction(
      name: inferredName,
      kind: node.isGenerator ? FunctionKind.generator : FunctionKind.normal,
      params: node.params,
      body: node.body,
      sourceLine: node.line,
      sourceColumn: node.column,
      sourceText: sourceText,
    );
    final idx = _ctx.addConstant(funcBytecode);
    _bc.emitU16(Op.fclosure, idx);
    _ctx.adjustStack(1);
  }

  @override
  void visitAsyncFunctionExpression(AsyncFunctionExpression node) {
    _bc.setLine(node.line);
    final inferredName = node.id?.name ?? _pendingFunctionName ?? '';
    final sourceText = _pendingFunctionSourceText ?? node.toString();
    _pendingFunctionName = null;
    _pendingFunctionSourceText = null;
    final funcBytecode = _compileFunction(
      name: inferredName,
      kind: node.isGenerator
          ? FunctionKind.asyncGenerator
          : FunctionKind.asyncFunction,
      params: node.params,
      body: node.body,
      sourceLine: node.line,
      sourceColumn: node.column,
      sourceText: sourceText,
    );
    final idx = _ctx.addConstant(funcBytecode);
    _bc.emitU16(Op.fclosure, idx);
    _ctx.adjustStack(1);
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    _bc.setLine(node.line);
    node.argument.accept(this);
    _bc.emit(Op.await_);
    // Stack: 1 in (promise), 1 out (resolved value): net 0
  }

  @override
  void visitYieldExpression(YieldExpression node) {
    _bc.setLine(node.line);
    if (node.argument != null) {
      node.argument!.accept(this);
    } else {
      _bc.emit(Op.pushUndefined);
      _ctx.adjustStack(1);
    }
    if (node.delegate) {
      _bc.emit(Op.yieldStar);
    } else {
      _bc.emit(Op.yield_);
    }
  }

  @override
  void visitNullishCoalescingExpression(NullishCoalescingExpression node) {
    _bc.setLine(node.line);
    node.left.accept(this);
    _bc.emit(Op.dup);
    _ctx.adjustStack(1);
    _bc.emit(Op.isNullOrUndefined);
    final skipPatch = _bc.emitJump(Op.ifFalse);
    _ctx.adjustStack(-1);
    _bc.emit(Op.drop);
    _ctx.adjustStack(-1);
    node.right.accept(this);
    _bc.patchJump(skipPatch, _bc.offset);
  }

  @override
  void visitOptionalChainingExpression(OptionalChainingExpression node) {
    _bc.setLine(node.line);
    node.object.accept(this);
    _bc.emit(Op.dup);
    _ctx.adjustStack(1);
    _bc.emit(Op.isNullOrUndefined);
    final skipPatch = _bc.emitJump(Op.ifTrue);
    _ctx.adjustStack(-1);

    // Not null: access the property
    if (node.isCall) {
      // obj?.method() — property is a CallExpression
      // The callee might be an Identifier (the method name)
      final callExpr = node.property as CallExpression?;
      if (callExpr != null &&
          callExpr.callee is IdentifierExpression &&
          (callExpr.callee as IdentifierExpression).name ==
              '__optionalCallMarker__') {
        final hasSpread = callExpr.arguments.any((a) => a is SpreadElement);
        if (hasSpread) {
          _compileArgsArray(callExpr.arguments);
          _bc.emit(Op.apply);
          _ctx.adjustStack(-1); // func + argsArray -> result
        } else {
          for (final arg in callExpr.arguments) {
            arg.accept(this);
          }
          _bc.emitU16(Op.call, callExpr.arguments.length);
          _ctx.adjustStack(-callExpr.arguments.length);
        }
      } else if (callExpr != null &&
          (callExpr.callee is IdentifierExpression ||
              callExpr.callee is PrivateIdentifierExpression)) {
        // Stack: [obj]
        // Duplicate to keep obj for callee access
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        // Stack: [obj, obj]

        final propName = _resolveMemberPropertyName(callExpr.callee);
        if (propName == null) {
          _bc.emit(Op.drop);
          _ctx.adjustStack(-1);
          _bc.emit(Op.drop);
          _ctx.adjustStack(-1);
          _emitInvalidPrivateAccess(
            (callExpr.callee as PrivateIdentifierExpression).name,
            node.line,
          );
          return;
        }
        final atom = _ctx.addConstant(propName);
        _bc.emitU32(Op.getField, atom);
        // Stack: [obj, method]

        // Compile arguments
        final hasSpread = callExpr.arguments.any((a) => a is SpreadElement);
        if (hasSpread) {
          _compileArgsArray(callExpr.arguments);
          _bc.emit(Op.applyMethod);
          _ctx.adjustStack(-2); // obj + func + argsArray -> result
        } else {
          for (final arg in callExpr.arguments) {
            arg.accept(this);
          }
          _bc.emitU16(Op.callMethod, callExpr.arguments.length);
          _ctx.adjustStack(-(callExpr.arguments.length + 1));
        }
      } else if (callExpr != null && callExpr.callee is MemberExpression) {
        // Handle obj?.other.method() - callee is a MemberExpression
        final member = callExpr.callee as MemberExpression;
        // Stack: [obj]
        // Duplicate for the callee (we need obj to get the method)
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        // Stack: [obj, obj]

        if (member.computed) {
          member.property.accept(this);
          _bc.emit(Op.getElem);
          _ctx.adjustStack(-1);
        } else {
          final name = _resolveMemberPropertyName(member.property);
          if (name == null) {
            _bc.emit(Op.drop);
            _ctx.adjustStack(-1);
            _bc.emit(Op.drop);
            _ctx.adjustStack(-1);
            _emitInvalidPrivateAccess(
              (member.property as PrivateIdentifierExpression).name,
              node.line,
            );
            return;
          }
          final atom = _ctx.addConstant(name);
          _bc.emitU32(Op.getField, atom);
        }
        // Stack: [obj, method]

        // Compile arguments
        final hasSpread = callExpr.arguments.any((a) => a is SpreadElement);
        if (hasSpread) {
          _compileArgsArray(callExpr.arguments);
          _bc.emit(Op.applyMethod);
          _ctx.adjustStack(-2);
        } else {
          for (final arg in callExpr.arguments) {
            arg.accept(this);
          }
          _bc.emitU16(Op.callMethod, callExpr.arguments.length);
          _ctx.adjustStack(-(callExpr.arguments.length + 1));
        }
      } else {
        // Computed property call: parser represents `obj?.[expr](...)` and
        // `(obj?.[expr])()` as a CallExpression whose callee is the key expr.
        // Preserve the optional base as the receiver for the eventual call.
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);

        callExpr!.callee.accept(this);
        _bc.emit(Op.getElem);
        _ctx.adjustStack(-1);

        final hasSpread = callExpr.arguments.any((a) => a is SpreadElement);
        if (hasSpread) {
          _compileArgsArray(callExpr.arguments);
          _bc.emit(Op.applyMethod);
          _ctx.adjustStack(-2);
        } else {
          for (final arg in callExpr.arguments) {
            arg.accept(this);
          }
          _bc.emitU16(Op.callMethod, callExpr.arguments.length);
          _ctx.adjustStack(-(callExpr.arguments.length + 1));
        }
      }
    } else if (node.property is IdentifierExpression ||
        node.property is PrivateIdentifierExpression) {
      final name = _resolveMemberPropertyName(node.property);
      if (name == null) {
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
        _emitInvalidPrivateAccess(
          (node.property as PrivateIdentifierExpression).name,
          node.line,
        );
        return;
      }
      final atom = _ctx.addConstant(name);
      _bc.emitU32(Op.getField, atom);
    } else {
      node.property.accept(this);
      _bc.emit(Op.getElem);
      _ctx.adjustStack(-1);
    }
    final endPatch = _bc.emitJump(Op.goto_);

    // Null: replace with undefined
    _bc.patchJump(skipPatch, _bc.offset);
    _bc.emit(Op.drop);
    _ctx.adjustStack(-1);
    _bc.emit(Op.pushUndefined);
    _ctx.adjustStack(1);

    _bc.patchJump(endPatch, _bc.offset);
  }

  @override
  void visitSpreadElement(SpreadElement node) {
    node.argument.accept(this);
    _bc.emit(Op.spread);
  }

  // ===================================================================
  // Visitor: Statements
  // ===================================================================

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    node.expression.accept(this);
    _bc.emit(Op.drop);
    _ctx.adjustStack(-1);
  }

  @override
  void visitBlockStatement(BlockStatement node) {
    _ctx.pushScope();
    _predeclareClassNames(node.body);
    for (final stmt in node.body) {
      stmt.accept(this);
    }
    _emitScopeDisposals();
    _ctx.popScope();
  }

  /// Emit disposal calls for `using`/`await using` declarations in the current scope.
  /// Resources are disposed in LIFO (reverse declaration) order.
  /// Null/undefined resources are skipped; errors during disposal don't prevent
  /// subsequent disposals (each disposal is wrapped in try-catch).
  void _emitScopeDisposals() {
    final disposals = _ctx.scope.usingDisposals;
    if (disposals.isEmpty) return;

    final symbolAtom = _ctx.addConstant('Symbol');
    final disposeAtom = _ctx.addConstant('dispose');
    final asyncDisposeAtom = _ctx.addConstant('asyncDispose');

    // Dispose in reverse order (LIFO)
    for (var i = disposals.length - 1; i >= 0; i--) {
      final d = disposals[i];

      // Skip null/undefined: if resource == null || resource == undefined, skip
      _bc.emitU16(Op.getLoc, d.slot); // [resource]
      _ctx.adjustStack(1);
      _bc.emit(Op.pushNull); // [resource, null]
      _ctx.adjustStack(1);
      _bc.emit(Op.eq); // [isNull]
      _ctx.adjustStack(-1);
      final skipPatch = _bc.emitJump(Op.ifTrue); // []
      _ctx.adjustStack(-1);

      // Wrap each disposal in try-catch so errors don't prevent others
      final catchPatch = _bc.emitJump(Op.catch_);

      // -- try body: call [Symbol.dispose]() --
      _bc.emitU16(Op.getLoc, d.slot); // [resource]
      _ctx.adjustStack(1);
      _bc.emit(Op.dup); // [resource, resource]
      _ctx.adjustStack(1);
      _bc.emitU32(Op.getVar, symbolAtom); // [resource, resource, Symbol]
      _ctx.adjustStack(1);
      if (d.isAsync) {
        _bc.emitU32(Op.getField, asyncDisposeAtom);
      } else {
        _bc.emitU32(Op.getField, disposeAtom);
      }
      _bc.emit(Op.getElem); // [resource, disposeFn]
      _ctx.adjustStack(-1);
      _bc.emitU16(Op.callMethod, 0); // [result]
      if (d.isAsync) {
        _bc.emit(Op.await_);
      }
      _bc.emit(Op.drop); // []
      _ctx.adjustStack(-1);

      _bc.emit(Op.uncatch);
      // Jump past catch
      final endPatch = _bc.emitJump(Op.goto_);

      // -- catch: swallow the error --
      _bc.patchJump(catchPatch, _bc.offset);
      _ctx.adjustStack(1); // exception on stack
      _bc.emit(Op.drop); // drop the error
      _ctx.adjustStack(-1);

      _bc.patchJump(endPatch, _bc.offset);
      _bc.patchJump(skipPatch, _bc.offset);
    }
  }

  @override
  void visitIfStatement(IfStatement node) {
    _bc.setLine(node.line);
    node.test.accept(this);

    if (node.alternate != null) {
      final elsePatch = _bc.emitJump(Op.ifFalse);
      _ctx.adjustStack(-1);
      node.consequent.accept(this);
      final endPatch = _bc.emitJump(Op.goto_);
      _bc.patchJump(elsePatch, _bc.offset);
      node.alternate!.accept(this);
      _bc.patchJump(endPatch, _bc.offset);
    } else {
      final endPatch = _bc.emitJump(Op.ifFalse);
      _ctx.adjustStack(-1);
      node.consequent.accept(this);
      _bc.patchJump(endPatch, _bc.offset);
    }
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    _bc.setLine(node.line);

    final label = _ctx.pendingLabel;
    _ctx.pendingLabel = null;
    final target = _LabelTarget(
      label: label,
      stackDepth: _ctx._currentStackDepth,
      finallyDepth: _finallyBlockStack.length,
      isBreakTarget: true,
      isLoopTarget: true,
    );
    _ctx.labelStack.add(target);

    final loopStart = _bc.offset;

    // Continue target = re-evaluate condition
    // Patch continue jumps to loopStart after body

    node.test.accept(this);
    final exitPatch = _bc.emitJump(Op.ifFalse);
    _ctx.adjustStack(-1);

    node.body.accept(this);

    _bc.emitI32(Op.goto_, loopStart);
    _bc.patchJump(exitPatch, _bc.offset);

    // Patch break/continue
    _patchJumpsHere(target.breakPatches);
    for (final p in target.continuePatches) {
      _bc.patchJump(p, loopStart);
    }

    _ctx.labelStack.removeLast();
  }

  @override
  void visitDoWhileStatement(DoWhileStatement node) {
    _bc.setLine(node.line);

    final label = _ctx.pendingLabel;
    _ctx.pendingLabel = null;
    final target = _LabelTarget(
      label: label,
      stackDepth: _ctx._currentStackDepth,
      finallyDepth: _finallyBlockStack.length,
      isBreakTarget: true,
      isLoopTarget: true,
    );
    _ctx.labelStack.add(target);

    final loopStart = _bc.offset;

    node.body.accept(this);

    final continueTarget = _bc.offset;

    node.test.accept(this);
    final continuePatch = _bc.emitJump(Op.ifTrue);
    _ctx.adjustStack(-1);

    // ifTrue jumps back to loopStart
    _bc.patchJump(continuePatch, loopStart);

    _patchJumpsHere(target.breakPatches);
    for (final p in target.continuePatches) {
      _bc.patchJump(p, continueTarget);
    }

    _ctx.labelStack.removeLast();
  }

  @override
  void visitForStatement(ForStatement node) {
    _bc.setLine(node.line);
    _ctx.pushScope();

    final label = _ctx.pendingLabel;
    _ctx.pendingLabel = null;
    final target = _LabelTarget(
      label: label,
      stackDepth: _ctx._currentStackDepth,
      finallyDepth: _finallyBlockStack.length,
      isBreakTarget: true,
      isLoopTarget: true,
    );
    _ctx.labelStack.add(target);

    // Init
    if (node.init != null) {
      node.init!.accept(this);
      if (node.init is Expression) {
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
      }
    }

    final loopStart = _bc.offset;

    // Test
    int? exitPatch;
    if (node.test != null) {
      node.test!.accept(this);
      exitPatch = _bc.emitJump(Op.ifFalse);
      _ctx.adjustStack(-1);
    }

    // Body
    node.body.accept(this);

    // Update (continue target)
    final updateStart = _bc.offset;
    if (node.update != null) {
      node.update!.accept(this);
      _bc.emit(Op.drop);
      _ctx.adjustStack(-1);
    }

    _bc.emitI32(Op.goto_, loopStart);

    if (exitPatch != null) {
      _bc.patchJump(exitPatch, _bc.offset);
    }

    _patchJumpsHere(target.breakPatches);
    for (final p in target.continuePatches) {
      _bc.patchJump(p, updateStart);
    }

    _ctx.labelStack.removeLast();
    _ctx.popScope();
  }

  @override
  void visitForInStatement(ForInStatement node) {
    _bc.setLine(node.line);
    _ctx.pushScope();

    final label = _ctx.pendingLabel;
    _ctx.pendingLabel = null;
    final target = _LabelTarget(
      label: label,
      stackDepth: _ctx._currentStackDepth,
      finallyDepth: _finallyBlockStack.length,
      isBreakTarget: true,
      isLoopTarget: true,
    );
    _ctx.labelStack.add(target);

    // Determine if destructuring pattern
    Pattern? pattern;
    String? varName;
    MemberExpression? memberTarget;
    String kind = 'let';

    if (node.left is VariableDeclaration) {
      final decl = node.left as VariableDeclaration;
      kind = decl.kind;
      final declarator = decl.declarations.first;
      if (declarator.id is ObjectPattern || declarator.id is ArrayPattern) {
        pattern = declarator.id;
      } else {
        varName = _getDeclaratorName(declarator);
        _ctx.declareLocal(
          varName,
          scope: kind == 'var' ? VarScope.funcScope : VarScope.blockScope,
          isConst: kind == 'const',
          isLexical: kind != 'var',
          scopeLevel: _ctx.scope.depth,
        );
      }
    } else {
      if (node.left is IdentifierExpression) {
        varName = (node.left as IdentifierExpression).name;
      } else if (node.left is MemberExpression) {
        memberTarget = node.left as MemberExpression;
      }
    }

    node.right.accept(this);
    _bc.emit(Op.forInStart);

    final loopStart = _bc.offset;
    _bc.emit(Op.forInNext);
    _ctx.adjustStack(2); // key, done

    // if done, exit
    final exitPatch = _bc.emitJump(Op.ifTrue);
    _ctx.adjustStack(-1);

    // Assign key to loop variable
    if (pattern != null) {
      _compileDestructuringBinding(pattern, declare: true, kind: kind);
    } else if (memberTarget != null) {
      _emitAssignLoopValueToMember(memberTarget);
    } else {
      _emitPutVar(varName!, node.line);
    }

    // Body
    node.body.accept(this);

    _bc.emitI32(Op.goto_, loopStart);

    _bc.patchJump(exitPatch, _bc.offset);
    // On the done path, forInNext leaves [iterator, undefined] on the stack
    // because the key/value is only consumed on the non-done path.
    _bc.emit(Op.drop);
    _bc.emit(Op.drop);
    _ctx.adjustStack(-2);

    _patchJumpsHere(target.breakPatches);
    for (final p in target.continuePatches) {
      _bc.patchJump(p, loopStart);
    }

    _ctx.labelStack.removeLast();
    _ctx.popScope();
  }

  @override
  void visitForOfStatement(ForOfStatement node) {
    _bc.setLine(node.line);
    _ctx.pushScope();

    final label = _ctx.pendingLabel;
    _ctx.pendingLabel = null;
    final target = _LabelTarget(
      label: label,
      stackDepth: _ctx._currentStackDepth,
      finallyDepth: _finallyBlockStack.length,
      isBreakTarget: true,
      isLoopTarget: true,
    );
    _ctx.labelStack.add(target);

    // Determine if destructuring pattern
    Pattern? pattern;
    String? varName;
    MemberExpression? memberTarget;
    String kind = 'let';

    if (node.left is VariableDeclaration) {
      final decl = node.left as VariableDeclaration;
      kind = decl.kind;
      final declarator = decl.declarations.first;
      if (declarator.id is ObjectPattern || declarator.id is ArrayPattern) {
        pattern = declarator.id;
      } else {
        varName = _getDeclaratorName(declarator);
        _ctx.declareLocal(
          varName,
          scope: kind == 'var' ? VarScope.funcScope : VarScope.blockScope,
          isConst: kind == 'const',
          isLexical: kind != 'var',
          scopeLevel: _ctx.scope.depth,
        );
      }
    } else {
      if (node.left is IdentifierExpression) {
        varName = (node.left as IdentifierExpression).name;
      } else if (node.left is MemberExpression) {
        memberTarget = node.left as MemberExpression;
      }
    }

    node.right.accept(this);
    if (node.await) {
      _bc.emit(Op.forAwaitOfStart);
    } else {
      _bc.emit(Op.forOfStart);
    }

    final loopStart = _bc.offset;
    if (node.await) {
      _bc.emit(Op.forAwaitOfNext);
    } else {
      _bc.emit(Op.forOfNext);
    }
    _ctx.adjustStack(2); // value, done

    final exitPatch = _bc.emitJump(Op.ifTrue);
    _ctx.adjustStack(-1);

    if (pattern != null) {
      _compileDestructuringBinding(pattern, declare: true, kind: kind);
    } else if (memberTarget != null) {
      _emitAssignLoopValueToMember(memberTarget);
    } else {
      _emitPutVar(varName!, node.line);
    }

    node.body.accept(this);

    _bc.emitI32(Op.goto_, loopStart);

    _bc.patchJump(exitPatch, _bc.offset);
    // On the done path, forOfNext leaves [iterator, undefined] on the stack
    // because the yielded value is only consumed on the non-done path.
    _bc.emit(Op.drop);
    _bc.emit(Op.drop);
    _ctx.adjustStack(-2);

    _patchJumpsHere(target.breakPatches);
    for (final p in target.continuePatches) {
      _bc.patchJump(p, loopStart);
    }

    _ctx.labelStack.removeLast();
    _ctx.popScope();
  }

  void _emitAssignLoopValueToMember(MemberExpression target) {
    if (target.computed) {
      target.object.accept(this);
      target.property.accept(this);
      _bc.emit(Op.rot3l);
      _bc.emit(Op.putElem);
      _ctx.adjustStack(-3);
      return;
    }

    target.object.accept(this);
    _bc.emit(Op.swap);
    final propName = _resolveMemberPropertyName(target.property);
    if (propName == null) {
      _bc.emit(Op.drop);
      _ctx.adjustStack(-1);
      _emitInvalidPrivateAccess(
        (target.property as PrivateIdentifierExpression).name,
        target.line,
      );
      return;
    }
    final atom = _ctx.addConstant(propName);
    _bc.emitU32(Op.putField, atom);
    _ctx.adjustStack(-2);
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    _bc.setLine(node.line);
    if (_finallyBlockStack.isNotEmpty) {
      if (node.argument != null) {
        node.argument!.accept(this);
      } else {
        _bc.emit(Op.pushUndefined);
        _ctx.adjustStack(1);
      }

      final tempSlot = _ctx.declareLocal(
        '__return_${_bc.offset}',
        scopeLevel: _ctx.scope.depth,
      );
      _bc.emitU16(Op.putLoc, tempSlot);
      _ctx.adjustStack(-1);

      _emitPendingFinallyBlocks();

      _bc.emitU16(Op.getLoc, tempSlot);
      _ctx.adjustStack(1);
      if (_ctx.kind == FunctionKind.asyncFunction ||
          _ctx.kind == FunctionKind.asyncArrow) {
        _bc.emit(Op.returnAsync);
      } else {
        _bc.emit(Op.return_);
      }
      _ctx.adjustStack(-1);
      return;
    }

    if (node.argument != null) {
      // TCO: set _inTailPosition so that call expressions in tail position
      // emit Op.tailCall instead of Op.call. The flag propagates through
      // conditional, logical, and sequence expressions.
      final canTailCall =
          _ctx.kind != FunctionKind.asyncFunction &&
          _ctx.kind != FunctionKind.asyncArrow &&
          _ctx.kind != FunctionKind.generator &&
          _ctx.kind != FunctionKind.asyncGenerator &&
          _finallyBlockStack.isEmpty &&
          _tryCatchDepth == 0;

      if (canTailCall) {
        _inTailPosition = true;
      }
      node.argument!.accept(this);
      _inTailPosition = false;

      if (_ctx.kind == FunctionKind.asyncFunction ||
          _ctx.kind == FunctionKind.asyncArrow) {
        _bc.emit(Op.returnAsync);
      } else {
        _bc.emit(Op.return_);
      }
      _ctx.adjustStack(-1);
    } else {
      if (_ctx.kind == FunctionKind.asyncFunction ||
          _ctx.kind == FunctionKind.asyncArrow) {
        _bc.emit(Op.pushUndefined);
        _ctx.adjustStack(1);
        _bc.emit(Op.returnAsync);
        _ctx.adjustStack(-1);
      } else {
        _bc.emit(Op.returnUndef);
      }
    }
  }

  @override
  void visitBreakStatement(BreakStatement node) {
    _bc.setLine(node.line);
    final target = _findLabelTarget(node.label);
    if (target == null) {
      throw CompileError('break outside of loop/switch', node.line);
    }
    // Drop extra items on the stack (e.g. for-of iterators) to match the
    // target's stack depth.  The break jumps past the loop's own cleanup so
    // we need to clean up here.
    final extra = _ctx._currentStackDepth - target.stackDepth;
    for (var i = 0; i < extra; i++) {
      _bc.emit(Op.drop);
    }
    _emitPendingFinallyBlocks(target.finallyDepth);
    final patch = _bc.emitJump(Op.goto_);
    target.breakPatches.add(patch);
  }

  @override
  void visitContinueStatement(ContinueStatement node) {
    _bc.setLine(node.line);
    final target = _findContinueTarget(node.label);
    if (target == null) {
      throw CompileError('continue outside of loop', node.line);
    }
    _emitPendingFinallyBlocks(target.finallyDepth);
    final patch = _bc.emitJump(Op.goto_);
    target.continuePatches.add(patch);
  }

  _LabelTarget? _findLabelTarget(String? label) {
    if (label == null) {
      // Find innermost breakable target (loop or switch), skipping
      // plain labeled statements that require an explicit label.
      for (var i = _ctx.labelStack.length - 1; i >= 0; i--) {
        if (_ctx.labelStack[i].isBreakTarget) {
          return _ctx.labelStack[i];
        }
      }
      return null;
    }
    for (var i = _ctx.labelStack.length - 1; i >= 0; i--) {
      if (_ctx.labelStack[i].label == label) {
        return _ctx.labelStack[i];
      }
    }
    return null;
  }

  _LabelTarget? _findContinueTarget(String? label) {
    if (label == null) {
      for (var i = _ctx.labelStack.length - 1; i >= 0; i--) {
        if (_ctx.labelStack[i].isLoopTarget) {
          return _ctx.labelStack[i];
        }
      }
      return null;
    }

    final target = _findLabelTarget(label);
    if (target != null && target.isLoopTarget) {
      return target;
    }
    return null;
  }

  @override
  void visitThrowStatement(ThrowStatement node) {
    _bc.setLine(node.line);
    node.argument.accept(this);
    _bc.emit(Op.throw_);
    _ctx.adjustStack(-1);
  }

  @override
  void visitTryStatement(TryStatement node) {
    _bc.setLine(node.line);

    void emitFinallyBlock() {
      if (node.finalizer != null) {
        _compileInlineFinallyBlock(node.finalizer!);
      }
    }

    if (node.finalizer != null) {
      _finallyBlockStack.add(node.finalizer!);
    }
    try {
      if (node.handler != null && node.finalizer != null) {
        // ── try-catch-finally ──
        // Outer catch handles exceptions from try block
        final catchPatch = _bc.emitJump(Op.catch_);

        // Try block
        _tryCatchDepth++;
        node.block.accept(this);
        _tryCatchDepth--;
        _bc.emit(Op.uncatch);

        // Normal path: run finally inline, jump to end
        emitFinallyBlock();
        final endPatch = _bc.emitJump(Op.goto_);

        // Catch block (exception on stack from try)
        _bc.patchJump(catchPatch, _bc.offset);

        // Set up inner catch to handle exceptions from the catch block itself
        final catchRethrowPatch = _bc.emitJump(Op.catch_);

        _ctx.pushScope();
        _ctx.adjustStack(1); // exception value on stack
        if (node.handler!.param != null) {
          final name = node.handler!.param!.name;
          final slot = _ctx.declareLocal(name, scopeLevel: _ctx.scope.depth);
          _bc.emitU16(Op.putLoc, slot);
          _ctx.adjustStack(-1);
        } else {
          _bc.emit(Op.drop);
          _ctx.adjustStack(-1);
        }

        for (final stmt in node.handler!.body.body) {
          stmt.accept(this);
        }
        _ctx.popScope();

        _bc.emit(Op.uncatch);

        // Catch normal exit: run finally inline, jump to end
        emitFinallyBlock();
        final endPatch2 = _bc.emitJump(Op.goto_);

        // Catch-rethrow path: exception from catch block
        _bc.patchJump(catchRethrowPatch, _bc.offset);
        // Exception value is on the stack
        _ctx.adjustStack(1);
        // Save exception to a temp local
        final tempSlot = _ctx.declareLocal(
          '__finally_exc_${_bc.offset}',
          scopeLevel: _ctx.scope.depth,
        );
        _bc.emitU16(Op.putLoc, tempSlot);
        _ctx.adjustStack(-1);

        emitFinallyBlock();

        // Re-throw the saved exception
        _bc.emitU16(Op.getLoc, tempSlot);
        _ctx.adjustStack(1);
        _bc.emit(Op.throw_);
        _ctx.adjustStack(-1);

        _bc.patchJump(endPatch, _bc.offset);
        _bc.patchJump(endPatch2, _bc.offset);
      } else if (node.handler != null) {
        // ── try-catch (no finally) ──
        final catchPatch = _bc.emitJump(Op.catch_);

        _tryCatchDepth++;
        node.block.accept(this);
        _tryCatchDepth--;
        _bc.emit(Op.uncatch);
        final endPatch = _bc.emitJump(Op.goto_);

        _bc.patchJump(catchPatch, _bc.offset);

        _ctx.pushScope();
        _ctx.adjustStack(1);
        if (node.handler!.param != null) {
          final name = node.handler!.param!.name;
          final slot = _ctx.declareLocal(name, scopeLevel: _ctx.scope.depth);
          _bc.emitU16(Op.putLoc, slot);
          _ctx.adjustStack(-1);
        } else {
          _bc.emit(Op.drop);
          _ctx.adjustStack(-1);
        }

        for (final stmt in node.handler!.body.body) {
          stmt.accept(this);
        }
        _ctx.popScope();

        _bc.patchJump(endPatch, _bc.offset);
      } else if (node.finalizer != null) {
        // ── try-finally (no catch) ──
        final catchPatch = _bc.emitJump(Op.catch_);

        _tryCatchDepth++;
        node.block.accept(this);
        _tryCatchDepth--;
        _bc.emit(Op.uncatch);

        // Normal path: run finally inline, jump to end
        emitFinallyBlock();
        final endPatch = _bc.emitJump(Op.goto_);

        // Exception path: exception on stack
        _bc.patchJump(catchPatch, _bc.offset);
        _ctx.adjustStack(1);
        // Save exception to temp local
        final tempSlot = _ctx.declareLocal(
          '__finally_exc_${_bc.offset}',
          scopeLevel: _ctx.scope.depth,
        );
        _bc.emitU16(Op.putLoc, tempSlot);
        _ctx.adjustStack(-1);

        emitFinallyBlock();

        // Re-throw
        _bc.emitU16(Op.getLoc, tempSlot);
        _ctx.adjustStack(1);
        _bc.emit(Op.throw_);
        _ctx.adjustStack(-1);

        _bc.patchJump(endPatch, _bc.offset);
      }
    } finally {
      if (node.finalizer != null) {
        _finallyBlockStack.removeLast();
      }
    }
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    _bc.setLine(node.line);

    final target = _LabelTarget(
      stackDepth: _ctx._currentStackDepth,
      finallyDepth: _finallyBlockStack.length,
      isBreakTarget: true,
    );
    _ctx.labelStack.add(target);

    // Evaluate discriminant
    node.discriminant.accept(this);

    // Compile case tests: for each case, dup discriminant, compile test, strict_eq, if_true -> case body
    final caseJumps = <int>[]; // jump patches for each case
    int? defaultJump;

    for (final c in node.cases) {
      if (c.test == null) {
        // Default case: save for later
        defaultJump = caseJumps.length;
        caseJumps.add(-1); // placeholder
      } else {
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        c.test!.accept(this);
        _bc.emit(Op.strictEq);
        _ctx.adjustStack(-1);
        final casePatch = _bc.emitJump(Op.ifTrue);
        _ctx.adjustStack(-1);
        caseJumps.add(casePatch);
      }
    }

    // Jump to default if no case matched, or to end
    final afterCasesPatch = _bc.emitJump(Op.goto_);

    // Compile case bodies
    for (var i = 0; i < node.cases.length; i++) {
      if (i == defaultJump) {
        // This is where the default entry point goes
        _bc.patchJump(afterCasesPatch, _bc.offset);
      }
      if (caseJumps[i] != -1) {
        _bc.patchJump(caseJumps[i], _bc.offset);
      }

      // Drop discriminant when entering case body
      if (i == 0 || caseJumps[i] != -1) {
        // Only drop once
      }

      for (final stmt in node.cases[i].consequent) {
        stmt.accept(this);
      }
    }

    // If no default, after-cases goes to end
    if (defaultJump == null) {
      _bc.patchJump(afterCasesPatch, _bc.offset);
    }

    // Drop the discriminant
    _bc.emit(Op.drop);
    _ctx.adjustStack(-1);

    _patchJumpsHere(target.breakPatches);
    _ctx.labelStack.removeLast();
  }

  @override
  void visitLabeledStatement(LabeledStatement node) {
    final body = node.body;
    final isLoop =
        body is WhileStatement ||
        body is DoWhileStatement ||
        body is ForStatement ||
        body is ForInStatement ||
        body is ForOfStatement;

    if (isLoop) {
      // Pass the label to the loop so it creates a single target with the label.
      // This way, `continue label` and `break label` both find the loop's target.
      _ctx.pendingLabel = node.label;
      body.accept(this);
      // The loop will have consumed the pending label and handled break/continue.
    } else {
      // Non-loop labeled statement: only break is meaningful.
      final target = _LabelTarget(
        label: node.label,
        stackDepth: _ctx._currentStackDepth,
        finallyDepth: _finallyBlockStack.length,
      );
      _ctx.labelStack.add(target);
      body.accept(this);
      _patchJumpsHere(target.breakPatches);
      _ctx.labelStack.removeLast();
    }
  }

  // ===================================================================
  // Visitor: Declarations
  // ===================================================================

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    for (final decl in node.declarations) {
      _compileVariableDeclarator(decl, node.kind, node.line);
    }
  }

  void _compileVariableDeclarator(
    VariableDeclarator decl,
    String kind,
    int line,
  ) {
    final id = decl.id;

    // Check if this is a destructuring pattern
    if (id is ObjectPattern || id is ArrayPattern) {
      // Compile the initializer (must have one for destructuring)
      if (decl.init != null) {
        decl.init!.accept(this);
      } else {
        _bc.emit(Op.pushUndefined);
        _ctx.adjustStack(1);
      }
      _compileDestructuringBinding(id, declare: true, kind: kind);
      return;
    }

    final name = _getDeclaratorName(decl);
    final isUsing = kind == 'using' || kind == 'await-using';
    final slot = _ctx.declareLocal(
      name,
      scope: kind == 'var' ? VarScope.funcScope : VarScope.blockScope,
      isConst: kind == 'const' || isUsing,
      isLexical: kind != 'var',
      scopeLevel: _ctx.scope.depth,
    );

    if (decl.init != null) {
      final init = decl.init!;
      _compileWithInferredFunctionName(name, init, () {
        init.accept(this);
      });
      _bc.emitU16(Op.putLoc, slot);
      _ctx.adjustStack(-1);
    } else if (kind != 'var') {
      // Lexical bindings leave TDZ when execution reaches their declaration.
      _bc.emit(Op.pushUndefined);
      _ctx.adjustStack(1);
      _bc.emitU16(Op.putLoc, slot);
      _ctx.adjustStack(-1);
    }

    // Track 'using' declarations for scope-exit disposal
    if (isUsing) {
      _ctx.scope.usingDisposals.add((
        slot: slot,
        isAsync: kind == 'await-using',
      ));
    }
  }

  String _getDeclaratorName(VariableDeclarator decl) {
    final id = decl.id;
    if (id is IdentifierPattern) return id.name;
    if (id is IdentifierExpression) return (id as IdentifierExpression).name;
    // Destructuring — for now use a placeholder
    return '_destr_${decl.hashCode}';
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final hoisted =
        _hoistedFunctionDeclStack.isNotEmpty &&
        _hoistedFunctionDeclStack.last.remove(node);
    if (hoisted) {
      return;
    }

    _bc.setLine(node.line);

    // Declare the function name FIRST (hoisted) so the body can reference it
    final name = node.id.name;
    final slot = _ctx.declareLocal(name, scope: VarScope.funcScope);

    // Compile the function body into its own FunctionBytecode
    final funcBytecode = _compileFunction(
      name: node.id.name,
      kind: node.isGenerator ? FunctionKind.generator : FunctionKind.normal,
      params: node.params,
      body: node.body,
      sourceLine: node.line,
      sourceColumn: node.column,
      sourceText: node.toString(),
    );

    // Create closure and store
    final idx = _ctx.addConstant(funcBytecode);
    _bc.emitU16(Op.fclosure, idx);
    _ctx.adjustStack(1);
    _bc.emitU16(Op.putLoc, slot);
    _ctx.adjustStack(-1);
  }

  @override
  void visitAsyncFunctionDeclaration(AsyncFunctionDeclaration node) {
    final hoisted =
        _hoistedFunctionDeclStack.isNotEmpty &&
        _hoistedFunctionDeclStack.last.remove(node);
    if (hoisted) {
      return;
    }

    _bc.setLine(node.line);

    final funcBytecode = _compileFunction(
      name: node.id.name,
      kind: node.isGenerator
          ? FunctionKind.asyncGenerator
          : FunctionKind.asyncFunction,
      params: node.params,
      body: node.body,
      sourceLine: node.line,
      sourceColumn: node.column,
      sourceText: node.toString(),
    );

    final name = node.id.name;
    final slot = _ctx.declareLocal(name, scope: VarScope.funcScope);

    final idx = _ctx.addConstant(funcBytecode);
    _bc.emitU16(Op.fclosure, idx);
    _ctx.adjustStack(1);
    _bc.emitU16(Op.putLoc, slot);
    _ctx.adjustStack(-1);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _bc.setLine(node.line);
    // Declare the class name BEFORE compiling the body so methods can
    // reference the class (e.g. Counter.count++ in constructor).
    int? outerNameSlot;
    int? innerNameSlot;
    if (node.id != null) {
      outerNameSlot = _ctx.declareLocal(
        node.id!.name,
        scope: VarScope.blockScope,
      );
      _ctx.pushScope();
      innerNameSlot = _ctx.declareLocal(
        node.id!.name,
        scopeLevel: _ctx.scope.depth,
      );
    }
    _compileClassBody(
      id: node.id,
      superClass: node.superClass,
      body: node.body,
      line: node.line,
      classBindingSlot: innerNameSlot,
    );
    if (node.id != null) {
      _ctx.popScope();
    }
    if (outerNameSlot != null) {
      _bc.emitU16(Op.putLoc, outerNameSlot);
      _ctx.adjustStack(-1);
    } else {
      _bc.emit(Op.drop);
      _ctx.adjustStack(-1);
    }
  }

  @override
  void visitClassExpression(ClassExpression node) {
    _bc.setLine(node.line);
    final className = node.id?.name ?? _pendingFunctionName;
    _pendingFunctionName = null;
    _pendingFunctionSourceText = null;
    int? classBindingSlot;
    if (node.id != null) {
      _ctx.pushScope();
      classBindingSlot = _ctx.declareLocal(
        node.id!.name,
        scopeLevel: _ctx.scope.depth,
      );
    }
    final effectiveId = className == null
        ? null
        : IdentifierExpression(
            name: className,
            line: node.line,
            column: node.column,
          );
    _compileClassBody(
      id: effectiveId,
      superClass: node.superClass,
      body: node.body,
      line: node.line,
      classBindingSlot: classBindingSlot,
    );
    if (node.id != null) {
      _ctx.popScope();
    }
  }

  /// Compile a class body and leave the constructor function on the stack.
  void _compileClassBody({
    IdentifierExpression? id,
    Expression? superClass,
    required ClassBody body,
    required int line,
    int? classBindingSlot,
  }) {
    final className = id?.name ?? '';
    final privateScopeId = _privateScopeCounter++;
    final privateNames = <String, String>{};

    // Find constructor method
    MethodDefinition? ctorMethod;
    final instanceMethods = <MethodDefinition>[];
    final staticMembers = <ClassMember>[];
    final instanceFields = <FieldDeclaration>[];
    final staticFields = <FieldDeclaration>[];

    for (final member in body.members) {
      if (member is MethodDefinition) {
        if (member.key is PrivateIdentifierExpression) {
          final name = (member.key as PrivateIdentifierExpression).name;
          privateNames[name] ??= _createPrivateStorageName(
            name,
            privateScopeId,
          );
        }
        if (member.kind == MethodKind.constructor) {
          ctorMethod = member;
        } else if (member.isStatic) {
          staticMembers.add(member);
        } else {
          instanceMethods.add(member);
        }
      } else if (member is FieldDeclaration) {
        if (member.key is PrivateIdentifierExpression) {
          final name = (member.key as PrivateIdentifierExpression).name;
          privateNames[name] ??= _createPrivateStorageName(
            name,
            privateScopeId,
          );
        }
        if (member.isStatic) {
          staticFields.add(member);
        } else {
          instanceFields.add(member);
        }
      }
    }

    _privateNameStack.add(privateNames);
    try {
      // If we have a superclass, compile it first and store in a temp var
      int? superSlot;
      final savedSuperVarName = _superVarName;
      if (superClass != null) {
        superClass.accept(this);
        superSlot = _ctx.declareLocal(
          '__super_$className',
          scope: VarScope.blockScope,
        );
        _bc.emitU16(Op.putLoc, superSlot);
        _ctx.adjustStack(-1);
        _superVarName = '__super_$className';
      } else {
        _superVarName = null;
      }

      // Compile the constructor function
      if (ctorMethod != null) {
        // Use the constructor's function body
        final func = ctorMethod.value;
        _staticMethodStack.add(false);
        final funcBytecode = _compileFunction(
          name: className,
          params: func.params,
          body: func.body,
        );
        _staticMethodStack.removeLast();
        final idx = _ctx.addConstant(funcBytecode);
        _bc.emitU16(Op.fclosure, idx);
        _ctx.adjustStack(1);
      } else if (superClass != null) {
        // Default constructor with super(...args): function(...args) { super(...args); }
        // Compile a constructor that calls super with all arguments
        final funcBytecode = _compileDefaultConstructorWithSuper(
          className,
          superSlot!,
        );
        final idx = _ctx.addConstant(funcBytecode);
        _bc.emitU16(Op.fclosure, idx);
        _ctx.adjustStack(1);
      } else {
        // Default empty constructor: function() {}
        final funcBytecode = _compileFunction(
          name: className,
          params: [],
          body: BlockStatement(body: [], line: line, column: 0),
        );
        final idx = _ctx.addConstant(funcBytecode);
        _bc.emitU16(Op.fclosure, idx);
        _ctx.adjustStack(1);
      }
      // Stack: [constructor]

      // Save constructor to temp local for later use
      final ctorTempSlot = _ctx.declareLocal(
        '__ctor_$className',
        scope: VarScope.blockScope,
      );
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      _bc.emitU16(Op.putLoc, ctorTempSlot);
      _ctx.adjustStack(-1);

      if (classBindingSlot != null) {
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        _bc.emitU16(Op.putLoc, classBindingSlot);
        _ctx.adjustStack(-1);
      }

      // Set up prototype
      // constructor.prototype = Object.create(superProto || Object.prototype)
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);

      // Create prototype object
      _bc.emit(Op.object);
      _ctx.adjustStack(1);
      // Stack: [constructor, constructor, proto]

      // If superclass, set prototype chain
      if (superClass != null) {
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        // Get super.prototype
        _bc.emitU16(Op.getLoc, superSlot!);
        _ctx.adjustStack(1);
        final protoAtom = _ctx.addConstant('prototype');
        _bc.emitU32(Op.getField, protoAtom);
        // Stack: [ctor, ctor, proto, proto, superProto]
        // Set proto.__proto__ = superProto
        final protoAtom2 = _ctx.addConstant('__proto__');
        _bc.emitU32(Op.putField, protoAtom2);
        _ctx.adjustStack(-2);
        // Stack: [ctor, ctor, proto]
      }

      // Set proto.constructor = ctor (non-enumerable, before methods)
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      // Stack: [ctor, ctor, proto, proto]
      _bc.emitU16(Op.getLoc, ctorTempSlot);
      _ctx.adjustStack(1);
      // Stack: [ctor, ctor, proto, proto, ctor]
      {
        final constructorAtom = _ctx.addConstant('constructor');
        _bc.emitU32(Op.defineMethod, constructorAtom);
        _ctx.adjustStack(-1);
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
      }
      // Stack: [ctor, ctor, proto]

      // Add instance methods to prototype
      for (final method in instanceMethods) {
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        // Stack: [..., proto, proto]

        final func = method.value;
        String methodName = '';
        if (!method.computed) {
          if (method.key is IdentifierExpression ||
              method.key is PrivateIdentifierExpression) {
            methodName = method.key is PrivateIdentifierExpression
                ? _getPrivateStorageName(
                    (method.key as PrivateIdentifierExpression).name,
                  )
                : _propName(method.key);
          } else {
            methodName = _getPropertyKeyName(method.key);
          }
        }
        final functionName = _classMemberFunctionName(methodName, method.kind);

        _staticMethodStack.add(false);
        final isAsync = func is AsyncFunctionExpression;
        final FunctionKind methodKind;
        if (isAsync && func.isGenerator) {
          methodKind = FunctionKind.asyncGenerator;
        } else if (isAsync) {
          methodKind = FunctionKind.asyncFunction;
        } else if (func.isGenerator) {
          methodKind = FunctionKind.generator;
        } else {
          methodKind = FunctionKind.normal;
        }
        final funcBytecode = _compileFunction(
          name: functionName,
          params: func.params,
          body: func.body,
          kind: methodKind,
        );
        _staticMethodStack.removeLast();
        final funcIdx = _ctx.addConstant(funcBytecode);
        _bc.emitU16(Op.fclosure, funcIdx);
        _ctx.adjustStack(1);
        // Stack: [..., proto, proto, methodFunc]

        if (method.computed) {
          method.key.accept(this);
          // Stack: [..., proto, proto, methodFunc, key]
          switch (method.kind) {
            case MethodKind.get:
              _bc.emit(Op.defineGetterElem);
              _ctx.adjustStack(-2);
              _bc.emit(Op.drop);
              _ctx.adjustStack(-1);
            case MethodKind.set:
              _bc.emit(Op.defineSetterElem);
              _ctx.adjustStack(-2);
              _bc.emit(Op.drop);
              _ctx.adjustStack(-1);
            default:
              _bc.emit(Op.defineMethodElem);
              _ctx.adjustStack(-2);
              _bc.emit(Op.drop);
              _ctx.adjustStack(-1);
          }
        } else {
          final nameAtom = _ctx.addConstant(methodName);
          switch (method.kind) {
            case MethodKind.method:
              _bc.emitU32(Op.defineMethod, nameAtom);
              _ctx.adjustStack(-1);
              _bc.emit(Op.drop);
              _ctx.adjustStack(-1);
            case MethodKind.get:
              _bc.emitU32(Op.defineGetter, nameAtom);
              _ctx.adjustStack(-1);
              _bc.emit(Op.drop);
              _ctx.adjustStack(-1);
            case MethodKind.set:
              _bc.emitU32(Op.defineSetter, nameAtom);
              _ctx.adjustStack(-1);
              _bc.emit(Op.drop);
              _ctx.adjustStack(-1);
            default:
              _bc.emitU32(Op.defineMethod, nameAtom);
              _ctx.adjustStack(-1);
              _bc.emit(Op.drop);
              _ctx.adjustStack(-1);
          }
        }
        // Stack: [..., proto]
      }

      // Set constructor.prototype = proto
      final protoNameAtom = _ctx.addConstant('prototype');
      _bc.emitU32(Op.putField, protoNameAtom);
      _ctx.adjustStack(-2);
      // Stack: [constructor]

      // Add static members to constructor in declaration order so static
      // fields and static blocks observe the right initialization sequence.
      for (final member in body.members) {
        if (member is MethodDefinition && member.isStatic) {
          _bc.emit(Op.dup);
          _ctx.adjustStack(1);

          String methodName = '';
          if (!member.computed) {
            if (member.key is IdentifierExpression ||
                member.key is PrivateIdentifierExpression) {
              methodName = member.key is PrivateIdentifierExpression
                  ? _getPrivateStorageName(
                      (member.key as PrivateIdentifierExpression).name,
                    )
                  : _propName(member.key);
            } else {
              methodName = _getPropertyKeyName(member.key);
            }
          }

          final func = member.value;
          final functionName = _classMemberFunctionName(
            methodName,
            member.kind,
          );
          _staticMethodStack.add(true);
          final isAsyncStatic = func is AsyncFunctionExpression;
          final FunctionKind staticMethodKind;
          if (isAsyncStatic && func.isGenerator) {
            staticMethodKind = FunctionKind.asyncGenerator;
          } else if (isAsyncStatic) {
            staticMethodKind = FunctionKind.asyncFunction;
          } else if (func.isGenerator) {
            staticMethodKind = FunctionKind.generator;
          } else {
            staticMethodKind = FunctionKind.normal;
          }
          final funcBytecode = _compileFunction(
            name: functionName,
            params: func.params,
            body: func.body,
            kind: staticMethodKind,
          );
          _staticMethodStack.removeLast();
          final funcIdx = _ctx.addConstant(funcBytecode);
          _bc.emitU16(Op.fclosure, funcIdx);
          _ctx.adjustStack(1);

          if (member.computed) {
            member.key.accept(this);
            switch (member.kind) {
              case MethodKind.get:
                _bc.emit(Op.defineGetterElem);
                _ctx.adjustStack(-2);
                _bc.emit(Op.drop);
                _ctx.adjustStack(-1);
              case MethodKind.set:
                _bc.emit(Op.defineSetterElem);
                _ctx.adjustStack(-2);
                _bc.emit(Op.drop);
                _ctx.adjustStack(-1);
              default:
                _bc.emit(Op.defineMethodElem);
                _ctx.adjustStack(-2);
                _bc.emit(Op.drop);
                _ctx.adjustStack(-1);
            }
          } else {
            final nameAtom = _ctx.addConstant(methodName);
            switch (member.kind) {
              case MethodKind.method:
                _bc.emitU32(Op.defineMethod, nameAtom);
                _ctx.adjustStack(-1);
                _bc.emit(Op.drop);
                _ctx.adjustStack(-1);
              case MethodKind.get:
                _bc.emitU32(Op.defineGetter, nameAtom);
                _ctx.adjustStack(-1);
                _bc.emit(Op.drop);
                _ctx.adjustStack(-1);
              case MethodKind.set:
                _bc.emitU32(Op.defineSetter, nameAtom);
                _ctx.adjustStack(-1);
                _bc.emit(Op.drop);
                _ctx.adjustStack(-1);
              default:
                _bc.emitU32(Op.defineMethod, nameAtom);
                _ctx.adjustStack(-1);
                _bc.emit(Op.drop);
                _ctx.adjustStack(-1);
            }
          }
        } else if (member is FieldDeclaration && member.isStatic) {
          final field = member;
          if (field.initializer == null) {
            continue;
          }
          _bc.emit(Op.dup);
          _ctx.adjustStack(1);
          _bc.emit(Op.dup);
          _ctx.adjustStack(1);
          final initBytecode = _compileStaticFieldInitializer(field);
          final initIdx = _ctx.addConstant(initBytecode);
          _bc.emitU16(Op.fclosure, initIdx);
          _ctx.adjustStack(1);
          _bc.emitU16(Op.callMethod, 0);
          _ctx.adjustStack(-1);
          if (!field.isPrivate &&
              (field.key is IdentifierExpression ||
                  field.key is PrivateIdentifierExpression)) {
            final nameAtom = _ctx.addConstant(_propName(field.key));
            _bc.emitU32(Op.putField, nameAtom);
            _ctx.adjustStack(-2);
          } else if (field.key is PrivateIdentifierExpression) {
            final nameAtom = _ctx.addConstant(
              _getPrivateStorageName(
                (field.key as PrivateIdentifierExpression).name,
              ),
            );
            _bc.emitU32(Op.putField, nameAtom);
            _ctx.adjustStack(-2);
          } else {
            _bc.emit(Op.drop);
            _ctx.adjustStack(-1);
            _bc.emit(Op.drop);
            _ctx.adjustStack(-1);
          }
        } else if (member is StaticBlockDeclaration) {
          _bc.emit(Op.dup);
          _ctx.adjustStack(1);

          _staticMethodStack.add(true);
          final blockBytecode = _compileFunction(
            name: '',
            params: const [],
            body: member.body,
            kind: FunctionKind.normal,
          );
          _staticMethodStack.removeLast();

          final funcIdx = _ctx.addConstant(blockBytecode);
          _bc.emitU16(Op.fclosure, funcIdx);
          _ctx.adjustStack(1);
          _bc.emitU16(Op.callMethod, 0);
          _ctx.adjustStack(-1);
          _bc.emit(Op.drop);
          _ctx.adjustStack(-1);
        }
      }

      // If extends, set constructor.__proto__ = superClass (for static method inheritance)
      if (superClass != null) {
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        _bc.emitU16(Op.getLoc, superSlot!);
        _ctx.adjustStack(1);
        final proto2 = _ctx.addConstant('__proto__');
        _bc.emitU32(Op.putField, proto2);
        _ctx.adjustStack(-2);
      }

      // Stack: [constructor]
      // Instance fields are initialized in the constructor at runtime
      // We handle this by injecting field initialization at the start of _callConstructor
      // For now, store field info on the constructor function
      if (instanceFields.isNotEmpty) {
        // Compile field initializers as a function that takes `this` and initializes fields
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        final initBytecode = _compileFieldInitializer(instanceFields);
        final initIdx = _ctx.addConstant(initBytecode);
        _bc.emitU16(Op.fclosure, initIdx);
        _ctx.adjustStack(1);
        final initAtom = _ctx.addConstant('__fieldInit__');
        _bc.emitU32(Op.putField, initAtom);
        _ctx.adjustStack(-2);
      }

      // Stack: [constructor]
      _superVarName = savedSuperVarName;
    } finally {
      _privateNameStack.removeLast();
    }
  }

  String _classMemberFunctionName(String methodName, MethodKind kind) {
    return switch (kind) {
      MethodKind.get when methodName.isNotEmpty => 'get $methodName',
      MethodKind.set when methodName.isNotEmpty => 'set $methodName',
      _ => methodName,
    };
  }

  FunctionBytecode _compileDefaultConstructorWithSuper(
    String className,
    int superSlot,
  ) {
    _pushFunction(
      name: className,
      kind: FunctionKind.normal,
      argCount: 1,
      hasRest: true,
    );
    _ctx.declareArg('args');

    // super(...args) — call super constructor with this binding and forwarded args
    // Stack: push this (receiver), push super constructor, push args array
    _bc.emit(Op.getThis);
    _ctx.adjustStack(1);
    _emitGetVar(_superVarName!, 0);
    _bc.emitU16(Op.getArg, 0); // args rest array
    _ctx.adjustStack(1);
    _bc.emit(Op.applyMethod);
    _ctx.adjustStack(-2); // [this, func, argsArray] -> [result]
    _bc.emit(Op.drop);
    _ctx.adjustStack(-1);
    _bc.emit(Op.returnUndef);

    return _popFunction();
  }

  FunctionBytecode _compileFieldInitializer(List<FieldDeclaration> fields) {
    _pushFunction(
      name: '__fieldInit__',
      kind: FunctionKind.normal,
      argCount: 0,
    );

    for (final field in fields) {
      if (field.key is! IdentifierExpression &&
          field.key is! PrivateIdentifierExpression) {
        continue;
      }
      final fieldName = field.key is PrivateIdentifierExpression
          ? _getPrivateStorageName(
              (field.key as PrivateIdentifierExpression).name,
            )
          : _propName(field.key);

      // this.fieldName = initializer ?? undefined
      _bc.emit(Op.getThis);
      _ctx.adjustStack(1);
      if (field.initializer != null) {
        field.initializer!.accept(this);
      } else {
        _bc.emit(Op.pushUndefined);
        _ctx.adjustStack(1);
      }
      final atom = _ctx.addConstant(fieldName);
      _bc.emitU32(Op.putField, atom);
      _ctx.adjustStack(-2);
    }

    _bc.emit(Op.returnUndef);
    return _popFunction();
  }

  FunctionBytecode _compileStaticFieldInitializer(FieldDeclaration field) {
    return _compileFunction(
      name: '',
      kind: FunctionKind.normal,
      params: const [],
      body: BlockStatement(
        body: [
          ReturnStatement(
            argument: field.initializer,
            line: field.line,
            column: field.column,
          ),
        ],
        line: field.line,
        column: field.column,
      ),
    );
  }

  @override
  void visitEmptyStatement(EmptyStatement node) {
    // Nothing to emit
  }

  @override
  void visitWithStatement(WithStatement node) {
    if (_ctx.isStrict) {
      _emitString(
        'Strict mode code may not include a with statement',
        node.line,
      );
      _bc.emit(Op.throw_);
      _ctx.adjustStack(-1);
      return;
    }

    node.object.accept(this);
    _bc.emit(Op.enterWith);
    _ctx.adjustStack(-1);
    _withDepth += 1;
    node.body.accept(this);
    _withDepth -= 1;
    _bc.emit(Op.leaveWith);
  }

  // ===================================================================
  // Visitor: Yet to implement (stubs)
  // ===================================================================

  @override
  void visitRegexLiteralExpression(RegexLiteralExpression node) {
    // Push pattern and flags as constants, then emit regexp opcode
    _emitString(node.pattern, node.line, node.column);
    _emitString(node.flags, node.line, node.column);
    _bc.setLine(node.line, node.column);
    _bc.emit(Op.regexp);
    _ctx.adjustStack(-1); // 2 in, 1 out
  }

  @override
  void visitTemplateLiteralExpression(TemplateLiteralExpression node) {
    _bc.setLine(node.line);
    // Sub-expressions inside a template literal are never in tail position.
    final savedTail = _inTailPosition;
    _inTailPosition = false;

    // Compile as string concatenation
    if (node.quasis.isEmpty && node.expressions.isEmpty) {
      _bc.emit(Op.pushEmptyString);
      _ctx.adjustStack(1);
      _inTailPosition = savedTail;
      return;
    }

    // Start with the first quasi
    _emitString(node.quasis[0], node.line);

    for (var i = 0; i < node.expressions.length; i++) {
      node.expressions[i].accept(this);
      _bc.emit(Op.add);
      _ctx.adjustStack(-1);
      if (i + 1 < node.quasis.length && node.quasis[i + 1].isNotEmpty) {
        _emitString(node.quasis[i + 1], node.line);
        _bc.emit(Op.add);
        _ctx.adjustStack(-1);
      }
    }
    _inTailPosition = savedTail;
  }

  void _compileTemplateObject(TemplateLiteralExpression node) {
    _bc.emit(Op.array);
    _ctx.adjustStack(1);
    for (final quasi in node.quasis) {
      _emitString(quasi, node.line);
      _bc.emit(Op.arrayAppend);
      _ctx.adjustStack(-1);
    }

    _bc.emit(Op.dup);
    _ctx.adjustStack(1);

    _bc.emit(Op.array);
    _ctx.adjustStack(1);
    for (final quasi in node.quasis) {
      _emitString(quasi, node.line);
      _bc.emit(Op.arrayAppend);
      _ctx.adjustStack(-1);
    }

    final rawAtom = _ctx.addConstant('raw');
    _bc.emitU32(Op.putField, rawAtom);
    _ctx.adjustStack(-2);
  }

  @override
  void visitTaggedTemplateExpression(TaggedTemplateExpression node) {
    _bc.setLine(node.line);

    final isTailCall = _inTailPosition;
    _inTailPosition = false;

    final argCount = node.quasi.expressions.length + 1;

    if (node.tag is MemberExpression) {
      final member = node.tag as MemberExpression;

      member.object.accept(this);
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);

      if (member.computed) {
        member.property.accept(this);
        _bc.emit(Op.getElem);
        _ctx.adjustStack(-1);
      } else {
        final name = _resolveMemberPropertyName(member.property);
        if (name == null) {
          _bc.emit(Op.drop);
          _ctx.adjustStack(-1);
          _bc.emit(Op.drop);
          _ctx.adjustStack(-1);
          _emitInvalidPrivateAccess(
            (member.property as PrivateIdentifierExpression).name,
            node.line,
          );
          _inTailPosition = isTailCall;
          return;
        }
        final atom = _ctx.addConstant(name);
        _bc.emitU32(Op.getField, atom);
      }

      _compileTemplateObject(node.quasi);
      for (final expression in node.quasi.expressions) {
        expression.accept(this);
      }

      if (isTailCall) {
        _bc.emitU16(Op.tailCallMethod, argCount);
      } else {
        _bc.emitU16(Op.callMethod, argCount);
      }
      _ctx.adjustStack(-(argCount + 1));
    } else {
      node.tag.accept(this);
      _compileTemplateObject(node.quasi);
      for (final expression in node.quasi.expressions) {
        expression.accept(this);
      }

      if (isTailCall) {
        _bc.emitU16(Op.tailCall, argCount);
      } else {
        _bc.emitU16(Op.call, argCount);
      }
      _ctx.adjustStack(-argCount);
    }

    _inTailPosition = isTailCall;
  }

  @override
  void visitSuperExpression(SuperExpression node) {
    if (_superVarName != null) {
      _emitGetVar(_superVarName!, node.line);
    } else {
      _bc.emit(Op.pushUndefined);
      _ctx.adjustStack(1);
    }
  }

  @override
  void visitPrivateIdentifierExpression(PrivateIdentifierExpression node) {
    _emitInvalidPrivateAccess(node.name, node.line);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    // Handled in class compilation
  }

  @override
  void visitStaticBlockDeclaration(StaticBlockDeclaration node) {
    // Handled in class compilation
  }

  @override
  void visitUsingStatement(UsingStatement node) {
    // UsingStatement has an explicit body. Create a scope, declare the
    // resources, compile the body, then dispose.
    _ctx.pushScope();
    for (final decl in node.declarations) {
      _compileVariableDeclarator(
        decl,
        node.await ? 'await-using' : 'using',
        node.line,
      );
    }
    node.body.accept(this);
    _emitScopeDisposals();
    _ctx.popScope();
  }

  @override
  void visitAwaitUsingDeclaration(AwaitUsingDeclaration node) {
    // Compiled via visitVariableDeclaration path with kind='await-using'
    for (final decl in node.declarations) {
      _compileVariableDeclarator(decl, 'await-using', node.line);
    }
  }

  @override
  void visitCatchClause(CatchClause node) {
    // Handled by visitTryStatement
  }

  @override
  void visitSwitchCase(SwitchCase node) {
    // Handled by visitSwitchStatement
  }

  @override
  void visitProgram(Program node) {
    _predeclareClassNames(node.body);
    for (final stmt in node.body) {
      stmt.accept(this);
    }
  }

  void _predeclareClassNames(List<Statement> statements) {
    for (final stmt in statements) {
      final effectiveStmt = stmt is ExportDeclarationStatement
          ? stmt.declaration
          : stmt;

      if (effectiveStmt is ClassDeclaration && effectiveStmt.id != null) {
        _ctx.declareLocal(
          effectiveStmt.id!.name,
          scope: VarScope.blockScope,
          isLexical: true,
          scopeLevel: _ctx.scope.depth,
        );
      } else if (effectiveStmt is VariableDeclaration &&
          effectiveStmt.kind != 'var') {
        final isConst =
            effectiveStmt.kind == 'const' ||
            effectiveStmt.kind == 'using' ||
            effectiveStmt.kind == 'await-using';
        for (final decl in effectiveStmt.declarations) {
          _predeclareLexicalPattern(decl.id, isConst: isConst);
        }
      }
    }
  }

  void _predeclareLexicalPattern(dynamic pattern, {required bool isConst}) {
    if (pattern is IdentifierPattern) {
      _ctx.declareLocal(
        pattern.name,
        scope: VarScope.blockScope,
        isConst: isConst,
        isLexical: true,
        scopeLevel: _ctx.scope.depth,
      );
      return;
    }
    if (pattern is IdentifierExpression) {
      _ctx.declareLocal(
        pattern.name,
        scope: VarScope.blockScope,
        isConst: isConst,
        isLexical: true,
        scopeLevel: _ctx.scope.depth,
      );
      return;
    }
    if (pattern is ObjectPattern) {
      for (final prop in pattern.properties) {
        _predeclareLexicalPattern(prop.value, isConst: isConst);
      }
      if (pattern.restElement != null) {
        _predeclareLexicalPattern(pattern.restElement!, isConst: isConst);
      }
      return;
    }
    if (pattern is ArrayPattern) {
      for (final element in pattern.elements) {
        if (element != null) {
          _predeclareLexicalPattern(element, isConst: isConst);
        }
      }
      if (pattern.restElement != null) {
        _predeclareLexicalPattern(pattern.restElement!, isConst: isConst);
      }
      return;
    }
    if (pattern is AssignmentPattern) {
      _predeclareLexicalPattern(pattern.left, isConst: isConst);
    }
  }

  /// Pre-declare all `var` bindings in a function body so closures can
  /// capture them. `var` declarations hoist to the top of the function
  /// scope, so inner functions must be able to see them even if the
  /// declaration appears later in source order.
  void _hoistVarDeclarations(List<Statement> statements) {
    for (final stmt in statements) {
      _collectVarNames(stmt);
    }
  }

  void _collectVarNames(Statement stmt) {
    final effectiveStmt = stmt is ExportDeclarationStatement
        ? stmt.declaration
        : stmt;

    if (effectiveStmt is VariableDeclaration && effectiveStmt.kind == 'var') {
      for (final decl in effectiveStmt.declarations) {
        _collectVarNamesFromPattern(decl.id);
      }
    } else if (effectiveStmt is BlockStatement) {
      for (final s in effectiveStmt.body) {
        _collectVarNames(s);
      }
    } else if (effectiveStmt is IfStatement) {
      _collectVarNames(effectiveStmt.consequent);
      if (effectiveStmt.alternate != null) {
        _collectVarNames(effectiveStmt.alternate!);
      }
    } else if (effectiveStmt is WhileStatement) {
      _collectVarNames(effectiveStmt.body);
    } else if (effectiveStmt is DoWhileStatement) {
      _collectVarNames(effectiveStmt.body);
    } else if (effectiveStmt is ForStatement) {
      if (effectiveStmt.init is VariableDeclaration) {
        final decl = effectiveStmt.init as VariableDeclaration;
        if (decl.kind == 'var') {
          for (final d in decl.declarations) {
            _collectVarNamesFromPattern(d.id);
          }
        }
      }
      _collectVarNames(effectiveStmt.body);
    } else if (effectiveStmt is ForInStatement) {
      if (effectiveStmt.left is VariableDeclaration) {
        final decl = effectiveStmt.left as VariableDeclaration;
        if (decl.kind == 'var') {
          for (final d in decl.declarations) {
            _collectVarNamesFromPattern(d.id);
          }
        }
      }
      _collectVarNames(effectiveStmt.body);
    } else if (effectiveStmt is ForOfStatement) {
      if (effectiveStmt.left is VariableDeclaration) {
        final decl = effectiveStmt.left as VariableDeclaration;
        if (decl.kind == 'var') {
          for (final d in decl.declarations) {
            _collectVarNamesFromPattern(d.id);
          }
        }
      }
      _collectVarNames(effectiveStmt.body);
    } else if (effectiveStmt is LabeledStatement) {
      _collectVarNames(effectiveStmt.body);
    } else if (effectiveStmt is TryStatement) {
      _collectVarNames(effectiveStmt.block);
      if (effectiveStmt.handler != null) {
        _collectVarNames(effectiveStmt.handler!.body);
      }
      if (effectiveStmt.finalizer != null) {
        _collectVarNames(effectiveStmt.finalizer!);
      }
    } else if (effectiveStmt is SwitchStatement) {
      for (final c in effectiveStmt.cases) {
        for (final s in c.consequent) {
          _collectVarNames(s);
        }
      }
    }
    // Note: do NOT recurse into FunctionDeclaration, ClassDeclaration, etc.
    // var declarations inside nested functions don't hoist out.
  }

  void _collectVarNamesFromPattern(Pattern pattern) {
    if (pattern is IdentifierPattern) {
      // Always declare in function scope — var hoists to function top
      // regardless of whether the name exists in parent scopes
      _ctx.declareLocal(pattern.name, scope: VarScope.funcScope);
    } else if (pattern is ObjectPattern) {
      for (final prop in pattern.properties) {
        _collectVarNamesFromPattern(prop.value);
      }
      if (pattern.restElement != null) {
        _collectVarNamesFromPattern(pattern.restElement!);
      }
    } else if (pattern is ArrayPattern) {
      for (final elem in pattern.elements) {
        if (elem != null) _collectVarNamesFromPattern(elem);
      }
      if (pattern.restElement != null) {
        _collectVarNamesFromPattern(pattern.restElement!);
      }
    } else if (pattern is AssignmentPattern) {
      _collectVarNamesFromPattern(pattern.left);
    }
  }

  void _hoistFunctionDeclarations(List<Statement> statements) {
    if (_hoistedFunctionDeclStack.isEmpty) {
      return;
    }

    final hoistedNodes = _hoistedFunctionDeclStack.last;
    for (final stmt in statements) {
      final effectiveStmt = stmt is ExportDeclarationStatement
          ? stmt.declaration
          : stmt;

      if (effectiveStmt is AsyncFunctionDeclaration) {
        _ctx.declareLocal(effectiveStmt.id.name, scope: VarScope.funcScope);
      } else if (effectiveStmt is FunctionDeclaration) {
        _ctx.declareLocal(effectiveStmt.id.name, scope: VarScope.funcScope);
      }
    }

    for (final stmt in statements) {
      final effectiveStmt = stmt is ExportDeclarationStatement
          ? stmt.declaration
          : stmt;

      if (effectiveStmt is AsyncFunctionDeclaration) {
        _emitHoistedAsyncFunctionDeclaration(effectiveStmt, hoistedNodes);
      } else if (effectiveStmt is FunctionDeclaration) {
        _emitHoistedFunctionDeclaration(effectiveStmt, hoistedNodes);
      }
    }
  }

  void _emitHoistedFunctionDeclaration(
    FunctionDeclaration node,
    Set<Statement> hoistedNodes,
  ) {
    final name = node.id.name;
    final slot = _ctx.declareLocal(name, scope: VarScope.funcScope);
    final funcBytecode = _compileFunction(
      name: name,
      kind: node.isGenerator ? FunctionKind.generator : FunctionKind.normal,
      params: node.params,
      body: node.body,
      sourceLine: node.line,
      sourceColumn: node.column,
      sourceText: node.toString(),
    );

    final idx = _ctx.addConstant(funcBytecode);
    _bc.emitU16(Op.fclosure, idx);
    _ctx.adjustStack(1);
    _bc.emitU16(Op.putLoc, slot);
    _ctx.adjustStack(-1);
    hoistedNodes.add(node);
  }

  void _emitHoistedAsyncFunctionDeclaration(
    AsyncFunctionDeclaration node,
    Set<Statement> hoistedNodes,
  ) {
    final name = node.id.name;
    final slot = _ctx.declareLocal(name, scope: VarScope.funcScope);
    final funcBytecode = _compileFunction(
      name: name,
      kind: node.isGenerator
          ? FunctionKind.asyncGenerator
          : FunctionKind.asyncFunction,
      params: node.params,
      body: node.body,
      sourceLine: node.line,
      sourceColumn: node.column,
      sourceText: node.toString(),
    );

    final idx = _ctx.addConstant(funcBytecode);
    _bc.emitU16(Op.fclosure, idx);
    _ctx.adjustStack(1);
    _bc.emitU16(Op.putLoc, slot);
    _ctx.adjustStack(-1);
    hoistedNodes.add(node);
  }

  // ---- Destructuring patterns ----

  /// Compile a destructuring binding pattern.
  /// Expects the value to destructure on top of the stack.
  /// After this, the value is consumed (popped).
  /// If [declare] is true, new locals are declared with [kind].
  /// If [declare] is false, existing variables are assigned.
  void _compileDestructuringBinding(
    Pattern pattern, {
    bool declare = true,
    String kind = 'let',
  }) {
    if (pattern is IdentifierPattern) {
      // Simple binding — value is on stack
      if (declare) {
        final slot = _ctx.declareLocal(
          pattern.name,
          scope: kind == 'var' ? VarScope.funcScope : VarScope.blockScope,
          isConst: kind == 'const',
          isLexical: kind != 'var',
          scopeLevel: _ctx.scope.depth,
        );
        _bc.emitU16(Op.putLoc, slot);
        _ctx.adjustStack(-1);
      } else {
        _emitSetVar(pattern.name, pattern.line);
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
      }
    } else if (pattern is ObjectPattern) {
      _compileObjectPattern(pattern, declare: declare, kind: kind);
    } else if (pattern is ArrayPattern) {
      _compileArrayPattern(pattern, declare: declare, kind: kind);
    } else if (pattern is AssignmentPattern) {
      _compileAssignmentPattern(pattern, declare: declare, kind: kind);
    } else if (pattern is ExpressionPattern) {
      // e.g. ...obj.prop — compile as assignment to the expression
      _compileExpressionPatternAssign(pattern);
    } else {
      // Unknown pattern — just drop the value
      _bc.emit(Op.drop);
      _ctx.adjustStack(-1);
    }
  }

  void _emitDestructuringValidator(String helperName, int line) {
    _bc.setLine(line);
    if (helperName == '__validateArrayDestructure__') {
      _bc.emit(Op.validateArrayDestructure);
      return;
    }
    if (helperName == '__validateObjectDestructure__') {
      _bc.emit(Op.validateObjectDestructure);
      return;
    }

    final atom = _ctx.addConstant(helperName);
    _bc.emit(Op.dup);
    _ctx.adjustStack(1);
    _bc.emitU32(Op.getVar, atom);
    _ctx.adjustStack(1);
    _bc.emit(Op.rot3l);
    _bc.emitU16(Op.call, 1);
    _ctx.adjustStack(-1);
    _bc.emit(Op.drop);
    _ctx.adjustStack(-1);
  }

  void _compileObjectPattern(
    ObjectPattern pattern, {
    bool declare = true,
    String kind = 'let',
  }) {
    // Stack: [obj]
    _emitDestructuringValidator('__validateObjectDestructure__', pattern.line);

    final computedKeySlots = <int?>[];

    // For each property, dup obj, get property, bind to the pattern value
    for (final prop in pattern.properties) {
      _bc.emit(Op.dup); // [obj, obj]
      _ctx.adjustStack(1);

      final captureRef = _canCaptureDestructuringReference(prop.value);
      int? sourceObjSlot;

      if (captureRef) {
        sourceObjSlot = _ctx.declareLocal(
          '__obj_pat_src_${_objectPatternTempCounter++}',
          scopeLevel: _ctx.scope.depth,
        );
        _bc.emitU16(Op.putLoc, sourceObjSlot);
        _ctx.adjustStack(-1);
      }

      // Get the property by key
      if (prop.computed) {
        final keySlot = _ctx.declareLocal(
          '__obj_pat_key_${_objectPatternTempCounter++}',
          scopeLevel: _ctx.scope.depth,
        );
        computedKeySlots.add(keySlot);
        _inTailPosition = false;
        prop.keyExpression!.accept(this);
        _bc.emit(Op.toPropertyKey);
        _bc.emitU16(Op.putLoc, keySlot);
        _ctx.adjustStack(-1);

        if (captureRef) {
          _emitCaptureDestructuringReference(prop.value);
          _bc.emitU16(Op.getLoc, sourceObjSlot!);
          _ctx.adjustStack(1);
          _bc.emitU16(Op.getLoc, keySlot);
          _ctx.adjustStack(1);
          _bc.emit(Op.getElem); // [obj, ref, value]
          _ctx.adjustStack(-1);
        } else {
          _bc.emitU16(Op.getLoc, keySlot);
          _ctx.adjustStack(1);
          _bc.emit(Op.getElem); // [obj, value]
          _ctx.adjustStack(-1);
        }
      } else {
        computedKeySlots.add(null);
        final atom = _ctx.addConstant(prop.key);
        if (captureRef) {
          _emitCaptureDestructuringReference(prop.value);
          _bc.emitU16(Op.getLoc, sourceObjSlot!);
          _ctx.adjustStack(1);
          _bc.emitU32(Op.getField, atom); // [obj, ref, value]
        } else {
          _bc.emitU32(Op.getField, atom); // [obj, value]
        }
      }

      // Handle default value
      if (prop.defaultValue != null) {
        if (captureRef) {
          _compileCapturedDestructuringReferenceBinding(
            AssignmentPattern(
              left: prop.value,
              right: prop.defaultValue!,
              line: prop.line,
              column: prop.column,
            ),
          );
          continue;
        }

        // If value is undefined, use default
        _bc.emit(Op.dup);
        _ctx.adjustStack(1);
        _bc.emit(Op.pushUndefined);
        _ctx.adjustStack(1);
        _bc.emit(Op.strictEq);
        _ctx.adjustStack(-1);
        final skipPatch = _bc.emitJump(Op.ifFalse);
        _ctx.adjustStack(-1);
        _bc.emit(Op.drop);
        _ctx.adjustStack(-1);
        _compileWithInferredFunctionName(
          _destructuringTargetName(prop.value),
          prop.defaultValue!,
          () {
            prop.defaultValue!.accept(this);
          },
        );
        _bc.patchJump(skipPatch, _bc.offset);
      }

      if (captureRef) {
        _compileCapturedDestructuringReferenceBinding(prop.value);
        continue;
      }

      // Stack: [obj, value]
      _compileDestructuringBinding(prop.value, declare: declare, kind: kind);
      // Stack: [obj]
    }

    // Handle rest element: {...rest} = obj
    if (pattern.restElement != null) {
      // Collect already-extracted keys
      final excludedKeyCount = pattern.properties.length;

      // Stack: [obj]
      _bc.emit(Op.dup); // [obj, obj_for_rest]
      _ctx.adjustStack(1);

      // Push excluded property keys onto stack.
      for (var i = 0; i < pattern.properties.length; i++) {
        final prop = pattern.properties[i];
        final keySlot = computedKeySlots[i];
        if (keySlot != null) {
          _bc.emitU16(Op.getLoc, keySlot);
          _ctx.adjustStack(1);
        } else {
          _emitString(prop.key, 0);
        }
      }
      // Stack: [obj, obj_for_rest, key0, key1, ...]

      // Op.objectRest pops N keys + the obj, pushes the rest object
      _bc.emitU16(Op.objectRest, excludedKeyCount);
      _ctx.adjustStack(
        -excludedKeyCount,
      ); // net: consumed keys, obj stays as rest obj
      // Stack: [obj, restObj]

      _compileDestructuringBinding(
        pattern.restElement!,
        declare: declare,
        kind: kind,
      );
      // Stack: [obj]
    }

    // Drop the original object
    _bc.emit(Op.drop);
    _ctx.adjustStack(-1);
  }

  void _compileArrayPattern(
    ArrayPattern pattern, {
    bool declare = true,
    String kind = 'let',
  }) {
    // Stack: [iterable]
    _emitDestructuringValidator('__validateArrayDestructure__', pattern.line);

    _bc.emit(Op.forOfStart);

    final iteratorSlot = _ctx.declareLocal(
      '__array_pattern_iter_${_objectPatternTempCounter++}',
      scopeLevel: _ctx.scope.depth,
    );
    _bc.emitU16(Op.putLoc, iteratorSlot);
    _ctx.adjustStack(-1);

    final doneSlot = _ctx.declareLocal(
      '__array_pattern_done_${_objectPatternTempCounter++}',
      scopeLevel: _ctx.scope.depth,
    );
    _bc.emit(Op.pushFalse);
    _ctx.adjustStack(1);
    _bc.emitU16(Op.putLoc, doneSlot);
    _ctx.adjustStack(-1);

    for (var i = 0; i < pattern.elements.length; i++) {
      final elem = pattern.elements[i];
      _compileArrayPatternElement(
        elem,
        iteratorSlot: iteratorSlot,
        doneSlot: doneSlot,
        line: pattern.line,
        declare: declare,
        kind: kind,
      );
    }

    if (pattern.restElement != null) {
      _bc.emit(Op.array);
      _ctx.adjustStack(1);

      final restLoopStart = _bc.offset;
      _bc.emitU16(Op.getLoc, doneSlot);
      _ctx.adjustStack(1);
      final restLoopExit = _bc.emitJump(Op.ifTrue);
      _ctx.adjustStack(-1);

      _bc.emitU16(Op.getLoc, iteratorSlot);
      _ctx.adjustStack(1);
      _bc.emit(Op.forOfNext);
      _ctx.adjustStack(2);
      _bc.emitU16(Op.setLoc, doneSlot);
      final restDonePatch = _bc.emitJump(Op.ifTrue);
      _ctx.adjustStack(-1);
      final restDoneDepth = _ctx._currentStackDepth;

      _bc.emit(Op.swap);
      _bc.emit(Op.drop);
      _ctx.adjustStack(-1);
      _bc.emit(Op.arrayAppend);
      _ctx.adjustStack(-1);
      _bc.emitI32(Op.goto_, restLoopStart);

      _bc.patchJump(restDonePatch, _bc.offset);
      _ctx._currentStackDepth = restDoneDepth;
      _bc.emit(Op.drop);
      _ctx.adjustStack(-1);
      _bc.emit(Op.drop);
      _ctx.adjustStack(-1);
      _bc.patchJump(restLoopExit, _bc.offset);

      _compileDestructuringBinding(
        pattern.restElement!,
        declare: declare,
        kind: kind,
      );
    } else {
      _emitArrayPatternCloseIfNeeded(iteratorSlot, doneSlot, pattern.line);
    }
  }

  void _emitArrayPatternNextValue(int iteratorSlot, int doneSlot, int line) {
    _bc.emitU16(Op.getLoc, doneSlot);
    _ctx.adjustStack(1);
    final alreadyDonePatch = _bc.emitJump(Op.ifTrue);
    _ctx.adjustStack(-1);
    final alreadyDoneDepth = _ctx._currentStackDepth;

    _bc.emitU16(Op.getLoc, iteratorSlot);
    _ctx.adjustStack(1);
    _bc.setLine(line);
    _bc.emit(Op.forOfNext);
    _ctx.adjustStack(2);
    _bc.emitU16(Op.setLoc, doneSlot);
    _bc.emit(Op.drop);
    _ctx.adjustStack(-1);
    _bc.emit(Op.swap);
    _bc.emit(Op.drop);
    _ctx.adjustStack(-1);
    final mergedDepth = _ctx._currentStackDepth;
    final endPatch = _bc.emitJump(Op.goto_);

    _bc.patchJump(alreadyDonePatch, _bc.offset);
    _ctx._currentStackDepth = alreadyDoneDepth;
    _bc.emit(Op.pushUndefined);
    _ctx.adjustStack(1);
    _bc.patchJump(endPatch, _bc.offset);
    _ctx._currentStackDepth = mergedDepth;
  }

  void _emitArrayPatternCloseIfNeeded(
    int iteratorSlot,
    int doneSlot,
    int line,
  ) {
    _bc.emitU16(Op.getLoc, doneSlot);
    _ctx.adjustStack(1);
    final skipPatch = _bc.emitJump(Op.ifTrue);
    _ctx.adjustStack(-1);

    _bc.emitU16(Op.getLoc, iteratorSlot);
    _ctx.adjustStack(1);
    _bc.setLine(line);
    _bc.emit(Op.iteratorClose);
    _ctx.adjustStack(-1);

    _bc.patchJump(skipPatch, _bc.offset);
  }

  bool _canCaptureDestructuringReference(Pattern pattern) {
    final target = pattern is AssignmentPattern ? pattern.left : pattern;
    if (target is! ExpressionPattern) {
      return false;
    }

    final expr = target.expression;
    return expr is IdentifierExpression || expr is MemberExpression;
  }

  void _emitCaptureDestructuringReference(Pattern pattern) {
    final target = pattern is AssignmentPattern ? pattern.left : pattern;
    final expr = (target as ExpressionPattern).expression;

    if (expr is IdentifierExpression) {
      final atom = _ctx.addConstant(expr.name);
      _bc.emitU32(Op.captureVarRef, atom);
      _ctx.adjustStack(1);
      return;
    }

    final member = expr as MemberExpression;
    member.object.accept(this);
    if (member.computed) {
      member.property.accept(this);
      _bc.emit(Op.captureElemRef);
      _ctx.adjustStack(-1);
      return;
    }

    final atom = _ctx.addConstant(_propName(member.property));
    _bc.emitU32(Op.captureFieldRef, atom);
  }

  void _compileCapturedDestructuringReferenceBinding(Pattern pattern) {
    if (pattern is AssignmentPattern) {
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      _bc.emit(Op.pushUndefined);
      _ctx.adjustStack(1);
      _bc.emit(Op.strictEq);
      _ctx.adjustStack(-1);
      final skipPatch = _bc.emitJump(Op.ifFalse);
      _ctx.adjustStack(-1);
      _bc.emit(Op.drop);
      _ctx.adjustStack(-1);
      _compileWithInferredFunctionName(
        _destructuringTargetName(pattern.left),
        pattern.right,
        () {
          pattern.right.accept(this);
        },
      );
      _bc.patchJump(skipPatch, _bc.offset);
      _bc.emit(Op.swap);
      _bc.emit(Op.putCapturedVar);
      _ctx.adjustStack(-2);
      return;
    }

    _bc.emit(Op.swap);
    _bc.emit(Op.putCapturedVar);
    _ctx.adjustStack(-2);
  }

  void _compileArrayPatternElement(
    Pattern? elem, {
    required int iteratorSlot,
    required int doneSlot,
    required int line,
    required bool declare,
    required String kind,
  }) {
    if (elem == null) {
      _emitArrayPatternNextValue(iteratorSlot, doneSlot, line);
      _bc.emit(Op.drop);
      _ctx.adjustStack(-1);
      return;
    }

    if (_canCaptureDestructuringReference(elem)) {
      _emitCaptureDestructuringReference(elem);
      _emitArrayPatternNextValue(iteratorSlot, doneSlot, line);
      _compileCapturedDestructuringReferenceBinding(elem);
    } else {
      _emitArrayPatternNextValue(iteratorSlot, doneSlot, line);
      _compileDestructuringBinding(elem, declare: declare, kind: kind);
    }
  }

  void _compileAssignmentPattern(
    AssignmentPattern pattern, {
    bool declare = true,
    String kind = 'let',
  }) {
    // Stack: [value]
    // If value is undefined, replace with default
    _bc.emit(Op.dup);
    _ctx.adjustStack(1);
    _bc.emit(Op.pushUndefined);
    _ctx.adjustStack(1);
    _bc.emit(Op.strictEq);
    _ctx.adjustStack(-1);
    final skipPatch = _bc.emitJump(Op.ifFalse);
    _ctx.adjustStack(-1);
    _bc.emit(Op.drop);
    _ctx.adjustStack(-1);
    _compileWithInferredFunctionName(
      _destructuringTargetName(pattern.left),
      pattern.right,
      () {
        pattern.right.accept(this);
      },
    );
    _bc.patchJump(skipPatch, _bc.offset);

    // Now bind the resolved value to the left pattern
    _compileDestructuringBinding(pattern.left, declare: declare, kind: kind);
  }

  void _compileExpressionPatternAssign(ExpressionPattern pattern) {
    // Stack: [value]
    // The expression pattern is used for rest targets like ...obj.prop
    // Compile the expression as an assignment target
    final expr = pattern.expression;
    if (expr is IdentifierExpression) {
      _emitSetVar(expr.name, expr.line, expr.column);
      _bc.emit(Op.drop);
      _ctx.adjustStack(-1);
    } else if (expr is MemberExpression) {
      expr.object.accept(this); // [value, obj]
      if (expr.computed) {
        expr.property.accept(this); // [value, obj, key]
        _bc.emit(Op.rot3l); // [obj, key, value]
        _bc.emit(Op.putElem); // []
        _ctx.adjustStack(-3);
      } else {
        final name = _propName(expr.property);
        final atom = _ctx.addConstant(name);
        _bc.emit(Op.swap); // [obj, value]
        _bc.emitU32(Op.putField, atom); // []
        _ctx.adjustStack(-2);
      }
    } else {
      // Fallback — just drop
      _bc.emit(Op.drop);
      _ctx.adjustStack(-1);
    }
  }

  @override
  void visitIdentifierPattern(IdentifierPattern node) {}

  @override
  void visitExpressionPattern(ExpressionPattern node) {}

  @override
  void visitAssignmentPattern(AssignmentPattern node) {}

  @override
  void visitArrayPattern(ArrayPattern node) {}

  @override
  void visitObjectPattern(ObjectPattern node) {}

  @override
  void visitObjectPatternProperty(ObjectPatternProperty node) {}

  @override
  void visitDestructuringAssignmentExpression(
    DestructuringAssignmentExpression node,
  ) {
    // Compile the right side
    node.right.accept(this);
    // Dup so the expression value is preserved (assignment is an expression)
    _bc.emit(Op.dup);
    _ctx.adjustStack(1);
    // Destructure into the pattern (no declaration, just assignment)
    _compileDestructuringBinding(node.left, declare: false);
    // Result of the expression is the right-hand value (still on stack)
  }

  // ---- Module declarations (stubs) ----

  @override
  void visitImportDeclaration(ImportDeclaration node) {
    // Static import: import { x } from 'module'
    // Emit a call to __import_sync__(moduleId) which returns the exports object.
    final moduleId = node.source.value as String;

    // Push the sync import helper and call it
    final helperAtom = _ctx.addConstant('__import_sync__');
    _bc.emitU32(Op.getVar, helperAtom);
    _ctx.adjustStack(1);
    _emitString(moduleId, node.line);
    _bc.emitU16(Op.call, 1);
    _ctx.adjustStack(-1); // consumed helper + arg, produced result
    // Stack: [exports_obj]

    // Handle default import: import defaultName from 'module'
    if (node.defaultSpecifier != null) {
      final localName = node.defaultSpecifier!.local.name;
      final slot = _ctx.declareLocal(
        localName,
        scope: VarScope.blockScope,
        isConst: true,
      );
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      final fieldAtom = _ctx.addConstant('default');
      _bc.emitU32(Op.getField, fieldAtom);
      _bc.emitU16(Op.putLoc, slot);
      _ctx.adjustStack(-1);
    }

    // Handle named imports: import { x, y as z } from 'module'
    for (final spec in node.namedSpecifiers) {
      final exportName = spec.imported.name;
      final localName = spec.local?.name ?? exportName;
      final slot = _ctx.declareLocal(
        localName,
        scope: VarScope.blockScope,
        isConst: true,
      );
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      final fieldAtom = _ctx.addConstant(exportName);
      _bc.emitU32(Op.getField, fieldAtom);
      _bc.emitU16(Op.putLoc, slot);
      _ctx.adjustStack(-1);
    }

    // Handle namespace import: import * as name from 'module'
    if (node.namespaceSpecifier != null) {
      final localName = node.namespaceSpecifier!.local.name;
      final slot = _ctx.declareLocal(
        localName,
        scope: VarScope.blockScope,
        isConst: true,
      );
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      _bc.emitU16(Op.putLoc, slot);
      _ctx.adjustStack(-1);
    }

    // Drop the exports object
    _bc.emit(Op.drop);
    _ctx.adjustStack(-1);
  }

  @override
  void visitImportSpecifier(ImportSpecifier node) {}
  @override
  void visitImportDefaultSpecifier(ImportDefaultSpecifier node) {}
  @override
  void visitImportNamespaceSpecifier(ImportNamespaceSpecifier node) {}
  @override
  void visitExportDeclaration(ExportDeclaration node) {
    // ExportDeclarationStatement wraps a declaration — compile it
    if (node is ExportDeclarationStatement) {
      node.declaration.accept(this);
    }
  }

  @override
  void visitExportSpecifier(ExportSpecifier node) {}
  @override
  void visitExportDefaultDeclaration(ExportDefaultDeclaration node) {
    final decl = node.declaration;

    // Compile the expression (pushes value on stack)
    decl.accept(this);

    // If the declaration has a name, also bind it in the local scope
    String? name;
    if (decl is FunctionExpression && decl.id != null) {
      name = decl.id!.name;
    } else if (decl is AsyncFunctionExpression && decl.id != null) {
      name = decl.id!.name;
    } else if (decl is ClassExpression && decl.id != null) {
      name = decl.id!.name;
    }

    if (name != null) {
      // Duplicate the value on stack so we can both bind and export
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      final slot = _ctx.declareLocal(name, scope: VarScope.funcScope);
      _bc.emitU16(Op.putLoc, slot);
      _ctx.adjustStack(-1);
    }

    // Store as 'default' local (pops the value)
    final slot = _ctx.declareLocal('default', scope: VarScope.funcScope);
    _bc.emitU16(Op.putLoc, slot);
    _ctx.adjustStack(-1);
  }

  @override
  void visitExportNamedDeclaration(ExportNamedDeclaration node) {
    // Named exports like `export { x, y as z }` — bindings are collected
    // in _collectExportBindings and resolved at end of compileModule.
    // Nothing to emit here.
  }
  @override
  void visitExportAllDeclaration(ExportAllDeclaration node) {}
  @override
  void visitImportExpression(ImportExpression node) {
    // Compile the source expression (module specifier)
    node.source.accept(this);
    _bc.emit(Op.import_);
    // import_ pops specifier, pushes Promise
  }

  @override
  void visitMetaProperty(MetaProperty node) {
    if (node.meta == 'import' && node.property == 'meta') {
      _bc.emit(Op.object);
      _ctx.adjustStack(1);
      _bc.emit(Op.dup);
      _ctx.adjustStack(1);
      final url = moduleUrl ?? 'file:///unknown';
      _emitString(url, 0);
      final atom = _ctx.addConstant('url');
      _bc.emitU32(Op.putField, atom);
      _ctx.adjustStack(-2);
      return;
    }

    if (node.meta == 'new' && node.property == 'target') {
      _bc.emit(Op.getNewTarget);
      _ctx.adjustStack(1);
      return;
    }

    _bc.emit(Op.pushUndefined);
    _ctx.adjustStack(1);
  }
}

/// Compilation error
class CompileError implements Exception {
  final String message;
  final int? line;

  CompileError(this.message, [this.line]);

  @override
  String toString() => line != null
      ? 'SyntaxError: $message (line $line)'
      : 'SyntaxError: $message';
}
