/// Abstract runtime interface for JavaScript execution.
///
/// Both the tree-walking evaluator (JSEvaluator) and the bytecode VM
/// implement this interface. Runtime types (JSPromise, JSObject, etc.)
/// use [JSRuntime.current] instead of depending on a specific backend.
library;

import 'js_value.dart';

/// Global function caller / runtime interface.
///
/// Provides the minimal API that runtime types need to call back into
/// the execution engine (whichever backend is active).
abstract class JSRuntime {
  // ---------------------------------------------------------------------------
  // Static singleton — set by the active execution engine
  // ---------------------------------------------------------------------------

  static JSRuntime? _current;

  /// The currently active runtime (evaluator or bytecode VM wrapper).
  static JSRuntime? get current => _current;

  /// Set the active runtime.  Called by the engine at the start of execution.
  static void setCurrent(JSRuntime? runtime) {
    _current = runtime;
  }

  // ---------------------------------------------------------------------------
  // Function calling
  // ---------------------------------------------------------------------------

  /// Call [func] with [args] and optional [thisBinding].
  ///
  /// This is the universal entry-point used by getters, setters, Promise
  /// callbacks, Proxy traps, etc.
  JSValue callFunction(
    JSValue func,
    List<JSValue> args, [
    JSValue? thisBinding,
  ]);

  // ---------------------------------------------------------------------------
  // Strict mode
  // ---------------------------------------------------------------------------

  /// Whether the current execution context is in strict mode.
  bool isStrictMode();

  // ---------------------------------------------------------------------------
  // Async / microtask scheduling
  // ---------------------------------------------------------------------------

  /// Enqueue a microtask (Promise callback) to be executed.
  void enqueueMicrotask(void Function() callback);

  /// Notify the scheduler that [promise] has been resolved/rejected.
  void notifyPromiseResolved(JSPromise promise);

  /// Execute all pending microtasks / async tasks.
  void runPendingTasks();

  // ---------------------------------------------------------------------------
  // Eval
  // ---------------------------------------------------------------------------

  /// Evaluate JavaScript source code (used by the `eval()` global function).
  JSValue evalCode(String code, {bool directEval = false});

  // ---------------------------------------------------------------------------
  // Globals
  // ---------------------------------------------------------------------------

  /// Look up a global binding by name (e.g. `"TypeError"` → its constructor).
  JSValue getGlobal(String name);

  // ---------------------------------------------------------------------------
  // Weak references / host GC hooks
  // ---------------------------------------------------------------------------

  /// Whether [value] is currently reachable from strong runtime roots.
  bool isValueReachable(JSValue value) => true;

  /// Register a weak map instance with the active runtime.
  void registerWeakMap(JSWeakMap weakMap) {}

  /// Register a weak reference instance with the active runtime.
  void registerWeakRef(JSWeakRefObject weakRef) {}

  /// Register a finalization registry instance with the active runtime.
  void registerFinalizationRegistry(JSFinalizationRegistryObject registry) {}

  /// Run the host's observable weak-reference garbage collection step.
  void performHostGarbageCollection() {}

  // ---------------------------------------------------------------------------
  // Function caller tracking (for Function.caller)
  // ---------------------------------------------------------------------------

  /// Get the caller of [callee] (for `Function.caller`).
  /// Returns null if unavailable or restricted by strict mode.
  JSValue? getCurrentCaller(JSFunction callee) => null;

  // ---------------------------------------------------------------------------
  // Getter / setter cycle detection
  // ---------------------------------------------------------------------------

  bool isGetterCycle(JSObject obj, String property) => false;
  void markGetterActive(JSObject obj, String property) {}
  void unmarkGetterActive(JSObject obj, String property) {}
  bool isSetterCycle(JSObject obj, String property) => false;
  void markSetterActive(JSObject obj, String property) {}
  void unmarkSetterActive(JSObject obj, String property) {}

  // ---------------------------------------------------------------------------
  // AST evaluation (evaluator-only; bytecode VM returns undefined)
  // ---------------------------------------------------------------------------

  /// Evaluate an AST expression node. Only meaningful for the tree-walking
  /// evaluator.  The bytecode VM returns undefined.
  JSValue evalASTNode(dynamic node) => JSUndefined.instance;

  /// Execute a static block in a class. Only meaningful for the tree-walking
  /// evaluator.
  void executeStaticBlock(dynamic body, JSValue classObj) {}
}

/// Specialized function objects that can execute directly on any runtime.
///
/// This lets the VM call selected legacy JSFunction subclasses without going
/// through the generic evaluator bridge.
abstract class RuntimeCallableFunction {
  JSValue callWithRuntime(
    List<JSValue> args,
    JSValue thisBinding,
    JSRuntime runtime,
  );
}
