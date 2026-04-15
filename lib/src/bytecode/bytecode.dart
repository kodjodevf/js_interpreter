/// Core bytecode data structures for the JS interpreter VM
///
/// These structures represent compiled functions and execution state.
library;

import 'dart:typed_data';

import '../runtime/environment.dart';
import '../runtime/js_runtime.dart';
import '../runtime/js_value.dart';
import 'opcodes.dart';

// ================================================================
// Closure variable reference (how closures capture outer variables)
// ================================================================

/// How a closure variable is accessed
enum ClosureVarKind {
  /// From the enclosing function's locals
  local,

  /// From the enclosing function's arguments
  arg,

  /// From the enclosing function's own closure vars (transitive capture)
  varRef,
}

/// A reference to a variable captured by a closure.
///
/// records where to find the value in the parent scope.
class ClosureVarDef {
  /// Name of the variable (for debugging / `with` statements)
  final String name;

  /// Where does this variable live in the parent function?
  final ClosureVarKind kind;

  /// Index within the parent's locals/args/varRefs depending on [kind]
  final int index;

  /// Is this a `const` binding?
  final bool isConst;

  /// Is this a `let`/`const` (needs TDZ check)?
  final bool isLexical;

  const ClosureVarDef({
    required this.name,
    required this.kind,
    required this.index,
    this.isConst = false,
    this.isLexical = false,
  });

  @override
  String toString() => 'ClosureVar($name, $kind, #$index)';
}

// ================================================================
// Variable definition within a function
// ================================================================

/// Scope of a local variable
enum VarScope {
  /// Function-scoped (var, parameters)
  funcScope,

  /// Block-scoped (let, const)
  blockScope,
}

/// A local variable or named parameter within a function.
class VarDef {
  /// Variable name
  final String name;

  /// Scope type
  final VarScope scope;

  /// Is this a const binding?
  final bool isConst;

  /// Is this captured by a child closure?
  /// If true, the variable lives on the heap (in a VarRef box) rather than
  /// on the stack frame.
  bool isCaptured;

  /// Scope depth at which this variable is defined (for block scoping)
  final int scopeLevel;

  /// Is this binding subject to TDZ checks before initialization?
  final bool isLexical;

  VarDef({
    required this.name,
    required this.scope,
    this.isConst = false,
    this.isCaptured = false,
    this.scopeLevel = 0,
    this.isLexical = false,
  });

  @override
  String toString() =>
      'VarDef($name, $scope${isConst ? ", const" : ""}${isLexical ? ", lexical" : ""}${isCaptured ? ", captured" : ""})';
}

// ================================================================
// Compiled function bytecode
// ================================================================

/// The kind of function for the bytecode
enum FunctionKind {
  normal,
  arrow,
  method,
  getter,
  setter,
  constructor_,
  generator,
  asyncFunction,
  asyncArrow,
  asyncGenerator,
}

/// A compiled JavaScript function.
///
/// Contains everything needed to execute the function:
/// - The bytecode instructions
/// - Constant pool for literals & nested functions
/// - Variable/argument metadata
/// - Closure variable definitions
class FunctionBytecode {
  /// Function name (empty string for anonymous)
  final String name;

  /// What kind of function
  final FunctionKind kind;

  /// Is strict mode?
  final bool isStrict;

  // ----- Bytecode -----

  /// The raw bytecode bytes.
  /// Each instruction is: 1 byte opcode + N bytes operands.
  late Uint8List bytecode;

  // ----- Arguments -----

  /// Number of declared parameters (excluding rest)
  final int argCount;

  /// Declared parameter names in slot order.
  final List<String> argNames;

  /// The value for Function.length: params before first rest/default
  final int expectedArgCount;

  /// Number of local slots that belong to the parameter environment.
  final int parameterVarCount;

  /// Bytecode offset where the function body begins after parameter setup.
  final int bodyStartPc;

  /// Does this function have a rest parameter?
  final bool hasRest;

  // ----- Locals -----

  /// Local variable definitions (includes `var` declarations and
  /// block-scoped `let`/`const`).
  /// These are accessed by slot index in the bytecode.
  final List<VarDef> vars;

  /// Maximum stack depth needed (computed at compile time).
  /// Used to pre-allocate the operand stack in the frame.
  int stackSize;

