/// Bytecode opcodes for the JS interpreter VM
///
/// Stack-based VM: operands are pushed/popped from the stack.
library;

/// All bytecode opcodes.
///
/// Naming convention:
///   - `push_*` / `pop` : stack manipulation
///   - `get_*` / `put_*` / `set_*` : variable access (get=read, put=write+pop, set=write+keep)
///   - `if_*` / `goto*` : control flow
///   - Arithmetic/logic ops consume operands from stack, push result
///
/// Operand encoding (after opcode byte):
///   - No suffix: no operand
///   - `_i8` : 1 byte signed
///   - `_u8` : 1 byte unsigned
///   - `_i16`: 2 bytes signed (big-endian)
///   - `_u16`: 2 bytes unsigned (big-endian)
///   - `_i32`: 4 bytes signed (big-endian)
///   - `_u32`: 4 bytes unsigned (big-endian)
///   - `_f64`: 8 bytes IEEE 754 double
///   - `_atom`: 4 bytes atom/constant pool index
enum Op {
  // ============================================================
  // Stack manipulation
  // ============================================================

  /// Push undefined onto stack
  pushUndefined, // [] -> [undefined]
  /// Push null onto stack
  pushNull, // [] -> [null]
  /// Push true onto stack
  pushTrue, // [] -> [true]
  /// Push false onto stack
  pushFalse, // [] -> [false]
  /// Push 32-bit integer: push_i32 &lt;i32&gt;
  pushI32, // [] -> [int]
  /// Push 64-bit float: push_f64 &lt;f64&gt;
  pushF64, // [] -> [double]
  /// Push constant from pool: push_const &lt;u16&gt;
  pushConst, // [] -> [value]  (index into constant pool)
  /// Push empty string
  pushEmptyString, // [] -> [""]
  // Short integer push (0-7) for common values
  push0,
  push1,
  push2,
  push3,
  push4,
  push5,
  push6,
  push7,

  /// Duplicate top of stack
  dup, // [a] -> [a, a]
  /// Duplicate top 2 values
  dup2, // [a, b] -> [a, b, a, b]
  /// Pop and discard top of stack
  drop, // [a] -> []
  /// Swap top 2 values
  swap, // [a, b] -> [b, a]
  /// Rotate 3: [a, b, c] -> [b, c, a]
  rot3l,

  /// Insert: [a, b, c] -> [c, a, b]
  insert3,

  /// Insert: [a, b, c, d] -> [d, a, b, c]
  insert4,

  /// No operation
  nop,

  // ============================================================
  // Local variable access (by slot index)
  // ============================================================

  /// Get local variable: get_loc &lt;u16&gt;
  getLoc, // [] -> [value]
  /// Put (assign) local variable: put_loc &lt;u16&gt;
  putLoc, // [value] -> []
  /// Set (assign and keep on stack): set_loc &lt;u16&gt;
  setLoc, // [value] -> [value]
  // Short forms for locals 0-3
  getLoc0,
  getLoc1,
  getLoc2,
  getLoc3,
  putLoc0,
  putLoc1,
  putLoc2,
  putLoc3,

  // ============================================================
  // Argument access (by slot index)
  // ============================================================

  /// Get argument: get_arg &lt;u16&gt;
  getArg, // [] -> [value]
  /// Put argument: put_arg &lt;u16&gt;
  putArg, // [value] -> []
  /// Set argument: set_arg &lt;u16&gt;
  setArg, // [value] -> [value]
  // Short forms for args 0-3
  getArg0,
  getArg1,
  getArg2,
  getArg3,

  // ============================================================
  // Closure variable access (captured from outer scope)
  // ============================================================

  /// Get closure variable: get_var_ref &lt;u16&gt;
  getVarRef, // [] -> [value]
  /// Put closure variable: put_var_ref &lt;u16&gt;
  putVarRef, // [value] -> []
  /// Set closure variable: set_var_ref &lt;u16&gt;
  setVarRef, // [value] -> [value]
  // ============================================================
  // Global variable access (by atom/name)
  // ============================================================

