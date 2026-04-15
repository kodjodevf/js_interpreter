library;

import 'package:js_interpreter/src/runtime/number_object.dart';

import 'error_object.dart';
import 'function_prototype.dart';
import 'global_functions.dart';
import 'intl_object.dart';
import 'iterator_protocol.dart';
import 'js_regexp.dart';
import 'js_runtime.dart';
import 'js_symbol.dart';
import 'js_value.dart';
import 'json_object.dart';
import 'math_object.dart';
import 'missing_builtins.dart';
import 'native_functions.dart';
import 'object_prototype.dart';
import 'temporal.dart';
import 'date_object.dart';
import 'text_codec.dart';
import 'typed_arrays.dart';

class RuntimeBootstrap {
  static void populateGlobals(
    Map<String, JSValue> globals, {
    String? Function()? getInterpreterInstanceId,
  }) {
    final previousRuntime = JSRuntime.current;
    final bootstrapRuntime = _BootstrapRuntime(globals);
    JSRuntime.setCurrent(bootstrapRuntime);
    try {
      JSSymbol.initializeWellKnownSymbols();

      _define(globals, 'console', ConsoleObject.createConsoleObject());
      _define(globals, 'Math', MathObject.createMathObject());
      _define(globals, 'Number', _createNumberConstructor());
      _define(globals, 'Object', ObjectGlobal.createObjectGlobal());
      _define(globals, 'Function', FunctionGlobal.createFunctionGlobal());
      _define(globals, 'String', _createStringConstructor());
      _define(globals, 'Boolean', _createBooleanConstructor());
      _define(globals, 'Array', _createArrayConstructor());
      _define(globals, 'RegExp', _createRegExpConstructor());
      _define(globals, 'Date', _createDateConstructor());
      _define(globals, 'BigInt', _createBigIntConstructor());
      _define(globals, 'Symbol', _createSymbolConstructor());
      _define(globals, 'JSON', JSONObject.createJSONObject());
      _define(
        globals,
        'TextEncoder',
        TextEncoder.createTextEncoderConstructor(),
      );
      _define(
        globals,
        'TextDecoder',
        TextDecoder.createTextDecoderConstructor(),
      );

      final errorConstructors = JSErrorObjectFactory.createErrorObject();
      for (final name in [
        'Error',
        'TypeError',
        'ReferenceError',
        'SyntaxError',
        'RangeError',
        'EvalError',
        'URIError',
        'AggregateError',
      ]) {
        final ctor = errorConstructors.getProperty(name);
        if (!ctor.isUndefined) {
          _define(globals, name, ctor);
        }
      }

      _installCollections(globals);
      _installWeakCollections(globals);
      _installProxy(globals);
      _installReflect(globals);
      _installIntl(globals);
      _installTemporal(globals);
      _installMissingBuiltins(globals);
      _installTypedArrays(globals);
      _installPromise(globals);
      _installGlobalFunctions(
        globals,
        getInterpreterInstanceId: getInterpreterInstanceId,
      );
      _define(globals, 'global_var0', JSValueFactory.number(0));
      _installCommonJsGlobals(globals);
      _installGlobalThis(globals);
    } finally {
      JSRuntime.setCurrent(previousRuntime);
    }
  }

  static void _define(
    Map<String, JSValue> globals,
    String name,
    JSValue value,
  ) {
    globals[name] = value;
  }