  // ----- Constants -----

  /// Constant pool: holds string/number literals, regex patterns,
  /// and nested `FunctionBytecode` objects.
  final List<Object> constantPool;

  // ----- Closures -----

  /// Definitions of variables captured from enclosing scopes.
  /// At runtime, these are resolved to `VarRef` objects.
  final List<ClosureVarDef> closureVars;

  // ----- Source info (for error messages & debugging) -----

  /// Source file name
  String? sourceFile;

  /// Line number where function starts
  int? sourceLine;

  /// Column number where function starts
  int? sourceColumn;

  /// Original source text for Function.prototype.toString()
  String? sourceText;

  /// Source line mapping: bytecode offset → source line number.
  /// Sparse map: only entries where line changes are recorded.
  List<SourceMapping>? sourceMap;

  /// Module export name -> local binding name.
  /// Used by the VM to expose live module bindings during cyclic evaluation.
  Map<String, String> moduleExportBindings;

  FunctionBytecode({
    this.name = '',
    this.kind = FunctionKind.normal,
    this.isStrict = false,
    required this.argCount,
    List<String>? argNames,
    int? expectedArgCount,
    this.parameterVarCount = 0,
    this.bodyStartPc = 0,
    this.hasRest = false,
    List<VarDef>? vars,
    this.stackSize = 0,
    List<Object>? constantPool,
    List<ClosureVarDef>? closureVars,
    this.sourceFile,
    this.sourceLine,
    this.sourceColumn,
    this.sourceText,
    Map<String, String>? moduleExportBindings,
  }) : argNames = List.unmodifiable(argNames ?? const <String>[]),
       expectedArgCount = expectedArgCount ?? argCount,
       vars = vars ?? [],
       constantPool = constantPool ?? [],
       closureVars = closureVars ?? [],
       moduleExportBindings = moduleExportBindings ?? {};

  /// Total number of local slots = vars.length
  int get varCount => vars.length;

  /// Total slots needed in the stack frame = args + vars
  int get totalSlots => argCount + varCount;

  @override
  String toString() {
    final kindStr = kind == FunctionKind.normal ? '' : ' ($kind)';
    return 'FunctionBytecode(${name.isEmpty ? "<anonymous>" : name}$kindStr, '
        '${bytecode.length} bytes, '
        '$argCount args, $varCount vars, stack=$stackSize)';
  }
}

/// Source offset mapping entry
class SourceMapping {
  final int bytecodeOffset;
  final int line;
  final int column;

  const SourceMapping(this.bytecodeOffset, this.line, [this.column = 0]);
}

// ================================================================
// Runtime structures
// ================================================================

/// A heap-allocated box for a variable that might be captured by a closure.
///
/// When a local variable is captured, it is "lifted" from the stack into
/// a VarRef box. Both the parent and child function then access the value
/// through this box, ensuring mutations are visible to both.
class VarRef {
  JSValue _value;

  VarRef(JSValue value) : _value = value;

  // ignore: unnecessary_getters_setters
  JSValue get value => _value;

  set value(JSValue newValue) {
    _value = newValue;
  }

  void initialize(JSValue newValue) {
    _value = newValue;
  }

  @override
  String toString() => 'VarRef($value)';
}

/// Internal sentinel for bytecode lexical bindings that are still in TDZ.
class JSTemporalDeadZone extends JSValue {
  static final JSTemporalDeadZone instance = JSTemporalDeadZone._();

  JSTemporalDeadZone._();

  @override
  JSValueType get type => JSValueType.undefined;

  @override
  dynamic get primitiveValue => null;

  @override
  bool toBoolean() => false;

  @override
  double toNumber() => double.nan;

  @override
  String toString() => '<uninitialized>';

  @override
  JSObject toObject() {
    throw JSTypeError('Cannot convert uninitialized lexical binding to object');
  }

  @override
  bool equals(JSValue other) => identical(this, other);

  @override
  bool strictEquals(JSValue other) => identical(this, other);
}

/// A VarRef that preserves TDZ behavior for captured lexical bindings.
class LexicalVarRef extends VarRef {
  final String name;

  LexicalVarRef(this.name, [JSValue? value])
    : super(value ?? JSTemporalDeadZone.instance);

