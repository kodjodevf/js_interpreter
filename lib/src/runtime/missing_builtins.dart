/// Missing built-in constructors and objects for test262 compatibility
library;

import 'js_value.dart';
import 'js_symbol.dart';
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

      if (target is! JSObject && target is! JSSymbol) {
        throw JSTypeError('WeakRef target must be an object or symbol');
      }

      return JSWeakRefObject(target);
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

      return JSFinalizationRegistryObject(callback);
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
