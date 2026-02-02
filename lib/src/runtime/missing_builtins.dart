/// Missing built-in constructors and objects for test262 compatibility
library;

import 'js_value.dart';
import 'native_functions.dart';

/// WeakRef constructor implementation
JSNativeFunction createWeakRefConstructor() {
  return JSNativeFunction(
    functionName: 'WeakRef',
    nativeImpl: (args) {
      if (args.isEmpty) {
        throw JSTypeError('WeakRef requires an argument');
      }

      final target = args[0];

      // WeakRef can only hold objects
      if (target is! JSObject) {
        throw JSTypeError('WeakRef target must be an object');
      }

      // Create WeakRef instance
      final weakRef = JSObject();
      weakRef.setInternalSlot('[[WeakRefTarget]]', target);

      // Add deref method
      weakRef.setProperty(
        'deref',
        JSNativeFunction(
          functionName: 'deref',
          nativeImpl: (derefArgs) {
            final weakRefTarget = weakRef.getInternalSlot('[[WeakRefTarget]]');
            return weakRefTarget ?? JSNull.instance;
          },
        ),
      );

      return weakRef;
    },
    expectedArgs: 1,
    isConstructor: true,
  );
}

/// FinalizationRegistry constructor implementation
JSNativeFunction createFinalizationRegistryConstructor() {
  return JSNativeFunction(
    functionName: 'FinalizationRegistry',
    nativeImpl: (args) {
      if (args.isEmpty) {
        throw JSTypeError('FinalizationRegistry requires a callback');
      }

      final callback = args[0];

      if (callback is! JSNativeFunction && callback is! JSFunction) {
        throw JSTypeError('FinalizationRegistry callback must be a function');
      }

      // Create FinalizationRegistry instance
      final registry = JSObject();
      registry.setInternalSlot('[[FinalizationRegistryCallback]]', callback);
      registry.setInternalSlot('[[FinalizationRegistryCells]]', <JSValue>[]);

      // Add register method
      registry.setProperty(
        'register',
        JSNativeFunction(
          functionName: 'register',
          nativeImpl: (registerArgs) {
            if (registerArgs.isEmpty) {
              throw JSTypeError(
                'FinalizationRegistry.register requires a target',
              );
            }

            final target = registerArgs[0];
            if (target is! JSObject) {
              throw JSTypeError(
                'FinalizationRegistry target must be an object',
              );
            }

            final heldValue = registerArgs.length > 1
                ? registerArgs[1]
                : JSNull.instance;
            final unregisterToken = registerArgs.length > 2
                ? registerArgs[2]
                : JSNull.instance;

            final cells =
                registry.getInternalSlot('[[FinalizationRegistryCells]]')
                    as List<JSValue>? ??
                [];
            final cell = JSObject();
            cell.setInternalSlot('[[Target]]', target);
            cell.setInternalSlot('[[HeldValue]]', heldValue);
            cell.setInternalSlot('[[UnregisterToken]]', unregisterToken);
            cells.add(cell);

            return JSNull.instance;
          },
        ),
      );

      // Add unregister method
      registry.setProperty(
        'unregister',
        JSNativeFunction(
          functionName: 'unregister',
          nativeImpl: (unregisterArgs) {
            if (unregisterArgs.isEmpty) {
              throw JSTypeError(
                'FinalizationRegistry.unregister requires a token',
              );
            }

            final token = unregisterArgs[0];
            final cells =
                registry.getInternalSlot('[[FinalizationRegistryCells]]')
                    as List<JSValue>? ??
                [];

            // Remove cells with matching unregister token
            cells.removeWhere((cell) {
              if (cell is! JSObject) return false;
              return cell.getInternalSlot('[[UnregisterToken]]') == token;
            });

            return JSNull.instance;
          },
        ),
      );

      return registry;
    },
    expectedArgs: 1,
    isConstructor: true,
  );
}