  @override
  JSValue get value {
    final current = super.value;
    if (identical(current, JSTemporalDeadZone.instance)) {
      throw JSReferenceError('Cannot access \'$name\' before initialization');
    }
    return current;
  }
}

/// A VarRef backed by a bytecode local binding.
///
/// This preserves TDZ and const assignment semantics when a local is boxed so
/// that closures and direct eval share the same live binding.
class LocalBindingVarRef extends VarRef {
  final String name;
  final bool isConst;
  final bool isLexical;

  LocalBindingVarRef(
    this.name, {
    required this.isConst,
    required this.isLexical,
    JSValue? value,
  }) : super(
         value ??
             (isLexical ? JSTemporalDeadZone.instance : JSUndefined.instance),
       );

  @override
  JSValue get value {
    final current = super.value;
    if (isLexical && identical(current, JSTemporalDeadZone.instance)) {
      throw JSReferenceError('Cannot access \'$name\' before initialization');
    }
    return current;
  }

  @override
  set value(JSValue newValue) {
    final current = super.value;
    if (isLexical && identical(current, JSTemporalDeadZone.instance)) {
      throw JSReferenceError('Cannot access \'$name\' before initialization');
    }
    if (isConst && !identical(current, JSTemporalDeadZone.instance)) {
      throw JSTypeError('Assignment to constant variable: $name');
    }
    super.value = newValue;
  }

  @override
  // ignore: unnecessary_overrides
  void initialize(JSValue newValue) {
    super.initialize(newValue);
  }
}

/// A VarRef backed directly by a legacy evaluator binding.
///
/// This allows promoted bytecode functions to share captured state with the
/// original lexical environment instead of using a one-time snapshot.
class LegacyBindingVarRef extends VarRef {
  final Binding binding;

  LegacyBindingVarRef(this.binding) : super(binding.value);

  @override
  JSValue get value {
    if (!binding.initialized) {
      throw JSReferenceError(
        'Cannot access \'${binding.name}\' before initialization',
      );
    }
    return binding.value;
  }

  @override
  set value(JSValue newValue) {
    if (binding.type == BindingType.functionExprName) {
      final runtime = JSRuntime.current;
      final isStrictMode = runtime?.isStrictMode() ?? false;
      if (isStrictMode) {
        throw JSTypeError('Assignment to constant variable: ${binding.name}');
      }
      return;
    }
    binding.setValue(newValue);
  }
}

/// A VarRef for the inner name binding of a named function expression.
///
/// In sloppy mode, assignments to this binding are ignored.
/// In strict mode, they throw a TypeError.
class FunctionExprNameVarRef extends VarRef {
  final String name;

  FunctionExprNameVarRef(this.name, JSValue value) : super(value);

  @override
  set value(JSValue newValue) {
    final runtime = JSRuntime.current;
    final isStrictMode = runtime?.isStrictMode() ?? false;
    if (isStrictMode) {
      throw JSTypeError('Assignment to constant variable: $name');
    }
  }
}

/// A runtime stack frame for bytecode execution.
///
class StackFrame {
  /// The bytecode being executed
  final FunctionBytecode func;

  /// Program counter (index into func.bytecode)
  int pc = 0;

  /// Operand stack
  final List<JSValue> stack;

  /// Stack pointer (index of next free slot in stack)
  int sp = 0;

  /// Argument values — fixed size = func.argCount
  final List<JSValue> args;

  /// Local variable values — fixed size = func.varCount
  /// For captured variables, this holds VarRef objects (stored as JSValue wrappers).
  final List<JSValue> locals;

  /// Closure variable references — resolved at function call time.
  /// These point to VarRef boxes from enclosing scopes.
  final List<VarRef> closureVarRefs;

  /// The `this` value for this call
  JSValue thisValue;

  /// The `new.target` value visible to this frame
  JSValue newTarget;

  /// The function object executing in this frame.
  JSFunction? calleeFunction;

  /// The calling frame (for returning)
  StackFrame? callerFrame;

  /// Exception handler stack: pairs of (catch_pc, stack_depth)
  final List<ExceptionHandler> exceptionHandlers;

  /// For generators/async: saved state for suspend/resume
  bool isSuspended = false;

  /// All arguments passed to this call (for building arguments object)
  List<JSValue> passedArgs;

