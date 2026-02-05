library;

/// JavaScript evaluator
/// Interprets the AST and executes JavaScript code

import 'dart:async';
import 'dart:math' as math;
import 'package:js_interpreter/js_interpreter.dart';

/// Helper to safely convert a double to int, handling Infinity/NaN per ES spec
int _safeToInt(
  double value, {
  int defaultForNaN = 0,
  int? maxValue,
  int? minValue,
}) {
  if (value.isNaN) return defaultForNaN;
  if (value.isInfinite) {
    if (value.isNegative) {
      return minValue ?? -0x1FFFFFFFFFFFFF;
    } else {
      return maxValue ?? 0x1FFFFFFFFFFFFF;
    }
  }
  return value.truncate();
}

/// Possible states of an asynchronous task
enum AsyncTaskState { running, suspended, completed, failed }

/// Exception thrown when an async function is suspended by await
class AsyncSuspensionException implements Exception {
  final String message;
  AsyncSuspensionException(this.message);

  @override
  String toString() => message;
}

/// Exception thrown when a generator is suspended by yield
class GeneratorYieldException implements Exception {
  final JSValue value;
  final bool delegate; // true for yield*, false for yield

  GeneratorYieldException(this.value, {this.delegate = false});

  @override
  String toString() => 'Generator yielded: $value';
}

/// Completion record for tracking statement values
/// According to ECMA-262, a completion record contains:
/// - value: the completion value
/// - type: normal, break, continue, return, throw
/// - target: optional label for break/continue
class CompletionRecord {
  final JSValue value;
  final String type; // 'normal', 'break', 'continue', 'return', 'throw'
  final String? target; // label name for break/continue

  CompletionRecord({required this.value, required this.type, this.target});

  static CompletionRecord normal(JSValue value) =>
      CompletionRecord(value: value, type: 'normal');

  bool get isNormal => type == 'normal';
  bool get isAbrupt => type != 'normal';
}

/// Execution context for a generator
/// Stores state between next() calls
class GeneratorExecutionContext {
  final FunctionDeclaration node;
  final List<JSValue> args;
  final Environment closureEnv;

  // Generator execution environment (created on first execution)
  Environment? executionEnv;

  // Value to inject into generator (via next(value))
  JSValue? inputValue;

  // If true, generator should throw an exception instead of resuming normally
  bool shouldThrow = false;
  JSValue? exceptionToThrow;

  // Index of next statement to execute in function body
  int currentStatementIndex = 0;

  // Stack of continuations to handle yields in loops/blocks
  final List<GeneratorContinuation> continuationStack = [];

  // Counter of executed yields (to distinguish yields in loops)
  int yieldCount = 0;

  // Number of the last yield that suspended
  int? lastYieldNumber;

  // If true, next visitYieldExpression should return inputValue instead of yielding
  bool resumingFromYield = false;

  // For yield* - iterator delegation
  JSValue? delegatedIterator;
  int? delegatingYieldNumber;

  JSValue? thisBinding;

  // Cache of yield results (yield number -> yielded value)
  final Map<int, JSValue> yieldResults = {};

  // Index of statement where last yield occurred
  // Used to avoid re-execution of side effects before yield
  int? lastYieldStatementIndex;

  GeneratorExecutionContext({
    required this.node,
    required this.args,
    required this.closureEnv,
    this.thisBinding,
  });
}

/// Represents a continuation to resume execution at a specific point
class GeneratorContinuation {
  final Statement statement;
  final Map<String, dynamic> state; // Custom state depending on statement type

  GeneratorContinuation(this.statement, {Map<String, dynamic>? state})
    : state = state ?? {};
}

/// Wrapper for async functions that properly handles .call() and .apply()
class _JSAsyncFunctionWrapper extends JSNativeFunction {
  final AsyncFunctionDeclaration asyncNode;
  final Environment closureEnv;
  @override
  // ignore: overridden_fields
  final String? moduleUrl;
  final JSEvaluator evaluator;

  _JSAsyncFunctionWrapper(
    String functionName,
    int expectedArgs,
    this.asyncNode,
    this.closureEnv,
    this.moduleUrl,
    this.evaluator,
  ) : super(
        functionName: functionName,
        expectedArgs: expectedArgs,
        nativeImpl: (_) => throw 'Should not be called directly',
      );

  @override
  JSValue callWithThis(List<JSValue> args, JSValue thisBinding) {
    // Normal call with explicit thisBinding (from .call(), .apply(), etc.)
    // args are the actual function arguments
    // thisBinding is the 'this' value
    return _createAsyncPromise(args, thisBinding);
  }

  @override
  JSValue call(List<JSValue> args) {
    // Normal call without explicit thisBinding
    return _createAsyncPromise(args, JSValueFactory.undefined());
  }

  JSValue _createAsyncPromise(List<JSValue> args, JSValue thisBinding) {
    // Create a Promise for this async function
    final promise = JSPromise(
      JSNativeFunction(
        functionName: '${functionName}_resolver',
        nativeImpl: (executorArgs) {
          final resolve = executorArgs[0] as JSNativeFunction;
          final reject = executorArgs[1] as JSNativeFunction;

          // Create an async task for this execution
          final taskId =
              'async_${functionName}_${DateTime.now().millisecondsSinceEpoch}';
          final asyncTask = AsyncTask(taskId);

          // Create the continuation with thisBinding
          final continuation = AsyncContinuation(
            asyncNode,
            args,
            closureEnv,
            resolve,
            reject,
            moduleUrl,
            thisBinding, // Pass the thisBinding!
          );
          asyncTask.setContinuation(continuation);

          // Add task to scheduler
          evaluator._asyncScheduler.addTask(asyncTask);

          // Start async execution
          evaluator._executeAsyncFunction(asyncTask);

          return JSValueFactory.undefined();
        },
      ),
    );

    return promise;
  }
}

/// Represents a continuation for an async function
class AsyncContinuation {
  final AsyncFunctionDeclaration node;
  final List<JSValue> args;
  final Environment closureEnv;
  final JSNativeFunction resolve;
  final JSNativeFunction reject;
  final String? moduleUrl; // Module URL where the async function was defined
  final JSValue? thisBinding; // 'this' binding for method calls
  final JSClass? parentClass; // Parent class for method calls

  // Execution state
  int _currentAwaitIndex = 0;
  final List<JSValue> _awaitedValues = [];
  Environment?
  _functionEnv; // Function environment preserved between executions
  Environment?
  _bodyBlockEnv; // Body block environment preserved between executions

  // Cache for objects created by 'new' expressions during async execution
  // Key is the hashCode of the NewExpression AST node
  final Map<int, JSValue> _createdObjects = {};

  AsyncContinuation(
    this.node,
    this.args,
    this.closureEnv,
    this.resolve,
    this.reject,
    this.moduleUrl, [
    this.thisBinding,
    this.parentClass,
  ]);

  /// Gets or creates the function environment
  Environment getFunctionEnv(JSEvaluator evaluator) {
    if (_functionEnv == null) {
      // Create the function environment once
      _functionEnv = Environment(parent: closureEnv);
      // Create a separate parameter scope environment for default evaluation
      final paramScopeEnv = Environment(parent: closureEnv);

      // Collect all parameter names for eval validation
      final parameterNames = <String>{};
      for (final param in node.params) {
        if (param.name != null && !param.isRest) {
          parameterNames.add(param.name!.name);
        }
      }

      // First pass: Create uninitialized TDZ bindings for all parameters with defaults
      // This ensures parameters cannot reference themselves in their own default values
      for (final param in node.params) {
        if (param.name != null && !param.isRest && param.defaultValue != null) {
          paramScopeEnv.defineUninitialized(
            param.name!.name,
            BindingType.parameter,
          );
        }
      }

      // Bind parameters to arguments (only once)
      int argIndex = 0;
      for (int i = 0; i < node.params.length; i++) {
        final param = node.params[i];

        if (param.isRest) {
          // Rest parameter: collect all remaining arguments
          final restArgs = <JSValue>[];
          for (int j = argIndex; j < args.length; j++) {
            restArgs.add(args[j]);
          }
          final argValue = JSValueFactory.array(restArgs);
          if (param.name != null) {
            paramScopeEnv.define(
              param.name!.name,
              argValue,
              BindingType.parameter,
            );
            _functionEnv!.define(
              param.name!.name,
              argValue,
              BindingType.parameter,
            );
          }
          break;
        } else if (param.isDestructuring && param.pattern != null) {
          // Destructuring parameter
          JSValue argValue;
          if (argIndex < args.length) {
            argValue = args[argIndex];
          } else if (param.defaultValue != null) {
            // Evaluate default in parameter scope environment where previous params are visible
            final paramContext = ExecutionContext(
              lexicalEnvironment: paramScopeEnv,
              variableEnvironment: paramScopeEnv,
              thisBinding: JSValueFactory.undefined(),
              strictMode: false,
              parameterNames: parameterNames,
            );
            evaluator._executionStack.push(paramContext);
            try {
              argValue = param.defaultValue!.accept(evaluator);
            } finally {
              evaluator._executionStack.pop();
            }
          } else {
            argValue = JSValueFactory.undefined();
          }
          evaluator._destructurePattern(
            param.pattern!,
            argValue,
            paramScopeEnv,
          );
          evaluator._destructurePattern(
            param.pattern!,
            argValue,
            _functionEnv!,
          );
          argIndex++;
        } else {
          // Simple parameter
          JSValue argValue;
          if (argIndex < args.length) {
            if (args[argIndex].isUndefined && param.defaultValue != null) {
              // Evaluate default in parameter scope environment where previous params are visible
              final paramContext = ExecutionContext(
                lexicalEnvironment: paramScopeEnv,
                variableEnvironment: paramScopeEnv,
                thisBinding: JSValueFactory.undefined(),
                strictMode: false,
                parameterNames: parameterNames,
              );
              evaluator._executionStack.push(paramContext);
              try {
                argValue = param.defaultValue!.accept(evaluator);
              } finally {
                evaluator._executionStack.pop();
              }
            } else {
              argValue = args[argIndex];
            }
          } else {
            if (param.defaultValue != null) {
              // Evaluate default in parameter scope environment where previous params are visible
              final paramContext = ExecutionContext(
                lexicalEnvironment: paramScopeEnv,
                variableEnvironment: paramScopeEnv,
                thisBinding: JSValueFactory.undefined(),
                strictMode: false,
                parameterNames: parameterNames,
              );
              evaluator._executionStack.push(paramContext);
              try {
                argValue = param.defaultValue!.accept(evaluator);
              } finally {
                evaluator._executionStack.pop();
              }
            } else {
              argValue = JSValueFactory.undefined();
            }
          }
          if (param.name != null) {
            paramScopeEnv.define(
              param.name!.name,
              argValue,
              BindingType.parameter,
            );
            _functionEnv!.define(
              param.name!.name,
              argValue,
              BindingType.parameter,
            );
          }
          argIndex++;
        }
      }

      // Create arguments object
      // Check if we should use mapped arguments (non-strict with simple parameters)
      // Simple parameters = no defaults, no destructuring, no rest
      final hasSimpleParams = node.params.every(
        (p) =>
            !p.isRest &&
            !p.isDestructuring &&
            p.name != null &&
            p.defaultValue == null,
      );

      final isStrictMode = false; // Async functions in non-strict mode for now

      final JSObject argumentsObject;
      if (!isStrictMode && hasSimpleParams) {
        // Create mapped arguments - changes to arguments[i] sync with parameters
        final parameterNames = <int, String>{};
        for (int i = 0; i < node.params.length && i < args.length; i++) {
          final param = node.params[i];
          if (param.name != null) {
            parameterNames[i] = param.name!.name;
          }
        }
        argumentsObject = JSMappedArguments(
          parameterNames: parameterNames,
          functionEnv: _functionEnv!,
          prototype: JSObject.objectPrototype,
        );
      } else {
        // Create regular unmapped arguments object
        argumentsObject = JSValueFactory.argumentsObject({});
      }

      argumentsObject.setProperty(
        'length',
        JSValueFactory.number(args.length.toDouble()),
      );
      for (int i = 0; i < args.length; i++) {
        argumentsObject.setProperty(i.toString(), args[i]);
      }
      _functionEnv!.define('arguments', argumentsObject, BindingType.var_);

      // For async functions, add 'this' as special variable if thisBinding is defined
      if (thisBinding != null) {
        _functionEnv!.define('this', thisBinding!, BindingType.var_);
      }
    }
    return _functionEnv!;
  }

  /// Gets or creates the block environment for function body
  /// This environment is preserved between async resumptions
  Environment getOrCreateBodyBlockEnv(Environment parentEnv) {
    _bodyBlockEnv ??= Environment.block(parentEnv);
    return _bodyBlockEnv!;
  }

  /// Checks if body block environment has already been created
  bool get hasBodyBlockEnv => _bodyBlockEnv != null;

  /// Cache an object created by a 'new' expression
  void cacheCreatedObject(int nodeHashCode, JSValue object) {
    _createdObjects[nodeHashCode] = object;
  }

  /// Get a cached object if it exists
  JSValue? getCachedObject(int nodeHashCode) {
    return _createdObjects[nodeHashCode];
  }

  /// Clear the object cache to free memory after async function completes
  void clearObjectCache() {
    _createdObjects.clear();
  }

  /// Adds an awaited value (result of an await)
  void addAwaitedValue(JSValue value) {
    _awaitedValues.add(value);
    _currentAwaitIndex++;
  }

  /// Gets the next awaited value
  JSValue? getNextAwaitedValue() {
    if (_currentAwaitIndex < _awaitedValues.length) {
      return _awaitedValues[_currentAwaitIndex++];
    }
    return null;
  }

  /// Gets the current await index
  int get currentAwaitIndex => _currentAwaitIndex;

  /// Creates a copy of continuation for new call
  AsyncContinuation clone() {
    final copy = AsyncContinuation(
      node,
      args,
      closureEnv,
      resolve,
      reject,
      moduleUrl,
      thisBinding,
      parentClass,
    );
    copy._currentAwaitIndex = _currentAwaitIndex;
    copy._awaitedValues.addAll(_awaitedValues);
    copy._functionEnv = _functionEnv; // Preserve environment
    copy._bodyBlockEnv = _bodyBlockEnv; // Preserve body block environment
    copy._createdObjects.addAll(_createdObjects); // Preserve created objects
    return copy;
  }
}

/// Continuation for async arrow functions
class AsyncArrowContinuation {
  final JSAsyncArrowFunction arrowFunc;
  final List<JSValue> args;
  final JSNativeFunction resolve;
  final JSNativeFunction reject;

  AsyncArrowContinuation(this.arrowFunc, this.args, this.resolve, this.reject);
}

/// Represents an async task (async function) that can be suspended and resumed
/// Represents a value or expected error
class AwaitedResult {
  final JSValue value;
  final bool isError;

  AwaitedResult(this.value, {this.isError = false});
}

class AsyncTask {
  final String id;
  AsyncTaskState _state = AsyncTaskState.running;
  JSValue? _result;
  JSValue? _error;
  final List<AwaitedResult> _awaitedResults = [];
  int _currentAwaitIndex = 0;

  // Continuation to resume execution
  AsyncContinuation? _continuation;
  AsyncArrowContinuation? _arrowContinuation;

  // BUGFIX: Track if this is a resumed execution (not the first run)
  // Used to skip re-initialization of variables in the function body
  bool _isResumedExecution = false;

  AsyncTask(this.id);

  /// Returns true if this task has been resumed after suspension (not first execution)
  bool get isResumedExecution => _isResumedExecution;

  /// Mark that we're about to resume after a suspension
  void markAsResumed() {
    _isResumedExecution = true;
  }

  /// Current state of task
  AsyncTaskState get state => _state;

  /// Result of task (if completed)
  JSValue? get result => _result;

  /// Error of task (if failed)
  JSValue? get error => _error;

  /// Sets continuation for this task
  void setContinuation(AsyncContinuation continuation) {
    _continuation = continuation;
  }

  /// Sets arrow continuation for this task
  void setArrowContinuation(AsyncArrowContinuation continuation) {
    _arrowContinuation = continuation;
  }

  /// Suspend the task with a continuation
  void suspend() {
    _state = AsyncTaskState.suspended;
  }

  /// Resume the task with a value
  void resume(JSValue value) {
    if (_state == AsyncTaskState.suspended) {
      _state = AsyncTaskState.running;
      _awaitedResults.add(AwaitedResult(value, isError: false));
      _isResumedExecution = true; // Mark that we're resuming
      // The continuation will be executed by the evaluator
    }
  }

  /// Marks task as completed with a result
  void complete(JSValue result) {
    _state = AsyncTaskState.completed;
    _result = result;
    // Clear object cache to free memory
    _continuation?.clearObjectCache();
  }

  /// Marks task as failed with an error (for a specific await value)
  void fail(JSValue error) {
    // For individual awaits, add error as expected result
    if (_state == AsyncTaskState.suspended) {
      _state = AsyncTaskState.running;
      _awaitedResults.add(AwaitedResult(error, isError: true));
    } else {
      // For global task failure
      _state = AsyncTaskState.failed;
      _error = error;
      // Clear object cache to free memory
      _continuation?.clearObjectCache();
    }
  }

  /// Gets next expected result (for await)
  AwaitedResult? getNextAwaitedResult() {
    if (_currentAwaitIndex < _awaitedResults.length) {
      return _awaitedResults[_currentAwaitIndex++];
    }
    return null;
  }

  /// Gets the continuation
  AsyncContinuation? get continuation => _continuation;

  /// Gets the arrow continuation
  AsyncArrowContinuation? get arrowContinuation => _arrowContinuation;

  /// Resets the awaited results index for a new execution
  void resetAwaitedValueIndex() {
    _currentAwaitIndex = 0;
  }
}

/// Scheduler to manage async tasks
class AsyncScheduler {
  final List<AsyncTask> _pendingTasks = [];
  final List<AsyncTask> _suspendedTasks = [];
  final Map<JSPromise, List<AsyncTask>> _promiseWaiters = {};

  /// Adds a task to scheduler
  void addTask(AsyncTask task) {
    _pendingTasks.add(task);
  }

  /// Suspend a task waiting for a Promise
  void suspendTask(AsyncTask task, JSPromise promise) {
    task.suspend();
    _suspendedTasks.add(task);

    // Record that this task is waiting for this Promise
    _promiseWaiters.putIfAbsent(promise, () => []).add(task);
  }

  /// Notifies that a Promise has been resolved
  void notifyPromiseResolved(JSPromise promise, JSEvaluator evaluator) {
    final waiters = _promiseWaiters.remove(promise);
    if (waiters != null) {
      for (final task in waiters) {
        if (promise.state == PromiseState.fulfilled) {
          task.resume(promise.value ?? JSValueFactory.undefined());
          // Add the resumed task to pending tasks so it can be executed
          _pendingTasks.add(task);
        } else if (promise.state == PromiseState.rejected) {
          task.fail(
            promise.reason ?? JSValueFactory.string('Promise rejected'),
          );
          // For failed tasks, also add them to handle the error
          _pendingTasks.add(task);
        }
        _suspendedTasks.remove(task);
      }
      // Execute any pending tasks that were just resumed
      if (_pendingTasks.isNotEmpty) {
        evaluator.runPendingAsyncTasks();
      }
    }
  }

  /// Executes all pending tasks
  void runPendingTasks(JSEvaluator evaluator) {
    // Process only the tasks that were pending when this method was called
    // to avoid infinite loops when tasks add more tasks during execution
    final tasksToProcess = List<AsyncTask>.from(_pendingTasks);
    _pendingTasks.clear();

    for (final task in tasksToProcess) {
      if (task.state == AsyncTaskState.running) {
        // The task is ready to be executed or resumed
        if (task.arrowContinuation != null) {
          evaluator._executeAsyncArrowFunctionWithTask(task);
        } else {
          evaluator._executeAsyncFunction(task);
        }
      }
    }
  }

  /// Gets the number of pending tasks
  int get pendingTaskCount => _pendingTasks.length;

  /// Gets the number of suspended tasks
  int get suspendedTaskCount => _suspendedTasks.length;
}

/// Represente un module ES6
/// Module states according to ES2022 specification
enum ModuleStatus {
  unlinked, // Module is parsed but not yet linked
  linking, // Module is being linked
  linked, // Module is linked but not yet evaluated
  evaluating, // Module is being evaluated (sync)
  evaluatingAsync, // Module is being evaluated (has top-level await)
  evaluated, // Module evaluation completed successfully
  error, // Module evaluation failed
}

class JSModule {
  final String id;
  final Map<String, JSValue> exports = {};
  JSValue? defaultExport;
  bool isLoaded = false;
  late Environment environment; // Module-specific environment
  Program? ast; // Module AST for deferred evaluation

  // ES2022: Top-level await support
  bool hasTopLevelAwait = false;
  ModuleStatus status = ModuleStatus.unlinked;
  JSPromise? evaluationPromise; // Promise for async module evaluation
  JSValue? evaluationError; // Error if evaluation failed

  // Module dependencies
  final List<String> requestedModules = []; // Modules this module imports
  final List<JSModule> loadedRequestedModules = []; // Loaded dependency modules

  // Async evaluation tracking
  int? dfsIndex; // For cycle detection
  int? dfsAncestorIndex;
  bool? hasTLA; // Has Top-Level Await (after analysis)
  bool? cycleRoot; // Is this a cycle root
  List<JSModule>? asyncParentModules; // Modules waiting for this one

  JSModule(this.id, Environment globalEnvironment) {
    // Create module environment inheriting from global environment
    environment = Environment.module(globalEnvironment);
  }

  /// Check if module is ready to execute (all dependencies loaded and evaluated)
  bool get isReadyToExecute {
    if (status != ModuleStatus.linked) return false;
    return loadedRequestedModules.every(
      (m) =>
          m.status == ModuleStatus.evaluated ||
          m.status == ModuleStatus.evaluatingAsync,
    );
  }
}

/// Implements ES spec GetFunctionRealm (7.3.22)
/// Returns the realm (JSEvaluator) in which a function was created
JSEvaluator? _getFunctionRealmHelper(JSFunction func) {
  // Check if the function has a Realm internal slot
  final realm = func.getInternalSlot('Realm');
  if (realm is JSEvaluator) {
    return realm;
  }
  // Fall back to current evaluator if no realm is stored
  return JSEvaluator.currentInstance;
}

/// Gets the intrinsic prototype for a constructor type from a realm
/// This implements the fallback in GetPrototypeFromConstructor when
/// newTarget.prototype is not an object
JSObject? _getIntrinsicPrototypeHelper(
  String constructorName,
  JSEvaluator realm,
) {
  // Get the constructor from the realm's global environment
  final constructor = realm.globalEnvironment.get(constructorName);
  if (constructor is JSFunction) {
    final proto = constructor.getProperty('prototype');
    if (proto is JSObject) {
      return proto;
    }
  }
  // Fall back to Object.prototype
  final objectCtor = realm.globalEnvironment.get('Object');
  if (objectCtor is JSFunction) {
    final proto = objectCtor.getProperty('prototype');
    if (proto is JSObject) {
      return proto;
    }
  }
  return null;
}

/// Main evaluator for the JavaScript engine
class JSEvaluator implements ASTVisitor<JSValue> {
  final String? getInterpreterInstanceId;
  static String? _getInterpreterInstanceId;
  final ExecutionStack _executionStack = ExecutionStack();
  late Environment _globalEnvironment;
  late JSValue _globalThisBinding; // Global 'this' value for non-strict mode
  final AsyncScheduler _asyncScheduler = AsyncScheduler();
  bool moduleMode =
      false; // Track if we're in module mode (modules are always strict)

  /// Stack to track whether super() was called in each constructor level
  /// Each level of the inheritance hierarchy has its own entry
  final List<bool> _superCalledStack = [];

  /// Stack to track if we're currently in a constructor (true) or other function (false)
  final List<bool> _constructorStack = [];

  /// Stack to track the current 'this' value in constructor execution
  /// When super() returns an object, we update this stack
  final List<JSValue> _constructorThisStack = [];

  /// Stack to track the captured class context of arrow functions
  /// When calling an arrow function created in a class constructor, we push its context
  final List<JSClass?> _arrowFunctionClassContextStack = [];

  /// Function call stack for tracking caller-callee relationships (for Function.caller)
  final List<JSFunction?> _functionCallStack = [];

  /// Prototype manager - stores all prototypes for this interpreter instance
  final PrototypeManager prototypeManager = PrototypeManager();

  /// Current instance of the evaluator (for access from native methods)
  static JSEvaluator? _currentInstance;

  /// Notifies the scheduler that a Promise has been resolved
  void notifyPromiseResolved(JSPromise promise) {
    _asyncScheduler.notifyPromiseResolved(promise, this);
  }

  /// Manually executes pending asynchronous tasks (for testing)
  void runPendingAsyncTasks() {
    _asyncScheduler.runPendingTasks(this);
  }

  /// Schedules an asynchronous operation and returns a JavaScript Promise
  JSValue scheduleAsyncOperation(Future<JSValue> Function() asyncOperation) {
    // Create executor that captures resolve and reject
    final executor = JSNativeFunction(
      functionName: 'executor',
      nativeImpl: (args) {
        if (args.length >= 2) {
          final resolve = args[0] as JSNativeFunction;
          final reject = args[1] as JSNativeFunction;

          // Start the asynchronous operation and resolve the Promise when it completes
          asyncOperation()
              .then((result) {
                // Call resolve with the result
                resolve.call([result]);
              })
              .catchError((error) {
                // Call reject with the error
                reject.call([JSValueFactory.string(error.toString())]);
              });
        }
        return JSValueFactory.undefined();
      },
    );

    // Create Promise with executor
    return JSPromise(executor);
  }

  /// Set to detect circular references in getters
  static final Set<String> _activeGetters = <String>{};

  /// Set to detect circular references in setters
  static final Set<String> _activeSetters = <String>{};

  /// Stack to track the current class context (for private properties)
  final List<JSClass> _classContextStack = [];

  /// Target binding name for function name inference (ES6 anonymous function names)
  /// When a function expression is used as a default initializer in destructuring,
  /// e.g., [x = function() {}], the function should get name 'x'
  String? _targetBindingNameForFunction;

  JSEvaluator({this.getInterpreterInstanceId}) {
    _getInterpreterInstanceId = getInterpreterInstanceId;
    // Initialize within the prototype manager's Zone
    _currentInstance =
        this; // Register the current instance BEFORE initialization
    prototypeManager.runWithin(() {
      _initializeGlobalEnvironment();
    });
  }

  /// Gets the current evaluator instance (for native callbacks)
  static JSEvaluator? get currentInstance => _currentInstance;

  /// Sets the current evaluator instance (used for Realm switching)
  static void setCurrentInstance(JSEvaluator evaluator) {
    _currentInstance = evaluator;
  }

  /// Checks and manages cycles in getters
  static bool isGetterCycle(JSObject obj, String propertyName) {
    final key = '${obj.hashCode}.$propertyName';
    return _activeGetters.contains(key);
  }

  /// Marks a getter as active
  static void markGetterActive(JSObject obj, String propertyName) {
    final key = '${obj.hashCode}.$propertyName';
    _activeGetters.add(key);
  }

  /// Unmarks a getter as inactive
  static void unmarkGetterActive(JSObject obj, String propertyName) {
    final key = '${obj.hashCode}.$propertyName';
    _activeGetters.remove(key);
  }

  /// Checks and manages cycles in setters
  static bool isSetterCycle(JSObject obj, String propertyName) {
    final key = '${obj.hashCode}.$propertyName';
    return _activeSetters.contains(key);
  }

  /// Marks a setter as active
  static void markSetterActive(JSObject obj, String propertyName) {
    final key = '${obj.hashCode}.$propertyName';
    _activeSetters.add(key);
  }

  /// Unmarks a setter as inactive
  static void unmarkSetterActive(JSObject obj, String propertyName) {
    final key = '${obj.hashCode}.$propertyName';
    _activeSetters.remove(key);
  }

  /// Access to the global environment (for testing)
  Environment get globalEnvironment => _globalEnvironment;

  /// Checks if we are currently in strict mode
  bool isCurrentlyInStrictMode() {
    if (_executionStack.isEmpty) {
      return false;
    }
    return _executionStack.current.strictMode;
  }

  /// Push a function onto the call stack when entering a function
  void pushFunctionCall(JSFunction? func) {
    _functionCallStack.add(func);
  }

  /// Pop a function from the call stack when exiting a function
  void popFunctionCall() {
    if (_functionCallStack.isNotEmpty) {
      _functionCallStack.removeLast();
    }
  }

  /// Get the current caller function (second-to-last on stack)
  /// Returns null if no caller exists, or if caller is strict mode
  /// Throws TypeError if caller is a strict mode function
  JSFunction? getCurrentCaller(JSFunction callee) {
    // Find the position of the callee in the stack
    if (_functionCallStack.length < 2) {
      return null; // No caller
    }
    // The caller is at index length - 2 (second from top)
    final caller = _functionCallStack[_functionCallStack.length - 2];
    if (caller != null && caller.strictMode) {
      // Per ES5 strict mode: accessing .caller when caller is strict throws TypeError
      throw JSTypeError(
        '"caller", "callee", and "arguments" properties may not be accessed on strict mode functions or the arguments objects for calls to them',
      );
    }
    return caller;
  }

  /// Initialize all prototypes before any other setup
  /// This ensures prototypes are created in the correct Zone
  void _initializePrototypes() {
    // Create Object.prototype first (it's the root of the prototype chain)
    final objectProto = JSObject.createObjectPrototype();
    JSObject.setObjectPrototype(objectProto);

    // Note: Other prototypes will be initialized by their respective setup methods
    // (e.g., Array.prototype in _setupArrayGlobal, Function.prototype in _setupFunctionGlobal)
    // This is just to ensure Object.prototype exists first
  }

  /// Initialise l'environnement global avec les objets natifs
  void _initializeGlobalEnvironment() {
    // Clear any static state from previous interpreter instances
    ArrayPrototype.clearOriginalNatives();

    // Initialiser les symboles well-known
    JSSymbol.initializeWellKnownSymbols();

    // CRITICAL: Initialize all prototypes FIRST before any other setup
    // This ensures they are created in the correct Zone
    _initializePrototypes();

    _globalEnvironment = Environment.global();

    // Create console
    _setupConsoleObject();

    // Create Math
    _setupMathObject();

    // Create Number object
    _setupNumberObject();

    // Create Object
    _setupObjectGlobal();

    // Create Function
    _setupFunctionGlobal();

    // Create String object
    _setupStringGlobal();

    // Create Boolean object
    _setupBooleanGlobal();

    // Create Array object
    _setupArrayGlobal();

    // Create TypedArrays (ArrayBuffer, Int8Array, etc.)
    _setupTypedArraysGlobal();

    // Create RegExp object
    _setupRegExpGlobal();

    // Create Date object
    _setupDateGlobal();

    // Create BigInt object
    _setupBigIntGlobal();

    // Create Symbol object
    _setupSymbolGlobal();

    // Add global variables for tests
    _globalEnvironment.set('global_var0', JSValueFactory.number(0));

    // Create TextEncoder/TextDecoder objects
    _setupTextCodecGlobal();

    // Create JSON
    _setupJSONGlobal();

    // Create Map
    _setupMapGlobal();

    // Create Set
    _setupSetGlobal();

    // Create Promise
    _setupPromiseGlobal();

    // Configure CommonJS globals (module, exports, require)
    _setupCommonJSGlobal();

    // Create WeakMap
    _setupWeakMapGlobal();

    // Create WeakSet
    _setupWeakSetGlobal();

    // Create missing built-ins for test262
    _setupMissingBuiltins();

    // Create Proxy
    _setupProxyGlobal();

    // Create Reflect
    _setupReflectGlobal();

    // Create objets Error
    _setupErrorObjects();

    // Create Intl
    _setupIntlGlobal();

    // Create Temporal
    _setupTemporalGlobal();

    // Add global functions
    _setupGlobalFunctions();

    // Configure the executor for Function.prototype
    FunctionPrototype.setFunctionExecutor(_callJSFunction);

    // Configure the executor for JSONObject
    JSONObject.setFunctionExecutor((function, args) {
      return callFunction(function, args, JSValueFactory.undefined());
    });

    // Configure the executor for StringPrototype (ES2018: replace with callbacks)
    StringPrototype.setFunctionExecutor((function, args) {
      return callFunction(function, args, JSValueFactory.undefined());
    });

    // Create globalThis - universal reference to the global object
    // globalThis points to the global object itself
    final globalThis = JSGlobalThis(_globalEnvironment);

    // Define globalThis in environment
    _globalEnvironment.define('globalThis', globalThis, BindingType.var_);

    // Define 'globalThis' as property of globalThis
    globalThis.defineProperty(
      'globalThis',
      PropertyDescriptor(
        value: globalThis,
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );

    // Add Node.js-compatible 'global' as alias
    _globalEnvironment.define('global', globalThis, BindingType.var_);

    // Add 'global' as property of globalThis for node-like access pattern
    globalThis.defineProperty(
      'global',
      PropertyDescriptor(
        value: globalThis,
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );

    // Save the reference to use it as the default thisBinding
    _globalThisBinding = globalThis;

    // Define Promise on globalThis with proper property descriptor
    _definePromiseOnGlobalThis(globalThis);

    // Define all global constructor properties with proper descriptors
    _defineGlobalProperties(globalThis);

    // Create the global context with globalThis as thisBinding
    final globalContext = ExecutionContext.global(
      _globalEnvironment,
      globalThis: globalThis,
    );
    _executionStack.push(globalContext);
  }

  /// Methods to manage class context (private properties)
  void _pushClassContext(JSClass jsClass) {
    _classContextStack.add(jsClass);
  }

  void _popClassContext() {
    if (_classContextStack.isNotEmpty) {
      _classContextStack.removeLast();
    }
  }

  JSClass? get _currentClassContext =>
      _classContextStack.isNotEmpty ? _classContextStack.last : null;

  bool _isInClassContext(JSClass jsClass) {
    return _classContextStack.contains(jsClass);
  }

  /// Configures the global console object
  void _setupConsoleObject() {
    // Create console
    final consoleObj = ConsoleObject.createConsoleObject();

    // Add it to the global environment
    _globalEnvironment.define('console', consoleObj, BindingType.var_);
  }

  /// Configures the global Math object
  void _setupMathObject() {
    // Create Math
    final mathObj = MathObject.createMathObject();

    // Add it to the global environment
    _globalEnvironment.define('Math', mathObj, BindingType.var_);
  }

  /// Configures the global Number object
  void _setupNumberObject() {
    // Create the Number constructor function
    final numberConstructor = JSNativeFunction(
      functionName: 'Number',
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSValueFactory.number(0.0);
        }
        return JSValueFactory.number(args[0].toNumber());
      },
      expectedArgs: 1,
      isConstructor: true, // Number is a constructor
    );

    // Static properties of Number (non-writable, non-enumerable, non-configurable)
    numberConstructor.defineProperty(
      'MAX_VALUE',
      PropertyDescriptor(
        value: JSValueFactory.number(double.maxFinite),
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    numberConstructor.defineProperty(
      'MIN_VALUE',
      PropertyDescriptor(
        value: JSValueFactory.number(5e-324),
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    numberConstructor.defineProperty(
      'POSITIVE_INFINITY',
      PropertyDescriptor(
        value: JSValueFactory.number(double.infinity),
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    numberConstructor.defineProperty(
      'NEGATIVE_INFINITY',
      PropertyDescriptor(
        value: JSValueFactory.number(double.negativeInfinity),
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    numberConstructor.defineProperty(
      'NaN',
      PropertyDescriptor(
        value: JSValueFactory.number(double.nan),
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    numberConstructor.defineProperty(
      'MAX_SAFE_INTEGER',
      PropertyDescriptor(
        value: JSValueFactory.number(9007199254740991),
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    numberConstructor.defineProperty(
      'MIN_SAFE_INTEGER',
      PropertyDescriptor(
        value: JSValueFactory.number(-9007199254740991),
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    numberConstructor.defineProperty(
      'EPSILON',
      PropertyDescriptor(
        value: JSValueFactory.number(2.220446049250313e-16),
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );

    // Static methods of Number
    numberConstructor.setProperty(
      'isNaN',
      JSNativeFunction(
        functionName: 'isNaN',
        nativeImpl: (args) {
          if (args.isEmpty) return JSValueFactory.boolean(false);
          final value = args[0];
          if (value.type != JSValueType.number) {
            return JSValueFactory.boolean(false);
          }
          return JSValueFactory.boolean((value as JSNumber).value.isNaN);
        },
      ),
    );

    numberConstructor.setProperty(
      'isFinite',
      JSNativeFunction(
        functionName: 'isFinite',
        nativeImpl: (args) {
          if (args.isEmpty) return JSValueFactory.boolean(false);
          final value = args[0];
          if (value.type != JSValueType.number) {
            return JSValueFactory.boolean(false);
          }
          final num = (value as JSNumber).value;
          return JSValueFactory.boolean(num.isFinite);
        },
      ),
    );

    numberConstructor.setProperty(
      'parseFloat',
      JSNativeFunction(
        functionName: 'parseFloat',
        nativeImpl: (args) {
          if (args.isEmpty) return JSValueFactory.number(double.nan);
          final str = args[0].toString();
          final result = double.tryParse(str);
          return JSValueFactory.number(result ?? double.nan);
        },
      ),
    );

    numberConstructor.setProperty(
      'parseInt',
      JSNativeFunction(
        functionName: 'parseInt',
        nativeImpl: (args) {
          if (args.isEmpty) return JSValueFactory.number(double.nan);

          String str = args[0].toString().trim();
          if (str.isEmpty) return JSValueFactory.number(double.nan);

          // Determiner la base (radix)
          int radix = 10;
          if (args.length > 1) {
            final radixArg = args[1].toNumber();
            if (radixArg.isNaN) return JSValueFactory.number(double.nan);
            radix = radixArg.toInt();

            // Validation de la base selon la spec JavaScript
            if (radix != 0 && (radix < 2 || radix > 36)) {
              return JSValueFactory.number(double.nan);
            }
          }

          // Auto-detection of radix if radix = 0 or not specified
          if (radix == 0 || (args.length == 1)) {
            if (str.toLowerCase().startsWith('0x')) {
              radix = 16;
              str = str.substring(2);
            } else if (str.startsWith('0') && str.length > 1) {
              // Note: octal auto-detection est deprecated en strict mode
              // but we implement it for compatibility
              radix = 8;
              str = str.substring(1);
            } else {
              radix = 10;
            }
          } else if (radix == 16 && str.toLowerCase().startsWith('0x')) {
            str = str.substring(2);
          }

          // Parser le nombre avec la base specifiee
          if (str.isEmpty) return JSValueFactory.number(double.nan);

          // Trouver la partie valide de la string
          String validPart = '';
          bool negative = false;
          int i = 0;

          // Handle the sign
          if (str[0] == '-') {
            negative = true;
            i = 1;
          } else if (str[0] == '+') {
            i = 1;
          }

          // Extract valid characters for the given radix
          for (; i < str.length; i++) {
            final char = str[i].toLowerCase();
            int digitValue;

            if (char.codeUnitAt(0) >= '0'.codeUnitAt(0) &&
                char.codeUnitAt(0) <= '9'.codeUnitAt(0)) {
              digitValue = char.codeUnitAt(0) - '0'.codeUnitAt(0);
            } else if (char.codeUnitAt(0) >= 'a'.codeUnitAt(0) &&
                char.codeUnitAt(0) <= 'z'.codeUnitAt(0)) {
              digitValue = char.codeUnitAt(0) - 'a'.codeUnitAt(0) + 10;
            } else {
              break; // Caractere invalide, on s'arrete ici
            }

            if (digitValue >= radix) {
              break; // Digit too large for this radix
            }

            validPart += str[i];
          }

          if (validPart.isEmpty) return JSValueFactory.number(double.nan);

          // Parser avec la base specifiee
          try {
            final result = int.parse(validPart, radix: radix);
            return JSValueFactory.number(
              (negative ? -result : result).toDouble(),
            );
          } catch (e) {
            return JSValueFactory.number(double.nan);
          }
        },
      ),
    );

    numberConstructor.setProperty(
      'isInteger',
      JSNativeFunction(
        functionName: 'isInteger',
        nativeImpl: (args) {
          if (args.isEmpty) return JSValueFactory.boolean(false);
          final value = args[0];
          if (value.type != JSValueType.number) {
            return JSValueFactory.boolean(false);
          }
          final num = (value as JSNumber).value;
          if (!num.isFinite) return JSValueFactory.boolean(false);
          return JSValueFactory.boolean(num == num.toInt());
        },
      ),
    );

    numberConstructor.setProperty(
      'isSafeInteger',
      JSNativeFunction(
        functionName: 'isSafeInteger',
        nativeImpl: (args) {
          if (args.isEmpty) return JSValueFactory.boolean(false);
          final value = args[0];
          if (value.type != JSValueType.number) {
            return JSValueFactory.boolean(false);
          }
          final num = (value as JSNumber).value;
          if (!num.isFinite) return JSValueFactory.boolean(false);
          if (num != num.toInt()) return JSValueFactory.boolean(false);
          const maxSafe = 9007199254740991; // 2^53 - 1
          const minSafe = -9007199254740991; // -(2^53 - 1)
          return JSValueFactory.boolean(num >= minSafe && num <= maxSafe);
        },
      ),
    );

    // Create the Number prototype
    final numberPrototype = JSObject();
    numberConstructor.setProperty('prototype', numberPrototype);

    // IMPORTANT: Add the constructor property to Number.prototype
    numberPrototype.setProperty('constructor', numberConstructor);

    // Add Number.prototype methods
    numberPrototype.setProperty(
      'toString',
      JSNativeFunction(
        functionName: 'toString',
        nativeImpl: (args) {
          // args[0] is 'this' when called with call/apply
          final thisValue = args.isNotEmpty
              ? args[0]
              : JSValueFactory.number(0);
          final radix = args.length > 1 ? args[1].toNumber().floor() : 10;

          if (thisValue is JSNumberObject) {
            final numValue = thisValue.primitiveValue;
            if (radix == 10) {
              return JSValueFactory.string(numValue.toString());
            } else if (radix >= 2 && radix <= 36) {
              final intVal = numValue.floor();
              return JSValueFactory.string(intVal.toRadixString(radix));
            }
            throw JSRangeError('toString radix must be between 2 and 36');
          } else if (thisValue.isNumber) {
            final numValue = thisValue.primitiveValue as double;
            if (radix == 10) {
              return JSValueFactory.string(numValue.toString());
            } else if (radix >= 2 && radix <= 36) {
              final intVal = numValue.floor();
              return JSValueFactory.string(intVal.toRadixString(radix));
            }
            throw JSRangeError('toString radix must be between 2 and 36');
          }
          throw JSTypeError('Number.prototype.toString called on non-number');
        },
      ),
    );

    numberPrototype.setProperty(
      'valueOf',
      JSNativeFunction(
        functionName: 'valueOf',
        nativeImpl: (args) {
          // args[0] is 'this' when called with call/apply
          final thisValue = args.isNotEmpty
              ? args[0]
              : JSValueFactory.number(0);
          if (thisValue is JSNumberObject) {
            return JSValueFactory.number(thisValue.primitiveValue);
          } else if (thisValue.isNumber) {
            return thisValue; // Already a number primitive
          }
          throw JSTypeError('Number.prototype.valueOf called on non-number');
        },
      ),
    );

    // Mark this as a wrapper prototype for [[Class]] detection
    numberPrototype.setInternalSlot('__internalClass__', 'Number');

    // Set the static Number prototype so all JSNumberObject instances inherit from it
    JSNumberObject.setNumberPrototype(numberPrototype);

    // Add it to the global environment
    _globalEnvironment.define('Number', numberConstructor, BindingType.var_);
  }

  /// Configures the global Object object
  void _setupObjectGlobal() {
    // Create Object
    final objectGlobal = ObjectGlobal.createObjectGlobal();

    // Add it to the global environment
    _globalEnvironment.define('Object', objectGlobal, BindingType.var_);
  }

  /// Configures the global Function object
  void _setupFunctionGlobal() {
    // Create Function
    final functionGlobal = FunctionGlobal.createFunctionGlobal();

    // Add it to the global environment
    _globalEnvironment.define('Function', functionGlobal, BindingType.var_);
  }

  /// Configures the global String object
  void _setupStringGlobal() {
    // Create the String constructor function
    final stringConstructor = JSNativeFunction(
      functionName: 'String',
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSValueFactory.string('');
        }
        final arg = args[0];
        // Use JSConversion.jsToString to handle ToPrimitive properly
        final strValue = JSConversion.jsToString(arg);
        return JSValueFactory.string(strValue);
      },
      expectedArgs: 1,
      isConstructor: true, // String is a constructor
    );

    // ES6: String.fromCodePoint(...codePoints)
    // Creates a string from one or more Unicode code points
    stringConstructor.setProperty(
      'fromCodePoint',
      JSNativeFunction(
        functionName: 'fromCodePoint',
        nativeImpl: (args) {
          final buffer = StringBuffer();

          for (final arg in args) {
            final codePoint = arg.toNumber().floor();

            // Validate code point range
            if (codePoint < 0 || codePoint > 0x10FFFF) {
              throw JSRangeError('Invalid code point $codePoint');
            }

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

          return JSValueFactory.string(buffer.toString());
        },
      ),
    );

    // ES6: String.raw(template, ...substitutions)
    // Returns raw string content of template literal
    stringConstructor.setProperty(
      'raw',
      JSNativeFunction(
        functionName: 'raw',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSTypeError('String.raw requires at least 1 argument');
          }

          final template = args[0];
          if (template is! JSObject) {
            throw JSTypeError('String.raw called on non-object');
          }

          final rawProp = template.getProperty('raw');
          if (rawProp is! JSArray) {
            throw JSTypeError('String.raw: template.raw must be array-like');
          }

          final buffer = StringBuffer();
          final substitutions = args.sublist(1);

          for (int i = 0; i < rawProp.length; i++) {
            buffer.write(rawProp.get(i).toString());
            if (i < substitutions.length) {
              buffer.write(substitutions[i].toString());
            }
          }

          return JSValueFactory.string(buffer.toString());
        },
      ),
    );

    // ES3: String.fromCharCode(...charCodes)
    // Creates a string from one or more UTF-16 code units
    stringConstructor.setProperty(
      'fromCharCode',
      JSNativeFunction(
        functionName: 'fromCharCode',
        nativeImpl: (args) {
          final buffer = StringBuffer();

          for (final arg in args) {
            final charCode = arg.toNumber().floor();
            // Convert to int and mask to 16 bits (UTF-16 code unit)
            final codeUnit = charCode.toInt() & 0xFFFF;
            buffer.writeCharCode(codeUnit);
          }

          return JSValueFactory.string(buffer.toString());
        },
      ),
    );

    // Create the String prototype
    final stringPrototype = JSObject();
    stringConstructor.setProperty('prototype', stringPrototype);

    // IMPORTANT: Add the constructor property to String.prototype
    stringPrototype.setProperty('constructor', stringConstructor);

    // Add String.prototype methods
    stringPrototype.setProperty(
      'toString',
      JSNativeFunction(
        functionName: 'toString',
        nativeImpl: (args) {
          // args[0] is 'this' when called with call/apply
          final thisValue = args.isNotEmpty
              ? args[0]
              : JSValueFactory.string('');
          if (thisValue is JSStringObject) {
            return JSValueFactory.string(thisValue.value);
          } else if (thisValue.isString) {
            return thisValue; // Already a string primitive
          }
          throw JSTypeError('String.prototype.toString called on non-string');
        },
      ),
    );

    stringPrototype.setProperty(
      'valueOf',
      JSNativeFunction(
        functionName: 'valueOf',
        nativeImpl: (args) {
          // args[0] is 'this' when called with call/apply
          final thisValue = args.isNotEmpty
              ? args[0]
              : JSValueFactory.string('');
          if (thisValue is JSStringObject) {
            return JSValueFactory.string(thisValue.value);
          } else if (thisValue.isString) {
            return thisValue; // Already a string primitive
          }
          throw JSTypeError('String.prototype.valueOf called on non-string');
        },
      ),
    );

    // Mark this as a wrapper prototype for [[Class]] detection
    stringPrototype.setInternalSlot('__internalClass__', 'String');

    // ES6: String.prototype[Symbol.iterator] - create string iterator
    stringPrototype.setProperty(
      JSSymbol.iterator.toString(),
      JSNativeFunction(
        functionName: 'Symbol.iterator',
        nativeImpl: (args) {
          // 'this' is the string value - get it from the first argument if it's a function call
          // For property access, we need to capture the string from context
          // This will be called via: someString[Symbol.iterator]()
          final evaluator = JSEvaluator.currentInstance;
          if (evaluator == null) {
            throw JSError('No evaluator available for String iterator');
          }

          // The string value is accessible from context
          // When called as a method, 'args[0]' will be the string if bound properly
          final stringValue = args.isNotEmpty && args[0] is JSString
              ? (args[0] as JSString).value
              : '';

          // Create iterator object with next() method
          final iterator = JSObject();
          var index = 0;

          iterator.setProperty(
            'next',
            JSNativeFunction(
              functionName: 'next',
              nativeImpl: (nextArgs) {
                if (index >= stringValue.length) {
                  // Return {done: true, value: undefined}
                  final result = JSObject();
                  result.setProperty('done', JSValueFactory.boolean(true));
                  result.setProperty('value', JSValueFactory.undefined());
                  return result;
                }

                // Return {done: false, value: currentChar}
                final result = JSObject();
                result.setProperty('done', JSValueFactory.boolean(false));
                result.setProperty(
                  'value',
                  JSValueFactory.string(stringValue[index]),
                );
                index++;
                return result;
              },
            ),
          );

          // Make the iterator itself iterable (return this for Symbol.iterator)
          iterator.setProperty(
            JSSymbol.iterator.toString(),
            JSNativeFunction(
              functionName: 'Symbol.iterator',
              nativeImpl: (iteratorArgs) => iterator,
            ),
          );

          return iterator;
        },
      ),
    );

    // Set the static String prototype so all JSStringObject instances inherit from it
    JSStringObject.setStringPrototype(stringPrototype);

    // Add it to the global environment
    _globalEnvironment.define('String', stringConstructor, BindingType.var_);
  }

  /// Configures the global Boolean object
  void _setupBooleanGlobal() {
    // Create the Boolean constructor function
    final booleanConstructor = JSNativeFunction(
      functionName: 'Boolean',
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSValueFactory.boolean(false);
        }
        final value = args[0];
        // When called as a function (not constructor), convert to boolean
        // For objects, this should always be true
        if (value is JSObject) {
          return JSValueFactory.boolean(true);
        }
        // For primitives, use the normal toBoolean logic
        return JSValueFactory.boolean(value.toBoolean());
      },
      expectedArgs: 1,
      isConstructor: true, // Boolean is a constructor
    );

    // Create the Boolean prototype - must be a JSBooleanObject with value false
    // so that Boolean.prototype == false returns true (coercion)
    final booleanPrototype = JSBooleanObject(false);

    // Set the prototype of Boolean.prototype to Object.prototype
    booleanPrototype.setPrototype(JSObject.objectPrototype);

    // Set Boolean.prototype with proper property descriptor
    // (non-writable, non-configurable)
    booleanConstructor.defineProperty(
      'prototype',
      PropertyDescriptor(
        value: booleanPrototype,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );

    // IMPORTANT: Add the constructor property to Boolean.prototype
    booleanPrototype.defineProperty(
      'constructor',
      PropertyDescriptor(
        value: booleanConstructor,
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );

    // Add Boolean.prototype methods (with configurable=true so they can be deleted)
    booleanPrototype.defineProperty(
      'toString',
      PropertyDescriptor(
        value: JSNativeFunction(
          functionName: 'toString',
          nativeImpl: (args) {
            // args[0] is 'this' when called with call/apply
            final thisValue = args.isNotEmpty
                ? args[0]
                : JSValueFactory.boolean(false);
            if (thisValue is JSBooleanObject) {
              return JSValueFactory.string(thisValue.primitiveValue.toString());
            } else if (thisValue.isBoolean) {
              return JSValueFactory.string(thisValue.primitiveValue.toString());
            }
            throw JSTypeError(
              'Boolean.prototype.toString called on non-boolean',
            );
          },
        ),
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );

    booleanPrototype.defineProperty(
      'valueOf',
      PropertyDescriptor(
        value: JSNativeFunction(
          functionName: 'valueOf',
          nativeImpl: (args) {
            // args[0] is 'this' when called with call/apply
            final thisValue = args.isNotEmpty
                ? args[0]
                : JSValueFactory.boolean(false);
            if (thisValue is JSBooleanObject) {
              return JSValueFactory.boolean(thisValue.primitiveValue);
            } else if (thisValue.isBoolean) {
              return thisValue; // Already a boolean primitive
            }
            throw JSTypeError(
              'Boolean.prototype.valueOf called on non-boolean',
            );
          },
        ),
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );

    // Mark this as a wrapper prototype for [[Class]] detection
    booleanPrototype.setInternalSlot('__internalClass__', 'Boolean');

    // Set the static Boolean prototype so all JSBooleanObject instances inherit from it
    JSBooleanObject.setBooleanPrototype(booleanPrototype);

    // Add it to the global environment
    _globalEnvironment.define('Boolean', booleanConstructor, BindingType.var_);
  }

  /// Configures the global Array object
  void _setupArrayGlobal() {
    // Create Array.prototype first
    final arrayPrototype = JSValueFactory.array([]);

    // Set Array.prototype's prototype to Object.prototype
    arrayPrototype.setPrototype(JSObject.objectPrototype);

    // Set the global Array.prototype reference so all arrays can inherit from it
    JSArray.setArrayPrototype(arrayPrototype);

    // Create the Array constructor function
    final arrayConstructor = JSNativeFunction(
      functionName: 'Array',
      nativeImpl: (args) {
        JSArray arr;
        if (args.isEmpty) {
          arr = JSValueFactory.array([]);
        } else if (args.length == 1 && args[0].isNumber) {
          // If a single numeric argument, create an array of that size
          final numValue = args[0].toNumber();

          // ES6: If ToUint32(len) !== ToNumber(len), throw RangeError
          // This catches: NaN, Infinity, negative numbers, non-integers (1.5)
          if (numValue.isNaN ||
              numValue.isInfinite ||
              numValue < 0 ||
              numValue > 4294967295 ||
              numValue != numValue.truncateToDouble()) {
            throw JSRangeError('Invalid array length');
          }

          final length = numValue.toInt();

          // For large sizes, create an empty array and just set length
          // Sparse storage will handle large indices
          arr = JSValueFactory.array([]);
          arr.setProperty('length', JSValueFactory.number(length));
        } else {
          // Otherwise, use the arguments as elements
          arr = JSValueFactory.array(args);
        }

        // Set the prototype explicitly to ensure it's correct
        // This is necessary for both new Array() and Array() calls
        arr.setPrototype(arrayPrototype);

        return arr;
      },
      expectedArgs: 1, // Array constructor expects 1 argument (arrayLength)
      isConstructor: true, // Array is a constructor
    );

    // Set up Array.prototype property on constructor
    arrayConstructor.setProperty('prototype', arrayPrototype);

    // Add static properties to Array
    // Array.isArray - ES5.1: writable: true, enumerable: false, configurable: true
    final isArrayFunc = JSNativeFunction(
      functionName: 'isArray',
      nativeImpl: (args) {
        if (args.isEmpty) return JSValueFactory.boolean(false);
        return JSValueFactory.boolean(args[0] is JSArray);
      },
      expectedArgs: 1,
    );
    arrayConstructor.setProperty('isArray', isArrayFunc);
    arrayConstructor.defineProperty(
      'isArray',
      PropertyDescriptor(
        value: isArrayFunc,
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );

    // Array.from(arrayLike[, mapFn[, thisArg]]) - ES6
    // Supports: Array.from(items, mapFn, thisArg)
    //          Array.from.call(CustomConstructor, items, mapFn, thisArg)

    // Create a special wrapper class that properly handles .call() semantics
    final arrayFromFunction = _ArrayFromFunction();

    arrayConstructor.setProperty('from', arrayFromFunction);
    arrayConstructor.defineProperty(
      'from',
      PropertyDescriptor(
        value: arrayFromFunction,
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );

    // Array.of(...elements) - ES6: writable: true, enumerable: false, configurable: true
    // Per ES6 spec: should use the this value as constructor if it's callable
    final ofFunc = JSNativeFunction(
      functionName: 'of',
      nativeImpl: (args) {
        // Determine 'this' and items
        // When called as Array.of(1, 2, 3): this is Array constructor, items are [1,2,3]
        // When called as Array.of.call(C, 1, 2): this is C, items are [1,2]

        JSValue thisValue = JSValueFactory.undefined();
        List<JSValue> items = args;

        // First arg is 'this' when called as a method
        if (args.isNotEmpty) {
          thisValue = args[0];

          // Check if this is a normal Array.of() call (this = Array constructor)
          // vs Array.of.call(CustomConstructor, items...)
          if (thisValue == arrayConstructor) {
            // Normal call: Array.of(items...)
            items = args.sublist(1);
            thisValue = arrayConstructor;
          } else if (thisValue.isFunction) {
            // Called via .call(Constructor, items...)
            items = args.sublist(1);
          } else {
            // First arg is not a constructor, treat all as items
            items = args;
            thisValue = arrayConstructor;
          }
        }

        final len = items.length;
        JSValue result;

        // Check if thisValue is a constructor
        bool useConstructor = false;
        if (thisValue is JSFunction) {
          useConstructor = thisValue.isConstructor;
        } else if (thisValue is JSNativeFunction) {
          useConstructor = thisValue.isConstructor;
        }

        if (useConstructor && thisValue != arrayConstructor) {
          // Call the custom constructor with length as argument
          final newObj = JSObject();

          // Set prototype from the constructor's prototype property
          JSValue prototypeValue = JSValueFactory.undefined();
          if (thisValue is JSFunction) {
            prototypeValue = thisValue.getProperty('prototype');
          } else if (thisValue is JSNativeFunction) {
            prototypeValue = thisValue.getProperty('prototype');
          }

          if (prototypeValue is JSObject) {
            newObj.setPrototype(prototypeValue);
          }

          // Call constructor with length argument and newObj as this
          callFunction(thisValue, [
            JSValueFactory.number(len.toDouble()),
          ], newObj);

          result = newObj;

          // Set the items in the result object using indexed properties
          if (result is JSObject) {
            for (int i = 0; i < items.length; i++) {
              result.setProperty(i.toString(), items[i]);
            }
            result.setProperty('length', JSValueFactory.number(len.toDouble()));
          }
        } else {
          // Default: create a normal JSArray with items
          result = JSValueFactory.array(items);
        }

        return result;
      },
      expectedArgs: 0,
    );
    arrayConstructor.setProperty('of', ofFunc);
    arrayConstructor.defineProperty(
      'of',
      PropertyDescriptor(
        value: ofFunc,
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );

    // Array[@@species] getter - ES6: get: function, set: undefined, enumerable: false, configurable: true
    // Returns the this value (the Array constructor or subclass)
    final speciesGetter = JSNativeFunction(
      functionName: 'get [Symbol.species]',
      nativeImpl: (args) {
        // For getters, the first argument is the thisBinding (prepended by callWithThis)
        return args.isNotEmpty ? args[0] : JSValueFactory.undefined();
      },
      expectedArgs: 0,
    );

    final speciesKey = JSSymbol.species.toString();
    arrayConstructor.defineProperty(
      speciesKey,
      PropertyDescriptor(
        getter: speciesGetter,
        setter: null,
        enumerable: false,
        configurable: true,
        hasValueProperty: false,
      ),
    );

    // IMPORTANT: Add the constructor property to Array.prototype
    // Note: Non-enumerable comme en JavaScript standard
    arrayPrototype.defineProperty(
      'constructor',
      PropertyDescriptor(
        value: arrayConstructor,
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );

    // Set up Array.prototype methods
    _setupArrayPrototype(arrayPrototype);

    // Add it to the global environment
    _globalEnvironment.define('Array', arrayConstructor, BindingType.var_);
  }

  /// Helper to define a non-enumerable property on an object
  /// Used for native methods on prototypes
  void _defineNonEnumerableProperty(JSObject obj, String name, JSValue value) {
    obj.defineProperty(
      name,
      PropertyDescriptor(
        value: value,
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );
  }

  /// Configure Array.prototype with all methods
  void _setupArrayPrototype(JSArray arrayPrototype) {
    // Array.prototype.length (propriete speciale geree par JSArray)

    // Array.prototype.push
    _defineNonEnumerableProperty(
      arrayPrototype,
      'push',
      JSNativeFunction(
        functionName: 'push',
        expectedArgs: 1,
        nativeImpl: (args) => ArrayPrototype.push(args, arrayPrototype),
      ),
    );

    // Array.prototype.pop
    _defineNonEnumerableProperty(
      arrayPrototype,
      'pop',
      JSNativeFunction(
        functionName: 'pop',
        expectedArgs: 0,
        nativeImpl: (args) => ArrayPrototype.pop(args, arrayPrototype),
      ),
    );

    // Array.prototype.shift
    _defineNonEnumerableProperty(
      arrayPrototype,
      'shift',
      JSNativeFunction(
        functionName: 'shift',
        expectedArgs: 0,
        nativeImpl: (args) => ArrayPrototype.shift(args, arrayPrototype),
      ),
    );

    // Array.prototype.unshift
    _defineNonEnumerableProperty(
      arrayPrototype,
      'unshift',
      JSNativeFunction(
        functionName: 'unshift',
        expectedArgs: 1,
        nativeImpl: (args) => ArrayPrototype.unshift(args, arrayPrototype),
      ),
    );

    // Array.prototype.slice
    _defineNonEnumerableProperty(
      arrayPrototype,
      'slice',
      JSNativeFunction(
        functionName: 'slice',
        nativeImpl: (args) => ArrayPrototype.slice(args, arrayPrototype),
      ),
    );

    // Array.prototype.splice
    _defineNonEnumerableProperty(
      arrayPrototype,
      'splice',
      JSNativeFunction(
        functionName: 'splice',
        nativeImpl: (args) => ArrayPrototype.splice(args, arrayPrototype),
      ),
    );

    // Array.prototype.join - needs to work with .call() passing thisArg
    _defineNonEnumerableProperty(
      arrayPrototype,
      'join',
      JSNativeFunction(
        functionName: 'join',
        nativeImpl: (args) {
          // When called via .call(thisArg, separator), thisArg is prepended
          if (args.isNotEmpty && args[0] is JSArray) {
            final arr = args[0] as JSArray;
            final restArgs = args.length > 1 ? args.sublist(1) : <JSValue>[];
            return ArrayPrototype.join(restArgs, arr);
          }
          // Fallback to empty array behavior
          return JSValueFactory.string('');
        },
      ),
    );

    // Array.prototype.toString - needs to work with .call() passing thisArg
    // ES spec: If this doesn't have a callable join method, use Object.prototype.toString
    _defineNonEnumerableProperty(
      arrayPrototype,
      'toString',
      JSNativeFunction(
        functionName: 'toString',
        nativeImpl: (args) {
          // Pass args to toString_ which handles both arrays and non-arrays
          return ArrayPrototype.toString_(args);
        },
      ),
    );

    // Array.prototype.concat
    _defineNonEnumerableProperty(
      arrayPrototype,
      'concat',
      JSNativeFunction(
        functionName: 'concat',
        nativeImpl: (args) => ArrayPrototype.concat(args, arrayPrototype),
      ),
    );

    // Array.prototype.indexOf
    _defineNonEnumerableProperty(
      arrayPrototype,
      'indexOf',
      JSNativeFunction(
        functionName: 'indexOf',
        nativeImpl: (args) => ArrayPrototype.indexOf(args, arrayPrototype),
        expectedArgs: 1, // searchElement is required
      ),
    );

    // Array.prototype.lastIndexOf
    _defineNonEnumerableProperty(
      arrayPrototype,
      'lastIndexOf',
      JSNativeFunction(
        functionName: 'lastIndexOf',
        nativeImpl: (args) => ArrayPrototype.lastIndexOf(args, arrayPrototype),
        expectedArgs: 1, // searchElement is required
      ),
    );

    // Array.prototype.includes
    _defineNonEnumerableProperty(
      arrayPrototype,
      'includes',
      JSNativeFunction(
        functionName: 'includes',
        nativeImpl: (args) => ArrayPrototype.includes(args),
        expectedArgs: 1, // searchElement is required
      ),
    );

    // Array.prototype.reverse
    _defineNonEnumerableProperty(
      arrayPrototype,
      'reverse',
      JSNativeFunction(
        functionName: 'reverse',
        nativeImpl: (args) => ArrayPrototype.reverse(args),
        expectedArgs: 0, // No required parameters
      ),
    );

    // Array.prototype.sort
    _defineNonEnumerableProperty(
      arrayPrototype,
      'sort',
      JSNativeFunction(
        functionName: 'sort',
        nativeImpl: (args) => ArrayPrototype.sort(args, arrayPrototype),
      ),
    );

    // Array.prototype.forEach
    _defineNonEnumerableProperty(
      arrayPrototype,
      'forEach',
      JSNativeFunction(
        functionName: 'forEach',
        expectedArgs: 1,
        nativeImpl: (args) => ArrayPrototype.forEach(args),
      ),
    );

    // Array.prototype.map
    _defineNonEnumerableProperty(
      arrayPrototype,
      'map',
      JSNativeFunction(
        functionName: 'map',
        expectedArgs: 1,
        nativeImpl: (args) => ArrayPrototype.map(args, arrayPrototype),
      ),
    );

    // Array.prototype.filter
    _defineNonEnumerableProperty(
      arrayPrototype,
      'filter',
      JSNativeFunction(
        functionName: 'filter',
        expectedArgs: 1,
        nativeImpl: (args) => ArrayPrototype.filter(args, arrayPrototype),
      ),
    );

    // Array.prototype.find
    _defineNonEnumerableProperty(
      arrayPrototype,
      'find',
      JSNativeFunction(
        functionName: 'find',
        expectedArgs: 1,
        nativeImpl: (args) => ArrayPrototype.find(args, arrayPrototype),
      ),
    );

    // Array.prototype.findIndex
    _defineNonEnumerableProperty(
      arrayPrototype,
      'findIndex',
      JSNativeFunction(
        functionName: 'findIndex',
        expectedArgs: 1,
        nativeImpl: (args) => ArrayPrototype.findIndex(args, arrayPrototype),
      ),
    );

    // Array.prototype.findLast
    _defineNonEnumerableProperty(
      arrayPrototype,
      'findLast',
      JSNativeFunction(
        functionName: 'findLast',
        expectedArgs: 1,
        nativeImpl: (args) => ArrayPrototype.findLast(args, arrayPrototype),
      ),
    );

    // Array.prototype.findLastIndex
    _defineNonEnumerableProperty(
      arrayPrototype,
      'findLastIndex',
      JSNativeFunction(
        functionName: 'findLastIndex',
        expectedArgs: 1,
        nativeImpl: (args) =>
            ArrayPrototype.findLastIndex(args, arrayPrototype),
      ),
    );

    // Array.prototype.every
    _defineNonEnumerableProperty(
      arrayPrototype,
      'every',
      JSNativeFunction(
        functionName: 'every',
        expectedArgs: 1,
        nativeImpl: (args) => ArrayPrototype.every(args, arrayPrototype),
      ),
    );

    // Array.prototype.some
    _defineNonEnumerableProperty(
      arrayPrototype,
      'some',
      JSNativeFunction(
        functionName: 'some',
        expectedArgs: 1,
        nativeImpl: (args) => ArrayPrototype.some(args, arrayPrototype),
      ),
    );

    // Array.prototype.reduce
    _defineNonEnumerableProperty(
      arrayPrototype,
      'reduce',
      JSNativeFunction(
        functionName: 'reduce',
        expectedArgs: 1,
        nativeImpl: (args) => ArrayPrototype.reduce(args, arrayPrototype),
      ),
    );

    // Array.prototype.reduceRight
    _defineNonEnumerableProperty(
      arrayPrototype,
      'reduceRight',
      JSNativeFunction(
        functionName: 'reduceRight',
        expectedArgs: 1,
        nativeImpl: (args) => ArrayPrototype.reduceRight(args, arrayPrototype),
      ),
    );

    // Array.prototype.fill
    _defineNonEnumerableProperty(
      arrayPrototype,
      'fill',
      JSNativeFunction(
        functionName: 'fill',
        nativeImpl: (args) => ArrayPrototype.fill(args),
        expectedArgs: 1, // value is required
      ),
    );

    // Array.prototype.copyWithin
    _defineNonEnumerableProperty(
      arrayPrototype,
      'copyWithin',
      JSNativeFunction(
        functionName: 'copyWithin',
        nativeImpl: (args) => ArrayPrototype.copyWithin(args),
        expectedArgs: 2, // target and start are required
      ),
    );

    // Array.prototype.flat
    _defineNonEnumerableProperty(
      arrayPrototype,
      'flat',
      JSNativeFunction(
        functionName: 'flat',
        nativeImpl: (args) => ArrayPrototype.flat(args),
      ),
    );

    // Array.prototype.flatMap
    _defineNonEnumerableProperty(
      arrayPrototype,
      'flatMap',
      JSNativeFunction(
        functionName: 'flatMap',
        expectedArgs: 1,
        nativeImpl: (args) => ArrayPrototype.flatMap(args, arrayPrototype),
      ),
    );

    // Array iterator methods
    // Note: Symbol properties cannot use defineProperty with PropertyDescriptor
    // We handle them separately to maintain symbol reference
    arrayPrototype.setPropertyWithSymbol(
      JSSymbol.iterator.toString(),
      JSNativeFunction(
        functionName: 'Symbol.iterator',
        nativeImpl: (args) => ArrayPrototype.values(args, arrayPrototype),
      ),
      JSSymbol.iterator,
    );

    _defineNonEnumerableProperty(
      arrayPrototype,
      'keys',
      JSNativeFunction(
        functionName: 'keys',
        nativeImpl: (args) => ArrayPrototype.keys(args, arrayPrototype),
      ),
    );

    _defineNonEnumerableProperty(
      arrayPrototype,
      'values',
      JSNativeFunction(
        functionName: 'values',
        nativeImpl: (args) => ArrayPrototype.values(args, arrayPrototype),
      ),
    );

    // Array.prototype.at (ES2022)
    _defineNonEnumerableProperty(
      arrayPrototype,
      'at',
      JSNativeFunction(
        functionName: 'at',
        expectedArgs: 1,
        nativeImpl: (args) => ArrayPrototype.at(args, arrayPrototype),
      ),
    );

    _defineNonEnumerableProperty(
      arrayPrototype,
      'entries',
      JSNativeFunction(
        functionName: 'entries',
        nativeImpl: (args) => ArrayPrototype.entries(args, arrayPrototype),
      ),
    );

    // Array.prototype[Symbol.unscopables] (ES6)
    // Contains methods that should be excluded from with statement bindings
    final unscopablesObj = JSObject();
    unscopablesObj.setProperty('at', JSValueFactory.boolean(true));
    unscopablesObj.setProperty('copyWithin', JSValueFactory.boolean(true));
    unscopablesObj.setProperty('entries', JSValueFactory.boolean(true));
    unscopablesObj.setProperty('fill', JSValueFactory.boolean(true));
    unscopablesObj.setProperty('find', JSValueFactory.boolean(true));
    unscopablesObj.setProperty('findIndex', JSValueFactory.boolean(true));
    unscopablesObj.setProperty('findLast', JSValueFactory.boolean(true));
    unscopablesObj.setProperty('findLastIndex', JSValueFactory.boolean(true));
    unscopablesObj.setProperty('flat', JSValueFactory.boolean(true));
    unscopablesObj.setProperty('flatMap', JSValueFactory.boolean(true));
    unscopablesObj.setProperty('includes', JSValueFactory.boolean(true));
    unscopablesObj.setProperty('keys', JSValueFactory.boolean(true));
    unscopablesObj.setProperty('values', JSValueFactory.boolean(true));

    // Define Symbol.unscopables with specific attributes
    arrayPrototype.defineProperty(
      JSSymbol.unscopables.toString(),
      PropertyDescriptor(
        value: unscopablesObj,
        writable: false,
        enumerable: false,
        configurable: true,
      ),
    );

    // Register all original native functions for override detection
    // This allows getArrayProperty to detect when methods like toString have been replaced
    final symbolIteratorKey = JSSymbol.iterator.toString();
    final nativeMethodNames = [
      'join',
      'toString',
      'concat',
      'indexOf',
      'lastIndexOf',
      'includes',
      'reverse',
      'sort',
      'forEach',
      'map',
      'filter',
      'find',
      'findIndex',
      'findLast',
      'findLastIndex',
      'every',
      'some',
      'reduce',
      'reduceRight',
      'fill',
      'copyWithin',
      'flat',
      'flatMap',
      'at',
      'toReversed',
      'toSorted',
      'toSpliced',
      'keys',
      'values',
      'entries',
      symbolIteratorKey,
      'push',
      'pop',
      'shift',
      'unshift',
      'slice',
      'splice',
      'with',
    ];
    for (final name in nativeMethodNames) {
      final fn = arrayPrototype.getOwnPropertyDirect(name);
      if (fn is JSNativeFunction) {
        ArrayPrototype.registerOriginalNative(name, fn);
      }
    }
  }

  /// Configures global TypedArrays and ArrayBuffer
  void _setupTypedArraysGlobal() {
    // Get Array.prototype for inheritance
    final arrayConstructor =
        _globalEnvironment.get('Array') as JSNativeFunction;
    final arrayPrototype = arrayConstructor.getProperty('prototype');

    // Helper function to setup prototype inheritance
    void setupTypedArrayPrototype(
      JSNativeFunction constructor,
      String name, {
      int bytesPerElement = 0,
    }) {
      final prototype = JSObject();
      prototype.setPrototype(arrayPrototype as JSObject);
      prototype.setProperty('constructor', constructor);
      constructor.setProperty('prototype', prototype);

      // Set static BYTES_PER_ELEMENT property on constructor
      if (bytesPerElement > 0) {
        constructor.setProperty(
          'BYTES_PER_ELEMENT',
          JSValueFactory.number(bytesPerElement.toDouble()),
        );
        prototype.setProperty(
          'BYTES_PER_ELEMENT',
          JSValueFactory.number(bytesPerElement.toDouble()),
        );
      }
    }

    // ArrayBuffer constructor
    final arrayBufferConstructor = JSNativeFunction(
      functionName: 'ArrayBuffer',
      nativeImpl: (args) {
        if (args.isEmpty) {
          throw JSTypeError('ArrayBuffer constructor requires 1 argument');
        }
        final byteLength = _safeToInt(args[0].toNumber());
        if (byteLength < 0) {
          throw JSRangeError('Invalid ArrayBuffer length');
        }
        return JSArrayBuffer(byteLength);
      },
      expectedArgs: 1,
      isConstructor: true, // ArrayBuffer is a constructor
    );

    // ArrayBuffer prototype
    setupTypedArrayPrototype(arrayBufferConstructor, 'ArrayBuffer');

    _globalEnvironment.define(
      'ArrayBuffer',
      arrayBufferConstructor,
      BindingType.var_,
    );

    // Int8Array constructor
    final int8ArrayConstructor = JSNativeFunction(
      functionName: 'Int8Array',
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSInt8Array.fromLength(0);
        }

        final arg = args[0];

        // If it's a number: create an array of that length
        if (arg.isNumber) {
          final length = _safeToInt(arg.toNumber());
          if (length < 0) {
            throw JSRangeError('Invalid typed array length');
          }
          return JSInt8Array.fromLength(length);
        }

        // If it's an ArrayBuffer: create a view on this buffer
        if (arg is JSArrayBuffer) {
          final byteOffset = args.length > 1
              ? _safeToInt(args[1].toNumber())
              : 0;
          final length = args.length > 2
              ? _safeToInt(args[2].toNumber())
              : (arg.byteLength - byteOffset);
          return JSInt8Array(
            buffer: arg,
            byteOffset: byteOffset,
            length: length,
          );
        }

        // If it's an array or iterable: copy the values
        if (arg is JSArray) {
          final values = arg.elements.map((e) => e.toNumber()).toList();
          return JSInt8Array.fromArray(values);
        }

        throw JSTypeError('Invalid argument to Int8Array constructor');
      },
      expectedArgs: 1,
      isConstructor: true, // Int8Array is a constructor
    );

    // Int8Array prototype
    setupTypedArrayPrototype(
      int8ArrayConstructor,
      'Int8Array',
      bytesPerElement: 1,
    );

    _globalEnvironment.define(
      'Int8Array',
      int8ArrayConstructor,
      BindingType.var_,
    );

    // Uint8Array constructor
    final uint8ArrayConstructor = JSNativeFunction(
      functionName: 'Uint8Array',
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSUint8Array.fromLength(0);
        }

        final arg = args[0];

        if (arg.isNumber) {
          final length = _safeToInt(arg.toNumber());
          if (length < 0) {
            throw JSRangeError('Invalid typed array length');
          }
          return JSUint8Array.fromLength(length);
        }

        if (arg is JSArrayBuffer) {
          final byteOffset = args.length > 1
              ? _safeToInt(args[1].toNumber())
              : 0;
          final length = args.length > 2
              ? _safeToInt(args[2].toNumber())
              : (arg.byteLength - byteOffset);
          return JSUint8Array(
            buffer: arg,
            byteOffset: byteOffset,
            length: length,
          );
        }

        if (arg is JSArray) {
          final values = arg.elements.map((e) => e.toNumber()).toList();
          return JSUint8Array.fromArray(values);
        }

        throw JSTypeError('Invalid argument to Uint8Array constructor');
      },
      expectedArgs: 1,
      isConstructor: true, // Uint8Array is a constructor
    );

    // Uint8Array prototype
    setupTypedArrayPrototype(
      uint8ArrayConstructor,
      'Uint8Array',
      bytesPerElement: 1,
    );

    _globalEnvironment.define(
      'Uint8Array',
      uint8ArrayConstructor,
      BindingType.var_,
    );

    // Uint8ClampedArray constructor
    final uint8ClampedArrayConstructor = JSNativeFunction(
      functionName: 'Uint8ClampedArray',
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSUint8ClampedArray.fromLength(0);
        }

        final arg = args[0];

        if (arg.isNumber) {
          final length = _safeToInt(arg.toNumber());
          if (length < 0) {
            throw JSRangeError('Invalid typed array length');
          }
          return JSUint8ClampedArray.fromLength(length);
        }

        if (arg is JSArrayBuffer) {
          final byteOffset = args.length > 1
              ? _safeToInt(args[1].toNumber())
              : 0;
          final length = args.length > 2
              ? _safeToInt(args[2].toNumber())
              : (arg.byteLength - byteOffset);
          return JSUint8ClampedArray(
            buffer: arg,
            byteOffset: byteOffset,
            length: length,
          );
        }

        if (arg is JSArray) {
          final values = arg.elements.map((e) => e.toNumber()).toList();
          return JSUint8ClampedArray.fromArray(values);
        }

        throw JSTypeError('Invalid argument to Uint8ClampedArray constructor');
      },
      expectedArgs: 1,
      isConstructor: true,
    );

    // Uint8ClampedArray prototype
    setupTypedArrayPrototype(
      uint8ClampedArrayConstructor,
      'Uint8ClampedArray',
      bytesPerElement: 1,
    );

    _globalEnvironment.define(
      'Uint8ClampedArray',
      uint8ClampedArrayConstructor,
      BindingType.var_,
    );

    // Int16Array constructor
    final int16ArrayConstructor = JSNativeFunction(
      functionName: 'Int16Array',
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSInt16Array.fromLength(0);
        }

        final arg = args[0];

        if (arg.isNumber) {
          final length = _safeToInt(arg.toNumber());
          if (length < 0) {
            throw JSRangeError('Invalid typed array length');
          }
          return JSInt16Array.fromLength(length);
        }

        if (arg is JSArrayBuffer) {
          final byteOffset = args.length > 1
              ? _safeToInt(args[1].toNumber())
              : 0;
          final length = args.length > 2
              ? _safeToInt(args[2].toNumber())
              : ((arg.byteLength - byteOffset) ~/ 2);
          return JSInt16Array(
            buffer: arg,
            byteOffset: byteOffset,
            length: length,
          );
        }

        if (arg is JSArray) {
          final values = arg.elements.map((e) => e.toNumber()).toList();
          return JSInt16Array.fromArray(values);
        }

        throw JSTypeError('Invalid argument to Int16Array constructor');
      },
      expectedArgs: 1,
      isConstructor: true,
    );

    // Int16Array prototype
    setupTypedArrayPrototype(
      int16ArrayConstructor,
      'Int16Array',
      bytesPerElement: 2,
    );

    _globalEnvironment.define(
      'Int16Array',
      int16ArrayConstructor,
      BindingType.var_,
    );

    // Uint16Array constructor
    final uint16ArrayConstructor = JSNativeFunction(
      functionName: 'Uint16Array',
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSUint16Array.fromLength(0);
        }

        final arg = args[0];

        if (arg.isNumber) {
          final length = _safeToInt(arg.toNumber());
          if (length < 0) {
            throw JSRangeError('Invalid typed array length');
          }
          return JSUint16Array.fromLength(length);
        }

        if (arg is JSArrayBuffer) {
          final byteOffset = args.length > 1
              ? _safeToInt(args[1].toNumber())
              : 0;
          final length = args.length > 2
              ? _safeToInt(args[2].toNumber())
              : ((arg.byteLength - byteOffset) ~/ 2);
          return JSUint16Array(
            buffer: arg,
            byteOffset: byteOffset,
            length: length,
          );
        }

        if (arg is JSArray) {
          final values = arg.elements.map((e) => e.toNumber()).toList();
          return JSUint16Array.fromArray(values);
        }

        throw JSTypeError('Invalid argument to Uint16Array constructor');
      },
      expectedArgs: 1,
      isConstructor: true,
    );

    // Uint16Array prototype
    setupTypedArrayPrototype(
      uint16ArrayConstructor,
      'Uint16Array',
      bytesPerElement: 2,
    );

    _globalEnvironment.define(
      'Uint16Array',
      uint16ArrayConstructor,
      BindingType.var_,
    );

    // Int32Array constructor
    final int32ArrayConstructor = JSNativeFunction(
      functionName: 'Int32Array',
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSInt32Array.fromLength(0);
        }

        final arg = args[0];

        if (arg.isNumber) {
          final length = _safeToInt(arg.toNumber());
          if (length < 0) {
            throw JSRangeError('Invalid typed array length');
          }
          return JSInt32Array.fromLength(length);
        }

        if (arg is JSArrayBuffer) {
          final byteOffset = args.length > 1
              ? _safeToInt(args[1].toNumber())
              : 0;
          final length = args.length > 2
              ? _safeToInt(args[2].toNumber())
              : ((arg.byteLength - byteOffset) ~/ 4);
          return JSInt32Array(
            buffer: arg,
            byteOffset: byteOffset,
            length: length,
          );
        }

        if (arg is JSArray) {
          final values = arg.elements.map((e) => e.toNumber()).toList();
          return JSInt32Array.fromArray(values);
        }

        throw JSTypeError('Invalid argument to Int32Array constructor');
      },
      expectedArgs: 1,
      isConstructor: true,
    );

    // Int32Array prototype
    setupTypedArrayPrototype(
      int32ArrayConstructor,
      'Int32Array',
      bytesPerElement: 4,
    );

    _globalEnvironment.define(
      'Int32Array',
      int32ArrayConstructor,
      BindingType.var_,
    );

    // Uint32Array constructor
    final uint32ArrayConstructor = JSNativeFunction(
      functionName: 'Uint32Array',
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSUint32Array.fromLength(0);
        }

        final arg = args[0];

        if (arg.isNumber) {
          final length = _safeToInt(arg.toNumber());
          if (length < 0) {
            throw JSRangeError('Invalid typed array length');
          }
          return JSUint32Array.fromLength(length);
        }

        if (arg is JSArrayBuffer) {
          final byteOffset = args.length > 1
              ? _safeToInt(args[1].toNumber())
              : 0;
          final length = args.length > 2
              ? _safeToInt(args[2].toNumber())
              : ((arg.byteLength - byteOffset) ~/ 4);
          return JSUint32Array(
            buffer: arg,
            byteOffset: byteOffset,
            length: length,
          );
        }

        if (arg is JSArray) {
          final values = arg.elements.map((e) => e.toNumber()).toList();
          return JSUint32Array.fromArray(values);
        }

        throw JSTypeError('Invalid argument to Uint32Array constructor');
      },
      expectedArgs: 1,
      isConstructor: true,
    );

    // Uint32Array prototype
    setupTypedArrayPrototype(
      uint32ArrayConstructor,
      'Uint32Array',
      bytesPerElement: 4,
    );

    _globalEnvironment.define(
      'Uint32Array',
      uint32ArrayConstructor,
      BindingType.var_,
    );

    // Float16Array constructor
    final float16ArrayConstructor = JSNativeFunction(
      functionName: 'Float16Array',
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSFloat16Array.fromLength(0);
        }

        final arg = args[0];

        if (arg.isNumber) {
          final length = _safeToInt(arg.toNumber());
          if (length < 0) {
            throw JSTypeError('Invalid array length');
          }
          return JSFloat16Array.fromLength(length);
        }

        if (arg is JSTypedArray) {
          final buffer = arg.buffer;
          final byteOffset = arg.byteOffset;
          final length = arg.length;
          return JSFloat16Array(
            buffer: buffer,
            byteOffset: byteOffset,
            length: length,
          );
        }

        if (arg is JSArrayBuffer) {
          final buffer = arg;
          final byteOffset = args.length > 1
              ? _safeToInt(args[1].toNumber())
              : 0;
          final length = args.length > 2
              ? _safeToInt(args[2].toNumber())
              : (buffer.byteLength - byteOffset) ~/ 2;
          return JSFloat16Array(
            buffer: buffer,
            byteOffset: byteOffset,
            length: length,
          );
        }

        if (arg is JSArray) {
          final values = arg.elements.map((e) => e.toNumber()).toList();
          return JSFloat16Array.fromArray(values);
        }

        throw JSTypeError('Invalid argument to Float16Array constructor');
      },
      expectedArgs: 1,
      isConstructor: true,
    );

    // Float16Array prototype
    setupTypedArrayPrototype(
      float16ArrayConstructor,
      'Float16Array',
      bytesPerElement: 2,
    );

    _globalEnvironment.define(
      'Float16Array',
      float16ArrayConstructor,
      BindingType.var_,
    );

    // Float32Array constructor
    final float32ArrayConstructor = JSNativeFunction(
      functionName: 'Float32Array',
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSFloat32Array.fromLength(0);
        }

        final arg = args[0];

        if (arg.isNumber) {
          final length = _safeToInt(arg.toNumber());
          if (length < 0) {
            throw JSRangeError('Invalid typed array length');
          }
          return JSFloat32Array.fromLength(length);
        }

        if (arg is JSArrayBuffer) {
          final byteOffset = args.length > 1
              ? _safeToInt(args[1].toNumber())
              : 0;
          final length = args.length > 2
              ? _safeToInt(args[2].toNumber())
              : ((arg.byteLength - byteOffset) ~/ 4);
          return JSFloat32Array(
            buffer: arg,
            byteOffset: byteOffset,
            length: length,
          );
        }

        if (arg is JSArray) {
          final values = arg.elements.map((e) => e.toNumber()).toList();
          return JSFloat32Array.fromArray(values);
        }

        throw JSTypeError('Invalid argument to Float32Array constructor');
      },
      expectedArgs: 1,
      isConstructor: true,
    );

    // Float32Array prototype
    setupTypedArrayPrototype(
      float32ArrayConstructor,
      'Float32Array',
      bytesPerElement: 4,
    );

    _globalEnvironment.define(
      'Float32Array',
      float32ArrayConstructor,
      BindingType.var_,
    );

    // Float64Array constructor
    final float64ArrayConstructor = JSNativeFunction(
      functionName: 'Float64Array',
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSFloat64Array.fromLength(0);
        }

        final arg = args[0];

        if (arg.isNumber) {
          final length = _safeToInt(arg.toNumber());
          if (length < 0) {
            throw JSRangeError('Invalid typed array length');
          }
          return JSFloat64Array.fromLength(length);
        }

        if (arg is JSArrayBuffer) {
          final byteOffset = args.length > 1
              ? _safeToInt(args[1].toNumber())
              : 0;
          final length = args.length > 2
              ? _safeToInt(args[2].toNumber())
              : ((arg.byteLength - byteOffset) ~/ 8);
          return JSFloat64Array(
            buffer: arg,
            byteOffset: byteOffset,
            length: length,
          );
        }

        if (arg is JSArray) {
          final values = arg.elements.map((e) => e.toNumber()).toList();
          return JSFloat64Array.fromArray(values);
        }

        throw JSTypeError('Invalid argument to Float64Array constructor');
      },
      expectedArgs: 1,
      isConstructor: true,
    );

    // Float64Array prototype
    setupTypedArrayPrototype(
      float64ArrayConstructor,
      'Float64Array',
      bytesPerElement: 8,
    );

    _globalEnvironment.define(
      'Float64Array',
      float64ArrayConstructor,
      BindingType.var_,
    );

    // BigInt64Array constructor
    final bigInt64ArrayConstructor = JSNativeFunction(
      functionName: 'BigInt64Array',
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSBigInt64Array.fromLength(0);
        }

        final arg = args[0];

        if (arg.isNumber) {
          final length = _safeToInt(arg.toNumber());
          if (length < 0) {
            throw JSRangeError('Invalid typed array length');
          }
          return JSBigInt64Array.fromLength(length);
        }

        if (arg is JSArrayBuffer) {
          final byteOffset = args.length > 1
              ? _safeToInt(args[1].toNumber())
              : 0;
          final length = args.length > 2
              ? _safeToInt(args[2].toNumber())
              : ((arg.byteLength - byteOffset) ~/ 8);
          return JSBigInt64Array(
            buffer: arg,
            byteOffset: byteOffset,
            length: length,
          );
        }

        if (arg is JSArray) {
          final values = arg.elements.map((e) {
            if (e is JSBigInt) return e.value;
            return BigInt.from(e.toNumber().truncate());
          }).toList();
          return JSBigInt64Array.fromArray(values);
        }

        throw JSTypeError('Invalid argument to BigInt64Array constructor');
      },
      expectedArgs: 1,
      isConstructor: true,
    );

    // BigInt64Array prototype
    setupTypedArrayPrototype(
      bigInt64ArrayConstructor,
      'BigInt64Array',
      bytesPerElement: 8,
    );

    _globalEnvironment.define(
      'BigInt64Array',
      bigInt64ArrayConstructor,
      BindingType.var_,
    );

    // BigUint64Array constructor
    final bigUint64ArrayConstructor = JSNativeFunction(
      functionName: 'BigUint64Array',
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSBigUint64Array.fromLength(0);
        }

        final arg = args[0];

        if (arg.isNumber) {
          final length = _safeToInt(arg.toNumber());
          if (length < 0) {
            throw JSRangeError('Invalid typed array length');
          }
          return JSBigUint64Array.fromLength(length);
        }

        if (arg is JSArrayBuffer) {
          final byteOffset = args.length > 1
              ? _safeToInt(args[1].toNumber())
              : 0;
          final length = args.length > 2
              ? _safeToInt(args[2].toNumber())
              : ((arg.byteLength - byteOffset) ~/ 8);
          return JSBigUint64Array(
            buffer: arg,
            byteOffset: byteOffset,
            length: length,
          );
        }

        if (arg is JSArray) {
          final values = arg.elements.map((e) {
            if (e is JSBigInt) return e.value;
            return BigInt.from(e.toNumber().truncate());
          }).toList();
          return JSBigUint64Array.fromArray(values);
        }

        throw JSTypeError('Invalid argument to BigUint64Array constructor');
      },
      expectedArgs: 1,
      isConstructor: true,
    );

    // BigUint64Array prototype
    setupTypedArrayPrototype(
      bigUint64ArrayConstructor,
      'BigUint64Array',
      bytesPerElement: 8,
    );

    _globalEnvironment.define(
      'BigUint64Array',
      bigUint64ArrayConstructor,
      BindingType.var_,
    );

    // DataView constructor
    final dataViewConstructor = JSNativeFunction(
      functionName: 'DataView',
      nativeImpl: (args) {
        if (args.isEmpty) {
          throw JSTypeError('DataView constructor requires 1 argument');
        }

        final buffer = args[0];
        if (buffer is! JSArrayBuffer) {
          throw JSTypeError(
            'First argument to DataView constructor must be an ArrayBuffer',
          );
        }

        final byteOffset = args.length > 1 ? _safeToInt(args[1].toNumber()) : 0;
        final byteLength = args.length > 2
            ? _safeToInt(args[2].toNumber())
            : null;

        return JSDataView(
          buffer: buffer,
          byteOffset: byteOffset,
          byteLength: byteLength,
        );
      },
      expectedArgs: 1,
      isConstructor: true,
    );

    // DataView prototype (doesn't inherit from Array.prototype)
    final dataViewPrototype = JSObject();
    dataViewPrototype.setProperty('constructor', dataViewConstructor);
    dataViewConstructor.setProperty('prototype', dataViewPrototype);

    _globalEnvironment.define(
      'DataView',
      dataViewConstructor,
      BindingType.var_,
    );
  }

  /// Configures the global RegExp object
  void _setupRegExpGlobal() {
    // Create the RegExp constructor function
    final regexpConstructor = JSNativeFunction(
      functionName: 'RegExp',
      nativeImpl: (args) {
        String pattern = '';
        String flags = '';

        if (args.isNotEmpty) {
          final firstArg = args[0];
          if (firstArg is JSRegExp) {
            // RegExp(regex) ou RegExp(regex, flags)
            pattern = firstArg.source;
            if (args.length > 1) {
              flags = args[1].toString();
            } else {
              flags = firstArg.flags;
            }
          } else {
            // RegExp(pattern, flags)
            pattern = firstArg.toString();
            if (args.length > 1) {
              flags = args[1].toString();
            }
          }
        }

        try {
          final validatedFlags = JSRegExpFactory.parseFlags(flags);
          return JSRegExp(pattern, validatedFlags);
        } catch (e) {
          throw JSSyntaxError('Invalid regular expression: $e');
        }
      },
      expectedArgs: 2,
      isConstructor: true, // RegExp is a constructor
    );

    // Create the RegExp prototype
    final regexpPrototype = JSObject();
    regexpConstructor.setProperty('prototype', regexpPrototype);

    // IMPORTANT: Add the constructor property to RegExp.prototype
    regexpPrototype.setProperty('constructor', regexpConstructor);

    // Add it to the global environment
    _globalEnvironment.define('RegExp', regexpConstructor, BindingType.var_);
  }

  /// Configures the global Date object
  void _setupDateGlobal() {
    // Create the Date constructor function
    final dateConstructor = DateObject.createDateConstructor();

    // Create the Date prototype
    final datePrototype = JSObject();
    dateConstructor.setProperty('prototype', datePrototype);

    // IMPORTANT: Add the constructor property to Date.prototype
    datePrototype.setProperty('constructor', dateConstructor);

    // Add it to the global environment
    _globalEnvironment.define('Date', dateConstructor, BindingType.var_);
  }

  /// Configures the global BigInt object
  void _setupBigIntGlobal() {
    // Create the BigInt constructor function
    final bigintConstructor = JSNativeFunction(
      functionName: 'BigInt',
      nativeImpl: (args) {
        if (args.isEmpty) {
          throw JSTypeError('BigInt constructor requires an argument');
        }

        final value = args[0];

        if (value.isBigInt) {
          // If it's already a BigInt, return it as-is
          return value;
        } else if (value.isString) {
          // Convert from a string
          final str = value.toString();
          try {
            // Remove spaces and handle prefixes
            final trimmed = str.trim();
            if (trimmed.isEmpty) {
              return JSValueFactory.bigint(BigInt.zero);
            }

            // Handle binary, octal, hexadecimal prefixes
            BigInt result;
            if (trimmed.startsWith('0b') || trimmed.startsWith('0B')) {
              result = BigInt.parse(trimmed.substring(2), radix: 2);
            } else if (trimmed.startsWith('0o') || trimmed.startsWith('0O')) {
              result = BigInt.parse(trimmed.substring(2), radix: 8);
            } else if (trimmed.startsWith('0x') || trimmed.startsWith('0X')) {
              result = BigInt.parse(trimmed.substring(2), radix: 16);
            } else {
              result = BigInt.parse(trimmed);
            }

            return JSValueFactory.bigint(result);
          } catch (e) {
            throw JSTypeError('Invalid BigInt string: $str');
          }
        } else if (value.isNumber) {
          // Convert from a number
          final num = value.toNumber();
          if (num.isNaN || num.isInfinite) {
            throw JSTypeError(
              'Cannot convert ${num.isNaN ? 'NaN' : 'Infinity'} to BigInt',
            );
          }

          // For large numbers, use string representation
          // because toInt() can lose precision
          if (num.abs() > 9007199254740991) {
            // Number.MAX_SAFE_INTEGER
            // Check that it's an integer using modulo
            if (num % 1 != 0) {
              throw JSTypeError('Cannot convert non-integer number to BigInt');
            }

            final str = num.toStringAsExponential();
            final parts = str.split('e');
            final mantissa = parts[0].replaceAll('.', '');
            final exponent = int.parse(parts[1]);
            final decimalPlaces = parts[0].contains('.')
                ? parts[0].split('.')[1].length
                : 0;
            final bigMantissa = BigInt.parse(mantissa);
            final result =
                bigMantissa * BigInt.from(10).pow(exponent - decimalPlaces);
            return JSValueFactory.bigint(result);
          }

          // Check that it's an integer
          if (num != num.truncate()) {
            throw JSTypeError('Cannot convert non-integer number to BigInt');
          }

          return JSValueFactory.bigint(BigInt.from(num.toInt()));
        } else if (value.isBoolean) {
          // Convert from a boolean
          return JSValueFactory.bigint(
            value.toBoolean() ? BigInt.one : BigInt.zero,
          );
        } else {
          // For other types, try converting to string first
          final str = value.toString();
          try {
            final result = BigInt.parse(str.trim());
            return JSValueFactory.bigint(result);
          } catch (e) {
            throw JSTypeError('Cannot convert $value to BigInt');
          }
        }
      },
    );

    // Proprietes statiques de BigInt
    bigintConstructor.setProperty(
      'asIntN',
      JSNativeFunction(
        functionName: 'asIntN',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError('BigInt.asIntN requires 2 arguments');
          }

          final bits = args[0].toNumber();
          if (bits.isNaN || bits.isInfinite || bits < 0) {
            throw JSTypeError('Invalid bits value for BigInt.asIntN');
          }

          final bigint = args[1];
          if (!bigint.isBigInt) {
            throw JSTypeError(
              'BigInt.asIntN requires a BigInt as second argument',
            );
          }

          final value = (bigint as JSBigInt).value;
          final bitsInt = bits.toInt();

          if (bitsInt == 0) {
            return JSValueFactory.bigint(BigInt.zero);
          }

          // Calculate the mask for the specified bits
          final mask = (BigInt.one << bitsInt) - BigInt.one;
          final masked = value & mask;

          // If the sign bit is set, extend the sign
          if (bitsInt > 0 &&
              (masked & (BigInt.one << (bitsInt - 1))) != BigInt.zero) {
            final signExtension = ~mask;
            return JSValueFactory.bigint(masked | signExtension);
          }

          return JSValueFactory.bigint(masked);
        },
      ),
    );

    bigintConstructor.setProperty(
      'asUintN',
      JSNativeFunction(
        functionName: 'asUintN',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError('BigInt.asUintN requires 2 arguments');
          }

          final bits = args[0].toNumber();
          if (bits.isNaN || bits.isInfinite || bits < 0) {
            throw JSTypeError('Invalid bits value for BigInt.asUintN');
          }

          final bigint = args[1];
          if (!bigint.isBigInt) {
            throw JSTypeError(
              'BigInt.asUintN requires a BigInt as second argument',
            );
          }

          final value = (bigint as JSBigInt).value;
          final bitsInt = bits.toInt();

          if (bitsInt == 0) {
            return JSValueFactory.bigint(BigInt.zero);
          }

          // Calculate the mask for the specified bits
          final mask = (BigInt.one << bitsInt) - BigInt.one;
          return JSValueFactory.bigint(value & mask);
        },
      ),
    );

    // Create the BigInt prototype
    final bigintPrototype = JSObject();
    bigintConstructor.setProperty('prototype', bigintPrototype);

    // IMPORTANT: Add the constructor property to BigInt.prototype
    bigintPrototype.setProperty('constructor', bigintConstructor);

    // Add it to the global environment
    _globalEnvironment.define('BigInt', bigintConstructor, BindingType.var_);
  }

  /// Configure the global Symbol object
  void _setupSymbolGlobal() {
    // Create the Symbol constructor function
    final symbolConstructor = JSNativeFunction(
      functionName: 'Symbol',
      nativeImpl: (args) {
        final description = args.isNotEmpty ? args[0].toString() : null;
        return JSSymbol(description);
      },
    );

    // Proprietes statiques de Symbol
    symbolConstructor.setProperty(
      'for',
      JSNativeFunction(
        functionName: 'Symbol.for',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSTypeError('Symbol.for requires 1 argument');
          }
          final key = args[0].toString();
          return JSSymbol.symbolFor(key);
        },
      ),
    );

    symbolConstructor.setProperty(
      'keyFor',
      JSNativeFunction(
        functionName: 'Symbol.keyFor',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSTypeError('Symbol.keyFor requires 1 argument');
          }
          final symbol = args[0];
          if (!symbol.isSymbol) {
            throw JSTypeError('Symbol.keyFor requires a Symbol as argument');
          }
          final jsSymbol = symbol as JSSymbol;
          return jsSymbol.globalKey != null
              ? JSValueFactory.string(jsSymbol.globalKey!)
              : JSValueFactory.undefined();
        },
      ),
    );

    // Symboles well-known
    symbolConstructor.setProperty('iterator', JSSymbol.iterator);
    symbolConstructor.setProperty('asyncIterator', JSSymbol.asyncIterator);
    symbolConstructor.setProperty('toStringTag', JSSymbol.toStringTag);
    symbolConstructor.setProperty('hasInstance', JSSymbol.hasInstance);
    symbolConstructor.setProperty('species', JSSymbol.species);
    symbolConstructor.setProperty('toPrimitive', JSSymbol.symbolToPrimitive);
    symbolConstructor.setProperty('match', JSSymbol.match);
    symbolConstructor.setProperty('replace', JSSymbol.replace);
    symbolConstructor.setProperty('search', JSSymbol.search);
    symbolConstructor.setProperty('split', JSSymbol.split);
    symbolConstructor.setProperty(
      'isConcatSpreadable',
      JSSymbol.isConcatSpreadable,
    );
    symbolConstructor.setProperty('unscopables', JSSymbol.unscopables);

    // Symbol ne peut pas etre appele avec new
    final symbolPrototype = JSObject();
    symbolConstructor.setProperty('prototype', symbolPrototype);

    // IMPORTANT: Add the constructor property to Symbol.prototype
    symbolPrototype.setProperty('constructor', symbolConstructor);

    // Add Symbol.prototype.toString
    symbolPrototype.setProperty(
      'toString',
      JSNativeFunction(
        functionName: 'toString',
        nativeImpl: (args) {
          if (args.isNotEmpty) {
            if (args[0] is JSSymbol) {
              return JSValueFactory.string(args[0].toString());
            } else if (args[0] is JSSymbolObject) {
              return JSValueFactory.string(
                (args[0] as JSSymbolObject).primitiveValue.toString(),
              );
            }
          }
          return JSValueFactory.string('[Symbol]');
        },
      ),
    );

    // Add Symbol.prototype.valueOf
    symbolPrototype.setProperty(
      'valueOf',
      JSNativeFunction(
        functionName: 'valueOf',
        nativeImpl: (args) {
          if (args.isNotEmpty) {
            if (args[0] is JSSymbol) {
              return args[0];
            } else if (args[0] is JSSymbolObject) {
              return (args[0] as JSSymbolObject).primitiveValue;
            }
          }
          throw JSTypeError('Symbol.prototype.valueOf called on non-Symbol');
        },
      ),
    );

    // IMPORTANT: Set Symbol.prototype for JSSymbolObject instances
    JSSymbolObject.setSymbolPrototype(symbolPrototype);

    // Add it to the global environment
    _globalEnvironment.define('Symbol', symbolConstructor, BindingType.var_);
  }

  /// Configure the global TextEncoder/TextDecoder objects
  void _setupTextCodecGlobal() {
    // Create the TextEncoder constructor
    final textEncoderConstructor =
        TextEncoder.createTextEncoderConstructor() as JSNativeFunction;

    // Create the TextEncoder prototype
    final textEncoderPrototype = JSObject();
    textEncoderConstructor.setProperty('prototype', textEncoderPrototype);

    // IMPORTANT: Add the constructor property to TextEncoder.prototype
    textEncoderPrototype.setProperty('constructor', textEncoderConstructor);

    // Create the TextDecoder constructor
    final textDecoderConstructor =
        TextDecoder.createTextDecoderConstructor() as JSNativeFunction;

    // Create the TextDecoder prototype
    final textDecoderPrototype = JSObject();
    textDecoderConstructor.setProperty('prototype', textDecoderPrototype);

    // IMPORTANT: Add the constructor property to TextDecoder.prototype
    textDecoderPrototype.setProperty('constructor', textDecoderConstructor);

    // Add them to the global environment
    _globalEnvironment.define(
      'TextEncoder',
      textEncoderConstructor,
      BindingType.var_,
    );
    _globalEnvironment.define(
      'TextDecoder',
      textDecoderConstructor,
      BindingType.var_,
    );
  }

  /// Configure the global JSON object
  void _setupJSONGlobal() {
    // Create JSON
    final jsonObject = JSONObject.createJSONObject();

    // Add it to the global environment
    _globalEnvironment.define('JSON', jsonObject, BindingType.var_);
  }

  /// Configure the global CommonJS objects (module, exports, require)
  /// Permet aux fichiers bundles et au code Node.js de fonctionner
  void _setupCommonJSGlobal() {
    // Create module avec exports
    final moduleObject = JSValueFactory.createObject();
    final exportsObject = JSValueFactory.createObject();

    moduleObject.setProperty('exports', exportsObject);

    // Definir exports (reference au meme objet que module.exports)
    _globalEnvironment.define('exports', exportsObject, BindingType.var_);
    _globalEnvironment.define('module', moduleObject, BindingType.var_);

    // Create the require function
    final requireFunction = JSNativeFunction(
      functionName: 'require',
      nativeImpl: (args) {
        if (args.isEmpty) {
          throw JSError('require() expects a module path');
        }

        final modulePath = args[0].toString();

        // For integrated CommonJS modules, we can return empty objects
        // ou essayer de charger depuis le systeme de modules ES6
        if (_modules.containsKey(modulePath)) {
          // If it's an ES6 module, return its exports
          return _getModuleExports(modulePath);
        }

        // Otherwise, return an empty object (simulates an empty module)
        return JSValueFactory.createObject();
      },
    );

    _globalEnvironment.define('require', requireFunction, BindingType.var_);
  }

  /// Configure the global Map object
  void _setupMapGlobal() {
    // Create the Map constructor
    final mapConstructor = JSNativeFunction(
      functionName: 'Map',
      nativeImpl: (args) {
        final map = JSMap();

        // If an iterable argument is provided, use it to initialize the map
        if (args.isNotEmpty) {
          final iterable = args[0];
          if (iterable is JSArray) {
            // Traiter chaque paire [key, value]
            for (final pair in iterable.elements) {
              if (pair is JSArray && pair.elements.length >= 2) {
                map.set(pair.elements[0], pair.elements[1]);
              }
            }
          }
        }

        return map;
      },
      expectedArgs: 0,
      isConstructor: true, // Map is a constructor
    );

    // Ajouter des methodes statiques
    mapConstructor.setProperty(
      'groupBy',
      JSNativeFunction(
        functionName: 'Map.groupBy',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError('Map.groupBy requires at least 2 arguments');
          }

          final items = args[0];
          final callback = args[1];

          if (callback is! JSFunction) {
            throw JSTypeError('Map.groupBy callback must be a function');
          }

          final result = JSMap();

          // Get an iterator for the items object
          final iterator = IteratorUtils.getIterator(items);
          if (iterator != null) {
            // The object is iterable - use the iterator
            while (true) {
              final nextResult = iterator.next();
              if (nextResult is JSObject) {
                final done = nextResult.getProperty('done').toBoolean();
                if (done) break;

                final item = nextResult.getProperty('value');
                final key = callFunction(callback, [item]);

                // Get or create the group
                var group = result.get(key);
                if (group.isUndefined) {
                  group = JSArray([]);
                  result.set(key, group);
                }

                if (group is JSArray) {
                  group.elements.add(item);
                }
              } else {
                break;
              }
            }
          } else if (items is JSObject) {
            // The object is not iterable - treat it as a simple object
            // Iterate over enumerable properties
            final propertyNames = items.getPropertyNames();
            for (final propName in propertyNames) {
              final item = items.getProperty(propName);
              final key = callFunction(callback, [item]);

              // Obtenir ou creer le groupe
              var group = result.get(key);
              if (group.isUndefined) {
                group = JSArray([]);
                result.set(key, group);
              }

              if (group is JSArray) {
                group.elements.add(item);
              }
            }
          } else {
            // Type non supporte
            throw JSTypeError(
              'Map.groupBy: items must be iterable or an object',
            );
          }

          return result;
        },
      ),
    );

    // Create the Map prototype
    final mapPrototype = JSObject();
    mapConstructor.setProperty('prototype', mapPrototype);

    // IMPORTANT: Add the constructor property to Map.prototype
    mapPrototype.setProperty('constructor', mapConstructor);

    // Add Symbol.species getter - ES6: Map[@@species]
    final mapSpeciesGetter = JSNativeFunction(
      functionName: 'get [Symbol.species]',
      nativeImpl: (args) {
        // Return 'this' - the constructor that was used
        return args.isNotEmpty ? args[0] : JSValueFactory.undefined();
      },
      expectedArgs: 0,
    );

    final mapSpeciesKey = JSSymbol.species.toString();
    mapConstructor.defineProperty(
      mapSpeciesKey,
      PropertyDescriptor(
        getter: mapSpeciesGetter,
        setter: null,
        enumerable: false,
        configurable: true,
        hasValueProperty: false,
      ),
    );

    // Add it to the global environment
    _globalEnvironment.define('Map', mapConstructor, BindingType.var_);
  }

  /// Configure the global Set object
  void _setupSetGlobal() {
    // Create the Set constructor
    final setConstructor = JSNativeFunction(
      functionName: 'Set',
      nativeImpl: (args) {
        final set = JSSet();

        // If an iterable argument is provided, use it to initialize the set
        if (args.isNotEmpty) {
          final iterable = args[0];
          if (iterable is JSArray) {
            // Add each element from the array
            for (final element in iterable.elements) {
              set.add(element);
            }
          }
        }

        return set;
      },
      expectedArgs: 0,
      isConstructor: true, // Set is a constructor
    );

    // Add static methods
    setConstructor.setProperty(
      'isDisjointFrom',
      JSNativeFunction(
        functionName: 'Set.isDisjointFrom',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSError('Set.isDisjointFrom requires 2 arguments');
          }

          final setA = args[0];
          final setB = args[1];

          if (setA is! JSSet || setB is! JSSet) {
            throw JSError('Both arguments must be Set objects');
          }

          // Check for common elements
          for (final element in setA.values) {
            if ((setB.has(element) as JSBoolean).value) {
              return JSValueFactory.boolean(false);
            }
          }

          return JSValueFactory.boolean(true);
        },
      ),
    );

    setConstructor.setProperty(
      'isSubsetOf',
      JSNativeFunction(
        functionName: 'Set.isSubsetOf',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSError('Set.isSubsetOf requires 2 arguments');
          }

          final subset = args[0];
          final superset = args[1];

          if (subset is! JSSet || superset is! JSSet) {
            throw JSError('Both arguments must be Set objects');
          }

          // Check that all elements of subset are in superset
          for (final element in subset.values) {
            if (!(superset.has(element) as JSBoolean).value) {
              return JSValueFactory.boolean(false);
            }
          }

          return JSValueFactory.boolean(true);
        },
      ),
    );

    setConstructor.setProperty(
      'isSupersetOf',
      JSNativeFunction(
        functionName: 'Set.isSupersetOf',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSError('Set.isSupersetOf requires 2 arguments');
          }

          final superset = args[0];
          final subset = args[1];

          if (superset is! JSSet || subset is! JSSet) {
            throw JSError('Both arguments must be Set objects');
          }

          // Check that all elements of subset are in superset
          for (final element in subset.values) {
            if (!(superset.has(element) as JSBoolean).value) {
              return JSValueFactory.boolean(false);
            }
          }

          return JSValueFactory.boolean(true);
        },
      ),
    );

    // Create the Set prototype
    final setPrototype = JSObject();
    setConstructor.setProperty('prototype', setPrototype);

    // IMPORTANT: Add the constructor property to Set.prototype
    setPrototype.setProperty('constructor', setConstructor);

    // Add Symbol.species getter - ES6: Set[@@species]
    final setSpeciesGetter = JSNativeFunction(
      functionName: 'get [Symbol.species]',
      nativeImpl: (args) {
        // Return 'this' - the constructor that was used
        return args.isNotEmpty ? args[0] : JSValueFactory.undefined();
      },
      expectedArgs: 0,
    );

    final setSpeciesKey = JSSymbol.species.toString();
    setConstructor.defineProperty(
      setSpeciesKey,
      PropertyDescriptor(
        getter: setSpeciesGetter,
        setter: null,
        enumerable: false,
        configurable: true,
        hasValueProperty: false,
      ),
    );

    // Add it to the global environment
    _globalEnvironment.define('Set', setConstructor, BindingType.var_);
  }

  /// Configure l'objet Promise global
  void _setupPromiseGlobal() {
    // Creer le constructeur Promise
    final promiseConstructor = JSNativeFunction(
      functionName: 'Promise',
      nativeImpl: (args) {
        if (args.isEmpty) {
          throw JSTypeError('Promise constructor requires 1 argument');
        }

        final executor = args[0];
        if (executor is! JSFunction) {
          throw JSTypeError('Promise executor must be a function');
        }

        return JSPromise(executor);
      },
      expectedArgs: 1,
      isConstructor: true, // Promise is a constructor
    );

    // Add static methods with non-enumerable properties
    promiseConstructor.defineProperty(
      'resolve',
      PropertyDescriptor(
        value: PromiseStaticMethod(
          functionName: 'resolve',
          expectedArgs: 1,
          promiseNativeImpl: PromisePrototype.resolveWithThis,
          isCtorFn: false, // Promise.resolve is not a constructor
        ),
        enumerable: false,
        configurable: true,
        writable: true,
      ),
    );

    promiseConstructor.defineProperty(
      'reject',
      PropertyDescriptor(
        value: PromiseStaticMethod(
          functionName: 'reject',
          expectedArgs: 1,
          promiseNativeImpl: PromisePrototype.rejectWithThis,
          isCtorFn: false, // Promise.reject is not a constructor
        ),
        enumerable: false,
        configurable: true,
        writable: true,
      ),
    );

    promiseConstructor.defineProperty(
      'all',
      PropertyDescriptor(
        value: PromiseStaticMethod(
          functionName: 'all',
          expectedArgs: 1,
          nativeImpl: PromisePrototype.all,
          isCtorFn: false,
        ),
        enumerable: false,
        configurable: true,
        writable: true,
      ),
    );

    promiseConstructor.defineProperty(
      'race',
      PropertyDescriptor(
        value: PromiseStaticMethod(
          functionName: 'race',
          expectedArgs: 1,
          nativeImpl: PromisePrototype.race,
          isCtorFn: false,
        ),
        enumerable: false,
        configurable: true,
        writable: true,
      ),
    );

    // ES2020: Promise.allSettled
    promiseConstructor.defineProperty(
      'allSettled',
      PropertyDescriptor(
        value: PromiseStaticMethod(
          functionName: 'allSettled',
          expectedArgs: 1,
          nativeImpl: PromisePrototype.allSettled,
          isCtorFn: false,
        ),
        enumerable: false,
        configurable: true,
        writable: true,
      ),
    );

    // ES2021: Promise.any
    promiseConstructor.defineProperty(
      'any',
      PropertyDescriptor(
        value: PromiseStaticMethod(
          functionName: 'any',
          expectedArgs: 1,
          nativeImpl: PromisePrototype.any,
          isCtorFn: false,
        ),
        enumerable: false,
        configurable: true,
        writable: true,
      ),
    );

    // ES2024: Promise.withResolvers()
    promiseConstructor.defineProperty(
      'withResolvers',
      PropertyDescriptor(
        value: PromiseStaticMethod(
          functionName: 'withResolvers',
          expectedArgs: 0,
          isCtorFn: false,
          nativeImpl: (args) {
            // Create result object first
            final result = JSObject();

            // Create the promise with an executor that stores resolve/reject in the result object
            final promise = JSPromise(
              JSNativeFunction(
                functionName: 'withResolvers-executor',
                nativeImpl: (executorArgs) {
                  if (executorArgs.length >= 2) {
                    // Store resolve and reject functions in the result object
                    result.setProperty('resolve', executorArgs[0]);
                    result.setProperty('reject', executorArgs[1]);
                  }
                  return JSValueFactory.undefined();
                },
              ),
            );

            // Store the promise in the result object
            result.setProperty('promise', promise);

            return result;
          },
        ),
        enumerable: false,
        configurable: true,
        writable: true,
      ),
    );

    // Add Symbol.species getter - ES6: Promise[@@species]
    final promiseSpeciesGetter = JSNativeFunction(
      functionName: 'get [Symbol.species]',
      nativeImpl: (args) {
        // Return 'this' - the constructor that was used
        return args.isNotEmpty ? args[0] : JSValueFactory.undefined();
      },
      expectedArgs: 0,
    );

    final promiseSpeciesKey = JSSymbol.species.toString();
    promiseConstructor.defineProperty(
      promiseSpeciesKey,
      PropertyDescriptor(
        getter: promiseSpeciesGetter,
        setter: null,
        enumerable: false,
        configurable: true,
        hasValueProperty: false,
      ),
    );

    // Add it to the global environment
    _globalEnvironment.define('Promise', promiseConstructor, BindingType.var_);

    // Get Error prototype for AggregateError to extend
    JSObject? errorProto;
    try {
      final errorConstructor = _globalEnvironment.get('Error');
      if (errorConstructor is JSFunction) {
        final proto = errorConstructor.getProperty('prototype');
        if (proto is JSObject) {
          errorProto = proto;
        }
      }
    } catch (_) {}

    // Creer le prototype AggregateError first
    final aggregateErrorPrototype = JSObject();
    if (errorProto != null) {
      // AggregateError.prototype should extend Error.prototype
      aggregateErrorPrototype.setPrototype(errorProto);
    }
    aggregateErrorPrototype.setProperty(
      'name',
      JSValueFactory.string('AggregateError'),
    );

    // ES2021: AggregateError constructor
    final aggregateErrorConstructor = JSNativeFunction(
      functionName: 'AggregateError',
      nativeImpl: (args) {
        JSObject? existingInstance;
        List<JSValue> effectiveArgs = args;

        // Check if first argument is an existing instance (from super() call)
        if (args.isNotEmpty && args[0] is JSObject) {
          final firstArg = args[0] as JSObject;
          final proto = firstArg.getPrototype();

          // Check if this is a subclass instance
          if (proto != null && proto != aggregateErrorPrototype) {
            // Walk up the chain to see if AggregateError.prototype is in the chain
            JSObject? current = proto;
            bool extendsAggregateError = false;
            while (current != null) {
              if (current == aggregateErrorPrototype) {
                extendsAggregateError = true;
                break;
              }
              // Also check for error-type prototypes
              final nameVal = current.getOwnPropertyDirect('name');
              if (nameVal != null && nameVal is JSString) {
                final name = nameVal.toString();
                if (name == 'AggregateError') {
                  extendsAggregateError = true;
                  break;
                }
              }
              current = current.getPrototype();
            }

            if (extendsAggregateError) {
              existingInstance = firstArg;
              effectiveArgs = args.length > 1 ? args.sublist(1) : [];
            }
          }
        }

        final errorsArg = effectiveArgs.isNotEmpty
            ? effectiveArgs[0]
            : JSValueFactory.array([]);
        final messageArg = effectiveArgs.length > 1
            ? JSConversion.jsToString(effectiveArgs[1])
            : 'All promises were rejected';

        // Use existing instance or create new one
        final aggregateError = existingInstance ?? JSValueFactory.object({});

        aggregateError.setProperty(
          'name',
          JSValueFactory.string('AggregateError'),
        );
        aggregateError.setProperty(
          'message',
          JSValueFactory.string(messageArg),
        );

        // Set [[ErrorData]] internal slot - required by ES spec
        aggregateError.setInternalSlot('ErrorData', true);

        // Set prototype to AggregateError.prototype (only if creating new object)
        if (existingInstance == null) {
          aggregateError.setPrototype(aggregateErrorPrototype);
        }

        // Convertir errorsArg en tableau si ce n'en est pas un
        final errorsArray = errorsArg is JSArray
            ? errorsArg
            : JSValueFactory.array([errorsArg]);
        aggregateError.setProperty('errors', errorsArray);

        return aggregateError;
      },
      expectedArgs: 2,
      isConstructor: true, // AggregateError is a constructor
    );

    aggregateErrorConstructor.setProperty('prototype', aggregateErrorPrototype);

    // IMPORTANT: Ajouter la propriete constructor a AggregateError.prototype
    aggregateErrorPrototype.setProperty(
      'constructor',
      aggregateErrorConstructor,
    );

    _globalEnvironment.define(
      'AggregateError',
      aggregateErrorConstructor,
      BindingType.var_,
    );

    // Configurer le prototype Promise
    final promisePrototype = JSObject();

    // Set constructor property first so it can be referenced
    // (Will be set again after promiseConstructor is fully created)

    final thenFunction = JSNativeFunction(
      functionName: 'Promise.prototype.then',
      nativeImpl: (args) {
        var promise = args.isNotEmpty ? args[0] : null;
        // Support Promise subclasses with internal [[PromiseInstance]] slot
        if (promise is JSObject && promise is! JSPromise) {
          final internalPromise = promise.getInternalSlot(
            '[[PromiseInstance]]',
          );
          if (internalPromise is JSPromise) {
            promise = internalPromise;
          }
        }
        if (promise is! JSPromise) {
          throw JSTypeError(
            'Method Promise.prototype.then called on incompatible receiver',
          );
        }
        return PromisePrototype.then(args.sublist(1), promise);
      },
    );

    promisePrototype.defineProperty(
      'then',
      PropertyDescriptor(
        value: thenFunction,
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );

    final catchFunction = JSNativeFunction(
      functionName: 'Promise.prototype.catch',
      nativeImpl: (args) {
        var promise = args.isNotEmpty ? args[0] : null;
        // Support Promise subclasses with internal [[PromiseInstance]] slot
        if (promise is JSObject && promise is! JSPromise) {
          final internalPromise = promise.getInternalSlot(
            '[[PromiseInstance]]',
          );
          if (internalPromise is JSPromise) {
            promise = internalPromise;
          }
        }
        if (promise is! JSPromise) {
          throw JSTypeError(
            'Method Promise.prototype.catch called on incompatible receiver',
          );
        }
        return PromisePrototype.catch_(args.sublist(1), promise);
      },
    );

    promisePrototype.defineProperty(
      'catch',
      PropertyDescriptor(
        value: catchFunction,
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );

    final finallyFunction = JSNativeFunction(
      functionName: 'Promise.prototype.finally',
      nativeImpl: (args) {
        var promise = args.isNotEmpty ? args[0] : null;
        // Support Promise subclasses with internal [[PromiseInstance]] slot
        if (promise is JSObject && promise is! JSPromise) {
          final internalPromise = promise.getInternalSlot(
            '[[PromiseInstance]]',
          );
          if (internalPromise is JSPromise) {
            promise = internalPromise;
          }
        }
        if (promise is! JSPromise) {
          throw JSTypeError(
            'Method Promise.prototype.finally called on incompatible receiver',
          );
        }
        return PromisePrototype.finally_(args.sublist(1), promise);
      },
    );

    promisePrototype.defineProperty(
      'finally',
      PropertyDescriptor(
        value: finallyFunction,
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );

    // Definir le prototype sur le constructeur avec le bon descriptor
    // { writable: false, enumerable: false, configurable: false }
    promiseConstructor.defineProperty(
      'prototype',
      PropertyDescriptor(
        value: promisePrototype,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );

    // Set constructor property on the prototype to point back to the constructor
    promisePrototype.setProperty('constructor', promiseConstructor);

    // Add Symbol.toStringTag for Promise instances with proper descriptor
    // { writable: false, enumerable: false, configurable: true }
    promisePrototype.defineProperty(
      JSSymbol.toStringTag.toString(),
      PropertyDescriptor(
        value: JSValueFactory.string('Promise'),
        writable: false,
        enumerable: false,
        configurable: true,
      ),
    );

    // Configurer le prototype pour les instances JSPromise
    JSPromise.setPromisePrototype(promisePrototype);
  }

  /// Define Promise on globalThis with proper property descriptor
  void _definePromiseOnGlobalThis(JSGlobalThis globalThis) {
    try {
      final promiseConstructor = _globalEnvironment.get('Promise');
      globalThis.defineProperty(
        'Promise',
        PropertyDescriptor(
          value: promiseConstructor,
          writable: true,
          enumerable: false,
          configurable: true,
        ),
      );
    } catch (e) {
      // Promise not yet defined, ignore
    }
  }

  /// Define global constructor properties with correct descriptors
  void _defineGlobalProperties(JSGlobalThis globalThis) {
    // List of global constructors and objects that need proper property descriptors
    final globalProperties = [
      'Boolean',
      'Number',
      'String',
      'Array',
      'Object',
      'Function',
      'Date',
      'RegExp',
      'Error',
      'Math',
      'JSON',
      'Symbol',
      'Map',
      'Set',
      'WeakMap',
      'WeakSet',
      'Proxy',
      'Reflect',
      'Promise',
      'ArrayBuffer',
      'DataView',
      'Int8Array',
      'Uint8Array',
      'Uint8ClampedArray',
      'Int16Array',
      'Uint16Array',
      'Int32Array',
      'Uint32Array',
      'Float32Array',
      'Float64Array',
      'BigInt64Array',
      'BigUint64Array',
      // Global functions
      'eval',
      'parseInt',
      'parseFloat',
      'isNaN',
      'isFinite',
      'encodeURI',
      'encodeURIComponent',
      'decodeURI',
      'decodeURIComponent',
    ];

    for (final name in globalProperties) {
      try {
        final value = _globalEnvironment.get(name);
        globalThis.defineProperty(
          name,
          PropertyDescriptor(
            value: value,
            writable: true,
            enumerable: false,
            configurable: true,
          ),
        );
      } catch (e) {
        // Property not defined, skip
      }
    }
  }

  /// Define Promise on globalThis with proper property descriptor

  /// Configure l'objet WeakMap global
  void _setupWeakMapGlobal() {
    // Creer le constructeur WeakMap
    final weakMapConstructor = JSNativeFunction(
      functionName: 'WeakMap',
      nativeImpl: (args) {
        final weakMap = JSWeakMap();

        // If an iterable argument is provided, use it to initialize the WeakMap
        if (args.isNotEmpty) {
          final iterable = args[0];
          if (iterable is JSArray) {
            // Traiter chaque paire [key, value]
            for (final pair in iterable.elements) {
              if (pair is JSArray && pair.elements.length >= 2) {
                final key = pair.elements[0];
                final value = pair.elements[1];
                if (key is JSObject) {
                  weakMap.setValue(key, value);
                }
              }
            }
          }
        }

        return weakMap;
      },
      expectedArgs: 0,
      isConstructor: true, // WeakMap is a constructor
    );

    // Creer le prototype WeakMap
    final weakMapPrototype = JSObject();
    weakMapConstructor.setProperty('prototype', weakMapPrototype);

    // IMPORTANT: Ajouter la propriete constructor a WeakMap.prototype
    weakMapPrototype.setProperty('constructor', weakMapConstructor);

    // Add it to the global environment
    _globalEnvironment.define('WeakMap', weakMapConstructor, BindingType.var_);
  }

  /// Configure l'objet WeakSet global
  void _setupWeakSetGlobal() {
    // Creer le constructeur WeakSet
    final weakSetConstructor = JSNativeFunction(
      functionName: 'WeakSet',
      nativeImpl: (args) {
        final weakSet = JSWeakSet();

        // If an iterable argument is provided, use it to initialize the WeakSet
        if (args.isNotEmpty) {
          final iterable = args[0];
          if (iterable is JSArray) {
            // Add each value
            for (final value in iterable.elements) {
              if (value is JSObject) {
                weakSet.addValue(value);
              }
            }
          }
        }

        return weakSet;
      },
      expectedArgs: 0,
      isConstructor: true, // WeakSet is a constructor
    );

    // Creer le prototype WeakSet
    final weakSetPrototype = JSObject();
    weakSetConstructor.setProperty('prototype', weakSetPrototype);

    // IMPORTANT: Ajouter la propriete constructor a WeakSet.prototype
    weakSetPrototype.setProperty('constructor', weakSetConstructor);

    // Add it to the global environment
    _globalEnvironment.define('WeakSet', weakSetConstructor, BindingType.var_);
  }

  /// Configure the missing built-ins (WeakRef, FinalizationRegistry, DisposableStack, AsyncDisposableStack, Atomics)
  void _setupMissingBuiltins() {
    // WeakRef constructor
    final weakRefConstructor = createWeakRefConstructor();
    _globalEnvironment.define('WeakRef', weakRefConstructor, BindingType.var_);

    // FinalizationRegistry constructor
    final finalizationRegistryConstructor =
        createFinalizationRegistryConstructor();
    _globalEnvironment.define(
      'FinalizationRegistry',
      finalizationRegistryConstructor,
      BindingType.var_,
    );

    // DisposableStack constructor
    final disposableStackConstructor = createDisposableStackConstructor();
    _globalEnvironment.define(
      'DisposableStack',
      disposableStackConstructor,
      BindingType.var_,
    );

    // AsyncDisposableStack constructor
    final asyncDisposableStackConstructor =
        createAsyncDisposableStackConstructor();
    _globalEnvironment.define(
      'AsyncDisposableStack',
      asyncDisposableStackConstructor,
      BindingType.var_,
    );

    // Atomics object
    final atomicsObject = createAtomicsObject();
    _globalEnvironment.define('Atomics', atomicsObject, BindingType.var_);
  }

  /// Configure the global Proxy object
  void _setupProxyGlobal() {
    // Create the Proxy prototype
    final proxyPrototype = JSObject();

    // Create the Proxy constructor
    final proxyConstructor = JSNativeFunction(
      functionName: 'Proxy',
      nativeImpl: (args) {
        if (args.length < 2) {
          throw JSTypeError('Proxy constructor requires at least 2 arguments');
        }

        final target = args[0];
        final handler = args[1];

        final proxy = JSProxy(target, handler);
        // Set the internal prototype without triggering the setPrototypeOf trap
        proxy.setInternalPrototype(proxyPrototype);
        return proxy;
      },
      expectedArgs: 2,
      isConstructor: true, // Proxy is a constructor
    );

    // Proxy is not subclassable, so its prototype property should be undefined
    // This makes class P extends Proxy {} throw a TypeError
    proxyConstructor.setProperty('prototype', JSValueFactory.undefined());
    proxyPrototype.setProperty('constructor', proxyConstructor);

    // Add Proxy.revocable static method
    proxyConstructor.setProperty(
      'revocable',
      JSNativeFunction(
        functionName: 'Proxy.revocable',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError('Proxy.revocable requires at least 2 arguments');
          }

          final target = args[0];
          final handler = args[1];

          final proxy = JSProxy(target, handler);
          proxy.setInternalPrototype(proxyPrototype);

          // Create the revocable object with { proxy, revoke }
          final revocableObj = JSObject();
          revocableObj.setProperty('proxy', proxy);

          // Create the revoke function
          revocableObj.setProperty(
            'revoke',
            JSNativeFunction(
              functionName: 'revoke',
              nativeImpl: (revokeArgs) {
                return JSValueFactory.undefined();
              },
            ),
          );

          return revocableObj;
        },
      ),
    );

    // Add it to the global environment
    _globalEnvironment.define('Proxy', proxyConstructor, BindingType.var_);
  }

  /// Configure the global Reflect object
  void _setupReflectGlobal() {
    // Create Reflect
    final reflectObject = JSObject();

    // Reflect.get(target, propertyKey[, receiver])
    reflectObject.setProperty(
      'get',
      JSNativeFunction(
        functionName: 'Reflect.get',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError('Reflect.get requires at least 2 arguments');
          }

          final target = args[0];
          final propertyKey = args[1].toString();

          if (target is JSObject) {
            return target.getProperty(propertyKey);
          } else {
            throw JSTypeError('Reflect.get target must be an object');
          }
        },
      ),
    );

    // Reflect.set(target, propertyKey, value[, receiver])
    reflectObject.setProperty(
      'set',
      JSNativeFunction(
        functionName: 'Reflect.set',
        nativeImpl: (args) {
          if (args.length < 3) {
            throw JSTypeError('Reflect.set requires at least 3 arguments');
          }

          final target = args[0];
          final propertyKey = args[1].toString();
          final value = args[2];

          if (target is JSObject) {
            // Check if property exists with a descriptor and is not writable
            final descriptor = target.getOwnPropertyDescriptor(propertyKey);

            // If property exists with a descriptor and is not writable, return false
            if (descriptor != null &&
                descriptor.isData &&
                !descriptor.writable) {
              return JSValueFactory.boolean(false);
            }

            try {
              target.setProperty(propertyKey, value);
              return JSValueFactory.boolean(true);
            } on JSError {
              // Property assignment failed - return false per ES6 spec
              return JSValueFactory.boolean(false);
            }
          } else {
            throw JSTypeError('Reflect.set target must be an object');
          }
        },
      ),
    );

    // Reflect.has(target, propertyKey)
    reflectObject.setProperty(
      'has',
      JSNativeFunction(
        functionName: 'Reflect.has',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError('Reflect.has requires at least 2 arguments');
          }

          final target = args[0];
          final propertyKey = args[1].toString();

          if (target is JSObject) {
            return JSValueFactory.boolean(target.hasProperty(propertyKey));
          } else {
            throw JSTypeError('Reflect.has target must be an object');
          }
        },
      ),
    );

    // Reflect.deleteProperty(target, propertyKey)
    reflectObject.setProperty(
      'deleteProperty',
      JSNativeFunction(
        functionName: 'Reflect.deleteProperty',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError(
              'Reflect.deleteProperty requires at least 2 arguments',
            );
          }

          final target = args[0];
          final propertyKey = args[1].toString();

          if (target is JSObject) {
            final result = target.deleteProperty(propertyKey);
            return JSValueFactory.boolean(result);
          } else {
            throw JSTypeError(
              'Reflect.deleteProperty target must be an object',
            );
          }
        },
      ),
    );

    // Reflect.apply(target, thisArgument, argumentsList)
    reflectObject.setProperty(
      'apply',
      JSNativeFunction(
        functionName: 'Reflect.apply',
        nativeImpl: (args) {
          if (args.length < 3) {
            throw JSTypeError('Reflect.apply requires at least 3 arguments');
          }

          final target = args[0];
          final thisArgument = args[1];
          final argumentsList = args[2];

          if (target is! JSFunction) {
            throw JSTypeError('Reflect.apply target must be a function');
          }

          if (argumentsList is! JSArray) {
            throw JSTypeError('Reflect.apply argumentsList must be an array');
          }

          final evaluator = JSEvaluator.currentInstance;
          if (evaluator != null) {
            return evaluator.callFunction(
              target,
              argumentsList.elements,
              thisArgument,
            );
          } else {
            throw JSError('No evaluator available for Reflect.apply');
          }
        },
      ),
    );

    // Reflect.construct(target, argumentsList[, newTarget])
    reflectObject.setProperty(
      'construct',
      JSNativeFunction(
        functionName: 'Reflect.construct',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError(
              'Reflect.construct requires at least 2 arguments',
            );
          }

          final target = args[0];
          final argumentsList = args[1];
          final newTarget = args.length > 2 ? args[2] : target;

          // Check if target is a function
          if (target is! JSFunction) {
            throw JSTypeError('Reflect.construct target must be a function');
          }

          // Check if target is a constructor
          // For all function types, check isConstructor property
          if (!target.isConstructor) {
            throw JSTypeError('Reflect.construct target must be a constructor');
          }

          // Check if newTarget is a constructor (if provided)
          if (newTarget is! JSFunction) {
            throw JSTypeError(
              'Reflect.construct newTarget must be a constructor',
            );
          }
          if (!newTarget.isConstructor) {
            throw JSTypeError(
              'Reflect.construct newTarget must be a constructor',
            );
          }

          if (argumentsList is! JSArray) {
            throw JSTypeError(
              'Reflect.construct argumentsList must be an array',
            );
          }

          // Create new object and call function as constructor
          final newObject = JSObject();

          final evaluator = JSEvaluator.currentInstance;
          if (evaluator != null) {
            // For Promise constructor specifically, the spec says:
            // 1. If NewTarget is undefined, throw TypeError
            // 2. If IsCallable(executor) is false, throw TypeError
            // 3. OrdinaryCreateFromConstructor (gets prototype from newTarget)
            // So executor check happens BEFORE getting prototype

            if (target.functionName == 'Promise') {
              // Step 2: Check if executor is callable BEFORE getting prototype
              final executor = argumentsList.elements.isNotEmpty
                  ? argumentsList.elements[0]
                  : JSValueFactory.undefined();
              if (executor is! JSFunction &&
                  executor is! JSNativeFunction &&
                  executor is! JSBoundFunction) {
                throw JSTypeError('Promise executor must be a function');
              }
            }

            // Step 3: Get prototype from newTarget - this can throw any error
            // from a getter, and that error should propagate directly
            final prototypeValue = newTarget.getProperty('prototype');

            // Set prototype on newObject
            if (prototypeValue is JSObject) {
              newObject.setPrototype(prototypeValue);
            } else if (prototypeValue.isNull || prototypeValue.isUndefined) {
              // If newTarget.prototype is null/undefined, use intrinsic prototype
              // Get the intrinsic prototype from the target's realm
              final functionRealm = _getFunctionRealmHelper(newTarget);
              if (functionRealm != null) {
                final intrinsicProto = _getIntrinsicPrototypeHelper(
                  target.functionName,
                  functionRealm,
                );
                if (intrinsicProto != null) {
                  newObject.setPrototype(intrinsicProto);
                }
              }
            } else {
              // prototype is not an object and not null/undefined
              // Use intrinsic fallback
              final functionRealm = _getFunctionRealmHelper(newTarget);
              if (functionRealm != null) {
                final intrinsicProto = _getIntrinsicPrototypeHelper(
                  target.functionName,
                  functionRealm,
                );
                if (intrinsicProto != null) {
                  newObject.setPrototype(intrinsicProto);
                }
              }
            }

            // Now call the constructor
            try {
              final result = evaluator.callFunction(
                target,
                argumentsList.elements,
                newObject,
              );
              // Per ES6 spec: If constructor returns an object, use that.
              // Otherwise, use the created newObject.
              if (result is JSObject) {
                result.setProperty('constructor', newTarget);
                return result;
              }
              newObject.setProperty('constructor', newTarget);
              return newObject;
            } on JSTypeError catch (e) {
              // Convert Dart JSTypeError to JavaScript TypeError
              final errorValue = JSErrorObjectFactory.fromDartError(e);
              throw JSException(errorValue);
            }
          } else {
            throw JSError('No evaluator available for Reflect.construct');
          }
        },
      ),
    );

    // Reflect.getPrototypeOf(target)
    reflectObject.setProperty(
      'getPrototypeOf',
      JSNativeFunction(
        functionName: 'Reflect.getPrototypeOf',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSTypeError('Reflect.getPrototypeOf requires 1 argument');
          }

          final target = args[0];
          if (target is! JSObject) {
            throw JSTypeError(
              'Reflect.getPrototypeOf target must be an object',
            );
          }

          return target.getPrototype() ?? JSValueFactory.nullValue();
        },
      ),
    );

    // Reflect.setPrototypeOf(target, prototype)
    reflectObject.setProperty(
      'setPrototypeOf',
      JSNativeFunction(
        functionName: 'Reflect.setPrototypeOf',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError(
              'Reflect.setPrototypeOf requires at least 2 arguments',
            );
          }

          final target = args[0];
          final prototype = args[1];

          if (target is! JSObject) {
            throw JSTypeError(
              'Reflect.setPrototypeOf target must be an object',
            );
          }

          if (prototype is JSObject || prototype.type == JSValueType.nullType) {
            target.setPrototype(prototype as JSObject?);
            return JSValueFactory.boolean(true);
          } else {
            throw JSTypeError(
              'Reflect.setPrototypeOf prototype must be an object or null',
            );
          }
        },
      ),
    );

    // Reflect.isExtensible(target)
    reflectObject.setProperty(
      'isExtensible',
      JSNativeFunction(
        functionName: 'Reflect.isExtensible',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSTypeError('Reflect.isExtensible requires 1 argument');
          }

          final target = args[0];
          if (target is! JSObject) {
            throw JSTypeError('Reflect.isExtensible target must be an object');
          }

          // Check the actual extensibility flag on the object
          return JSValueFactory.boolean(target.isExtensible);
        },
      ),
    );

    // Reflect.preventExtensions(target)
    reflectObject.setProperty(
      'preventExtensions',
      JSNativeFunction(
        functionName: 'Reflect.preventExtensions',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSTypeError('Reflect.preventExtensions requires 1 argument');
          }

          final target = args[0];
          if (target is! JSObject) {
            throw JSTypeError(
              'Reflect.preventExtensions target must be an object',
            );
          }

          // Mark the object as non-extensible
          // Always returns true (it always succeeds in ES6)
          target.isExtensible = false;
          return JSValueFactory.boolean(true);
        },
      ),
    );

    // Reflect.getOwnPropertyDescriptor(target, propertyKey)
    reflectObject.setProperty(
      'getOwnPropertyDescriptor',
      JSNativeFunction(
        functionName: 'Reflect.getOwnPropertyDescriptor',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError(
              'Reflect.getOwnPropertyDescriptor requires at least 2 arguments',
            );
          }

          final target = args[0];
          final propertyKey = args[1].toString();

          if (target is! JSObject) {
            throw JSTypeError(
              'Reflect.getOwnPropertyDescriptor target must be an object',
            );
          }

          final descriptor = target.getOwnPropertyDescriptor(propertyKey);
          if (descriptor == null) {
            return JSValueFactory.undefined();
          }

          // Create property descriptor object
          final descObj = JSObject();
          if (descriptor.value != null) {
            descObj.setProperty('value', descriptor.value!);
          }
          if (descriptor.getter != null) {
            descObj.setProperty('get', descriptor.getter!);
          }
          if (descriptor.setter != null) {
            descObj.setProperty('set', descriptor.setter!);
          }
          descObj.setProperty(
            'writable',
            JSValueFactory.boolean(descriptor.writable),
          );
          descObj.setProperty(
            'enumerable',
            JSValueFactory.boolean(descriptor.enumerable),
          );
          descObj.setProperty(
            'configurable',
            JSValueFactory.boolean(descriptor.configurable),
          );

          return descObj;
        },
      ),
    );

    // Reflect.defineProperty(target, propertyKey, attributes)
    reflectObject.setProperty(
      'defineProperty',
      JSNativeFunction(
        functionName: 'Reflect.defineProperty',
        nativeImpl: (args) {
          if (args.length < 3) {
            throw JSTypeError(
              'Reflect.defineProperty requires at least 3 arguments',
            );
          }

          final target = args[0];
          final propertyKey = args[1].toString();
          final attributes = args[2];

          if (target is! JSObject) {
            throw JSTypeError(
              'Reflect.defineProperty target must be an object',
            );
          }

          if (attributes is! JSObject) {
            throw JSTypeError(
              'Reflect.defineProperty attributes must be an object',
            );
          }

          // Parse attributes
          final value = attributes.getProperty('value');
          final hasValue = attributes.hasProperty('value');
          final getter = attributes.getProperty('get');
          final setter = attributes.getProperty('set');
          final writable = attributes.getProperty('writable').toBoolean();
          final enumerable = attributes.getProperty('enumerable').toBoolean();
          final configurable = attributes
              .getProperty('configurable')
              .toBoolean();

          final descriptor = PropertyDescriptor(
            value: value != JSValueFactory.undefined() ? value : null,
            getter: getter is JSFunction ? getter : null,
            setter: setter is JSFunction ? setter : null,
            writable: writable,
            enumerable: enumerable,
            configurable: configurable,
            hasValueProperty: hasValue,
          );

          try {
            target.defineProperty(propertyKey, descriptor);
            return JSValueFactory.boolean(true);
          } on JSError {
            // Per ES6 spec, Reflect.defineProperty returns false on failure, not throw
            return JSValueFactory.boolean(false);
          }
        },
      ),
    );

    // Reflect.ownKeys(target)
    reflectObject.setProperty(
      'ownKeys',
      JSNativeFunction(
        functionName: 'Reflect.ownKeys',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSTypeError('Reflect.ownKeys requires 1 argument');
          }

          final target = args[0];
          if (target is! JSObject) {
            throw JSTypeError('Reflect.ownKeys target must be an object');
          }

          final keys = target.getPropertyNames();
          final result = JSArray();
          for (final key in keys) {
            result.elements.add(JSValueFactory.string(key));
          }
          return result;
        },
      ),
    );

    // Add it to the global environment
    _globalEnvironment.define('Reflect', reflectObject, BindingType.var_);
  }

  /// Configure the global Error objects
  void _setupErrorObjects() {
    // Create error constructors
    final errorConstructors = JSErrorObjectFactory.createErrorObject();

    // Add the constructors individually to the global environment
    _globalEnvironment.define(
      'Error',
      errorConstructors.getProperty('Error'),
      BindingType.var_,
    );
    _globalEnvironment.define(
      'TypeError',
      errorConstructors.getProperty('TypeError'),
      BindingType.var_,
    );
    _globalEnvironment.define(
      'ReferenceError',
      errorConstructors.getProperty('ReferenceError'),
      BindingType.var_,
    );
    _globalEnvironment.define(
      'SyntaxError',
      errorConstructors.getProperty('SyntaxError'),
      BindingType.var_,
    );
    _globalEnvironment.define(
      'RangeError',
      errorConstructors.getProperty('RangeError'),
      BindingType.var_,
    );
    _globalEnvironment.define(
      'EvalError',
      errorConstructors.getProperty('EvalError'),
      BindingType.var_,
    );
    _globalEnvironment.define(
      'URIError',
      errorConstructors.getProperty('URIError'),
      BindingType.var_,
    );
  }

  /// Configure l'objet Intl global
  void _setupIntlGlobal() {
    final intlObj = IntlObject.createIntlObject();
    _globalEnvironment.define('Intl', intlObj, BindingType.var_);
  }

  /// Configure l'objet Temporal global
  void _setupTemporalGlobal() {
    final temporalNamespace = getTemporalNamespace();
    _globalEnvironment.define('Temporal', temporalNamespace, BindingType.var_);
  }

  /// Configure les fonctions globales
  void _setupGlobalFunctions() {
    // Constantes globales
    _globalEnvironment.define(
      'NaN',
      JSValueFactory.number(double.nan),
      BindingType.var_,
    );
    _globalEnvironment.define(
      'Infinity',
      JSValueFactory.number(double.infinity),
      BindingType.var_,
    );
    _globalEnvironment.define(
      'undefined',
      JSValueFactory.undefined(),
      BindingType.var_,
    );

    // eval() - Evaluation de code dynamique
    _globalEnvironment.define(
      'eval',
      GlobalFunctions.createEval(),
      BindingType.var_,
    );

    // parseInt() - Conversion string vers entier
    _globalEnvironment.define(
      'parseInt',
      GlobalFunctions.createParseInt(),
      BindingType.var_,
    );

    // parseFloat() - Conversion string vers float
    _globalEnvironment.define(
      'parseFloat',
      GlobalFunctions.createParseFloat(),
      BindingType.var_,
    );

    // isNaN() - Test NaN
    _globalEnvironment.define(
      'isNaN',
      GlobalFunctions.createIsNaN(),
      BindingType.var_,
    );

    // isFinite() - Test finite
    _globalEnvironment.define(
      'isFinite',
      GlobalFunctions.createIsFinite(),
      BindingType.var_,
    );

    // URI encoding/decoding functions
    _globalEnvironment.define(
      'encodeURI',
      GlobalFunctions.createEncodeURI(),
      BindingType.var_,
    );
    _globalEnvironment.define(
      'decodeURI',
      GlobalFunctions.createDecodeURI(),
      BindingType.var_,
    );
    _globalEnvironment.define(
      'encodeURIComponent',
      GlobalFunctions.createEncodeURIComponent(),
      BindingType.var_,
    );
    _globalEnvironment.define(
      'decodeURIComponent',
      GlobalFunctions.createDecodeURIComponent(),
      BindingType.var_,
    );

    // sendMessage() - Bridge to Dart message system
    _globalEnvironment.define(
      'sendMessage',
      GlobalFunctions(_getInterpreterInstanceId).createSendMessage(),
      BindingType.var_,
    );

    // sendMessageAsync() - Async bridge to Dart message system
    _globalEnvironment.define(
      'sendMessageAsync',
      GlobalFunctions(_getInterpreterInstanceId).createSendMessageAsync(),
      BindingType.var_,
    );

    // setTimeout() - Schedule function execution after delay
    _globalEnvironment.define(
      'setTimeout',
      GlobalFunctions.createSetTimeout(),
      BindingType.var_,
    );

    // clearTimeout() - Cancel scheduled timeout
    _globalEnvironment.define(
      'clearTimeout',
      GlobalFunctions.createClearTimeout(),
      BindingType.var_,
    );
  }

  /// Evalue un programme JavaScript
  JSValue evaluate(Program program) {
    // Execute within the prototype manager's Zone to ensure proper prototype isolation
    return prototypeManager.runWithin(() {
      try {
        final result = visitProgram(program);
        return result;
      } catch (e) {
        if (e is FlowControlException) {
          // Une exception de controle de flux non geree
          if (e.type == ExceptionType.return_) {
            final result = e.value ?? JSValueFactory.undefined();
            return result;
          }
          throw JSError('Unexpected ${e.type.name}');
        }
        rethrow;
      }
    });
  }

  /// Throws a proper JavaScript SyntaxError that can be caught by JS code
  /// and has error.constructor === SyntaxError
  Never throwJSSyntaxError(String message) {
    final syntaxErrorCtor = _globalEnvironment.get('SyntaxError');
    if (syntaxErrorCtor is JSNativeFunction) {
      final errorObj = syntaxErrorCtor.call([JSValueFactory.string(message)]);
      if (errorObj is JSObject) {
        errorObj.setProperty('constructor', syntaxErrorCtor);
        final prototypeValue = syntaxErrorCtor.getProperty('prototype');
        if (prototypeValue is JSObject) {
          errorObj.setPrototype(prototypeValue);
        }
      }
      throw JSException(errorObj);
    }
    // Fallback
    throw JSSyntaxError(message);
  }

  /// Evalue un programme JavaScript dans le contexte d'un eval() direct
  /// Gere les conflits var/let selon ES6 EvalDeclarationInstantiation
  JSValue evaluateDirectEval(Program program) {
    // Get current lexical and variable environments
    final lexEnv = _currentContext().lexicalEnvironment;
    final varEnv = _currentContext().variableEnvironment;
    final isStrict = _currentContext().strictMode;
    final parameterNames = _currentContext().parameterNames;

    // ES6 18.2.1.3: EvalDeclarationInstantiation
    // In non-strict mode, check for var/let conflicts
    if (!isStrict) {
      // Collect var names from the eval code
      final varNames = _collectVarDeclaredNames(program);

      // Check if any var name conflicts with a lexical declaration
      // Walk up the lexical environment chain until we reach the variable environment
      Environment? currentLex = lexEnv;
      while (currentLex != null && !identical(currentLex, varEnv)) {
        for (final name in varNames) {
          if (currentLex.hasLocal(name)) {
            // Check if it's a let/const binding
            final binding = currentLex.getBinding(name);
            if (binding != null &&
                (binding.type == BindingType.let_ ||
                    binding.type == BindingType.const_)) {
              // Throw proper JavaScript SyntaxError
              throwJSSyntaxError(
                'Identifier \'$name\' has already been declared',
              );
            }
          }
        }
        currentLex = currentLex.parent;
      }

      // Check if any var name conflicts with parameter names (for eval in parameter defaults)
      // This is needed for eval("var x") when x is a parameter name being evaluated
      if (parameterNames != null) {
        for (final name in varNames) {
          if (parameterNames.contains(name)) {
            throwJSSyntaxError(
              'Identifier \'$name\' has already been declared',
            );
          }
        }
      }

      // Also check for conflicts with parameters in the variable environment
      // This is needed for eval("var x") when x is a parameter name
      for (final name in varNames) {
        if (varEnv.hasLocal(name)) {
          final binding = varEnv.getBinding(name);
          if (binding != null && binding.type == BindingType.parameter) {
            // ES6: In sloppy mode, eval can't redeclare a parameter
            throwJSSyntaxError(
              'Identifier \'$name\' has already been declared',
            );
          }
        }
      }
    }

    // Execute the eval code in current context
    return prototypeManager.runWithin(() {
      try {
        JSValue result = JSValueFactory.undefined();
        for (final stmt in program.body) {
          // EmptyStatement returns an empty completion; do not override
          // the running eval result with undefined for this case.
          if (stmt is EmptyStatement) {
            stmt.accept(this);
            continue;
          }
          result = stmt.accept(this);
        }
        return result;
      } catch (e) {
        if (e is FlowControlException) {
          if (e.type == ExceptionType.return_) {
            return e.value ?? JSValueFactory.undefined();
          }
          throw JSError('Unexpected ${e.type.name}');
        }
        rethrow;
      }
    });
  }

  /// Collecte tous les noms declares avec var dans un programme
  Set<String> _collectVarDeclaredNames(Program program) {
    final names = <String>{};
    for (final stmt in program.body) {
      _collectVarNamesFromStatement(stmt, names);
    }
    return names;
  }

  /// Collecte recursivement les noms var d'un statement
  void _collectVarNamesFromStatement(Statement stmt, Set<String> names) {
    if (stmt is VariableDeclaration && stmt.kind == 'var') {
      for (final decl in stmt.declarations) {
        if (decl.id is IdentifierPattern) {
          names.add((decl.id as IdentifierPattern).name);
        }
      }
    } else if (stmt is BlockStatement) {
      for (final s in stmt.body) {
        _collectVarNamesFromStatement(s, names);
      }
    } else if (stmt is IfStatement) {
      _collectVarNamesFromStatement(stmt.consequent, names);
      if (stmt.alternate != null) {
        _collectVarNamesFromStatement(stmt.alternate!, names);
      }
    } else if (stmt is WhileStatement) {
      _collectVarNamesFromStatement(stmt.body, names);
    } else if (stmt is DoWhileStatement) {
      _collectVarNamesFromStatement(stmt.body, names);
    } else if (stmt is ForStatement) {
      if (stmt.init is VariableDeclaration) {
        final varDecl = stmt.init as VariableDeclaration;
        if (varDecl.kind == 'var') {
          for (final decl in varDecl.declarations) {
            if (decl.id is IdentifierPattern) {
              names.add((decl.id as IdentifierPattern).name);
            }
          }
        }
      }
      _collectVarNamesFromStatement(stmt.body, names);
    } else if (stmt is ForInStatement) {
      if (stmt.left is VariableDeclaration) {
        final varDecl = stmt.left as VariableDeclaration;
        if (varDecl.kind == 'var') {
          for (final decl in varDecl.declarations) {
            if (decl.id is IdentifierPattern) {
              names.add((decl.id as IdentifierPattern).name);
            }
          }
        }
      }
      _collectVarNamesFromStatement(stmt.body, names);
    } else if (stmt is ForOfStatement) {
      if (stmt.left is VariableDeclaration) {
        final varDecl = stmt.left as VariableDeclaration;
        if (varDecl.kind == 'var') {
          for (final decl in varDecl.declarations) {
            if (decl.id is IdentifierPattern) {
              names.add((decl.id as IdentifierPattern).name);
            }
          }
        }
      }
      _collectVarNamesFromStatement(stmt.body, names);
    } else if (stmt is TryStatement) {
      _collectVarNamesFromStatement(stmt.block, names);
      if (stmt.handler != null) {
        _collectVarNamesFromStatement(stmt.handler!.body, names);
      }
      if (stmt.finalizer != null) {
        _collectVarNamesFromStatement(stmt.finalizer!, names);
      }
    } else if (stmt is SwitchStatement) {
      for (final c in stmt.cases) {
        for (final s in c.consequent) {
          _collectVarNamesFromStatement(s, names);
        }
      }
    }
    // FunctionDeclaration doesn't hoist its var names to eval scope
  }

  /// Collecte les noms de variables d'un pattern (destructuring)
  void _collectPatternNames(Pattern pattern, Set<String> names) {
    if (pattern is IdentifierPattern) {
      names.add(pattern.name);
    } else if (pattern is ObjectPattern) {
      for (final prop in pattern.properties) {
        _collectPatternNames(prop.value, names);
      }
      if (pattern.restElement != null) {
        _collectPatternNames(pattern.restElement!, names);
      }
    } else if (pattern is ArrayPattern) {
      for (final element in pattern.elements) {
        if (element != null) {
          _collectPatternNames(element, names);
        }
      }
      if (pattern.restElement != null) {
        _collectPatternNames(pattern.restElement!, names);
      }
    } else if (pattern is AssignmentPattern) {
      _collectPatternNames(pattern.left, names);
    }
  }

  /// Evalue une chaine de code JavaScript
  static JSValue evaluateString(String code) {
    try {
      final program = JSParser.parseString(code);
      final evaluator = JSEvaluator(
        getInterpreterInstanceId: _getInterpreterInstanceId,
      );
      final result = evaluator.evaluate(program);
      return result;
    } catch (e) {
      if (e is JSError) rethrow;
      throw JSError('Evaluation error: $e');
    }
  }

  JSNativeFunction _createSuperFunction(
    JSClass superClass,
    JSObject thisObject,
  ) {
    final evaluator = this;
    return JSNativeFunction(
      functionName: 'super',
      nativeImpl: (args) {
        // Check if super() was already called BEFORE attempting to call it again
        final superAlreadyCalled = evaluator._isSuperCalled();

        // Mark that super() was called - BEFORE executing the super constructor
        // This allows the derived class to use `this` after super() returns
        evaluator._markSuperCalled();

        if (superClass.constructor != null) {
          final superCtorFunction = superClass.constructor!;
          final superDeclaration = superCtorFunction.declaration;
          final superFunctionEnv = Environment(
            parent: superCtorFunction.closureEnvironment,
          );

          // Create arguments object (array-like) for super constructor
          final argumentsObject = JSValueFactory.argumentsObject({});
          // Mark the arguments object so that callee/caller access throws
          argumentsObject.markAsArgumentsObject();
          argumentsObject.setProperty(
            'length',
            JSValueFactory.number(args.length.toDouble()),
          );
          for (int i = 0; i < args.length; i++) {
            argumentsObject.setProperty(i.toString(), args[i]);
          }
          superFunctionEnv.define(
            'arguments',
            argumentsObject,
            BindingType.var_,
          );

          // Bind super constructor parameters
          final superParams = superDeclaration?.params;
          if (superParams != null) {
            for (int i = 0; i < superParams.length; i++) {
              final param = superParams[i];
              if (param?.name == null) continue;

              JSValue argValue;
              if (i < args.length) {
                argValue = args[i];
              } else {
                argValue = JSValueFactory.undefined();
              }

              // Ne pas afficher de logs pour les parametres
              superFunctionEnv.define(
                param.name!.name,
                argValue,
                BindingType.parameter,
              );
            }
          }

          // If the superclass itself has a superclass, create its super function recursively
          if (superClass.superClass != null) {
            final superOfSuperConstructor = _createSuperFunction(
              superClass.superClass!,
              thisObject,
            );
            superFunctionEnv.define(
              'super',
              superOfSuperConstructor,
              BindingType.var_,
            );
          }

          // Executer le super constructor avec le meme this
          final superContext = ExecutionContext(
            lexicalEnvironment: superFunctionEnv,
            variableEnvironment: superFunctionEnv,
            thisBinding: thisObject,
          );

          _executionStack.push(superContext);
          // Push a new constructor level for the super constructor
          evaluator._pushConstructorLevel();
          // Push the parent class context
          evaluator._pushClassContext(superClass);
          try {
            final result = superDeclaration.body.accept(this);
            // AFTER the parent constructor executed, check if super() was already called
            // If it was, throw the error now
            if (superAlreadyCalled) {
              throw JSReferenceError(
                'super() called multiple times in constructor',
              );
            }
            return result;
          } on FlowControlException catch (e) {
            // Handle explicit returns from super constructor
            if (e.type == ExceptionType.return_ && e.value != null) {
              // Check if super() was already called
              if (superAlreadyCalled) {
                throw JSReferenceError(
                  'super() called multiple times in constructor',
                );
              }
              // If super constructor returned an object, update the derived constructor's this binding
              if (e.value is JSObject && e.value!.type == JSValueType.object) {
                // Update the constructor's this binding on the stack if we're in a constructor
                if (evaluator._constructorThisStack.isNotEmpty) {
                  evaluator._constructorThisStack[evaluator
                              ._constructorThisStack
                              .length -
                          1] =
                      e.value!;
                }
                return e.value!;
              }
              // For non-object returns, return undefined (per spec)
              return JSValueFactory.undefined();
            }
            // For other flow control (shouldn't happen in constructor), rethrow
            rethrow;
          } finally {
            evaluator._popConstructorLevel(); // Pop the super constructor level
            evaluator._popClassContext(); // Pop the parent class context
            _executionStack.pop();
          }
        } else if (superClass.superClass != null) {
          // Pas de constructor explicite, mais il y a une superclass
          // En ES6, le comportement par defaut est d'appeler super(...args)
          // Create the super function for the grandparent
          final superOfSuperConstructor = _createSuperFunction(
            superClass.superClass!,
            thisObject,
          );

          // Push a constructor level for this implicit super call
          evaluator._pushConstructorLevel();

          try {
            // Appeler le super constructor
            // This will check that super wasn't called (on the new level), mark it, then recurse
            final result = superOfSuperConstructor.call(args);
            // BUGFIX: After implicit super call, we should NOT mark the current level as called
            // because we're delegating to the grandparent constructor.
            // However, the marking already happened at the start of this nativeImpl (line 5466)
            // So we don't need to do anything else.
            return result;
          } finally {
            evaluator._popConstructorLevel();
          }
        }
        return JSValueFactory.undefined();
      },
    );
  }

  /// Helper: Check if super() was called in current constructor level
  bool _isSuperCalled() {
    if (_superCalledStack.isEmpty) {
      return false;
    }
    final result = _superCalledStack.last;
    return result;
  }

  /// Helper: Mark super() as called in current constructor level
  void _markSuperCalled() {
    if (_superCalledStack.isNotEmpty) {
      _superCalledStack[_superCalledStack.length - 1] = true;
    }
  }

  /// Helper: Push a new constructor level onto the stack
  void _pushConstructorLevel() {
    _superCalledStack.add(false);
  }

  /// Helper: Pop a constructor level from the stack
  void _popConstructorLevel() {
    if (_superCalledStack.isNotEmpty) {
      _superCalledStack.removeLast();
    }
  }

  // ===== VISITOR IMPLEMENTATIONS =====

  /// Detecte si un bloc de code commence par une directive "use strict"
  /// Selon la spec ECMAScript, une directive est une ExpressionStatement
  /// contenant un LiteralExpression de type 'string' comme premiere instruction
  bool _detectStrictMode(List<Statement> statements) {
    if (statements.isEmpty) return false;

    final firstStmt = statements.first;
    if (firstStmt is! ExpressionStatement) return false;

    final expr = firstStmt.expression;
    if (expr is! LiteralExpression) return false;

    // Check if it's a string with the value "use strict"
    return expr.type == 'string' && expr.value == 'use strict';
  }

  @override
  JSValue visitProgram(Program node) {
    JSValue lastValue = JSValueFactory.undefined();

    // Detecter le strict mode au niveau du programme
    final isStrict = _detectStrictMode(node.body);

    // If strict mode detected, update the global context
    if (isStrict && !_executionStack.isEmpty) {
      final currentCtx = _currentContext();
      // Create nouveau contexte avec strictMode active
      final strictContext = ExecutionContext(
        lexicalEnvironment: currentCtx.lexicalEnvironment,
        variableEnvironment: currentCtx.variableEnvironment,
        thisBinding: currentCtx.thisBinding,
        strictMode: true,
        debugName: currentCtx.debugName,
      );
      _executionStack.pop();
      _executionStack.push(strictContext);
    }

    // Hoisting pass - scanner les declarations
    _hoistDeclarations(node.body);

    // Executer les instructions
    for (final stmt in node.body) {
      // Per ES spec: EmptyStatement completes with empty and should not
      // overwrite the running completion value. Preserve lastValue.
      if (stmt is EmptyStatement) {
        // Execute for side effects (none) but don't update lastValue
        stmt.accept(this);
        continue;
      }
      lastValue = stmt.accept(this);
    }

    return lastValue;
  }

  /// Systeme de modules ES6
  final Map<String, JSModule> _modules = {};

  /// Callback pour charger le contenu d'un module (web-compatible)
  Future<String> Function(String moduleId)? moduleLoader;

  /// Callback pour resoudre les chemins de modules
  String Function(String moduleId, String? importer)? moduleResolver;

  /// Etats de chargement pour detecter les dependances circulaires
  final Set<String> _loadingModules = {};

  /// Cache des Futures de chargement de modules pour eviter les doublons
  final Map<String, Future<JSModule>> _moduleLoadingFutures = {};
  final Set<String> _loadedModules = {};

  /// Module actuellement en cours d'evaluation
  JSModule? _currentModule;

  /// URL du module actuellement en cours d'evaluation (pour import.meta)
  String? _currentModuleUrl;

  /// Detecte si un module contient des top-level await (ES2022)
  ///
  /// Cette methode parcourt l'AST du module pour trouver des AwaitExpression
  /// au niveau racine du module (pas a l'interieur de fonctions).
  /// Retourne true si le module contient du top-level await.
  bool _detectTopLevelAwait(Program program) {
    // Parcourir les statements du module pour detecter await au top-level
    for (final statement in program.body) {
      if (_statementHasTopLevelAwait(statement)) {
        return true;
      }
    }

    return false;
  }

  /// Verifie si un statement contient un top-level await (pas dans une fonction)
  bool _statementHasTopLevelAwait(Statement statement) {
    // Variable declarations: const x = await ...
    if (statement is VariableDeclaration) {
      for (final declarator in statement.declarations) {
        if (declarator.init != null &&
            _expressionContainsAwait(declarator.init!)) {
          return true;
        }
      }
    }

    // Expression statements: await ...
    if (statement is ExpressionStatement) {
      return _expressionContainsAwait(statement.expression);
    }

    // If statements: if (await ...)
    if (statement is IfStatement) {
      if (_expressionContainsAwait(statement.test)) return true;
      // Ne pas checker les bodies car ils peuvent contenir des fonctions
    }

    // For/While loops: for (...; await ...; ...)
    if (statement is ForStatement) {
      if (statement.init != null && statement.init is Expression) {
        if (_expressionContainsAwait(statement.init as Expression)) return true;
      }
      if (statement.test != null && _expressionContainsAwait(statement.test!)) {
        return true;
      }
      if (statement.update != null &&
          _expressionContainsAwait(statement.update!)) {
        return true;
      }
    }

    if (statement is WhileStatement) {
      if (_expressionContainsAwait(statement.test)) return true;
    }

    if (statement is DoWhileStatement) {
      if (_expressionContainsAwait(statement.test)) return true;
    }

    // For-in/of: for (x of await ...)
    if (statement is ForOfStatement || statement is ForInStatement) {
      final forStmt = statement as dynamic;
      if (_expressionContainsAwait(forStmt.right)) return true;
    }

    // Return/Throw: return await ...
    if (statement is ReturnStatement && statement.argument != null) {
      return _expressionContainsAwait(statement.argument!);
    }

    if (statement is ThrowStatement) {
      return _expressionContainsAwait(statement.argument);
    }

    return false;
  }

  /// Verifie si une expression contient await (sans descendre dans les fonctions)
  bool _expressionContainsAwait(Expression expr) {
    // Direct await expression
    if (expr is AwaitExpression) {
      return true;
    }

    // Ne pas descendre dans les fonctions
    if (expr is FunctionExpression ||
        expr is ArrowFunctionExpression ||
        expr is AsyncArrowFunctionExpression) {
      return false;
    }

    // Binary/Logical: await x + y
    if (expr is BinaryExpression) {
      return _expressionContainsAwait(expr.left) ||
          _expressionContainsAwait(expr.right);
    }

    // Unary: !await x
    if (expr is UnaryExpression) {
      return _expressionContainsAwait(expr.operand);
    }

    // Conditional: (await x) ? y : z
    if (expr is ConditionalExpression) {
      return _expressionContainsAwait(expr.test) ||
          _expressionContainsAwait(expr.consequent) ||
          _expressionContainsAwait(expr.alternate);
    }

    // Assignment: x = await y
    if (expr is AssignmentExpression) {
      return _expressionContainsAwait(expr.right);
    }

    // Call: fn(await x)
    if (expr is CallExpression) {
      if (_expressionContainsAwait(expr.callee)) return true;
      for (final arg in expr.arguments) {
        if (_expressionContainsAwait(arg)) return true;
      }
      return false;
    }

    // New: new Cls(await x)
    if (expr is NewExpression) {
      for (final arg in expr.arguments) {
        if (_expressionContainsAwait(arg)) return true;
      }
      return false;
    }

    // Member: (await x).prop
    if (expr is MemberExpression) {
      return _expressionContainsAwait(expr.object);
    }

    // Array: [await x, y]
    if (expr is ArrayExpression) {
      for (final element in expr.elements) {
        if (element != null && _expressionContainsAwait(element)) return true;
      }
      return false;
    }

    // Object: {x: await y}
    if (expr is ObjectExpression) {
      for (final prop in expr.properties) {
        if (prop.value is Expression && _expressionContainsAwait(prop.value)) {
          return true;
        }
      }
      return false;
    }

    // Sequence: (x, await y)
    if (expr is SequenceExpression) {
      for (final e in expr.expressions) {
        if (_expressionContainsAwait(e)) return true;
      }
      return false;
    }

    // Spread: [...await x]
    if (expr is SpreadElement) {
      return _expressionContainsAwait(expr.argument);
    }

    // Template: `${await x}`
    if (expr is TemplateLiteralExpression) {
      for (final e in expr.expressions) {
        if (_expressionContainsAwait(e)) return true;
      }
      return false;
    }

    return false;
  }

  /// Charge un module avec gestion des dependances circulaires
  Future<JSModule> _loadModuleAsync(String moduleId, [String? importer]) async {
    // Resoudre le chemin du module si un resolver est fourni
    final resolvedId = moduleResolver?.call(moduleId, importer) ?? moduleId;

    // Check if the module is already loaded
    if (_modules.containsKey(resolvedId)) {
      final module = _modules[resolvedId]!;
      if (module.isLoaded) {
        return module;
      }
    }

    // Check if the module is already being loaded
    // If yes, return the existing Future to avoid double loading
    if (_moduleLoadingFutures.containsKey(resolvedId)) {
      return _moduleLoadingFutures[resolvedId]!;
    }

    // Create Future pour le chargement de ce module
    final loadingFuture = _loadModuleImpl(resolvedId);
    _moduleLoadingFutures[resolvedId] = loadingFuture;

    try {
      final module = await loadingFuture;
      return module;
    } finally {
      // Retirer du cache une fois charge
      _moduleLoadingFutures.remove(resolvedId);
    }
  }

  /// Implementation reelle du chargement de module
  Future<JSModule> _loadModuleImpl(String resolvedId) async {
    // Marquer le module comme en cours de chargement
    _loadingModules.add(resolvedId);

    try {
      final module = JSModule(resolvedId, _globalEnvironment);
      _modules[resolvedId] = module;

      // Charger le contenu du module
      if (moduleLoader == null) {
        throw JSError(
          'No module loader provided. Set moduleLoader callback to enable module loading.',
        );
      }

      final sourceCode = await moduleLoader!(resolvedId);

      // Parser le code du module
      final ast = JSParser.parseString(sourceCode);
      module.ast = ast;

      // ES2022: Detecter si le module contient du top-level await
      module.hasTopLevelAwait = _detectTopLevelAwait(ast);

      // If the module has top-level await, mark its status as evaluatingAsync
      if (module.hasTopLevelAwait) {
        module.status = ModuleStatus
            .linked; // Will become evaluatingAsync during evaluation
      }

      // Evaluer le module dans son propre environnement
      await _evaluateModule(module);

      // Marquer comme charge
      module.isLoaded = true;
      _loadedModules.add(resolvedId);

      return module;
    } finally {
      _loadingModules.remove(resolvedId);
    }
  }

  /// Evalue un module avec top-level await en utilisant le systeme AsyncTask
  ///
  /// ES2022: Wrappe le code du module dans une fonction async qui est executee
  /// avec notre systeme AsyncTask existant. Cela permet au top-level await
  /// de fonctionner correctement avec le mecanisme de suspension/reprise.
  Future<void> _evalModuleAsync(JSModule module) async {
    final ast = module.ast!;
    final completer = Completer<void>();

    // Createe fonction async wrapper pour le module
    final taskId =
        'module_${module.id}_${DateTime.now().millisecondsSinceEpoch}';
    final asyncTask = AsyncTask(taskId);

    // Createe continuation qui execute le code du module
    final continuation = AsyncContinuation(
      // Create AsyncFunctionDeclaration fictif qui contient le code du module
      AsyncFunctionDeclaration(
        id: IdentifierExpression(name: '__moduleWrapper__', line: 0, column: 0),
        params: [],
        body: BlockStatement(body: ast.body, line: 0, column: 0),
        line: 0,
        column: 0,
      ),
      [], // Pas d'arguments
      module.environment, // Generator execution environment
      JSNativeFunction(
        functionName: 'moduleResolve',
        nativeImpl: (args) {
          completer.complete();
          return JSValueFactory.undefined();
        },
      ),
      JSNativeFunction(
        functionName: 'moduleReject',
        nativeImpl: (args) {
          final error = args.isNotEmpty
              ? args[0]
              : JSValueFactory.string('Module evaluation failed');
          completer.completeError(error);
          return JSValueFactory.undefined();
        },
      ),
      _currentModuleUrl, // Module URL for import.meta
    );

    asyncTask.setContinuation(continuation);
    _asyncScheduler.addTask(asyncTask);

    // Demarrer l'execution asynchrone
    _executeAsyncFunction(asyncTask);

    // Attendre la completion
    try {
      await completer.future;
    } catch (e) {
      // Propager l'erreur
      rethrow;
    }
  }

  /// Evalue un module dans son propre environnement
  ///
  /// ES2022: Si le module contient du top-level await, l'evaluation devient
  /// asynchrone et attend les Promises rencontrees.
  Future<void> _evaluateModule(JSModule module) async {
    if (module.ast == null) return;

    // Sauvegarder le module actuel et son URL
    final previousModule = _currentModule;
    final previousModuleUrl = _currentModuleUrl;
    _currentModule = module;
    _currentModuleUrl = 'file:///${module.id}';

    // Create contexte d'execution pour le module
    final moduleContext = ExecutionContext(
      lexicalEnvironment: module.environment,
      variableEnvironment: module.environment,
      thisBinding: JSValueFactory.undefined(),
      strictMode: false,
      debugName: module.hasTopLevelAwait
          ? 'AsyncModule(${module.id})'
          : 'Module(${module.id})',
    );

    _executionStack.push(moduleContext);

    try {
      // ES2022: Marquer le statut selon le type de module
      module.status = module.hasTopLevelAwait
          ? ModuleStatus.evaluatingAsync
          : ModuleStatus.evaluating;

      // Evaluer le programme du module
      if (module.hasTopLevelAwait) {
        // Top-level await: wrappe dans une fonction async et utilise AsyncTask
        await _evalModuleAsync(module);
      } else {
        // Module synchrone: evaluation normale
        module.ast!.accept(this);
      }

      module.status = ModuleStatus.evaluated;
    } catch (e) {
      module.status = ModuleStatus.error;
      module.evaluationError = e is JSValue
          ? e
          : JSValueFactory.string(e.toString());
      rethrow;
    } finally {
      // Restaurer l'environnement et le module precedents
      _executionStack.pop();
      _currentModule = previousModule;
      _currentModuleUrl = previousModuleUrl;
    }
  }

  /// Precharge un module de maniere asynchrone
  Future<JSModule> loadModule(String moduleId, [String? importer]) {
    return _loadModuleAsync(moduleId, importer);
  }

  /// Configure le loader de modules
  void setModuleLoader(Future<String> Function(String moduleId) loader) {
    moduleLoader = loader;
  }

  /// Configure le resolver de modules
  void setModuleResolver(
    String Function(String moduleId, String? importer) resolver,
  ) {
    moduleResolver = resolver;
  }

  /// Version synchrone pour les imports statiques (module doit etre precharge)
  JSModule _loadModule(String moduleId) {
    if (_modules.containsKey(moduleId)) {
      final module = _modules[moduleId]!;
      if (!module.isLoaded) {
        throw JSError(
          'Module $moduleId is not loaded. Use loadModule() to load it first.',
        );
      }
      return module;
    }

    throw JSError(
      'Module $moduleId not found. Use loadModule() to load it first.',
    );
  }

  /// Obtient les exports d'un module
  JSValue _getModuleExports(String moduleId) {
    final module = _loadModule(moduleId);
    final exports = JSValueFactory.createObject();

    // Copier tous les exports nommes
    for (final entry in module.exports.entries) {
      exports.setProperty(entry.key, entry.value);
    }

    // Add the default export if present
    if (module.defaultExport != null) {
      exports.setProperty('default', module.defaultExport!);
    }

    return exports;
  }

  /// Import dynamique (import('module'))
  @override
  JSValue visitImportExpression(ImportExpression node) {
    final sourceValue = node.source.accept(this);
    if (!sourceValue.isString) {
      throw JSTypeError('Module specifier must be a string');
    }

    final moduleId = sourceValue.toString();

    // Return a Promise that resolves with the module's exports
    final promise = JSValueFactory.createPromise();

    // Charger le module de maniere asynchrone
    _loadModuleAsync(moduleId)
        .then((module) {
          // Utiliser module.id (resolu) au lieu de moduleId (original)
          final exports = _getModuleExports(module.id);
          promise.resolve(exports);
        })
        .catchError((error) {
          promise.reject(JSValueFactory.string(error.toString()));
        });

    return promise;
  }

  /// Propriete meta (import.meta)
  @override
  JSValue visitMetaProperty(MetaProperty node) {
    // import.meta
    if (node.meta == 'import' && node.property == 'meta') {
      // Create import.meta avec la propriete url
      final metaObject = JSValueFactory.object();

      // If we have a current module, use its URL
      // Sinon, utiliser une URL par defaut
      final currentModuleUrl = _currentModuleUrl ?? 'file:///unknown';
      metaObject.setProperty('url', JSValueFactory.string(currentModuleUrl));

      return metaObject;
    }

    // new.target
    if (node.meta == 'new' && node.property == 'target') {
      // new.target returns the function/class that was called with 'new'
      // Returns undefined if not in a constructor context
      if (!_executionStack.isEmpty) {
        final context = _executionStack.current;
        if (context.newTarget != null) {
          return context.newTarget!;
        }
      }
      return JSValueFactory.undefined();
    }

    throw JSReferenceError(
      'Unsupported meta property: ${node.meta}.${node.property}',
    );
  }

  /// Declaration d'import
  @override
  JSValue visitImportDeclaration(ImportDeclaration node) {
    final moduleId = node.source.value as String;
    final module = _loadModule(moduleId);
    final env = _currentEnvironment();

    // Traiter l'import par defaut
    if (node.defaultSpecifier != null) {
      final defaultValue = module.defaultExport ?? JSValueFactory.undefined();
      env.define(
        node.defaultSpecifier!.local.name,
        defaultValue,
        BindingType.const_,
      );
    }

    // Traiter les imports nommes
    for (final specifier in node.namedSpecifiers) {
      final exportName = specifier.imported.name;
      final localName = specifier.local?.name ?? exportName;

      final exportValue =
          module.exports[exportName] ?? JSValueFactory.undefined();
      env.define(localName, exportValue, BindingType.const_);
    }

    // Traiter l'import namespace (* as name)
    if (node.namespaceSpecifier != null) {
      final namespaceObject = _getModuleExports(moduleId);
      env.define(
        node.namespaceSpecifier!.local.name,
        namespaceObject,
        BindingType.const_,
      );
    }

    return JSValueFactory.undefined();
  }

  /// Declaration d'export nomme
  @override
  JSValue visitExportNamedDeclaration(ExportNamedDeclaration node) {
    final env = _currentEnvironment();

    // If it's a re-export from another module
    if (node.source != null) {
      final moduleId = node.source!.value as String;
      final sourceModule = _loadModule(moduleId);

      for (final specifier in node.specifiers) {
        final localName = specifier.local.name;
        final exportedName = specifier.exported.name;

        final value =
            sourceModule.exports[localName] ?? JSValueFactory.undefined();
        if (_currentModule != null) {
          _currentModule!.exports[exportedName] = value;
        }
      }
    } else {
      // Export depuis le scope local
      for (final specifier in node.specifiers) {
        final localName = specifier.local.name;
        final exportedName = specifier.exported.name;

        final value = env.get(localName);
        if (_currentModule != null) {
          _currentModule!.exports[exportedName] = value;
        }
      }
    }

    return JSValueFactory.undefined();
  }

  /// Export par defaut
  @override
  JSValue visitExportDefaultDeclaration(ExportDefaultDeclaration node) {
    JSValue value;
    final currentEnv = _currentEnvironment();

    // Cas special pour export default class: on extrait la classe de la IIFE
    if (node.declaration is CallExpression) {
      final callExpr = node.declaration as CallExpression;
      if (callExpr.callee is FunctionExpression) {
        final funcExpr = callExpr.callee as FunctionExpression;
        final block = funcExpr.body;
        // Chercher une ClassDeclaration dans le bloc
        for (final stmt in block.body) {
          if (stmt is ClassDeclaration) {
            // Evaluer la classe directement
            JSClass? superClass;
            JSFunction? superFunction;
            if (stmt.superClass != null) {
              final superValue = stmt.superClass!.accept(this);
              if (superValue is JSClass) {
                superClass = superValue;
              } else if (superValue is JSFunction) {
                superFunction = superValue;
              }
            }
            value = JSValueFactory.classValue(
              stmt,
              currentEnv,
              superClass,
              superFunction,
            );
            // Definir la classe dans l'environnement pour qu'elle soit accessible
            if (stmt.id != null) {
              currentEnv.define(stmt.id!.name, value, BindingType.let_);
            }
            if (_currentModule != null) {
              _currentModule!.defaultExport = value;
            }
            return JSValueFactory.undefined();
          }
        }
      }
    }

    // Cas normal: evaluer l'expression
    value = node.declaration.accept(this);

    // If it's a function or async function with a name, define it in the environment
    if (node.declaration is FunctionExpression) {
      final funcExpr = node.declaration as FunctionExpression;
      if (funcExpr.id != null) {
        currentEnv.define(funcExpr.id!.name, value, BindingType.let_);
      }
    } else if (node.declaration is AsyncFunctionExpression) {
      final funcExpr = node.declaration as AsyncFunctionExpression;
      if (funcExpr.id != null) {
        currentEnv.define(funcExpr.id!.name, value, BindingType.let_);
      }
    } else if (node.declaration is ClassExpression) {
      // Handle export default class (with a name)
      final classExpr = node.declaration as ClassExpression;
      if (classExpr.id != null) {
        currentEnv.define(classExpr.id!.name, value, BindingType.let_);
      }
    }

    if (_currentModule != null) {
      _currentModule!.defaultExport = value;
    }
    return JSValueFactory.undefined();
  }

  /// Export de tous les exports d'un module
  @override
  JSValue visitExportAllDeclaration(ExportAllDeclaration node) {
    final moduleId = node.source.value as String;
    final sourceModule = _loadModule(moduleId);

    for (final entry in sourceModule.exports.entries) {
      if (_currentModule != null) {
        _currentModule!.exports[entry.key] = entry.value;
      }
    }

    if (sourceModule.defaultExport != null && _currentModule != null) {
      _currentModule!.defaultExport = sourceModule.defaultExport!;
    }

    return JSValueFactory.undefined();
  }

  /// Export de declaration (export const/let/var/function/class)
  @override
  JSValue visitExportDeclaration(ExportDeclaration node) {
    if (node is ExportDeclarationStatement) {
      // Executer la declaration normalement
      final result = node.declaration.accept(this);

      // If it's a function or class declaration, export it
      if (node.declaration is FunctionDeclaration) {
        final funcDecl = node.declaration as FunctionDeclaration;
        if (_currentModule != null) {
          _currentModule!.exports[funcDecl.id.name] = result;
        }
      } else if (node.declaration is AsyncFunctionDeclaration) {
        final funcDecl = node.declaration as AsyncFunctionDeclaration;
        if (_currentModule != null) {
          _currentModule!.exports[funcDecl.id.name] = result;
        }
      } else if (node.declaration is ClassDeclaration) {
        final classDecl = node.declaration as ClassDeclaration;
        if (_currentModule != null && classDecl.id != null) {
          _currentModule!.exports[classDecl.id!.name] = result;
        }
      } else if (node.declaration is VariableDeclaration) {
        final varDecl = node.declaration as VariableDeclaration;
        // Exporter toutes les variables declarees
        for (final decl in varDecl.declarations) {
          if (decl.id is IdentifierPattern) {
            final name = (decl.id as IdentifierPattern).name;
            final value = decl.init?.accept(this) ?? JSValueFactory.undefined();
            if (_currentModule != null) {
              _currentModule!.exports[name] = value;
            }
          }
        }
      }

      return result;
    }

    throw UnsupportedError(
      'Unsupported export declaration type: ${node.runtimeType}',
    );
  }

  /// Visiteurs pour les specificateurs (pas utilises directement)
  @override
  JSValue visitImportSpecifier(ImportSpecifier node) {
    throw UnsupportedError('ImportSpecifier should not be visited directly');
  }

  @override
  JSValue visitImportDefaultSpecifier(ImportDefaultSpecifier node) {
    throw UnsupportedError(
      'ImportDefaultSpecifier should not be visited directly',
    );
  }

  @override
  JSValue visitImportNamespaceSpecifier(ImportNamespaceSpecifier node) {
    throw UnsupportedError(
      'ImportNamespaceSpecifier should not be visited directly',
    );
  }

  @override
  JSValue visitExportSpecifier(ExportSpecifier node) {
    throw UnsupportedError('ExportSpecifier should not be visited directly');
  }

  /// ES6: Hoist var declarations to a specific environment
  /// Used when hasParameterExpressions is true to separate param and body scopes
  void _hoistVarDeclarationsToEnv(List<Statement> statements, Environment env) {
    _hoistVarDeclarationsRecursive(statements, env);
  }

  void _hoistVarDeclarationsRecursive(
    List<Statement> statements,
    Environment env,
  ) {
    for (final stmt in statements) {
      if (stmt is VariableDeclaration && stmt.kind == 'var') {
        // Hoist var declarations
        for (final decl in stmt.declarations) {
          if (decl.id is IdentifierPattern) {
            final name = (decl.id as IdentifierPattern).name;
            // Use hasLocal instead of has - we need to define in this specific env
            // even if the variable exists in a parent scope (that's the point of
            // the separate bodyEnv - to shadow parent variables for body closures)
            if (!env.hasLocal(name)) {
              env.define(name, JSValueFactory.undefined(), BindingType.var_);
            }
          }
        }
      } else if (stmt is IfStatement) {
        _hoistVarDeclarationsRecursive([stmt.consequent], env);
        if (stmt.alternate != null) {
          _hoistVarDeclarationsRecursive([stmt.alternate!], env);
        }
      } else if (stmt is WhileStatement) {
        _hoistVarDeclarationsRecursive([stmt.body], env);
      } else if (stmt is DoWhileStatement) {
        _hoistVarDeclarationsRecursive([stmt.body], env);
      } else if (stmt is ForStatement) {
        if (stmt.init is VariableDeclaration) {
          final varDecl = stmt.init as VariableDeclaration;
          if (varDecl.kind == 'var') {
            for (final decl in varDecl.declarations) {
              if (decl.id is IdentifierPattern) {
                final name = (decl.id as IdentifierPattern).name;
                if (!env.hasLocal(name)) {
                  env.define(
                    name,
                    JSValueFactory.undefined(),
                    BindingType.var_,
                  );
                }
              }
            }
          }
        }
        _hoistVarDeclarationsRecursive([stmt.body], env);
      } else if (stmt is ForInStatement) {
        if (stmt.left is VariableDeclaration) {
          final varDecl = stmt.left as VariableDeclaration;
          if (varDecl.kind == 'var') {
            for (final decl in varDecl.declarations) {
              if (decl.id is IdentifierPattern) {
                final name = (decl.id as IdentifierPattern).name;
                if (!env.hasLocal(name)) {
                  env.define(
                    name,
                    JSValueFactory.undefined(),
                    BindingType.var_,
                  );
                }
              }
            }
          }
        }
        _hoistVarDeclarationsRecursive([stmt.body], env);
      } else if (stmt is ForOfStatement) {
        if (stmt.left is VariableDeclaration) {
          final varDecl = stmt.left as VariableDeclaration;
          if (varDecl.kind == 'var') {
            for (final decl in varDecl.declarations) {
              if (decl.id is IdentifierPattern) {
                final name = (decl.id as IdentifierPattern).name;
                if (!env.hasLocal(name)) {
                  env.define(
                    name,
                    JSValueFactory.undefined(),
                    BindingType.var_,
                  );
                }
              }
            }
          }
        }
        _hoistVarDeclarationsRecursive([stmt.body], env);
      } else if (stmt is BlockStatement) {
        _hoistVarDeclarationsRecursive(stmt.body, env);
      } else if (stmt is TryStatement) {
        _hoistVarDeclarationsRecursive(stmt.block.body, env);
        if (stmt.handler != null) {
          _hoistVarDeclarationsRecursive(stmt.handler!.body.body, env);
        }
        if (stmt.finalizer != null) {
          _hoistVarDeclarationsRecursive(stmt.finalizer!.body, env);
        }
      } else if (stmt is SwitchStatement) {
        for (final switchCase in stmt.cases) {
          _hoistVarDeclarationsRecursive(switchCase.consequent, env);
        }
      }
      // Note: FunctionDeclarations are NOT hoisted to bodyEnv when hasParamExpressions
      // They stay in the lexical scope
    }
  }

  /// Phase de hoisting pour les declarations var et function
  void _hoistDeclarations(List<Statement> statements) {
    // For var and function, hoist in variableEnvironment (enclosing function)
    // For let and const, they are NOT hoisted
    final varEnv = _currentContext().variableEnvironment;
    // Les fonctions capturent lexicalEnvironment pour avoir acces aux let/const du bloc
    final lexEnv = _currentEnvironment();

    // Parcourir recursivement tous les statements pour hoister les var
    _hoistDeclarationsRecursive(statements, varEnv, lexEnv);
  }

  void _hoistDeclarationsRecursive(
    List<Statement> statements,
    Environment varEnv,
    Environment lexEnv,
  ) {
    for (final stmt in statements) {
      if (stmt is VariableDeclaration && stmt.kind == 'var') {
        // Hoister les declarations var (seulement pour les identifiants simples)
        for (final decl in stmt.declarations) {
          if (decl.id is IdentifierPattern) {
            varEnv.define(
              (decl.id as IdentifierPattern).name,
              JSValueFactory.undefined(),
              BindingType.var_,
            );
          }
          // Les patterns complexes (array/object) ne peuvent pas etre hoistes
        }
      } else if (stmt is FunctionDeclaration) {
        // Hoister les declarations de fonction avec creation d'objet fonction complet
        // Les fonctions capturent lexicalEnvironment pour acceder aux let/const
        // Also inherit strict mode from current context
        // ES2019: Generate source text from AST
        final sourceText = stmt.toString();
        final function = JSFunction(
          stmt,
          lexEnv,
          sourceText: sourceText,
          moduleUrl: _currentModuleUrl,
          strictMode: _currentContext().strictMode,
        );
        varEnv.define(stmt.id.name, function, BindingType.function);
      } else if (stmt is IfStatement) {
        // Hoister recursivement dans les branches if/else
        if (stmt.consequent is BlockStatement) {
          _hoistDeclarationsRecursive(
            (stmt.consequent as BlockStatement).body,
            varEnv,
            lexEnv,
          );
        } else {
          _hoistDeclarationsRecursive([stmt.consequent], varEnv, lexEnv);
        }
        if (stmt.alternate != null) {
          if (stmt.alternate is BlockStatement) {
            _hoistDeclarationsRecursive(
              (stmt.alternate as BlockStatement).body,
              varEnv,
              lexEnv,
            );
          } else {
            _hoistDeclarationsRecursive([stmt.alternate!], varEnv, lexEnv);
          }
        }
      } else if (stmt is ForStatement) {
        // Hoister les declarations var dans l'init du for
        if (stmt.init is VariableDeclaration) {
          final varDecl = stmt.init as VariableDeclaration;
          if (varDecl.kind == 'var') {
            for (final decl in varDecl.declarations) {
              if (decl.id is IdentifierPattern) {
                varEnv.define(
                  (decl.id as IdentifierPattern).name,
                  JSValueFactory.undefined(),
                  BindingType.var_,
                );
              }
            }
          }
        }
        // Hoister recursivement dans le corps du for
        if (stmt.body is BlockStatement) {
          _hoistDeclarationsRecursive(
            (stmt.body as BlockStatement).body,
            varEnv,
            lexEnv,
          );
        } else {
          _hoistDeclarationsRecursive([stmt.body], varEnv, lexEnv);
        }
      } else if (stmt is ForInStatement) {
        // Hoister les declarations var dans le left du for-in
        if (stmt.left is VariableDeclaration) {
          final varDecl = stmt.left as VariableDeclaration;
          if (varDecl.kind == 'var') {
            for (final decl in varDecl.declarations) {
              if (decl.id is IdentifierPattern) {
                varEnv.define(
                  (decl.id as IdentifierPattern).name,
                  JSValueFactory.undefined(),
                  BindingType.var_,
                );
              }
            }
          }
        }
        // Hoister recursivement dans le corps du for-in
        if (stmt.body is BlockStatement) {
          _hoistDeclarationsRecursive(
            (stmt.body as BlockStatement).body,
            varEnv,
            lexEnv,
          );
        } else {
          _hoistDeclarationsRecursive([stmt.body], varEnv, lexEnv);
        }
      } else if (stmt is WhileStatement) {
        // Hoister recursivement dans le corps du while
        if (stmt.body is BlockStatement) {
          _hoistDeclarationsRecursive(
            (stmt.body as BlockStatement).body,
            varEnv,
            lexEnv,
          );
        } else {
          _hoistDeclarationsRecursive([stmt.body], varEnv, lexEnv);
        }
      } else if (stmt is DoWhileStatement) {
        // Hoister recursivement dans le corps du do-while
        if (stmt.body is BlockStatement) {
          _hoistDeclarationsRecursive(
            (stmt.body as BlockStatement).body,
            varEnv,
            lexEnv,
          );
        } else {
          _hoistDeclarationsRecursive([stmt.body], varEnv, lexEnv);
        }
      } else if (stmt is BlockStatement) {
        // Hoister recursivement dans les blocs
        _hoistDeclarationsRecursive(stmt.body, varEnv, lexEnv);
      } else if (stmt is TryStatement) {
        // Hoister recursivement dans try/catch/finally
        _hoistDeclarationsRecursive(stmt.block.body, varEnv, lexEnv);
        if (stmt.handler != null) {
          _hoistDeclarationsRecursive(stmt.handler!.body.body, varEnv, lexEnv);
        }
        if (stmt.finalizer != null && stmt.finalizer is BlockStatement) {
          _hoistDeclarationsRecursive(
            (stmt.finalizer as BlockStatement).body,
            varEnv,
            lexEnv,
          );
        }
      } else if (stmt is SwitchStatement) {
        // Hoister recursivement dans les cas du switch
        for (final switchCase in stmt.cases) {
          _hoistDeclarationsRecursive(switchCase.consequent, varEnv, lexEnv);
        }
      }
    }
  }

  // ===== STATEMENTS =====

  @override
  JSValue visitExpressionStatement(ExpressionStatement node) {
    return node.expression.accept(this);
  }

  @override
  JSValue visitEmptyStatement(EmptyStatement node) {
    // Empty statements do nothing, return undefined
    return JSValueFactory.undefined();
  }

  @override
  JSValue visitBlockStatement(BlockStatement node) {
    // Create nouveau scope pour le bloc
    final parentEnv = _currentEnvironment();

    // Always create a new block environment for proper scoping
    final blockEnv = Environment.block(parentEnv);

    // Create nouveau contexte d'execution
    final blockContext = ExecutionContext(
      lexicalEnvironment: blockEnv,
      variableEnvironment: _currentContext().variableEnvironment,
      thisBinding: _currentContext().thisBinding,
      strictMode: _currentContext().strictMode,
      debugName: 'Block',
      asyncTask:
          _currentContext().asyncTask, // Heriter l'asyncTask du contexte parent
      function:
          _currentContext().function, // Heriter la fonction du contexte parent
      arguments: _currentContext()
          .arguments, // Heriter les arguments du contexte parent
      newTarget: _currentContext()
          .newTarget, // Heriter le newTarget du contexte parent (ES6)
    );

    _executionStack.push(blockContext);

    try {
      JSValue lastValue = JSValueFactory.undefined();

      // HOISTING: Hoister les declarations var et function SEULEMENT si c'est
      // le body d'une fonction (pas un bloc autonome dans un programme)
      // Le body d'une fonction a variableEnvironment = lexicalEnvironment du parent
      final isFunctionBody = _currentContext().function != null;
      if (isFunctionBody) {
        _hoistDeclarations(node.body);
      }

      // Executer tous les statements sauf les FunctionDeclaration
      // (les fonctions sont deja hoistees)
      try {
        for (final stmt in node.body) {
          if (stmt is! FunctionDeclaration || !isFunctionBody) {
            lastValue = stmt.accept(this);
          }
        }
      } on FlowControlException catch (e) {
        // Attach the last value before the abrupt completion
        if ((e.type == ExceptionType.break_ ||
                e.type == ExceptionType.continue_) &&
            e.completionValue == null) {
          // Re-throw with the completion value attached
          throw FlowControlException(
            e.type,
            label: e.label,
            completionValue: lastValue,
          );
        }
        rethrow;
      }

      // For function bodies, return undefined (functions only return values through explicit return statements)
      // For other blocks, return the last statement's value (for expressions like IIFE)
      if (isFunctionBody) {
        return JSValueFactory.undefined();
      }
      return lastValue;
    } finally {
      _executionStack.pop();
    }
  }

  @override
  JSValue visitVariableDeclaration(VariableDeclaration node) {
    final env = node.kind == 'var'
        ? _currentContext().variableEnvironment
        : _currentEnvironment();

    for (final decl in node.declarations) {
      // ES6: const declarations must have an initializer
      if (node.kind == 'const' && decl.init == null) {
        throw JSSyntaxError('Missing initializer in const declaration');
      }

      // Handle destructuring or simple identifier
      if (decl.id is IdentifierPattern) {
        final identifierPattern = decl.id as IdentifierPattern;
        final name = identifierPattern.name;

        // Check if eval is trying to declare a var with a parameter name
        final parameterNames = _currentContext().parameterNames;
        if (node.kind == 'var' &&
            parameterNames != null &&
            parameterNames.contains(name)) {
          // Eval is trying to redeclare a function parameter via var
          throwJSSyntaxError('Identifier \'$name\' has already been declared');
        }

        // Set target binding name context for anonymous function name inference
        // ES6: var foo = function() {} => foo.name should be 'foo'
        final previousTarget = _targetBindingNameForFunction;
        _targetBindingNameForFunction = name;
        // Evaluate the initializer
        final value = decl.init?.accept(this) ?? JSValueFactory.undefined();
        _targetBindingNameForFunction = previousTarget;

        // ES6: Set name for anonymous class expressions assigned to variables
        // e.g., var E = class {} => E.name should be "E"
        if (value is JSClass &&
            (value.name == 'anonymous' || value.name.isEmpty)) {
          value.name = name;
        }
        // Also handle anonymous functions assigned to variables
        // Only call setFunctionName if the function is truly anonymous (name was 'anonymous')
        if (value is JSFunction && value.functionName == 'anonymous') {
          value.setFunctionName(name);
        }

        final bindingType = switch (node.kind) {
          'var' => BindingType.var_,
          'let' => BindingType.let_,
          'const' => BindingType.const_,
          _ => throw JSError('Unknown variable declaration kind: ${node.kind}'),
        };

        if (node.kind == 'var' && env.has(name)) {
          // var est deja hoistee (possiblement dans un parent), juste mettre a jour la valeur
          env.set(name, value);
        } else if (node.kind == 'var') {
          // var pas encore definie (peut arriver si pas de hoisting)
          env.define(name, value, bindingType);
        } else {
          // let/const - check if already exists in local scope (during generator resumption)
          if (env.hasLocal(name) &&
              _currentGeneratorContext != null &&
              _currentGeneratorContext!.resumingFromYield) {
            // During generator resumption, if the variable already exists locally, force reassign it
            // Using setLocalForce to bypass const/let mutability checks during generator re-execution
            env.setLocalForce(name, value);
          } else {
            // Normal case: define normally
            env.define(name, value, bindingType);
          }
        }
      } else {
        // C'est un pattern de destructuring
        final value = decl.init?.accept(this) ?? JSValueFactory.undefined();
        _assignToPattern(decl.id, value);
      }
    }

    return JSValueFactory.undefined();
  }

  /// Cree un objet generateur pour une fonction generatrice
  JSGenerator _createGenerator(
    FunctionDeclaration node,
    List<JSValue> args,
    Environment closureEnv, [
    JSValue? thisBinding,
  ]) {
    // Create environment and bind parameters EAGERLY (at generator call time)
    // This ensures TDZ errors are thrown when the generator is called, not on .next()
    final executionEnv = Environment.block(closureEnv);

    // Bind 'this' in the generator if provided
    if (thisBinding != null && !thisBinding.isUndefined) {
      executionEnv.define('this', thisBinding, BindingType.var_);
    }

    // Bind parameters with TDZ support for default values
    int argIndex = 0;
    for (var i = 0; i < node.params.length; i++) {
      final param = node.params[i];

      if (param.isDestructuring && param.pattern != null) {
        JSValue argValue;
        if (argIndex < args.length) {
          argValue = args[argIndex];
          if (argValue.isUndefined && param.defaultValue != null) {
            // Push context for default evaluation
            final paramContext = ExecutionContext(
              lexicalEnvironment: executionEnv,
              variableEnvironment: executionEnv,
              thisBinding: thisBinding ?? JSValueFactory.undefined(),
            );
            _executionStack.push(paramContext);
            try {
              argValue = param.defaultValue!.accept(this);
            } finally {
              _executionStack.pop();
            }
          }
        } else if (param.defaultValue != null) {
          final paramContext = ExecutionContext(
            lexicalEnvironment: executionEnv,
            variableEnvironment: executionEnv,
            thisBinding: thisBinding ?? JSValueFactory.undefined(),
          );
          _executionStack.push(paramContext);
          try {
            argValue = param.defaultValue!.accept(this);
          } finally {
            _executionStack.pop();
          }
        } else {
          argValue = JSValueFactory.undefined();
        }
        _destructurePattern(param.pattern!, argValue, executionEnv);
        argIndex++;
      } else if (param.isRest) {
        // Rest parameter
        final restArgs = <JSValue>[];
        for (int j = argIndex; j < args.length; j++) {
          restArgs.add(args[j]);
        }
        if (param.name != null) {
          executionEnv.define(
            param.name!.name,
            JSValueFactory.array(restArgs),
            BindingType.parameter,
          );
        }
        break;
      } else if (param.name != null) {
        JSValue argValue;
        if (argIndex < args.length) {
          if (args[argIndex].isUndefined && param.defaultValue != null) {
            // Create TDZ binding before evaluating default
            executionEnv.defineUninitialized(
              param.name!.name,
              BindingType.parameter,
            );
            // Push execution context so default expression sees the TDZ binding
            final paramContext = ExecutionContext(
              lexicalEnvironment: executionEnv,
              variableEnvironment: executionEnv,
              thisBinding: thisBinding ?? JSValueFactory.undefined(),
            );
            _executionStack.push(paramContext);
            try {
              argValue = param.defaultValue!.accept(this);
            } finally {
              _executionStack.pop();
            }
          } else {
            argValue = args[argIndex];
          }
        } else if (param.defaultValue != null) {
          // Create TDZ binding before evaluating default
          executionEnv.defineUninitialized(
            param.name!.name,
            BindingType.parameter,
          );
          // Push execution context so default expression sees the TDZ binding
          final paramContext = ExecutionContext(
            lexicalEnvironment: executionEnv,
            variableEnvironment: executionEnv,
            thisBinding: thisBinding ?? JSValueFactory.undefined(),
          );
          _executionStack.push(paramContext);
          try {
            argValue = param.defaultValue!.accept(this);
          } finally {
            _executionStack.pop();
          }
        } else {
          argValue = JSValueFactory.undefined();
        }
        // Define the parameter (handles TDZ->initialized transition for uninitialized bindings)
        executionEnv.define(param.name!.name, argValue, BindingType.parameter);
        argIndex++;
      } else {
        argIndex++;
      }
    }

    // Creer le contexte d'execution du generateur
    final context = GeneratorExecutionContext(
      node: node,
      args: args,
      closureEnv: closureEnv,
      thisBinding: thisBinding,
    );
    // SAVE the executionEnv after parameter binding
    // This ensures parameters are bound once at generator creation time
    // and reused for all generator.next() calls, avoiding TDZ re-creation issues
    context.executionEnv = executionEnv;

    // Create generateur avec une fonction qui execute le corps du generateur
    final generator = JSGenerator(
      generatorFunction: (JSValue inputValue, GeneratorState previousState) {
        return _executeGenerator(context, inputValue, previousState);
      },
    );

    return generator;
  }

  /// Create an async generator object from an async generator function
  /// Async generators are similar to generators but yield Promises
  JSAsyncGenerator _createAsyncGenerator(
    AsyncFunctionDeclaration node,
    List<JSValue> args,
    Environment closureEnv, [
    JSValue? thisBinding,
  ]) {
    // Create the generator execution context for an async generator
    final context = GeneratorExecutionContext(
      node: node,
      args: args,
      closureEnv: closureEnv,
      thisBinding: thisBinding,
    );

    // Create an async generator with a function that executes the async generator body
    // Each iteration returns an iterator result {value, done}
    // The .next() call on the async generator wraps this in a Promise
    final generator = JSAsyncGenerator(
      generatorFunction: (JSValue inputValue, GeneratorState previousState) {
        // Execute the generator - this returns {value, done}
        return _executeGenerator(context, inputValue, previousState);
      },
    );

    return generator;
  }

  /// Obtient un iterateur depuis une valeur (pour yield*)
  JSValue? _getIteratorFromValue(JSValue value) {
    // If it's already a generator or iterator, return it as-is
    if (value is JSGenerator) {
      return value;
    }

    // If it's an object with a Symbol.iterator method
    if (value is JSObject) {
      final iteratorKey = JSSymbol.iterator.toString();
      final iteratorMethod = value.getProperty(iteratorKey);

      if (!iteratorMethod.isUndefined &&
          (iteratorMethod is JSFunction ||
              iteratorMethod is JSNativeFunction)) {
        // Appeler la methode Symbol.iterator pour obtenir l'iterateur
        final iterator = callFunction(iteratorMethod, [], value);
        return iterator;
      }
    }

    return null;
  }

  /// Gere la delegation yield* a un iterateur
  Map<String, dynamic> _handleYieldDelegation(
    GeneratorExecutionContext context,
    JSValue iterableValue,
    JSValue inputValue,
  ) {
    // If we don't yet have a delegated iterator, get one
    if (context.delegatedIterator == null) {
      // Marquer ce yield comme point de delegation
      context.delegatingYieldNumber = context.yieldCount;

      // Obtenir l'iterateur depuis la valeur
      final iterator = _getIteratorFromValue(iterableValue);
      if (iterator == null) {
        throw JSTypeError(
          '${iterableValue.type.name} is not iterable (cannot read property Symbol.iterator)',
        );
      }

      context.delegatedIterator = iterator;
    }

    // Obtenir l'iterateur delegue
    final iterator = context.delegatedIterator!;

    // Appeler next(inputValue) sur l'iterateur delegue
    JSValue iteratorResult;
    if (iterator is JSGenerator) {
      iteratorResult = iterator.next(inputValue);
    } else if (iterator is JSObject && iterator.hasProperty('next')) {
      final nextMethod = iterator.getProperty('next');
      if (nextMethod is JSFunction || nextMethod is JSNativeFunction) {
        iteratorResult = callFunction(nextMethod, [inputValue], iterator);
      } else {
        throw JSTypeError('Iterator next method is not callable');
      }
    } else {
      throw JSTypeError('Invalid iterator for yield* delegation');
    }

    // Extraire value et done du resultat
    JSValue resultValue = JSValueFactory.undefined();
    bool resultDone = false;

    if (iteratorResult is JSObject) {
      if (iteratorResult.hasProperty('value')) {
        resultValue = iteratorResult.getProperty('value');
      }
      if (iteratorResult.hasProperty('done')) {
        final doneValue = iteratorResult.getProperty('done');
        resultDone = doneValue.toBoolean();
      }
    }

    if (resultDone) {
      // L'iterateur delegue est termine
      // Nettoyer le contexte de delegation
      context.delegatedIterator = null;
      context.delegatingYieldNumber = null;

      // Return the final value and mark as not finished
      // (le generateur continue son execution)
      // On doit reprendre l'execution du generateur en injectant la valeur finale
      context.inputValue = resultValue;
      context.resumingFromYield = true;

      // Relancer l'execution du generateur pour continuer
      return _executeGenerator(
        context,
        resultValue,
        GeneratorState.suspendedYield,
      );
    } else {
      // L'iterateur delegue a produit une valeur
      // La yielder au generateur parent
      return {'value': resultValue, 'done': false};
    }
  }

  /// Execute une etape du generateur
  Map<String, dynamic> _executeGenerator(
    GeneratorExecutionContext context,
    JSValue inputValue,
    GeneratorState previousState,
  ) {
    try {
      // Creer l'environnement d'execution si c'est la premiere fois
      // NOTE: If executionEnv is already set, it was created in _createGenerator
      // and we should reuse it. Do NOT recreate parameters.
      if (context.executionEnv == null) {
        // This case should be rare/deprecated, kept for backward compat only
        // Create nouvel environnement pour le generateur
        context.executionEnv = Environment.block(context.closureEnv);

        // Lier 'this' dans le generateur si fourni
        if (context.thisBinding != null && !context.thisBinding!.isUndefined) {
          context.executionEnv!.define(
            'this',
            context.thisBinding!,
            BindingType.var_,
          );
        }

        // Bind parameters to arguments with TDZ support for default values
        int argIndex = 0;
        for (var i = 0; i < context.node.params.length; i++) {
          final param = context.node.params[i];

          // Handle destructuring or simple parameter
          if (param.isDestructuring && param.pattern != null) {
            JSValue argValue;
            if (argIndex < context.args.length) {
              argValue = context.args[argIndex];
              if (argValue.isUndefined && param.defaultValue != null) {
                argValue = param.defaultValue!.accept(this);
              }
            } else if (param.defaultValue != null) {
              argValue = param.defaultValue!.accept(this);
            } else {
              argValue = JSValueFactory.undefined();
            }
            _destructurePattern(
              param.pattern!,
              argValue,
              context.executionEnv!,
            );
            argIndex++;
          } else if (param.isRest) {
            // Rest parameter
            final restArgs = <JSValue>[];
            for (int j = argIndex; j < context.args.length; j++) {
              restArgs.add(context.args[j]);
            }
            if (param.name != null) {
              context.executionEnv!.define(
                param.name!.name,
                JSValueFactory.array(restArgs),
                BindingType.parameter,
              );
            }
            break;
          } else if (param.name != null) {
            JSValue argValue;
            if (argIndex < context.args.length) {
              if (context.args[argIndex].isUndefined &&
                  param.defaultValue != null) {
                // Create TDZ binding before evaluating default
                context.executionEnv!.defineUninitialized(
                  param.name!.name,
                  BindingType.parameter,
                );
                // Push execution context so default expression sees the TDZ binding
                final paramContext = ExecutionContext(
                  lexicalEnvironment: context.executionEnv!,
                  variableEnvironment: context.executionEnv!,
                  thisBinding:
                      context.thisBinding ?? JSValueFactory.undefined(),
                );
                _executionStack.push(paramContext);
                try {
                  argValue = param.defaultValue!.accept(this);
                } finally {
                  _executionStack.pop();
                }
              } else {
                argValue = context.args[argIndex];
              }
            } else if (param.defaultValue != null) {
              // Create TDZ binding before evaluating default
              context.executionEnv!.defineUninitialized(
                param.name!.name,
                BindingType.parameter,
              );
              // Push execution context so default expression sees the TDZ binding
              final paramContext = ExecutionContext(
                lexicalEnvironment: context.executionEnv!,
                variableEnvironment: context.executionEnv!,
                thisBinding: context.thisBinding ?? JSValueFactory.undefined(),
              );
              _executionStack.push(paramContext);
              try {
                argValue = param.defaultValue!.accept(this);
              } finally {
                _executionStack.pop();
              }
            } else {
              argValue = JSValueFactory.undefined();
            }
            // Define or update the parameter
            if (context.executionEnv!.hasLocal(param.name!.name)) {
              context.executionEnv!.setLocal(param.name!.name, argValue);
            } else {
              context.executionEnv!.define(
                param.name!.name,
                argValue,
                BindingType.parameter,
              );
            }
            argIndex++;
          } else {
            argIndex++;
          }
        }
      }

      // Injecter l'inputValue dans le contexte (pour yield)
      context.inputValue = inputValue;

      // If we have an active delegated iterator (yield*), continue delegating
      if (context.delegatedIterator != null) {
        return _handleYieldDelegation(
          context,
          context.delegatedIterator!,
          inputValue,
        );
      }

      // DON'T reset yield counter - it must be persistent across all .next() calls
      // Each yield has a unique, persistent number that never changes
      // context.yieldCount = 0; // REMOVED - This was breaking yield tracking

      // If resuming after a yield (not the first time), mark the context
      // SAUF si on a une continuation de boucle (dans ce cas, on reprend APRES le yield)
      if (previousState == GeneratorState.suspendedYield &&
          context.lastYieldNumber != null &&
          context.continuationStack.isEmpty) {
        context.resumingFromYield = true;
        // NOTE: Don't reset currentStatementIndex to 0
        // Instead, continue from where we left off to avoid re-executing side effects
        // The yield counting logic in visitYieldExpression will handle finding the right yield
      }

      // Create contexte d'execution pour le generateur
      final genContext = ExecutionContext(
        lexicalEnvironment: context.executionEnv!,
        variableEnvironment: context.executionEnv!,
        thisBinding: context.thisBinding ?? JSValueFactory.undefined(),
        debugName: 'Generator',
      );

      _executionStack.push(genContext);

      // Sauvegarder le contexte du generateur pour que visitYieldExpression puisse y acceder
      _currentGeneratorContext = context;

      try {
        // Executer le corps du generateur statement par statement
        final result = _executeGeneratorBody(context);

        // If we get here, the generator has finished normally
        _executionStack.pop();
        _currentGeneratorContext = null;
        return {
          'value': result.type != JSValueType.undefined
              ? result
              : JSValueFactory.undefined(),
          'done': true,
        };
      } on GeneratorYieldException catch (e) {
        // Le generateur a yielded une valeur
        _executionStack.pop();
        _currentGeneratorContext = null;

        if (e.delegate) {
          // yield* - deleguer a un autre iterateur
          return _handleYieldDelegation(context, e.value, inputValue);
        } else {
          // yield simple
          return {'value': e.value, 'done': false};
        }
      } on FlowControlException catch (e) {
        // Le generateur a fait un return explicite
        _executionStack.pop();
        if (e.type == ExceptionType.return_) {
          return {'value': e.value ?? JSValueFactory.undefined(), 'done': true};
        }
        rethrow;
      } catch (e) {
        // Une erreur s'est produite
        _executionStack.pop();
        rethrow;
      }
    } on JSError {
      // Les erreurs JavaScript (JSTypeError, JSReferenceError, etc.) doivent etre propagees
      rethrow;
    } catch (e) {
      // Erreur lors de l'execution (erreurs internes seulement)
      return {'value': JSValueFactory.undefined(), 'done': true};
    }
  }

  /// Execute le corps du generateur statement par statement
  /// en reprenant depuis la derniere position sauvegardee
  JSValue _executeGeneratorBody(GeneratorExecutionContext context) {
    final body = context.node.body;
    final statements = body.body;
    JSValue lastValue = JSValueFactory.undefined();

    // Reprendre depuis le dernier statement non-execute
    for (int i = context.currentStatementIndex; i < statements.length; i++) {
      context.currentStatementIndex = i;
      final stmt = statements[i];

      lastValue = stmt.accept(this);

      // Incrementer pour la prochaine fois
      context.currentStatementIndex = i + 1;
    }

    return lastValue;
  }

  @override
  JSValue visitFunctionDeclaration(FunctionDeclaration node) {
    // Create objet fonction JavaScript avec closure
    final currentEnv = _currentContext().variableEnvironment;
    // Pass strict mode context to function
    final currentStrictMode = _currentContext().strictMode;

    // Calculate function length (number of params until first default or rest)
    int functionLength = 0;
    for (final param in node.params) {
      if (param.defaultValue != null || param.isRest) {
        break;
      }
      functionLength++;
    }

    JSValue functionValue;

    if (node.isGenerator) {
      // Createe fonction generateur
      // Quand appelee, elle retourne un objet generateur au lieu d'executer directement
      functionValue = JSNativeFunction(
        functionName: node.id.name,
        expectedArgs: functionLength,
        nativeImpl: (args) {
          // Return a generator instead of executing the function
          return _createGenerator(node, args, currentEnv);
        },
      );
    } else {
      // Creer la fonction normale avec l'environnement de closure
      // ES2019: Generate source text from AST
      final sourceText = node.toString();
      functionValue = JSValueFactory.function(
        node,
        currentEnv,
        sourceText: sourceText,
        strictMode: currentStrictMode,
      );
    }

    // Enregistrer la fonction dans l'environnement courant (avec hoisting)
    currentEnv.define(node.id.name, functionValue, BindingType.function);

    // Retourner la fonction pour permettre l'export
    return functionValue;
  }

  /// Validate that an async function doesn't contain super calls or super properties
  void _validateAsyncFunctionConstraints(ASTNode node) {
    // Visitor to find all super expressions
    var superFound = false;

    void checkNode(ASTNode n) {
      if (n is SuperExpression) {
        superFound = true;
      } else if (n is BlockStatement) {
        for (final stmt in n.body) {
          checkNode(stmt);
          if (superFound) return;
        }
      } else if (n is ExpressionStatement) {
        checkNode(n.expression);
      } else if (n is CallExpression) {
        checkNode(n.callee);
        if (superFound) return;
        for (final arg in n.arguments) {
          checkNode(arg);
          if (superFound) return;
        }
      } else if (n is MemberExpression) {
        checkNode(n.object);
        if (superFound) return;
        if (!n.computed) {
          // property is an identifier, no need to check
        } else {
          checkNode(n.property);
        }
      } else if (n is ReturnStatement && n.argument != null) {
        checkNode(n.argument!);
      } else if (n is IfStatement) {
        checkNode(n.test);
        if (superFound) return;
        checkNode(n.consequent);
        if (superFound) return;
        if (n.alternate != null) checkNode(n.alternate!);
      } else if (n is WhileStatement) {
        checkNode(n.test);
        if (superFound) return;
        checkNode(n.body);
      } else if (n is DoWhileStatement) {
        checkNode(n.body);
        if (superFound) return;
        checkNode(n.test);
      } else if (n is ForStatement) {
        if (n.init != null) checkNode(n.init!);
        if (superFound) return;
        if (n.test != null) checkNode(n.test!);
        if (superFound) return;
        if (n.update != null) checkNode(n.update!);
        if (superFound) return;
        checkNode(n.body);
      } else if (n is VariableDeclaration) {
        for (final decl in n.declarations) {
          if (decl.init != null) {
            checkNode(decl.init!);
            if (superFound) return;
          }
        }
      } else if (n is AssignmentExpression) {
        checkNode(n.left);
        if (superFound) return;
        checkNode(n.right);
      } else if (n is UnaryExpression) {
        checkNode(n.operand);
      } else if (n is BinaryExpression) {
        checkNode(n.left);
        if (superFound) return;
        checkNode(n.right);
      } else if (n is ConditionalExpression) {
        checkNode(n.test);
        if (superFound) return;
        checkNode(n.consequent);
        if (superFound) return;
        checkNode(n.alternate);
      } else if (n is ArrayExpression) {
        for (final elem in n.elements) {
          if (elem != null) {
            checkNode(elem);
            if (superFound) return;
          }
        }
      } else if (n is ObjectExpression) {
        for (final prop in n.properties) {
          if (prop.value != null) {
            checkNode(prop.value!);
            if (superFound) return;
          }
        }
      }
      // Don't recurse into nested function declarations
    }

    if (node is AsyncFunctionDeclaration) {
      checkNode(node.body);
    } else if (node is AsyncFunctionExpression) {
      checkNode(node.body);
    } else if (node is AsyncArrowFunctionExpression) {
      if (node.body is! Expression) {
        checkNode(node.body);
      } else {
        checkNode(node.body as Expression);
      }
    }

    if (superFound) {
      throw JSSyntaxError(
        'It is a syntax error if AsyncFunctionBody contains SuperCall or SuperProperty is true',
      );
    }
  }

  @override
  JSValue visitAsyncFunctionDeclaration(AsyncFunctionDeclaration node) {
    // Validate async function constraints before creating the function
    _validateAsyncFunctionConstraints(node);

    // Create objet fonction JavaScript async avec closure
    final currentEnv = _currentContext().variableEnvironment;
    // Capture the module URL at function definition time
    final capturedModuleUrl = _currentModuleUrl;

    // Calculate function length (number of params until first default or rest)
    int functionLength = 0;
    for (final param in node.params) {
      if (param.defaultValue != null || param.isRest) {
        break;
      }
      functionLength++;
    }

    JSValue functionValue;

    if (node.isGenerator) {
      // Async generator function: returns an async generator object
      functionValue = JSNativeFunction(
        functionName: node.id.name,
        expectedArgs: functionLength,
        nativeImpl: (args) {
          // Return an async generator (which is also an async iterable)
          return _createAsyncGenerator(node, args, currentEnv);
        },
      );
    } else {
      // Normal async function: returns a Promise
      // This wrapper allows us to intercept .call() and .apply() calls
      final asyncFunction = _JSAsyncFunctionWrapper(
        node.id.name,
        functionLength,
        node,
        currentEnv,
        capturedModuleUrl,
        this,
      );

      functionValue = asyncFunction;
    }

    // Enregistrer la fonction dans l'environnement courant (avec hoisting)
    currentEnv.define(node.id.name, functionValue, BindingType.function);

    // Retourner la fonction pour permettre l'export
    return functionValue;
  }

  /// Resout une valeur de retour async, en deroulant les Promises si necessaire
  void _resolveAsyncReturn(
    JSValue returnValue,
    JSNativeFunction resolve,
    JSNativeFunction reject,
  ) {
    // If the return value is a Promise, we must unwrap it
    if (returnValue is JSPromise) {
      // Attacher des handlers pour derouler la Promise
      PromisePrototype.then([
        JSNativeFunction(
          functionName: 'unwrapResolver',
          nativeImpl: (args) {
            final value = args.isNotEmpty
                ? args[0]
                : JSValueFactory.undefined();
            // Resoudre la Promise externe avec la valeur deroulee
            resolve.call([value]);
            return JSValueFactory.undefined();
          },
        ),
        JSNativeFunction(
          functionName: 'unwrapRejecter',
          nativeImpl: (args) {
            final error = args.isNotEmpty
                ? args[0]
                : JSValueFactory.undefined();
            // Rejeter la Promise externe avec l'erreur
            reject.call([error]);
            return JSValueFactory.undefined();
          },
        ),
      ], returnValue);
      // Executer les taches en attente pour traiter la Promise
      _asyncScheduler.runPendingTasks(this);
    } else {
      // Valeur normale, resoudre directement
      resolve.call([returnValue]);
    }
  }

  /// Execute une fonction async avec gestion des continuations
  void _executeAsyncFunction(AsyncTask task) {
    final continuation = task.continuation;
    if (continuation == null) return;

    // Reset the awaited value index for this execution
    task.resetAwaitedValueIndex();

    try {
      // Obtenir ou creer l'environnement de fonction (preserve entre executions)
      // This can throw JSError if parameter defaults have invalid references
      Environment functionEnv;
      try {
        functionEnv = continuation.getFunctionEnv(this);
      } on JSError catch (e) {
        // Parameter binding failed with a JS error - reject the promise
        final errorObj = JSErrorObjectFactory.fromDartError(e);
        task.fail(errorObj);
        continuation.reject.call([errorObj]);
        // Only run pending tasks if task was suspended and is now running
        // If task failed fatally, don't waste time on runPendingTasks()
        if (task.state == AsyncTaskState.running) {
          _asyncScheduler.runPendingTasks(this);
        }
        return;
      }

      // Pousser le contexte de classe si c'est une methode
      final needsClassContext = continuation.parentClass != null;
      if (needsClassContext) {
        _pushClassContext(continuation.parentClass!);
      }

      // Create contexte d'execution pour la fonction async
      final functionContext = ExecutionContext(
        lexicalEnvironment: functionEnv,
        variableEnvironment: functionEnv,
        thisBinding: continuation.thisBinding ?? JSValueFactory.undefined(),
        function: null,
        arguments: continuation.args,
        debugName: 'AsyncFunction ${continuation.node.id.name}',
        asyncTask: task,
      );

      // Save and set module URL from async function's module context
      final previousModuleUrl = _currentModuleUrl;
      _currentModuleUrl = continuation.moduleUrl;

      _executionStack.push(functionContext);
      try {
        // Executer le corps de la fonction async
        final result = continuation.node.body.accept(this);

        // La fonction s'est terminee normalement
        task.complete(result);
        _resolveAsyncReturn(result, continuation.resolve, continuation.reject);
      } catch (e) {
        if (e is FlowControlException && e.type == ExceptionType.return_) {
          // Return statement - la fonction se terme avec la valeur de retour
          final returnValue = e.value ?? JSValueFactory.undefined();
          task.complete(returnValue);
          _resolveAsyncReturn(
            returnValue,
            continuation.resolve,
            continuation.reject,
          );
        } else if (e is AsyncSuspensionException) {
          // La fonction a ete suspendue par un await
          // Ne rien faire, la tache sera reprise plus tard
        } else if (e is JSException) {
          // Erreur JavaScript (throw statement)
          final errorValue = e.value;
          task.fail(errorValue);
          continuation.reject.call([errorValue]);
          // Only run pending tasks if task was suspended and is now running
          if (task.state == AsyncTaskState.running) {
            _asyncScheduler.runPendingTasks(this);
          }
        } else {
          // Erreur inattendue
          final errorValue = e is JSValue
              ? e
              : JSValueFactory.string(e.toString());
          task.fail(errorValue);
          continuation.reject.call([errorValue]);
          // Only run pending tasks if task was suspended and is now running
          if (task.state == AsyncTaskState.running) {
            _asyncScheduler.runPendingTasks(this);
          }
        }
      } finally {
        if (needsClassContext) {
          _popClassContext();
        }
        _executionStack.pop();
        _currentModuleUrl = previousModuleUrl;
      }
    } catch (e) {
      // Erreur lors de la configuration
      final errorValue = e is JSException
          ? e.value
          : (e is JSValue ? e : JSValueFactory.string(e.toString()));
      task.fail(errorValue);
      continuation.reject.call([errorValue]);
      // Executer les taches en attente apres le rejet
      _asyncScheduler.runPendingTasks(this);
    }
  }

  /// Execute une expression de fonction async de maniere asynchrone avec gestion des suspensions
  void _executeAsyncFunctionExpression(
    AsyncTask task,
    AsyncFunctionExpression node,
    List<JSValue> args,
    Environment closureEnv,
    JSNativeFunction resolve,
    JSNativeFunction reject,
  ) {
    try {
      // Create nouvel environnement pour l'execution de la fonction
      final functionEnv = Environment(parent: closureEnv);

      // Create a separate environment for parameter scope (allows defaults to reference previous params)
      final paramScopeEnv = Environment(parent: closureEnv);

      // Collect all parameter names for eval validation
      final parameterNames = <String>{};
      for (final param in node.params) {
        if (param.name != null && !param.isRest) {
          parameterNames.add(param.name!.name);
        }
      }

      // First pass: Create uninitialized TDZ bindings for all parameters with defaults
      for (final param in node.params) {
        if (param.name != null && !param.isRest && param.defaultValue != null) {
          paramScopeEnv.defineUninitialized(
            param.name!.name,
            BindingType.parameter,
          );
        }
      }

      // Lier les parametres aux arguments
      int argIndex = 0;
      for (int i = 0; i < node.params.length; i++) {
        final param = node.params[i];

        if (param.isRest) {
          // Parametre rest: collecter tous les arguments restants
          final restArgs = <JSValue>[];
          for (int j = argIndex; j < args.length; j++) {
            restArgs.add(args[j]);
          }
          final argValue = JSValueFactory.array(restArgs);
          if (param.name != null) {
            paramScopeEnv.define(
              param.name!.name,
              argValue,
              BindingType.parameter,
            );
            functionEnv.define(
              param.name!.name,
              argValue,
              BindingType.parameter,
            );
          }
          break;
        } else if (param.isDestructuring && param.pattern != null) {
          // Parametre destructuring
          JSValue argValue;
          if (argIndex < args.length) {
            argValue = args[argIndex];
          } else if (param.defaultValue != null) {
            final paramContext = ExecutionContext(
              lexicalEnvironment: paramScopeEnv,
              variableEnvironment: paramScopeEnv,
              thisBinding: JSValueFactory.undefined(),
              strictMode: false,
              parameterNames: parameterNames,
            );
            _executionStack.push(paramContext);
            try {
              argValue = param.defaultValue!.accept(this);
            } finally {
              _executionStack.pop();
            }
          } else {
            argValue = JSValueFactory.undefined();
          }
          _destructurePattern(param.pattern!, argValue, paramScopeEnv);
          _destructurePattern(param.pattern!, argValue, functionEnv);
          argIndex++;
        } else {
          // Parametre simple
          JSValue argValue;
          if (argIndex < args.length) {
            if (args[argIndex].isUndefined && param.defaultValue != null) {
              final paramContext = ExecutionContext(
                lexicalEnvironment: paramScopeEnv,
                variableEnvironment: paramScopeEnv,
                thisBinding: JSValueFactory.undefined(),
                strictMode: false,
                parameterNames: parameterNames,
              );
              _executionStack.push(paramContext);
              try {
                argValue = param.defaultValue!.accept(this);
              } finally {
                _executionStack.pop();
              }
            } else {
              argValue = args[argIndex];
            }
          } else {
            if (param.defaultValue != null) {
              final paramContext = ExecutionContext(
                lexicalEnvironment: paramScopeEnv,
                variableEnvironment: paramScopeEnv,
                thisBinding: JSValueFactory.undefined(),
                strictMode: false,
                parameterNames: parameterNames,
              );
              _executionStack.push(paramContext);
              try {
                argValue = param.defaultValue!.accept(this);
              } finally {
                _executionStack.pop();
              }
            } else {
              argValue = JSValueFactory.undefined();
            }
          }
          if (param.name != null) {
            paramScopeEnv.define(
              param.name!.name,
              argValue,
              BindingType.parameter,
            );
            functionEnv.define(
              param.name!.name,
              argValue,
              BindingType.parameter,
            );
          }
          argIndex++;
        }
      }

      // Create arguments object
      // Check if we should use mapped arguments (non-strict with simple parameters)
      // Simple parameters = no defaults, no destructuring, no rest
      final hasSimpleParams = node.params.every(
        (p) =>
            !p.isRest &&
            !p.isDestructuring &&
            p.name != null &&
            p.defaultValue == null,
      );

      final isStrictMode = false; // Async functions in non-strict mode for now

      final JSObject argumentsObject;
      if (!isStrictMode && hasSimpleParams) {
        // Create mapped arguments - changes to arguments[i] sync with parameters
        final parameterNames = <int, String>{};
        for (int i = 0; i < node.params.length && i < args.length; i++) {
          final param = node.params[i];
          if (param.name != null) {
            parameterNames[i] = param.name!.name;
          }
        }
        argumentsObject = JSMappedArguments(
          parameterNames: parameterNames,
          functionEnv: functionEnv,
          prototype: JSObject.objectPrototype,
        );
      } else {
        // Create regular unmapped arguments object
        argumentsObject = JSValueFactory.argumentsObject({});
        // Mark the arguments object so that callee/caller access throws
        argumentsObject.markAsArgumentsObject();
      }

      argumentsObject.setProperty(
        'length',
        JSValueFactory.number(args.length.toDouble()),
      );
      for (int i = 0; i < args.length; i++) {
        argumentsObject.setProperty(i.toString(), args[i]);
      }
      functionEnv.define('arguments', argumentsObject, BindingType.var_);

      // Create contexte d'execution pour la fonction async
      final functionContext = ExecutionContext(
        lexicalEnvironment: functionEnv,
        variableEnvironment: functionEnv,
        thisBinding: JSValueFactory.undefined(),
        function: null,
        arguments: args,
        debugName: 'AsyncFunction ${node.id?.name ?? 'anonymous'}',
      );

      _executionStack.push(functionContext);
      try {
        // Executer le corps de la fonction async
        final result = node.body.accept(this);

        // La fonction s'est terminee normalement
        task.complete(result);
        resolve.call([result]);
      } catch (e) {
        if (e is FlowControlException && e.type == ExceptionType.return_) {
          // Return statement - la fonction se termine avec la valeur de retour
          final returnValue = e.value ?? JSValueFactory.undefined();
          task.complete(returnValue);
          resolve.call([returnValue]);
        } else if (e is AsyncSuspensionException) {
          // La fonction a ete suspendue par un await
          // Ne rien faire, la tache sera reprise plus tard
        } else if (e is JSException) {
          // Erreur JavaScript (throw statement)
          final errorValue = e.value;
          task.fail(errorValue);
          reject.call([errorValue]);
          // Only run pending tasks if task was suspended and is now running
          if (task.state == AsyncTaskState.running) {
            _asyncScheduler.runPendingTasks(this);
          }
        } else {
          // Erreur inattendue
          final errorValue = e is JSValue
              ? e
              : JSValueFactory.string(e.toString());
          task.fail(errorValue);
          reject.call([errorValue]);
          // Only run pending tasks if task was suspended and is now running
          if (task.state == AsyncTaskState.running) {
            _asyncScheduler.runPendingTasks(this);
          }
        }
      } finally {
        _executionStack.pop();
      }
    } catch (e) {
      // Erreur lors de la configuration
      final errorValue = e is JSException
          ? e.value
          : (e is JSValue ? e : JSValueFactory.string(e.toString()));
      task.fail(errorValue);
      reject.call([errorValue]);
      // Only run pending tasks if task was suspended and is now running
      if (task.state == AsyncTaskState.running) {
        _asyncScheduler.runPendingTasks(this);
      }
    }
  }

  @override
  JSValue visitAsyncFunctionExpression(AsyncFunctionExpression node) {
    // Validate async function constraints before creating the function
    _validateAsyncFunctionConstraints(node);

    // Createe fonction async anonyme qui retourne une Promise
    final currentEnv = _currentContext().lexicalEnvironment;

    // Calculate function length (number of params until first default or rest)
    int functionLength = 0;
    for (final param in node.params) {
      if (param.defaultValue != null || param.isRest) {
        break;
      }
      functionLength++;
    }

    JSValue functionValue;

    if (node.isGenerator) {
      // Async generator expression: returns an async generator object
      functionValue = JSNativeFunction(
        functionName: node.id?.name ?? 'anonymous',
        expectedArgs: functionLength,
        nativeImpl: (args) {
          // Return an async generator
          return _createAsyncGenerator(
            // Convert AsyncFunctionExpression to AsyncFunctionDeclaration for _createAsyncGenerator
            AsyncFunctionDeclaration(
              id:
                  node.id ??
                  IdentifierExpression(name: 'anonymous', line: 0, column: 0),
              params: node.params,
              body: node.body,
              line: node.line,
              column: node.column,
              isGenerator: true,
            ),
            args,
            currentEnv,
          );
        },
      );
    } else {
      final asyncFunction = JSNativeFunction(
        functionName: node.id?.name ?? 'anonymous',
        expectedArgs: functionLength,
        nativeImpl: (args) {
          // Createe Promise qui sera resolue quand la fonction async se termine
          final promise = JSPromise(
            JSNativeFunction(
              functionName: 'asyncResolver',
              nativeImpl: (executorArgs) {
                final resolve = executorArgs[0] as JSNativeFunction;
                final reject = executorArgs[1] as JSNativeFunction;

                // Createe tache asynchrone pour gerer l'execution
                final taskId =
                    'async_expr_${node.id?.name ?? 'anonymous'}_${DateTime.now().millisecondsSinceEpoch}';
                final asyncTask = AsyncTask(taskId);

                // Add the task to the scheduler
                _asyncScheduler.addTask(asyncTask);

                // Demarrer l'execution asynchrone
                _executeAsyncFunctionExpression(
                  asyncTask,
                  node,
                  args,
                  currentEnv,
                  resolve,
                  reject,
                );

                return JSValueFactory.undefined();
              },
            ),
          );

          return promise;
        },
      );

      functionValue = asyncFunction;
    }

    return functionValue;
  }

  @override
  JSValue visitAwaitExpression(AwaitExpression node) {
    // Check first if we are in an async function with a task in progress
    final asyncTask = _executionStack.current.asyncTask;

    // ES2022: Verifier si on est dans un module avec top-level await
    final inModuleWithTLA =
        _currentModule != null && _currentModule!.hasTopLevelAwait;

    if (asyncTask is AsyncTask) {
      // Check if an expected result is already available (execution resume)
      final awaitedResult = asyncTask.getNextAwaitedResult();
      if (awaitedResult != null) {
        // If it's an error, throw it
        if (awaitedResult.isError) {
          throw JSException(awaitedResult.value);
        }
        // Sinon, retourner la valeur
        return awaitedResult.value;
      }
    }
    final value = node.argument.accept(this);

    if (value is JSPromise) {
      // Check the Promise state
      if (value.state == PromiseState.fulfilled) {
        // Promise resolue - retourner la valeur
        return value.value ?? JSValueFactory.undefined();
      } else if (value.state == PromiseState.rejected) {
        // Promise rejetee - lever une erreur
        final reason =
            value.reason ?? JSValueFactory.string('Promise rejected');
        throw reason;
      } else {
        // Promise en attente
        if (asyncTask is AsyncTask) {
          // Dans une fonction async - suspendre l'execution
          _asyncScheduler.suspendTask(asyncTask, value);
          throw AsyncSuspensionException('Awaiting pending Promise');
        } else if (inModuleWithTLA) {
          // ES2022: Top-level await dans un module - retourner la Promise
          // Elle sera attendue par _evalModuleAsync
          return value;
        } else {
          // Pas dans une fonction async ni dans un module TLA - retourner la Promise elle-meme
          // Cela permet a evalAsync d'attendre la Promise
          return value;
        }
      }
    } else {
      // Pas une Promise - retourner la valeur telle quelle
      return value;
    }
  }

  @override
  JSValue visitYieldExpression(YieldExpression node) {
    final context = _currentGeneratorContext;

    if (context == null) {
      throw JSError('yield expression outside of generator function');
    }

    // Use the yield expression's object identity as a stable, unique ID
    final yieldID = identityHashCode(node);

    // If we're resuming from a previous yield, check if this is the one
    if (context.resumingFromYield && context.lastYieldNumber != null) {
      final suspensionPoint = context.lastYieldNumber!;

      if (yieldID == suspensionPoint) {
        // This is the EXACT yield we're resuming from
        // Return the input value and clear the flag
        context.resumingFromYield = false;
        return context.inputValue ?? JSValueFactory.undefined();
      } else if (context.yieldResults.containsKey(yieldID)) {
        // This yield has a cached value from a previous execution
        // Return it
        return context.yieldResults[yieldID]!;
      } else {
        // This is a new yield encountered during resumption
        // We need to continue resuming until we pass the suspension point,
        // then start evaluating new yields. Since we haven't reached the
        // suspension point yet, this must be a yield that comes AFTER it
        // that we haven't seen before. We should evaluate it and it will throw.
        final value = node.argument != null
            ? node.argument!.accept(this)
            : JSValueFactory.undefined();

        // Cache the value for this yield
        context.yieldResults[yieldID] = value;

        context.lastYieldNumber = yieldID;
        context.lastYieldStatementIndex = context.currentStatementIndex;
        throw GeneratorYieldException(value, delegate: node.delegate);
      }
    }

    // Not resuming: first time encountering this yield
    // Evaluate the yield value
    final value = node.argument != null
        ? node.argument!.accept(this)
        : JSValueFactory.undefined();

    // Cache the value
    context.yieldResults[yieldID] = value;

    // Yield normally
    context.lastYieldNumber = yieldID;
    context.lastYieldStatementIndex = context.currentStatementIndex;
    throw GeneratorYieldException(value, delegate: node.delegate);
  }

  GeneratorExecutionContext? _currentGeneratorContext;

  @override
  JSValue visitClassDeclaration(ClassDeclaration node) {
    // Use lexical environment to capture let/const variables
    // (not just variableEnvironment which only has var/function)
    final currentEnv = _currentEnvironment();
    final className = node.id!.name;

    // In module mode, certain identifiers cannot be used as class names
    if (moduleMode) {
      if (className == 'await' || className == 'yield') {
        throw JSSyntaxError(
          'The reserved word \'$className\' cannot be used as an identifier in module context',
        );
      }
    }

    // BUGFIX: In async function resumption, skip class declarations that already exist
    // This prevents re-declaration errors when the async function body is re-executed after an await
    final asyncTask = _executionStack.current.asyncTask;
    if (asyncTask is AsyncTask && currentEnv.hasLocal(className)) {
      // Class already exists from previous execution, skip re-declaration
      return JSValueFactory.undefined();
    }

    // Resoudre la superclasse si elle existe
    JSClass? superClass;
    JSFunction? superFunction;
    JSValue? superFunctionPrototype;
    bool extendsNull = false;
    if (node.superClass != null) {
      final superValue = node.superClass!.accept(this);
      if (superValue is JSClass) {
        superClass = superValue;
      } else if (superValue is JSFunction) {
        // Accepter aussi les fonctions natives comme Promise
        superFunction = superValue;
        // Validate that the superclass's prototype is valid (must be Object or Null)
        // Exception: Symbol is allowed even though its prototype is undefined
        // Store the prototype so we don't need to call the getter again in JSClass
        superFunctionPrototype = superFunction.getProperty('prototype');
        final functionName = superFunction is JSNativeFunction
            ? (superFunction).functionName
            : '';

        if (functionName != 'Symbol' &&
            !superFunctionPrototype.isNull &&
            superFunctionPrototype.type != JSValueType.object) {
          throw JSTypeError(
            'Class extends value\'s prototype must be an Object or null',
          );
        }
      } else if (superValue.isNull) {
        // class C extends null { } is valid - sets prototype to null
        extendsNull = true;
      } else {
        // ES6: Throw TypeError for invalid extends value
        throw JSTypeError('Class extends value is not a constructor or null');
      }
    }

    // Create a temporary placeholder for the class to bind the name in the closure environment
    // This creates a lexical scope where the class name can reference itself
    final classEnv = Environment.block(currentEnv);

    // Creer la classe avec l'environnement de closure
    // Pass the cached prototype to avoid calling the getter again
    final classValue = JSValueFactory.classValue(
      node,
      classEnv,
      superClass,
      superFunction,
      extendsNull,
      superFunctionPrototype,
    );

    // Now bind the class name in its own environment so methods can access it
    // ES6: The class name binding inside the class is immutable (const-like)
    classEnv.define(className, classValue, BindingType.const_);

    // Enregistrer la classe dans l'environnement courant
    currentEnv.define(className, classValue, BindingType.let_);

    return JSValueFactory.undefined();
  }

  @override
  JSValue visitClassExpression(ClassExpression node) {
    final currentEnv = _currentEnvironment();

    // In module mode, certain identifiers cannot be used as class names
    if (node.id != null && moduleMode) {
      final className = node.id!.name;
      if (className == 'await' || className == 'yield') {
        throw JSSyntaxError(
          'The reserved word \'$className\' cannot be used as an identifier in module context',
        );
      }
    }

    // Resoudre la superclasse si elle existe
    JSClass? superClass;
    JSFunction? superFunction;
    JSValue? superFunctionPrototype;
    bool extendsNull = false;
    if (node.superClass != null) {
      final superValue = node.superClass!.accept(this);
      if (superValue is JSClass) {
        superClass = superValue;
      } else if (superValue is JSFunction) {
        // Accepter aussi les fonctions natives comme Promise
        superFunction = superValue;
        // Validate that the superclass's prototype is valid (must be Object or Null)
        // Exception: Symbol is allowed even though its prototype is undefined
        // Store the prototype so we don't need to call the getter again in JSClass
        superFunctionPrototype = superFunction.getProperty('prototype');
        final functionName = superFunction is JSNativeFunction
            ? (superFunction).functionName
            : '';

        if (functionName != 'Symbol' &&
            !superFunctionPrototype.isNull &&
            superFunctionPrototype.type != JSValueType.object) {
          throw JSTypeError(
            'Class extends value\'s prototype must be an Object or null',
          );
        }
      } else if (superValue.isNull) {
        // class C extends null { } is valid - sets prototype to null
        extendsNull = true;
      } else {
        // ES6: Throw TypeError for invalid extends value
        throw JSTypeError('Class extends value is not a constructor or null');
      }
    }

    // Create a closure environment for the class
    final classEnv = Environment.block(currentEnv);

    // Creer la classe avec l'environnement de closure
    // For class expressions, we pass the node as a dynamic type (it has same structure as ClassDeclaration)
    // Pass the cached prototype to avoid calling the getter again
    final classValue = JSValueFactory.classValue(
      node,
      classEnv,
      superClass,
      superFunction,
      extendsNull,
      superFunctionPrototype,
    );

    // Pour les class expressions nommees, definir le nom dans l'environnement de la classe elle-meme
    // (comme pour les function expressions nommees)
    // ES6: The class name binding inside the class is immutable (const-like)
    if (node.id != null) {
      // The class name is only accessible inside the class body and closure
      classEnv.define(node.id!.name, classValue, BindingType.const_);
    }

    return classValue;
  }

  @override
  JSValue visitFieldDeclaration(FieldDeclaration node) {
    // Les champs de classe sont traites lors de la construction de l'instance
    // Cette methode ne devrait pas etre appelee directement
    throw UnimplementedError(
      'Field declarations should be handled in class instantiation',
    );
  }

  @override
  JSValue visitStaticBlockDeclaration(StaticBlockDeclaration node) {
    // Les blocs statiques sont executes lors de la definition de la classe
    // Cette methode ne devrait pas etre appelee directement
    throw UnimplementedError(
      'Static blocks should be handled in class definition',
    );
  }

  @override
  JSValue visitSuperExpression(SuperExpression node) {
    // Verifier si on est dans un contexte de classe
    final currentClassContext = _currentClassContext;

    // D'abord chercher super dans l'environnement (pour les constructeurs)
    final currentEnv = _currentContext().variableEnvironment;
    try {
      final superFunction = currentEnv.get('super');
      if (superFunction != JSValueFactory.undefined()) {
        return superFunction;
      }
    } catch (e) {
      // super n'est pas dans l'environnement, continuer
    }

    if (currentClassContext?.superClass != null) {
      return currentClassContext!.superClass!;
    }

    // Support for native function superclass (Promise, Array, etc.)
    if (currentClassContext?.superFunction != null) {
      return currentClassContext!.superFunction!;
    }

    // Default: return Object.prototype (ES6 spec: classes implicitly extend Object)
    // This allows super.property access in classes without explicit extends
    final objectPrototype = globalEnvironment
        .get('Object')
        .toObject()
        .getProperty('prototype');
    if (objectPrototype is JSObject) {
      return objectPrototype;
    }

    // Si on arrive ici, super n'est pas defini
    throw JSReferenceError('super is not defined');
  }

  @override
  JSValue visitIfStatement(IfStatement node) {
    final testValue = node.test.accept(this);

    try {
      if (testValue.toBoolean()) {
        final bodyValue = node.consequent.accept(this);
        return bodyValue;
      } else if (node.alternate != null) {
        final altValue = node.alternate!.accept(this);
        return altValue;
      }
      return JSValueFactory.undefined();
    } on FlowControlException catch (e) {
      // According to ECMA-262 sec-if-statement-runtime-semantics-evaluation:
      // Return Completion(UpdateEmpty(stmtCompletion, undefined))
      // This means if the statement breaks/continues, the if must propagate that
      // but with UpdateEmpty applied to the completion value
      if (e.type == ExceptionType.break_ || e.type == ExceptionType.continue_) {
        // Apply UpdateEmpty: if completion value is not set, use undefined
        final completionValue = e.completionValue ?? JSValueFactory.undefined();
        // Re-throw with updated completion value
        throw FlowControlException(
          e.type,
          label: e.label,
          completionValue: completionValue,
        );
      }
      rethrow;
    }
  }

  @override
  JSValue visitWhileStatement(WhileStatement node) {
    // Hoist var declarations from the loop body to the current variable environment
    // This must happen BEFORE entering the loop
    if (node.body is BlockStatement) {
      _hoistDeclarations((node.body as BlockStatement).body);
    } else {
      _hoistDeclarations([node.body]);
    }

    JSValue lastValue = JSValueFactory.undefined();

    try {
      while (true) {
        final testValue = node.test.accept(this);
        if (!testValue.toBoolean()) break;

        try {
          lastValue = node.body.accept(this);
        } on FlowControlException catch (e) {
          // Always capture the last value before an abrupt completion
          if ((e.type == ExceptionType.break_ ||
                  e.type == ExceptionType.continue_) &&
              e.completionValue == null) {
            // Re-throw with the last normal value attached
            throw FlowControlException(
              e.type,
              label: e.label,
              completionValue: lastValue,
            );
          }
          rethrow;
        }
      }
    } on FlowControlException catch (e) {
      if (e.type == ExceptionType.break_) {
        if (e.label != null) {
          // Break avec label - laisser le niveau superieur gerer
          rethrow;
        }
        // Break normal - return completion value if available
        if (e.completionValue != null) {
          return e.completionValue!;
        }
        return JSValueFactory.undefined();
      } else if (e.type == ExceptionType.continue_) {
        if (e.label != null) {
          // Continue avec label - laisser le niveau superieur gerer
          rethrow;
        }
        // Continue - reprendre la boucle with completion value
        return visitWhileStatement(node);
      } else {
        rethrow;
      }
    }

    return lastValue;
  }

  @override
  JSValue visitForStatement(ForStatement node) {
    // Si on est dans un generateur, utiliser la version avec gestion de continuation
    if (_currentGeneratorContext != null) {
      return _visitForStatementInGenerator(node);
    }

    // Pour les boucles for avec let/const, chaque iteration a son propre environnement lexical
    // pour permettre aux closures de capturer la valeur correcte

    // Verifier si l'initialisation contient let/const
    bool hasLetConst = false;
    if (node.init is VariableDeclaration) {
      final varDecl = node.init as VariableDeclaration;
      hasLetConst = varDecl.kind == 'let' || varDecl.kind == 'const';
    }

    if (hasLetConst) {
      return _visitForStatementWithLetConst(node);
    } else {
      return _visitForStatementStandard(node);
    }
  }

  /// Version speciale de visitForStatement pour les generateurs
  /// Permet de reprendre la boucle apres un yield
  JSValue _visitForStatementInGenerator(ForStatement node) {
    final context = _currentGeneratorContext!;

    // Chercher une continuation existante pour cette boucle
    GeneratorContinuation? continuation;
    for (var cont in context.continuationStack) {
      if (cont.statement == node) {
        continuation = cont;
        break;
      }
    }

    int startIteration = 0;
    bool isFirstRun = continuation == null;

    if (continuation != null) {
      // Reprendre depuis l'iteration sauvegardee
      startIteration = continuation.state['iteration'] ?? 0;
      // Retirer la continuation de la pile car on va la recreer si necessaire
      context.continuationStack.remove(continuation);
    }

    // Initialisation - seulement la premiere fois
    if (isFirstRun && node.init != null) {
      node.init!.accept(this);
    }

    // Create scope pour le corps de la boucle
    final parentEnv = _currentEnvironment();
    final forEnv = Environment.block(parentEnv);

    final forContext = ExecutionContext(
      lexicalEnvironment: forEnv,
      variableEnvironment: _currentContext().variableEnvironment,
      thisBinding: _currentContext().thisBinding,
      strictMode: _currentContext().strictMode,
      debugName: 'For',
    );

    _executionStack.push(forContext);

    try {
      JSValue lastValue = JSValueFactory.undefined();
      int iteration = startIteration; // Commence a l'iteration sauvegardee

      // Si on reprend, faire l'update de l'iteration precedente d'abord
      bool needsUpdate = !isFirstRun && startIteration > 0;

      try {
        while (true) {
          // Si on doit faire l'update de l'iteration precedente
          if (needsUpdate) {
            if (node.update != null) {
              node.update!.accept(this);
            }
            iteration++; // Incrementer car on a fait l'update
            needsUpdate = false;
          }

          // Test de la condition
          if (node.test != null) {
            final testValue = node.test!.accept(this);
            if (!testValue.toBoolean()) break;
          }

          try {
            // Corps de la boucle
            lastValue = node.body.accept(this);
          } on GeneratorYieldException {
            // Un yield s'est produit dans le corps
            // Sauvegarder l'etat: on veut reprendre a la PROCHAINE iteration
            // (apres avoir fait l'update)
            context.continuationStack.add(
              GeneratorContinuation(node, state: {'iteration': iteration + 1}),
            );

            // Relancer l'exception pour que _executeGenerator la capture
            rethrow;
          } on FlowControlException catch (e) {
            if (e.type == ExceptionType.break_) {
              if (e.label == null) {
                break;
              } else {
                rethrow;
              }
            } else if (e.type == ExceptionType.continue_) {
              if (e.label == null) {
                // Continue - passer a l'iteration suivante
              } else {
                rethrow;
              }
            } else {
              rethrow;
            }
          }

          // Update
          if (node.update != null) {
            node.update!.accept(this);
          }

          iteration++;
        }
      } on FlowControlException catch (e) {
        if (e.type == ExceptionType.continue_ && e.label != null) {
          rethrow;
        } else if (e.type == ExceptionType.break_ && e.label != null) {
          rethrow;
        }
      }

      _executionStack.pop();
      return lastValue;
    } catch (e) {
      // En cas d'erreur, s'assurer que le contexte est retire
      _executionStack.pop();
      rethrow;
    }
  }

  /// Gestion standard des boucles for (avec var ou sans declaration)
  JSValue _visitForStatementStandard(ForStatement node) {
    // Initialisation - se fait dans le scope courant
    if (node.init != null) {
      node.init!.accept(this);
    }

    // Hoist var declarations from loop body before entering the loop
    if (node.body is BlockStatement) {
      _hoistDeclarations((node.body as BlockStatement).body);
    } else {
      _hoistDeclarations([node.body]);
    }

    // Create scope pour le corps de la boucle seulement
    final parentEnv = _currentEnvironment();
    final forEnv = Environment.block(parentEnv);

    final forContext = ExecutionContext(
      lexicalEnvironment: forEnv,
      variableEnvironment: _currentContext().variableEnvironment,
      thisBinding: _currentContext().thisBinding,
      strictMode: _currentContext().strictMode,
      debugName: 'For',
    );

    _executionStack.push(forContext);

    try {
      JSValue lastValue = JSValueFactory.undefined();

      try {
        while (true) {
          // Test - dans le scope de la boucle
          if (node.test != null) {
            final testValue = node.test!.accept(this);
            if (!testValue.toBoolean()) break;
          }

          try {
            // Corps
            lastValue = node.body.accept(this);
          } on FlowControlException catch (e) {
            // Capture completion value before abrupt completion
            if ((e.type == ExceptionType.break_ ||
                    e.type == ExceptionType.continue_) &&
                e.completionValue == null) {
              throw FlowControlException(
                e.type,
                label: e.label,
                completionValue: lastValue,
              );
            }

            if (e.type == ExceptionType.break_) {
              if (e.label == null) {
                // Break sans label - sortir de cette boucle
                lastValue = e.completionValue ?? JSValueFactory.undefined();
                break;
              } else {
                // Break avec label - propager vers le niveau superieur
                rethrow;
              }
            } else if (e.type == ExceptionType.continue_) {
              if (e.label == null) {
                // Continue sans label - faire l'update et reprendre la boucle
                // Sauvegarder la completion value
                lastValue = e.completionValue ?? JSValueFactory.undefined();
                // L'update se fait dans le scope courant (parent), pas dans le scope de la boucle
                _executionStack.pop();
                try {
                  if (node.update != null) {
                    node.update!.accept(this);
                  }
                } finally {
                  _executionStack.push(forContext);
                }
                continue;
              } else {
                // Continue avec label - propager vers le niveau superieur
                rethrow;
              }
            } else {
              rethrow;
            }
          }

          // Update - se fait dans le scope courant (parent), pas dans le scope de la boucle
          _executionStack.pop();
          try {
            if (node.update != null) {
              node.update!.accept(this);
            }
          } finally {
            _executionStack.push(forContext);
          }
        }
      } catch (e) {
        rethrow;
      }

      return lastValue;
    } finally {
      _executionStack.pop();
    }
  }

  /// Gestion speciale des boucles for avec let/const (nouvel environnement par iteration)
  JSValue _visitForStatementWithLetConst(ForStatement node) {
    // Hoist var declarations from loop body before entering the loop
    if (node.body is BlockStatement) {
      _hoistDeclarations((node.body as BlockStatement).body);
    } else {
      _hoistDeclarations([node.body]);
    }

    // Create environnement pour l'initialisation
    final parentEnv = _currentEnvironment();
    final initEnv = Environment.block(parentEnv);

    final initContext = ExecutionContext(
      lexicalEnvironment: initEnv,
      variableEnvironment: _currentContext().variableEnvironment,
      thisBinding: _currentContext().thisBinding,
      strictMode: _currentContext().strictMode,
      debugName: 'ForInit',
      asyncTask:
          _currentContext().asyncTask, // Heriter l'asyncTask du contexte parent
    );

    _executionStack.push(initContext);

    try {
      // Initialisation dans l'environnement d'init
      if (node.init != null) {
        node.init!.accept(this);
      }

      JSValue lastValue = JSValueFactory.undefined();

      while (true) {
        // Test dans l'environnement d'init
        if (node.test != null) {
          final testValue = node.test!.accept(this);
          if (!testValue.toBoolean()) break;
        }

        // Create NOUVEL environnement pour chaque iteration
        // Ceci permet aux closures de capturer la valeur correcte
        final iterationEnv = Environment.block(initEnv);

        // Copier les variables let/const de l'init dans l'environnement d'iteration
        final varDecl = node.init as VariableDeclaration;
        for (final decl in varDecl.declarations) {
          if (decl.id is IdentifierPattern) {
            final identifierPattern = decl.id as IdentifierPattern;
            final name = identifierPattern.name;
            final value = initEnv.get(name);
            final bindingType = varDecl.kind == 'let'
                ? BindingType.let_
                : BindingType.const_;
            iterationEnv.define(name, value, bindingType);
          }
          // Pour les patterns de destructuring, ils sont deja geres dans visitVariableDeclaration
        }

        final iterationContext = ExecutionContext(
          lexicalEnvironment: iterationEnv,
          variableEnvironment: _currentContext().variableEnvironment,
          thisBinding: _currentContext().thisBinding,
          strictMode: _currentContext().strictMode,
          debugName: 'ForIteration',
          asyncTask: _currentContext()
              .asyncTask, // Heriter l'asyncTask du contexte parent
        );

        _executionStack.push(iterationContext);

        try {
          try {
            // Corps dans l'environnement d'iteration
            lastValue = node.body.accept(this);
          } on FlowControlException catch (e) {
            // Capture completion value before abrupt completion
            if ((e.type == ExceptionType.break_ ||
                    e.type == ExceptionType.continue_) &&
                e.completionValue == null) {
              throw FlowControlException(
                e.type,
                label: e.label,
                completionValue: lastValue,
              );
            }

            if (e.type == ExceptionType.break_) {
              if (e.label == null) {
                lastValue = e.completionValue ?? JSValueFactory.undefined();
                break;
              } else {
                rethrow;
              }
            } else if (e.type == ExceptionType.continue_) {
              if (e.label == null) {
                // Continue - mettre a jour dans l'init env et continuer
                lastValue = e.completionValue ?? JSValueFactory.undefined();
                _executionStack.pop(); // sortir de iteration
                if (node.update != null) {
                  node.update!.accept(this); // dans init env
                }
                continue;
              } else {
                rethrow;
              }
            } else {
              rethrow;
            }
          }

          // Update - dans l'environnement d'init
          _executionStack.pop(); // sortir de iteration
          if (node.update != null) {
            node.update!.accept(this);
          }
        } catch (e) {
          _executionStack.pop(); // sortir de iteration en cas d'erreur
          rethrow;
        }
      }

      return lastValue;
    } finally {
      _executionStack.pop(); // sortir de init
    }
  }

  @override
  JSValue visitDoWhileStatement(DoWhileStatement node) {
    // Hoist var declarations from the loop body to the current variable environment
    // This must happen BEFORE entering the loop
    if (node.body is BlockStatement) {
      _hoistDeclarations((node.body as BlockStatement).body);
    } else {
      _hoistDeclarations([node.body]);
    }

    JSValue lastValue = JSValueFactory.undefined();

    try {
      do {
        try {
          lastValue = node.body.accept(this);
        } on FlowControlException catch (e) {
          // Always capture the last value before an abrupt completion
          if ((e.type == ExceptionType.break_ ||
                  e.type == ExceptionType.continue_) &&
              e.completionValue == null) {
            // Re-throw with the last normal value attached
            throw FlowControlException(
              e.type,
              label: e.label,
              completionValue: lastValue,
            );
          }
          if (e.type == ExceptionType.break_) {
            if (e.label == null) {
              // Break without label - use the completion value and exit loop
              // The completion value contains the value of the last statement before break
              lastValue = e.completionValue ?? JSValueFactory.undefined();
              break;
            } else {
              // Labeled break - let outer context handle it
              rethrow;
            }
          } else if (e.type == ExceptionType.continue_) {
            if (e.label == null) {
              // Continue without label - go to test condition
              // Save the completion value before continuing
              lastValue = e.completionValue ?? JSValueFactory.undefined();
              continue;
            } else {
              // Labeled continue - let outer context handle it
              rethrow;
            }
          } else {
            // return, throw, etc.
            rethrow;
          }
        }
      } while (node.test.accept(this).toBoolean());
    } on FlowControlException catch (e) {
      if ((e.type == ExceptionType.break_ ||
              e.type == ExceptionType.continue_) &&
          e.label != null) {
        // Labeled break/continue already handled in inner try
        rethrow;
      }
      rethrow;
    }

    return lastValue;
  }

  @override
  JSValue visitForInStatement(ForInStatement node) {
    final objectValue = node.right.accept(this);
    JSValue lastValue = JSValueFactory.undefined();

    // Create scope pour la boucle
    final parentEnv = _currentEnvironment();
    final forInEnv = Environment.block(parentEnv);

    final forInContext = ExecutionContext(
      lexicalEnvironment: forInEnv,
      variableEnvironment: _currentContext().variableEnvironment,
      thisBinding: _currentContext().thisBinding,
      strictMode: _currentContext().strictMode,
      debugName: 'ForIn',
      asyncTask:
          _currentContext().asyncTask, // Heriter l'asyncTask du contexte parent
    );

    _executionStack.push(forInContext);

    try {
      if (objectValue.type == JSValueType.object) {
        final object = objectValue.toObject();

        for (final key in object.getForInPropertyNames()) {
          try {
            // Assigner la cle a la variable de la boucle
            if (node.left is VariableDeclaration) {
              final varDecl = node.left as VariableDeclaration;
              final pattern = varDecl.declarations.first.id;
              if (pattern is IdentifierPattern) {
                // Pour var, utiliser le variableEnvironment (function scope)
                _currentContext().variableEnvironment.define(
                  pattern.name,
                  JSValueFactory.string(key),
                  BindingType.var_,
                );
              } else {
                // Pour les patterns de destructuring, assigner la valeur
                _assignToPattern(pattern, JSValueFactory.string(key));
              }
            } else if (node.left is IdentifierExpression) {
              final identifier = node.left as IdentifierExpression;
              _currentEnvironment().set(
                identifier.name,
                JSValueFactory.string(key),
              );
            } else if (node.left is MemberExpression) {
              final memberExpr = node.left as MemberExpression;
              // Evaluer l'objet cible
              final target = memberExpr.object.accept(this);
              if (target.type == JSValueType.object) {
                final targetObj = target.toObject();
                // Assigner la cle a la propriete
                final keyValue = memberExpr.computed
                    ? memberExpr.property.accept(this)
                    : JSValueFactory.string(
                        (memberExpr.property as IdentifierExpression).name,
                      );

                targetObj.setProperty(
                  keyValue.toString(),
                  JSValueFactory.string(key),
                );
              } else {
                throw JSTypeError('Cannot assign to property of non-object');
              }
            }

            lastValue = node.body.accept(this);
          } on FlowControlException catch (e) {
            if (e.type == ExceptionType.break_) {
              break;
            } else if (e.type == ExceptionType.continue_) {
              continue;
            } else {
              rethrow;
            }
          }
        }
      }

      return lastValue;
    } finally {
      _executionStack.pop();
    }
  }

  @override
  JSValue visitForOfStatement(ForOfStatement node) {
    final iterableValue = node.right.accept(this);
    JSValue lastValue = JSValueFactory.undefined();

    // Create scope pour la boucle
    final parentEnv = _currentEnvironment();
    final forOfEnv = Environment.block(parentEnv);

    final forOfContext = ExecutionContext(
      lexicalEnvironment: forOfEnv,
      variableEnvironment: _currentContext().variableEnvironment,
      thisBinding: _currentContext().thisBinding,
      strictMode: _currentContext().strictMode,
      debugName: 'ForOf',
      asyncTask:
          _currentContext().asyncTask, // Heriter l'asyncTask du contexte parent
    );

    _executionStack.push(forOfContext);

    try {
      // Support pour les strings
      if (iterableValue.type == JSValueType.string) {
        final stringValue = iterableValue.toString();
        for (int i = 0; i < stringValue.length; i++) {
          try {
            final charValue = JSValueFactory.string(stringValue[i]);

            // Assigner le caractere a la variable de la boucle
            if (node.left is VariableDeclaration) {
              final varDecl = node.left as VariableDeclaration;
              final pattern = varDecl.declarations.first.id;
              if (pattern is IdentifierPattern) {
                // Pour var, utiliser le variableEnvironment (function scope)
                _currentContext().variableEnvironment.define(
                  pattern.name,
                  charValue,
                  BindingType.var_,
                );
              } else {
                // Pour les patterns de destructuring, assigner la valeur
                _assignToPattern(pattern, charValue);
              }
            } else if (node.left is IdentifierExpression) {
              final identifier = node.left as IdentifierExpression;
              _currentEnvironment().set(identifier.name, charValue);
            }

            lastValue = node.body.accept(this);
          } on FlowControlException catch (e) {
            if (e.type == ExceptionType.break_) {
              break;
            } else if (e.type == ExceptionType.continue_) {
              continue;
            } else {
              rethrow;
            }
          }
        }
      }
      // Support pour les objets
      else if (iterableValue.type == JSValueType.object) {
        final iterable = iterableValue.toObject();

        // Check for Symbol.iterator first (ES6 iteration protocol)
        final symbolIteratorKey = JSSymbol.iterator.toString();
        final iteratorMethod = iterable.getProperty(symbolIteratorKey);

        if (iteratorMethod != JSValueFactory.undefined()) {
          // Call Symbol.iterator to get the iterator
          final iterator = callFunction(iteratorMethod, [], iterable);
          final iteratorObj = iterator.toObject();

          // Use the iterator protocol
          try {
            while (true) {
              final result = callFunction(
                iteratorObj.getProperty('next'),
                [],
                iteratorObj,
              );
              final resultObj = result.toObject();
              final done = resultObj.getProperty('done').toBoolean();
              if (done) break;

              final value = resultObj.getProperty('value');

              try {
                // Assigner la valeur a la variable de la boucle
                if (node.left is VariableDeclaration) {
                  final varDecl = node.left as VariableDeclaration;
                  final pattern = varDecl.declarations.first.id;
                  if (pattern is IdentifierPattern) {
                    // Pour var, utiliser le variableEnvironment (function scope)
                    _currentContext().variableEnvironment.define(
                      pattern.name,
                      value,
                      BindingType.var_,
                    );
                  } else {
                    // Pour les patterns de destructuring, assigner la valeur
                    _assignToPattern(pattern, value);
                  }
                } else if (node.left is IdentifierExpression) {
                  final identifier = node.left as IdentifierExpression;
                  _currentEnvironment().set(identifier.name, value);
                }

                lastValue = node.body.accept(this);
              } on FlowControlException catch (e) {
                if (e.type == ExceptionType.break_) {
                  break;
                } else if (e.type == ExceptionType.continue_) {
                  continue;
                } else {
                  rethrow;
                }
              }
            }
          } finally {
            // Call return() on the iterator when exiting (break, return, or exception)
            final returnMethod = iteratorObj.getProperty('return');
            if (returnMethod != JSValueFactory.undefined()) {
              try {
                callFunction(returnMethod, [], iteratorObj);
              } catch (e) {
                // Ignore errors from return()
              }
            }
          }
        }
        // Check if the object is an iterator (has a next method)
        else if (iterable.getProperty('next') != JSValueFactory.undefined()) {
          // Use the iterator protocol directly
          try {
            while (true) {
              final result = callFunction(
                iterable.getProperty('next'),
                [],
                iterable,
              );
              final resultObj = result.toObject();
              final done = resultObj.getProperty('done').toBoolean();
              if (done) break;

              final value = resultObj.getProperty('value');

              try {
                // Assigner la valeur a la variable de la boucle
                if (node.left is VariableDeclaration) {
                  final varDecl = node.left as VariableDeclaration;
                  final pattern = varDecl.declarations.first.id;
                  if (pattern is IdentifierPattern) {
                    // Pour var, utiliser le variableEnvironment (function scope)
                    _currentContext().variableEnvironment.define(
                      pattern.name,
                      value,
                      BindingType.var_,
                    );
                  } else {
                    // Pour les patterns de destructuring, assigner la valeur
                    _assignToPattern(pattern, value);
                  }
                } else if (node.left is IdentifierExpression) {
                  final identifier = node.left as IdentifierExpression;
                  _currentEnvironment().set(identifier.name, value);
                }

                lastValue = node.body.accept(this);
              } on FlowControlException catch (e) {
                if (e.type == ExceptionType.break_) {
                  break;
                } else if (e.type == ExceptionType.continue_) {
                  continue;
                } else {
                  rethrow;
                }
              }
            }
          } finally {
            // Call return() on the iterator when exiting (break, return, or exception)
            final returnMethod = iterable.getProperty('return');
            if (returnMethod != JSValueFactory.undefined()) {
              try {
                callFunction(returnMethod, [], iterable);
              } catch (e) {
                // Ignore errors from return()
              }
            }
          }
        }
        // Check if the object is a Map or Set
        else if (iterable is JSMap) {
          // Iterate over Map entries
          for (final entry in iterable.entries) {
            try {
              final value = JSValueFactory.array([entry.key, entry.value]);

              // Assigner la valeur a la variable de la boucle
              if (node.left is VariableDeclaration) {
                final varDecl = node.left as VariableDeclaration;
                final pattern = varDecl.declarations.first.id;
                if (pattern is IdentifierPattern) {
                  // Pour var, utiliser le variableEnvironment (function scope)
                  _currentContext().variableEnvironment.define(
                    pattern.name,
                    value,
                    BindingType.var_,
                  );
                } else {
                  // Pour les patterns de destructuring, assigner la valeur
                  _assignToPattern(pattern, value);
                }
              } else if (node.left is IdentifierExpression) {
                final identifier = node.left as IdentifierExpression;
                _currentEnvironment().set(identifier.name, value);
              }

              lastValue = node.body.accept(this);
            } on FlowControlException catch (e) {
              if (e.type == ExceptionType.break_) {
                break;
              } else if (e.type == ExceptionType.continue_) {
                continue;
              } else {
                rethrow;
              }
            }
          }
        } else if (iterable is JSSet) {
          // Iterate over Set values
          for (final value in iterable.values) {
            try {
              // Assigner la valeur a la variable de la boucle
              if (node.left is VariableDeclaration) {
                final varDecl = node.left as VariableDeclaration;
                final pattern = varDecl.declarations.first.id;
                if (pattern is IdentifierPattern) {
                  // Pour var, utiliser le variableEnvironment (function scope)
                  _currentContext().variableEnvironment.define(
                    pattern.name,
                    value,
                    BindingType.var_,
                  );
                } else {
                  // Pour les patterns de destructuring, assigner la valeur
                  _assignToPattern(pattern, value);
                }
              } else if (node.left is IdentifierExpression) {
                final identifier = node.left as IdentifierExpression;
                _currentEnvironment().set(identifier.name, value);
              }

              lastValue = node.body.accept(this);
            } on FlowControlException catch (e) {
              if (e.type == ExceptionType.break_) {
                break;
              } else if (e.type == ExceptionType.continue_) {
                continue;
              } else {
                rethrow;
              }
            }
          }
        }
        // Support pour les tableaux (si c'est un JSArray)
        else if (iterable is JSArray) {
          for (int i = 0; i < iterable.length; i++) {
            try {
              final value = iterable.get(i);

              // Assigner la valeur a la variable de la boucle
              if (node.left is VariableDeclaration) {
                final varDecl = node.left as VariableDeclaration;
                final pattern = varDecl.declarations.first.id;
                if (pattern is IdentifierPattern) {
                  // Pour var, utiliser le variableEnvironment (function scope)
                  _currentContext().variableEnvironment.define(
                    pattern.name,
                    value,
                    BindingType.var_,
                  );
                } else {
                  // Pour les patterns de destructuring, assigner la valeur
                  _assignToPattern(pattern, value);
                }
              } else if (node.left is IdentifierExpression) {
                final identifier = node.left as IdentifierExpression;
                _currentEnvironment().set(identifier.name, value);
              }

              lastValue = node.body.accept(this);
            } on FlowControlException catch (e) {
              if (e.type == ExceptionType.break_) {
                break;
              } else if (e.type == ExceptionType.continue_) {
                continue;
              } else {
                rethrow;
              }
            }
          }
        }
        // Support pour les objets (iteration sur les valeurs)
        else {
          for (final key in iterable.getPropertyNames()) {
            try {
              final value = iterable.getProperty(key);

              // Assigner la valeur a la variable de la boucle
              if (node.left is VariableDeclaration) {
                final varDecl = node.left as VariableDeclaration;
                final pattern = varDecl.declarations.first.id;
                if (pattern is IdentifierPattern) {
                  // Pour var, utiliser le variableEnvironment (function scope)
                  _currentContext().variableEnvironment.define(
                    pattern.name,
                    value,
                    BindingType.var_,
                  );
                } else {
                  // Pour les patterns de destructuring, assigner la valeur
                  _assignToPattern(pattern, value);
                }
              } else if (node.left is IdentifierExpression) {
                final identifier = node.left as IdentifierExpression;
                _currentEnvironment().set(identifier.name, value);
              }

              lastValue = node.body.accept(this);
            } on FlowControlException catch (e) {
              if (e.type == ExceptionType.break_) {
                break;
              } else if (e.type == ExceptionType.continue_) {
                continue;
              } else {
                rethrow;
              }
            }
          }
        }
      }
      // Si ce n'est ni une string ni un objet, lever une erreur
      else {
        throw JSTypeError('${iterableValue.type.name} is not iterable');
      }

      return lastValue;
    } finally {
      _executionStack.pop();
    }
  }

  @override
  JSValue visitLabeledStatement(LabeledStatement node) {
    // Pour les labeled statements, nous devons implementer la logique specifique
    // selon le type de statement labelle
    if (node.body is ForStatement) {
      return _visitLabeledForStatement(node.label, node.body as ForStatement);
    } else {
      // Pour les autres types de statements, comportement standard
      try {
        return node.body.accept(this);
      } on FlowControlException catch (e) {
        if (e.label == node.label) {
          if (e.type == ExceptionType.break_) {
            return e.completionValue ?? JSValueFactory.undefined();
          } else if (e.type == ExceptionType.continue_) {
            // Continue avec ce label sur un non-loop statement = break
            return e.completionValue ?? JSValueFactory.undefined();
          }
        }
        rethrow;
      }
    }
  }

  // Methode specialisee pour les boucles for avec label
  JSValue _visitLabeledForStatement(String label, ForStatement node) {
    // Initialisation - se fait dans le scope courant
    if (node.init != null) {
      node.init!.accept(this);
    }

    // Create scope pour le corps de la boucle seulement
    final parentEnv = _currentEnvironment();
    final forEnv = Environment.block(parentEnv);

    final forContext = ExecutionContext(
      lexicalEnvironment: forEnv,
      variableEnvironment: _currentContext().variableEnvironment,
      thisBinding: _currentContext().thisBinding,
      strictMode: _currentContext().strictMode,
      debugName: 'LabeledFor',
    );

    _executionStack.push(forContext);

    try {
      JSValue lastValue = JSValueFactory.undefined();

      try {
        while (true) {
          // Test - dans le scope de la boucle
          if (node.test != null) {
            final testValue = node.test!.accept(this);
            if (!testValue.toBoolean()) break;
          }

          try {
            // Corps
            lastValue = node.body.accept(this);
          } on FlowControlException catch (e) {
            if (e.type == ExceptionType.break_) {
              if (e.label == null || e.label == label) {
                // Break sans label ou avec notre label - sortir de cette boucle
                break;
              } else {
                // Break avec un autre label - propager vers le niveau superieur
                rethrow;
              }
            } else if (e.type == ExceptionType.continue_) {
              if (e.label == null || e.label == label) {
                // Continue sans label ou avec notre label - faire l'update et reprendre
                _executionStack.pop();
                try {
                  if (node.update != null) {
                    node.update!.accept(this);
                  }
                } finally {
                  _executionStack.push(forContext);
                }
                continue;
              } else {
                // Continue avec un autre label - propager vers le niveau superieur
                rethrow;
              }
            } else {
              rethrow;
            }
          }

          // Update - se fait dans le scope courant (parent), pas dans le scope de la boucle
          _executionStack.pop();
          try {
            if (node.update != null) {
              node.update!.accept(this);
            }
          } finally {
            _executionStack.push(forContext);
          }
        }
      } catch (e) {
        rethrow;
      }

      return lastValue;
    } finally {
      _executionStack.pop();
    }
  }

  @override
  JSValue visitReturnStatement(ReturnStatement node) {
    final value = node.argument?.accept(this) ?? JSValueFactory.undefined();
    throw FlowControlException.return_(value);
  }

  @override
  JSValue visitBreakStatement(BreakStatement node) {
    throw FlowControlException.break_(node.label);
  }

  @override
  JSValue visitContinueStatement(ContinueStatement node) {
    throw FlowControlException.continue_(node.label);
  }

  @override
  JSValue visitThrowStatement(ThrowStatement node) {
    final value = node.argument.accept(this);
    // Lancer une JSException avec la valeur evaluee
    throw JSException(value);
  }

  @override
  JSValue visitSwitchStatement(SwitchStatement node) {
    final discriminantValue = node.discriminant.accept(this);
    JSValue lastValue = JSValueFactory.undefined();
    bool hasMatched = false;

    try {
      for (final switchCase in node.cases) {
        // Si c'est un default case ou si la valeur match
        final shouldExecute =
            switchCase.test == null ||
            (switchCase.test != null &&
                discriminantValue.strictEquals(switchCase.test!.accept(this)));

        if (shouldExecute || hasMatched) {
          if (switchCase.test != null) {
            hasMatched = true;
          }

          // Executer les statements de ce case
          for (final statement in switchCase.consequent) {
            lastValue = statement.accept(this);
          }
        }
      }
    } on FlowControlException catch (e) {
      if (e.type == ExceptionType.break_) {
        // Break dans switch - sortir normalement
        return lastValue;
      }
      // Autres flow control exceptions (continue) - propager
      rethrow;
    }

    return lastValue;
  }

  @override
  JSValue visitSwitchCase(SwitchCase node) {
    // Cette methode ne devrait pas etre appelee directement
    // car les cases sont gerees par visitSwitchStatement
    throw UnimplementedError('visitSwitchCase should not be called directly');
  }

  @override
  JSValue visitWithStatement(WithStatement node) {
    // En strict mode, le statement with est interdit
    if (_currentContext().strictMode) {
      throw JSSyntaxError('Strict mode code may not include a with statement');
    }

    // Evaluate the object (for potential side effects)
    final objectValue = node.object.accept(this);

    // Verify that it is an object
    if (!objectValue.isObject &&
        !objectValue.isNull &&
        !objectValue.isUndefined) {
      // In JavaScript, with converts the value to an object
      // To simplify, we throw an error if it is not an object
      throw JSTypeError('with statement requires an object');
    }

    // Execute the body
    // Note: A real implementation should modify the scope to include
    // les proprietes de l'objet, mais cela necessite un environnement special
    return node.body.accept(this);
  }

  @override
  JSValue visitTryStatement(TryStatement node) {
    JSValue? finallyResult;

    try {
      // Executer le bloc try
      return node.block.accept(this);
    } on JSException catch (jsError) {
      // Une exception JavaScript a ete lancee
      if (node.handler != null) {
        // Il y a un catch block
        try {
          return _executeCatch(node.handler!, jsError);
        } catch (e) {
          // Si le catch block lance une exception, executer finally puis relancer
          if (node.finalizer != null) {
            try {
              finallyResult = node.finalizer!.accept(this);
            } catch (_) {
              // Si finally lance une exception, elle remplace l'exception du catch
              rethrow;
            }
          }
          rethrow;
        }
      } else {
        // Pas de catch block, executer finally puis relancer
        if (node.finalizer != null) {
          try {
            finallyResult = node.finalizer!.accept(this);
          } catch (_) {
            // Si finally lance une exception, elle remplace l'exception originale
            rethrow;
          }
        }
        rethrow;
      }
    } on FlowControlException {
      // Break/continue - propager apres finally
      if (node.finalizer != null) {
        try {
          finallyResult = node.finalizer!.accept(this);
        } catch (_) {
          // Si finally lance une exception, elle remplace le flow control
          rethrow;
        }
      }
      rethrow; // Propager le break/continue
    } on AsyncSuspensionException {
      // Async suspension - propager a travers les try-catch (comme break/continue)
      if (node.finalizer != null) {
        try {
          finallyResult = node.finalizer!.accept(this);
        } catch (_) {
          // Si finally lance une exception, elle remplace la suspension
          rethrow;
        }
      }
      rethrow; // Propager la suspension
    } on JSError catch (jsError) {
      // Erreurs JavaScript (JSTypeError, JSReferenceError, etc.) - les convertir en JSException
      // Recuperer le prototype approprie depuis le constructeur global
      JSObject? prototype;
      try {
        final constructorName = jsError.name;
        final constructor = _globalEnvironment.get(constructorName);
        if (constructor is JSFunction && constructor is JSObject) {
          final proto = constructor.getProperty('prototype');
          if (proto is JSObject) {
            prototype = proto;
          }
        }
      } catch (_) {
        // Si on ne peut pas recuperer le prototype, continuer sans
      }
      final errorValue = JSErrorObjectFactory.fromDartError(jsError, prototype);
      final jsException = JSException(errorValue);
      if (node.handler != null) {
        try {
          return _executeCatch(node.handler!, jsException);
        } catch (catchError) {
          if (node.finalizer != null) {
            try {
              finallyResult = node.finalizer!.accept(this);
            } catch (_) {
              rethrow;
            }
          }
          rethrow;
        }
      } else {
        if (node.finalizer != null) {
          try {
            finallyResult = node.finalizer!.accept(this);
          } catch (_) {
            rethrow;
          }
        }
        rethrow;
      }
    } catch (e) {
      // Autres exceptions Dart - les traiter comme des erreurs JavaScript
      final jsError = JSException(JSValueFactory.string('Internal error: $e'));
      if (node.handler != null) {
        try {
          return _executeCatch(node.handler!, jsError);
        } catch (catchError) {
          if (node.finalizer != null) {
            try {
              finallyResult = node.finalizer!.accept(this);
            } catch (_) {
              rethrow;
            }
          }
          rethrow;
        }
      } else {
        if (node.finalizer != null) {
          try {
            finallyResult = node.finalizer!.accept(this);
          } catch (_) {
            rethrow;
          }
        }
        rethrow;
      }
    } finally {
      // Executer le bloc finally s'il y en a un et qu'il n'a pas encore ete execute
      if (node.finalizer != null && finallyResult == null) {
        try {
          node.finalizer!.accept(this);
        } catch (_) {
          // Si finally lance une exception, elle remplace tout le reste
          rethrow;
        }
      }
    }
  }

  @override
  JSValue visitCatchClause(CatchClause node) {
    // Cette methode ne devrait pas etre appelee directement
    // Elle est geree par visitTryStatement via _executeCatch
    throw JSError('CatchClause should not be visited directly');
  }

  /// Execute un bloc catch avec l'exception appropriee
  JSValue _executeCatch(CatchClause catchClause, JSException exception) {
    // Create nouvel environnement pour le catch block
    final parentEnv = _currentEnvironment();
    final catchEnv = Environment.block(parentEnv);

    // Si il y a un parametre de catch, l'associer a la valeur de l'exception
    if (catchClause.param != null) {
      final paramName = catchClause.param!.name;
      final exceptionValue = exception.toJSValue();
      catchEnv.define(paramName, exceptionValue, BindingType.let_);
    }

    // Create nouveau contexte d'execution pour le catch block
    final catchContext = ExecutionContext(
      lexicalEnvironment: catchEnv,
      variableEnvironment: _currentContext().variableEnvironment,
      thisBinding: _currentContext().thisBinding,
      strictMode: _currentContext().strictMode,
      debugName: 'Catch',
    );

    _executionStack.push(catchContext);

    try {
      // Executer le corps du catch
      return catchClause.body.accept(this);
    } finally {
      // Restaurer le contexte precedent
      _executionStack.pop();
    }
  }

  // ===== EXPRESSIONS =====

  @override
  JSValue visitLiteralExpression(LiteralExpression node) {
    // Verifier si c'est un ancien litteral octal en strict mode
    if (node.type == 'legacyOctal' && _currentContext().strictMode) {
      throw JSSyntaxError('Octal literals are not allowed in strict mode');
    }

    return switch (node.type) {
      'number' => JSValueFactory.number(node.value),
      'bigint' => JSValueFactory.bigint(node.value),
      'legacyOctal' => JSValueFactory.number(
        node.value,
      ), // En mode non-strict, traiter comme un nombre
      'string' => JSValueFactory.string(node.value),
      'template' => JSValueFactory.string(
        node.value,
      ), // Template literals sont des strings
      'boolean' => JSValueFactory.boolean(node.value),
      'null' => JSValueFactory.nullValue(),
      'undefined' => JSValueFactory.undefined(),
      _ => throw JSError('Unknown literal type: ${node.type}'),
    };
  }

  @override
  JSValue visitRegexLiteralExpression(RegexLiteralExpression node) {
    try {
      return JSRegExpFactory.create(node.pattern, node.flags);
    } catch (e) {
      throw JSSyntaxError(
        'Invalid regular expression: /${node.pattern}/${node.flags}',
      );
    }
  }

  @override
  JSValue visitTemplateLiteralExpression(TemplateLiteralExpression node) {
    final buffer = StringBuffer();

    // Les quasis et expressions sont entrelaces
    // `Hello ${name}!` → quasis: ['Hello ', '!'], expressions: [name]
    for (int i = 0; i < node.quasis.length; i++) {
      buffer.write(node.quasis[i]);

      if (i < node.expressions.length) {
        // Evaluer l'expression et la convertir en string
        final value = node.expressions[i].accept(this);
        buffer.write(value.toString());
      }
    }

    return JSValueFactory.string(buffer.toString());
  }

  @override
  JSValue visitTaggedTemplateExpression(TaggedTemplateExpression node) {
    // Tagged template: tag`template`
    // The tag function is called with the template strings array and the interpolated values
    final tag = node.tag.accept(this);

    // Build the strings array (the quasis)
    final stringElements = node.quasi.quasis
        .map((s) => JSValueFactory.string(s))
        .toList();
    final strings = JSArray(stringElements);

    // Evaluate all interpolated expressions
    final values = node.quasi.expressions
        .map((expr) => expr.accept(this))
        .toList();

    // Call the tag function with (strings, ...values)
    final callArguments = [strings, ...values];

    if (!tag.isFunction) {
      throw JSTypeError('${node.tag} is not a function');
    }

    return _callFunctionWithErrorConversion(
      tag,
      callArguments,
      JSValueFactory.undefined(),
    );
  }

  @override
  JSValue visitIdentifierExpression(IdentifierExpression node) {
    try {
      // First try to get from lexical environment
      final result = _currentEnvironment().get(node.name);
      return result;
    } catch (e) {
      // If not found in lexical environment, try variable environment
      if (e is JSReferenceError &&
          _currentContext().variableEnvironment != _currentEnvironment()) {
        try {
          final result = _currentContext().variableEnvironment.get(node.name);
          return result;
        } catch (e2) {
          // Not found in variable environment either
          if (e2 is JSReferenceError) {
            // Try to find as a property on the global object
            if (_globalThisBinding is JSObject) {
              final globalObj = _globalThisBinding as JSObject;
              if (globalObj.hasProperty(node.name)) {
                return globalObj.getProperty(node.name);
              }
            }
            rethrow;
          }
        }
      }

      // Try to find as a property on the global object if not in any environment
      if (e is JSReferenceError) {
        if (_globalThisBinding is JSObject) {
          final globalObj = _globalThisBinding as JSObject;
          if (globalObj.hasProperty(node.name)) {
            return globalObj.getProperty(node.name);
          }
        }
        rethrow;
      }

      throw JSReferenceError('${node.name} is not defined');
    }
  }

  @override
  JSValue visitPrivateIdentifierExpression(PrivateIdentifierExpression node) {
    // Les identifiants prives ne peuvent etre utilises que dans le contexte d'une classe
    // qui les declare
    throw JSError(
      'Private field \'${node.name}\' must be accessed within its declaring class',
    );
  }

  @override
  JSValue visitThisExpression(ThisExpression node) {
    // Check if we're in an arrow function created in a null-extending class constructor
    if (_arrowFunctionClassContextStack.isNotEmpty) {
      final capturedClassContext = _arrowFunctionClassContextStack.last;
      if (capturedClassContext != null && capturedClassContext.extendsNull) {
        throw JSReferenceError(
          'this is not initialized in constructor of null-extending class',
        );
      }
    }

    // Check if we're in a derived class constructor that hasn't called super() yet
    // Only check this when we're actually IN a constructor
    final isInConstructor =
        _constructorStack.isNotEmpty && _constructorStack.last;
    final classContext = _currentClassContext;

    if (isInConstructor &&
        classContext != null &&
        classContext.isDerivedClass &&
        !classContext
            .extendsNull && // null-extending classes don't require super()
        !_isSuperCalled()) {
      throw JSReferenceError(
        'Must call super constructor in derived class before accessing \'this\' or returning from derived constructor',
      );
    }

    // For null-extending classes, this is uninitialized and always throws
    if (isInConstructor && classContext != null && classContext.extendsNull) {
      throw JSReferenceError(
        'this is not initialized in constructor of null-extending class',
      );
    }

    // If we're in a constructor, check if we have a constructor this stack
    // (which may have been updated if super() returned an object)
    if (isInConstructor && _constructorThisStack.isNotEmpty) {
      return _constructorThisStack.last;
    }

    // D'abord essayer de resoudre 'this' depuis l'environnement (pour les fonctions async)
    final currentEnv = _currentEnvironment();
    try {
      final thisValue = currentEnv.get('this');
      if (!thisValue.isUndefined) {
        return thisValue;
      }
    } catch (e) {
      // 'this' n'est pas defini dans l'environnement, utiliser le contexte
    }

    // Retourner la valeur 'this' du contexte d'execution actuel
    return _currentContext().thisBinding;
  }

  @override
  JSValue visitBinaryExpression(BinaryExpression node) {
    // Special handling for && and || operators - they need short-circuit evaluation
    // Don't evaluate right side unless necessary
    if (node.operator == '&&' || node.operator == '||') {
      final left = node.left.accept(this);

      if (node.operator == '&&') {
        // For &&: if left is falsy, return left without evaluating right
        if (!left.toBoolean()) {
          return left;
        }
        // Left is truthy, evaluate and return right
        return node.right.accept(this);
      } else {
        // For ||: if left is truthy, return left without evaluating right
        if (left.toBoolean()) {
          return left;
        }
        // Left is falsy, evaluate and return right
        return node.right.accept(this);
      }
    }

    // For all other operators, evaluate both sides
    final left = node.left.accept(this);
    final right = node.right.accept(this);

    // Pour l'operateur +, verifier d'abord si l'un des operandes est une string
    // (la concatenation de strings a priorite sur les operations BigInt)
    if (node.operator == '+' && (left.isString || right.isString)) {
      return _addOperation(left, right);
    }

    // Gestion speciale pour les BigInt (sauf pour +  avec string)
    if (left.isBigInt || right.isBigInt) {
      return _performBigIntOperation(node.operator, left, right);
    }

    return switch (node.operator) {
      '+' => _addOperation(left, right),
      '-' => JSValueFactory.number(left.toNumber() - right.toNumber()),
      '*' => JSValueFactory.number(left.toNumber() * right.toNumber()),
      '/' => JSValueFactory.number(left.toNumber() / right.toNumber()),
      '%' => JSValueFactory.number(left.toNumber() % right.toNumber()),
      '**' => _performExponentiation(left, right),
      '==' => JSValueFactory.boolean(left.equals(right)),
      '!=' => JSValueFactory.boolean(!left.equals(right)),
      '===' => JSValueFactory.boolean(left.strictEquals(right)),
      '!==' => JSValueFactory.boolean(!left.strictEquals(right)),
      '<' => _performLessThan(left, right),
      '<=' => _performLessEqual(left, right),
      '>' => _performGreaterThan(left, right),
      '>=' => _performGreaterEqual(left, right),
      '&&' => throw JSError('Should not reach here - && handled above'),
      '||' => throw JSError('Should not reach here - || handled above'),
      '<<' => _performLeftShift(left, right),
      '>>' => _performRightShift(left, right),
      '>>>' => _performUnsignedRightShift(left, right),
      '&' => _performBitwiseAnd(left, right),
      '|' => _performBitwiseOr(left, right),
      '^' => _performBitwiseXor(left, right),
      'instanceof' => _performInstanceof(left, right),
      'in' => _performIn(left, right),
      _ => throw JSError('Unknown binary operator: ${node.operator}'),
    };
  }

  /// Effectue une comparaison moins-que selon les regles JavaScript
  JSValue _performLessThan(JSValue left, JSValue right) {
    if (left.type == JSValueType.string && right.type == JSValueType.string) {
      return JSValueFactory.boolean(
        left.toString().compareTo(right.toString()) < 0,
      );
    }
    final leftNum = left.toNumber();
    final rightNum = right.toNumber();
    if (leftNum.isNaN || rightNum.isNaN) return JSValueFactory.boolean(false);
    return JSValueFactory.boolean(leftNum < rightNum);
  }

  /// Effectue une comparaison moins-ou-egal selon les regles JavaScript
  JSValue _performLessEqual(JSValue left, JSValue right) {
    if (left.type == JSValueType.string && right.type == JSValueType.string) {
      return JSValueFactory.boolean(
        left.toString().compareTo(right.toString()) <= 0,
      );
    }
    final leftNum = left.toNumber();
    final rightNum = right.toNumber();
    if (leftNum.isNaN || rightNum.isNaN) return JSValueFactory.boolean(false);
    return JSValueFactory.boolean(leftNum <= rightNum);
  }

  /// Effectue une comparaison plus-que selon les regles JavaScript
  JSValue _performGreaterThan(JSValue left, JSValue right) {
    if (left.type == JSValueType.string && right.type == JSValueType.string) {
      return JSValueFactory.boolean(
        left.toString().compareTo(right.toString()) > 0,
      );
    }
    final leftNum = left.toNumber();
    final rightNum = right.toNumber();
    if (leftNum.isNaN || rightNum.isNaN) return JSValueFactory.boolean(false);
    return JSValueFactory.boolean(leftNum > rightNum);
  }

  /// Effectue une comparaison plus-ou-egal selon les regles JavaScript
  JSValue _performGreaterEqual(JSValue left, JSValue right) {
    if (left.type == JSValueType.string && right.type == JSValueType.string) {
      return JSValueFactory.boolean(
        left.toString().compareTo(right.toString()) >= 0,
      );
    }
    final leftNum = left.toNumber();
    final rightNum = right.toNumber();
    if (leftNum.isNaN || rightNum.isNaN) return JSValueFactory.boolean(false);
    return JSValueFactory.boolean(leftNum >= rightNum);
  }

  /// Convertit un nombre en entier 32-bit signe (ToInt32 spec JavaScript)
  int _toInt32(double value) {
    if (value.isNaN || value.isInfinite || value == 0) return 0;
    final int32 = value.truncate() & 0xFFFFFFFF;
    // Convertir en signe si necessaire
    return int32 >= 0x80000000 ? int32 - 0x100000000 : int32;
  }

  /// Convertit un nombre en entier 32-bit non signe (ToUint32 spec JavaScript)
  int _toUint32(double value) {
    if (value.isNaN || value.isInfinite || value == 0) return 0;
    return value.truncate() & 0xFFFFFFFF;
  }

  /// Effectue un left shift bitwise (<<)
  JSValue _performLeftShift(JSValue left, JSValue right) {
    final leftInt = _toInt32(left.toNumber());
    final shiftAmount = _toUint32(right.toNumber()) & 0x1F; // Modulo 32
    final result = (leftInt << shiftAmount) & 0xFFFFFFFF;
    // Convertir en signe
    final signedResult = result >= 0x80000000 ? result - 0x100000000 : result;
    return JSValueFactory.number(signedResult.toDouble());
  }

  /// Effectue un right shift bitwise signe (>>)
  JSValue _performRightShift(JSValue left, JSValue right) {
    final leftInt = _toInt32(left.toNumber());
    final shiftAmount = _toUint32(right.toNumber()) & 0x1F; // Modulo 32
    final result = leftInt >> shiftAmount;
    return JSValueFactory.number(result.toDouble());
  }

  /// Effectue un right shift bitwise non signe (>>>)
  JSValue _performUnsignedRightShift(JSValue left, JSValue right) {
    final leftInt = _toUint32(left.toNumber());
    final shiftAmount = _toUint32(right.toNumber()) & 0x1F; // Modulo 32
    final result = leftInt >>> shiftAmount;
    return JSValueFactory.number(result.toDouble());
  }

  /// Effectue un AND bitwise (&)
  JSValue _performBitwiseAnd(JSValue left, JSValue right) {
    final leftInt = _toInt32(left.toNumber());
    final rightInt = _toInt32(right.toNumber());
    final result = leftInt & rightInt;
    return JSValueFactory.number(result.toDouble());
  }

  /// Effectue un OR bitwise (|)
  JSValue _performBitwiseOr(JSValue left, JSValue right) {
    final leftInt = _toInt32(left.toNumber());
    final rightInt = _toInt32(right.toNumber());
    final result = leftInt | rightInt;
    return JSValueFactory.number(result.toDouble());
  }

  /// Effectue un XOR bitwise (^)
  JSValue _performBitwiseXor(JSValue left, JSValue right) {
    final leftInt = _toInt32(left.toNumber());
    final rightInt = _toInt32(right.toNumber());
    final result = leftInt ^ rightInt;
    return JSValueFactory.number(result.toDouble());
  }

  /// Effectue l'exponentiation (**)
  /// Suit les regles JavaScript: Math.pow(base, exponent)
  JSValue _performExponentiation(JSValue left, JSValue right) {
    // Gerer BigInt separement
    if (left.isBigInt || right.isBigInt) {
      BigInt leftBigInt;
      BigInt rightBigInt;

      if (left.isBigInt) {
        leftBigInt = (left as JSBigInt).value;
      } else {
        leftBigInt = BigInt.from(left.toNumber().truncate());
      }

      if (right.isBigInt) {
        rightBigInt = (right as JSBigInt).value;
      } else {
        rightBigInt = BigInt.from(right.toNumber().truncate());
      }

      return JSValueFactory.bigint(leftBigInt.pow(rightBigInt.toInt()));
    }

    // Cas normal avec des nombres
    final base = left.toNumber();
    final exponent = right.toNumber();

    // Cas speciaux selon la spec ECMAScript
    if (exponent.isNaN) return JSValueFactory.number(double.nan);
    if (exponent == 0) return JSValueFactory.number(1.0);
    if (base.isNaN && exponent != 0) return JSValueFactory.number(double.nan);

    // Utiliser dart:math pow pour le calcul
    final result = math.pow(base, exponent).toDouble();
    return JSValueFactory.number(result);
  }

  /// Effectue les operations BigInt
  JSValue _performBigIntOperation(
    String operator,
    JSValue left,
    JSValue right,
  ) {
    // Pour === et !==, verifier d'abord si les deux sont BigInt
    if (operator == '===' || operator == '!==') {
      // Si l'un des deux n'est pas BigInt, retourner false pour === et true pour !==
      if (!left.isBigInt || !right.isBigInt) {
        return JSValueFactory.boolean(operator == '!==');
      }
      // Les deux sont BigInt, comparer les valeurs
      final leftBigInt = (left as JSBigInt).value;
      final rightBigInt = (right as JSBigInt).value;
      return JSValueFactory.boolean(
        operator == '==='
            ? leftBigInt == rightBigInt
            : leftBigInt != rightBigInt,
      );
    }

    // Pour les operateurs de comparaison ==, !=, utiliser la methode equals
    if (operator == '==' || operator == '!=') {
      final result = left.equals(right);
      return JSValueFactory.boolean(operator == '==' ? result : !result);
    }

    // Convertir les operandes en BigInt
    BigInt leftBigInt;
    BigInt rightBigInt;

    if (left.isBigInt) {
      leftBigInt = (left as JSBigInt).value;
    } else {
      // Conversion depuis Number - verifier NaN/Infinity
      final num = left.toNumber();
      if (num.isNaN || num.isInfinite) {
        throw JSTypeError(
          'Cannot convert ${num.isNaN ? 'NaN' : 'Infinity'} to BigInt',
        );
      }
      leftBigInt = BigInt.from(num.truncate());
    }

    if (right.isBigInt) {
      rightBigInt = (right as JSBigInt).value;
    } else {
      // Conversion depuis Number - verifier NaN/Infinity
      final num = right.toNumber();
      if (num.isNaN || num.isInfinite) {
        throw JSTypeError(
          'Cannot convert ${num.isNaN ? 'NaN' : 'Infinity'} to BigInt',
        );
      }
      rightBigInt = BigInt.from(num.truncate());
    }

    return switch (operator) {
      '+' => JSValueFactory.bigint(leftBigInt + rightBigInt),
      '-' => JSValueFactory.bigint(leftBigInt - rightBigInt),
      '*' => JSValueFactory.bigint(leftBigInt * rightBigInt),
      '/' => JSValueFactory.bigint(
        leftBigInt ~/ rightBigInt,
      ), // Division entiere
      '%' => JSValueFactory.bigint(
        leftBigInt - (leftBigInt ~/ rightBigInt) * rightBigInt,
      ), // JavaScript modulo: result has sign of dividend
      '**' => JSValueFactory.bigint(
        leftBigInt.pow(rightBigInt.toInt()),
      ), // Exponentiation pour BigInt
      '<<' => JSValueFactory.bigint(leftBigInt << rightBigInt.toInt()),
      '>>' => JSValueFactory.bigint(leftBigInt >> rightBigInt.toInt()),
      '&' => JSValueFactory.bigint(leftBigInt & rightBigInt),
      '|' => JSValueFactory.bigint(leftBigInt | rightBigInt),
      '^' => JSValueFactory.bigint(leftBigInt ^ rightBigInt),
      '==' => JSValueFactory.boolean(leftBigInt == rightBigInt),
      '!=' => JSValueFactory.boolean(leftBigInt != rightBigInt),
      '<' => JSValueFactory.boolean(leftBigInt < rightBigInt),
      '<=' => JSValueFactory.boolean(leftBigInt <= rightBigInt),
      '>' => JSValueFactory.boolean(leftBigInt > rightBigInt),
      '>=' => JSValueFactory.boolean(leftBigInt >= rightBigInt),
      _ => throw JSError('BigInt does not support operator: $operator'),
    };
  }

  /// Implemente l'operateur instanceof
  JSValue _performInstanceof(JSValue obj, JSValue constructor) {
    // Le cote droit doit etre une fonction constructeur
    if (constructor is! JSFunction &&
        constructor is! JSObject &&
        constructor is! JSNativeFunction &&
        constructor is! JSClass) {
      throw JSTypeError('Right-hand side of instanceof is not callable');
    }

    // Cas speciaux pour les constructeurs natifs
    if (constructor is JSNativeFunction) {
      if (constructor.functionName == 'Array' && obj is JSArray) {
        return JSValueFactory.boolean(true);
      }
      if (constructor.functionName == 'Object' && obj is JSObject) {
        return JSValueFactory.boolean(true);
      }
      if (constructor.functionName == 'Function' &&
          (obj is JSFunction || obj is JSNativeFunction)) {
        return JSValueFactory.boolean(true);
      }
      // Pour d'autres constructeurs natifs, verifier le prototype
    }

    // Pour JSClass, verifier avec la chaine d'heritage des classes
    if (constructor is JSClass) {
      if (obj is! JSObject) {
        return JSValueFactory.boolean(false);
      }

      // Verifier si l'objet a ete cree par cette classe ou une sous-classe
      final objClass = obj.getProperty('constructor');
      if (objClass == constructor) {
        return JSValueFactory.boolean(true);
      }

      // Verifier la chaine d'heritage des classes
      JSClass? currentClass = objClass is JSClass ? objClass : null;
      while (currentClass != null) {
        if (currentClass == constructor) {
          return JSValueFactory.boolean(true);
        }
        currentClass = currentClass.superClass;
      }

      // Fallback to prototype chain check
    }

    // Si l'objet n'est pas un objet, retourner false
    if (obj is! JSObject) {
      return JSValueFactory.boolean(false);
    }

    // Obtenir le prototype du constructeur
    JSObject? constructorPrototype;
    if (constructor is JSFunction) {
      final prototypeValue = constructor.getProperty('prototype');
      if (prototypeValue is JSObject) {
        constructorPrototype = prototypeValue;
      }
    } else if (constructor is JSClass) {
      final prototypeValue = constructor.getProperty('prototype');
      if (prototypeValue is JSObject) {
        constructorPrototype = prototypeValue;
      }
    } else if (constructor is JSObject) {
      final prototypeValue = constructor.getProperty('prototype');
      if (prototypeValue is JSObject) {
        constructorPrototype = prototypeValue;
      }
    } else if (constructor is JSNativeFunction) {
      final prototypeValue = constructor.getProperty('prototype');
      if (prototypeValue is JSObject) {
        constructorPrototype = prototypeValue;
      }
    }

    if (constructorPrototype == null) {
      return JSValueFactory.boolean(false);
    }

    // Parcourir la chaine de prototypes de l'objet
    JSObject? current = obj.getPrototype();
    while (current != null) {
      if (current == constructorPrototype) {
        return JSValueFactory.boolean(true);
      }
      current = current.getPrototype();
    }

    return JSValueFactory.boolean(false);
  }

  /// Implemente l'operateur 'in' JavaScript (prop in obj)
  JSValue _performIn(JSValue property, JSValue object) {
    // Le cote droit doit etre un objet ou une fonction (fonctions sont des objets en JS)
    if (object is! JSObject && object is! JSFunction) {
      throw JSTypeError('Right-hand side of "in" operator must be an object');
    }

    // Convertir la propriete en string
    final propName = property.toString();

    // Verifier si la propriete existe (incluant la chaine de prototypes)
    if (object is JSFunction) {
      return JSValueFactory.boolean(object.hasProperty(propName));
    } else {
      return JSValueFactory.boolean((object as JSObject).hasProperty(propName));
    }
  }

  /// Implemente l'operation d'addition JavaScript (+ operator)
  JSValue _addOperation(JSValue left, JSValue right) {
    // Si l'un des operandes est une string, convertir en string
    // (la concatenation de strings a priorite sur tout)
    if (left.isString || right.isString) {
      final leftStr = left is JSArray ? left.toPrimitive() : left.toString();
      final rightStr = right is JSArray
          ? right.toPrimitive()
          : right.toString();
      return JSValueFactory.string(leftStr + rightStr);
    }

    // Gestion speciale pour les BigInt (si on arrive ici, ni left ni right n'est string)
    if (left.isBigInt || right.isBigInt) {
      return _performBigIntOperation('+', left, right);
    }

    // Sinon, conversion numerique
    return JSValueFactory.number(left.toNumber() + right.toNumber());
  }

  @override
  JSValue visitUnaryExpression(UnaryExpression node) {
    // Special handling for 'delete' - don't evaluate operand first
    if (node.operator == 'delete') {
      return _performDelete(node.operand);
    }

    // Special handling for 'typeof' with identifier - don't throw ReferenceError
    if (node.operator == 'typeof' && node.operand is IdentifierExpression) {
      try {
        final operand = node.operand.accept(this);
        return JSValueFactory.string(_getTypeof(operand));
      } catch (e) {
        // If identifier doesn't exist, return 'undefined' instead of throwing
        if (e is JSReferenceError ||
            e is EnvironmentError ||
            e.toString().contains('is not defined')) {
          return JSValueFactory.string('undefined');
        }
        rethrow;
      }
    }

    final operand = node.operand.accept(this);

    return switch (node.operator) {
      '-' =>
        operand.isBigInt
            ? JSValueFactory.bigint(-(operand as JSBigInt).value)
            : JSValueFactory.number(-operand.toNumber()),
      '+' =>
        operand.isBigInt ? operand : JSValueFactory.number(operand.toNumber()),
      '!' => JSValueFactory.boolean(!operand.toBoolean()),
      '~' => _performBitwiseNot(operand),
      'typeof' => JSValueFactory.string(_getTypeof(operand)),
      '++' => _incrementOperation(node.operand, node.prefix, 1),
      '--' => _incrementOperation(node.operand, node.prefix, -1),
      'void' =>
        JSValueFactory.undefined(), // ES6: void operator always returns undefined
      _ => throw JSError('Unknown unary operator: ${node.operator}'),
    };
  }

  /// Implemente l'operateur delete (ES6)
  /// delete obj.prop retourne true si la propriete a ete supprimee
  /// delete obj[key] retourne true si la propriete a ete supprimee
  /// delete nonExistent retourne true
  /// delete d'une variable retourne false en strict mode (throws), true en non-strict
  JSValue _performDelete(Expression target) {
    if (target is MemberExpression) {
      // delete obj.prop ou delete obj[key]
      final objectValue = target.object.accept(this);

      // Handle JSObject, JSFunction, and JSNativeFunction for delete
      if (objectValue is! JSObject &&
          objectValue is! JSFunction &&
          objectValue is! JSNativeFunction) {
        // Trying to delete property of non-object returns true
        return JSValueFactory.boolean(true);
      }

      String propertyKey;
      if (target.computed) {
        // delete obj[key]
        final keyValue = target.property.accept(this);
        propertyKey = JSConversion.jsToString(keyValue);
      } else {
        // delete obj.prop
        if (target.property is IdentifierExpression) {
          propertyKey = (target.property as IdentifierExpression).name;
        } else if (target.property is PrivateIdentifierExpression) {
          propertyKey = (target.property as PrivateIdentifierExpression).name;
        } else {
          return JSValueFactory.boolean(false);
        }
      }

      // Delete the property
      bool success;
      if (objectValue is JSNativeFunction) {
        success = objectValue.deleteProperty(propertyKey);
      } else if (objectValue is JSFunction) {
        success = objectValue.deleteProperty(propertyKey);
      } else if (objectValue is JSObject) {
        success = objectValue.deleteProperty(propertyKey);
      } else {
        success = true;
      }

      // In strict mode, throw TypeError if delete returns false (non-configurable property)
      if (!success && _currentContext().strictMode) {
        throw JSTypeError(
          "Cannot delete property '$propertyKey' of #<${objectValue.runtimeType}>",
        );
      }

      return JSValueFactory.boolean(success);
    } else if (target is IdentifierExpression) {
      // delete variableName
      // En strict mode, lever une SyntaxError
      if (_currentContext().strictMode) {
        throw JSSyntaxError(
          'Delete of an unqualified identifier in strict mode',
        );
      }

      // En mode non-strict, try to delete from globalThis if it's a global property
      final env = _currentEnvironment();
      try {
        env.get(target.name);
        // Variable exists - check if it's a global property that can be deleted
        final globalThis = env.get('this');
        if (globalThis is JSGlobalThis) {
          // Try to delete from globalThis
          return JSValueFactory.boolean(globalThis.deleteProperty(target.name));
        }
        // Variable exists but not on globalThis, can't delete it
        return JSValueFactory.boolean(false);
      } catch (e) {
        // Variable doesn't exist, return true
        return JSValueFactory.boolean(true);
      }
    } else {
      // delete literal or delete expression result
      // Always returns true
      return JSValueFactory.boolean(true);
    }
  }

  /// Effectue un NOT bitwise (~)
  JSValue _performBitwiseNot(JSValue operand) {
    if (operand.isBigInt) {
      // Pour BigInt, ~ inverse tous les bits
      final bigIntValue = (operand as JSBigInt).value;
      return JSValueFactory.bigint(~bigIntValue);
    }
    // Pour Number, convertir en int32, inverser, reconvertir
    final int32 = _toInt32(operand.toNumber());
    final result = ~int32;
    return JSValueFactory.number(result.toDouble());
  }

  /// Implemente typeof
  String _getTypeof(JSValue value) {
    // Check for callable objects (functions and callable proxies)
    if (value is JSFunction || value is JSNativeFunction) {
      return 'function';
    }

    // For Proxy, check if target is callable
    if (value is JSProxy) {
      final target = value.target;
      if (target is JSFunction || target is JSNativeFunction) {
        return 'function';
      }
    }

    return switch (value.type) {
      JSValueType.undefined => 'undefined',
      JSValueType.nullType => 'object', // Quirk de JavaScript
      JSValueType.boolean => 'boolean',
      JSValueType.number => 'number',
      JSValueType.string => 'string',
      JSValueType.function => 'function',
      JSValueType.object => 'object',
      JSValueType.symbol => 'symbol',
      JSValueType.bigint => 'bigint',
    };
  }

  /// Implemente ++ et --
  JSValue _incrementOperation(Expression target, bool prefix, int delta) {
    if (target is IdentifierExpression) {
      // Increment/decrement d'une variable: x++ ou ++x
      final env = _currentEnvironment();
      final currentValue = env.get(target.name);

      JSValue newValue;
      if (currentValue.isBigInt) {
        // Pour BigInt, garder le type
        final bigintValue = (currentValue as JSBigInt).value;
        newValue = JSValueFactory.bigint(bigintValue + BigInt.from(delta));
      } else {
        // Pour les autres types, convertir en nombre
        final numValue = currentValue.toNumber();
        newValue = JSValueFactory.number(numValue + delta);
      }

      env.set(target.name, newValue);

      // Retourner la valeur selon prefix/postfix
      return prefix ? newValue : currentValue;
    } else if (target is MemberExpression) {
      // Increment/decrement d'une propriete d'objet: obj.prop++ ou ++obj.prop
      final objectValue = target.object.accept(this);

      if (target.computed) {
        // obj[key]++ ou ++obj[key]
        final keyValue = target.property.accept(this);

        if (objectValue is JSArray && keyValue.isNumber) {
          final index = keyValue.toNumber().floor();
          final currentValue = objectValue.get(index);
          final numValue = currentValue.toNumber();
          final newValue = JSValueFactory.number(numValue + delta);

          objectValue.set(index, newValue);
          return prefix ? newValue : currentValue;
        }

        if (objectValue is JSObject) {
          final propertyKey = JSConversion.jsToString(keyValue);
          final currentValue = objectValue.getProperty(propertyKey);
          final numValue = currentValue.toNumber();
          final newValue = JSValueFactory.number(numValue + delta);

          objectValue.setProperty(propertyKey, newValue);
          return prefix ? newValue : currentValue;
        }

        throw JSSyntaxError('Invalid left-hand side in assignment');
      } else {
        // obj.prop++ ou ++obj.prop ou obj.#privateProp++ ou ++obj.#privateProp
        String propName;
        bool isPrivate = false;

        if (target.property is IdentifierExpression) {
          propName = (target.property as IdentifierExpression).name;
        } else if (target.property is PrivateIdentifierExpression) {
          propName = (target.property as PrivateIdentifierExpression).name;
          isPrivate = true;
        } else {
          throw JSError('Invalid property access');
        }

        // Valider l'acces aux proprietes privees
        if (isPrivate) {
          JSClass? propertyOwnerClass;

          if (objectValue is JSClass) {
            propertyOwnerClass = objectValue;
          } else if (objectValue is JSObject) {
            JSObject? current = objectValue;
            while (current != null) {
              final constructor = current.getProperty('constructor');
              if (constructor is JSClass) {
                propertyOwnerClass = constructor;
                break;
              }
              current = current.getPrototype();
            }
          }

          final currentClass = _currentClassContext;
          if (propertyOwnerClass == null ||
              currentClass == null ||
              !_isInClassContext(propertyOwnerClass)) {
            throw JSSyntaxError(
              "Private field '#$propName' must be accessed from an enclosing class",
            );
          }

          // Transformer le nom pour l'acces
          propName = '_private_$propName';
        }

        if (objectValue is JSObject) {
          final currentValue = objectValue.getProperty(propName);
          final numValue = currentValue.toNumber();
          final newValue = JSValueFactory.number(numValue + delta);

          objectValue.setProperty(propName, newValue);
          return prefix ? newValue : currentValue;
        }

        if (objectValue is JSClass) {
          final currentValue = objectValue.getProperty(propName);
          final numValue = currentValue.toNumber();
          final newValue = JSValueFactory.number(numValue + delta);

          objectValue.setProperty(propName, newValue);
          return prefix ? newValue : currentValue;
        }

        throw JSSyntaxError('Invalid left-hand side in assignment');
      }
    } else {
      throw JSSyntaxError('Invalid left-hand side in assignment');
    }
  }

  @override
  JSValue visitAssignmentExpression(AssignmentExpression node) {
    // Pour les operateurs d'assignation logique (&&=, ||=, ??=), on doit implementer
    // le short-circuit: ne pas evaluer le cote droit si pas necessaire
    if (node.operator == '&&=' ||
        node.operator == '||=' ||
        node.operator == '??=') {
      return _handleLogicalAssignment(node);
    }

    // ES6: Set target binding name context for anonymous function name inference
    // This allows: x = function() {} => x.name should be 'x'
    final previousTarget = _targetBindingNameForFunction;
    if (node.left is IdentifierExpression && node.operator == '=') {
      final target = node.left as IdentifierExpression;
      _targetBindingNameForFunction = target.name;
    }

    final rightValue = node.right.accept(this);
    _targetBindingNameForFunction = previousTarget;

    if (node.left is IdentifierExpression) {
      // Assignment a une variable: x = value
      final target = node.left as IdentifierExpression;
      final env = _currentEnvironment();

      JSValue finalValue;
      switch (node.operator) {
        case '=':
          finalValue = rightValue;
          // For JSFunction (not JSNativeFunction which includes generators),
          // still call setFunctionName for late binding in case needed
          if (finalValue is JSFunction &&
              finalValue is! JSNativeFunction &&
              (finalValue.functionName == 'anonymous' ||
                  finalValue.functionName.isEmpty)) {
            finalValue.setFunctionName(target.name);
          }
          // Also set name for anonymous class expressions (but only if 'name' property doesn't already exist)
          if (finalValue is JSClass && finalValue.name == 'anonymous') {
            // Check if the class has a static 'name' member defined
            // If it does, don't override it
            final nameDescriptor = finalValue.getOwnPropertyDescriptor('name');
            if (nameDescriptor == null ||
                nameDescriptor.value == JSValueFactory.string('anonymous')) {
              finalValue.name = target.name;
            }
          }
          break;
        case '+=':
          final leftValue = env.get(target.name);
          finalValue = _addOperation(leftValue, rightValue);
          break;
        case '-=':
          final leftValue = env.get(target.name);
          if (leftValue.isBigInt || rightValue.isBigInt) {
            finalValue = _performBigIntOperation('-', leftValue, rightValue);
          } else {
            finalValue = JSValueFactory.number(
              leftValue.toNumber() - rightValue.toNumber(),
            );
          }
          break;
        case '*=':
          final leftValue = env.get(target.name);
          if (leftValue.isBigInt || rightValue.isBigInt) {
            finalValue = _performBigIntOperation('*', leftValue, rightValue);
          } else {
            finalValue = JSValueFactory.number(
              leftValue.toNumber() * rightValue.toNumber(),
            );
          }
          break;
        case '/=':
          final leftValue = env.get(target.name);
          if (leftValue.isBigInt || rightValue.isBigInt) {
            finalValue = _performBigIntOperation('/', leftValue, rightValue);
          } else {
            finalValue = JSValueFactory.number(
              leftValue.toNumber() / rightValue.toNumber(),
            );
          }
          break;
        case '%=':
          final leftValue = env.get(target.name);
          if (leftValue.isBigInt || rightValue.isBigInt) {
            finalValue = _performBigIntOperation('%', leftValue, rightValue);
          } else {
            finalValue = JSValueFactory.number(
              leftValue.toNumber() % rightValue.toNumber(),
            );
          }
          break;
        case '**=':
          final leftValue = env.get(target.name);
          finalValue = _performExponentiation(leftValue, rightValue);
          break;
        case '&=':
          final leftValue = env.get(target.name);
          finalValue = _performBitwiseAnd(leftValue, rightValue);
          break;
        case '|=':
          final leftValue = env.get(target.name);
          finalValue = _performBitwiseOr(leftValue, rightValue);
          break;
        case '^=':
          final leftValue = env.get(target.name);
          finalValue = _performBitwiseXor(leftValue, rightValue);
          break;
        case '<<=':
          final leftValue = env.get(target.name);
          finalValue = _performLeftShift(leftValue, rightValue);
          break;
        case '>>=':
          final leftValue = env.get(target.name);
          finalValue = _performRightShift(leftValue, rightValue);
          break;
        case '>>>=':
          final leftValue = env.get(target.name);
          finalValue = _performUnsignedRightShift(leftValue, rightValue);
          break;
        default:
          throw JSError('Unsupported assignment operator: ${node.operator}');
      }

      // Passer le strictMode a la methode set
      env.set(
        target.name,
        finalValue,
        strictMode: _currentContext().strictMode,
      );
      return finalValue;
    } else if (node.left is MemberExpression) {
      // Assignment a une propriete/index: obj.prop = value ou obj[key] = value
      final memberExpr = node.left as MemberExpression;
      final objectValue = memberExpr.object.accept(this);

      if (memberExpr.computed) {
        // obj[key] = value
        final keyValue = memberExpr.property.accept(this);

        if (objectValue is JSArray && keyValue.isNumber) {
          final numIndex = keyValue.toNumber();

          // NaN, Infinity, and -Infinity should be treated as string properties
          // per ES6 spec: ToPropertyKey converts these to their string representations
          if (numIndex.isNaN || numIndex.isInfinite) {
            final propertyKey = numIndex.isNaN
                ? 'NaN'
                : numIndex.isNegative
                ? '-Infinity'
                : 'Infinity';

            if (node.operator == '=') {
              objectValue.setProperty(propertyKey, rightValue);
              return rightValue;
            } else {
              // Compound assignment
              final currentValue = objectValue.getProperty(propertyKey);
              final newValue = _performCompoundAssignment(
                currentValue,
                rightValue,
                node.operator,
              );
              objectValue.setProperty(propertyKey, newValue);
              return newValue;
            }
          }

          final index = numIndex.floor();

          // Check if the number is actually an integer (not fractional)
          // Non-integer numbers like 1.1 should be treated as string properties
          if (numIndex != index.toDouble()) {
            final propertyKey = numIndex.toString();

            if (node.operator == '=') {
              objectValue.setProperty(propertyKey, rightValue);
              return rightValue;
            } else {
              // Compound assignment
              final currentValue = objectValue.getProperty(propertyKey);
              final newValue = _performCompoundAssignment(
                currentValue,
                rightValue,
                node.operator,
              );
              objectValue.setProperty(propertyKey, newValue);
              return newValue;
            }
          }

          if (node.operator == '=') {
            // Use setProperty instead of set to respect property descriptors
            // This ensures frozen/sealed arrays work correctly
            objectValue.setProperty(index.toString(), rightValue);
            return rightValue;
          } else {
            // Compound assignment pour array index
            final currentValue = objectValue.get(index);
            final newValue = _performCompoundAssignment(
              currentValue,
              rightValue,
              node.operator,
            );
            // Use setProperty instead of set to respect property descriptors
            objectValue.setProperty(index.toString(), newValue);
            return newValue;
          }
        }

        if (objectValue is JSObject) {
          final propertyKey = JSConversion.jsToString(keyValue);

          if (node.operator == '=') {
            try {
              // ES6: Use setPropertyWithSymbol if this is a symbol key
              if (keyValue is JSSymbol) {
                objectValue.setPropertyWithSymbol(
                  propertyKey,
                  rightValue,
                  keyValue,
                );
              } else {
                objectValue.setProperty(propertyKey, rightValue);
              }
            } on JSError catch (jsError) {
              // Convertir les erreurs Dart JSError en JSException
              if (jsError is JSException) {
                rethrow;
              }
              JSObject? prototype;
              try {
                final constructorName = jsError.name;
                final constructor = _globalEnvironment.get(constructorName);
                if (constructor is JSFunction && constructor is JSObject) {
                  final proto = constructor.getProperty('prototype');
                  if (proto is JSObject) {
                    prototype = proto;
                  }
                }
              } catch (_) {}
              final errorValue = JSErrorObjectFactory.fromDartError(
                jsError,
                prototype,
              );
              throw JSException(errorValue);
            }
            return rightValue;
          } else {
            // Compound assignment pour object property
            final currentValue = objectValue.getProperty(propertyKey);
            final newValue = _performCompoundAssignment(
              currentValue,
              rightValue,
              node.operator,
            );
            try {
              // ES6: Use setPropertyWithSymbol if this is a symbol key
              if (keyValue is JSSymbol) {
                objectValue.setPropertyWithSymbol(
                  propertyKey,
                  newValue,
                  keyValue,
                );
              } else {
                objectValue.setProperty(propertyKey, newValue);
              }
            } on JSError catch (jsError) {
              // Convertir les erreurs Dart JSError en JSException
              if (jsError is JSException) {
                rethrow;
              }
              JSObject? prototype;
              try {
                final constructorName = jsError.name;
                final constructor = _globalEnvironment.get(constructorName);
                if (constructor is JSFunction && constructor is JSObject) {
                  final proto = constructor.getProperty('prototype');
                  if (proto is JSObject) {
                    prototype = proto;
                  }
                }
              } catch (_) {}
              final errorValue = JSErrorObjectFactory.fromDartError(
                jsError,
                prototype,
              );
              throw JSException(errorValue);
            }
            return newValue;
          }
        }

        // Support pour JSFunction computed assignment (func[key] = value)
        // Les fonctions sont des objets en JavaScript et peuvent avoir des proprietes
        if (objectValue is JSFunction) {
          final propertyKey = JSConversion.jsToString(keyValue);

          if (node.operator == '=') {
            objectValue.setProperty(propertyKey, rightValue);
            return rightValue;
          } else {
            // Compound assignment pour function property
            final currentValue = objectValue.getProperty(propertyKey);
            final newValue = _performCompoundAssignment(
              currentValue,
              rightValue,
              node.operator,
            );
            objectValue.setProperty(propertyKey, newValue);
            return newValue;
          }
        }

        // Support pour JSClass computed assignment (Class[key] = value)
        // Les classes peuvent avoir des proprietes statiques
        if (objectValue is JSClass) {
          final propertyKey = JSConversion.jsToString(keyValue);

          if (node.operator == '=') {
            objectValue.setProperty(propertyKey, rightValue);
            return rightValue;
          } else {
            // Compound assignment pour class property
            final currentValue = objectValue.getProperty(propertyKey);
            final newValue = _performCompoundAssignment(
              currentValue,
              rightValue,
              node.operator,
            );
            objectValue.setProperty(propertyKey, newValue);
            return newValue;
          }
        }

        throw JSError('Member assignment not supported for this type');
      } else {
        // obj.prop = value ou obj.#privateProp = value
        String propName;
        bool isPrivate = false;

        if (memberExpr.property is IdentifierExpression) {
          propName = (memberExpr.property as IdentifierExpression).name;
        } else if (memberExpr.property is PrivateIdentifierExpression) {
          propName = (memberExpr.property as PrivateIdentifierExpression).name;
          isPrivate = true;
        } else {
          throw JSError('Invalid property access');
        }

        // NOUVEAU: Validation d'acces aux proprietes privees lors de l'assignment
        if (isPrivate) {
          // Determiner la classe proprietaire de la propriete privee
          JSClass? propertyOwnerClass;

          // Si l'objet est une instance de classe, chercher la classe qui definit cette propriete
          if (objectValue is JSObject) {
            // Parcourir la chaine de prototypes pour trouver la classe
            JSObject? current = objectValue;
            while (current != null) {
              final constructor = current.getProperty('constructor');
              if (constructor is JSClass) {
                // Verifier si cette classe declare reellement cette propriete privee
                if (constructor.hasPrivateField(propName) ||
                    !constructor.hasAnyPrivateFields()) {
                  propertyOwnerClass = constructor;
                  break;
                }
              }

              // Remonter la chaine de prototypes
              current = current.getPrototype();
            }
          }

          // Verifier que l'acces se fait depuis le bon contexte de classe
          final currentClass = _currentClassContext;

          if (propertyOwnerClass == null) {
            // Permettre la creation de nouvelles proprietes privees depuis un contexte de classe
            if (currentClass == null) {
              throw JSSyntaxError(
                "Private field '#$propName' must be declared in an enclosing class",
              );
            }
            // Utiliser la classe courante comme proprietaire
            propertyOwnerClass = currentClass;
          } else if (currentClass == null ||
              !_isInClassContext(propertyOwnerClass)) {
            throw JSSyntaxError(
              "Private field '#$propName' must be declared in an enclosing class",
            );
          }

          // L'acces est autorise, utiliser le nom modifie
          propName = '_private_$propName';
        }

        if (objectValue is JSObject) {
          if (node.operator == '=') {
            objectValue.setProperty(propName, rightValue);
            return rightValue;
          } else {
            // Compound assignment pour object property
            final currentValue = objectValue.getProperty(propName);
            final newValue = _performCompoundAssignment(
              currentValue,
              rightValue,
              node.operator,
            );
            objectValue.setProperty(propName, newValue);
            return newValue;
          }
        } else if (objectValue is JSFunction) {
          if (node.operator == '=') {
            objectValue.setProperty(propName, rightValue);
            return rightValue;
          } else {
            // Compound assignment pour object property
            final currentValue = objectValue.getProperty(propName);
            final newValue = _performCompoundAssignment(
              currentValue,
              rightValue,
              node.operator,
            );
            objectValue.setProperty(propName, newValue);
            return newValue;
          }
        } else if (objectValue is JSClass) {
          if (node.operator == '=') {
            objectValue.setProperty(propName, rightValue);
            return rightValue;
          } else {
            // Compound assignment pour class property
            final currentValue = objectValue.getProperty(propName);
            final newValue = _performCompoundAssignment(
              currentValue,
              rightValue,
              node.operator,
            );
            objectValue.setProperty(propName, newValue);
            return newValue;
          }
        } else if (objectValue is JSNativeFunction) {
          if (node.operator == '=') {
            objectValue.setProperty(propName, rightValue);
            return rightValue;
          } else {
            // Compound assignment pour object property
            final currentValue = objectValue.getProperty(propName);
            final newValue = _performCompoundAssignment(
              currentValue,
              rightValue,
              node.operator,
            );
            objectValue.setProperty(propName, newValue);
            return newValue;
          }
        }

        throw JSTypeError('Property assignment not supported for this type');
      }
    } else {
      throw JSSyntaxError('Invalid left-hand side in assignment');
    }
  }

  @override
  JSValue visitConditionalExpression(ConditionalExpression node) {
    final testValue = node.test.accept(this);

    if (testValue.toBoolean()) {
      return node.consequent.accept(this);
    } else {
      return node.alternate.accept(this);
    }
  }

  @override
  JSValue visitSequenceExpression(SequenceExpression node) {
    // Evalue toutes les expressions dans l'ordre
    // et retourne la valeur de la derniere expression
    JSValue result = JSValueFactory.undefined();

    for (final expr in node.expressions) {
      result = expr.accept(this);
    }

    return result;
  }

  @override
  JSValue visitSpreadElement(SpreadElement node) {
    // Le spread element lui-meme n'est pas evalue directement
    // Il est traite par son contexte parent (array, object, call)
    throw JSError('SpreadElement should be handled by parent context');
  }

  @override
  JSValue visitArrowFunctionExpression(ArrowFunctionExpression node) {
    // Capturer l'environnement actuel pour la closure
    final currentEnv = _currentContext().lexicalEnvironment;
    final currentThis = _currentContext().thisBinding;
    final currentStrictMode = _currentContext().strictMode;
    final currentClassContext =
        _currentClassContext; // Capture current class context

    // Convertir les parametres simples en liste de strings et detecter rest parameter
    final paramNames = node.params
        .where((p) => p.name != null)
        .map((p) => p.name!.name)
        .toList();
    bool hasRestParam = false;
    int restParamIndex = -1;

    for (int i = 0; i < node.params.length; i++) {
      if (node.params[i].isRest) {
        hasRestParam = true;
        restParamIndex = i;
        break;
      }
    }

    // Createe arrow function avec l'environnement capture
    // ES2019: Generate source text from AST
    final sourceText = node.toString();
    // Capture new.target from lexical context (ES6)
    final currentNewTarget = _currentContext().newTarget;
    return JSArrowFunction(
      parameters: paramNames,
      body: node.body,
      closureEnvironment: currentEnv,
      capturedThis: currentThis,
      capturedNewTarget: currentNewTarget,
      capturedClassContext:
          currentClassContext, // Pass the captured class context
      hasRestParam: hasRestParam,
      restParamIndex: restParamIndex,
      parametersList:
          node.params, // ES2019: Store complete parameters for destructuring
      sourceText: sourceText,
      moduleUrl: _currentModuleUrl,
      strictMode: currentStrictMode, // Inherit strict mode from parent context
      inferredName: _targetBindingNameForFunction,
    );
  }

  @override
  JSValue visitAsyncArrowFunctionExpression(AsyncArrowFunctionExpression node) {
    // Validate async function constraints before creating the function
    _validateAsyncFunctionConstraints(node);

    // Capturer l'environnement actuel pour la closure
    final currentEnv = _currentContext().lexicalEnvironment;
    final currentThis = _currentContext().thisBinding;

    // Convertir les parametres simples en liste de strings et detecter rest parameter
    final paramNames = node.params
        .where((p) => p.name != null)
        .map((p) => p.name!.name)
        .toList();
    bool hasRestParam = false;
    int restParamIndex = -1;

    for (int i = 0; i < node.params.length; i++) {
      if (node.params[i].isRest) {
        hasRestParam = true;
        restParamIndex = i;
        break;
      }
    }

    // Capture new.target from lexical context (ES6)
    final currentNewTarget = _currentContext().newTarget;

    // Createe arrow function async avec l'environnement capture
    return JSAsyncArrowFunction(
      parameters: paramNames,
      body: node.body,
      closureEnvironment: currentEnv,
      capturedThis: currentThis,
      capturedNewTarget: currentNewTarget,
      hasRestParam: hasRestParam,
      restParamIndex: restParamIndex,
      parametersList:
          node.params, // ES2019: Store complete parameters for destructuring
      moduleUrl: _currentModuleUrl,
      inferredName: _targetBindingNameForFunction,
    );
  }

  @override
  JSValue visitFunctionExpression(FunctionExpression node) {
    // Capturer l'environnement actuel pour la closure
    final currentEnv = _currentContext().lexicalEnvironment;
    // Pass strict mode context to function
    final currentStrictMode = _currentContext().strictMode;

    // Calculate function length (number of params until first default or rest)
    int functionLength = 0;
    for (final param in node.params) {
      if (param.defaultValue != null || param.isRest) {
        break;
      }
      functionLength++;
    }

    // Handle generator functions
    if (node.isGenerator) {
      // For generator function expressions, create a function that returns a generator
      final functionName =
          node.id?.name ?? _targetBindingNameForFunction ?? 'anonymous';
      final generatorFunction = JSNativeFunction(
        functionName: functionName,
        expectedArgs: functionLength,
        nativeImpl: (args) {
          // Return a generator object instead of executing the function
          return _createGenerator(
            // Convert FunctionExpression to FunctionDeclaration for _createGenerator
            FunctionDeclaration(
              id:
                  node.id ??
                  IdentifierExpression(
                    name: functionName,
                    line: node.line,
                    column: node.column,
                  ),
              params: node.params,
              body: node.body,
              line: node.line,
              column: node.column,
              isGenerator: true,
            ),
            args,
            currentEnv,
          );
        },
      );

      // If named function expression, bind it in an intermediate environment
      if (node.id != null) {
        final closureEnv = Environment(parent: currentEnv);
        closureEnv.define(node.id!.name, generatorFunction, BindingType.const_);
        // Update the function's closure environment
        // Note: JSNativeFunction doesn't have closure, but that's okay for generators
      }

      return generatorFunction;
    }

    // Si la fonction a un nom (named function expression), creer un environnement
    // intermediaire ou le nom de la fonction est lie a elle-meme
    Environment closureEnv = currentEnv;
    JSFunction? function;

    if (node.id != null) {
      // Create environnement intermediaire pour le nom de la fonction
      closureEnv = Environment(parent: currentEnv);
      // ES2019: Generate source text from AST
      final sourceText = node.toString();
      // Creer la fonction d'abord
      function = JSFunction(
        node,
        closureEnv,
        sourceText: sourceText,
        moduleUrl: _currentModuleUrl,
        strictMode: currentStrictMode,
        inferredName: node.id!.name,
      );
      // Puis lier son nom dans l'environnement intermediaire
      closureEnv.define(node.id!.name, function, BindingType.const_);
      return function;
    } else {
      // Fonction anonyme
      // ES2019: Generate source text from AST
      final sourceText = node.toString();
      // Use target binding name for function name inference (ES6 feature)
      final inferredName = _targetBindingNameForFunction;
      final func = JSFunction(
        node,
        currentEnv,
        sourceText: sourceText,
        moduleUrl: _currentModuleUrl,
        strictMode: currentStrictMode,
        inferredName: inferredName,
      );
      return func;
    }
  } // ===== NOT YET IMPLEMENTED =====

  /// Helper method to wrap callFunction and convert JSError to JSException
  JSValue _callFunctionWithErrorConversion(
    JSValue function,
    List<JSValue> args, [
    JSValue? thisBinding,
  ]) {
    try {
      return callFunction(function, args, thisBinding);
    } on JSError catch (jsError) {
      // Convertir les erreurs Dart JSError en JSException pour JavaScript
      // Mais ne pas convertir les JSException qui sont deja des erreurs JavaScript
      if (jsError is JSException) {
        rethrow;
      }

      // Recuperer le prototype approprie depuis le constructeur global
      JSObject? prototype;
      try {
        final constructorName = jsError.name;
        final constructor = _globalEnvironment.get(constructorName);
        if (constructor is JSFunction && constructor is JSObject) {
          final proto = constructor.getProperty('prototype');
          if (proto is JSObject) {
            prototype = proto;
          }
        }
      } catch (_) {
        // Si on ne peut pas recuperer le prototype, continuer sans
      }
      final errorValue = JSErrorObjectFactory.fromDartError(jsError, prototype);
      throw JSException(errorValue);
    }
  }

  @override
  JSValue visitCallExpression(CallExpression node) {
    // Determiner la valeur de 'this' et la fonction en une seule passe
    // For method calls (obj.method()), this is the object
    // For direct function calls (func()), this should be null and let the function decide based on its strict mode
    JSValue? thisBinding;
    JSValue
    calleeValue; // Si c'est un appel de methode (obj.method()), this devrait etre obj
    if (node.callee is MemberExpression) {
      final memberExpr = node.callee as MemberExpression;

      // Special handling for Function.prototype.call() and apply()
      // These need to be handled before evaluating the member expression
      if (memberExpr.property is IdentifierExpression) {
        final propName = (memberExpr.property as IdentifierExpression).name;
        if (propName == 'call' || propName == 'apply' || propName == 'bind') {
          // Evaluer l'objet (the function being called)
          final funcToBind = memberExpr.object.accept(this);

          // Evaluer les arguments
          final argValues = <JSValue>[];
          for (final arg in node.arguments) {
            if (arg is SpreadElement) {
              final spreadValue = arg.argument.accept(this);
              if (spreadValue is JSArray) {
                argValues.addAll(spreadValue.elements);
              } else if (spreadValue.isString) {
                final str = spreadValue.toString();
                for (int i = 0; i < str.length; i++) {
                  argValues.add(JSValueFactory.string(str[i]));
                }
              } else {
                throw JSTypeError('${spreadValue.type} is not iterable');
              }
            } else {
              argValues.add(arg.accept(this));
            }
          }

          // Handle Function.prototype.call specially
          if (propName == 'call') {
            if (!funcToBind.isFunction) {
              throw JSTypeError(
                'Function.prototype.call called on non-function',
              );
            }

            // ES6: Class constructors cannot be called without 'new'
            if (funcToBind is JSClass) {
              throw JSTypeError(
                'Class constructor ${funcToBind.name} cannot be invoked without \'new\'',
              );
            }

            // Check if this is a constructor-only function being called without 'new'
            if (funcToBind is JSNativeFunction &&
                funcToBind.isConstructor &&
                funcToBind.functionName == 'Promise') {
              throw JSTypeError(
                'Promise constructor requires the \'new\' keyword',
              );
            }

            // Arguments: [thisArg, arg1, arg2, ...]
            final effectiveThisArg = argValues.isNotEmpty
                ? argValues[0]
                : JSValueFactory.undefined();
            final funcArgs = argValues.length > 1
                ? argValues.sublist(1)
                : <JSValue>[];

            // Call the function with the specified this binding
            return _callFunctionWithErrorConversion(
              funcToBind,
              funcArgs,
              effectiveThisArg,
            );
          }

          // Handle Function.prototype.apply specially
          if (propName == 'apply') {
            if (!funcToBind.isFunction) {
              throw JSTypeError(
                'Function.prototype.apply called on non-function',
              );
            }

            // ES6: Class constructors cannot be called without 'new'
            if (funcToBind is JSClass) {
              throw JSTypeError(
                'Class constructor ${funcToBind.name} cannot be invoked without \'new\'',
              );
            }

            // Arguments: [thisArg, argsArray]
            final effectiveThisArg = argValues.isNotEmpty
                ? argValues[0]
                : JSValueFactory.undefined();

            List<JSValue> funcArgs = [];
            if (argValues.length > 1) {
              final argsArray = argValues[1];
              if (!argsArray.isNull && !argsArray.isUndefined) {
                if (argsArray is JSArray) {
                  funcArgs = argsArray.elements.toList();
                } else if (argsArray is JSObject) {
                  final lengthProp = argsArray.getProperty('length');
                  if (lengthProp.isNumber) {
                    final length = _safeToInt(lengthProp.toNumber());
                    funcArgs = List.generate(length, (i) {
                      return argsArray.getProperty(i.toString());
                    });
                  }
                } else {
                  throw JSTypeError(
                    'Function.prototype.apply: arguments list has wrong type',
                  );
                }
              }
            }

            // Call the function with the specified this binding
            return _callFunctionWithErrorConversion(
              funcToBind,
              funcArgs,
              effectiveThisArg,
            );
          }

          // Handle Function.prototype.bind specially
          if (propName == 'bind') {
            if (!funcToBind.isFunction) {
              throw JSTypeError(
                'Function.prototype.bind called on non-function',
              );
            }

            // Arguments: [thisArg, arg1, arg2, ...]
            final boundThisArg = argValues.isNotEmpty
                ? argValues[0]
                : JSValueFactory.undefined();
            final boundArgs = argValues.length > 1
                ? argValues.sublist(1)
                : <JSValue>[];

            // Return a bound function
            return JSBoundFunction(funcToBind, boundThisArg, boundArgs);
          }
        }
      }

      // Evaluer l'objet une seule fois
      final objectValue = memberExpr.object.accept(this);

      // Verifier si l'objet est null ou undefined (TypeError en JS)
      if (objectValue.isNull || objectValue.isUndefined) {
        final propName = memberExpr.computed
            ? memberExpr.property.accept(this).toString()
            : (memberExpr.property as IdentifierExpression).name;
        throw JSTypeError(
          "Cannot read properties of ${objectValue.isNull ? 'null' : 'undefined'} (reading '$propName')",
        );
      }

      // Cas special pour super.method() : utiliser le this du contexte actuel
      if (memberExpr.object is SuperExpression) {
        thisBinding = _currentContext().thisBinding;
      } else {
        thisBinding = objectValue;
      }

      // Maintenant obtenir la propriete/methode
      if (memberExpr.computed) {
        // obj[method]()
        final keyValue = memberExpr.property.accept(this);
        if (objectValue is JSObject) {
          final propertyKey = JSConversion.jsToString(keyValue);
          calleeValue = objectValue.getProperty(propertyKey);
        } else if (objectValue is JSArray) {
          if (keyValue.isNumber) {
            final index = keyValue.toNumber().floor();
            calleeValue = objectValue.get(index);
          } else if (keyValue.isString) {
            calleeValue = objectValue.getProperty(keyValue.toString());
          } else {
            calleeValue = JSValueFactory.undefined();
          }
        } else if (objectValue is JSNativeFunction) {
          // Support pour l'acces aux proprietes statiques des constructeurs
          final propertyKey = JSConversion.jsToString(keyValue);
          calleeValue = objectValue.getProperty(propertyKey);
        } else if (objectValue.isString) {
          // Support pour les appels de methodes sur strings: str[method]()
          final str = objectValue.toString();
          if (keyValue.isNumber) {
            final index = keyValue.toNumber().floor();
            if (index >= 0 && index < str.length) {
              calleeValue = JSValueFactory.string(str[index]);
            } else {
              calleeValue = JSValueFactory.undefined();
            }
          } else if (keyValue.isString) {
            final propertyKey = keyValue.toString();
            calleeValue = StringPrototype.getStringProperty(str, propertyKey);
          } else if (keyValue is JSSymbol) {
            // Support pour Symbol keys sur strings (comme Symbol.iterator)
            calleeValue = StringPrototype.getStringProperty(
              str,
              keyValue.toString(),
            );
          } else {
            calleeValue = JSValueFactory.undefined();
          }
        } else if (objectValue is JSFunction) {
          // Support for accessing properties/methods on functions
          final propertyKey = JSConversion.jsToString(keyValue);
          calleeValue = objectValue.getProperty(propertyKey);
        } else if (objectValue is JSClass) {
          // Support for accessing static properties/methods on classes
          final propertyKey = JSConversion.jsToString(keyValue);
          calleeValue = objectValue.getProperty(propertyKey);
        } else {
          throw JSError(
            'Member access on ${objectValue.type} not implemented yet',
          );
        }
      } else {
        // obj.method() ou obj.#privateMethod()
        String propName;

        if (memberExpr.property is IdentifierExpression) {
          propName = (memberExpr.property as IdentifierExpression).name;
        } else if (memberExpr.property is PrivateIdentifierExpression) {
          final originalName =
              (memberExpr.property as PrivateIdentifierExpression).name;

          // NOUVEAU: Valider l'acces aux methodes privees
          JSClass? propertyOwnerClass;

          // Si l'objet est une classe directement (pour methodes statiques)
          if (objectValue is JSClass) {
            propertyOwnerClass = objectValue;
          }
          // Si l'objet est une instance de classe, chercher la classe qui definit cette methode
          else if (objectValue is JSObject) {
            JSObject? current = objectValue;
            while (current != null) {
              final constructor = current.getProperty('constructor');
              if (constructor is JSClass) {
                propertyOwnerClass = constructor;
                break;
              }
              current = current.getPrototype();
            }
          }

          // Verifier que l'acces se fait depuis le bon contexte de classe
          final currentClass = _currentClassContext;

          if (propertyOwnerClass == null) {
            throw JSError('Private method #$originalName is not defined');
          }

          if (currentClass == null || !_isInClassContext(propertyOwnerClass)) {
            throw JSSyntaxError(
              "Private method '#$originalName' must be called from an enclosing class",
            );
          }

          // Transformer les noms des methodes privees pour l'acces
          propName = '_private_$originalName';
        } else {
          throw JSError('Invalid property access');
        }

        if (objectValue is JSArray) {
          calleeValue = objectValue.getProperty(propName);
        } else if (objectValue is JSObject) {
          calleeValue = objectValue.getProperty(propName);
        } else if (objectValue is JSString) {
          calleeValue = StringPrototype.getStringProperty(
            objectValue.value,
            propName,
          );
        } else if (objectValue is JSNumber) {
          calleeValue = NumberPrototype.getNumberProperty(
            objectValue.value,
            propName,
          );
        } else if (objectValue is JSBigInt) {
          calleeValue = BigIntPrototype.getBigIntProperty(
            objectValue.value,
            propName,
          );
        } else if (objectValue is JSBoolean) {
          calleeValue = BooleanPrototype.getBooleanProperty(
            objectValue.value,
            propName,
          );
        } else {
          if (objectValue is JSSymbol) {
            // Support pour les methodes sur les symbols - lookup from Symbol.prototype
            try {
              final symbolConstructor = _globalEnvironment.get('Symbol');
              if (symbolConstructor is JSNativeFunction) {
                final symbolPrototype = symbolConstructor.getProperty(
                  'prototype',
                );
                if (symbolPrototype is JSObject) {
                  calleeValue = symbolPrototype.getProperty(propName);
                } else {
                  calleeValue = JSValueFactory.undefined();
                }
              } else {
                calleeValue = JSValueFactory.undefined();
              }
            } catch (e) {
              calleeValue = JSValueFactory.undefined();
            }
          } else if (objectValue is JSFunction) {
            // Special handling for super.method() before super() is called
            if (memberExpr.object is SuperExpression &&
                objectValue is JSNativeFunction &&
                objectValue.functionName == 'super') {
              // CHECK: In a derived class constructor, accessing super.property before super() is called should throw ReferenceError
              final isInConstructor =
                  _constructorStack.isNotEmpty && _constructorStack.last;
              if (isInConstructor && !_isSuperCalled()) {
                throw JSReferenceError(
                  'must call super constructor before accessing super in derived class',
                );
              }

              // This is a super property/method access
              final currentClass = _currentClassContext;
              if (currentClass != null && currentClass.superClass != null) {
                final superClass = currentClass.superClass!;
                final parentProto = superClass.getProperty('prototype');
                if (parentProto is JSObject) {
                  calleeValue = parentProto.getProperty(propName);
                } else {
                  calleeValue = JSValueFactory.undefined();
                }
              } else {
                calleeValue = JSValueFactory.undefined();
              }
            } else {
              calleeValue = objectValue.getProperty(propName);
            }
          } else if (objectValue is JSClass) {
            calleeValue = objectValue.getProperty(propName);
          } else if (objectValue is JSNativeFunction) {
            // Support pour l'acces aux proprietes statiques des constructeurs
            calleeValue = objectValue.getProperty(propName);
          } else {
            throw JSError(
              'Property access on ${objectValue.type} not implemented yet',
            );
          }
        }
      }
    } else {
      // Appel de fonction normal - evaluer la fonction
      calleeValue = node.callee.accept(this);
    }

    // Verifier si c'est un appel super() dans un constructeur
    // NOTE: When super() is called in a constructor, the callee (SuperExpression) evaluates to
    // a JSNativeFunction, not a JSClass. We need to check for SuperExpression callee, not JSClass calleeValue

    if (node.callee is SuperExpression) {
      // For super() calls, we need to use the current 'this' from the execution context
      // rather than setting it based on the callee (which is null for direct super calls)
      var currentThis = thisBinding;
      if (currentThis == null || currentThis is! JSObject) {
        // Use the 'this' binding from the current execution context
        currentThis = _currentContext().thisBinding;
      }

      if (currentThis is JSObject) {
        // Evaluer les arguments d'abord (BEFORE checking if super was called)
        // This ensures side effects of argument evaluation happen before the error
        final argumentValues = <JSValue>[];
        bool superCalledInArguments = false;
        final superCalledBefore = _isSuperCalled();

        for (final arg in node.arguments) {
          if (arg is SpreadElement) {
            final spreadValue = arg.argument.accept(this);
            if (spreadValue is JSArray) {
              argumentValues.addAll(spreadValue.elements);
            } else if (spreadValue.isString) {
              final str = spreadValue.toString();
              for (int i = 0; i < str.length; i++) {
                argumentValues.add(JSValueFactory.string(str[i]));
              }
            } else {
              throw JSTypeError('${spreadValue.type} is not iterable');
            }
          } else {
            argumentValues.add(arg.accept(this));
          }

          // Check if super() was called during argument evaluation
          if (!superCalledBefore && _isSuperCalled()) {
            superCalledInArguments = true;
            break;
          }
        }

        // NOTE: Don't check superCalledBefore here - let the native super function handle
        // the check and throw the error AFTER calling the super constructor
        // This ensures side effects of the super constructor are visible even if error is thrown

        // CHECK: super() cannot be called inside arguments to super()
        if (superCalledInArguments) {
          throw JSReferenceError(
            'super() cannot be called inside arguments to super()',
          );
        }

        // NOTE: The native super function (_createSuperFunction) will call _markSuperCalled()
        // So we don't mark it here - it will be marked when the native function is executed

        // Call the appropriate super() handler based on calleeValue type
        if (calleeValue is JSClass) {
          // Appeler construct avec l'instance existante
          return calleeValue.construct(argumentValues, currentThis);
        } else if (calleeValue is JSNativeFunction) {
          // Call the native super function
          // The native function (_createSuperFunction) will call _markSuperCalled() internally
          return calleeValue.callWithThis(argumentValues, currentThis);
        } else {
          throw JSTypeError('super() callee must be a function or class');
        }
      }
    }

    // Classes cannot be called without 'new' - must throw TypeError
    if (calleeValue is JSClass) {
      throw JSTypeError(
        "Class constructor ${(calleeValue).getProperty('name')} cannot be invoked without 'new'",
      );
    }

    if (!calleeValue.isFunction) {
      // Ameliorer le message d'erreur pour etre plus conforme a JavaScript
      final description = _getValueDescription(calleeValue);

      throw JSTypeError('$description is not a function');
    }

    // Evaluer les arguments
    final argumentValues = <JSValue>[];
    for (final arg in node.arguments) {
      if (arg is SpreadElement) {
        // Spread element: func(...args)
        final spreadValue = arg.argument.accept(this);

        if (spreadValue is JSArray) {
          // Spread d'un array dans les arguments
          argumentValues.addAll(spreadValue.elements);
        } else if (spreadValue.isString) {
          // Spread d'une string dans les arguments
          final str = spreadValue.toString();
          for (int i = 0; i < str.length; i++) {
            argumentValues.add(JSValueFactory.string(str[i]));
          }
        } else {
          throw JSTypeError('${spreadValue.type} is not iterable');
        }
      } else {
        argumentValues.add(arg.accept(this));
      }
    }

    // Verifier si c'est une fonction native
    if (calleeValue is JSNativeFunction) {
      // Check if this is a constructor-only function being called without 'new'
      if (calleeValue.isConstructor && calleeValue.functionName == 'Promise') {
        throw JSTypeError('Promise constructor requires the \'new\' keyword');
      }

      // Special case: Date() without 'new' should return a string, not an object
      if (calleeValue.functionName == 'Date') {
        // Call the native Date constructor to create the object
        final dateObj = calleeValue.call(argumentValues);
        // Convert to string representation (ISO string)
        if (dateObj is JSDate) {
          return JSValueFactory.string(dateObj.toISOString());
        }
        return JSValueFactory.string(dateObj.toString());
      }

      // Appel de fonction native (comme console.log)
      // Si c'est un appel de methode, utiliser callWithThis pour le bon this binding
      if (node.callee is MemberExpression) {
        // For method calls, thisBinding is always set (it's the object)
        try {
          return calleeValue.callWithThis(argumentValues, thisBinding!);
        } on JSError catch (jsError) {
          // Convert JSError to JSException for JavaScript catch blocks
          if (jsError is JSException) {
            rethrow;
          }

          // Get appropriate prototype from global constructor
          JSObject? prototype;
          try {
            final constructorName = jsError.name;
            final constructor = _globalEnvironment.get(constructorName);
            if (constructor is JSFunction && constructor is JSObject) {
              final proto = constructor.getProperty('prototype');
              if (proto is JSObject) {
                prototype = proto;
              }
            }
          } catch (_) {
            // Continue without prototype if we can't get it
          }
          final errorValue = JSErrorObjectFactory.fromDartError(
            jsError,
            prototype,
          );
          throw JSException(errorValue);
        }
      } else {
        return calleeValue.call(argumentValues);
      }
    }

    // Verifier si c'est une arrow function
    if (calleeValue is JSArrowFunction) {
      return _callArrowFunction(calleeValue, argumentValues);
    }

    // Verifier si c'est une bound function
    if (calleeValue is JSBoundFunction) {
      return _callBoundFunction(calleeValue, argumentValues);
    }

    // Utiliser notre methode centralisee pour tous les autres types de fonctions
    return _callFunctionWithErrorConversion(
      calleeValue,
      argumentValues,
      thisBinding,
    );
  }

  /// Helper to cache and return an object created by 'new' in async context
  JSValue _cacheNewObjectAndReturn(NewExpression node, JSValue result) {
    final asyncTask = _executionStack.current.asyncTask;
    if (asyncTask is AsyncTask && asyncTask.continuation != null) {
      asyncTask.continuation!.cacheCreatedObject(node.hashCode, result);
    }
    return result;
  }

  @override
  JSValue visitNewExpression(NewExpression node) {
    // BUGFIX: In async function resumption, return cached object if it exists
    // This prevents re-creating objects when the async function body is re-executed
    final asyncTask = _executionStack.current.asyncTask;
    if (asyncTask is AsyncTask && asyncTask.continuation != null) {
      final continuation = asyncTask.continuation!;
      final cachedObject = continuation.getCachedObject(node.hashCode);
      if (cachedObject != null) {
        return cachedObject;
      }
    }

    // Evaluer la fonction constructeur
    final constructorValue = node.callee.accept(this);

    // Support special pour les fonctions bound utilisees comme constructeurs
    if (constructorValue is JSBoundFunction) {
      // Pour les fonctions bound, utiliser la fonction originale comme constructeur
      // Combiner les arguments bound avec les nouveaux arguments
      final argumentValues = <JSValue>[];
      for (final arg in node.arguments) {
        if (arg is SpreadElement) {
          // Spread dans les arguments: new Constructor(...args)
          final spreadValue = arg.argument.accept(this);

          if (spreadValue is JSArray) {
            argumentValues.addAll(spreadValue.elements);
          } else if (spreadValue.isString) {
            final str = spreadValue.toString();
            for (int i = 0; i < str.length; i++) {
              argumentValues.add(JSValueFactory.string(str[i]));
            }
          } else {
            throw JSTypeError('${spreadValue.type} is not iterable');
          }
        } else {
          argumentValues.add(arg.accept(this));
        }
      }

      final allArgs = [...constructorValue.boundArgs, ...argumentValues];
      final originalFunc = constructorValue.originalFunction;

      // Handle JSClass bound constructor
      if (originalFunc is JSClass) {
        // Reset super() call tracking for this constructor invocation
        _pushConstructorLevel();
        try {
          // For bound class, call construct with the combined args
          return originalFunc.construct(allArgs);
        } finally {
          _popConstructorLevel();
        }
      }

      // Create nouvel objet et l'utiliser comme 'this'
      final newObject = JSObject();

      // Obtenir le prototype de la fonction originale
      final prototypeValue = originalFunc is JSFunction
          ? (originalFunc).getProperty('prototype')
          : originalFunc is JSNativeFunction
          ? (originalFunc).getProperty('prototype')
          : JSValueFactory.undefined();
      if (prototypeValue is JSObject) {
        newObject.setPrototype(prototypeValue);
      }
      newObject.setProperty('constructor', constructorValue);

      // Appeler la fonction originale avec le nouvel objet comme 'this'
      // ES6: Set new.target to the original function
      if (originalFunc is JSFunction) {
        // Push constructor level for proper super() tracking
        _pushConstructorLevel();
        try {
          _callJSFunction(originalFunc, allArgs, newObject, originalFunc);
        } finally {
          _popConstructorLevel();
        }
      } else if (originalFunc is JSNativeFunction) {
        (originalFunc).callWithThis(allArgs, newObject);
      }

      return _cacheNewObjectAndReturn(node, newObject);
    }

    // Evaluer les arguments
    final argumentValues = <JSValue>[];
    for (final arg in node.arguments) {
      if (arg is SpreadElement) {
        // Spread dans les arguments: new Constructor(...args)
        final spreadValue = arg.argument.accept(this);

        if (spreadValue is JSArray) {
          argumentValues.addAll(spreadValue.elements);
        } else if (spreadValue.isString) {
          final str = spreadValue.toString();
          for (int i = 0; i < str.length; i++) {
            argumentValues.add(JSValueFactory.string(str[i]));
          }
        } else {
          throw JSTypeError('${spreadValue.type} is not iterable');
        }
      } else {
        argumentValues.add(arg.accept(this));
      }
    }

    // Support pour les constructeurs natifs
    if (constructorValue is JSNativeFunction) {
      // Check if this function is a constructor
      if (!constructorValue.isConstructor) {
        throw JSTypeError(
          '${constructorValue.functionName} is not a constructor',
        );
      }

      try {
        // Pour les constructeurs natifs, appeler directement la fonction
        // qui doit retourner un objet approprie
        final result = constructorValue.call(argumentValues);

        // Si le resultat est un objet ou une fonction, s'assurer qu'il a le bon prototype
        if (result is JSObject || result is JSFunction) {
          // S'assurer que l'objet a le bon prototype
          if (result is JSObject) {
            // Special case: JSProxy already handles its own prototype setup
            // in the constructor via setInternalPrototype() to bypass the trap
            // Also skip setting prototype for primitive wrapper objects returned
            // by Object() constructor - they already have the correct prototype
            // (e.g., JSStringObject has String.prototype)
            final isPrimitiveWrapper =
                result is JSStringObject ||
                result is JSNumberObject ||
                result is JSBooleanObject ||
                result is JSBigIntObject;
            if (result is! JSProxy && !isPrimitiveWrapper) {
              final prototypeValue = constructorValue.getProperty('prototype');
              if (prototypeValue is JSObject) {
                result.setPrototype(prototypeValue);
              }
            }
            // S'assurer que constructor est defini
            // NOTE: Don't set constructor on JSProxy - it would trigger the set trap
            // Also don't override constructor for primitive wrappers - they inherit
            // their constructor from their prototype (e.g., String.prototype.constructor)
            if (result is! JSProxy &&
                !isPrimitiveWrapper &&
                !result.hasOwnProperty('constructor')) {
              result.setProperty('constructor', constructorValue);
            }
          }
          return result;
        }

        // Pour les types primitifs, creer un objet wrapper approprie
        // new String(...) → JSStringObject
        // NOTE: Don't set constructor as own property - it should come from prototype
        if (result is JSString) {
          final stringWrapper = JSStringObject(result.value);
          final prototypeValue = constructorValue.getProperty('prototype');
          if (prototypeValue is JSObject) {
            stringWrapper.setPrototype(prototypeValue);
          }
          return _cacheNewObjectAndReturn(node, stringWrapper);
        }

        // new Number(...) → JSNumberObject
        // NOTE: Don't set constructor as own property - it should come from prototype
        if (result is JSNumber) {
          final numberWrapper = JSNumberObject(result.value);
          final prototypeValue = constructorValue.getProperty('prototype');
          if (prototypeValue is JSObject) {
            numberWrapper.setPrototype(prototypeValue);
          }
          return _cacheNewObjectAndReturn(node, numberWrapper);
        }

        // new Boolean(...) → JSBooleanObject
        // NOTE: Don't set constructor as own property - it should come from prototype
        if (result is JSBoolean) {
          final booleanWrapper = JSBooleanObject(result.value);
          final prototypeValue = constructorValue.getProperty('prototype');
          if (prototypeValue is JSObject) {
            booleanWrapper.setPrototype(prototypeValue);
          }
          return _cacheNewObjectAndReturn(node, booleanWrapper);
        }

        // Sinon, creer un objet generique et configurer le prototype
        final newObject = JSObject();
        final prototypeValue = constructorValue.getProperty('prototype');
        if (prototypeValue is JSObject) {
          newObject.setPrototype(prototypeValue);
        }
        newObject.setProperty('constructor', constructorValue);
        return _cacheNewObjectAndReturn(node, newObject);
      } catch (e) {
        // Rethrow all JavaScript errors (JSTypeError, JSRangeError, etc.)
        if (e is JSError) rethrow;
        throw JSError('Constructor error: $e');
      }
    }

    // Support pour les classes ES6
    if (constructorValue is JSClass) {
      // Createe nouvelle instance
      // If the class extends a native type (Array, etc.), create the appropriate type
      JSObject newObject;
      final superFunction = constructorValue.superFunction;
      if (superFunction != null && superFunction is JSNativeFunction) {
        final funcName = superFunction.functionName;
        if (funcName == 'Array') {
          // Create a JSArray instance for Array subclasses
          newObject = JSValueFactory.array([]);
        } else if (funcName == 'Error' ||
            funcName == 'TypeError' ||
            funcName == 'RangeError' ||
            funcName == 'ReferenceError' ||
            funcName == 'SyntaxError' ||
            funcName == 'EvalError' ||
            funcName == 'URIError') {
          // Create an error object for Error subclasses
          newObject = JSObject();
        } else if (funcName == 'Map') {
          // Create a JSMap instance for Map subclasses
          newObject = JSMap();
        } else if (funcName == 'Set') {
          // Create a JSSet instance for Set subclasses
          newObject = JSSet();
        } else if (funcName == 'Promise') {
          // Promise subclasses need special handling - create wrapper object
          newObject = JSObject();
        } else {
          // Default to JSObject for other native types
          newObject = JSObject();
        }
      } else {
        // Regular class, create JSObject
        newObject = JSObject();
      }
      newObject.setPrototype(constructorValue.prototype);
      newObject.setProperty('constructor', constructorValue);

      // NOUVEAU: Initialiser les champs d'instance avec leurs valeurs par defaut
      // AVANT d'appeler le constructor. Initialiser d'abord les champs de la
      // superclass, puis ceux de la classe actuelle (pour respecter l'ordre d'heritage)
      final classHierarchy = <JSClass>[];
      JSClass? currentClass = constructorValue;
      while (currentClass != null) {
        classHierarchy.insert(
          0,
          currentClass,
        ); // Insert au debut pour avoir l'ordre: Base -> Derived
        currentClass = currentClass.superClass;
      }

      for (final classInHierarchy in classHierarchy) {
        _pushClassContext(classInHierarchy);
        final fieldContext = ExecutionContext(
          lexicalEnvironment: Environment(
            parent: classInHierarchy.closureEnvironment,
          ),
          variableEnvironment: Environment(
            parent: classInHierarchy.closureEnvironment,
          ),
          thisBinding: newObject,
        );
        _executionStack.push(fieldContext);
        try {
          for (final fieldMember in classInHierarchy.instanceFields) {
            String fieldName;
            bool isPrivateField = false;

            if (fieldMember.key is IdentifierExpression) {
              fieldName = (fieldMember.key as IdentifierExpression).name;
            } else if (fieldMember.key is PrivateIdentifierExpression) {
              fieldName = (fieldMember.key as PrivateIdentifierExpression).name;
              isPrivateField = true;
            } else {
              // For computed property names, evaluate the expression to get the key
              final keyValue = fieldMember.key.accept(this);
              fieldName = keyValue.toString();
            }

            final storageKey = isPrivateField
                ? '_private_$fieldName'
                : fieldName;

            // Evaluer l'initializer si present
            JSValue initialValue = JSValueFactory.undefined();
            if (fieldMember.initializer != null) {
              initialValue = fieldMember.initializer.accept(this);
            }

            newObject.setProperty(storageKey, initialValue);
          }
        } finally {
          _executionStack.pop();
          _popClassContext();
        }
      }

      // Appeler le constructor s'il existe
      if (constructorValue.constructor != null) {
        final constructor = constructorValue.constructor!;
        final declaration = constructor.declaration;

        if (declaration != null) {
          final functionEnv = Environment(
            parent: constructor.closureEnvironment,
          );
          // Create arguments object (array-like) for class constructors
          final argumentsObject = JSValueFactory.argumentsObject({});
          // Mark the arguments object so that callee/caller access throws
          argumentsObject.markAsArgumentsObject();
          argumentsObject.setProperty(
            'length',
            JSValueFactory.number(argumentValues.length.toDouble()),
          );
          for (int i = 0; i < argumentValues.length; i++) {
            argumentsObject.setProperty(i.toString(), argumentValues[i]);
          }
          functionEnv.define('arguments', argumentsObject, BindingType.var_);

          // Bind parameters to arguments
          final params = declaration.params;
          if (params != null) {
            for (int i = 0; i < params.length; i++) {
              final param = params[i];

              if (param == null) continue;

              // Gerer les rest parameters
              if (param.isRest) {
                final restArgs = <JSValue>[];
                for (int j = i; j < argumentValues.length; j++) {
                  restArgs.add(argumentValues[j]);
                }
                final restArray = JSValueFactory.array(restArgs);

                if (param.name != null) {
                  functionEnv.define(
                    param.name!.name,
                    restArray,
                    BindingType.parameter,
                  );
                }
                break; // Rest parameter doit etre le dernier
              }

              JSValue argValue;
              if (i < argumentValues.length) {
                argValue = argumentValues[i];
              } else if (param.defaultValue != null) {
                final paramContext = ExecutionContext(
                  lexicalEnvironment: functionEnv,
                  variableEnvironment: functionEnv,
                  thisBinding: newObject,
                );
                _executionStack.push(paramContext);
                try {
                  argValue = param.defaultValue!.accept(this);
                } finally {
                  _executionStack.pop();
                }
              } else {
                argValue = JSValueFactory.undefined();
              }

              // Gerer le destructuring ou les parametres simples
              if (param.isDestructuring && param.pattern != null) {
                // Destructuring parameter: {x, y} ou [a, b]
                _destructurePattern(param.pattern!, argValue, functionEnv);
              } else if (param.name != null) {
                // Simple parameter
                functionEnv.define(
                  param.name!.name,
                  argValue,
                  BindingType.parameter,
                );
              } else {
                throw JSError(
                  'Parameter $i has neither name nor pattern in constructor',
                );
              }
            }
          }

          // Add support for super() in the constructor
          if (constructorValue.superClass != null) {
            final superConstructor = _createSuperFunction(
              constructorValue.superClass!,
              newObject,
            );

            // Definir super dans l'environnement du constructeur
            functionEnv.define('super', superConstructor, BindingType.var_);
          } else if (constructorValue.superFunction != null) {
            // Support pour les super classes natives (Promise, Array, etc.)
            final nativeSuperFunction = constructorValue.superFunction!;

            // Createe fonction qui appellera le super constructor correctement
            final evaluator = this;
            final superConstructor = JSNativeFunction(
              functionName: 'super',
              nativeImpl: (args) {
                // Symbol cannot be called with super()
                if (nativeSuperFunction is JSNativeFunction &&
                    nativeSuperFunction.functionName == 'Symbol') {
                  throw JSTypeError('Symbol cannot be called with super()');
                }

                // Mark that super() was called
                evaluator._markSuperCalled();

                // Special handling for Array subclasses
                // super(42) should set length to 42 on the existing this object
                if (nativeSuperFunction is JSNativeFunction &&
                    nativeSuperFunction.functionName == 'Array') {
                  if (args.isEmpty) {
                    // super() - no arguments, length stays 0
                  } else if (args.length == 1 && args[0].isNumber) {
                    // super(len) - set length
                    final numValue = args[0].toNumber();
                    if (numValue.isNaN ||
                        numValue.isInfinite ||
                        numValue < 0 ||
                        numValue > 4294967295 ||
                        numValue != numValue.truncateToDouble()) {
                      throw JSRangeError('Invalid array length');
                    }
                    newObject.setProperty(
                      'length',
                      JSValueFactory.number(numValue),
                    );
                  } else {
                    // super(elem1, elem2, ...) - set elements
                    for (int i = 0; i < args.length; i++) {
                      newObject.setProperty(i.toString(), args[i]);
                    }
                    newObject.setProperty(
                      'length',
                      JSValueFactory.number(args.length.toDouble()),
                    );
                  }
                  return newObject;
                }

                // Special handling for Promise subclasses
                // super(executor) should initialize Promise on the existing this object
                if (nativeSuperFunction is JSNativeFunction &&
                    nativeSuperFunction.functionName == 'Promise') {
                  if (args.isEmpty) {
                    throw JSTypeError(
                      'Promise constructor requires 1 argument',
                    );
                  }
                  final executor = args[0];
                  if (executor is! JSFunction) {
                    throw JSTypeError('Promise executor must be a function');
                  }

                  // Initialize Promise internal slots on the existing object
                  // We need to make newObject behave like a Promise
                  // Store the promise-specific state in a JSPromise wrapper
                  final promise = JSPromise.createInternal();

                  // Copy the promise state handling to newObject
                  newObject.setInternalSlot('[[PromiseState]]', promise);

                  // Create resolve and reject functions
                  final resolveFunction = JSNativeFunction(
                    functionName: '',
                    expectedArgs: 1,
                    nativeImpl: (resolveArgs) {
                      final value = resolveArgs.isNotEmpty
                          ? resolveArgs[0]
                          : JSValueFactory.undefined();
                      promise.resolve(value);
                      return JSValueFactory.undefined();
                    },
                    isConstructor: false,
                  );

                  final rejectFunction = JSNativeFunction(
                    functionName: '',
                    expectedArgs: 1,
                    nativeImpl: (rejectArgs) {
                      final reason = rejectArgs.isNotEmpty
                          ? rejectArgs[0]
                          : JSValueFactory.undefined();
                      promise.reject(reason);
                      return JSValueFactory.undefined();
                    },
                    isConstructor: false,
                  );

                  // Call the executor with resolve and reject
                  try {
                    evaluator.callFunction(executor, [
                      resolveFunction,
                      rejectFunction,
                    ], JSValueFactory.undefined());
                  } catch (e) {
                    // If executor throws, reject the promise
                    if (e is JSException) {
                      promise.reject(e.value);
                    } else if (e is JSError) {
                      promise.reject(JSValueFactory.string(e.message));
                    } else {
                      promise.reject(JSValueFactory.string(e.toString()));
                    }
                  }

                  // Make newObject delegate promise methods to the internal promise
                  newObject.setInternalSlot('[[PromiseInstance]]', promise);

                  return newObject;
                }

                // Appeler la fonction native comme constructeur
                // avec thisObject comme contexte
                if (nativeSuperFunction is JSNativeFunction) {
                  return nativeSuperFunction.callWithThis(args, newObject);
                } else {
                  // Pour les autres types de JSFunction, les appeler via l'evaluator
                  return evaluator.callFunction(
                    nativeSuperFunction,
                    args,
                    newObject,
                  );
                }
              },
            );

            // Definir super dans l'environnement du constructeur
            functionEnv.define('super', superConstructor, BindingType.var_);
          } else if (constructorValue.extendsNull) {
            // class extends null - super() tries to call %FunctionPrototype% as constructor
            // which is not a constructor, so it throws TypeError
            final superConstructor = JSNativeFunction(
              functionName: 'super',
              nativeImpl: (args) {
                // Per spec: When class extends null, [[ConstructorParent]] is %FunctionPrototype%
                // super() calls GetSuperConstructor() which returns %FunctionPrototype%
                // Since %FunctionPrototype% is not a constructor, TypeError is thrown
                throw JSTypeError(
                  'Super constructor null of C is not a constructor',
                );
              },
            );
            functionEnv.define('super', superConstructor, BindingType.var_);
          }

          // Creer le contexte d'execution pour le constructor
          // ES6: Class constructors are always in strict mode
          // ES6: Set new.target to the class being constructed
          final constructorContext = ExecutionContext(
            lexicalEnvironment: functionEnv,
            variableEnvironment: functionEnv,
            thisBinding: newObject,
            strictMode: true, // ES6: Class constructors are always strict
            newTarget: constructorValue, // ES6: new.target is the class
          );

          _executionStack.push(constructorContext);

          // NUOVO: Tracker il contesto di classe per le proprieta private
          _pushClassContext(constructorValue);

          // Reset super() call tracking for this constructor
          _pushConstructorLevel();

          // BUGFIX: Push to _constructorStack so visitThisExpression knows we're in a constructor
          _constructorStack.add(true);

          // Push the newObject as the current 'this' for constructor execution
          // When super() returns an object, this will be updated
          _constructorThisStack.add(newObject);

          JSValue resultThis =
              newObject; // Will be updated if super() returns an object
          try {
            // Executer le corps du constructor
            declaration.body.accept(this);

            // Check if super() was required but not called after normal completion
            if (constructorValue.isDerivedClass &&
                !constructorValue.extendsNull) {
              // Regular derived classes require super() to be called
              // BUT null-extending classes don't (super() would fail anyway)
              if (!_isSuperCalled()) {
                throw JSReferenceError(
                  'must call super constructor before using this in derived class',
                );
              }
            }

            // For null-extending classes returning undefined, check if this is initialized
            // Per spec: 9.2.2 [[Construct]] - step 15: Return ? envRec.GetThisBinding()
            // If this was never initialized (not modified by super), GetThisBinding throws ReferenceError
            if (constructorValue.extendsNull) {
              // Check if 'this' was ever modified (would indicate initialization)
              // For null-extending classes, 'this' starts as undefined and must be explicitly
              // modified or an object must be returned
              // Since we can't modify uninitialized 'this', accessing it throws
              throw JSReferenceError(
                'this is not initialized in constructor of null-extending class',
              );
            }

            // Capture the current 'this' which may have been updated by super()
            resultThis = _constructorThisStack.last;
          } on FlowControlException catch (e) {
            if (e.type == ExceptionType.return_ && e.value != null) {
              // Si le constructor retourne explicitement un objet, l'utiliser
              // Note: Must check type, not Dart inheritance, since JSSymbol extends JSObject
              if (e.value is JSObject && e.value!.type == JSValueType.object) {
                // Explicit object return is always valid, even without super() call
                resultThis = e.value!;
              } else {
                // For derived classes, returning a non-object throws TypeError
                // This check happens BEFORE the super() check per spec
                if (e.value != null && !e.value!.isUndefined) {
                  if (constructorValue.isDerivedClass) {
                    // Derived class cannot return non-object values
                    throw JSTypeError(
                      'Derived constructors may only return object or undefined',
                    );
                  }
                }

                // For undefined returns (returning `this`), check if super() was called
                // BUT null-extending classes don't require super() (it would fail anyway)
                // BUT null-extending classes with undefined return must throw because 'this' is uninitialized
                if (constructorValue.extendsNull) {
                  throw JSReferenceError(
                    'this is not initialized in constructor of null-extending class',
                  );
                }

                if (constructorValue.isDerivedClass &&
                    !constructorValue.extendsNull) {
                  if (!_isSuperCalled()) {
                    throw JSReferenceError(
                      'must call super constructor before using this in derived class',
                    );
                  }
                }

                // Capture the current 'this' for undefined return
                resultThis = _constructorThisStack.last;
              }
            }
            // Sinon, ignorer (return dans un constructor ne retourne pas la valeur)
          } finally {
            _constructorStack
                .removeLast(); // BUGFIX: Pop from _constructorStack
            _constructorThisStack
                .removeLast(); // Pop from _constructorThisStack
            _popClassContext(); // NOUVEAU: Pop du contexte de classe
            _popConstructorLevel(); // Pop from constructor level stack
            _executionStack.pop();
          }

          // Return the result 'this' which may have been updated by super()
          return _cacheNewObjectAndReturn(node, resultThis);
        }
      } else if (constructorValue.superClass != null &&
          constructorValue.constructor == null) {
        // Default constructor for class extending another JS class (no explicit constructor)
        // Automatically call super(...args) with the provided arguments
        final result = constructorValue.superClass!.construct(
          argumentValues,
          newObject,
        );
        // If super constructor returned a different object, use it
        if (result is JSObject && result != newObject) {
          return _cacheNewObjectAndReturn(node, result);
        }
      } else if (constructorValue.superClass == null &&
          constructorValue.superFunction != null) {
        // Default constructor for class with native superclass (no explicit constructor)
        // Automatically call super(...args) with the provided arguments
        final nativeSuperFunction = constructorValue.superFunction!;

        // Symbol cannot be called with super() even implicitly
        if (nativeSuperFunction is JSNativeFunction &&
            nativeSuperFunction.functionName == 'Symbol') {
          throw JSTypeError('Symbol cannot be called with super()');
        }

        try {
          if (nativeSuperFunction is JSNativeFunction) {
            nativeSuperFunction.callWithThis(argumentValues, newObject);
          } else {
            // For other function types, call via evaluator
            callFunction(nativeSuperFunction, argumentValues, newObject);
          }
        } catch (e) {
          // Propagate constructor errors (e.g., TypeError from Promise)
          rethrow;
        }
      }

      return _cacheNewObjectAndReturn(node, newObject);
    }

    // Support pour les fonctions JavaScript comme constructeurs
    if (constructorValue is JSFunction) {
      // Check if this is a function that shouldn't be used as constructor
      if (constructorValue is _ArrayFromFunction) {
        throw JSTypeError('Array.from is not a constructor');
      }

      // Create nouvel objet
      final newObject = JSObject();

      // Obtenir le prototype du constructeur et l'utiliser
      final prototypeValue = constructorValue.getProperty('prototype');
      if (prototypeValue is JSObject) {
        // Configurer la chaine de prototypes correctement
        newObject.setPrototype(prototypeValue);
      }

      // Definir la propriete constructor
      newObject.setProperty('constructor', constructorValue);

      // Appeler le constructeur avec 'this' = newObject
      final function = constructorValue;
      final declaration = function.declaration;

      if (declaration != null) {
        final functionEnv = Environment(parent: function.closureEnvironment);

        // Create arguments object (array-like) for normal functions
        final argumentsObject = JSValueFactory.argumentsObject({});
        // Mark the arguments object so that callee/caller access throws
        argumentsObject.markAsArgumentsObject();
        argumentsObject.setProperty(
          'length',
          JSValueFactory.number(argumentValues.length.toDouble()),
        );
        for (int i = 0; i < argumentValues.length; i++) {
          argumentsObject.setProperty(i.toString(), argumentValues[i]);
        }
        functionEnv.define('arguments', argumentsObject, BindingType.var_);

        // Lier les parametres aux arguments
        final params = declaration.params;
        if (params != null) {
          for (int i = 0; i < params.length; i++) {
            final param = params[i];

            if (param == null) continue;

            // Gerer les rest parameters
            if (param.isRest) {
              final restArgs = <JSValue>[];
              for (int j = i; j < argumentValues.length; j++) {
                restArgs.add(argumentValues[j]);
              }
              final restArray = JSValueFactory.array(restArgs);

              if (param.name != null) {
                functionEnv.define(
                  param.name!.name,
                  restArray,
                  BindingType.parameter,
                );
              }
              break; // Rest parameter doit etre le dernier
            }

            JSValue argValue;
            if (i < argumentValues.length) {
              argValue = argumentValues[i];
            } else if (param.defaultValue != null) {
              final paramContext = ExecutionContext(
                lexicalEnvironment: functionEnv,
                variableEnvironment: functionEnv,
                thisBinding: newObject,
              );
              _executionStack.push(paramContext);
              try {
                argValue = param.defaultValue!.accept(this);
              } finally {
                _executionStack.pop();
              }
            } else {
              argValue = JSValueFactory.undefined();
            }

            // Gerer le destructuring ou les parametres simples
            if (param.isDestructuring && param.pattern != null) {
              // Destructuring parameter: {x, y} ou [a, b]
              _destructurePattern(param.pattern!, argValue, functionEnv);
            } else if (param.name != null) {
              // Simple parameter
              functionEnv.define(
                param.name!.name,
                argValue,
                BindingType.parameter,
              );
            } else {
              throw JSError(
                'Parameter $i has neither name nor pattern in constructor',
              );
            }
          }
        }

        // Creer le contexte de construction avec this = newObject
        // ES6: Class constructors are always in strict mode
        // ES6: Set new.target to the constructor being invoked
        final constructorContext = ExecutionContext(
          lexicalEnvironment: functionEnv,
          variableEnvironment: functionEnv,
          thisBinding: newObject,
          function: function,
          arguments: argumentValues,
          strictMode: true, // ES6: Class constructors are always strict
          debugName: 'Constructor ${declaration.id?.name ?? 'anonymous'}',
          newTarget: constructorValue, // ES6: new.target is the constructor
        );

        // Executer le constructeur
        _executionStack.push(constructorContext);
        try {
          declaration.body.accept(this);
          // Si le constructeur retourne un objet, l'utiliser, sinon retourner newObject
          return _cacheNewObjectAndReturn(node, newObject);
        } on FlowControlException catch (e) {
          if (e.type == ExceptionType.return_) {
            final returnValue = e.value ?? JSValueFactory.undefined();
            // Si le constructeur retourne un objet, l'utiliser
            // Note: Must check type, not Dart inheritance, since JSSymbol extends JSObject
            if (returnValue is JSObject &&
                returnValue.type == JSValueType.object) {
              return returnValue;
            }
            // For derived classes, must return undefined or an object
            if (returnValue.isUndefined) {
              return _cacheNewObjectAndReturn(node, newObject);
            }
            // Check if this is a derived class
            if (constructorValue is JSClass) {
              final jsClass = constructorValue as JSClass;
              if (jsClass.isDerivedClass) {
                // Derived class cannot return non-object values
                throw JSTypeError(
                  'Derived constructors may only return object or undefined',
                );
              }
            }
            return _cacheNewObjectAndReturn(node, newObject);
          }
          rethrow;
        } finally {
          _executionStack.pop();
        }
      }
    }

    throw JSTypeError('${constructorValue.type} is not a constructor');
  }

  @override
  JSValue visitMemberExpression(MemberExpression node) {
    // CHECK: If accessing super[...] in a constructor before super() is called, throw error
    if (node.object is SuperExpression) {
      final isInConstructor =
          _constructorStack.isNotEmpty && _constructorStack.last;
      final classContext = _currentClassContext;

      if (isInConstructor &&
          classContext != null &&
          classContext.isDerivedClass &&
          !_isSuperCalled()) {
        throw JSReferenceError(
          'must call super constructor before accessing super in derived class',
        );
      }
    }

    // Evaluer l'objet
    final objectValue = node.object.accept(this);

    // JavaScript lance TypeError pour l'acces aux proprietes sur null/undefined
    if (objectValue.isNull) {
      final propertyName = node.computed
          ? '[computed property]'
          : (node.property as IdentifierExpression).name;
      throw JSTypeError(
        "Cannot read properties of null (reading '$propertyName')",
      );
    }
    if (objectValue.isUndefined) {
      final propertyName = node.computed
          ? '[computed property]'
          : (node.property as IdentifierExpression).name;
      throw JSTypeError(
        "Cannot read properties of undefined (reading '$propertyName')",
      );
    }

    if (node.computed) {
      // Acces computed: obj[key]
      final keyValue = node.property.accept(this);

      if (objectValue is JSArray) {
        // Acces a un array par index ou propriete
        if (keyValue.isNumber) {
          final numIndex = keyValue.toNumber();

          // NaN, Infinity, and -Infinity should be treated as string properties
          // per ES6 spec: ToPropertyKey converts these to their string representations
          if (numIndex.isNaN || numIndex.isInfinite) {
            final propertyKey = numIndex.isNaN
                ? 'NaN'
                : numIndex.isNegative
                ? '-Infinity'
                : 'Infinity';
            return objectValue.getProperty(propertyKey);
          }

          final index = numIndex.floor();

          // Check if the number is actually an integer (not fractional)
          // Non-integer numbers like 1.1 should be treated as string properties
          if (numIndex != index.toDouble()) {
            return objectValue.getProperty(numIndex.toString());
          }

          // Valid array indices are 0 to 2^32-2 (4294967294)
          // Indices >= 4294967295 should be treated as regular properties
          if (index >= 0 &&
              index < 4294967295 &&
              numIndex == index.toDouble()) {
            // Use getProperty to handle accessor properties (Object.defineProperty with getter)
            return objectValue.getProperty(index.toString());
          }
          // For non-valid indices (like 4294967295), use getProperty
          return objectValue.getProperty(index.toString());
        }

        // Acces a une propriete d'array (length, push, etc.) ou symbole
        if (keyValue.isString) {
          return objectValue.getProperty(keyValue.toString());
        }

        // Handle symbol property access
        if (keyValue is JSSymbol) {
          return objectValue.getProperty(keyValue.toString());
        }

        // For other types (boolean, null, undefined), convert to string
        // e.g., arr[true] -> arr["true"]
        final propertyKey = JSConversion.jsToString(keyValue);
        return objectValue.getProperty(propertyKey);
      }

      // Support for JSObject computed access (obj["key"])
      if (objectValue is JSObject) {
        // Handle symbol property keys
        if (keyValue is JSSymbol) {
          return objectValue.getProperty(keyValue.toString());
        }

        final propertyKey = JSConversion.jsToString(keyValue);
        return objectValue.getProperty(propertyKey);
      }

      // Support for JSFunction computed access (func[key])
      // Les fonctions sont des objets en JavaScript et peuvent avoir des proprietes
      if (objectValue is JSFunction) {
        final propertyKey = JSConversion.jsToString(keyValue);
        return objectValue.getProperty(propertyKey);
      }

      // Support for JSClass computed access (Class[key])
      // Les classes peuvent avoir des proprietes statiques
      if (objectValue is JSClass) {
        final propertyKey = JSConversion.jsToString(keyValue);
        return objectValue.getProperty(propertyKey);
      }

      // Support for string computed access (str[index] or str[key])
      // En JavaScript, les strings sont des objets array-like
      if (objectValue.isString) {
        final str = objectValue.toString();

        // Acces par index numerique: str[0], str[1], etc.
        if (keyValue.isNumber) {
          final numIndex = keyValue.toNumber();

          // NaN, Infinity, and -Infinity should return undefined
          // per ES spec: ToPropertyKey converts these to string but they don't match indices
          if (numIndex.isNaN || numIndex.isInfinite) {
            return JSValueFactory.undefined();
          }

          final index = numIndex.floor();
          if (index >= 0 &&
              index < str.length &&
              numIndex == index.toDouble()) {
            return JSValueFactory.string(str[index]);
          }
          return JSValueFactory.undefined();
        }

        // Acces aux proprietes de string: str["length"], str["charAt"], etc.
        if (keyValue.isString) {
          final propertyKey = keyValue.toString();

          // Utiliser getStringProperty qui gere length et toutes les methodes
          return StringPrototype.getStringProperty(str, propertyKey);
        }

        // Handle symbol property access on strings (e.g., str[Symbol.iterator])
        if (keyValue is JSSymbol) {
          return StringPrototype.getStringProperty(str, keyValue.toString());
        }

        return JSValueFactory.undefined();
      }

      throw JSError('Member access on ${objectValue.type} not implemented yet');
    } else {
      // Acces par point: obj.prop ou obj.#privateProp
      String propName;
      bool isPrivate = false;

      if (node.property is IdentifierExpression) {
        propName = (node.property as IdentifierExpression).name;
      } else if (node.property is PrivateIdentifierExpression) {
        propName = (node.property as PrivateIdentifierExpression).name;
        isPrivate = true;
      } else {
        throw JSError('Invalid property access');
      }

      // NOUVEAU: Validation d'acces aux proprietes privees
      if (isPrivate) {
        // Determiner la classe proprietaire de la propriete privee
        JSClass? propertyOwnerClass;

        // Si l'objet est la classe elle-meme (pour les membres statiques prives)
        if (objectValue is JSClass) {
          // Acces a un membre statique prive
          if (objectValue.hasPrivateField(propName) ||
              !objectValue.hasAnyPrivateFields()) {
            propertyOwnerClass = objectValue;
          }
        }
        // Si l'objet est une instance de classe, chercher la classe qui definit cette propriete
        else if (objectValue is JSObject) {
          // Parcourir la chaine de prototypes pour trouver la classe
          JSObject? current = objectValue;
          while (current != null) {
            final constructor = current.getProperty('constructor');
            if (constructor is JSClass) {
              // Verifier si cette classe declare reellement cette propriete privee
              if (constructor.hasPrivateField(propName) ||
                  !constructor.hasAnyPrivateFields()) {
                propertyOwnerClass = constructor;
                break;
              }
            }

            // Remonter la chaine de prototypes
            current = current.getPrototype();
          }
        }

        // Verifier que l'acces se fait depuis le bon contexte de classe
        final currentClass = _currentClassContext;

        if (propertyOwnerClass == null) {
          throwJSSyntaxError('Private field \'#$propName\' is not defined');
        }

        if (currentClass == null || !_isInClassContext(propertyOwnerClass)) {
          throwJSSyntaxError(
            "Private field '#$propName' must be declared in an enclosing class",
          );
        }

        // L'acces est autorise, utiliser le nom modifie
        propName = '_private_$propName';
      }

      if (objectValue is JSArray) {
        return objectValue.getProperty(propName);
      }

      // Support for JSObject property access (console.log, etc.)
      if (objectValue is JSObject) {
        return objectValue.getProperty(propName);
      }

      // Auto-boxing pour strings
      if (objectValue is JSString) {
        return StringPrototype.getStringProperty(objectValue.value, propName);
      }

      // Auto-boxing pour string primitives
      if (objectValue.isString) {
        final str = objectValue.toString();
        return StringPrototype.getStringProperty(str, propName);
      }

      // Auto-boxing pour numbers
      if (objectValue is JSNumber) {
        return NumberPrototype.getNumberProperty(objectValue.value, propName);
      }

      // Auto-boxing pour BigInt
      if (objectValue is JSBigInt) {
        return BigIntPrototype.getBigIntProperty(objectValue.value, propName);
      }

      // Auto-boxing pour booleans
      if (objectValue is JSBoolean) {
        return BooleanPrototype.getBooleanProperty(objectValue.value, propName);
      }

      // Auto-boxing pour symbols
      if (objectValue is JSSymbol) {
        // Les symbols n'ont pas de proprietes speciales, mais toString() devrait fonctionner
        if (propName == 'toString') {
          return JSNativeFunction(
            functionName: 'toString',
            nativeImpl: (args) => JSValueFactory.string(objectValue.toString()),
          );
        }
        // Propriete description (ES2019)
        if (propName == 'description') {
          if (objectValue.description != null) {
            return JSValueFactory.string(objectValue.description!);
          } else {
            return JSValueFactory.undefined();
          }
        }
        // Methode valueOf
        if (propName == 'valueOf') {
          return JSNativeFunction(
            functionName: 'valueOf',
            nativeImpl: (args) => objectValue,
          );
        }
        // Pour les autres proprietes, retourner undefined (comme en JS)
        return JSValueFactory.undefined();
      }

      // Support for JSFunction property access (function.call, function.apply, etc.)
      if (objectValue is JSFunction) {
        // Cas special pour super.property dans les constructeurs de classes derivees
        // La fonction super est une JSNativeFunction avec le nom 'super'
        if (node.object is SuperExpression &&
            objectValue is JSNativeFunction &&
            objectValue.functionName == 'super') {
          // CHECK: In a derived class constructor, accessing super.property before super() is called should throw ReferenceError
          final isInConstructor =
              _constructorStack.isNotEmpty && _constructorStack.last;
          if (isInConstructor && !_isSuperCalled()) {
            throw JSReferenceError(
              'must call super constructor before accessing super in derived class',
            );
          }

          // Obtenir la classe parent depuis le contexte de classe actuel
          final currentClass = _currentClassContext;
          if (currentClass != null && currentClass.superClass != null) {
            final superClass = currentClass.superClass!;
            // Chercher dans le prototype de la classe parent
            final parentProto = superClass.getProperty('prototype');
            if (parentProto is JSObject) {
              final parentProperty = parentProto.getProperty(propName);
              if (parentProperty != JSValueFactory.undefined()) {
                return parentProperty;
              }
            }
          }
        }
        return objectValue.getProperty(propName);
      }

      // Support for JSClass property access (static methods, static fields, etc.)
      if (objectValue is JSClass) {
        // Cas special pour super.property dans les methodes/getters d'instance
        // On doit utiliser le this binding du contexte actuel
        if (node.object is SuperExpression) {
          final thisBinding = _currentContext().thisBinding;

          // Verifier si c'est un accessor (getter) dans le prototype de la classe elle-meme
          final descriptor = objectValue.getPrototypeAccessorDescriptor(
            propName,
          );
          if (descriptor != null && descriptor.getter != null) {
            // C'est un getter, l'appeler avec le thisBinding correct (l'instance actuelle)
            return callFunction(descriptor.getter!, [], thisBinding);
          }

          // Chercher une methode/propriete dans le prototype de CETTE classe (objectValue)
          // car objectValue EST deja la superclass
          final parentProto = objectValue.getProperty('prototype');
          if (parentProto is JSObject) {
            final parentProperty = parentProto.getProperty(propName);
            if (parentProperty != JSValueFactory.undefined()) {
              return parentProperty;
            }
          }

          // Sinon chercher dans le superClass (pour la chaine de prototypes)
          if (objectValue.superClass != null) {
            final grandparentProto = objectValue.superClass!.getProperty(
              'prototype',
            );
            if (grandparentProto is JSObject) {
              final grandparentMethod = grandparentProto.getProperty(propName);
              if (grandparentMethod != JSValueFactory.undefined()) {
                return grandparentMethod;
              }
            }
          }

          // Sinon, obtenir la propriete normalement (methode ou propriete statique)
          return objectValue.getProperty(propName);
        }

        return objectValue.getProperty(propName);
      }

      // Support pour les objets generiques
      if (objectValue is JSSymbolObject) {
        // Special handling for JSSymbolObject (wrapped Symbol)
        // For 'description', return it directly (not inherited from prototype)
        if (propName == 'description') {
          if (objectValue.primitiveValue.description != null) {
            return JSValueFactory.string(
              objectValue.primitiveValue.description!,
            );
          } else {
            return JSValueFactory.undefined();
          }
        }
        // For other properties (toString, valueOf), use the prototype
        // by delegating to JSObject.getProperty which walks the prototype chain
      }

      if (objectValue is JSObject) {
        return objectValue.getProperty(propName);
      }

      throw JSError(
        'Property access on ${objectValue.type} not implemented yet',
      );
    }
  }

  @override
  JSValue visitArrayExpression(ArrayExpression node) {
    // Evaluer tous les elements de l'array
    final elements = <JSValue>[];
    final holes = <int>[]; // Track hole indices

    for (final element in node.elements) {
      if (element == null) {
        // Element vide (sparse array) - mark as hole
        holes.add(elements.length);
        elements.add(JSValueFactory.undefined());
      } else if (element is SpreadElement) {
        // Spread element: [...array]
        // Note: When the spread argument contains a yield, we need to handle it specially
        // The yield should suspend and return its value to be spread
        JSValue spreadValue;
        try {
          spreadValue = element.argument.accept(this);
        } on GeneratorYieldException {
          // A nested yield: throw it up to let the generator handle suspension/resumption
          rethrow;
        }

        // Convertir en array iterable
        if (spreadValue is JSArray) {
          final spreadArray = spreadValue.elements;
          elements.addAll(spreadArray);
        } else if (spreadValue.isString) {
          // Les strings sont iterables caractere par caractere
          final str = spreadValue.toString();
          for (int i = 0; i < str.length; i++) {
            elements.add(JSValueFactory.string(str[i]));
          }
        } else if (spreadValue is JSObject) {
          // Verifier si l'objet est iterable (a Symbol.iterator)
          final iterator = spreadValue.getIterator();
          if (iterator != null) {
            // Consommer l'iterateur
            while (true) {
              final result = iterator.next();
              if (result is! JSObject) break;

              final done = result.getProperty('done').toBoolean();
              if (done) break;

              final value = result.getProperty('value');
              elements.add(value);
            }
          } else {
            throw JSTypeError('${spreadValue.type} is not iterable');
          }
        } else {
          throw JSTypeError('${spreadValue.type} is not iterable');
        }
      } else {
        elements.add(element.accept(this));
      }
    }

    final array = JSArray(elements);
    // Ensure array literals have Array.prototype in their prototype chain
    final arrayProto = JSArray.arrayPrototype;
    if (arrayProto != null) {
      array.setPrototype(arrayProto);
    }
    // Mark holes in the array
    for (final holeIndex in holes) {
      array.markHole(holeIndex);
    }
    return array;
  }

  @override
  JSValue visitObjectExpression(ObjectExpression node) {
    // Create nouvel objet JavaScript avec le bon prototype
    final obj = JSValueFactory.object();

    // Traiter chaque propriete
    for (final prop in node.properties) {
      if (prop is SpreadElement) {
        // Spread element: {...obj}
        JSValue spreadValue;
        try {
          spreadValue = prop.argument.accept(this);
        } on GeneratorYieldException {
          // A yield in a spread element: rethrow it up
          rethrow;
        }

        if (spreadValue.isObject) {
          final spreadObj = spreadValue.toObject();
          // Copier toutes les proprietes enumerables de l'objet spreade
          final keys = spreadObj.getPropertyNames();
          for (final key in keys) {
            final value = spreadObj.getProperty(key);
            obj.setProperty(key, value);
          }
        } else {
          throw JSTypeError('Cannot spread non-object value');
        }
        continue;
      }

      // Traitement normal des proprietes ObjectProperty
      final objectProp = prop as ObjectProperty;
      String propertyKey;
      JSSymbol? symbolKey; // ES6: Track the symbol if it's a symbol key

      if (objectProp.computed) {
        // Propriete computed: {[expression]: value}
        final keyValue = objectProp.key.accept(this);

        // ES6: Track if this is a symbol key
        if (keyValue is JSSymbol) {
          symbolKey = keyValue;
        }

        propertyKey = JSConversion.jsToString(keyValue);
      } else {
        // Propriete normale: {identifier: value} ou {"string": value}
        if (objectProp.key is IdentifierExpression) {
          propertyKey = (objectProp.key as IdentifierExpression).name;
        } else if (objectProp.key is LiteralExpression) {
          final literal = objectProp.key as LiteralExpression;
          if (literal.type == 'string') {
            propertyKey = literal.value as String;
          } else if (literal.type == 'number') {
            // Convertir les nombres en string de la meme facon que JS (sans .0)
            // Utiliser JSConversion.jsToString pour coherence avec member access
            final numValue = JSValueFactory.number(literal.value as double);
            propertyKey = JSConversion.jsToString(numValue);
          } else {
            // Convertir en string
            propertyKey = literal.value.toString();
          }
        } else {
          throw JSError('Invalid property key in object literal');
        }
      }

      // Gerer les getters et setters
      if (objectProp.kind == 'get') {
        // Getter: { get prop() { return value; } }
        // ES6 spec: Object literal getters are enumerable
        final getterFunction = objectProp.value.accept(this) as JSFunction;
        obj.defineGetter(propertyKey, getterFunction, enumerable: true);
      } else if (objectProp.kind == 'set') {
        // Setter: { set prop(value) { this._value = value; } }
        // ES6 spec: Object literal setters are enumerable
        final setterFunction = objectProp.value.accept(this) as JSFunction;
        obj.defineSetter(propertyKey, setterFunction, enumerable: true);
      } else {
        // Propriete normale: { prop: value }
        // ES2019: For method shorthand, capture source text from ObjectProperty
        if (objectProp.value is FunctionExpression) {
          final funcExpr = objectProp.value as FunctionExpression;

          // Build method shorthand syntax: methodName(params) { body }
          final paramStr = funcExpr.params
              .map((p) {
                if (p.isRest) return '...${p.name?.name ?? 'param'}';
                return p.name?.name ?? 'param';
              })
              .join(', ');
          final sourceText = '$propertyKey($paramStr) ${funcExpr.body}';

          final closureEnv = _currentEnvironment();

          if (funcExpr.id != null) {
            final funcClosureEnv = Environment(parent: closureEnv);
            final function = JSFunction(
              funcExpr,
              funcClosureEnv,
              sourceText: sourceText,
              moduleUrl: _currentModuleUrl,
            );
            funcClosureEnv.define(
              funcExpr.id!.name,
              function,
              BindingType.const_,
            );
            // ES6: Use setPropertyWithSymbol if this is a symbol key
            // ES spec: Object literals use CreateDataPropertyOrThrow
            if (symbolKey != null) {
              obj.setPropertyWithSymbol(propertyKey, function, symbolKey);
            } else {
              obj.createDataPropertyOrThrow(propertyKey, function);
            }
          } else {
            final function = JSFunction(
              funcExpr,
              closureEnv,
              sourceText: sourceText,
              moduleUrl: _currentModuleUrl,
            );
            // ES6: Use setPropertyWithSymbol if this is a symbol key
            // ES spec: Object literals use CreateDataPropertyOrThrow
            if (symbolKey != null) {
              obj.setPropertyWithSymbol(propertyKey, function, symbolKey);
            } else {
              obj.createDataPropertyOrThrow(propertyKey, function);
            }
          }
        } else {
          final propertyValue = objectProp.value.accept(this);
          // ES6: Use setPropertyWithSymbol if this is a symbol key
          // ES spec: Object literals use CreateDataPropertyOrThrow to create
          // own properties, bypassing prototype setters
          if (symbolKey != null) {
            obj.setPropertyWithSymbol(propertyKey, propertyValue, symbolKey);
          } else {
            obj.createDataPropertyOrThrow(propertyKey, propertyValue);
          }
        }
      }
    }

    return obj;
  }

  // ===== UTILITAIRES =====

  /// Retourne l'environnement courant
  Environment _currentEnvironment() {
    return _currentContext().lexicalEnvironment;
  }

  /// Retourne le contexte d'execution courant
  ExecutionContext _currentContext() {
    return _executionStack.current;
  }

  /// Definit une variable dans l'environnement global
  void setGlobalVariable(String name, JSValue value) {
    if (_globalEnvironment.hasLocal(name)) {
      _globalEnvironment.set(name, value);
    } else {
      _globalEnvironment.define(name, value, BindingType.var_);
    }
  }

  /// Recupere une variable de l'environnement global
  JSValue getGlobalVariable(String name) {
    return _globalEnvironment.get(name);
  }

  /// Verifie si une variable existe dans l'environnement global
  bool hasGlobalVariable(String name) {
    return _globalEnvironment.has(name);
  }

  /// Check if function has parameter expressions (default values)
  bool _hasParameterExpressions(List<dynamic>? parametersList) {
    if (parametersList == null) return false;
    for (final p in parametersList) {
      final param = p as Parameter;
      if (param.defaultValue != null) return true;
      if (param.isDestructuring) return true;
    }
    return false;
  }

  /// Appelle une arrow function
  JSValue _callArrowFunction(
    JSArrowFunction arrowFunc,
    List<JSValue> arguments,
  ) {
    // Verifier si c'est une async arrow function
    if (arrowFunc is JSAsyncArrowFunction) {
      return _callAsyncArrowFunction(arrowFunc, arguments);
    }

    // ES6: Check if we need separate environments for params and body
    // When hasParameterExpressions is true, closures in parameter defaults
    // should not have visibility of var declarations in the function body
    final hasParamExpressions = _hasParameterExpressions(
      arrowFunc.parametersList,
    );

    // ES6 FunctionDeclarationInstantiation:
    // When hasParameterExpressions is true (sloppy mode with parameter defaults):
    // 1. Create an "eval environment" for var declarations from eval() in param defaults
    //    This is where eval('var x = ...') will create bindings
    // 2. Create paramEnv inheriting from evalEnv for parameter bindings
    // 3. Create bodyEnv for function body

    final Environment
    evalEnv; // Environment for eval() var declarations in param defaults
    final Environment paramEnv; // Environment for parameter bindings
    final Environment bodyEnv; // Environment for function body

    if (hasParamExpressions) {
      // Create eval environment that inherits from closure
      // This is where eval('var x = ...') in param defaults will create vars
      evalEnv = Environment(parent: arrowFunc.closureEnvironment);
      // Parameter environment inherits from eval environment
      paramEnv = Environment(parent: evalEnv);
      // Body environment inherits from param environment
      bodyEnv = Environment(parent: paramEnv);
    } else {
      // Simple case: all environments are the same
      evalEnv = Environment(parent: arrowFunc.closureEnvironment);
      paramEnv = evalEnv;
      bodyEnv = evalEnv;
    }

    // Alias pour compatibilite avec code existant
    final functionEnv = paramEnv;

    // Collect all parameter names for eval() validation
    Set<String>? allParamNames;
    if (arrowFunc.parametersList != null) {
      allParamNames = <String>{};
      for (final param in arrowFunc.parametersList!) {
        if (param.name != null) {
          allParamNames.add(param.name!.name);
        } else if (param.pattern != null) {
          _collectPatternNames(param.pattern!, allParamNames);
        }
      }
    }

    // ES2019: Si on a les parametres complets (avec possibilite de destructuring)
    if (arrowFunc.parametersList != null) {
      final paramsList = arrowFunc.parametersList!;

      for (int i = 0; i < paramsList.length; i++) {
        final param = paramsList[i];

        if (param.isRest) {
          // Rest parameter: collecter les arguments restants
          final restArgs = <JSValue>[];
          for (int j = i; j < arguments.length; j++) {
            restArgs.add(arguments[j]);
          }
          final restArray = JSValueFactory.array(restArgs);

          if (param.name != null) {
            // Simple rest parameter: ...rest
            functionEnv.define(
              param.name.name,
              restArray,
              BindingType.parameter,
            );
          } else if (param.pattern != null) {
            // Rest parameter with destructuring pattern: ...[a, b = expr]
            // Need to evaluate any default values in the pattern with proper context
            final paramContext = ExecutionContext(
              lexicalEnvironment: functionEnv,
              variableEnvironment: evalEnv,
              thisBinding: arrowFunc.capturedThis ?? JSValueFactory.undefined(),
              parameterNames: allParamNames,
            );
            _executionStack.push(paramContext);
            try {
              _destructurePattern(param.pattern, restArray, functionEnv);
            } finally {
              _executionStack.pop();
            }
          }
          break; // Rest parameter doit etre le dernier
        } else if (param.isDestructuring && param.pattern != null) {
          // Destructuring parameter
          JSValue argValue;
          if (i < arguments.length) {
            argValue = arguments[i];
          } else if (param.defaultValue != null) {
            // ES6: Define parameter with undefined first, then evaluate default in function env
            // Push function environment context so default expression can access previous params
            // variableEnvironment is evalEnv so eval('var x') creates vars there
            final paramContext = ExecutionContext(
              lexicalEnvironment: functionEnv,
              variableEnvironment: evalEnv,
              thisBinding:
                  arrowFunc.capturedThis ??
                  JSValueFactory.undefined(), // Arrow functions use captured this
              parameterNames: allParamNames,
            );
            _executionStack.push(paramContext);
            try {
              argValue = param.defaultValue!.accept(this);
            } finally {
              _executionStack.pop();
            }
          } else {
            argValue = JSValueFactory.undefined();
          }
          _destructurePattern(param.pattern, argValue, functionEnv);
        } else if (param.name != null) {
          // Simple parameter with possible default value
          JSValue argValue;
          if (i < arguments.length) {
            // Argument provided
            if (arguments[i].isUndefined && param.defaultValue != null) {
              // undefined triggers default value
              // Define parameter with undefined first for next params to reference
              functionEnv.define(
                param.name.name,
                JSValueFactory.undefined(),
                BindingType.var_,
              );
              // Push function environment context so default expression can access previous params
              // variableEnvironment is evalEnv so eval('var x') creates vars there
              final paramContext = ExecutionContext(
                lexicalEnvironment: functionEnv,
                variableEnvironment: evalEnv,
                thisBinding:
                    arrowFunc.capturedThis ??
                    JSValueFactory.undefined(), // Arrow functions use captured this
                parameterNames: allParamNames,
              );
              _executionStack.push(paramContext);
              try {
                argValue = param.defaultValue!.accept(this);
              } finally {
                _executionStack.pop();
              }
            } else {
              argValue = arguments[i];
            }
          } else {
            // No argument provided
            if (param.defaultValue != null) {
              // Define parameter with undefined first
              functionEnv.define(
                param.name.name,
                JSValueFactory.undefined(),
                BindingType.var_,
              );
              // Push function environment context so default expression can access previous params
              // variableEnvironment is evalEnv so eval('var x') creates vars there
              final paramContext = ExecutionContext(
                lexicalEnvironment: functionEnv,
                variableEnvironment: evalEnv,
                thisBinding:
                    arrowFunc.capturedThis ??
                    JSValueFactory.undefined(), // Arrow functions use captured this
                parameterNames: allParamNames,
              );
              _executionStack.push(paramContext);
              try {
                argValue = param.defaultValue!.accept(this);
              } finally {
                _executionStack.pop();
              }
            } else {
              argValue = JSValueFactory.undefined();
            }
          }
          // Define or update parameter
          if (functionEnv.has(param.name.name)) {
            functionEnv.set(param.name.name, argValue);
          } else {
            functionEnv.define(
              param.name.name,
              argValue,
              BindingType.parameter,
            );
          }
        }
      }
    } else {
      // Fallback: ancienne methode avec juste les noms de parametres
      // Lier les parametres
      if (arrowFunc.hasRestParam && arrowFunc.restParamIndex >= 0) {
        // Gerer rest parameter
        for (int i = 0; i < arrowFunc.restParamIndex; i++) {
          final paramName = arrowFunc.parameters[i];
          final argValue = i < arguments.length
              ? arguments[i]
              : JSValueFactory.undefined();
          functionEnv.define(paramName, argValue, BindingType.parameter);
        }

        // Collecter les arguments restants dans un array
        final restArgs = <JSValue>[];
        for (int i = arrowFunc.restParamIndex; i < arguments.length; i++) {
          restArgs.add(arguments[i]);
        }
        final restArray = JSValueFactory.array(restArgs);
        final restParamName = arrowFunc.parameters[arrowFunc.restParamIndex];
        functionEnv.define(restParamName, restArray, BindingType.parameter);
      } else {
        // Pas de rest parameter
        for (int i = 0; i < arrowFunc.parameters.length; i++) {
          final paramName = arrowFunc.parameters[i];
          final argValue = i < arguments.length
              ? arguments[i]
              : JSValueFactory.undefined();
          functionEnv.define(paramName, argValue, BindingType.parameter);
        }
      }
    }

    // ES6: When hasParameterExpressions, hoist var declarations to bodyEnv
    // This ensures closures in parameter defaults don't see body vars
    if (hasParamExpressions && arrowFunc.body is BlockStatement) {
      _hoistVarDeclarationsToEnv(
        (arrowFunc.body as BlockStatement).body,
        bodyEnv,
      );
    }

    // Creer le contexte d'execution - use bodyEnv for body execution
    final functionContext = ExecutionContext(
      lexicalEnvironment: bodyEnv,
      variableEnvironment: bodyEnv,
      thisBinding:
          arrowFunc.capturedThis ??
          JSValueFactory.undefined(), // Arrow functions use captured this
      strictMode:
          arrowFunc.strictMode, // Inherit strict mode from arrow function
      newTarget: arrowFunc
          .capturedNewTarget, // Arrow functions inherit new.target from lexical context
    );

    // Save and set module URL from arrow function's module context
    final previousModuleUrl = _currentModuleUrl;
    _currentModuleUrl = arrowFunc.moduleUrl;

    // Push the captured class context of the arrow function
    // This allows visitThisExpression to know if we're in a null-extending class
    _arrowFunctionClassContextStack.add(arrowFunc.capturedClassContext);

    _executionStack.push(functionContext);
    try {
      if (arrowFunc.body is Expression) {
        // Arrow function avec expression: x => x * 2
        return (arrowFunc.body as Expression).accept(this);
      } else {
        // Arrow function avec block: x => { ... }
        // Block arrow functions only return a value if there's an explicit return statement
        // which throws a FlowControlException caught below
        (arrowFunc.body as Statement).accept(this);
        return JSValueFactory.undefined();
      }
    } catch (e) {
      if (e is FlowControlException && e.type == ExceptionType.return_) {
        return e.value ?? JSValueFactory.undefined();
      }
      rethrow;
    } finally {
      _executionStack.pop();
      _arrowFunctionClassContextStack
          .removeLast(); // Pop the captured class context
      _currentModuleUrl = previousModuleUrl;
    }
  }

  /// Appelle une async arrow function
  JSValue _callAsyncArrowFunction(
    JSAsyncArrowFunction arrowFunc,
    List<JSValue> arguments,
  ) {
    // Createe Promise qui sera resolue quand la fonction async se termine
    final promise = JSPromise(
      JSNativeFunction(
        functionName: 'asyncArrowResolver',
        nativeImpl: (executorArgs) {
          final resolve = executorArgs[0] as JSNativeFunction;
          final reject = executorArgs[1] as JSNativeFunction;

          // Createe tache asynchrone pour gerer l'execution
          final taskId = 'async_arrow_${DateTime.now().millisecondsSinceEpoch}';
          final asyncTask = AsyncTask(taskId);

          // Creer la continuation pour cette tache
          final continuation = AsyncArrowContinuation(
            arrowFunc,
            arguments,
            resolve,
            reject,
          );
          asyncTask.setArrowContinuation(continuation);

          // Add the task to the scheduler
          _asyncScheduler.addTask(asyncTask);

          // Start asynchronous execution
          _executeAsyncArrowFunctionWithTask(asyncTask);

          return JSValueFactory.undefined();
        },
      ),
    );

    return promise;
  }

  /// Bind parameters for async arrow function with default value support
  void _bindAsyncArrowParameters(
    JSAsyncArrowFunction arrowFunc,
    List<JSValue> arguments,
    Environment functionEnv,
  ) {
    final parametersList = arrowFunc.parametersList;

    // Collect all parameter names for eval() validation
    Set<String>? allParamNames;
    if (parametersList != null && parametersList.isNotEmpty) {
      allParamNames = <String>{};
      for (final p in parametersList) {
        final param = p as Parameter;
        if (param.name != null) {
          allParamNames.add(param.name!.name);
        } else if (param.pattern != null) {
          _collectPatternNames(param.pattern!, allParamNames);
        }
      }
    }

    // If we have detailed parameter info, use it for default values
    if (parametersList != null && parametersList.isNotEmpty) {
      // First pass: Create TDZ bindings for all parameters with default values
      // This ensures parameters cannot reference themselves or later parameters
      for (final p in parametersList) {
        final param = p as Parameter;
        if (param.name != null && !param.isRest && param.defaultValue != null) {
          functionEnv.defineUninitialized(
            param.name!.name,
            BindingType.parameter,
          );
        }
      }

      int argIndex = 0;
      for (int i = 0; i < parametersList.length; i++) {
        final param = parametersList[i] as Parameter;

        if (param.isRest) {
          // Rest parameter: collect remaining arguments
          final restArgs = <JSValue>[];
          for (int j = argIndex; j < arguments.length; j++) {
            restArgs.add(arguments[j]);
          }
          final restArray = JSValueFactory.array(restArgs);
          if (param.name != null) {
            functionEnv.define(
              param.name!.name,
              restArray,
              BindingType.parameter,
            );
          }
          break;
        } else if (param.name != null) {
          // Simple parameter with potential default value
          JSValue argValue;
          if (argIndex < arguments.length && !arguments[argIndex].isUndefined) {
            argValue = arguments[argIndex];
          } else if (param.defaultValue != null) {
            // Evaluate default value in the function environment
            // where previous parameters are already defined
            final defaultContext = ExecutionContext(
              lexicalEnvironment: functionEnv,
              variableEnvironment: functionEnv,
              thisBinding: JSValueFactory.undefined(),
              strictMode: false,
              parameterNames: allParamNames,
            );
            _executionStack.push(defaultContext);
            try {
              argValue = param.defaultValue!.accept(this);
            } finally {
              _executionStack.pop();
            }
          } else {
            argValue = argIndex < arguments.length
                ? arguments[argIndex]
                : JSValueFactory.undefined();
          }
          // Initialize the parameter (or define it if no TDZ binding exists)
          if (param.defaultValue != null) {
            functionEnv.define(
              param.name!.name,
              argValue,
              BindingType.parameter,
            );
          } else {
            functionEnv.define(
              param.name!.name,
              argValue,
              BindingType.parameter,
            );
          }
          argIndex++;
        } else if (param.isDestructuring && param.pattern != null) {
          // Destructuring parameter
          JSValue argValue;
          if (argIndex < arguments.length) {
            argValue = arguments[argIndex];
          } else if (param.defaultValue != null) {
            final defaultContext = ExecutionContext(
              lexicalEnvironment: functionEnv,
              variableEnvironment: functionEnv,
              thisBinding: JSValueFactory.undefined(),
              strictMode: false,
              parameterNames: allParamNames,
            );
            _executionStack.push(defaultContext);
            try {
              argValue = param.defaultValue!.accept(this);
            } finally {
              _executionStack.pop();
            }
          } else {
            argValue = JSValueFactory.undefined();
          }
          _destructurePattern(param.pattern!, argValue, functionEnv);
          argIndex++;
        }
      }
    } else {
      // Fallback: use simple parameter names without default values
      if (arrowFunc.hasRestParam && arrowFunc.restParamIndex >= 0) {
        for (int i = 0; i < arrowFunc.restParamIndex; i++) {
          final paramName = arrowFunc.parameters[i];
          final argValue = i < arguments.length
              ? arguments[i]
              : JSValueFactory.undefined();
          functionEnv.define(paramName, argValue, BindingType.parameter);
        }
        final restArgs = <JSValue>[];
        for (int i = arrowFunc.restParamIndex; i < arguments.length; i++) {
          restArgs.add(arguments[i]);
        }
        final restArray = JSValueFactory.array(restArgs);
        final restParamName = arrowFunc.parameters[arrowFunc.restParamIndex];
        functionEnv.define(restParamName, restArray, BindingType.parameter);
      } else {
        for (int i = 0; i < arrowFunc.parameters.length; i++) {
          final paramName = arrowFunc.parameters[i];
          final argValue = i < arguments.length
              ? arguments[i]
              : JSValueFactory.undefined();
          functionEnv.define(paramName, argValue, BindingType.parameter);
        }
      }
    }
  }

  /// Execute une async arrow function avec AsyncTask
  void _executeAsyncArrowFunctionWithTask(AsyncTask asyncTask) {
    final continuation = asyncTask.arrowContinuation;
    if (continuation == null) return;

    // Reset the awaited value index for this execution
    asyncTask.resetAwaitedValueIndex();

    final arrowFunc = continuation.arrowFunc;
    final arguments = continuation.args;
    final resolve = continuation.resolve;
    final reject = continuation.reject;

    try {
      // ES6: Check if we need separate environments for params and body
      final hasParamExpressions = _hasParameterExpressions(
        arrowFunc.parametersList,
      );

      // Create environnement pour les parametres (herite de closure)
      final paramEnv = Environment(parent: arrowFunc.closureEnvironment);

      // Create environnement pour le corps (herite de paramEnv si hasParamExpressions)
      final Environment bodyEnv;
      if (hasParamExpressions) {
        bodyEnv = Environment(parent: paramEnv);
      } else {
        bodyEnv = paramEnv;
      }

      // Bind parameters in paramEnv
      _bindAsyncArrowParameters(arrowFunc, arguments, paramEnv);

      // ES6: When hasParameterExpressions, hoist var declarations to bodyEnv
      if (hasParamExpressions && arrowFunc.body is BlockStatement) {
        _hoistVarDeclarationsToEnv(
          (arrowFunc.body as BlockStatement).body,
          bodyEnv,
        );
      }

      // Creer le contexte d'execution avec bodyEnv pour l'execution du corps
      final functionContext = ExecutionContext(
        lexicalEnvironment: bodyEnv,
        variableEnvironment: bodyEnv,
        thisBinding: JSValueFactory.undefined(),
        asyncTask: asyncTask,
      );

      // Save and set module URL from async arrow function's module context
      final previousModuleUrl = _currentModuleUrl;
      _currentModuleUrl = arrowFunc.moduleUrl;

      _executionStack.push(functionContext);

      try {
        JSValue result;
        if (arrowFunc.body is Expression) {
          // Arrow function avec expression: async x => x * 2
          result = (arrowFunc.body as Expression).accept(this);
        } else {
          // Arrow function avec block: async x => { return x * 2; }
          result = (arrowFunc.body as Statement).accept(this);
          if (result.isUndefined) {
            result = JSValueFactory.undefined();
          }
        }

        // Resoudre la Promise avec le resultat (en deroulant les Promises si necessaire)
        asyncTask.complete(result);
        _resolveAsyncReturn(result, resolve, reject);
      } catch (e) {
        if (e is AsyncSuspensionException) {
          // Fonction suspendue - elle reprendra plus tard
          return;
        } else if (e is FlowControlException &&
            e.type == ExceptionType.return_) {
          // Return statement dans la fonction async
          final returnValue = e.value ?? JSValueFactory.undefined();
          asyncTask.complete(returnValue);
          _resolveAsyncReturn(returnValue, resolve, reject);
        } else if (e is JSException) {
          // Exception JavaScript
          asyncTask.fail(e.value);
          reject.call([e.value]);
          // Executer les taches en attente apres le rejet
          _asyncScheduler.runPendingTasks(this);
        } else if (e is JSError) {
          // Convertir JSError (comme JSReferenceError) en objet Error JavaScript
          JSObject? prototype;
          try {
            final constructorName = e.name;
            final constructor = _globalEnvironment.get(constructorName);
            if (constructor is JSFunction && constructor is JSObject) {
              final proto = constructor.getProperty('prototype');
              if (proto is JSObject) {
                prototype = proto;
              }
            }
          } catch (_) {
            // Si on ne peut pas recuperer le prototype, continuer sans
          }
          final errorValue = JSErrorObjectFactory.fromDartError(e, prototype);
          asyncTask.fail(errorValue);
          reject.call([errorValue]);
          // Executer les taches en attente apres le rejet
          _asyncScheduler.runPendingTasks(this);
        } else if (e is JSValue) {
          // Autre valeur levee
          asyncTask.fail(e);
          reject.call([e]);
          // Executer les taches en attente apres le rejet
          _asyncScheduler.runPendingTasks(this);
        } else {
          // Erreur Dart
          final errorValue = JSValueFactory.string(e.toString());
          asyncTask.fail(errorValue);
          reject.call([errorValue]);
          // Executer les taches en attente apres le rejet
          _asyncScheduler.runPendingTasks(this);
        }
      } finally {
        _executionStack.pop();
        _currentModuleUrl = previousModuleUrl;
      }
    } catch (e) {
      // Erreur lors de la configuration (par exemple, TDZ errors dans les parametres)
      JSValue errorValue;
      if (e is JSException) {
        errorValue = e.value;
      } else if (e is JSError) {
        // Convertir JSError (comme JSReferenceError) en objet Error JavaScript
        JSObject? prototype;
        try {
          final constructorName = e.name;
          final constructor = _globalEnvironment.get(constructorName);
          if (constructor is JSFunction && constructor is JSObject) {
            final proto = constructor.getProperty('prototype');
            if (proto is JSObject) {
              prototype = proto;
            }
          }
        } catch (_) {
          // Si on ne peut pas recuperer le prototype, continuer sans
        }
        errorValue = JSErrorObjectFactory.fromDartError(e, prototype);
      } else if (e is JSValue) {
        errorValue = e;
      } else {
        errorValue = JSValueFactory.string(e.toString());
      }
      asyncTask.fail(errorValue);
      reject.call([errorValue]);
      // Executer les taches en attente apres le rejet
      _asyncScheduler.runPendingTasks(this);
    }
  }

  /// Appelle une bound function
  JSValue _callBoundFunction(
    JSBoundFunction boundFunc,
    List<JSValue> arguments,
  ) {
    // Combiner les arguments bound avec les nouveaux arguments
    final allArgs = [...boundFunc.boundArgs, ...arguments];

    // Appeler la fonction originale avec tous les arguments et le 'this' bound
    // IMPORTANT: L'ordre des verifications est crucial car JSNativeFunction herite de JSFunction
    if (boundFunc.originalFunction is JSBoundFunction) {
      // Si c'est une bound function imbriquee, appeler recursivement
      return _callBoundFunction(
        boundFunc.originalFunction as JSBoundFunction,
        allArgs,
      );
    } else if (boundFunc.originalFunction is JSClass) {
      // ES6: Class constructors cannot be called without 'new', even when bound
      final jsClass = boundFunc.originalFunction as JSClass;
      throw JSTypeError(
        'Class constructor ${jsClass.name} cannot be invoked without \'new\'',
      );
    } else if (boundFunc.originalFunction is JSNativeFunction) {
      // Pour les fonctions natives comme Function.prototype.call/apply/bind,
      // le thisArg de bind devient le premier argument (la fonction a appeler)
      final nativeFunc = boundFunc.originalFunction as JSNativeFunction;

      // Passer thisArg en premier suivi des autres arguments
      // C'est le comportement standard de bind avec des methodes comme call/apply
      final argsWithThis = [boundFunc.thisArg, ...allArgs];
      return nativeFunc.call(argsWithThis);
    } else if (boundFunc.originalFunction is JSArrowFunction) {
      return _callArrowFunction(
        boundFunc.originalFunction as JSArrowFunction,
        allArgs,
      );
    } else if (boundFunc.originalFunction is JSFunction) {
      final originalFunc = boundFunc.originalFunction as JSFunction;

      // Check if this is an async function - must return a Promise
      if (originalFunc.declaration is AsyncFunctionExpression) {
        // Use callFunction which handles async functions properly
        return callFunction(originalFunc, allArgs, boundFunc.thisArg);
      }

      return _callJSFunction(originalFunc, allArgs, boundFunc.thisArg);
    } else {
      throw JSError('Invalid bound function');
    }
  }

  /// Effectue un compound assignment (+=, -=, *=, etc.)
  /// Gere les operateurs d'assignation logique avec short-circuit (&&=, ||=, ??=)
  JSValue _handleLogicalAssignment(AssignmentExpression node) {
    if (node.left is IdentifierExpression) {
      final target = node.left as IdentifierExpression;
      final env = _currentEnvironment();
      final leftValue = env.get(target.name);

      JSValue finalValue;
      switch (node.operator) {
        case '&&=':
          // a &&= b => a && (a = b)
          // N'assigner que si a est truthy
          if (leftValue.isTruthy) {
            finalValue = node.right.accept(this);
            env.set(target.name, finalValue);
          } else {
            finalValue = leftValue;
          }
          break;
        case '||=':
          // a ||= b => a || (a = b)
          // N'assigner que si a est falsy
          if (!leftValue.isTruthy) {
            finalValue = node.right.accept(this);
            env.set(target.name, finalValue);
          } else {
            finalValue = leftValue;
          }
          break;
        case '??=':
          // a ??= b => a ?? (a = b)
          // N'assigner que si a est null ou undefined
          if (leftValue.type == JSValueType.nullType ||
              leftValue.type == JSValueType.undefined) {
            finalValue = node.right.accept(this);
            env.set(target.name, finalValue);
          } else {
            finalValue = leftValue;
          }
          break;
        default:
          throw JSError(
            'Unsupported logical assignment operator: ${node.operator}',
          );
      }
      return finalValue;
    } else if (node.left is MemberExpression) {
      final memberExpr = node.left as MemberExpression;
      final objectValue = memberExpr.object.accept(this);

      if (memberExpr.computed) {
        // obj[key] &&= value
        final keyValue = memberExpr.property.accept(this);

        if (objectValue is JSArray && keyValue.isNumber) {
          final index = keyValue.toNumber().floor();
          final leftValue = objectValue.get(index);

          JSValue finalValue;
          switch (node.operator) {
            case '&&=':
              if (leftValue.isTruthy) {
                finalValue = node.right.accept(this);
                objectValue.set(index, finalValue);
              } else {
                finalValue = leftValue;
              }
              break;
            case '||=':
              if (!leftValue.isTruthy) {
                finalValue = node.right.accept(this);
                objectValue.set(index, finalValue);
              } else {
                finalValue = leftValue;
              }
              break;
            case '??=':
              if (leftValue.type == JSValueType.nullType ||
                  leftValue.type == JSValueType.undefined) {
                finalValue = node.right.accept(this);
                objectValue.set(index, finalValue);
              } else {
                finalValue = leftValue;
              }
              break;
            default:
              throw JSError(
                'Unsupported logical assignment operator: ${node.operator}',
              );
          }
          return finalValue;
        }

        if (objectValue is JSObject) {
          final propertyKey = JSConversion.jsToString(keyValue);
          final leftValue = objectValue.getProperty(propertyKey);

          JSValue finalValue;
          switch (node.operator) {
            case '&&=':
              if (leftValue.isTruthy) {
                finalValue = node.right.accept(this);
                objectValue.setProperty(propertyKey, finalValue);
              } else {
                finalValue = leftValue;
              }
              break;
            case '||=':
              if (!leftValue.isTruthy) {
                finalValue = node.right.accept(this);
                objectValue.setProperty(propertyKey, finalValue);
              } else {
                finalValue = leftValue;
              }
              break;
            case '??=':
              if (leftValue.type == JSValueType.nullType ||
                  leftValue.type == JSValueType.undefined) {
                finalValue = node.right.accept(this);
                objectValue.setProperty(propertyKey, finalValue);
              } else {
                finalValue = leftValue;
              }
              break;
            default:
              throw JSError(
                'Unsupported logical assignment operator: ${node.operator}',
              );
          }
          return finalValue;
        }

        throw JSError('Logical assignment not supported for this type');
      } else {
        // obj.prop &&= value
        String propName;
        if (memberExpr.property is IdentifierExpression) {
          propName = (memberExpr.property as IdentifierExpression).name;
        } else {
          throw JSError('Invalid property access');
        }

        if (objectValue is JSObject ||
            objectValue is JSFunction ||
            objectValue is JSClass) {
          final jsObj = objectValue as dynamic;
          final leftValue = jsObj.getProperty(propName);

          JSValue? finalValue;
          switch (node.operator) {
            case '&&=':
              if (leftValue.isTruthy) {
                finalValue = node.right.accept(this);
                jsObj.setProperty(propName, finalValue);
              } else {
                finalValue = leftValue;
              }
              break;
            case '||=':
              if (!leftValue.isTruthy) {
                finalValue = node.right.accept(this);
                jsObj.setProperty(propName, finalValue);
              } else {
                finalValue = leftValue;
              }
              break;
            case '??=':
              if (leftValue.type == JSValueType.nullType ||
                  leftValue.type == JSValueType.undefined) {
                finalValue = node.right.accept(this);
                jsObj.setProperty(propName, finalValue);
              } else {
                finalValue = leftValue;
              }
              break;
          }
          return finalValue!;
        }

        throw JSError('Logical assignment not supported for this type');
      }
    }

    throw JSError('Invalid left-hand side in logical assignment');
  }

  JSValue _performCompoundAssignment(
    JSValue left,
    JSValue right,
    String operator,
  ) {
    switch (operator) {
      case '+=':
        return _addOperation(left, right);
      case '-=':
        return JSValueFactory.number(left.toNumber() - right.toNumber());
      case '*=':
        return JSValueFactory.number(left.toNumber() * right.toNumber());
      case '/=':
        return JSValueFactory.number(left.toNumber() / right.toNumber());
      case '%=':
        return JSValueFactory.number(left.toNumber() % right.toNumber());
      case '**=':
        return _performExponentiation(left, right);
      case '&=':
        return _performBitwiseAnd(left, right);
      case '|=':
        return _performBitwiseOr(left, right);
      case '^=':
        return _performBitwiseXor(left, right);
      case '<<=':
        return _performLeftShift(left, right);
      case '>>=':
        return _performRightShift(left, right);
      case '>>>=':
        return _performUnsignedRightShift(left, right);
      default:
        throw JSError('Unsupported compound assignment operator: $operator');
    }
  }

  /// Execute a function created via new Function(params, body)
  /// Parses the body code and executes it with proper strict mode and caller tracking
  JSValue executeDynamicFunction(
    DynamicFunction function,
    List<JSValue> argumentValues, [
    JSValue? thisBinding,
  ]) {
    // Parse the function body using the static parseString method
    final wrappedCode = '{\n${function.bodyCode}\n}';
    final ast = JSParser.parseString(wrappedCode);

    if (ast.body.isEmpty) {
      return JSValueFactory.undefined();
    }

    // Create a new environment for the function
    final functionEnv = Environment(parent: function.closureEnvironment);

    // Define parameters in the environment
    for (int i = 0; i < function.parameterNames.length; i++) {
      final value = i < argumentValues.length
          ? argumentValues[i]
          : JSValueFactory.undefined();
      functionEnv.define(function.parameterNames[i], value, BindingType.var_);
    }

    // Define 'arguments' object if not in strict mode
    if (!function.isStrict) {
      final argumentsObject = JSValueFactory.object({});
      argumentsObject.setProperty(
        'length',
        JSValueFactory.number(argumentValues.length.toDouble()),
      );
      for (int i = 0; i < argumentValues.length; i++) {
        argumentsObject.setProperty(i.toString(), argumentValues[i]);
      }
      functionEnv.define('arguments', argumentsObject, BindingType.var_);
    }

    // Determine 'this' binding
    final JSValue effectiveThis;
    if (thisBinding == null || thisBinding.isUndefined || thisBinding.isNull) {
      effectiveThis = function.isStrict
          ? JSValueFactory.undefined()
          : _globalThisBinding;
    } else {
      effectiveThis = thisBinding;
    }

    // Create execution context
    final functionContext = ExecutionContext(
      lexicalEnvironment: functionEnv,
      variableEnvironment: functionEnv,
      thisBinding: effectiveThis,
      strictMode: function.isStrict,
    );

    // Push function to call stack for Function.caller tracking
    pushFunctionCall(function);

    _executionStack.push(functionContext);
    try {
      // Execute the parsed block
      final block = ast.body.first;
      return block.accept(this);
    } catch (e) {
      if (e is FlowControlException && e.type == ExceptionType.return_) {
        return e.value ?? JSValueFactory.undefined();
      }
      rethrow;
    } finally {
      _executionStack.pop();
      popFunctionCall();
    }
  }

  /// Appelle une fonction JavaScript normale (methode helper)
  JSValue _callJSFunction(
    JSFunction function,
    List<JSValue> argumentValues, [
    JSValue? thisBinding,
    JSValue? newTarget,
  ]) {
    final declaration = function.declaration;

    if (declaration == null) {
      throw JSError('Cannot call function without declaration');
    }

    // Detect strict mode in function body OR if function was defined in strict mode context
    // A function is strict if:
    // 1. It has its own 'use strict' directive, OR
    // 2. It was defined in a strict mode context (function.strictMode flag)
    final hasOwnStrict =
        declaration.body?.body != null &&
        _detectStrictMode(declaration.body.body);
    final isStrictFunction = hasOwnStrict || function.strictMode;

    // Check if function has parameter expressions (non-simple parameters)
    bool hasParameterExpressions = false;
    if (declaration.params != null) {
      for (final param in declaration.params!) {
        if (param.defaultValue != null ||
            param.isDestructuring ||
            param.isRest) {
          hasParameterExpressions = true;
          break;
        }
      }
    }

    // Create nouvel environnement pour l'execution de la fonction
    // If there are parameter expressions, create a separate environment for parameter scope
    // and another for the function body (ES6 spec requirement)
    final Environment parameterEnv;
    final Environment bodyEnv;

    if (hasParameterExpressions) {
      // Create separate environments: one for parameter defaults, one for body
      // IMPORTANT: parameterEnv must be isolated from bodyEnv so functions created
      // in parameter expressions don't see function body variable declarations
      parameterEnv = Environment(
        parent: function.closureEnvironment,
        debugName: 'ParameterEnv',
      );
      bodyEnv = Environment(
        parent: function.closureEnvironment,
        debugName: 'BodyEnv',
      );
    } else {
      // No parameter expressions: use single environment for both
      parameterEnv = Environment(parent: function.closureEnvironment);
      bodyEnv = parameterEnv; // Same environment
    }

    // Create arguments object (array-like) pour les fonctions normales
    final argumentsObject = JSValueFactory.object({});
    // Mark the arguments object so that callee/caller access throws
    argumentsObject.markAsArgumentsObject();
    argumentsObject.setProperty(
      'length',
      JSValueFactory.number(argumentValues.length.toDouble()),
    );
    for (int i = 0; i < argumentValues.length; i++) {
      argumentsObject.setProperty(i.toString(), argumentValues[i]);
    }
    bodyEnv.define('arguments', argumentsObject, BindingType.var_);

    // Lier les parametres aux arguments avec support des valeurs par defaut et des parametres rest
    if (declaration.params != null) {
      int argIndex = 0; // Index dans la liste des arguments
      // Create a separate environment for parameter scope (allows defaults to reference previous params)
      final paramScopeEnv = parameterEnv;

      // Collect all parameter names for eval() validation
      final allParamNames = <String>{};
      for (final param in declaration.params!) {
        if (param.name != null) {
          allParamNames.add(param.name!.name);
        } else if (param.pattern != null) {
          _collectPatternNames(param.pattern!, allParamNames);
        }
      }

      // First pass: Create uninitialized TDZ bindings for all parameters with defaults
      // This ensures parameters cannot reference themselves in their own default values
      for (final param in declaration.params!) {
        if (param.name != null && !param.isRest && param.defaultValue != null) {
          paramScopeEnv.defineUninitialized(
            param.name!.name,
            BindingType.parameter,
          );
        }
      }

      // Process each parameter and evaluate defaults
      argIndex = 0;
      for (int i = 0; i < declaration.params!.length; i++) {
        final param = declaration.params![i];

        if (param.isRest) {
          // Parametre rest: collecter tous les arguments restants dans un tableau
          final restArgs = <JSValue>[];
          for (int j = argIndex; j < argumentValues.length; j++) {
            restArgs.add(argumentValues[j]);
          }
          final argValue = JSValueFactory.array(restArgs);

          if (param.name != null) {
            paramScopeEnv.define(
              param.name!.name,
              argValue,
              BindingType.parameter,
            );
            if (!identical(bodyEnv, paramScopeEnv)) {
              bodyEnv.define(param.name!.name, argValue, BindingType.parameter);
            }
          }
          // Les parametres rest doivent etre le dernier parametre, donc on peut sortir
          break;
        } else if (param.isDestructuring) {
          // Parametre destructuring: {x, y} ou [a, b]
          JSValue argValue;
          if (argIndex < argumentValues.length) {
            argValue = argumentValues[argIndex];
          } else if (param.defaultValue != null) {
            // ES6: Default value can reference previous parameters (but not current)
            // Evaluate default in the parameter scope environment where previous params are visible
            final defaultThis =
                thisBinding ??
                (isStrictFunction
                    ? JSValueFactory.undefined()
                    : _globalThisBinding);
            final paramContext = ExecutionContext(
              lexicalEnvironment: paramScopeEnv,
              variableEnvironment: paramScopeEnv,
              thisBinding: defaultThis,
              strictMode: isStrictFunction,
              parameterNames: allParamNames,
            );
            _executionStack.push(paramContext);
            try {
              argValue = param.defaultValue!.accept(this);
            } finally {
              _executionStack.pop();
            }
          } else {
            argValue = JSValueFactory.undefined();
          }

          if (param.pattern != null) {
            _destructurePattern(param.pattern!, argValue, paramScopeEnv);
            if (!identical(bodyEnv, paramScopeEnv)) {
              _destructurePattern(param.pattern!, argValue, bodyEnv);
            }
          }
          argIndex++;
        } else {
          // Parametre simple
          JSValue argValue;
          if (argIndex < argumentValues.length) {
            argValue = argumentValues[argIndex];
          } else if (param.defaultValue != null) {
            // ES6: Default value can reference previous parameters (but not current)
            // Evaluate default in the parameter scope environment where previous params are visible
            final defaultThis =
                thisBinding ??
                (isStrictFunction
                    ? JSValueFactory.undefined()
                    : _globalThisBinding);
            final paramContext = ExecutionContext(
              lexicalEnvironment: paramScopeEnv,
              variableEnvironment: paramScopeEnv,
              thisBinding: defaultThis,
              strictMode: isStrictFunction,
              parameterNames: allParamNames,
            );
            _executionStack.push(paramContext);
            try {
              argValue = param.defaultValue!.accept(this);
            } finally {
              _executionStack.pop();
            }
          } else {
            argValue = JSValueFactory.undefined();
          }

          if (param.name != null) {
            paramScopeEnv.define(
              param.name!.name,
              argValue,
              BindingType.parameter,
            );
            if (!identical(bodyEnv, paramScopeEnv)) {
              bodyEnv.define(param.name!.name, argValue, BindingType.parameter);
            }
          }
          argIndex++;
        }
      }
    }

    // Creer le contexte d'execution de la fonction avec le bon 'this' binding
    // In strict mode: this is undefined if not explicitly set or if explicitly undefined/null
    // In non-strict mode: undefined/null this becomes the global object
    final JSValue effectiveThis;
    if (thisBinding == null || thisBinding.isUndefined || thisBinding.isNull) {
      // No thisBinding provided, or explicitly undefined/null
      effectiveThis = isStrictFunction
          ? JSValueFactory.undefined()
          : _globalThisBinding;
    } else {
      // Explicit thisBinding provided (and not undefined/null)
      effectiveThis = thisBinding;
    }

    final functionContext = ExecutionContext(
      lexicalEnvironment: bodyEnv,
      variableEnvironment: bodyEnv,
      thisBinding: effectiveThis,
      strictMode: isStrictFunction,
      newTarget: newTarget,
    );

    // Save and set module URL from function's module context
    final previousModuleUrl = _currentModuleUrl;
    _currentModuleUrl = function.moduleUrl;

    // Push function to call stack for Function.caller tracking
    pushFunctionCall(function);

    _executionStack.push(functionContext);
    try {
      return declaration.body.accept(this);
    } catch (e) {
      if (e is FlowControlException && e.type == ExceptionType.return_) {
        return e.value ?? JSValueFactory.undefined();
      }
      rethrow;
    } finally {
      _executionStack.pop();
      popFunctionCall();
      _currentModuleUrl = previousModuleUrl;
    }
  }

  /// Methode utilitaire pour appeler une fonction JavaScript depuis des methodes natives
  JSValue callFunction(
    JSValue function,
    List<JSValue> args, [
    JSValue? thisBinding,
  ]) {
    if (function is DynamicFunction) {
      return executeDynamicFunction(function, args, thisBinding);
    }

    // Cas special pour Array.from.call(CustomConstructor, ...)
    // Nous interceptons ici pour detecter le constructeur personnalise
    if (function is _ArrayFromFunction) {
      return function.callWithCustomConstructor(
        args,
        thisBinding ?? JSValueFactory.undefined(),
        this,
      );
    }

    // For native functions, provide a default this binding
    // For JS functions, leave it null so _callJSFunction can decide based on strict mode
    final JSValue nativeThisBinding = thisBinding ?? _globalThisBinding;

    // Verifier si c'est une fonction native
    if (function is JSNativeFunction) {
      return function.callWithThis(args, nativeThisBinding);
    }

    // Verifier si c'est une arrow function
    if (function is JSArrowFunction) {
      return _callArrowFunction(function, args);
    }

    // Verifier si c'est une bound function
    if (function is JSBoundFunction) {
      return _callBoundFunction(function, args);
    }

    // Verifier si c'est une classe (pour les appels super dans les methodes statiques)
    if (function is JSClass) {
      return function.construct(args);
    }

    // Verifier si c'est une fonction async (declaree avec async ou methode async)
    if (function is JSFunction &&
        function.declaration is AsyncFunctionExpression) {
      // Createe Promise pour cette fonction async
      final asyncExpr = function.declaration as AsyncFunctionExpression;
      final promise = JSPromise(
        JSNativeFunction(
          functionName: 'asyncMethodResolver',
          nativeImpl: (executorArgs) {
            final resolve = executorArgs[0] as JSNativeFunction;
            final reject = executorArgs[1] as JSNativeFunction;

            // Creer continuation pour cette fonction async
            final continuation = AsyncContinuation(
              // Convertir AsyncFunctionExpression en AsyncFunctionDeclaration
              AsyncFunctionDeclaration(
                id: IdentifierExpression(
                  name: 'async_method',
                  line: asyncExpr.line,
                  column: asyncExpr.column,
                ),
                params: asyncExpr.params,
                body: asyncExpr.body,
                line: asyncExpr.line,
                column: asyncExpr.column,
              ),
              args,
              function.closureEnvironment,
              resolve,
              reject,
              function.moduleUrl,
              thisBinding, // Pass the 'this' binding
              function.parentClass, // Pass the parent class
            );

            final asyncTask = AsyncTask(
              'async_method_${DateTime.now().millisecondsSinceEpoch}',
            );
            asyncTask.setContinuation(continuation);

            _asyncScheduler.addTask(asyncTask);

            // Demarrer l'execution de la fonction async de maniere differee
            Future.microtask(() => _asyncScheduler.runPendingTasks(this));

            return JSValueFactory.undefined();
          },
        ),
      );
      return promise;
    }

    // Check if this is a generator function (JSFunction with FunctionExpression that has isGenerator=true)
    if (function is JSFunction && function.declaration is FunctionExpression) {
      final funcExpr = function.declaration as FunctionExpression;
      if (funcExpr.isGenerator) {
        // Create and return a generator object
        return _createGenerator(
          // Convert FunctionExpression to FunctionDeclaration
          FunctionDeclaration(
            id: IdentifierExpression(
              name: funcExpr.id?.name ?? 'generatorMethod',
              line: funcExpr.line,
              column: funcExpr.column,
            ),
            params: funcExpr.params,
            body: funcExpr.body,
            line: funcExpr.line,
            column: funcExpr.column,
            isGenerator: true,
          ),
          args,
          function.closureEnvironment,
          thisBinding,
        );
      }
    }

    // Fonction JavaScript normale
    final jsFunction = function as JSFunction;

    // NOUVEAU: Si c'est une methode de classe, pousser le contexte de classe
    final needsClassContext = jsFunction.parentClass != null;
    if (needsClassContext) {
      _pushClassContext(jsFunction.parentClass!);
    }

    final declaration = jsFunction.declaration;

    // Detect strict mode BEFORE binding parameters (for default values)
    // ES6: Class bodies are always in strict mode
    bool isStrictMode = jsFunction.parentClass != null;
    if (!isStrictMode && declaration.body is BlockStatement) {
      final blockBody = declaration.body as BlockStatement;
      isStrictMode = _detectStrictMode(blockBody.body);
    }
    // Also check if function was defined in strict mode context
    isStrictMode = isStrictMode || jsFunction.strictMode;

    // Compute effective this binding based on strict mode (needed for parameter defaults)
    // In strict mode: undefined/null this stays undefined
    // In non-strict mode: undefined/null this becomes the global object
    final JSValue effectiveThis;
    if (thisBinding == null || thisBinding.isUndefined || thisBinding.isNull) {
      effectiveThis = isStrictMode
          ? JSValueFactory.undefined()
          : _globalThisBinding;
    } else {
      effectiveThis = thisBinding;
    }

    // Check if function has parameter expressions (non-simple parameters)
    bool hasParameterExpressions = false;
    if (declaration.params != null) {
      for (final param in declaration.params!) {
        if (param.defaultValue != null ||
            param.isDestructuring ||
            param.isRest) {
          hasParameterExpressions = true;
          break;
        }
      }
    }

    // Create nouvel environnement pour l'execution de la fonction
    // If there are parameter expressions, create a separate environment for parameter scope
    // and another for the function body (ES6 spec requirement)
    final Environment parameterEnv;
    final Environment bodyEnv;

    if (hasParameterExpressions) {
      // Create separate environments: one for parameter defaults, one for body
      // IMPORTANT: parameterEnv must be isolated from bodyEnv so functions created
      // in parameter expressions don't see function body variable declarations
      parameterEnv = Environment(
        parent: jsFunction.closureEnvironment,
        debugName: 'ParameterEnv',
      );
      // bodyEnv has parameterEnv as parent - this is correct per ES6 spec
      // Closures in parameter defaults capture parameterEnv
      // Closures in body capture bodyEnv (which has var hoisting)
      bodyEnv = Environment(parent: parameterEnv, debugName: 'BodyEnv');
    } else {
      // No parameter expressions: use single environment for both
      parameterEnv = Environment(parent: jsFunction.closureEnvironment);
      bodyEnv = parameterEnv; // Same environment
    }

    final functionEnv = bodyEnv; // Use bodyEnv as the function environment

    // Lier les parametres aux arguments avec support des valeurs par defaut et des parametres rest
    if (declaration.params != null) {
      int argIndex = 0; // Index dans la liste des arguments

      for (int i = 0; i < declaration.params!.length; i++) {
        final param = declaration.params![i];

        if (param.isRest) {
          // Parametre rest: collecter tous les arguments restants dans un tableau
          final restArgs = <JSValue>[];
          for (int j = argIndex; j < args.length; j++) {
            restArgs.add(args[j]);
          }
          final argValue = JSValueFactory.array(restArgs);

          if (param.name != null) {
            parameterEnv.define(
              param.name!.name,
              argValue,
              BindingType.parameter,
            );
            // Only define in bodyEnv if it's different from parameterEnv
            if (!identical(parameterEnv, bodyEnv)) {
              bodyEnv.define(param.name!.name, argValue, BindingType.parameter);
            }
          }
          // Les parametres rest doivent etre le dernier parametre, donc on peut sortir
          break;
        } else if (param.isDestructuring) {
          // Parametre destructuring: {x, y} ou [a, b]
          JSValue argValue;
          if (argIndex < args.length) {
            argValue = args[argIndex];
          } else if (param.defaultValue != null) {
            // ES6: Default value can reference previous parameters
            // Evaluate default in the parameter scope environment
            final paramContext = ExecutionContext(
              lexicalEnvironment: parameterEnv,
              variableEnvironment: parameterEnv,
              thisBinding: effectiveThis,
            );
            _executionStack.push(paramContext);
            try {
              argValue = param.defaultValue!.accept(this);
            } finally {
              _executionStack.pop();
            }
          } else {
            argValue = JSValueFactory.undefined();
          }

          // Appliquer le destructuring dans les deux environnements
          _destructurePattern(param.pattern!, argValue, parameterEnv);
          // Only destructure in bodyEnv if it's different from parameterEnv
          if (!identical(parameterEnv, bodyEnv)) {
            _destructurePattern(param.pattern!, argValue, bodyEnv);
          }
          argIndex++;
        } else {
          // Parametre simple
          // ES6: Define parameter BEFORE evaluating next default value
          // This allows default values to reference previous parameters

          JSValue argValue;
          if (argIndex < args.length) {
            // Argument provided
            if (args[argIndex].isUndefined && param.defaultValue != null) {
              // undefined triggers default value
              // Define parameter as uninitialized (TDZ) before evaluating default
              // This ensures x = x throws ReferenceError (can't access before init)
              if (param.name != null) {
                parameterEnv.defineUninitialized(
                  param.name!.name,
                  BindingType.parameter,
                );
              }
              // Push parameter environment context so default expression can access previous params
              final paramContext = ExecutionContext(
                lexicalEnvironment: parameterEnv,
                variableEnvironment: parameterEnv,
                thisBinding: effectiveThis,
              );
              _executionStack.push(paramContext);
              try {
                argValue = param.defaultValue!.accept(this);
              } finally {
                _executionStack.pop();
              }
            } else {
              argValue = args[argIndex];
            }
          } else {
            // No argument provided, use default if exists
            if (param.defaultValue != null) {
              // Define parameter as uninitialized (TDZ) before evaluating default
              // This ensures x = x throws ReferenceError (can't access before init)
              if (param.name != null) {
                parameterEnv.defineUninitialized(
                  param.name!.name,
                  BindingType.parameter,
                );
              }
              // Push parameter environment context so default expression can access previous params
              final paramContext = ExecutionContext(
                lexicalEnvironment: parameterEnv,
                variableEnvironment: parameterEnv,
                thisBinding: effectiveThis,
              );
              _executionStack.push(paramContext);
              try {
                argValue = param.defaultValue!.accept(this);
              } finally {
                _executionStack.pop();
              }
            } else {
              argValue = JSValueFactory.undefined();
            }
          }

          // Define parameter in both parameterEnv and bodyEnv
          if (param.name != null) {
            parameterEnv.define(
              param.name!.name,
              argValue,
              BindingType.parameter,
            );
            // Only define in bodyEnv if it's different from parameterEnv
            if (!identical(parameterEnv, bodyEnv)) {
              bodyEnv.define(param.name!.name, argValue, BindingType.parameter);
            }
          }
          argIndex++; // Passer a l'argument suivant
        }
      }
    }

    // Create arguments object (array-like) pour les fonctions normales
    final argumentsObject = JSValueFactory.object({});
    // Mark the arguments object so that callee/caller access throws
    argumentsObject.markAsArgumentsObject();

    // Add a length property
    argumentsObject.setProperty(
      'length',
      JSValueFactory.number(args.length.toDouble()),
    );

    // Add each argument as an indexed property
    for (int i = 0; i < args.length; i++) {
      argumentsObject.setProperty(i.toString(), args[i]);
    }

    // Definir l'objet arguments dans l'environnement de la fonction
    functionEnv.define('arguments', argumentsObject, BindingType.var_);

    // Add 'super' to environment ONLY if this is a constructor of a class with a superclass
    // Don't add 'super' for getters, setters, or regular methods
    // isConstructor is true if:
    // 1. declaration is a MethodDefinition with kind='constructor', OR
    // 2. jsFunction has a parentClass (indicating it's a class constructor)
    final isMethodConstructor =
        declaration is MethodDefinition &&
        declaration.kind.toString() == 'MethodKind.constructor';
    // Check if this jsFunction is actually the constructor of its parent class
    final isClassConstructor =
        jsFunction.parentClass != null &&
        jsFunction.parentClass!.constructor == jsFunction;
    final isConstructor = isMethodConstructor || isClassConstructor;

    if (isConstructor &&
        jsFunction.parentClass != null &&
        thisBinding is JSObject) {
      final newObject = thisBinding;
      final evaluator = this;

      // Case 1: Native superclass (Promise, Array, etc.)
      if (jsFunction.parentClass!.superFunction != null) {
        final nativeSuperFunction = jsFunction.parentClass!.superFunction!;
        final superConstructor = JSNativeFunction(
          functionName: 'super',
          nativeImpl: (superArgs) {
            // Special handling for Array subclasses
            if (nativeSuperFunction is JSNativeFunction &&
                nativeSuperFunction.functionName == 'Array') {
              if (superArgs.isEmpty) {
                newObject.setProperty('length', JSValueFactory.number(0));
              } else if (superArgs.length == 1 && superArgs[0].isNumber) {
                final numValue = superArgs[0].toNumber();
                if (numValue.isNaN ||
                    numValue.isInfinite ||
                    numValue < 0 ||
                    numValue > 4294967295 ||
                    numValue != numValue.truncateToDouble()) {
                  throw JSRangeError('Invalid array length');
                }
                newObject.setProperty(
                  'length',
                  JSValueFactory.number(numValue),
                );
              } else {
                for (int i = 0; i < superArgs.length; i++) {
                  newObject.setProperty(i.toString(), superArgs[i]);
                }
                newObject.setProperty(
                  'length',
                  JSValueFactory.number(superArgs.length.toDouble()),
                );
              }
              return newObject;
            }

            // Special handling for Promise subclasses
            if (nativeSuperFunction is JSNativeFunction &&
                nativeSuperFunction.functionName == 'Promise') {
              if (superArgs.isEmpty) {
                throw JSTypeError('Promise constructor requires 1 argument');
              }
              final executor = superArgs[0];
              if (executor is! JSFunction) {
                throw JSTypeError('Promise executor must be a function');
              }

              // Initialize Promise internal slots on the existing object
              final promise = JSPromise.createInternal();
              newObject.setInternalSlot('[[PromiseState]]', promise);

              // Create resolve and reject functions
              final resolveFunction = JSNativeFunction(
                functionName: '',
                expectedArgs: 1,
                nativeImpl: (resolveArgs) {
                  final value = resolveArgs.isNotEmpty
                      ? resolveArgs[0]
                      : JSValueFactory.undefined();
                  promise.resolve(value);
                  return JSValueFactory.undefined();
                },
                isConstructor: false,
              );

              final rejectFunction = JSNativeFunction(
                functionName: '',
                expectedArgs: 1,
                nativeImpl: (rejectArgs) {
                  final reason = rejectArgs.isNotEmpty
                      ? rejectArgs[0]
                      : JSValueFactory.undefined();
                  promise.reject(reason);
                  return JSValueFactory.undefined();
                },
                isConstructor: false,
              );

              // Call the executor with resolve and reject
              try {
                evaluator.callFunction(executor, [
                  resolveFunction,
                  rejectFunction,
                ], JSValueFactory.undefined());
              } catch (e) {
                if (e is JSException) {
                  promise.reject(e.value);
                } else if (e is JSError) {
                  promise.reject(JSValueFactory.string(e.message));
                } else {
                  promise.reject(JSValueFactory.string(e.toString()));
                }
              }

              newObject.setInternalSlot('[[PromiseInstance]]', promise);
              return newObject;
            }

            // Default: Call the native superclass constructor with thisBinding as context
            if (nativeSuperFunction is JSNativeFunction) {
              return nativeSuperFunction.callWithThis(superArgs, thisBinding);
            } else {
              // For other function types, call via evaluator
              return callFunction(nativeSuperFunction, superArgs, thisBinding);
            }
          },
        );
        functionEnv.define('super', superConstructor, BindingType.var_);
      }
      // Case 2: JS class superclass
      else if (jsFunction.parentClass!.superClass != null) {
        final superClass = jsFunction.parentClass!.superClass!;
        final superConstructor = _createSuperFunction(superClass, thisBinding);
        functionEnv.define('super', superConstructor, BindingType.var_);
      }
    }

    // Strict mode was already detected earlier (before parameter binding)
    // En strict mode, verifier les parametres dupliques
    if (isStrictMode && declaration.params != null) {
      final paramNames = <String>{};
      for (final param in declaration.params!) {
        if (param.name != null) {
          final paramName = param.name!.name;
          if (paramNames.contains(paramName)) {
            throw JSSyntaxError(
              'Duplicate parameter name not allowed in strict mode: $paramName',
            );
          }
          paramNames.add(paramName);
        }
      }
    }

    // ES6: When hasParameterExpressions, hoist var declarations to bodyEnv
    // This ensures closures in parameter defaults don't see body vars
    if (hasParameterExpressions && declaration.body is BlockStatement) {
      _hoistVarDeclarationsToEnv(
        (declaration.body as BlockStatement).body,
        bodyEnv,
      );
    }

    // Create contexte d'execution pour la fonction (effectiveThis was computed earlier)
    final functionContext = ExecutionContext(
      lexicalEnvironment: functionEnv,
      variableEnvironment: functionEnv,
      thisBinding: effectiveThis,
      function: jsFunction,
      arguments: args,
      strictMode: isStrictMode,
      debugName: 'Function ${declaration.id?.name ?? 'anonymous'}',
      asyncTask: _executionStack
          .current
          .asyncTask, // Propager l.AsyncTask du contexte parent
    );

    _executionStack.push(functionContext);
    // Track if we're in a constructor
    _constructorStack.add(isConstructor);
    try {
      return declaration.body.accept(this);
    } catch (e) {
      if (e is FlowControlException && e.type == ExceptionType.return_) {
        return e.value ?? JSValueFactory.undefined();
      }
      rethrow;
    } finally {
      if (needsClassContext) {
        _popClassContext(); // NOUVEAU: Pop du contexte de classe
      }
      _constructorStack.removeLast();
      _executionStack.pop();
    }
  }

  /// ES2022: Execute a static initialization block in the context of a class
  /// Static blocks are executed when the class is defined, with 'this' bound to the class
  void executeStaticBlock(BlockStatement block, JSClass classValue) {
    // Create a new environment for the static block with the class's closure environment
    final blockEnv = Environment(parent: classValue.closureEnvironment);

    // Push the class context so 'this' references work correctly
    _pushClassContext(classValue);

    // Push execution context with the class as 'this'
    _executionStack.push(
      ExecutionContext(
        lexicalEnvironment: blockEnv,
        variableEnvironment: blockEnv,
        thisBinding: classValue,
        strictMode: false,
        debugName: 'StaticBlock(${classValue.name})',
      ),
    );

    try {
      // Execute each statement in the static block
      for (final statement in block.body) {
        statement.accept(this);
      }
    } finally {
      _popClassContext();
      _executionStack.pop();
    }
  }

  // ===== DESTRUCTURING PATTERNS =====

  @override
  JSValue visitIdentifierPattern(IdentifierPattern node) {
    // Cette methode ne devrait pas etre appelee directement
    // Les patterns sont traites dans le contexte d'un assignment
    throw JSError('IdentifierPattern should not be visited directly');
  }

  @override
  JSValue visitAssignmentPattern(AssignmentPattern node) {
    // Cette methode ne devrait pas etre appelee directement
    // Les patterns sont traites dans le contexte d'un assignment
    throw JSError('AssignmentPattern should not be visited directly');
  }

  @override
  JSValue visitArrayPattern(ArrayPattern node) {
    // Cette methode ne devrait pas etre appelee directement
    // Les patterns sont traites dans le contexte d'un assignment
    throw JSError('ArrayPattern should not be visited directly');
  }

  @override
  JSValue visitObjectPattern(ObjectPattern node) {
    // Cette methode ne devrait pas etre appelee directement
    // Les patterns sont traites dans le contexte d'un assignment
    throw JSError('ObjectPattern should not be visited directly');
  }

  @override
  JSValue visitObjectPatternProperty(ObjectPatternProperty node) {
    // Cette methode ne devrait pas etre appelee directement
    // Les patterns sont traites dans le contexte d'un assignment
    throw JSError('ObjectPatternProperty should not be visited directly');
  }

  @override
  JSValue visitExpressionPattern(ExpressionPattern node) {
    // Cette methode ne devrait pas etre appelee directement
    // Les patterns sont traites dans le contexte d'un assignment
    throw JSError('ExpressionPattern should not be visited directly');
  }

  @override
  JSValue visitDestructuringAssignmentExpression(
    DestructuringAssignmentExpression node,
  ) {
    final value = node.right.accept(this);
    _assignToPattern(node.left, value);
    return value;
  }

  /// Assigne une valeur a un pattern de destructuring
  void _assignToPattern(Pattern pattern, JSValue value) {
    switch (pattern) {
      case IdentifierPattern identifierPattern:
        _assignToIdentifier(identifierPattern.name, value);
        break;

      case AssignmentPattern assignmentPattern:
        // Si la valeur est undefined, utiliser la default value
        final actualValue = value.isUndefined
            ? assignmentPattern.right.accept(this)
            : value;
        _assignToPattern(assignmentPattern.left, actualValue);
        break;

      case ArrayPattern arrayPattern:
        _assignToArrayPattern(arrayPattern, value);
        break;

      case ObjectPattern objectPattern:
        _assignToObjectPattern(objectPattern, value);
        break;

      case ExpressionPattern expressionPattern:
        // Evaluer l'expression pour obtenir la cible d'assignement
        // L'expression doit etre une MemberExpression ou autre expression assignable
        final targetExpr = expressionPattern.expression;

        // Createe assignation temporaire pour evaluer a la cible
        if (targetExpr is IdentifierExpression) {
          // Cas simple: identifier
          _assignToIdentifier(targetExpr.name, value);
        } else if (targetExpr is MemberExpression) {
          // Cas complexe: property access (obj.prop ou obj['key'])
          _assignToMemberExpression(targetExpr, value);
        } else {
          throw JSError(
            'Invalid target in rest pattern: ${targetExpr.runtimeType}',
          );
        }
        break;

      default:
        throw JSError('Unknown pattern type: ${pattern.runtimeType}');
    }
  }

  /// Assigne une valeur a un identifiant
  void _assignToIdentifier(String name, JSValue value) {
    final env = _currentEnvironment();

    // En mode non-strict, creer la variable si elle n'existe pas
    if (!env.has(name)) {
      env.define(name, value, BindingType.var_);
    } else {
      env.set(name, value);
    }
  }

  /// Assigne une valeur a une member expression (obj.prop ou obj[key])
  void _assignToMemberExpression(MemberExpression memberExpr, JSValue value) {
    final obj = memberExpr.object.accept(this);

    // Functions and objects can have properties assigned
    if (!(obj is JSObject || obj is JSFunction)) {
      throw JSTypeError('Cannot set property on non-object');
    }

    final propName = memberExpr.computed
        ? JSConversion.jsToString(memberExpr.property.accept(this))
        : (memberExpr.property as IdentifierExpression).name;

    if (obj is JSObject) {
      obj.setProperty(propName, value);
    } else if (obj is JSFunction) {
      obj.setProperty(propName, value);
    }
  }

  /// Recupere Symbol.iterator d'une valeur
  JSValue? _getSymbolIterator(JSValue value) {
    if (value is! JSObject) {
      return null;
    }

    final obj = value;

    // Recuperer Symbol.iterator (bien-connu symbol)
    final symbolIteratorKey = JSSymbol.iterator.toString();

    // D'abord chercher directement dans l'objet
    if (obj.hasProperty(symbolIteratorKey)) {
      return obj.getProperty(symbolIteratorKey);
    }

    // Chercher dans la chaine de prototypes
    // Access prototype chain by getting __proto__ property
    JSValue? current = obj.getProperty('__proto__');
    while (current != null && current.type == JSValueType.object) {
      final currentObj = current as JSObject;
      if (currentObj.hasProperty(symbolIteratorKey)) {
        return currentObj.getProperty(symbolIteratorKey);
      }
      current = currentObj.getProperty('__proto__');
    }

    return null;
  }

  /// Recupere les elements d'une valeur iterable en utilisant le protocole d'iteration
  List<JSValue> _getElementsFromIterator(JSValue value) {
    // Etape 1: Obtenir Symbol.iterator
    final iteratorFn = _getSymbolIterator(value);
    if (iteratorFn == null || iteratorFn.type != JSValueType.function) {
      throw JSTypeError('${_getValueDescription(value)} is not iterable');
    }

    // Etape 2: Appeler Symbol.iterator pour obtenir l'iterateur
    JSValue iterator;
    try {
      iterator = callFunction(iteratorFn, [], value);
    } catch (e) {
      rethrow;
    }

    // Verifier que l'iterateur est un objet
    if (iterator.type != JSValueType.object) {
      throw JSTypeError('Iterator must be an object');
    }

    final iteratorObj = iterator as JSObject;
    final nextMethod = iteratorObj.getProperty('next');
    if (nextMethod.type != JSValueType.function) {
      throw JSTypeError('Iterator missing next() method');
    }

    // Etape 3: Iterer et collecter les elements
    final elements = <JSValue>[];
    try {
      while (true) {
        // Appeler iterator.next()
        final result = callFunction(nextMethod, [], iterator);

        if (result.type != JSValueType.object) {
          throw JSTypeError('Iterator next() must return an object');
        }

        final resultObj = result as JSObject;

        // Verifier la propriete 'done'
        final done = resultObj.getProperty('done');
        final doneValue = done.toBoolean();

        if (doneValue) {
          break;
        }

        // Recuperer la propriete 'value'
        final valueResult = resultObj.getProperty('value');
        elements.add(valueResult);
      }
    } catch (e) {
      // IteratorClose: appeler iterator.return() s'il existe
      try {
        final returnMethod = iteratorObj.getProperty('return');
        if (returnMethod.type == JSValueType.function) {
          callFunction(returnMethod, [], iterator);
        }
      } catch (closeError) {
        // Ignorer les erreurs lors du nettoyage de l'iterateur
      }
      rethrow;
    }

    return elements;
  }

  /// Assigne une valeur a un pattern d'array ([a, b, ...rest] = arr)
  void _assignToArrayPattern(ArrayPattern pattern, JSValue value) {
    // Convertir la valeur en array si ce n'est pas deja fait
    final List<JSValue> elements;

    if (value.type == JSValueType.string) {
      // Supporter la destructuring des strings
      final str = value.primitiveValue as String;
      elements = str
          .split('')
          .map((char) => JSValueFactory.string(char))
          .toList();
    } else if (value is JSArray) {
      elements = value.elements;
    } else if (value is JSObject) {
      // Try iterator protocol for other objects
      elements = _getElementsFromIterator(value);
    } else {
      throw JSTypeError('${_getValueDescription(value)} is not iterable');
    }

    // Assigner chaque element du pattern
    for (int i = 0; i < pattern.elements.length; i++) {
      final patternElement = pattern.elements[i];
      if (patternElement != null) {
        final elementValue = i < elements.length
            ? elements[i]
            : JSValueFactory.undefined();
        _assignToPattern(patternElement, elementValue);
      }
    }

    // Gerer le rest element si present
    if (pattern.restElement != null) {
      final restElements = elements.skip(pattern.elements.length).toList();
      final restArray = JSArray(restElements);
      _assignToPattern(pattern.restElement!, restArray);
    }
  }

  /// Assigne une valeur a un pattern d'objet ({a, b: newName, ...rest} = obj)
  void _assignToObjectPattern(ObjectPattern pattern, JSValue value) {
    if (value.type != JSValueType.object) {
      throw JSTypeError('Cannot destructure non-object value');
    }

    final obj = value as JSObject;
    final assignedKeys = <String>{}; // Pour le rest element

    // Assigner chaque propriete du pattern
    for (final property in pattern.properties) {
      final key = property.key;
      assignedKeys.add(key);

      final propValue = obj.hasProperty(key)
          ? obj.getProperty(key)
          : (property.defaultValue?.accept(this) ?? JSValueFactory.undefined());

      _assignToPattern(property.value, propValue);
    }

    // Gerer le rest element si present
    if (pattern.restElement != null) {
      final restObj = JSObject();

      // Copier toutes les proprietes non assignees (enumerable only)
      // Rest element should only include enumerable properties per ES2017
      for (final key in obj.getPropertyNames(enumerableOnly: true)) {
        if (!assignedKeys.contains(key)) {
          restObj.setProperty(key, obj.getProperty(key));
        }
      }

      _assignToPattern(pattern.restElement!, restObj);
    }
  }

  /// Obtient une description lisible d'une valeur JavaScript pour les messages d'erreurs
  String _getValueDescription(JSValue value) {
    switch (value.type) {
      case JSValueType.undefined:
        return 'undefined';
      case JSValueType.nullType:
        return 'null';
      case JSValueType.boolean:
        return value.primitiveValue.toString();
      case JSValueType.number:
        final num = value.primitiveValue as double;
        if (num == num.roundToDouble()) {
          return num.toInt().toString();
        }
        return num.toString();
      case JSValueType.string:
        return '"${value.primitiveValue}"';
      case JSValueType.object:
        if (value is JSArray) {
          return '[object Array]';
        }
        // For other objects, just return a generic description
        // Don't try to format them with toMap() as that can fail with function properties
        return '[object Object]';
      case JSValueType.function:
        return 'function';
      default:
        return value.toString();
    }
  }

  /// Evalue une expression avec optional chaining (?.)
  @override
  JSValue visitOptionalChainingExpression(OptionalChainingExpression node) {
    final object = node.object.accept(this);

    // Si l'objet est null ou undefined, retourner undefined immediatement
    if (object.type == JSValueType.nullType ||
        object.type == JSValueType.undefined) {
      return JSValueFactory.undefined();
    }

    // Si c'est un appel de fonction avec optional chaining
    if (node.isCall && node.property is CallExpression) {
      final callExpr = node.property as CallExpression;

      // Pour obj?.method(), nous avons :
      // OptionalChainingExpression(
      //   object: obj,
      //   property: CallExpression(callee: method_name, arguments: [...]),
      //   isCall: true
      // )

      // Pour func?.(), nous avons :
      // OptionalChainingExpression(
      //   object: func_expression,
      //   property: CallExpression(callee: __optionalCallMarker__, arguments: [...]),
      //   isCall: true
      // )
      // Le marqueur __optionalCallMarker__ indique que nous devons appeler directement l'object

      // Evaluer les arguments
      final arguments = <JSValue>[];
      for (final arg in callExpr.arguments) {
        arguments.add(arg.accept(this));
      }

      // Verifier si c'est un appel direct (avec le marqueur) ou un appel de methode
      if (callExpr.callee is IdentifierExpression &&
          (callExpr.callee as IdentifierExpression).name ==
              '__optionalCallMarker__') {
        // Cas: func?.() ou func est l'objet evalue
        if (object.type == JSValueType.function) {
          return callFunction(object as JSFunction, arguments, null);
        } else if (object.type == JSValueType.undefined) {
          return JSValueFactory.undefined();
        } else {
          throw JSError('${object.type} is not a function');
        }
      } else if (callExpr.callee is IdentifierExpression) {
        // Cas: obj?.method()
        final methodName = (callExpr.callee as IdentifierExpression).name;

        // Obtenir la methode de l'objet
        if (object is JSObject) {
          final method = object.getProperty(methodName);
          if (method.type == JSValueType.function) {
            return callFunction(method as JSFunction, arguments, object);
          } else if (method.type == JSValueType.undefined) {
            return JSValueFactory.undefined();
          } else {
            throw JSError('Property $methodName is not a function');
          }
        } else {
          throw JSError('Cannot read property $methodName of ${object.type}');
        }
      } else {
        // Cas: func?.() ou func est une expression complexe (evaluee dans object)
        if (object.type == JSValueType.function) {
          return callFunction(object as JSFunction, arguments, null);
        } else if (object.type == JSValueType.undefined) {
          return JSValueFactory.undefined();
        } else {
          throw JSError('${callExpr.callee} is not a function');
        }
      }
    }

    // Sinon, c'est un acces a une propriete avec optional chaining
    // Traiter node.property comme un acces a une propriete sur l'objet
    if (node.property is IdentifierExpression) {
      // Cas: obj?.prop
      final propName = (node.property as IdentifierExpression).name;
      if (object is JSObject) {
        return object.getProperty(propName);
      } else if (object is JSArray) {
        return object.getProperty(propName);
      } else if (object is JSString) {
        return StringPrototype.getStringProperty(object.value, propName);
      } else if (object.isString) {
        // Support pour string primitives
        final str = object.toString();
        return StringPrototype.getStringProperty(str, propName);
      } else if (object is JSNumber) {
        return NumberPrototype.getNumberProperty(object.value, propName);
      } else if (object is JSBigInt) {
        return BigIntPrototype.getBigIntProperty(object.value, propName);
      } else if (object is JSBoolean) {
        return BooleanPrototype.getBooleanProperty(object.value, propName);
      } else {
        throw JSError('Property access on ${object.type} not implemented yet');
      }
    } else if (node.property is MemberExpression) {
      // Cas comme obj?.prop.subprop (pour les chaines plus complexes)
      final memberExpr = node.property as MemberExpression;

      // Create nouvel objet temporaire pour l'acces a la propriete
      JSValue currentObject = object;

      if (memberExpr.computed) {
        // obj?.[key] dans une chaine plus complexe
        final keyValue = memberExpr.property.accept(this);
        if (currentObject is JSObject) {
          final propertyKey = JSConversion.jsToString(keyValue);
          return currentObject.getProperty(propertyKey);
        } else if (currentObject is JSArray) {
          if (keyValue.isNumber) {
            final index = keyValue.toNumber().floor();
            return currentObject.get(index);
          } else if (keyValue.isString) {
            return currentObject.getProperty(keyValue.toString());
          } else {
            return JSValueFactory.undefined();
          }
        } else if (currentObject.isString) {
          // Support pour string primitives en optional chaining
          final str = currentObject.toString();
          if (keyValue.isNumber) {
            final index = keyValue.toNumber().floor();
            if (index >= 0 && index < str.length) {
              return JSValueFactory.string(str[index]);
            }
            return JSValueFactory.undefined();
          } else if (keyValue.isString) {
            return StringPrototype.getStringProperty(str, keyValue.toString());
          } else if (keyValue is JSSymbol) {
            // Support pour Symbol keys sur strings (comme Symbol.iterator)
            return StringPrototype.getStringProperty(str, keyValue.toString());
          } else {
            return JSValueFactory.undefined();
          }
        } else {
          throw JSError(
            'Member access on ${currentObject.type} not implemented yet',
          );
        }
      } else {
        // obj?.prop dans une chaine plus complexe
        final propName = (memberExpr.property as IdentifierExpression).name;
        if (currentObject is JSObject) {
          return currentObject.getProperty(propName);
        } else if (currentObject is JSArray) {
          return currentObject.getProperty(propName);
        } else if (currentObject.isString) {
          // Support pour string primitives en optional chaining
          final str = currentObject.toString();
          return StringPrototype.getStringProperty(str, propName);
        } else {
          throw JSError(
            'Property access on ${currentObject.type} not implemented yet',
          );
        }
      }
    } else {
      // Pour les autres types d'expressions (ex: computed property direct: obj?.[expr])
      // Evaluer l'expression pour obtenir la cle
      final keyValue = node.property.accept(this);

      // Utiliser cette cle pour acceder a la propriete
      if (object is JSArray) {
        if (keyValue.isNumber) {
          final index = keyValue.toNumber().floor();
          return object.get(index);
        } else if (keyValue.isString) {
          return object.getProperty(keyValue.toString());
        } else {
          return JSValueFactory.undefined();
        }
      } else if (object is JSObject) {
        final propertyKey = JSConversion.jsToString(keyValue);
        return object.getProperty(propertyKey);
      } else if (object is JSString) {
        if (keyValue.isNumber) {
          final index = keyValue.toNumber().floor();
          if (index >= 0 && index < object.value.length) {
            return JSValueFactory.string(object.value[index]);
          }
          return JSValueFactory.undefined();
        } else {
          final propertyKey = JSConversion.jsToString(keyValue);
          return StringPrototype.getStringProperty(object.value, propertyKey);
        }
      } else {
        throw JSError('Property access on ${object.type} not implemented yet');
      }
    }
  }

  /// Evalue une expression avec nullish coalescing (??)
  @override
  JSValue visitNullishCoalescingExpression(NullishCoalescingExpression node) {
    final left = node.left.accept(this);

    // Si la valeur de gauche n'est pas null ou undefined, retourner cette valeur
    if (left.type != JSValueType.nullType &&
        left.type != JSValueType.undefined) {
      return left;
    }

    // Sinon, evaluer et retourner la valeur de droite
    return node.right.accept(this);
  }

  /// Destructure un pattern et lie les variables dans l'environnement
  /// Utilise pour les parametres de fonctions avec destructuring: function foo({x, y}) {}
  void _destructurePattern(Pattern pattern, JSValue value, Environment env) {
    if (pattern is IdentifierPattern) {
      // Simple identifier: x
      env.define(pattern.name, value, BindingType.parameter);
    } else if (pattern is AssignmentPattern) {
      // Pattern with default value: a = 10
      if (value.isUndefined) {
        // Set target binding name context before evaluating the initializer
        // This enables ES6 anonymous function name inference:
        // [fn = function() {}] => fn.name should be 'fn', not 'anonymous'
        String? previousTarget = _targetBindingNameForFunction;
        try {
          // If left side is an identifier, use it as the target name
          if (pattern.left is IdentifierPattern) {
            _targetBindingNameForFunction =
                (pattern.left as IdentifierPattern).name;
          }
          final actualValue = pattern.right.accept(this);
          _destructurePattern(pattern.left, actualValue, env);
        } finally {
          // Restore previous context
          _targetBindingNameForFunction = previousTarget;
        }
      } else {
        _destructurePattern(pattern.left, value, env);
      }
    } else if (pattern is ObjectPattern) {
      // Object destructuring: {x, y} ou {x: a, y: b}
      final obj = value.toObject();

      for (final prop in pattern.properties) {
        // Obtenir la valeur de la propriete
        JSValue propValue = obj.getProperty(prop.key);

        // Appliquer la valeur par defaut si necessaire
        if (propValue.isUndefined && prop.defaultValue != null) {
          propValue = prop.defaultValue!.accept(this);
        }

        // Recursivement destructurer si necessaire
        _destructurePattern(prop.value, propValue, env);
      }

      // Gerer le rest element si present: {...rest}
      if (pattern.restElement != null) {
        final restObj = JSValueFactory.object({});
        final extractedKeys = pattern.properties.map((p) => p.key).toSet();

        // Only include enumerable properties in rest element per ES2017
        for (final key in obj.getPropertyNames(enumerableOnly: true)) {
          if (!extractedKeys.contains(key)) {
            restObj.setProperty(key, obj.getProperty(key));
          }
        }

        _destructurePattern(pattern.restElement!, restObj, env);
      }
    } else if (pattern is ArrayPattern) {
      // Array destructuring: [a, b] ou [a, ...rest]
      // Handle both arrays and iterables (generators, etc.)

      if (value is JSArray) {
        // For regular arrays, use direct access
        int index = 0;
        for (final element in pattern.elements) {
          if (element == null) {
            // Hole in array: [a, , c]
            index++;
            continue;
          }

          JSValue elemValue;
          if (index < value.length) {
            elemValue = value.get(index);
          } else {
            elemValue = JSValueFactory.undefined();
          }

          _destructurePattern(element, elemValue, env);
          index++;
        }

        // Handle rest element if present: [...rest]
        if (pattern.restElement != null) {
          final restArray = <JSValue>[];
          for (int i = index; i < value.length; i++) {
            restArray.add(value.get(i));
          }
          _destructurePattern(
            pattern.restElement!,
            JSValueFactory.array(restArray),
            env,
          );
        }
      } else if (value is JSGenerator) {
        // For generators, iterate on demand - only consuming what we need
        for (final element in pattern.elements) {
          if (element == null) {
            // Hole in array: [a, , c] - consume one value but skip destructuring
            final next = value.next(JSValueFactory.undefined());
            if (next is JSObject) {
              final done = next.getProperty('done');
              if (done.isTruthy) {
                break;
              }
            }
            continue;
          }

          // Get next value from generator
          JSValue elemValue = JSValueFactory.undefined();
          final next = value.next(JSValueFactory.undefined());
          if (next is JSObject) {
            final done = next.getProperty('done');
            if (!done.isTruthy) {
              elemValue = next.getProperty('value');
            }
          }

          _destructurePattern(element, elemValue, env);
        }

        // Handle rest element if present: [...rest]
        if (pattern.restElement != null) {
          final restArray = <JSValue>[];
          while (true) {
            final next = value.next(JSValueFactory.undefined());
            if (next is JSObject) {
              final done = next.getProperty('done');
              if (done.isTruthy) break;
              restArray.add(next.getProperty('value'));
            } else {
              break;
            }
          }
          _destructurePattern(
            pattern.restElement!,
            JSValueFactory.array(restArray),
            env,
          );
        }
      } else if (_isIterable(value)) {
        // For other iterables (strings, objects with Symbol.iterator), use iterator protocol
        JSArray arr = _iterableToArray(value);
        int index = 0;
        for (final element in pattern.elements) {
          if (element == null) {
            index++;
            continue;
          }

          JSValue elemValue;
          if (index < arr.length) {
            elemValue = arr.get(index);
          } else {
            elemValue = JSValueFactory.undefined();
          }

          _destructurePattern(element, elemValue, env);
          index++;
        }

        if (pattern.restElement != null) {
          final restArray = <JSValue>[];
          for (int i = index; i < arr.length; i++) {
            restArray.add(arr.get(i));
          }
          _destructurePattern(
            pattern.restElement!,
            JSValueFactory.array(restArray),
            env,
          );
        }
      } else {
        // For non-iterables, try to convert to array
        JSArray arr = _iterableToArray(value);
        int index = 0;
        for (final element in pattern.elements) {
          if (element == null) {
            index++;
            continue;
          }

          JSValue elemValue;
          if (index < arr.length) {
            elemValue = arr.get(index);
          } else {
            elemValue = JSValueFactory.undefined();
          }

          _destructurePattern(element, elemValue, env);
          index++;
        }

        if (pattern.restElement != null) {
          final restArray = <JSValue>[];
          for (int i = index; i < arr.length; i++) {
            restArray.add(arr.get(i));
          }
          _destructurePattern(
            pattern.restElement!,
            JSValueFactory.array(restArray),
            env,
          );
        }
      }
    }
  }

  /// Check if a value is iterable (has Symbol.iterator or is array-like)
  bool _isIterable(JSValue value) {
    if (value is JSArray) return true;
    if (value is JSGenerator) return true;
    if (value is JSString) return true; // Strings are iterable

    // Check for Symbol.iterator method
    if (value is JSObject) {
      final iterator = value.getProperty('Symbol.iterator');
      return iterator is JSFunction;
    }

    return false;
  }

  /// Convert an iterable value to a JSArray
  JSArray _iterableToArray(JSValue value) {
    if (value is JSArray) {
      return value;
    }
    if (value is JSString) {
      // String to array of characters
      final chars = <JSValue>[];
      for (int i = 0; i < value.value.length; i++) {
        chars.add(JSValueFactory.string(value.value[i]));
      }
      return JSValueFactory.array(chars);
    }

    // Null and undefined are not iterable
    if (value is JSNull || value is JSUndefined) {
      throw JSTypeError('Cannot destructure ${value.type} value');
    }

    // For generators and other iterables, we need to iterate
    if (value is JSGenerator) {
      final result = <JSValue>[];
      while (true) {
        final next = value.next(JSValueFactory.undefined());
        if (next is JSObject) {
          final done = next.getProperty('done');
          if (done.isTruthy) break;
          final val = next.getProperty('value');
          result.add(val);
        } else {
          break;
        }
      }
      return JSValueFactory.array(result);
    }

    // For objects with Symbol.iterator, would need full iterator protocol
    if (value is JSObject) {
      // Return empty array for non-iterable objects
      return JSValueFactory.array([]);
    }

    // For primitives like numbers, booleans, they are not iterable
    throw JSTypeError('Cannot destructure ${value.type} value');
  }
}

/// Classe specialisee pour Array.from qui gere .call(CustomConstructor, ...)
/// Cette classe intercepte l'appel pour detecter le constructeur personnalise
class _ArrayFromFunction extends JSFunction {
  // Mark this function as non-constructor (cannot be called with 'new')

  _ArrayFromFunction() : super(null, null) {
    // Set proper property descriptors for 'length' and 'name'
    defineProperty(
      'length',
      PropertyDescriptor(
        value: JSValueFactory.number(1),
        writable: false,
        enumerable: false,
        configurable: true,
      ),
    );
    defineProperty(
      'name',
      PropertyDescriptor(
        value: JSValueFactory.string('from'),
        writable: false,
        enumerable: false,
        configurable: true,
      ),
    );
  }

  // Override isConstructor to return false - Array.from is not a constructor
  @override
  bool get isConstructor => false;

  @override
  String toString() => 'function from() { [native code] }';

  @override
  JSValue getProperty(String name) {
    // For built-in 'length' and 'name', first check if they were explicitly deleted
    // by seeing if they're in the property descriptors
    final desc = getOwnPropertyDescriptor(name);

    if (name == 'name' && desc == null) {
      // Property was deleted
      return JSValueFactory.undefined();
    }
    if (name == 'length' && desc == null) {
      // Property was deleted
      return JSValueFactory.undefined();
    }

    // Return inherited getProperty behavior which will check descriptors/properties
    return super.getProperty(name);
  }

  /// Appelle Array.from avec potentiel detection du constructeur personnalise
  /// Cette methode doit etre appelee avec callFunctionInternal ou callWithThis
  JSValue callWithCustomConstructor(
    List<JSValue> args,
    JSValue thisBinding,
    JSEvaluator evaluator,
  ) {
    // Determiner si nous avons un constructeur personnalise
    // thisBinding sera le constructeur si appele via .call(constructor, ...)
    JSValue constructor = thisBinding;
    int argsStartIndex = 0;

    // Si thisBinding est undefined ou null, on utilise les arguments normaux (Array.from(items, mapFn, thisArg))
    if (thisBinding.isUndefined || thisBinding.isNull) {
      constructor = JSValueFactory.undefined();
      argsStartIndex = 0;
    }
    // Si thisBinding est Array (le constructeur), on utilise les arguments normaux
    else if (thisBinding is JSNativeFunction &&
        thisBinding.functionName == 'Array') {
      // Appel normal: Array.from(items, mapFn, thisArg)
      constructor = JSValueFactory.undefined();
      argsStartIndex = 0;
    } else {
      // Appel avec .call(): Array.from.call(CustomConstructor, items, mapFn, thisArg)
      // thisBinding est le CustomConstructor
      constructor = thisBinding;
      argsStartIndex = 0; // Les arguments commencent a l'index 0
    }

    // Verifier les arguments
    if (args.isEmpty) {
      throw JSTypeError('Array.from requires at least 1 argument');
    }

    final arrayLike = args[argsStartIndex];

    // ES6: Si items est undefined ou null, throw TypeError
    if (arrayLike.isUndefined || arrayLike.isNull) {
      throw JSTypeError('Cannot convert undefined or null to object');
    }

    final mapFn = args.length > (argsStartIndex + 1)
        ? args[argsStartIndex + 1]
        : null;
    final thisArg = args.length > (argsStartIndex + 2)
        ? args[argsStartIndex + 2]
        : null;

    // ES6: Si mapFn est fourni et pas undefined, doit etre callable
    if (mapFn != null && !mapFn.isUndefined) {
      if (!mapFn.isFunction) {
        throw JSTypeError(
          'Array.from: when provided, the second argument must be a function',
        );
      }
    }

    final result = <JSValue>[];

    // Helper function untuk menerapkan mapFn
    JSValue applyMapFn(JSValue element, int index) {
      if (mapFn != null && !mapFn.isUndefined && mapFn.isFunction) {
        // Per ES6 spec: "If thisArg was supplied, let T be thisArg; else let T be undefined."
        // In strict mode functions, undefined stays undefined.
        // In non-strict mode functions, undefined becomes the global object.
        // We must pass undefined (not null) when thisArg is not provided.
        final JSValue effectiveThisArg;
        if (thisArg != null) {
          // thisArg was explicitly provided
          effectiveThisArg = thisArg;
        } else {
          // No thisArg provided - pass undefined explicitly
          effectiveThisArg = JSValueFactory.undefined();
        }
        return evaluator.callFunction(mapFn, [
          element,
          JSValueFactory.number(index.toDouble()),
        ], effectiveThisArg);
      }
      return element;
    }

    // Step 1: Verifier Symbol.iterator (iterable protocol)
    if (arrayLike is JSObject) {
      final symbolIteratorKey = JSSymbol.iterator.toString();
      final iteratorMethod = arrayLike.getProperty(symbolIteratorKey);

      if (!iteratorMethod.isUndefined && iteratorMethod.isFunction) {
        // Appeler Symbol.iterator
        final iterator = evaluator.callFunction(iteratorMethod, [], arrayLike);
        if (iterator is JSObject) {
          int index = 0;
          try {
            while (true) {
              final nextMethod = iterator.getProperty('next');
              if (nextMethod.isUndefined || !nextMethod.isFunction) {
                break;
              }
              final iterResult = evaluator.callFunction(
                nextMethod,
                [],
                iterator,
              );
              if (iterResult is! JSObject) break;

              final done = iterResult.getProperty('done').toBoolean();
              if (done) break;

              final value = iterResult.getProperty('value');
              result.add(applyMapFn(value, index));
              index++;
            }
          } catch (e) {
            // If error occurs during iteration, close iterator and re-throw
            _closeIterator(iterator, evaluator);
            rethrow;
          }

          // Creer l'array avec le constructeur personnalise ou Array
          // For iterator path, pass null for length (will use 0)
          // This may throw if constructor throws or property assignment fails
          // Pass iterator for proper cleanup on error
          return _createArrayFromConstructor(
            constructor,
            result,
            evaluator,
            null,
            iterator,
          );
        }
      }
    }

    // Case 1: Array
    if (arrayLike is JSArray) {
      for (int i = 0; i < arrayLike.elements.length; i++) {
        result.add(applyMapFn(arrayLike.elements[i], i));
      }
    }
    // Case 2: String
    else if (arrayLike.isString) {
      final str = arrayLike.toString();
      for (int i = 0; i < str.length; i++) {
        result.add(applyMapFn(JSValueFactory.string(str[i]), i));
      }
    }
    // Case 3: Set
    else if (arrayLike is JSSet) {
      int index = 0;
      for (final element in arrayLike.values) {
        result.add(applyMapFn(element, index));
        index++;
      }
    }
    // Case 4: Map (iterable des entries)
    else if (arrayLike is JSMap) {
      int index = 0;
      for (final entry in arrayLike.entries) {
        final entryArray = JSValueFactory.array([entry.key, entry.value]);
        result.add(applyMapFn(entryArray, index));
        index++;
      }
    }
    // Case 5: Array-like object
    else if (arrayLike is JSObject) {
      final lengthProp = arrayLike.getProperty('length');
      if (!lengthProp.isUndefined) {
        final length = lengthProp.toNumber().floor();
        for (int i = 0; i < length; i++) {
          final element = arrayLike.getProperty(i.toString());
          result.add(applyMapFn(element, i));
        }
        // For array-like objects, pass the length to constructor
        return _createArrayFromConstructor(
          constructor,
          result,
          evaluator,
          JSValueFactory.number(length.toDouble()),
        );
      }
    }

    // Default: Creer l'array avec le constructeur approprie
    return _createArrayFromConstructor(constructor, result, evaluator, null);
  }

  /// Cree un array en utilisant un constructeur personnalise ou Array
  /// length can be null (use result.length) or a specific value (for array-like)
  JSValue _createArrayFromConstructor(
    JSValue constructor,
    List<JSValue> elements,
    JSEvaluator evaluator,
    JSValue? length, [
    JSObject? iterator,
  ]) {
    if (constructor.isUndefined) {
      // Utiliser Array par defaut
      return JSValueFactory.array(elements);
    }

    // Utiliser le constructeur personnalise
    if (constructor is! JSFunction) {
      throw JSTypeError('Array.from: constructor must be a function');
    }

    // Determine constructor arguments:
    // - For array-like: pass the length to the constructor
    // - For iterator: pass no arguments
    final constructorArgs = length != null ? <JSValue>[length] : <JSValue>[];

    // Use 'new' semantics for constructor call
    // Create a new object with the constructor's prototype
    final newObject = JSObject();

    // Set the prototype from the constructor's prototype property
    final prototypeValue = constructor.getProperty('prototype');
    if (prototypeValue is JSObject) {
      newObject.setPrototype(prototypeValue);
    }

    // Call the constructor with the new object as 'this'
    JSValue callResult;
    try {
      // For user-defined JS functions
      callResult = evaluator.callFunction(
        constructor,
        constructorArgs,
        newObject,
      );
    } catch (e) {
      // If constructor throws, close iterator and re-throw
      if (iterator != null) {
        _closeIterator(iterator, evaluator);
      }
      rethrow;
    }

    // Handle constructor return value per ES6 semantics:
    // If constructor returns an object, use that; otherwise use newObject
    JSValue resultInstance = newObject;
    if (callResult is JSObject) {
      // Constructor returned an object, use it
      resultInstance = callResult;
    }
    // If not an object, use the original newObject
    // (constructor didn't return anything explicit, or returned primitive)

    // Remplir l'objet avec les elements
    // For length: use normal property assignment to trigger setters (ES6 spec says Set, not CreateDataProperty)
    // For indexed properties: use CreateDataProperty
    if (resultInstance is JSObject) {
      try {
        // Set length property using normal assignment to trigger any setters
        resultInstance.setProperty(
          'length',
          JSValueFactory.number(elements.length.toDouble()),
        );

        for (int i = 0; i < elements.length; i++) {
          final indexStr = i.toString();
          resultInstance.createDataPropertyOrThrow(indexStr, elements[i]);
        }
      } catch (e) {
        // If property setting fails, close iterator and re-throw
        if (iterator != null) {
          _closeIterator(iterator, evaluator);
        }
        rethrow;
      }
    }
    // For non-object results, we can't add properties

    return resultInstance;
  }

  /// Helper method to close an iterator by calling its return() method
  void _closeIterator(JSObject iterator, JSEvaluator evaluator) {
    final returnMethod = iterator.getProperty('return');
    if (!returnMethod.isUndefined && returnMethod.isFunction) {
      try {
        evaluator.callFunction(returnMethod, [], iterator);
      } catch (_) {
        // Ignore errors from iterator.return() per ES6 spec
      }
    }
  }
}