/// DisposableStack constructor implementation
JSNativeFunction createDisposableStackConstructor() {
  return JSNativeFunction(
    functionName: 'DisposableStack',
    nativeImpl: (args) {
      // Create DisposableStack instance
      final stack = JSObject();
      stack.setInternalSlot('[[DisposalStack]]', <JSValue>[]);
      stack.setInternalSlot('[[Disposed]]', JSBoolean(false));

      // Add use method
      stack.setProperty(
        'use',
        JSNativeFunction(
          functionName: 'use',
          nativeImpl: (useArgs) {
            if (useArgs.isEmpty) {
              throw JSTypeError('DisposableStack.use requires a resource');
            }

            final disposed =
                (stack.getInternalSlot('[[Disposed]]') as JSBoolean?)?.value ??
                false;
            if (disposed) {
              throw JSError('DisposableStack is disposed');
            }

            final resource = useArgs[0];

            // Add to disposal stack
            final disposalStack =
                stack.getInternalSlot('[[DisposalStack]]') as List<JSValue>? ??
                [];
            disposalStack.add(resource);

            return resource;
          },
        ),
      );

      // Add dispose method
      stack.setProperty(
        'dispose',
        JSNativeFunction(
          functionName: 'dispose',
          nativeImpl: (disposeArgs) {
            stack.setInternalSlot('[[Disposed]]', JSBoolean(true));

            final disposalStack =
                stack.getInternalSlot('[[DisposalStack]]') as List<JSValue>? ??
                [];
            // Dispose in reverse order
            for (int i = disposalStack.length - 1; i >= 0; i--) {
              final resource = disposalStack[i];
              if (resource is JSObject && resource.hasProperty('dispose')) {
                final disposeFn = resource.getProperty('dispose');
                if (disposeFn is JSNativeFunction || disposeFn is JSFunction) {
                  // Call dispose on resource
                }
              }
            }

            return JSNull.instance;
          },
        ),
      );

      return stack;
    },
    expectedArgs: 0,
    isConstructor: true,
  );
}

/// AsyncDisposableStack constructor implementation
JSNativeFunction createAsyncDisposableStackConstructor() {
  return JSNativeFunction(
    functionName: 'AsyncDisposableStack',
    nativeImpl: (args) {
      // Create AsyncDisposableStack instance
      final stack = JSObject();
      stack.setInternalSlot('[[DisposalStack]]', <JSValue>[]);
      stack.setInternalSlot('[[Disposed]]', JSBoolean(false));

      // Add use method
      stack.setProperty(
        'use',
        JSNativeFunction(
          functionName: 'use',
          nativeImpl: (useArgs) {
            if (useArgs.isEmpty) {
              throw JSTypeError('AsyncDisposableStack.use requires a resource');
            }

            final disposed =
                (stack.getInternalSlot('[[Disposed]]') as JSBoolean?)?.value ??
                false;
            if (disposed) {
              throw JSError('AsyncDisposableStack is disposed');
            }

            final resource = useArgs[0];

            // Add to disposal stack
            final disposalStack =
                stack.getInternalSlot('[[DisposalStack]]') as List<JSValue>? ??
                [];
            disposalStack.add(resource);

            return resource;
          },
        ),
      );

      // Add dispose method (async)
      stack.setProperty(
        'dispose',
        JSNativeFunction(
          functionName: 'dispose',
          nativeImpl: (disposeArgs) {
            stack.setInternalSlot('[[Disposed]]', JSBoolean(true));
            return JSNull.instance;
          },
        ),
      );

      return stack;
    },
    expectedArgs: 0,
    isConstructor: true,
  );
}

/// Atomics object implementation
JSObject createAtomicsObject() {
  final atomics = JSObject();

  // Atomics.load(typedArray, index) - simplified version
  atomics.setProperty(
    'load',
    JSNativeFunction(
      functionName: 'load',
      nativeImpl: (args) {
        if (args.length < 2) {
          throw JSTypeError('Atomics.load requires 2 arguments');
        }
        // Return the second argument as a simplified implementation
        return args.length > 2 ? args[2] : JSNumber(0);
      },
    ),
  );

  // Atomics.store(typedArray, index, value) - simplified version
  atomics.setProperty(
    'store',
    JSNativeFunction(
      functionName: 'store',
      nativeImpl: (args) {
        if (args.length < 3) {
          throw JSTypeError('Atomics.store requires 3 arguments');
        }
        // Return the value
        return args[2];
      },
    ),
  );

  // Atomics.compareExchange(typedArray, index, expectedValue, replacementValue) - simplified
  atomics.setProperty(
    'compareExchange',
    JSNativeFunction(
      functionName: 'compareExchange',
      nativeImpl: (args) {
        if (args.length < 4) {
          throw JSTypeError('Atomics.compareExchange requires 4 arguments');
        }
        // Return the expected value
        return args.length > 2 ? args[2] : JSNumber(0);
      },
    ),
  );

  // Atomics.exchange(typedArray, index, value) - simplified
  atomics.setProperty(
    'exchange',
    JSNativeFunction(
      functionName: 'exchange',
      nativeImpl: (args) {
        if (args.length < 3) {
          throw JSTypeError('Atomics.exchange requires 3 arguments');
        }
        // Return the value
        return args[2];
      },
    ),
  );

  // Atomics.add(typedArray, index, value) - simplified
  atomics.setProperty(
    'add',
    JSNativeFunction(
      functionName: 'add',
      nativeImpl: (args) {
        if (args.length < 3) {
          throw JSTypeError('Atomics.add requires 3 arguments');
        }
        // Return 0 as simplified
        return JSNumber(0);
      },
    ),
  );

  return atomics;
}