  /// Dynamic bindings introduced by non-strict direct eval.
  final Map<String, VarRef> evalBindings;

  /// Active `with` object environments visible to this frame.
  final List<JSObject> withObjects;

  /// Whether this frame executes code produced by a direct eval() call.
  final bool isDirectEvalFrame;

  /// The host frame whose environment is visible to this direct eval.
  final StackFrame? directEvalHostFrame;

  StackFrame({
    required this.func,
    required this.thisValue,
    JSValue? newTarget,
    this.calleeFunction,
    this.callerFrame,
    List<JSValue>? passedArgs,
    Map<String, VarRef>? evalBindings,
    List<JSObject>? withObjects,
    this.isDirectEvalFrame = false,
    this.directEvalHostFrame,
  }) : stack = List<JSValue>.filled(func.stackSize, JSUndefined.instance),
       args = List<JSValue>.filled(func.argCount, JSUndefined.instance),
       locals = List<JSValue>.generate(
         func.varCount,
         (index) => func.vars[index].isLexical
             ? JSTemporalDeadZone.instance
             : JSUndefined.instance,
       ),
       closureVarRefs = List<VarRef>.generate(
         func.closureVars.length,
         (_) => VarRef(JSUndefined.instance),
       ),
       exceptionHandlers = [],
       passedArgs = passedArgs ?? const [],
       evalBindings = evalBindings ?? <String, VarRef>{},
       withObjects = withObjects ?? <JSObject>[],
       newTarget = newTarget ?? JSUndefined.instance;

  /// Push a value onto the operand stack
  void push(JSValue value) {
    stack[sp++] = value;
  }

  /// Pop a value from the operand stack
  JSValue pop() {
    return stack[--sp];
  }

  /// Peek at the top of the operand stack without popping
  JSValue peek() {
    return stack[sp - 1];
  }

  @override
  String toString() =>
      'StackFrame(${func.name.isEmpty ? "<anonymous>" : func.name}, pc=$pc, sp=$sp)';
}

/// An exception handler entry (for try-catch-finally)
class ExceptionHandler {
  /// PC to jump to when an exception occurs
  final int catchPc;

  /// Stack depth to restore when jumping to catch
  final int stackDepth;

  /// PC for finally block (or -1 if no finally)
  final int finallyPc;

  const ExceptionHandler({
    required this.catchPc,
    required this.stackDepth,
    this.finallyPc = -1,
  });
}

// ================================================================
// Bytecode builder (used by the compiler to emit instructions)
// ================================================================

/// Helper to build bytecode incrementally during compilation.
///
/// Provides methods to emit opcodes and operands, and to patch
/// jump targets after the target address is known.
class BytecodeBuilder {
  /// The bytecode buffer (grows dynamically, finalized to Uint8List)
  final List<int> _buffer = [];

  /// Source mappings accumulated during compilation
  final List<SourceMapping> sourceMappings = [];

  /// Current source line (for source map tracking)
  int _currentLine = 0;

  /// Current source column (for source map tracking)
  int _currentColumn = 0;

  /// Get current bytecode offset (= length so far)
  int get offset => _buffer.length;

  /// Emit a single opcode (no operands)
  void emit(Op op) {
    _buffer.add(op.index);
  }

  /// Emit opcode + 1 byte unsigned operand
  void emitU8(Op op, int value) {
    _buffer.add(op.index);
    _buffer.add(value & 0xFF);
  }

  /// Emit opcode + 1 byte signed operand
  void emitI8(Op op, int value) {
    _buffer.add(op.index);
    _buffer.add(value & 0xFF);
  }

  /// Emit opcode + 2 byte unsigned operand (big-endian)
  void emitU16(Op op, int value) {
    _buffer.add(op.index);
    _buffer.add((value >> 8) & 0xFF);
    _buffer.add(value & 0xFF);
  }

  /// Emit opcode + 2 byte signed operand (big-endian)
  void emitI16(Op op, int value) {
    emitU16(op, value);
  }

  /// Emit opcode + 4 byte unsigned operand (big-endian)
  void emitU32(Op op, int value) {
    _buffer.add(op.index);
    _buffer.add((value >> 24) & 0xFF);
    _buffer.add((value >> 16) & 0xFF);
    _buffer.add((value >> 8) & 0xFF);
    _buffer.add(value & 0xFF);
  }