  /// Get global variable: get_var &lt;u32 atom&gt;
  getVar, // [] -> [value]
  /// Put global variable: put_var &lt;u32 atom&gt;
  putVar, // [value] -> []
  /// Check if variable is defined: check_var &lt;u32 atom&gt;
  checkVar, // [] -> [bool]
  /// Check variable defined (strict): throws ReferenceError if not found: check_var_strict &lt;u32 atom&gt;
  checkVarStrict, // [] -> []
  /// Define global variable: define_var &lt;u32 atom&gt; &lt;u8 flags&gt;
  defineVar, // [] -> []
  // ============================================================
  // Property access
  // ============================================================

  /// Get property by name: get_field &lt;u32 atom&gt;
  getField, // [obj] -> [value]
  /// Put property by name: put_field &lt;u32 atom&gt;
  putField, // [obj, value] -> []
  /// Get property by computed key (bracket notation)
  getElem, // [obj, key] -> [value]
  /// Put property by computed key
  putElem, // [obj, key, value] -> []
  /// Delete property by name: delete_field &lt;u32 atom&gt;
  deleteField, // [obj] -> [bool]
  /// Delete property by computed key
  deleteElem, // [obj, key] -> [bool]
  /// Check if has property: in operator
  inOp, // [key, obj] -> [bool]
  /// instanceof operator
  instanceOf, // [obj, constructor] -> [bool]
  // ============================================================
  // Object/Array creation
  // ============================================================

  /// Create empty object: object
  object, // [] -> [{}]
  /// Create empty array: array
  array, // [] -> [[]]
  /// Append value to array on stack: array_append
  arrayAppend, // [array, value] -> [array]
  /// Append a hole (empty slot) to array on stack
  arrayHole, // [array] -> [array]
  /// Define own property: define_prop &lt;u32 atom&gt; &lt;u8 flags&gt;
  defineProp, // [obj, value] -> [obj]
  /// Define enumerable getter property for object literals
  defineGetterEnum, // [obj, getter] -> [obj]
  /// Define enumerable setter property for object literals
  defineSetterEnum, // [obj, setter] -> [obj]
  /// Object spread: copy properties from source to target
  copyDataProperties, // [target, source] -> [target]
  /// Set prototype: set_proto
  setProto, // [obj, proto] -> [obj]
  // ============================================================
  // Arithmetic & bitwise operators
  // ============================================================

  /// Binary operators: consume 2 values, push result
  add, // [a, b] -> [a+b]
  sub, // [a, b] -> [a-b]
  mul, // [a, b] -> [a*b]
  div, // [a, b] -> [a/b]
  mod, // [a, b] -> [a%b]
  pow, // [a, b] -> [a**b]
  /// Bitwise
  shl, // [a, b] -> [a<<b]
  sar, // [a, b] -> [a>>b]  (signed)
  shr, // [a, b] -> [a>>>b] (unsigned)
  bitAnd, // [a, b] -> [a&b]
  bitOr, // [a, b] -> [a|b]
  bitXor, // [a, b] -> [a^b]
  /// Unary operators
  neg, // [a] -> [-a]
  plus, // [a] -> [+a] (ToNumber)
  toNumeric, // [a] -> [ToNumeric(a)] (preserves BigInt)
  bitNot, // [a] -> [~a]
  not, // [a] -> [!a]
  typeOf, // [a] -> [typeof a]
  voidOp, // [a] -> [undefined]
  /// Increment/decrement (for postfix: dup first)
  inc, // [a] -> [a+1]
  dec, // [a] -> [a-1]
  // ============================================================
  // Comparison operators
  // ============================================================
  lt, // [a, b] -> [a < b]
  lte, // [a, b] -> [a <= b]
  gt, // [a, b] -> [a > b]
  gte, // [a, b] -> [a >= b]
  eq, // [a, b] -> [a == b]
  neq, // [a, b] -> [a != b]
  strictEq, // [a, b] -> [a === b]
  strictNeq, // [a, b] -> [a !== b]
  /// Nullish check
  isNullOrUndefined, // [a] -> [bool]
  // ============================================================
  // Control flow
  // ============================================================