  static JSNativeFunction _createNumberConstructor() {
    final numberConstructor = JSNativeFunction(
      functionName: 'Number',
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSValueFactory.number(0.0);
        }
        return JSValueFactory.number(args[0].toNumber());
      },
      expectedArgs: 1,
      isConstructor: true,
    );

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

    numberConstructor.setProperty(
      'isNaN',
      JSNativeFunction(functionName: 'isNaN', nativeImpl: NumberObject.isNaN),
    );
    numberConstructor.setProperty(
      'isFinite',
      JSNativeFunction(
        functionName: 'isFinite',
        nativeImpl: NumberObject.isFinite,
      ),
    );
    numberConstructor.setProperty(
      'isInteger',
      JSNativeFunction(
        functionName: 'isInteger',
        nativeImpl: NumberObject.isInteger,
      ),
    );
    numberConstructor.setProperty(
      'isSafeInteger',
      JSNativeFunction(
        functionName: 'isSafeInteger',
        nativeImpl: NumberObject.isSafeInteger,
      ),
    );
    numberConstructor.setProperty(
      'parseFloat',
      JSNativeFunction(
        functionName: 'parseFloat',
        nativeImpl: NumberObject.parseFloat,
      ),
    );
    numberConstructor.setProperty(
      'parseInt',
      JSNativeFunction(
        functionName: 'parseInt',
        nativeImpl: NumberObject.parseInt,
      ),
    );

    final numberPrototype = JSObject();
    numberConstructor.setProperty('prototype', numberPrototype);
    numberPrototype.defineConstructorProperty(numberConstructor);
    numberPrototype.setProperty(
      'toString',
      JSNativeFunction(
        functionName: 'toString',
        nativeImpl: (args) {
          final thisValue = args.isNotEmpty
              ? args[0]
              : JSValueFactory.number(0);
          final radix = args.length > 1 ? args[1].toNumber().floor() : 10;
          final double value;
          if (thisValue is JSNumberObject) {
            value = thisValue.primitiveValue;
          } else if (thisValue.isNumber) {
            value = thisValue.primitiveValue as double;
          } else {
            throw JSTypeError('Number.prototype.toString called on non-number');
          }
          if (radix == 10) {
            return JSValueFactory.string(value.toString());
          }
          if (radix < 2 || radix > 36) {
            throw JSRangeError('toString radix must be between 2 and 36');
          }
          return JSValueFactory.string(value.floor().toRadixString(radix));
        },
      ),
    );
    numberPrototype.setProperty(
      'valueOf',
      JSNativeFunction(
        functionName: 'valueOf',
        nativeImpl: (args) {
          final thisValue = args.isNotEmpty
              ? args[0]
              : JSValueFactory.number(0);
          if (thisValue is JSNumberObject) {
            return JSValueFactory.number(thisValue.primitiveValue);
          }
          if (thisValue.isNumber) {
            return thisValue;
          }
          throw JSTypeError('Number.prototype.valueOf called on non-number');
        },
      ),
    );
    numberPrototype.setInternalSlot('__internalClass__', 'Number');
    JSNumberObject.setNumberPrototype(numberPrototype);
    return numberConstructor;
  }

  static JSNativeFunction _createStringConstructor() {
    final stringConstructor = JSNativeFunction(
      functionName: 'String',
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSValueFactory.string('');
        }
        return JSValueFactory.string(args[0].toString());
      },
      expectedArgs: 1,
      isConstructor: true,
    );

    stringConstructor.setProperty(
      'fromCharCode',
      JSNativeFunction(
        functionName: 'fromCharCode',
        nativeImpl: (args) {
          final buffer = StringBuffer();
          for (final arg in args) {
            buffer.writeCharCode(arg.toNumber().floor() & 0xFFFF);
          }
          return JSValueFactory.string(buffer.toString());
        },
      ),
    );
    stringConstructor.setProperty(
      'fromCodePoint',
      JSNativeFunction(
        functionName: 'fromCodePoint',
        nativeImpl: (args) {
          final buffer = StringBuffer();
          for (final arg in args) {
            final number = arg.toNumber();
            if (number.isNaN || number.isInfinite) {
              throw JSRangeError('Invalid code point $number');
            }
            final codePoint = number.truncate();
            if (codePoint.toDouble() != number ||
                codePoint < 0 ||
                codePoint > 0x10FFFF) {
              throw JSRangeError('Invalid code point $number');
            }
            buffer.write(String.fromCharCode(codePoint));
          }
          return JSValueFactory.string(buffer.toString());
        },
      ),
    );
    stringConstructor.setProperty(
      'raw',
      JSNativeFunction(
        functionName: 'raw',
        expectedArgs: 1,
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSTypeError('String.raw requires a template object');
          }

          final template = args[0].toObject();
          final raw = template.getProperty('raw').toObject();
          final lengthValue = raw.getProperty('length').toNumber();

          if (lengthValue.isNaN || lengthValue <= 0) {
            return JSValueFactory.string('');
          }

          final literalSegments = lengthValue.floor();
          final buffer = StringBuffer();

          for (var index = 0; index < literalSegments; index++) {
            buffer.write(
              JSConversion.jsToString(raw.getProperty(index.toString())),
            );
            if (index + 1 >= literalSegments) {
              break;
            }

            final substitution = index + 1 < args.length
                ? args[index + 1]
                : JSValueFactory.string('');
            buffer.write(JSConversion.jsToString(substitution));
          }

          return JSValueFactory.string(buffer.toString());
        },
      ),
    );

    final stringPrototype = JSObject();
    stringConstructor.setProperty('prototype', stringPrototype);
    stringPrototype.defineConstructorProperty(stringConstructor);
    stringPrototype.setProperty(
      'toString',
      JSNativeFunction(
        functionName: 'toString',
        nativeImpl: (args) {
          final thisValue = args.isNotEmpty
              ? args[0]
              : JSValueFactory.string('');
          if (thisValue is JSStringObject) {
            return JSValueFactory.string(thisValue.value);
          }
          if (thisValue.isString) {
            return thisValue;
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
          final thisValue = args.isNotEmpty
              ? args[0]
              : JSValueFactory.string('');
          if (thisValue is JSStringObject) {
            return JSValueFactory.string(thisValue.value);
          }
          if (thisValue.isString) {
            return thisValue;
          }
          throw JSTypeError('String.prototype.valueOf called on non-string');
        },
      ),
    );
    stringPrototype.setProperty(
      JSSymbol.iterator.propertyKey,
      JSNativeFunction(
        functionName: 'Symbol.iterator',
        nativeImpl: (args) {
          final source = args.isNotEmpty ? args[0].toString() : '';
          final iterator = JSObject();
          var index = 0;
          iterator.setProperty(
            'next',
            JSNativeFunction(
              functionName: 'next',
              nativeImpl: (_) {
                final result = JSObject();
                if (index >= source.length) {
                  result.setProperty('done', JSValueFactory.boolean(true));
                  result.setProperty('value', JSValueFactory.undefined());
                  return result;
                }
                result.setProperty('done', JSValueFactory.boolean(false));
                result.setProperty(
                  'value',
                  JSValueFactory.string(source[index++]),
                );
                return result;
              },
            ),
          );
          iterator.setProperty(
            JSSymbol.iterator.propertyKey,
            JSNativeFunction(
              functionName: 'Symbol.iterator',
              nativeImpl: (_) => iterator,
            ),
          );
          return iterator;
        },
      ),
    );
    stringPrototype.setInternalSlot('__internalClass__', 'String');
    JSStringObject.setStringPrototype(stringPrototype);
    return stringConstructor;
  }

  static JSNativeFunction _createBooleanConstructor() {
    final booleanConstructor = JSNativeFunction(
      functionName: 'Boolean',
      nativeImpl: (args) {
        if (args.isEmpty) {
          return JSValueFactory.boolean(false);
        }
        final value = args[0];
        return JSValueFactory.boolean(
          value is JSObject ? true : value.toBoolean(),
        );
      },
      expectedArgs: 1,
      isConstructor: true,
    );

    final booleanPrototype = JSBooleanObject(false);
    booleanPrototype.setPrototype(JSObject.objectPrototype);
    booleanConstructor.defineProperty(
      'prototype',
      PropertyDescriptor(
        value: booleanPrototype,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    booleanPrototype.defineProperty(
      'constructor',
      PropertyDescriptor(
        value: booleanConstructor,
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );
    booleanPrototype.defineProperty(
      'toString',
      PropertyDescriptor(
        value: JSNativeFunction(
          functionName: 'toString',
          nativeImpl: (args) {
            final thisValue = args.isNotEmpty
                ? args[0]
                : JSValueFactory.boolean(false);
            if (thisValue is JSBooleanObject) {
              return JSValueFactory.string(thisValue.primitiveValue.toString());
            }
            if (thisValue.isBoolean) {
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
            final thisValue = args.isNotEmpty
                ? args[0]
                : JSValueFactory.boolean(false);
            if (thisValue is JSBooleanObject) {
              return JSValueFactory.boolean(thisValue.primitiveValue);
            }
            if (thisValue.isBoolean) {
              return thisValue;
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
    booleanPrototype.setInternalSlot('__internalClass__', 'Boolean');
    JSBooleanObject.setBooleanPrototype(booleanPrototype);
    return booleanConstructor;
  }

  static JSNativeFunction _createArrayConstructor() {
    final arrayPrototype = JSValueFactory.array([]);
    arrayPrototype.setPrototype(JSObject.objectPrototype);
    JSArray.setArrayPrototype(arrayPrototype);

    final arrayConstructor = JSNativeFunction(
      functionName: 'Array',
      nativeImpl: (args) {
        JSArray arr;
        if (args.isEmpty) {
          arr = JSValueFactory.array([]);
        } else if (args.length == 1 && args[0].isNumber) {
          final len = args[0].toNumber();
          if (len.isNaN ||
              len.isInfinite ||
              len < 0 ||
              len > 4294967295 ||
              len != len.truncateToDouble()) {
            throw JSRangeError('Invalid array length');
          }
          arr = JSValueFactory.array([]);
          arr.setProperty('length', JSValueFactory.number(len));
        } else {
          arr = JSValueFactory.array(args);
        }
        arr.setPrototype(arrayPrototype);
        return arr;
      },
      expectedArgs: 1,
      isConstructor: true,
    );

    arrayConstructor.setProperty('prototype', arrayPrototype);
    arrayPrototype.defineConstructorProperty(arrayConstructor);
    arrayConstructor.setProperty(
      'isArray',
      JSNativeFunction(
        functionName: 'isArray',
        nativeImpl: (args) =>
            JSValueFactory.boolean(args.isNotEmpty && args[0] is JSArray),
      ),
    );
    arrayConstructor.setProperty(
      'of',
      JSNativeFunction(
        functionName: 'of',
        nativeImpl: (args) => JSValueFactory.array(
          List<JSValue>.from(args.length > 1 ? args.sublist(1) : const []),
        ),
      ),
    );
    arrayConstructor.setProperty(
      'from',
      JSNativeFunction(
        functionName: 'from',
        nativeImpl: (args) {
          final actualArgs = args.length > 1
              ? args.sublist(1)
              : const <JSValue>[];
          if (actualArgs.isEmpty) {
            throw JSTypeError('Array.from requires at least 1 argument');
          }
          final source = actualArgs[0];
          final mapFn = actualArgs.length > 1 ? actualArgs[1] : null;
          final thisArg = actualArgs.length > 2
              ? actualArgs[2]
              : JSValueFactory.undefined();

          if (mapFn != null &&
              mapFn is! JSFunction &&
              mapFn is! JSNativeFunction) {
            throw JSTypeError(
              'Array.from: when provided, the second argument must be a function',
            );
          }

          final elements = <JSValue>[];
          void appendMapped(JSValue value, int index) {
            if (mapFn == null) {
              elements.add(value);
              return;
            }
            final runtime = JSRuntime.current;
            if (runtime == null) {
              throw JSError('No runtime available for Array.from callback');
            }
            elements.add(
              runtime.callFunction(mapFn, [
                value,
                JSValueFactory.number(index.toDouble()),
              ], thisArg),
            );
          }

          if (source is JSArray) {
            for (var index = 0; index < source.elements.length; index++) {
              appendMapped(source.elements[index], index);
            }
            return JSValueFactory.array(elements);
          }

          if (source is JSString) {
            final chars = source.value.split('');
            for (var index = 0; index < chars.length; index++) {
              appendMapped(JSValueFactory.string(chars[index]), index);
            }
            return JSValueFactory.array(elements);
          }

          final iterator = IteratorUtils.getIterator(source);
          if (iterator != null) {
            var index = 0;
            while (true) {
              final next = iterator.next();
              if (next is! JSObject || next.getProperty('done').toBoolean()) {
                break;
              }
              appendMapped(next.getProperty('value'), index++);
            }
            return JSValueFactory.array(elements);
          }

          if (source is JSObject && source.hasProperty('length')) {
            final length = source.getProperty('length').toNumber().toInt();
            for (var i = 0; i < length; i++) {
              appendMapped(source.getProperty(i.toString()), i);
            }
            return JSValueFactory.array(elements);
          }
          throw JSTypeError(
            'Array.from requires an iterable or array-like object',
          );
        },
      ),
    );
    return arrayConstructor;
  }

  static JSNativeFunction _createRegExpConstructor() {
    final regexpConstructor = JSNativeFunction(
      functionName: 'RegExp',
      nativeImpl: (args) {
        String pattern = '';
        String flags = '';
        if (args.isNotEmpty) {
          final firstArg = args[0];
          if (firstArg is JSRegExp) {
            pattern = firstArg.source;
            flags = args.length > 1 ? args[1].toString() : firstArg.flags;
          } else {
            pattern = firstArg.toString();
            if (args.length > 1) {
              flags = args[1].toString();
            }
          }
        }
        try {
          return JSRegExp(pattern, JSRegExpFactory.parseFlags(flags));
        } catch (e) {
          throw JSSyntaxError('Invalid regular expression: $e');
        }
      },
      expectedArgs: 2,
      isConstructor: true,
    );
    final regexpPrototype = JSObject();
    regexpConstructor.setProperty('prototype', regexpPrototype);
    regexpPrototype.defineConstructorProperty(regexpConstructor);
    JSRegExp.setRegExpPrototype(regexpPrototype);
    return regexpConstructor;
  }

  static JSNativeFunction _createDateConstructor() {
    final dateConstructor = DateObject.createDateConstructor();
    final datePrototype = JSObject();
    dateConstructor.setProperty('prototype', datePrototype);
    datePrototype.defineConstructorProperty(dateConstructor);
    return dateConstructor;
  }

  static JSNativeFunction _createBigIntConstructor() {
    final bigintConstructor = JSNativeFunction(
      functionName: 'BigInt',
      nativeImpl: (args) {
        if (args.isEmpty) {
          throw JSTypeError('BigInt constructor requires an argument');
        }
        final value = args[0];
        if (value.isBigInt) {
          return value;
        }
        if (value.isString) {
          final trimmed = value.toString().trim();
          if (trimmed.isEmpty) {
            return JSValueFactory.bigint(BigInt.zero);
          }

          var sign = BigInt.one;
          var digits = trimmed;
          if (digits.startsWith('+')) {
            digits = digits.substring(1);
          } else if (digits.startsWith('-')) {
            sign = BigInt.from(-1);
            digits = digits.substring(1);
          }

          if (digits.isEmpty) {
            throw JSSyntaxError('Invalid BigInt string: $trimmed');
          }

          try {
            if (digits.startsWith('0b') || digits.startsWith('0B')) {
              return JSValueFactory.bigint(
                sign * BigInt.parse(digits.substring(2), radix: 2),
              );
            }
            if (digits.startsWith('0o') || digits.startsWith('0O')) {
              return JSValueFactory.bigint(
                sign * BigInt.parse(digits.substring(2), radix: 8),
              );
            }
            if (digits.startsWith('0x') || digits.startsWith('0X')) {
              return JSValueFactory.bigint(
                sign * BigInt.parse(digits.substring(2), radix: 16),
              );
            }
            return JSValueFactory.bigint(sign * BigInt.parse(digits));
          } catch (_) {
            throw JSSyntaxError('Invalid BigInt string: $trimmed');
          }
        }
        if (value.isNumber) {
          final num = value.toNumber();
          if (num.isNaN || num.isInfinite || num != num.truncateToDouble()) {
            throw JSTypeError('Cannot convert non-integer number to BigInt');
          }
          return JSValueFactory.bigint(BigInt.from(num.toInt()));
        }
        if (value.isBoolean) {
          return JSValueFactory.bigint(
            value.toBoolean() ? BigInt.one : BigInt.zero,
          );
        }
        return JSValueFactory.bigint(BigInt.parse(value.toString()));
      },
    );
    bigintConstructor.setProperty(
      'asIntN',
      JSNativeFunction(
        functionName: 'asIntN',
        nativeImpl: (args) {
          if (args.length < 2 || !args[1].isBigInt) {
            throw JSTypeError('BigInt.asIntN requires 2 arguments');
          }
          final bits = args[0].toNumber().toInt();
          final value = (args[1] as JSBigInt).value;
          if (bits == 0) return JSValueFactory.bigint(BigInt.zero);
          final mask = (BigInt.one << bits) - BigInt.one;
          final masked = value & mask;
          if ((masked & (BigInt.one << (bits - 1))) != BigInt.zero) {
            return JSValueFactory.bigint(masked | ~mask);
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
          if (args.length < 2 || !args[1].isBigInt) {
            throw JSTypeError('BigInt.asUintN requires 2 arguments');
          }
          final bits = args[0].toNumber().toInt();
          final value = (args[1] as JSBigInt).value;
          if (bits == 0) return JSValueFactory.bigint(BigInt.zero);
          return JSValueFactory.bigint(
            value & ((BigInt.one << bits) - BigInt.one),
          );
        },
      ),
    );
    final bigintPrototype = JSObject();
    bigintConstructor.setProperty('prototype', bigintPrototype);
    bigintPrototype.defineConstructorProperty(bigintConstructor);
    return bigintConstructor;
  }

  static JSNativeFunction _createSymbolConstructor() {
    final symbolConstructor = JSNativeFunction(
      functionName: 'Symbol',
      nativeImpl: (args) {
        final description = args.isNotEmpty ? args[0].toString() : null;
        return JSSymbol(description);
      },
    );

    symbolConstructor.setProperty(
      'for',
      JSNativeFunction(
        functionName: 'Symbol.for',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSTypeError('Symbol.for requires 1 argument');
          }
          return JSSymbol.symbolFor(args[0].toString());
        },
      ),
    );
    symbolConstructor.setProperty(
      'keyFor',
      JSNativeFunction(
        functionName: 'Symbol.keyFor',
        nativeImpl: (args) {
          if (args.isEmpty || !args[0].isSymbol) {
            throw JSTypeError('Symbol.keyFor requires a Symbol as argument');
          }
          final symbol = args[0] as JSSymbol;
          return symbol.globalKey != null
              ? JSValueFactory.string(symbol.globalKey!)
              : JSValueFactory.undefined();
        },
      ),
    );

    for (final entry in <String, JSSymbol>{
      'iterator': JSSymbol.iterator,
      'asyncIterator': JSSymbol.asyncIterator,
      'toStringTag': JSSymbol.toStringTag,
      'hasInstance': JSSymbol.hasInstance,
      'species': JSSymbol.species,
      'toPrimitive': JSSymbol.symbolToPrimitive,
      'match': JSSymbol.match,
      'replace': JSSymbol.replace,
      'search': JSSymbol.search,
      'split': JSSymbol.split,
      'isConcatSpreadable': JSSymbol.isConcatSpreadable,
      'unscopables': JSSymbol.unscopables,
      'dispose': JSSymbol.dispose,
      'asyncDispose': JSSymbol.asyncDispose,
    }.entries) {
      symbolConstructor.setProperty(entry.key, entry.value);
    }

    final symbolPrototype = JSObject();
    symbolConstructor.setProperty('prototype', symbolPrototype);
    symbolPrototype.defineConstructorProperty(symbolConstructor);
    symbolPrototype.setProperty(
      'toString',
      JSNativeFunction(
        functionName: 'toString',
        nativeImpl: (args) {
          if (args.isNotEmpty) {
            if (args[0] is JSSymbol) {
              return JSValueFactory.string(args[0].toString());
            }
            if (args[0] is JSSymbolObject) {
              return JSValueFactory.string(
                (args[0] as JSSymbolObject).primitiveValue.toString(),
              );
            }
          }
          return JSValueFactory.string('[Symbol]');
        },
      ),
    );
    symbolPrototype.setProperty(
      'valueOf',
      JSNativeFunction(
        functionName: 'valueOf',
        nativeImpl: (args) {
          if (args.isNotEmpty) {
            if (args[0] is JSSymbol) {
              return args[0];
            }
            if (args[0] is JSSymbolObject) {
              return (args[0] as JSSymbolObject).primitiveValue;
            }
          }
          throw JSTypeError('Symbol.prototype.valueOf called on non-Symbol');
        },
      ),
    );
    JSSymbolObject.setSymbolPrototype(symbolPrototype);
    return symbolConstructor;
  }

  static void _installCollections(Map<String, JSValue> globals) {
    final mapPrototype = JSObject();
    final mapConstructor = JSNativeFunction(
      functionName: 'Map',
      nativeImpl: (args) {
        final map = JSMap();
        map.setPrototype(mapPrototype);
        if (args.isNotEmpty) {
          final iterable = args[0];
          if (iterable is JSArray) {
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
      isConstructor: true,
    );
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
          result.setPrototype(mapPrototype);
          if (items is JSArray) {
            for (var index = 0; index < items.length; index++) {
              if (items.isHole(index)) {
                continue;
              }
              final item = items.getProperty(index.toString());
              final key = JSRuntime.current!.callFunction(callback, [item]);
              var group = result.get(key);
              if (group.isUndefined) {
                group = JSArray([]);
                result.set(key, group);
              }
              if (group is JSArray) {
                group.elements.add(item);
              }
            }
            return result;
          }

          final iterator = IteratorUtils.getIterator(items);
          if (iterator != null) {
            while (true) {
              final nextResult = iterator.next();
              if (nextResult is! JSObject) break;
              if (nextResult.getProperty('done').toBoolean()) break;
              final item = nextResult.getProperty('value');
              final key = JSRuntime.current!.callFunction(callback, [item]);
              var group = result.get(key);
              if (group.isUndefined) {
                group = JSArray([]);
                result.set(key, group);
              }
              if (group is JSArray) {
                group.elements.add(item);
              }
            }
            return result;
          }

          if (items is JSObject) {
            for (final propertyName in items.getPropertyNames()) {
              final item = items.getProperty(propertyName);
              final key = JSRuntime.current!.callFunction(callback, [item]);
              var group = result.get(key);
              if (group.isUndefined) {
                group = JSArray([]);
                result.set(key, group);
              }
              if (group is JSArray) {
                group.elements.add(item);
              }
            }
            return result;
          }

          throw JSTypeError('Map.groupBy: items must be iterable or an object');
        },
      ),
    );
    mapConstructor.setProperty('prototype', mapPrototype);
    mapPrototype.defineConstructorProperty(mapConstructor);
    mapConstructor.defineProperty(
      JSSymbol.species.propertyKey,
      PropertyDescriptor(
        getter: JSNativeFunction(
          functionName: 'get [Symbol.species]',
          nativeImpl: (args) =>
              args.isNotEmpty ? args[0] : JSValueFactory.undefined(),
        ),
        setter: null,
        enumerable: false,
        configurable: true,
        hasValueProperty: false,
      ),
    );
    _define(globals, 'Map', mapConstructor);

    final setPrototype = JSObject();
    final setConstructor = JSNativeFunction(
      functionName: 'Set',
      nativeImpl: (args) {
        final set = JSSet();
        set.setPrototype(setPrototype);
        if (args.isNotEmpty) {
          final iterable = args[0];
          if (iterable is JSArray) {
            for (final element in iterable.elements) {
              set.add(element);
            }
          }
        }
        return set;
      },
      expectedArgs: 0,
      isConstructor: true,
    );
    setConstructor.setProperty(
      'isDisjointFrom',
      JSNativeFunction(
        functionName: 'Set.isDisjointFrom',
        nativeImpl: (args) {
          if (args.length < 2 || args[0] is! JSSet || args[1] is! JSSet) {
            throw JSError('Both arguments must be Set objects');
          }
          final setA = args[0] as JSSet;
          final setB = args[1] as JSSet;
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
          if (args.length < 2 || args[0] is! JSSet || args[1] is! JSSet) {
            throw JSError('Both arguments must be Set objects');
          }
          final subset = args[0] as JSSet;
          final superset = args[1] as JSSet;
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
          if (args.length < 2 || args[0] is! JSSet || args[1] is! JSSet) {
            throw JSError('Both arguments must be Set objects');
          }
          final superset = args[0] as JSSet;
          final subset = args[1] as JSSet;
          for (final element in subset.values) {
            if (!(superset.has(element) as JSBoolean).value) {
              return JSValueFactory.boolean(false);
            }
          }
          return JSValueFactory.boolean(true);
        },
      ),
    );
    setConstructor.setProperty('prototype', setPrototype);
    setPrototype.defineConstructorProperty(setConstructor);
    setConstructor.defineProperty(
      JSSymbol.species.propertyKey,
      PropertyDescriptor(
        getter: JSNativeFunction(
          functionName: 'get [Symbol.species]',
          nativeImpl: (args) =>
              args.isNotEmpty ? args[0] : JSValueFactory.undefined(),
        ),
        setter: null,
        enumerable: false,
        configurable: true,
        hasValueProperty: false,
      ),
    );
    _define(globals, 'Set', setConstructor);
  }

  static void _installWeakCollections(Map<String, JSValue> globals) {
    final weakMapPrototype = JSObject();
    final weakMapConstructor = JSNativeFunction(
      functionName: 'WeakMap',
      nativeImpl: (args) {
        final weakMap = JSWeakMap();
        weakMap.setPrototype(weakMapPrototype);
        if (args.isNotEmpty && args[0] is JSArray) {
          for (final pair in (args[0] as JSArray).elements) {
            if (pair is JSArray && pair.elements.length >= 2) {
              final key = pair.elements[0];
              if (key is JSObject) {
                weakMap.setValue(key, pair.elements[1]);
              }
            }
          }
        }
        return weakMap;
      },
      expectedArgs: 0,
      isConstructor: true,
    );
    weakMapConstructor.setProperty('prototype', weakMapPrototype);
    weakMapPrototype.defineConstructorProperty(weakMapConstructor);
    _define(globals, 'WeakMap', weakMapConstructor);

    final weakSetPrototype = JSObject();
    final weakSetConstructor = JSNativeFunction(
      functionName: 'WeakSet',
      nativeImpl: (args) {
        final weakSet = JSWeakSet();
        weakSet.setPrototype(weakSetPrototype);
        if (args.isNotEmpty && args[0] is JSArray) {
          for (final value in (args[0] as JSArray).elements) {
            if (value is JSObject) {
              weakSet.addValue(value);
            }
          }
        }
        return weakSet;
      },
      expectedArgs: 0,
      isConstructor: true,
    );
    weakSetConstructor.setProperty('prototype', weakSetPrototype);
    weakSetPrototype.defineConstructorProperty(weakSetConstructor);
    _define(globals, 'WeakSet', weakSetConstructor);
  }

  static void _installProxy(Map<String, JSValue> globals) {
    final proxyPrototype = JSObject();
    final proxyConstructor = JSNativeFunction(
      functionName: 'Proxy',
      nativeImpl: (args) {
        if (args.length < 2) {
          throw JSTypeError('Proxy constructor requires at least 2 arguments');
        }
        final proxy = JSProxy(args[0], args[1]);
        proxy.setInternalPrototype(proxyPrototype);
        return proxy;
      },
      expectedArgs: 2,
      isConstructor: true,
    );
    proxyConstructor.setProperty('prototype', JSValueFactory.undefined());
    proxyPrototype.defineConstructorProperty(proxyConstructor);
    proxyConstructor.setProperty(
      'revocable',
      JSNativeFunction(
        functionName: 'Proxy.revocable',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError('Proxy.revocable requires at least 2 arguments');
          }
          final proxy = JSProxy(args[0], args[1]);
          proxy.setInternalPrototype(proxyPrototype);
          final revocable = JSObject();
          revocable.setProperty('proxy', proxy);
          revocable.setProperty(
            'revoke',
            JSNativeFunction(
              functionName: 'revoke',
              nativeImpl: (_) => JSValueFactory.undefined(),
            ),
          );
          return revocable;
        },
      ),
    );
    _define(globals, 'Proxy', proxyConstructor);
  }

  static void _installReflect(Map<String, JSValue> globals) {
    final reflectObject = JSObject();
    reflectObject.setProperty(
      'get',
      JSNativeFunction(
        functionName: 'Reflect.get',
        nativeImpl: (args) {
          if (args.length < 2 || args[0] is! JSObject) {
            throw JSTypeError('Reflect.get target must be an object');
          }
          return (args[0] as JSObject).getProperty(args[1].toString());
        },
      ),
    );
    reflectObject.setProperty(
      'set',
      JSNativeFunction(
        functionName: 'Reflect.set',
        nativeImpl: (args) {
          if (args.length < 3 || args[0] is! JSObject) {
            throw JSTypeError('Reflect.set target must be an object');
          }
          final target = args[0] as JSObject;
          final propertyKey = args[1].toString();
          final descriptor = target.getOwnPropertyDescriptor(propertyKey);
          if (descriptor != null && descriptor.isData && !descriptor.writable) {
            return JSValueFactory.boolean(false);
          }
          try {
            target.setProperty(propertyKey, args[2]);
            return JSValueFactory.boolean(true);
          } on JSError {
            return JSValueFactory.boolean(false);
          }
        },
      ),
    );
    reflectObject.setProperty(
      'has',
      JSNativeFunction(
        functionName: 'Reflect.has',
        nativeImpl: (args) {
          if (args.length < 2 || args[0] is! JSObject) {
            throw JSTypeError('Reflect.has target must be an object');
          }
          return JSValueFactory.boolean(
            (args[0] as JSObject).hasProperty(args[1].toString()),
          );
        },
      ),
    );
    reflectObject.setProperty(
      'deleteProperty',
      JSNativeFunction(
        functionName: 'Reflect.deleteProperty',
        nativeImpl: (args) {
          if (args.length < 2 || args[0] is! JSObject) {
            throw JSTypeError(
              'Reflect.deleteProperty target must be an object',
            );
          }
          return JSValueFactory.boolean(
            (args[0] as JSObject).deleteProperty(args[1].toString()),
          );
        },
      ),
    );
    reflectObject.setProperty(
      'apply',
      JSNativeFunction(
        functionName: 'Reflect.apply',
        nativeImpl: (args) {
          if (args.length < 3 ||
              args[0] is! JSFunction ||
              args[2] is! JSArray) {
            throw JSTypeError(
              'Reflect.apply requires function, thisArgument, and array',
            );
          }
          final runtime = JSRuntime.current;
          if (runtime == null) {
            throw JSError('No runtime available for Reflect.apply');
          }
          return runtime.callFunction(
            args[0],
            (args[2] as JSArray).elements,
            args[1],
          );
        },
      ),
    );
    reflectObject.setProperty(
      'construct',
      JSNativeFunction(
        functionName: 'Reflect.construct',
        nativeImpl: (args) {
          if (args.length < 2 ||
              args[0] is! JSFunction ||
              args[1] is! JSArray) {
            throw JSTypeError(
              'Reflect.construct requires constructor and arguments array',
            );
          }
          final target = args[0] as JSFunction;
          final argumentsList = args[1] as JSArray;
          final newTarget = (args.length > 2 ? args[2] : target);
          final newTargetIsConstructor =
              (newTarget is JSFunction && newTarget.isConstructor) ||
              newTarget is JSProxy;
          if (!target.isConstructor || !newTargetIsConstructor) {
            throw JSTypeError(
              'Reflect.construct target and newTarget must be constructors',
            );
          }
          final runtime = JSRuntime.current;
          if (runtime == null) {
            throw JSError('No runtime available for Reflect.construct');
          }

          JSObject? getConstructPrototype(
            JSValue candidate,
            JSFunction targetFn,
          ) {
            final prototypeValue =
                (candidate as dynamic).getProperty('prototype') as JSValue;
            if (prototypeValue is JSObject) {
              return prototypeValue;
            }

            dynamic realm = candidate is JSFunction
                ? candidate.getInternalSlot('Realm')
                : null;
            if (realm == null) {
              try {
                final ctor =
                    (candidate as dynamic).getProperty('constructor')
                        as JSValue;
                if (ctor is JSFunction) {
                  realm = ctor.getInternalSlot('Realm');
                }
              } catch (_) {}
            }
            if (realm != null) {
              try {
                final intrinsicCtor =
                    (realm as dynamic).getGlobal(targetFn.functionName)
                        as JSValue;
                final intrinsicProto =
                    (intrinsicCtor as dynamic).getProperty('prototype')
                        as JSValue;
                if (intrinsicProto is JSObject) {
                  return intrinsicProto;
                }
              } catch (_) {}
            }

            final targetProto = targetFn.getProperty('prototype');
            return targetProto is JSObject ? targetProto : null;
          }

          final newObject = JSObject();
          JSObject? constructProto;
          JSValue result;
          if (target.functionName == 'Promise') {
            result = JSNativeFunction.withConstructorCall(
              () => runtime.callFunction(
                target,
                argumentsList.elements,
                newObject,
              ),
            );
            constructProto = getConstructPrototype(newTarget, target);
            if (constructProto != null) {
              newObject.setPrototype(constructProto);
            }
          } else {
            constructProto = getConstructPrototype(newTarget, target);
            if (constructProto != null) {
              newObject.setPrototype(constructProto);
            }
            newObject.defineProperty(
              '__reflectConstructInstance__',
              PropertyDescriptor(
                value: JSValueFactory.boolean(true),
                writable: true,
                enumerable: false,
                configurable: true,
              ),
            );
            result = JSNativeFunction.withConstructorCall(
              () => runtime.callFunction(
                target,
                argumentsList.elements,
                newObject,
              ),
            );
          }
          if (result is JSObject) {
            if (target.functionName == 'AggregateError' &&
                constructProto != null) {
              result.setPrototype(constructProto);
            }
            result.setProperty('constructor', newTarget);
            return result;
          }
          newObject.setProperty('constructor', newTarget);
          return newObject;
        },
      ),
    );
    reflectObject.setProperty(
      'getPrototypeOf',
      JSNativeFunction(
        functionName: 'Reflect.getPrototypeOf',
        nativeImpl: (args) {
          if (args.isEmpty || args[0] is! JSObject) {
            throw JSTypeError(
              'Reflect.getPrototypeOf target must be an object',
            );
          }
          return (args[0] as JSObject).getPrototype() ??
              JSValueFactory.nullValue();
        },
      ),
    );
    reflectObject.setProperty(
      'setPrototypeOf',
      JSNativeFunction(
        functionName: 'Reflect.setPrototypeOf',
        nativeImpl: (args) {
          if (args.length < 2 || args[0] is! JSObject) {
            throw JSTypeError(
              'Reflect.setPrototypeOf target must be an object',
            );
          }
          final prototype = args[1];
          if (prototype is JSObject || prototype.isNull) {
            (args[0] as JSObject).setPrototype(
              prototype is JSObject ? prototype : null,
            );
            return JSValueFactory.boolean(true);
          }
          throw JSTypeError(
            'Reflect.setPrototypeOf prototype must be an object or null',
          );
        },
      ),
    );
    reflectObject.setProperty(
      'isExtensible',
      JSNativeFunction(
        functionName: 'Reflect.isExtensible',
        nativeImpl: (args) {
          if (args.isEmpty || args[0] is! JSObject) {
            throw JSTypeError('Reflect.isExtensible target must be an object');
          }
          return JSValueFactory.boolean((args[0] as JSObject).isExtensible);
        },
      ),
    );
    reflectObject.setProperty(
      'preventExtensions',
      JSNativeFunction(
        functionName: 'Reflect.preventExtensions',
        nativeImpl: (args) {
          if (args.isEmpty || args[0] is! JSObject) {
            throw JSTypeError(
              'Reflect.preventExtensions target must be an object',
            );
          }
          (args[0] as JSObject).isExtensible = false;
          return JSValueFactory.boolean(true);
        },
      ),
    );
    reflectObject.setProperty(
      'getOwnPropertyDescriptor',
      JSNativeFunction(
        functionName: 'Reflect.getOwnPropertyDescriptor',
        nativeImpl: (args) {
          if (args.length < 2 || args[0] is! JSObject) {
            throw JSTypeError(
              'Reflect.getOwnPropertyDescriptor target must be an object',
            );
          }
          final descriptor = (args[0] as JSObject).getOwnPropertyDescriptor(
            args[1].toString(),
          );
          if (descriptor == null) {
            return JSValueFactory.undefined();
          }
          final descObject = JSObject();
          if (descriptor.value != null) {
            descObject.setProperty('value', descriptor.value!);
          }
          if (descriptor.getter != null) {
            descObject.setProperty('get', descriptor.getter!);
          }
          if (descriptor.setter != null) {
            descObject.setProperty('set', descriptor.setter!);
          }
          descObject.setProperty(
            'writable',
            JSValueFactory.boolean(descriptor.writable),
          );
          descObject.setProperty(
            'enumerable',
            JSValueFactory.boolean(descriptor.enumerable),
          );
          descObject.setProperty(
            'configurable',
            JSValueFactory.boolean(descriptor.configurable),
          );
          return descObject;
        },
      ),
    );
    reflectObject.setProperty(
      'defineProperty',
      JSNativeFunction(
        functionName: 'Reflect.defineProperty',
        nativeImpl: (args) {
          if (args.length < 3 || args[0] is! JSObject || args[2] is! JSObject) {
            throw JSTypeError(
              'Reflect.defineProperty requires object target and descriptor',
            );
          }
          final target = args[0] as JSObject;
          final attributes = args[2] as JSObject;
          final getter = attributes.getProperty('get');
          final setter = attributes.getProperty('set');
          final hasValue = attributes.hasProperty('value');
          final descriptor = PropertyDescriptor(
            value: hasValue ? attributes.getProperty('value') : null,
            getter: getter is JSFunction ? getter : null,
            setter: setter is JSFunction ? setter : null,
            writable: attributes.getProperty('writable').toBoolean(),
            enumerable: attributes.getProperty('enumerable').toBoolean(),
            configurable: attributes.getProperty('configurable').toBoolean(),
            hasValueProperty: hasValue,
          );
          try {
            target.defineProperty(args[1].toString(), descriptor);
            return JSValueFactory.boolean(true);
          } on JSError {
            return JSValueFactory.boolean(false);
          }
        },
      ),
    );
    reflectObject.setProperty(
      'ownKeys',
      JSNativeFunction(
        functionName: 'Reflect.ownKeys',
        nativeImpl: (args) {
          if (args.isEmpty || args[0] is! JSObject) {
            throw JSTypeError('Reflect.ownKeys target must be an object');
          }
          return JSArray(
            (args[0] as JSObject)
                .getPropertyNames()
                .map(JSValueFactory.string)
                .toList(),
          );
        },
      ),
    );
    _define(globals, 'Reflect', reflectObject);
  }

  static void _installIntl(Map<String, JSValue> globals) {
    _define(globals, 'Intl', IntlObject.createIntlObject());
  }

  static void _installTemporal(Map<String, JSValue> globals) {
    _define(globals, 'Temporal', getTemporalNamespace());
  }

  static void _installMissingBuiltins(Map<String, JSValue> globals) {
    _define(globals, 'WeakRef', createWeakRefConstructor());
    _define(
      globals,
      'FinalizationRegistry',
      createFinalizationRegistryConstructor(),
    );
    _define(globals, 'DisposableStack', createDisposableStackConstructor());
    _define(
      globals,
      'AsyncDisposableStack',
      createAsyncDisposableStackConstructor(),
    );
    _define(globals, 'Atomics', createAtomicsObject());
  }

  static int _safeToInt(double value) {
    if (value.isNaN) return 0;
    if (value.isInfinite) {
      return value.isNegative ? -0x1FFFFFFFFFFFFF : 0x1FFFFFFFFFFFFF;
    }
    return value.truncate();
  }

  static void _installTypedArrays(Map<String, JSValue> globals) {
    final arrayConstructor = globals['Array'] as JSNativeFunction;
    final arrayPrototype =
        arrayConstructor.getProperty('prototype') as JSObject;

    void setupTypedArrayPrototype(
      JSNativeFunction constructor,
      JSObject prototype, {
      int bytesPerElement = 0,
      bool inheritArrayPrototype = true,
    }) {
      if (inheritArrayPrototype) {
        prototype.setPrototype(arrayPrototype);
      }
      prototype.defineConstructorProperty(constructor);
      constructor.setProperty('prototype', prototype);
      if (bytesPerElement > 0) {
        final bytes = JSValueFactory.number(bytesPerElement.toDouble());
        constructor.setProperty('BYTES_PER_ELEMENT', bytes);
        prototype.setProperty('BYTES_PER_ELEMENT', bytes);
      }
    }

    JSObject attachPrototype(JSObject value, JSObject prototype) {
      value.setPrototype(prototype);
      return value;
    }

    JSObject buildNumericTypedArray(
      List<JSValue> args,
      String name,
      int bytesPerElement,
      JSObject Function(int length) fromLength,
      JSObject Function(JSArrayBuffer buffer, int byteOffset, int length)
      fromBuffer,
      JSObject Function(List<double> values) fromArray,
      JSObject prototype,
    ) {
      if (args.isEmpty) {
        return attachPrototype(fromLength(0), prototype);
      }

      final arg = args[0];
      if (arg.isNumber) {
        final length = _safeToInt(arg.toNumber());
        if (length < 0) {
          throw JSRangeError('Invalid typed array length');
        }
        return attachPrototype(fromLength(length), prototype);
      }

      if (arg is JSArrayBuffer) {
        final byteOffset = args.length > 1 ? _safeToInt(args[1].toNumber()) : 0;
        final length = args.length > 2
            ? _safeToInt(args[2].toNumber())
            : ((arg.byteLength - byteOffset) ~/ bytesPerElement);
        return attachPrototype(fromBuffer(arg, byteOffset, length), prototype);
      }

      if (arg is JSArray) {
        final values = arg.elements.map((e) => e.toNumber()).toList();
        return attachPrototype(fromArray(values), prototype);
      }

      throw JSTypeError('Invalid argument to $name constructor');
    }

    JSObject buildBigIntTypedArray(
      List<JSValue> args,
      String name,
      JSObject Function(int length) fromLength,
      JSObject Function(JSArrayBuffer buffer, int byteOffset, int length)
      fromBuffer,
      JSObject Function(List<BigInt> values) fromArray,
      JSObject prototype,
    ) {
      if (args.isEmpty) {
        return attachPrototype(fromLength(0), prototype);
      }

      final arg = args[0];
      if (arg.isNumber) {
        final length = _safeToInt(arg.toNumber());
        if (length < 0) {
          throw JSRangeError('Invalid typed array length');
        }
        return attachPrototype(fromLength(length), prototype);
      }

      if (arg is JSArrayBuffer) {
        final byteOffset = args.length > 1 ? _safeToInt(args[1].toNumber()) : 0;
        final length = args.length > 2
            ? _safeToInt(args[2].toNumber())
            : ((arg.byteLength - byteOffset) ~/ 8);
        return attachPrototype(fromBuffer(arg, byteOffset, length), prototype);
      }

      if (arg is JSArray) {
        final values = arg.elements.map((e) {
          if (e is JSBigInt) {
            return e.value;
          }
          return BigInt.from(e.toNumber().truncate());
        }).toList();
        return attachPrototype(fromArray(values), prototype);
      }

      throw JSTypeError('Invalid argument to $name constructor');
    }

    final arrayBufferPrototype = JSObject();
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
        return attachPrototype(JSArrayBuffer(byteLength), arrayBufferPrototype);
      },
      expectedArgs: 1,
      isConstructor: true,
    );
    setupTypedArrayPrototype(arrayBufferConstructor, arrayBufferPrototype);
    _define(globals, 'ArrayBuffer', arrayBufferConstructor);

    final int8ArrayPrototype = JSObject();
    final int8ArrayConstructor = JSNativeFunction(
      functionName: 'Int8Array',
      nativeImpl: (args) => buildNumericTypedArray(
        args,
        'Int8Array',
        1,
        JSInt8Array.fromLength,
        (buffer, byteOffset, length) =>
            JSInt8Array(buffer: buffer, byteOffset: byteOffset, length: length),
        JSInt8Array.fromArray,
        int8ArrayPrototype,
      ),
      expectedArgs: 1,
      isConstructor: true,
    );
    setupTypedArrayPrototype(
      int8ArrayConstructor,
      int8ArrayPrototype,
      bytesPerElement: 1,
    );
    _define(globals, 'Int8Array', int8ArrayConstructor);

    final uint8ArrayPrototype = JSObject();
    final uint8ArrayConstructor = JSNativeFunction(
      functionName: 'Uint8Array',
      nativeImpl: (args) => buildNumericTypedArray(
        args,
        'Uint8Array',
        1,
        JSUint8Array.fromLength,
        (buffer, byteOffset, length) => JSUint8Array(
          buffer: buffer,
          byteOffset: byteOffset,
          length: length,
        ),
        JSUint8Array.fromArray,
        uint8ArrayPrototype,
      ),
      expectedArgs: 1,
      isConstructor: true,
    );
    setupTypedArrayPrototype(
      uint8ArrayConstructor,
      uint8ArrayPrototype,
      bytesPerElement: 1,
    );
    _define(globals, 'Uint8Array', uint8ArrayConstructor);

    final uint8ClampedArrayPrototype = JSObject();
    final uint8ClampedArrayConstructor = JSNativeFunction(
      functionName: 'Uint8ClampedArray',
      nativeImpl: (args) => buildNumericTypedArray(
        args,
        'Uint8ClampedArray',
        1,
        JSUint8ClampedArray.fromLength,
        (buffer, byteOffset, length) => JSUint8ClampedArray(
          buffer: buffer,
          byteOffset: byteOffset,
          length: length,
        ),
        JSUint8ClampedArray.fromArray,
        uint8ClampedArrayPrototype,
      ),
      expectedArgs: 1,
      isConstructor: true,
    );
    setupTypedArrayPrototype(
      uint8ClampedArrayConstructor,
      uint8ClampedArrayPrototype,
      bytesPerElement: 1,
    );
    _define(globals, 'Uint8ClampedArray', uint8ClampedArrayConstructor);

    final int16ArrayPrototype = JSObject();
    final int16ArrayConstructor = JSNativeFunction(
      functionName: 'Int16Array',
      nativeImpl: (args) => buildNumericTypedArray(
        args,
        'Int16Array',
        2,
        JSInt16Array.fromLength,
        (buffer, byteOffset, length) => JSInt16Array(
          buffer: buffer,
          byteOffset: byteOffset,
          length: length,
        ),
        JSInt16Array.fromArray,
        int16ArrayPrototype,
      ),
      expectedArgs: 1,
      isConstructor: true,
    );
    setupTypedArrayPrototype(
      int16ArrayConstructor,
      int16ArrayPrototype,
      bytesPerElement: 2,
    );
    _define(globals, 'Int16Array', int16ArrayConstructor);

    final uint16ArrayPrototype = JSObject();
    final uint16ArrayConstructor = JSNativeFunction(
      functionName: 'Uint16Array',
      nativeImpl: (args) => buildNumericTypedArray(
        args,
        'Uint16Array',
        2,
        JSUint16Array.fromLength,
        (buffer, byteOffset, length) => JSUint16Array(
          buffer: buffer,
          byteOffset: byteOffset,
          length: length,
        ),
        JSUint16Array.fromArray,
        uint16ArrayPrototype,
      ),
      expectedArgs: 1,
      isConstructor: true,
    );
    setupTypedArrayPrototype(
      uint16ArrayConstructor,
      uint16ArrayPrototype,
      bytesPerElement: 2,
    );
    _define(globals, 'Uint16Array', uint16ArrayConstructor);

    final int32ArrayPrototype = JSObject();
    final int32ArrayConstructor = JSNativeFunction(
      functionName: 'Int32Array',
      nativeImpl: (args) => buildNumericTypedArray(
        args,
        'Int32Array',
        4,
        JSInt32Array.fromLength,
        (buffer, byteOffset, length) => JSInt32Array(
          buffer: buffer,
          byteOffset: byteOffset,
          length: length,
        ),
        JSInt32Array.fromArray,
        int32ArrayPrototype,
      ),
      expectedArgs: 1,
      isConstructor: true,
    );
    setupTypedArrayPrototype(
      int32ArrayConstructor,
      int32ArrayPrototype,
      bytesPerElement: 4,
    );
    _define(globals, 'Int32Array', int32ArrayConstructor);

    final uint32ArrayPrototype = JSObject();
    final uint32ArrayConstructor = JSNativeFunction(
      functionName: 'Uint32Array',
      nativeImpl: (args) => buildNumericTypedArray(
        args,
        'Uint32Array',
        4,
        JSUint32Array.fromLength,
        (buffer, byteOffset, length) => JSUint32Array(
          buffer: buffer,
          byteOffset: byteOffset,
          length: length,
        ),
        JSUint32Array.fromArray,
        uint32ArrayPrototype,
      ),
      expectedArgs: 1,
      isConstructor: true,
    );
    setupTypedArrayPrototype(
      uint32ArrayConstructor,
      uint32ArrayPrototype,
      bytesPerElement: 4,
    );
    _define(globals, 'Uint32Array', uint32ArrayConstructor);

    final float16ArrayPrototype = JSObject();
    final float16ArrayConstructor = JSNativeFunction(
      functionName: 'Float16Array',
      nativeImpl: (args) => buildNumericTypedArray(
        args,
        'Float16Array',
        2,
        JSFloat16Array.fromLength,
        (buffer, byteOffset, length) => JSFloat16Array(
          buffer: buffer,
          byteOffset: byteOffset,
          length: length,
        ),
        JSFloat16Array.fromArray,
        float16ArrayPrototype,
      ),
      expectedArgs: 1,
      isConstructor: true,
    );
    setupTypedArrayPrototype(
      float16ArrayConstructor,
      float16ArrayPrototype,
      bytesPerElement: 2,
    );
    _define(globals, 'Float16Array', float16ArrayConstructor);

    final float32ArrayPrototype = JSObject();
    final float32ArrayConstructor = JSNativeFunction(
      functionName: 'Float32Array',
      nativeImpl: (args) => buildNumericTypedArray(
        args,
        'Float32Array',
        4,
        JSFloat32Array.fromLength,
        (buffer, byteOffset, length) => JSFloat32Array(
          buffer: buffer,
          byteOffset: byteOffset,
          length: length,
        ),
        JSFloat32Array.fromArray,
        float32ArrayPrototype,
      ),
      expectedArgs: 1,
      isConstructor: true,
    );
    setupTypedArrayPrototype(
      float32ArrayConstructor,
      float32ArrayPrototype,
      bytesPerElement: 4,
    );
    _define(globals, 'Float32Array', float32ArrayConstructor);

    final float64ArrayPrototype = JSObject();
    final float64ArrayConstructor = JSNativeFunction(
      functionName: 'Float64Array',
      nativeImpl: (args) => buildNumericTypedArray(
        args,
        'Float64Array',
        8,
        JSFloat64Array.fromLength,
        (buffer, byteOffset, length) => JSFloat64Array(
          buffer: buffer,
          byteOffset: byteOffset,
          length: length,
        ),
        JSFloat64Array.fromArray,
        float64ArrayPrototype,
      ),
      expectedArgs: 1,
      isConstructor: true,
    );
    setupTypedArrayPrototype(
      float64ArrayConstructor,
      float64ArrayPrototype,
      bytesPerElement: 8,
    );
    _define(globals, 'Float64Array', float64ArrayConstructor);

    final bigInt64ArrayPrototype = JSObject();
    final bigInt64ArrayConstructor = JSNativeFunction(
      functionName: 'BigInt64Array',
      nativeImpl: (args) => buildBigIntTypedArray(
        args,
        'BigInt64Array',
        JSBigInt64Array.fromLength,
        (buffer, byteOffset, length) => JSBigInt64Array(
          buffer: buffer,
          byteOffset: byteOffset,
          length: length,
        ),
        JSBigInt64Array.fromArray,
        bigInt64ArrayPrototype,
      ),
      expectedArgs: 1,
      isConstructor: true,
    );
    setupTypedArrayPrototype(
      bigInt64ArrayConstructor,
      bigInt64ArrayPrototype,
      bytesPerElement: 8,
    );
    _define(globals, 'BigInt64Array', bigInt64ArrayConstructor);

    final bigUint64ArrayPrototype = JSObject();
    final bigUint64ArrayConstructor = JSNativeFunction(
      functionName: 'BigUint64Array',
      nativeImpl: (args) => buildBigIntTypedArray(
        args,
        'BigUint64Array',
        JSBigUint64Array.fromLength,
        (buffer, byteOffset, length) => JSBigUint64Array(
          buffer: buffer,
          byteOffset: byteOffset,
          length: length,
        ),
        JSBigUint64Array.fromArray,
        bigUint64ArrayPrototype,
      ),
      expectedArgs: 1,
      isConstructor: true,
    );
    setupTypedArrayPrototype(
      bigUint64ArrayConstructor,
      bigUint64ArrayPrototype,
      bytesPerElement: 8,
    );
    _define(globals, 'BigUint64Array', bigUint64ArrayConstructor);

    final dataViewPrototype = JSObject();
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
        final view = JSDataView(
          buffer: buffer,
          byteOffset: args.length > 1 ? _safeToInt(args[1].toNumber()) : 0,
          byteLength: args.length > 2 ? _safeToInt(args[2].toNumber()) : null,
        );
        return attachPrototype(view, dataViewPrototype);
      },
      expectedArgs: 1,
      isConstructor: true,
    );
    setupTypedArrayPrototype(
      dataViewConstructor,
      dataViewPrototype,
      inheritArrayPrototype: false,
    );
    _define(globals, 'DataView', dataViewConstructor);
  }

  static void _installPromise(Map<String, JSValue> globals) {
    final promiseConstructor = JSNativeFunction(
      functionName: 'Promise',
      nativeImpl: (args) {
        if (!JSNativeFunction.isConstructorCallActive) {
          throw JSTypeError('Promise constructor requires new');
        }
        final existingInstance = args.isNotEmpty && args[0] is JSObject
            ? args[0] as JSObject
            : null;
        final executorIndex = existingInstance != null ? 1 : 0;
        if (args.length <= executorIndex ||
            args[executorIndex] is! JSFunction) {
          throw JSTypeError('Promise constructor requires 1 function argument');
        }
        final promise = JSPromise(args[executorIndex] as JSFunction);
        if (existingInstance != null) {
          existingInstance.setInternalSlot('[[PromiseInstance]]', promise);
          return existingInstance;
        }
        return promise;
      },
      expectedArgs: 1,
      isConstructor: true,
    );

    promiseConstructor.defineProperty(
      'resolve',
      PropertyDescriptor(
        value: PromiseStaticMethod(
          functionName: 'resolve',
          expectedArgs: 1,
          promiseNativeImpl: PromisePrototype.resolveWithThis,
          isCtorFn: false,
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
          isCtorFn: false,
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
          promiseNativeImpl: PromisePrototype.allWithThis,
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
          promiseNativeImpl: PromisePrototype.raceWithThis,
          isCtorFn: false,
        ),
        enumerable: false,
        configurable: true,
        writable: true,
      ),
    );
    promiseConstructor.defineProperty(
      'allSettled',
      PropertyDescriptor(
        value: PromiseStaticMethod(
          functionName: 'allSettled',
          expectedArgs: 1,
          promiseNativeImpl: PromisePrototype.allSettledWithThis,
          isCtorFn: false,
        ),
        enumerable: false,
        configurable: true,
        writable: true,
      ),
    );
    promiseConstructor.defineProperty(
      'any',
      PropertyDescriptor(
        value: PromiseStaticMethod(
          functionName: 'any',
          expectedArgs: 1,
          promiseNativeImpl: PromisePrototype.anyWithThis,
          isCtorFn: false,
        ),
        enumerable: false,
        configurable: true,
        writable: true,
      ),
    );
    promiseConstructor.defineProperty(
      'withResolvers',
      PropertyDescriptor(
        value: PromiseStaticMethod(
          functionName: 'withResolvers',
          expectedArgs: 0,
          isCtorFn: false,
          promiseNativeImpl: PromisePrototype.withResolversWithThis,
        ),
        enumerable: false,
        configurable: true,
        writable: true,
      ),
    );
    promiseConstructor.defineProperty(
      'try',
      PropertyDescriptor(
        value: PromiseStaticMethod(
          functionName: 'try',
          expectedArgs: 1,
          isCtorFn: false,
          promiseNativeImpl: PromisePrototype.tryWithThis,
        ),
        enumerable: false,
        configurable: true,
        writable: true,
      ),
    );
    promiseConstructor.defineProperty(
      JSSymbol.species.propertyKey,
      PropertyDescriptor(
        getter: JSNativeFunction(
          functionName: 'get [Symbol.species]',
          expectedArgs: 0,
          nativeImpl: (args) =>
              args.isNotEmpty ? args[0] : JSValueFactory.undefined(),
        ),
        enumerable: false,
        configurable: true,
      ),
    );

    JSObject? errorProto;
    try {
      final errorConstructor = globals['Error'];
      if (errorConstructor is JSFunction) {
        final proto = errorConstructor.getProperty('prototype');
        if (proto is JSObject) {
          errorProto = proto;
        }
      }
    } catch (_) {}

    JSArray iterableToArray(JSValue iterable) {
      if (iterable.isNull || iterable.isUndefined) {
        throw JSTypeError('AggregateError errors is not iterable');
      }

      JSValue target = iterable;
      if (target is! JSObject && target is! JSFunction) {
        target = target.toObject();
      }

      final iteratorMethod =
          (target as dynamic).getProperty(JSSymbol.iterator.propertyKey)
              as JSValue;
      if (iteratorMethod is! JSFunction) {
        final directIterator = IteratorUtils.getIterator(iterable);
        if (directIterator == null) {
          throw JSTypeError('AggregateError errors is not iterable');
        }
        final values = <JSValue>[];
        while (true) {
          final nextResult = directIterator.next();
          if (nextResult is! JSObject) {
            throw JSTypeError('Iterator result is not an object');
          }
          if (nextResult.getProperty('done').toBoolean()) {
            break;
          }
          values.add(nextResult.getProperty('value'));
        }
        return JSValueFactory.array(values);
      }

      final runtime = JSRuntime.current;
      if (runtime == null) {
        throw JSError('No runtime available for AggregateError iteration');
      }

      final iterator = runtime.callFunction(
        iteratorMethod,
        const <JSValue>[],
        target,
      );
      if (iterator is! JSObject && iterator is! JSFunction) {
        throw JSTypeError('Iterator result is not an object');
      }

      final values = <JSValue>[];
      while (true) {
        final nextMethod = (iterator as dynamic).getProperty('next') as JSValue;
        if (nextMethod is! JSFunction) {
          throw JSTypeError('Iterator next is not callable');
        }
        final nextResult = runtime.callFunction(
          nextMethod,
          const <JSValue>[],
          iterator,
        );
        if (nextResult is! JSObject) {
          throw JSTypeError('Iterator result is not an object');
        }
        if (nextResult.getProperty('done').toBoolean()) {
          break;
        }
        values.add(nextResult.getProperty('value'));
      }
      return JSValueFactory.array(values);
    }

    String toAggregateErrorString(JSValue value) {
      if (value is JSSymbol || value.isSymbol) {
        throw JSTypeError('Cannot convert a Symbol value to a string');
      }

      if (value is! JSObject && value is! JSFunction) {
        return JSConversion.jsToString(value);
      }

      final runtime = JSRuntime.current;
      final objectValue = value;

      JSValue? getMethod(JSValue target, String name) {
        final method = (target as dynamic).getProperty(name) as JSValue;
        return method.isUndefined || method.isNull ? null : method;
      }

      JSValue callMethod(JSValue method, List<JSValue> args, JSValue receiver) {
        if (method is! JSFunction && method is! JSNativeFunction) {
          throw JSTypeError('$method is not a function');
        }
        if (runtime == null) {
          throw JSError(
            'No runtime available for AggregateError message conversion',
          );
        }
        return runtime.callFunction(method, args, receiver);
      }

      final toPrimitive = getMethod(
        objectValue,
        JSSymbol.symbolToPrimitive.propertyKey,
      );
      if (toPrimitive != null) {
        final primitive = callMethod(toPrimitive, [
          JSValueFactory.string('string'),
        ], objectValue);
        if (primitive is JSObject || primitive is JSFunction) {
          throw JSTypeError('Cannot convert object to primitive value');
        }
        if (primitive is JSSymbol || primitive.isSymbol) {
          throw JSTypeError('Cannot convert a Symbol value to a string');
        }
        return JSConversion.jsToString(primitive);
      }

      final toStringMethod = getMethod(objectValue, 'toString');
      if (toStringMethod != null) {
        final stringResult = callMethod(
          toStringMethod,
          const <JSValue>[],
          objectValue,
        );
        if (stringResult is! JSObject && stringResult is! JSFunction) {
          if (stringResult is JSSymbol || stringResult.isSymbol) {
            throw JSTypeError('Cannot convert a Symbol value to a string');
          }
          return JSConversion.jsToString(stringResult);
        }
      }

      final valueOfMethod = getMethod(objectValue, 'valueOf');
      if (valueOfMethod != null) {
        final valueOfResult = callMethod(
          valueOfMethod,
          const <JSValue>[],
          objectValue,
        );
        if (valueOfResult is! JSObject && valueOfResult is! JSFunction) {
          if (valueOfResult is JSSymbol || valueOfResult.isSymbol) {
            throw JSTypeError('Cannot convert a Symbol value to a string');
          }
          return JSConversion.jsToString(valueOfResult);
        }
      }

      throw JSTypeError('Cannot convert object to primitive value');
    }

    String? aggregateErrorMessage(JSValue value) {
      if (value.isUndefined) {
        return null;
      }
      return toAggregateErrorString(value);
    }

    final aggregateErrorPrototype = JSObject();
    if (errorProto != null) {
      aggregateErrorPrototype.setPrototype(errorProto);
    }
    aggregateErrorPrototype.defineProperty(
      'name',
      PropertyDescriptor(
        value: JSValueFactory.string('AggregateError'),
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );
    aggregateErrorPrototype.defineProperty(
      'message',
      PropertyDescriptor(
        value: JSValueFactory.string(''),
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );
    final aggregateErrorConstructor = JSNativeFunction(
      functionName: 'AggregateError',
      nativeImpl: (args) {
        JSObject? existingInstance;
        var effectiveArgs = args;
        if (args.isNotEmpty &&
            args[0] is JSObject &&
            (args[0] as JSObject).hasOwnProperty(
              '__reflectConstructInstance__',
            )) {
          existingInstance = args[0] as JSObject;
          existingInstance.deleteProperty('__reflectConstructInstance__');
          effectiveArgs = args.length > 1 ? args.sublist(1) : <JSValue>[];
        } else if (args.isNotEmpty && args[0] is JSObject) {
          final firstArg = args[0] as JSObject;
          final proto = firstArg.getPrototype();
          if (proto != null && proto != aggregateErrorPrototype) {
            JSObject? current = proto;
            var extendsAggregateError = false;
            while (current != null) {
              if (current == aggregateErrorPrototype) {
                extendsAggregateError = true;
                break;
              }
              final nameVal = current.getOwnPropertyDirect('name');
              if (nameVal is JSString &&
                  nameVal.toString() == 'AggregateError') {
                extendsAggregateError = true;
                break;
              }
              current = current.getPrototype();
            }
            if (extendsAggregateError) {
              existingInstance = firstArg;
              effectiveArgs = args.length > 1 ? args.sublist(1) : <JSValue>[];
            }
          }
        }

        final messageArg = effectiveArgs.length > 1
            ? aggregateErrorMessage(effectiveArgs[1])
            : null;
        final errorsArg = effectiveArgs.isNotEmpty
            ? effectiveArgs[0]
            : JSValueFactory.undefined();
        final errorsArray = iterableToArray(errorsArg);
        JSValue? cause;
        var hasCause = false;
        if (effectiveArgs.length > 2 && effectiveArgs[2] is JSObject) {
          final options = effectiveArgs[2] as JSObject;
          if (options.hasProperty('cause')) {
            hasCause = true;
            cause = options.getProperty('cause');
          }
        }

        final aggregateError = existingInstance ?? JSValueFactory.object({});
        aggregateError.defineProperty(
          'name',
          PropertyDescriptor(
            value: JSValueFactory.string('AggregateError'),
            writable: true,
            enumerable: false,
            configurable: true,
          ),
        );
        aggregateError.setInternalSlot('ErrorData', true);
        if (existingInstance == null) {
          aggregateError.setPrototype(aggregateErrorPrototype);
        }
        if (messageArg != null) {
          aggregateError.defineProperty(
            'message',
            PropertyDescriptor(
              value: JSValueFactory.string(messageArg),
              writable: true,
              enumerable: false,
              configurable: true,
            ),
          );
        }
        if (hasCause) {
          aggregateError.defineProperty(
            'cause',
            PropertyDescriptor(
              value: cause,
              writable: true,
              enumerable: false,
              configurable: true,
            ),
          );
        }
        aggregateError.defineProperty(
          'errors',
          PropertyDescriptor(
            value: errorsArray,
            writable: true,
            enumerable: false,
            configurable: true,
          ),
        );
        return aggregateError;
      },
      expectedArgs: 2,
      isConstructor: true,
    );
    final errorConstructor = globals['Error'];
    if (errorConstructor is JSFunction) {
      aggregateErrorConstructor.setProperty('__proto__', errorConstructor);
    }
    aggregateErrorConstructor.defineProperty(
      'prototype',
      PropertyDescriptor(
        value: aggregateErrorPrototype,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    aggregateErrorPrototype.defineProperty(
      'constructor',
      PropertyDescriptor(
        value: aggregateErrorConstructor,
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );
    _define(globals, 'AggregateError', aggregateErrorConstructor);

    final promisePrototype = JSObject();
    promisePrototype.defineProperty(
      'then',
      PropertyDescriptor(
        value: JSNativeFunction(
          functionName: 'then',
          expectedArgs: 2,
          nativeImpl: PromisePrototype.thenWithThis,
        ),
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );
    promisePrototype.defineProperty(
      'catch',
      PropertyDescriptor(
        value: JSNativeFunction(
          functionName: 'catch',
          expectedArgs: 1,
          nativeImpl: (args) => PromisePrototype.catchWithThis(args),
        ),
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );
    promisePrototype.defineProperty(
      'finally',
      PropertyDescriptor(
        value: JSNativeFunction(
          functionName: 'finally',
          expectedArgs: 1,
          nativeImpl: (args) => PromisePrototype.finallyWithThis(args),
        ),
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );

    promiseConstructor.defineProperty(
      'prototype',
      PropertyDescriptor(
        value: promisePrototype,
        writable: false,
        enumerable: false,
        configurable: false,
      ),
    );
    promisePrototype.defineConstructorProperty(promiseConstructor);
    promisePrototype.defineProperty(
      JSSymbol.toStringTag.propertyKey,
      PropertyDescriptor(
        value: JSValueFactory.string('Promise'),
        writable: false,
        enumerable: false,
        configurable: true,
      ),
    );
    promisePrototype.registerSymbolKey(
      JSSymbol.toStringTag.propertyKey,
      JSSymbol.toStringTag,
    );
    JSPromise.setPromisePrototype(promisePrototype);
    _define(globals, 'Promise', promiseConstructor);
  }

  static void _installGlobalFunctions(
    Map<String, JSValue> globals, {
    String? Function()? getInterpreterInstanceId,
  }) {
    _define(globals, 'NaN', JSValueFactory.number(double.nan));
    _define(globals, 'Infinity', JSValueFactory.number(double.infinity));
    _define(globals, 'undefined', JSValueFactory.undefined());
    _define(globals, 'eval', GlobalFunctions.createEval());
    _define(globals, 'parseInt', GlobalFunctions.createParseInt());
    _define(globals, 'parseFloat', GlobalFunctions.createParseFloat());
    _define(globals, 'isNaN', GlobalFunctions.createIsNaN());
    _define(globals, 'isFinite', GlobalFunctions.createIsFinite());
    _define(globals, 'encodeURI', GlobalFunctions.createEncodeURI());
    _define(globals, 'decodeURI', GlobalFunctions.createDecodeURI());
    _define(
      globals,
      'encodeURIComponent',
      GlobalFunctions.createEncodeURIComponent(),
    );
    _define(
      globals,
      'decodeURIComponent',
      GlobalFunctions.createDecodeURIComponent(),
    );
    _define(globals, 'setTimeout', GlobalFunctions.createSetTimeout());
    _define(globals, 'clearTimeout', GlobalFunctions.createClearTimeout());
    if (getInterpreterInstanceId != null) {
      final globalFunctions = GlobalFunctions(getInterpreterInstanceId());
      _define(globals, 'sendMessage', globalFunctions.createSendMessage());
      _define(
        globals,
        'sendMessageAsync',
        globalFunctions.createSendMessageAsync(),
      );
    }
  }

  static void _installCommonJsGlobals(Map<String, JSValue> globals) {
    final moduleObject = JSValueFactory.createObject();
    final exportsObject = JSValueFactory.createObject();
    moduleObject.setProperty('exports', exportsObject);
    _define(globals, 'module', moduleObject);
    _define(globals, 'exports', exportsObject);
    _define(
      globals,
      'require',
      JSNativeFunction(
        functionName: 'require',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSError('require() expects a module path');
          }
          return JSValueFactory.createObject();
        },
      ),
    );
  }

  static void _installGlobalThis(Map<String, JSValue> globals) {
    final globalThis = JSObject();
    _define(globals, 'globalThis', globalThis);
    _define(globals, 'global', globalThis);
    const readonlyGlobals = {'NaN', 'Infinity', 'undefined'};
    for (final entry in globals.entries.toList()) {
      globalThis.defineProperty(
        entry.key,
        PropertyDescriptor(
          value: entry.value,
          writable: !readonlyGlobals.contains(entry.key),
          enumerable: false,
          configurable: !readonlyGlobals.contains(entry.key),
        ),
      );
    }
    globalThis.defineProperty(
      'globalThis',
      PropertyDescriptor(
        value: globalThis,
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );
    globalThis.defineProperty(
      'global',
      PropertyDescriptor(
        value: globalThis,
        writable: true,
        enumerable: false,
        configurable: true,
      ),
    );
  }
}

class _BootstrapRuntime implements JSRuntime {
  final Map<String, JSValue> globals;

  _BootstrapRuntime(this.globals);

  @override
  JSValue callFunction(
    JSValue func,
    List<JSValue> args, [
    JSValue? thisBinding,
  ]) {
    final thisValue = thisBinding ?? JSUndefined.instance;
    if (func is JSNativeFunction) {
      return func.callWithThis(args, thisValue);
    }
    if (func is JSBoundFunction) {
      return callFunction(func.originalFunction, [
        ...func.boundArgs,
        ...args,
      ], func.thisArg);
    }
    if (func is RuntimeCallableFunction && func is JSFunction) {
      final callable = func as RuntimeCallableFunction;
      return callable.callWithRuntime(args, thisValue, this);
    }
    throw JSTypeError('Bootstrap runtime cannot execute ${func.runtimeType}');
  }

  @override
  bool isStrictMode() => false;

  @override
  void enqueueMicrotask(void Function() callback) {}

  @override
  void notifyPromiseResolved(JSPromise promise) {}

  @override
  void runPendingTasks() {}

  @override
  JSValue evalCode(String code, {bool directEval = false}) {
    throw UnsupportedError('eval is not available during runtime bootstrap');
  }

  @override
  JSValue getGlobal(String name) => globals[name] ?? JSUndefined.instance;

  @override
  bool isValueReachable(JSValue value) => true;

  @override
  void registerWeakMap(JSWeakMap weakMap) {}

  @override
  void registerWeakRef(JSWeakRefObject weakRef) {}

  @override
  void registerFinalizationRegistry(JSFinalizationRegistryObject registry) {}

  @override
  void performHostGarbageCollection() {}

  @override
  JSValue? getCurrentCaller(JSFunction callee) => null;

  @override
  bool isGetterCycle(JSObject obj, String property) => false;

  @override
  void markGetterActive(JSObject obj, String property) {}

  @override
  void unmarkGetterActive(JSObject obj, String property) {}

  @override
  bool isSetterCycle(JSObject obj, String property) => false;

  @override
  void markSetterActive(JSObject obj, String property) {}

  @override
  void unmarkSetterActive(JSObject obj, String property) {}

  @override
  JSValue evalASTNode(dynamic node) => JSUndefined.instance;

  @override
  void executeStaticBlock(dynamic body, JSValue classObj) {}
}