  /// Emit opcode + 4 byte signed operand
  void emitI32(Op op, int value) {
    emitU32(op, value);
  }

  /// Emit opcode + 8 byte double
  void emitF64(Op op, double value) {
    _buffer.add(op.index);
    final data = ByteData(8);
    data.setFloat64(0, value, Endian.big);
    for (var i = 0; i < 8; i++) {
      _buffer.add(data.getUint8(i));
    }
  }

  /// Emit opcode + 4 byte atom + 1 byte flags
  void emitAtomU8(Op op, int atom, int flags) {
    _buffer.add(op.index);
    _buffer.add((atom >> 24) & 0xFF);
    _buffer.add((atom >> 16) & 0xFF);
    _buffer.add((atom >> 8) & 0xFF);
    _buffer.add(atom & 0xFF);
    _buffer.add(flags & 0xFF);
  }

  // ----- Jump helpers -----

  /// Emit a jump instruction with a placeholder offset.
  /// Returns the bytecode offset of the jump target bytes so it can be patched.
  int emitJump(Op op) {
    _buffer.add(op.index);
    final patchOffset = _buffer.length;
    // Placeholder: 4 bytes for goto/catch/gosub, 2 bytes for conditional jumps
    if (op == Op.goto_ || op == Op.catch_ || op == Op.gosub) {
      _buffer.add(0);
      _buffer.add(0);
      _buffer.add(0);
      _buffer.add(0);
    } else {
      // i16 for if_true / if_false
      _buffer.add(0);
      _buffer.add(0);
    }
    return patchOffset;
  }

  /// Patch a previously-emitted jump target.
  /// [patchOffset] is the offset returned by [emitJump].
  /// [target] is the absolute bytecode offset to jump to.
  void patchJump(int patchOffset, int target) {
    final opByte = _buffer[patchOffset - 1];
    final op = Op.values[opByte];
    if (op == Op.goto_ || op == Op.catch_ || op == Op.gosub) {
      // 4-byte absolute offset
      _buffer[patchOffset] = (target >> 24) & 0xFF;
      _buffer[patchOffset + 1] = (target >> 16) & 0xFF;
      _buffer[patchOffset + 2] = (target >> 8) & 0xFF;
      _buffer[patchOffset + 3] = target & 0xFF;
    } else {
      // 2-byte relative offset from the instruction start
      final instrStart = patchOffset - 1;
      final rel = target - instrStart;
      _buffer[patchOffset] = (rel >> 8) & 0xFF;
      _buffer[patchOffset + 1] = rel & 0xFF;
    }
  }

  // ----- Source mapping -----

  /// Record a source line mapping at the current offset
  void setLine(int line, [int column = 0]) {
    if (line != _currentLine || column != _currentColumn) {
      _currentLine = line;
      _currentColumn = column;
      sourceMappings.add(SourceMapping(offset, line, column));
    }
  }

  // ----- Finalize -----

  /// Build the final bytecode as a Uint8List
  Uint8List build() {
    return Uint8List.fromList(_buffer);
  }
}

/// Read a u16 value from bytecode at the given offset (big-endian)
int readU16(Uint8List bc, int offset) {
  return (bc[offset] << 8) | bc[offset + 1];
}

/// Read an i16 value from bytecode at the given offset (big-endian)
int readI16(Uint8List bc, int offset) {
  final v = (bc[offset] << 8) | bc[offset + 1];
  return v >= 0x8000 ? v - 0x10000 : v;
}

/// Read a u32 value from bytecode at the given offset (big-endian)
int readU32(Uint8List bc, int offset) {
  return (bc[offset] << 24) |
      (bc[offset + 1] << 16) |
      (bc[offset + 2] << 8) |
      bc[offset + 3];
}

/// Read an i32 value from bytecode at the given offset (big-endian)
int readI32(Uint8List bc, int offset) {
  final v = readU32(bc, offset);
  return v >= 0x80000000 ? v - 0x100000000 : v;
}

/// Read a f64 value from bytecode at the given offset (big-endian)
double readF64(Uint8List bc, int offset) {
  final data = ByteData.sublistView(bc, offset, offset + 8);
  return data.getFloat64(0, Endian.big);
}