  /// Conditional jump (2-byte offset): if_false &lt;i16&gt;
  ifFalse, // [cond] -> []  jump if falsy
  /// Conditional jump: if_true &lt;i16&gt;
  ifTrue, // [cond] -> []  jump if truthy
  /// Unconditional jump: goto &lt;i32&gt;
  goto_, // jump to absolute offset
  /// Short jumps (1-byte offset)
  ifFalse8,
  ifTrue8,
  goto8,

  // ============================================================
  // Function calls
  // ============================================================

  /// Call function: call &lt;u16 argc&gt;
  /// Stack: [func, arg0, arg1, ..., argN] -> [result]
  call,

  /// Call method: call_method &lt;u16 argc&gt;
  /// Stack: [obj, func, arg0, ..., argN] -> [result]
  callMethod,

  /// New: call_constructor &lt;u16 argc&gt;
  /// Stack: [constructor, arg0, ..., argN] -> [instance]
  callConstructor,

  /// Tail call (reuse frame): tail_call &lt;u16 argc&gt;
  tailCall,

  /// Tail call method (reuse frame): tail_call_method &lt;u16 argc&gt;
  tailCallMethod,

  /// Apply: call with args array. Stack: [func, argsArray] -> [result]
  apply,

  /// Apply method: call with args array. Stack: [obj, func, argsArray] -> [result]
  applyMethod,

  /// Apply constructor: new with args array. Stack: [constructor, argsArray] -> [instance]
  applyConstructor,

  /// Return value from function
  return_, // [value] -> (returns to caller)
  /// Return undefined
  returnUndef, // [] -> (returns undefined to caller)
  // ============================================================
  // Function/closure creation
  // ============================================================

  /// Create function closure: fclosure &lt;u16 func_index&gt;
  /// Captures current scope's variables as closure refs
  fclosure, // [] -> [function]
  // ============================================================
  // Exception handling
  // ============================================================

  /// Throw value as exception
  throw_, // [value] -> (throws)
  /// Throw predefined error: throw_error &lt;u32 atom&gt; &lt;u8 error_type&gt;
  throwError, // [] -> (throws)
  /// Push catch handler: catch &lt;i32 catch_offset&gt;
  /// Pushes a try-catch frame. On exception, jumps to catch_offset.
  catch_,

  /// Pop catch handler (entering catch block or leaving try)
  uncatch,

  /// Push finally handler: gosub &lt;i32 finally_offset&gt;
  gosub,

  /// Return from finally: ret (jumps back to saved pc)
  ret,

  // ============================================================
  // Iteration / for-in / for-of
  // ============================================================

  /// Initialize for-in iteration
  forInStart, // [obj] -> [iterator]
  /// Get next for-in key
  forInNext, // [iterator] -> [iterator, key, done]
  /// Initialize for-of iteration (get [Symbol.iterator])
  forOfStart, // [iterable] -> [iterator]
  /// Get next for-of value
  forOfNext, // [iterator] -> [iterator, value, done]
  /// Close iterator (for break/return in for-of)
  iteratorClose, // [iterator] -> []
  /// Initialize for-await-of
  forAwaitOfStart,

  /// Get next for-await-of value
  forAwaitOfNext,

  // ============================================================
  // Generators
  // ============================================================

  /// Initial yield (generator entry point)
  initialYield, // [] -> (suspends)
  /// Yield value
  yield_, // [value] -> [received_value]
  /// Yield*: delegate to sub-generator
  yieldStar, // [iterable] -> [final_value]
  // ============================================================
  // Async / Await
  // ============================================================

