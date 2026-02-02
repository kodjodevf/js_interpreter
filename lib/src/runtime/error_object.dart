import 'js_value.dart';
import 'native_functions.dart';
import '../evaluator/evaluator.dart';

/// Helper class to store parsed constructor arguments
class _ErrorConstructorArgs {
  final JSObject? existingInstance;
  final String? message;
  final JSValue? cause;
  final bool hasCause;

  _ErrorConstructorArgs({
    this.existingInstance,
    this.message,
    this.cause,
    required this.hasCause,
  });
}

/// Parse error constructor arguments, detecting existing instances from super() calls
_ErrorConstructorArgs _parseErrorConstructorArgs(
  List<JSValue> args,
  JSObject errorPrototype,
) {
  JSObject? existingInstance;
  List<JSValue> effectiveArgs = args;

  // Check if first argument is an existing instance (from super() call)
  // An existing instance will have:
  // 1. A prototype that's in the Error prototype chain (but not errorPrototype itself)
  // 2. The instance is being passed from a subclass constructor
  if (args.isNotEmpty && args[0] is JSObject) {
    final firstArg = args[0] as JSObject;
    final proto = firstArg.getPrototype();

    // Check if this is a subclass instance:
    // - Has a prototype that extends Error
    // - Prototype is NOT the direct error prototype (i.e., it's a subclass prototype)
    if (proto != null && proto != errorPrototype) {
      // Walk up the chain to see if any Error prototype is in the chain
      JSObject? current = proto;
      bool extendsError = false;
      while (current != null) {
        // Check if this is an Error prototype by checking if it has the error-specific
        // properties that error prototypes have (name = 'Error' or similar)
        final nameVal = current.getOwnPropertyDirect('name');
        if (nameVal != null && nameVal is JSString) {
          final name = nameVal.toString();
          if (name == 'Error' ||
              name == 'TypeError' ||
              name == 'ReferenceError' ||
              name == 'SyntaxError' ||
              name == 'RangeError' ||
              name == 'EvalError' ||
              name == 'URIError' ||
              name == 'AggregateError') {
            extendsError = true;
            break;
          }
        }
        current = current.getPrototype();
      }

      // Only treat as existing instance if it extends an Error type
      if (extendsError) {
        existingInstance = firstArg;
        effectiveArgs = args.length > 1 ? args.sublist(1) : [];
      }
    }
  }

  String? message;
  JSValue? cause;
  bool hasCause = false;

  // Step 1: Convert message to string (may invoke toString method)
  if (effectiveArgs.isNotEmpty &&
      effectiveArgs[0].type != JSValueType.undefined) {
    final messageArg = effectiveArgs[0];
    // Call JavaScript's toString method if available
    if (messageArg.type == JSValueType.object) {
      final obj = messageArg as JSObject;
      final toStringProp = obj.getProperty('toString');
      if (toStringProp.type == JSValueType.function) {
        final toStringFunc = toStringProp as JSFunction;
        try {
          // Use evaluator to call the function
          final evaluator = JSEvaluator.currentInstance;
          if (evaluator != null) {
            final result = evaluator.callFunction(toStringFunc, [], obj);
            message = result.toString();
          } else {
            message = messageArg.toString();
          }
        } catch (e) {
          // If toString fails, use default conversion
          message = messageArg.toString();
        }
      } else {
        message = messageArg.toString();
      }
    } else {
      message = messageArg.toString();
    }
  }

  // Step 2: Handle options parameter and extract cause
  if (effectiveArgs.length > 1 && effectiveArgs[1].type == JSValueType.object) {
    final options = effectiveArgs[1] as JSObject;
    try {
      if (options.hasProperty('cause')) {
        hasCause = true;
        try {
          cause = options.getProperty('cause');
        } catch (e) {
          rethrow;
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  return _ErrorConstructorArgs(
    existingInstance: existingInstance,
    message: message,
    cause: cause,
    hasCause: hasCause,
  );
}

/// Factory to create JavaScript Error objects
class JSErrorObjectFactory {
  /// Create the global Error object with all error constructors
  static JSObject createErrorObject() {
    final errorObject = JSObject();

    // Create the prototypes first
    final errorPrototype = _createErrorPrototype('Error');
    final typeErrorPrototype = _createErrorPrototype('TypeError');
    final referenceErrorPrototype = _createErrorPrototype('ReferenceError');
    final syntaxErrorPrototype = _createErrorPrototype('SyntaxError');
    final rangeErrorPrototype = _createErrorPrototype('RangeError');
    final evalErrorPrototype = _createErrorPrototype('EvalError');
    final uriErrorPrototype = _createErrorPrototype('URIError');

    // Establish the prototype chain: Error.prototype -> Object.prototype
    // First, retrieve Object.prototype from the evaluator
    JSObject? objectPrototype;
    try {
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        final objectConstructor = evaluator.globalEnvironment.get('Object');
        if (objectConstructor is JSFunction) {
          final proto = objectConstructor.getProperty('prototype');
          if (proto is JSObject) {
            objectPrototype = proto;
          }
        }
      }
    } catch (_) {
      // If we can't retrieve Object.prototype, continue without
    }
    if (objectPrototype != null) {
      errorPrototype.setPrototype(objectPrototype);
    }

    // Establish the chain: TypeError.prototype -> Error.prototype, etc.
    typeErrorPrototype.setPrototype(errorPrototype);
    referenceErrorPrototype.setPrototype(errorPrototype);
    syntaxErrorPrototype.setPrototype(errorPrototype);
    rangeErrorPrototype.setPrototype(errorPrototype);
    evalErrorPrototype.setPrototype(errorPrototype);
    uriErrorPrototype.setPrototype(errorPrototype);

    // Error constructor de base
    final errorConstructor = JSNativeFunction(
      functionName: 'Error',
      nativeImpl: (args) {
        final parsed = _parseErrorConstructorArgs(args, errorPrototype);
        return _createErrorObject(
          'Error',
          parsed.message,
          parsed.cause,
          errorPrototype,
          null,
          parsed.hasCause,
          parsed.existingInstance,
        );
      },
      expectedArgs: 1,
      isConstructor: true, // Error is a constructor
    );

    // Add static properties to Error
    errorConstructor.setProperty('name', JSValueFactory.string('Error'));

    // ES2024: Error.isError static method
    final isErrorMethod = JSNativeFunction(
      functionName: 'isError',
      nativeImpl: (args) {
        if (args.isEmpty) return JSValueFactory.boolean(false);
        final arg = args[0];
        // Check if the argument is an object with an [[ErrorData]] internal slot
        if (arg.type != JSValueType.object) {
          return JSValueFactory.boolean(false);
        }
        final obj = arg as JSObject;
        // Per ES spec: Error.isError returns true if argument has [[ErrorData]] internal slot
        return JSValueFactory.boolean(obj.hasInternalSlot('ErrorData'));
      },
      expectedArgs: 1,
    );
    errorConstructor.setProperty('isError', isErrorMethod);
    // Set the descriptor for isError: writable=true, enumerable=false, configurable=true
    errorConstructor.defineOwnProperty(
      'isError',
      PropertyDescriptor(
        value: isErrorMethod,
        writable: true,
        enumerable: false,
        configurable: true,
        hasValueProperty: true,
      ),
    );

    // TypeError constructor
    final typeErrorConstructor = JSNativeFunction(
      functionName: 'TypeError',
      nativeImpl: (args) {
        final parsed = _parseErrorConstructorArgs(args, typeErrorPrototype);
        return _createErrorObject(
          'TypeError',
          parsed.message,
          parsed.cause,
          typeErrorPrototype,
          null,
          parsed.hasCause,
          parsed.existingInstance,
        );
      },
      expectedArgs: 1,
      isConstructor: true, // TypeError is a constructor
    );

    // ReferenceError constructor
    final referenceErrorConstructor = JSNativeFunction(
      functionName: 'ReferenceError',
      nativeImpl: (args) {
        final parsed = _parseErrorConstructorArgs(
          args,
          referenceErrorPrototype,
        );
        return _createErrorObject(
          'ReferenceError',
          parsed.message,
          parsed.cause,
          referenceErrorPrototype,
          null,
          parsed.hasCause,
          parsed.existingInstance,
        );
      },
      expectedArgs: 1,
      isConstructor: true, // ReferenceError is a constructor
    );

    // SyntaxError constructor
    final syntaxErrorConstructor = JSNativeFunction(
      functionName: 'SyntaxError',
      nativeImpl: (args) {
        final parsed = _parseErrorConstructorArgs(args, syntaxErrorPrototype);
        return _createErrorObject(
          'SyntaxError',
          parsed.message,
          parsed.cause,
          syntaxErrorPrototype,
          null,
          parsed.hasCause,
          parsed.existingInstance,
        );
      },
      expectedArgs: 1,
      isConstructor: true, // SyntaxError is a constructor
    );

    // RangeError constructor
    final rangeErrorConstructor = JSNativeFunction(
      functionName: 'RangeError',
      nativeImpl: (args) {
        final parsed = _parseErrorConstructorArgs(args, rangeErrorPrototype);
        return _createErrorObject(
          'RangeError',
          parsed.message,
          parsed.cause,
          rangeErrorPrototype,
          null,
          parsed.hasCause,
          parsed.existingInstance,
        );
      },
      expectedArgs: 1,
      isConstructor: true, // RangeError is a constructor
    );

    // EvalError constructor
    final evalErrorConstructor = JSNativeFunction(
      functionName: 'EvalError',
      nativeImpl: (args) {
        final parsed = _parseErrorConstructorArgs(args, evalErrorPrototype);
        return _createErrorObject(
          'EvalError',
          parsed.message,
          parsed.cause,
          evalErrorPrototype,
          null,
          parsed.hasCause,
          parsed.existingInstance,
        );
      },
      expectedArgs: 1,
      isConstructor: true, // EvalError is a constructor
    );

    // URIError constructor
    final uriErrorConstructor = JSNativeFunction(
      functionName: 'URIError',
      nativeImpl: (args) {
        final parsed = _parseErrorConstructorArgs(args, uriErrorPrototype);
        return _createErrorObject(
          'URIError',
          parsed.message,
          parsed.cause,
          uriErrorPrototype,
          null,
          parsed.hasCause,
          parsed.existingInstance,
        );
      },
      expectedArgs: 1,
      isConstructor: true, // URIError is a constructor
    );

    // Bind the constructors to their prototypes
    // The prototype property must be non-writable per ES spec
    errorConstructor.defineOwnProperty(
      'prototype',
      PropertyDescriptor(
        value: errorPrototype,
        writable: false,
        enumerable: false,
        configurable: false,
        hasValueProperty: true,
      ),
    );
    typeErrorConstructor.defineOwnProperty(
      'prototype',
      PropertyDescriptor(
        value: typeErrorPrototype,
        writable: false,
        enumerable: false,
        configurable: false,
        hasValueProperty: true,
      ),
    );
    referenceErrorConstructor.defineOwnProperty(
      'prototype',
      PropertyDescriptor(
        value: referenceErrorPrototype,
        writable: false,
        enumerable: false,
        configurable: false,
        hasValueProperty: true,
      ),
    );
    syntaxErrorConstructor.defineOwnProperty(
      'prototype',
      PropertyDescriptor(
        value: syntaxErrorPrototype,
        writable: false,
        enumerable: false,
        configurable: false,
        hasValueProperty: true,
      ),
    );
    rangeErrorConstructor.defineOwnProperty(
      'prototype',
      PropertyDescriptor(
        value: rangeErrorPrototype,
        writable: false,
        enumerable: false,
        configurable: false,
        hasValueProperty: true,
      ),
    );
    evalErrorConstructor.defineOwnProperty(
      'prototype',
      PropertyDescriptor(
        value: evalErrorPrototype,
        writable: false,
        enumerable: false,
        configurable: false,
        hasValueProperty: true,
      ),
    );
    uriErrorConstructor.defineOwnProperty(
      'prototype',
      PropertyDescriptor(
        value: uriErrorPrototype,
        writable: false,
        enumerable: false,
        configurable: false,
        hasValueProperty: true,
      ),
    );

    // Expose all constructors
    errorObject.setProperty('Error', errorConstructor);
    errorObject.setProperty('TypeError', typeErrorConstructor);
    errorObject.setProperty('ReferenceError', referenceErrorConstructor);
    errorObject.setProperty('SyntaxError', syntaxErrorConstructor);
    errorObject.setProperty('RangeError', rangeErrorConstructor);
    errorObject.setProperty('EvalError', evalErrorConstructor);
    errorObject.setProperty('URIError', uriErrorConstructor);

    return errorObject;
  }

  /// Create a JavaScript Error object with the specified name and message
  /// ES2022: Support for cause parameter
  /// existingInstance: If provided, initialize this instance instead of creating a new one
  static JSObject _createErrorObject(
    String name,
    String? message, [
    JSValue? cause,
    JSObject? prototype,
    JSValue? constructor,
    bool hasCause = false,
    JSObject? existingInstance,
  ]) {
    // Use existing instance if provided (super() call), otherwise create new
    final errorObj = existingInstance ?? JSObject();

    // Set [[ErrorData]] internal slot per ES spec
    // This is required for Object.prototype.toString to return "[object Error]"
    errorObj.setInternalSlot('ErrorData', true);

    // Only set prototype if this is a new object (not from subclass)
    if (existingInstance == null && prototype != null) {
      errorObj.setPrototype(prototype);
    }

    // Standard properties of an Error object
    // Per ES spec: name property is non-enumerable, writable, configurable
    errorObj.defineProperty(
      'name',
      PropertyDescriptor(
        value: JSValueFactory.string(name),
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );
    // Per spec: only set message property if message was explicitly provided
    // message property is non-enumerable, writable, configurable
    if (message != null) {
      errorObj.defineProperty(
        'message',
        PropertyDescriptor(
          value: JSValueFactory.string(message),
          writable: true,
          enumerable: false,
          configurable: true,
        ),
      );
    }

    // ES2022: Add cause property if provided - must be non-enumerable
    // Note: hasCause flag indicates whether cause was explicitly provided in options
    // even if its value is undefined
    if (hasCause) {
      // Set cause as non-enumerable data property
      errorObj.defineProperty(
        'cause',
        PropertyDescriptor(
          value: cause,
          writable: true,
          enumerable: false,
          configurable: true,
        ),
      );
    }

    // Set constructor property if provided, otherwise try to get it from global
    if (constructor != null) {
      errorObj.setProperty('constructor', constructor);
    } else {
      // Try to get the constructor from the global environment
      try {
        final evaluator = JSEvaluator.currentInstance;
        if (evaluator != null) {
          final ctor = evaluator.globalEnvironment.get(name);
          if (ctor is JSFunction) {
            errorObj.setProperty('constructor', ctor);
          }
        }
      } catch (_) {
        // If we can't get the constructor, continue without it
      }
    }

    // Stack trace (simplified version - we can improve it later)
    final stack = _generateStackTrace(name, message);
    errorObj.setProperty('stack', JSValueFactory.string(stack));

    // Per ES spec: Error instances should NOT have own toString method
    // They inherit toString from Error.prototype

    return errorObj;
  }

  /// Creates the prototype for an error type
  static JSObject _createErrorPrototype(String name) {
    final prototype = JSObject();

    prototype.setProperty('name', JSValueFactory.string(name));
    prototype.setProperty('message', JSValueFactory.string(''));

    // toString method for the prototype
    prototype.setProperty(
      'toString',
      JSNativeFunction(
        functionName: 'toString',
        nativeImpl: (args) {
          // When called as a method, 'this' is passed as the first argument
          JSValue thisObj = args.isNotEmpty
              ? args[0]
              : JSValueFactory.undefined();

          if (thisObj.type == JSValueType.object) {
            final obj = thisObj as JSObject;
            final errorName = obj.getProperty('name');
            final errorMessage = obj.getProperty('message');

            String nameStr = errorName.toString();
            String msgStr = errorMessage.toString();

            if (msgStr.isEmpty) {
              return JSValueFactory.string(nameStr);
            } else {
              return JSValueFactory.string('$nameStr: $msgStr');
            }
          }

          return JSValueFactory.string('$name: ');
        },
      ),
    );

    return prototype;
  }

  /// Genere une stack trace simplifiee
  static String _generateStackTrace(String name, String? message) {
    // Simplified version - in a complete implementation,
    // we would have access to the JavaScript call stack
    final buffer = StringBuffer();

    if (message != null && message.isNotEmpty) {
      buffer.writeln('$name: $message');
    } else {
      buffer.writeln(name);
    }

    // Simulated stack trace
    buffer.writeln('    at <anonymous>:1:1');

    return buffer.toString().trim();
  }

  /// Utility functions to throw errors in the interpreter

  /// Throw a TypeError
  static Never throwTypeError(String message) {
    throw JSTypeError(message);
  }

  /// Throw a ReferenceError
  static Never throwReferenceError(String message) {
    throw JSReferenceError(message);
  }

  /// Throw a SyntaxError
  static Never throwSyntaxError(String message) {
    throw JSSyntaxError(message);
  }

  /// Throw a RangeError
  static Never throwRangeError(String message) {
    throw JSRangeError(message);
  }

  /// Create a JSValue Error from a Dart exception
  static JSValue fromDartError(Object error, [JSObject? prototype]) {
    String name = 'Error';
    String message = error.toString();

    if (error is JSError) {
      name = error.name;
      message = error.message;
    } else if (error is TypeError) {
      name = 'TypeError';
    } else if (error is RangeError) {
      name = 'RangeError';
    } else if (error is ArgumentError) {
      name = 'TypeError';
    }

    // If no prototype is provided, try to get it from the global evaluator
    // Also get the constructor function
    JSValue? constructor;
    try {
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator != null) {
        final ctor = evaluator.globalEnvironment.get(name);
        if (ctor is JSFunction) {
          constructor = ctor;
          if (prototype == null) {
            final proto = ctor.getProperty('prototype');
            if (proto is JSObject) {
              prototype = proto;
            }
          }
        }
      }
    } catch (e) {
      // Ignore errors when trying to get prototype
    }

    return _createErrorObject(name, message, null, prototype, constructor);
  }
}