  /// Await expression
  await_, // [promise] -> [resolved_value]
  /// Return from async function (wraps in resolved promise)
  returnAsync, // [value] -> (returns)
  /// Async yield* for async generators
  asyncYieldStar,

  // ============================================================
  // Scope / With
  // ============================================================

  /// Enter 'with' statement scope
  withGetVar, // [obj, ...] -> [...] (like get_var but through with-scope)
  withPutVar,
  enterWith, // [obj] -> []
  leaveWith,

  /// Enter/leave scope (used during compilation, resolved in pass 2)
  enterScope, // <u16 scope_index>
  leaveScope, // <u16 scope_index>
  // ============================================================
  // Class
  /// Regular function call: call &lt;u16 argc&gt;
  // ============================================================
  /// Direct eval call when the callee is syntactically `eval`
  callDirectEval, // [func, arg0, arg1, ..., argN] -> [result]
  /// Method call: call_method &lt;u16 argc&gt;

  /// Constructor call: call_constructor &lt;u16 argc&gt;
  /// Define class: define_class &lt;u32 atom&gt;
  /// Tail call: tail_call &lt;u16 argc&gt;
  defineClass,

  /// Tail method call: tail_call_method &lt;u16 argc&gt;

  /// Apply function with array args: apply
  /// Define method on class/object
  /// Direct eval apply when the callee is syntactically `eval`
  applyDirectEval, // [func, argsArray] -> [result]
  /// Apply method with array args: apply_method
  defineMethod, // [obj, func] -> [obj]
  /// Apply constructor with array args: apply_constructor
  /// Define getter/setter
  defineGetter, // [obj, func] -> [obj]
  defineSetter, // [obj, func] -> [obj]
  defineGetterElem, // [obj, func, key] -> [obj]
  defineSetterElem, // [obj, func, key] -> [obj]
  defineMethodElem, // [obj, func, key] -> [obj]
  /// Get/set super property
  getSuperField, // [key] -> [value]
  putSuperField, // [key, value] -> []
  // ============================================================
  // Miscellaneous
  // ============================================================

  /// Debugger statement
  debugger_,

  /// Import expression: import(source)
  import_,

  /// Create RegExp: regexp &lt;u32 pattern_atom&gt; &lt;u32 flags_atom&gt;
  regexp,

  /// Spread into array/call args
  spread,

  /// Template literal: build template
  templateLiteral,

  /// Optional chaining: if null/undefined, jump
  optionalChain, // [value] -> [value] or jump
  /// Nullish coalescing: if not null/undefined, jump
  nullishCoalesce, // [value] -> [value] or jump
  /// Typeof for unresolved reference (doesn't throw ReferenceError)
  typeOfVar, // &lt;u32 atom&gt; [] -> [string]
  /// Delete variable
  deleteVar, // &lt;u32 atom&gt; [] -> [bool]
  /// Destructuring operations
  destructureArray,
  destructureObject,
  getIterator,
  iteratorNext,

  /// Create arguments object
  createArguments,
  createMappedArguments,

  /// Push the current `this` binding onto the stack
  getThis,

  /// Push the current `new.target` binding onto the stack
  getNewTarget,

  /// Object rest destructuring: pops N excluded key strings + source object,
  /// pushes new object with remaining own properties.
  /// Operand: u16 = number of excluded keys N
  objectRest,
}

/// Number of opcodes
final int opCount = Op.values.length;

/// Operand format for each opcode
enum OpFmt {
  none, // no operands
  u8, // 1 byte unsigned
  i8, // 1 byte signed
  u16, // 2 bytes unsigned
  i16, // 2 bytes signed
  u32, // 4 bytes unsigned
  i32, // 4 bytes signed
  f64, // 8 bytes double
  atomU8, // 4 bytes atom + 1 byte flags
}

/// Stack effect: how many values consumed / produced
class OpInfo {
  final String name;
  final OpFmt fmt;
  final int stackPop; // values consumed from stack
  final int stackPush; // values pushed to stack

  const OpInfo(this.name, this.fmt, this.stackPop, this.stackPush);

  int get stackDelta => stackPush - stackPop;
}

/// Metadata for each opcode
const Map<Op, OpInfo> opInfo = {
  // Stack manipulation
  Op.pushUndefined: OpInfo('push_undefined', OpFmt.none, 0, 1),
  Op.pushNull: OpInfo('push_null', OpFmt.none, 0, 1),
  Op.pushTrue: OpInfo('push_true', OpFmt.none, 0, 1),
  Op.pushFalse: OpInfo('push_false', OpFmt.none, 0, 1),
  Op.pushI32: OpInfo('push_i32', OpFmt.i32, 0, 1),
  Op.pushF64: OpInfo('push_f64', OpFmt.f64, 0, 1),
  Op.pushConst: OpInfo('push_const', OpFmt.u16, 0, 1),
  Op.pushEmptyString: OpInfo('push_empty_string', OpFmt.none, 0, 1),
  Op.push0: OpInfo('push_0', OpFmt.none, 0, 1),
  Op.push1: OpInfo('push_1', OpFmt.none, 0, 1),
  Op.push2: OpInfo('push_2', OpFmt.none, 0, 1),
  Op.push3: OpInfo('push_3', OpFmt.none, 0, 1),
  Op.push4: OpInfo('push_4', OpFmt.none, 0, 1),
  Op.push5: OpInfo('push_5', OpFmt.none, 0, 1),
  Op.push6: OpInfo('push_6', OpFmt.none, 0, 1),
  Op.push7: OpInfo('push_7', OpFmt.none, 0, 1),
  Op.dup: OpInfo('dup', OpFmt.none, 0, 1),
  Op.dup2: OpInfo('dup2', OpFmt.none, 0, 2),
  Op.drop: OpInfo('drop', OpFmt.none, 1, 0),
  Op.swap: OpInfo('swap', OpFmt.none, 0, 0),
  Op.rot3l: OpInfo('rot3l', OpFmt.none, 0, 0),
  Op.insert3: OpInfo('insert3', OpFmt.none, 0, 0),
  Op.insert4: OpInfo('insert4', OpFmt.none, 0, 0),
  Op.nop: OpInfo('nop', OpFmt.none, 0, 0),

  // Locals
  Op.getLoc: OpInfo('get_loc', OpFmt.u16, 0, 1),
  Op.putLoc: OpInfo('put_loc', OpFmt.u16, 1, 0),
  Op.setLoc: OpInfo('set_loc', OpFmt.u16, 0, 0),
  Op.getLoc0: OpInfo('get_loc0', OpFmt.none, 0, 1),
  Op.getLoc1: OpInfo('get_loc1', OpFmt.none, 0, 1),
  Op.getLoc2: OpInfo('get_loc2', OpFmt.none, 0, 1),
  Op.getLoc3: OpInfo('get_loc3', OpFmt.none, 0, 1),
  Op.putLoc0: OpInfo('put_loc0', OpFmt.none, 1, 0),
  Op.putLoc1: OpInfo('put_loc1', OpFmt.none, 1, 0),
  Op.putLoc2: OpInfo('put_loc2', OpFmt.none, 1, 0),
  Op.putLoc3: OpInfo('put_loc3', OpFmt.none, 1, 0),

  // Arguments
  Op.getArg: OpInfo('get_arg', OpFmt.u16, 0, 1),
  Op.putArg: OpInfo('put_arg', OpFmt.u16, 1, 0),
  Op.setArg: OpInfo('set_arg', OpFmt.u16, 0, 0),
  Op.getArg0: OpInfo('get_arg0', OpFmt.none, 0, 1),
  Op.getArg1: OpInfo('get_arg1', OpFmt.none, 0, 1),
  Op.getArg2: OpInfo('get_arg2', OpFmt.none, 0, 1),
  Op.getArg3: OpInfo('get_arg3', OpFmt.none, 0, 1),

  // Closure refs
  Op.getVarRef: OpInfo('get_var_ref', OpFmt.u16, 0, 1),
  Op.putVarRef: OpInfo('put_var_ref', OpFmt.u16, 1, 0),
  Op.setVarRef: OpInfo('set_var_ref', OpFmt.u16, 0, 0),

  // Globals
  Op.getVar: OpInfo('get_var', OpFmt.u32, 0, 1),
  Op.putVar: OpInfo('put_var', OpFmt.u32, 1, 0),
  Op.checkVar: OpInfo('check_var', OpFmt.u32, 0, 1),
  Op.checkVarStrict: OpInfo('check_var_strict', OpFmt.u32, 0, 0),
  Op.defineVar: OpInfo('define_var', OpFmt.atomU8, 0, 0),

  // Properties
  Op.getField: OpInfo('get_field', OpFmt.u32, 1, 1),
  Op.putField: OpInfo('put_field', OpFmt.u32, 2, 0),
  Op.getElem: OpInfo('get_elem', OpFmt.none, 2, 1),
  Op.putElem: OpInfo('put_elem', OpFmt.none, 3, 0),
  Op.deleteField: OpInfo('delete_field', OpFmt.u32, 1, 1),
  Op.deleteElem: OpInfo('delete_elem', OpFmt.none, 2, 1),
  Op.inOp: OpInfo('in', OpFmt.none, 2, 1),
  Op.instanceOf: OpInfo('instanceof', OpFmt.none, 2, 1),

  // Object/Array
  Op.object: OpInfo('object', OpFmt.none, 0, 1),
  Op.array: OpInfo('array', OpFmt.none, 0, 1),
  Op.arrayAppend: OpInfo('array_append', OpFmt.none, 1, 0),
  Op.arrayHole: OpInfo('array_hole', OpFmt.none, 0, 0),
  Op.defineProp: OpInfo('define_prop', OpFmt.atomU8, 1, 0),
  Op.copyDataProperties: OpInfo('copy_data_properties', OpFmt.none, 1, 0),
  Op.setProto: OpInfo('set_proto', OpFmt.none, 1, 0),

  // Arithmetic
  Op.add: OpInfo('add', OpFmt.none, 2, 1),
  Op.sub: OpInfo('sub', OpFmt.none, 2, 1),
  Op.mul: OpInfo('mul', OpFmt.none, 2, 1),
  Op.div: OpInfo('div', OpFmt.none, 2, 1),
  Op.mod: OpInfo('mod', OpFmt.none, 2, 1),
  Op.pow: OpInfo('pow', OpFmt.none, 2, 1),
  Op.shl: OpInfo('shl', OpFmt.none, 2, 1),
  Op.sar: OpInfo('sar', OpFmt.none, 2, 1),
  Op.shr: OpInfo('shr', OpFmt.none, 2, 1),
  Op.bitAnd: OpInfo('and', OpFmt.none, 2, 1),
  Op.bitOr: OpInfo('or', OpFmt.none, 2, 1),
  Op.bitXor: OpInfo('xor', OpFmt.none, 2, 1),
  Op.neg: OpInfo('neg', OpFmt.none, 1, 1),
  Op.plus: OpInfo('plus', OpFmt.none, 1, 1),
  Op.toNumeric: OpInfo('to_numeric', OpFmt.none, 1, 1),
  Op.bitNot: OpInfo('not', OpFmt.none, 1, 1),
  Op.not: OpInfo('lnot', OpFmt.none, 1, 1),
  Op.typeOf: OpInfo('typeof', OpFmt.none, 1, 1),
  Op.voidOp: OpInfo('void', OpFmt.none, 1, 1),
  Op.inc: OpInfo('inc', OpFmt.none, 1, 1),
  Op.dec: OpInfo('dec', OpFmt.none, 1, 1),

  // Comparison
  Op.lt: OpInfo('lt', OpFmt.none, 2, 1),
  Op.lte: OpInfo('lte', OpFmt.none, 2, 1),
  Op.gt: OpInfo('gt', OpFmt.none, 2, 1),
  Op.gte: OpInfo('gte', OpFmt.none, 2, 1),
  Op.eq: OpInfo('eq', OpFmt.none, 2, 1),
  Op.neq: OpInfo('neq', OpFmt.none, 2, 1),
  Op.strictEq: OpInfo('strict_eq', OpFmt.none, 2, 1),
  Op.strictNeq: OpInfo('strict_neq', OpFmt.none, 2, 1),
  Op.isNullOrUndefined: OpInfo('is_null_or_undef', OpFmt.none, 1, 1),

  // Control flow
  Op.ifFalse: OpInfo('if_false', OpFmt.i16, 1, 0),
  Op.ifTrue: OpInfo('if_true', OpFmt.i16, 1, 0),
  Op.goto_: OpInfo('goto', OpFmt.i32, 0, 0),
  Op.ifFalse8: OpInfo('if_false8', OpFmt.i8, 1, 0),
  Op.ifTrue8: OpInfo('if_true8', OpFmt.i8, 1, 0),
  Op.goto8: OpInfo('goto8', OpFmt.i8, 0, 0),

  // Calls
  Op.call: OpInfo('call', OpFmt.u16, -1, 1), // dynamic
  Op.callDirectEval: OpInfo('call_direct_eval', OpFmt.u16, -1, 1),
  Op.callMethod: OpInfo('call_method', OpFmt.u16, -1, 1),
  Op.callConstructor: OpInfo('call_constructor', OpFmt.u16, -1, 1),
  Op.tailCall: OpInfo('tail_call', OpFmt.u16, -1, 1),
  Op.tailCallMethod: OpInfo('tail_call_method', OpFmt.u16, -1, 1),
  Op.apply: OpInfo('apply', OpFmt.none, 2, 1),
  Op.applyDirectEval: OpInfo('apply_direct_eval', OpFmt.none, 2, 1),
  Op.applyMethod: OpInfo('apply_method', OpFmt.none, 3, 1),
  Op.applyConstructor: OpInfo('apply_constructor', OpFmt.none, 2, 1),
  Op.return_: OpInfo('return', OpFmt.none, 1, 0),
  Op.returnUndef: OpInfo('return_undef', OpFmt.none, 0, 0),

  // Closures
  Op.fclosure: OpInfo('fclosure', OpFmt.u16, 0, 1),

  // Exceptions
  Op.throw_: OpInfo('throw', OpFmt.none, 1, 0),
  Op.throwError: OpInfo('throw_error', OpFmt.atomU8, 0, 0),
  Op.catch_: OpInfo('catch', OpFmt.i32, 0, 0),
  Op.uncatch: OpInfo('uncatch', OpFmt.none, 0, 0),
  Op.gosub: OpInfo('gosub', OpFmt.i32, 0, 0),
  Op.ret: OpInfo('ret', OpFmt.none, 0, 0),

  // Iteration
  Op.forInStart: OpInfo('for_in_start', OpFmt.none, 1, 1),
  Op.forInNext: OpInfo('for_in_next', OpFmt.none, 0, 2),
  Op.forOfStart: OpInfo('for_of_start', OpFmt.none, 1, 1),
  Op.forOfNext: OpInfo('for_of_next', OpFmt.none, 0, 2),
  Op.iteratorClose: OpInfo('iterator_close', OpFmt.none, 1, 0),
  Op.forAwaitOfStart: OpInfo('for_await_of_start', OpFmt.none, 1, 1),
  Op.forAwaitOfNext: OpInfo('for_await_of_next', OpFmt.none, 0, 2),

  // Generators
  Op.initialYield: OpInfo('initial_yield', OpFmt.none, 0, 0),
  Op.yield_: OpInfo('yield', OpFmt.none, 1, 1),
  Op.yieldStar: OpInfo('yield_star', OpFmt.none, 1, 1),

  // Async
  Op.await_: OpInfo('await', OpFmt.none, 1, 1),
  Op.returnAsync: OpInfo('return_async', OpFmt.none, 1, 0),
  Op.asyncYieldStar: OpInfo('async_yield_star', OpFmt.none, 1, 1),

  // With/Scope
  Op.withGetVar: OpInfo('with_get_var', OpFmt.u32, 1, 1),
  Op.withPutVar: OpInfo('with_put_var', OpFmt.u32, 2, 0),
  Op.enterWith: OpInfo('enter_with', OpFmt.none, 1, 0),
  Op.leaveWith: OpInfo('leave_with', OpFmt.none, 0, 0),
  Op.enterScope: OpInfo('enter_scope', OpFmt.u16, 0, 0),
  Op.leaveScope: OpInfo('leave_scope', OpFmt.u16, 0, 0),

  // Class
  Op.defineClass: OpInfo('define_class', OpFmt.u32, -1, 1),
  Op.defineMethod: OpInfo('define_method', OpFmt.u32, 1, 0),
  Op.defineGetter: OpInfo('define_getter', OpFmt.u32, 1, 0),
  Op.defineSetter: OpInfo('define_setter', OpFmt.u32, 1, 0),
  Op.defineGetterElem: OpInfo('define_getter_elem', OpFmt.none, 2, 0),
  Op.defineSetterElem: OpInfo('define_setter_elem', OpFmt.none, 2, 0),
  Op.defineMethodElem: OpInfo('define_method_elem', OpFmt.none, 2, 0),
  Op.getSuperField: OpInfo('get_super', OpFmt.none, 1, 1),
  Op.putSuperField: OpInfo('put_super', OpFmt.none, 2, 0),

  // Misc
  Op.debugger_: OpInfo('debugger', OpFmt.none, 0, 0),
  Op.import_: OpInfo('import', OpFmt.none, 1, 1),
  Op.regexp: OpInfo('regexp', OpFmt.none, 2, 1),
  Op.spread: OpInfo('spread', OpFmt.none, 1, -1),
  Op.templateLiteral: OpInfo('template_literal', OpFmt.u16, -1, 1),
  Op.optionalChain: OpInfo('optional_chain', OpFmt.i16, 0, 0),
  Op.nullishCoalesce: OpInfo('nullish_coalesce', OpFmt.i16, 0, 0),
  Op.typeOfVar: OpInfo('typeof_var', OpFmt.u32, 0, 1),
  Op.deleteVar: OpInfo('delete_var', OpFmt.u32, 0, 1),
  Op.destructureArray: OpInfo('destructure_array', OpFmt.none, 2, -1),
  Op.destructureObject: OpInfo('destructure_object', OpFmt.none, 2, -1),
  Op.getIterator: OpInfo('get_iterator', OpFmt.none, 1, 1),
  Op.iteratorNext: OpInfo('iterator_next', OpFmt.none, 1, 2),
  Op.createArguments: OpInfo('create_arguments', OpFmt.none, 0, 1),
  Op.createMappedArguments: OpInfo('create_mapped_arguments', OpFmt.none, 0, 1),
  Op.getThis: OpInfo('get_this', OpFmt.none, 0, 1),
  Op.getNewTarget: OpInfo('get_new_target', OpFmt.none, 0, 1),
  Op.objectRest: OpInfo('object_rest', OpFmt.u16, -1, 1),
};
