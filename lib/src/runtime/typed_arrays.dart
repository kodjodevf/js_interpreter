/// Implementation of ArrayBuffer and TypedArrays (ES6)
///
/// Supports:
/// - ArrayBuffer: raw binary container
/// - Int8Array, Uint8Array, Uint8ClampedArray
/// - Int16Array, Uint16Array
/// - Int32Array, Uint32Array
/// - Float16Array, Float32Array, Float64Array
/// - DataView: flexible view on an ArrayBuffer
library;

import 'dart:typed_data';
import 'dart:math' as math;
import 'js_value.dart';
import 'native_functions.dart';
import '../evaluator/evaluator.dart';
import 'iterator_protocol.dart';
import 'js_symbol.dart';

/// Helper to safely convert a double to int, handling Infinity/NaN per ES spec
/// For array indices: NaN → 0, +Infinity → maxInt, -Infinity → minInt
int _toSafeInt(
  double value, {
  int defaultForNaN = 0,
  int? maxValue,
  int? minValue,
}) {
  if (value.isNaN) return defaultForNaN;
  if (value.isInfinite) {
    if (value.isNegative) {
      return minValue ?? -0x1FFFFFFFFFFFFF; // -(2^53 - 1)
    } else {
      return maxValue ?? 0x1FFFFFFFFFFFFF; // 2^53 - 1
    }
  }
  return value.truncate();
}

/// ArrayBuffer: represents a raw binary data buffer
class JSArrayBuffer extends JSObject {
  /// The raw binary data (bytes)
  final Uint8List _data;

  /// Constructor
  JSArrayBuffer(int byteLength) : _data = Uint8List(byteLength) {
    _setupProperties();
  }

  /// Constructor from existing data
  JSArrayBuffer.fromData(Uint8List data) : _data = data {
    _setupProperties();
  }

  /// Setup of properties
  void _setupProperties() {
    // Property byteLength (read-only)
    setProperty('byteLength', JSValueFactory.number(_data.length.toDouble()));

    // Method slice(begin, end)
    setProperty(
      'slice',
      JSNativeFunction(
        functionName: 'slice',
        nativeImpl: (args) {
          final begin = args.isNotEmpty ? _toSafeInt(args[0].toNumber()) : 0;
          final end = args.length > 1
              ? _toSafeInt(args[1].toNumber(), maxValue: _data.length)
              : _data.length;

          // Normalize negative indices
          final normalizedBegin = begin < 0 ? _data.length + begin : begin;
          final normalizedEnd = end < 0 ? _data.length + end : end;

          // Clamp the indices
          final clampedBegin = normalizedBegin.clamp(0, _data.length);
          final clampedEnd = normalizedEnd.clamp(0, _data.length);

          // Create the new buffer
          final length = (clampedEnd - clampedBegin).clamp(0, _data.length);
          final newData = Uint8List(length);
          for (var i = 0; i < length; i++) {
            newData[i] = _data[clampedBegin + i];
          }

          return JSArrayBuffer.fromData(newData);
        },
      ),
    );
  }

  /// Access to raw data
  Uint8List get data => _data;

  /// Length in bytes
  int get byteLength => _data.length;

  @override
  String toString() => '[object ArrayBuffer]';
}

/// Base class for all TypedArrays
abstract class JSTypedArray extends JSObject {
  /// The underlying buffer
  final JSArrayBuffer buffer;

  /// The offset in bytes in the buffer
  final int byteOffset;

  /// The length in bytes of the view
  final int byteLength;

  /// The number of elements
  final int length;

  /// Constructor
  JSTypedArray({
    required this.buffer,
    required this.byteOffset,
    required this.byteLength,
    required this.length,
  }) {
    _setupCommonProperties();
  }

  /// Helper method to call JavaScript callbacks (both native and user-defined)
  static JSValue _callCallback(
    JSValue callback,
    List<JSValue> args,
    JSValue thisBinding,
  ) {
    // If it's a native function, call it directly
    if (callback is JSNativeFunction) {
      return callback.nativeImpl(args);
    }

    // For JavaScript functions, use the evaluator
    if (callback is JSFunction) {
      final evaluator = JSEvaluator.currentInstance;
      if (evaluator == null) {
        throw JSError('No evaluator available for callback execution');
      }

      try {
        return evaluator.callFunction(callback, args, thisBinding);
      } catch (e) {
        if (e is JSException) {
          rethrow;
        }
        throw JSError('Error executing callback: $e');
      }
    }

    throw JSTypeError('Callback must be a function');
  }

  /// Setup of properties common to all TypedArrays
  void _setupCommonProperties() {
    setProperty('buffer', buffer);
    setProperty('byteOffset', JSValueFactory.number(byteOffset.toDouble()));
    setProperty('byteLength', JSValueFactory.number(byteLength.toDouble()));
    setProperty('length', JSValueFactory.number(length.toDouble()));
    setProperty(
      'BYTES_PER_ELEMENT',
      JSValueFactory.number(bytesPerElement.toDouble()),
    );

    // Method set(array, offset)
    setProperty(
      'set',
      JSNativeFunction(
        functionName: 'set',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSError('TypedArray.set requires at least 1 argument');
          }

          final source = args[0];
          final offset = args.length > 1 ? _toSafeInt(args[1].toNumber()) : 0;

          if (offset < 0 || offset >= length) {
            throw JSError('Offset is out of bounds');
          }

          // If it's a TypedArray
          if (source is JSTypedArray) {
            if (offset + source.length > length) {
              throw JSError('Source is too large');
            }

            for (var i = 0; i < source.length; i++) {
              setElement(offset + i, source.getElement(i));
            }
          } else if (source is JSArray) {
            // If it's a JavaScript array
            final sourceLength = source.elements.length;
            if (offset + sourceLength > length) {
              throw JSError('Source is too large');
            }

            for (var i = 0; i < sourceLength; i++) {
              final value = source.elements[i];
              setElement(offset + i, value.toNumber());
            }
          } else if (source is JSObject && source.hasProperty('length')) {
            // If it's a generic array-like object
            final lengthValue = source.getProperty('length');
            if (lengthValue.isNumber) {
              final sourceLength = _toSafeInt(lengthValue.toNumber());
              if (offset + sourceLength > length) {
                throw JSError('Source is too large');
              }

              for (var i = 0; i < sourceLength; i++) {
                final value = source.getProperty(i.toString());
                setElement(offset + i, value.toNumber());
              }
            }
          }

          return JSValueFactory.undefined();
        },
      ),
    );

    // Method subarray(begin, end)
    setProperty(
      'subarray',
      JSNativeFunction(
        functionName: 'subarray',
        nativeImpl: (args) {
          final begin = args.isNotEmpty ? _toSafeInt(args[0].toNumber()) : 0;
          final end = args.length > 1
              ? _toSafeInt(args[1].toNumber(), maxValue: length)
              : length;

          // Normalize negative indices
          final normalizedBegin = begin < 0 ? length + begin : begin;
          final normalizedEnd = end < 0 ? length + end : end;

          // Clamp the indices
          final clampedBegin = normalizedBegin.clamp(0, length);
          final clampedEnd = normalizedEnd.clamp(0, length);

          final newLength = (clampedEnd - clampedBegin).clamp(0, length);
          final newByteOffset = byteOffset + (clampedBegin * bytesPerElement);

          return createSubarray(
            buffer: buffer,
            byteOffset: newByteOffset,
            length: newLength,
          );
        },
      ),
    );

    // Method copyWithin(target, start, end)
    setProperty(
      'copyWithin',
      JSNativeFunction(
        functionName: 'copyWithin',
        nativeImpl: (args) {
          if (args.isEmpty) {
            return this;
          }

          final target = _toSafeInt(args[0].toNumber());
          final start = args.length > 1 ? _toSafeInt(args[1].toNumber()) : 0;
          final end = args.length > 2
              ? _toSafeInt(args[2].toNumber(), maxValue: length)
              : length;

          // Normalize the indices
          final normalizedTarget = target < 0 ? length + target : target;
          final normalizedStart = start < 0 ? length + start : start;
          final normalizedEnd = end < 0 ? length + end : end;

          // Clamp
          final clampedTarget = normalizedTarget.clamp(0, length);
          final clampedStart = normalizedStart.clamp(0, length);
          final clampedEnd = normalizedEnd.clamp(0, length);

          final copyLength = (clampedEnd - clampedStart).clamp(0, length);

          // Copier les elements
          final temp = <double>[];
          for (var i = 0; i < copyLength; i++) {
            temp.add(getElement(clampedStart + i));
          }
          for (var i = 0; i < copyLength; i++) {
            setElement(clampedTarget + i, temp[i]);
          }

          return this;
        },
        hasContextBound:
            true, // TypedArray has its own copyWithin implementation
      ),
    );

    // Method forEach(callback, thisArg)
    setProperty(
      'forEach',
      JSNativeFunction(
        functionName: 'forEach',
        hasContextBound: true, // TypedArray has 'this' bound via closure
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSError('forEach requires a callback function');
          }

          final callback = args[0];
          if (callback is! JSFunction) {
            throw JSTypeError(
              'Callback must be a function, got ${callback.runtimeType}',
            );
          }

          final thisArg = args.length > 1
              ? args[1]
              : JSValueFactory.undefined();

          for (var i = 0; i < length; i++) {
            final value = JSValueFactory.number(getElement(i));
            final index = JSValueFactory.number(i.toDouble());
            _callCallback(callback, [value, index, this], thisArg);
          }

          return JSValueFactory.undefined();
        },
      ),
    );

    // Method map(callback, thisArg)
    setProperty(
      'map',
      JSNativeFunction(
        functionName: 'map',
        hasContextBound: true, // TypedArray has 'this' bound via closure
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSError('map requires a callback function');
          }

          final callback = args[0];
          if (callback is! JSFunction) {
            throw JSTypeError('Callback must be a function');
          }

          final thisArg = args.length > 1
              ? args[1]
              : JSValueFactory.undefined();

          final result = <double>[];
          for (var i = 0; i < length; i++) {
            final value = JSValueFactory.number(getElement(i));
            final index = JSValueFactory.number(i.toDouble());
            final mapped = _callCallback(callback, [
              value,
              index,
              this,
            ], thisArg);
            result.add(mapped.toNumber());
          }

          // Create a new TypedArray of the same type
          final newBuffer = JSArrayBuffer(result.length * bytesPerElement);
          final mappedArray = createSubarray(
            buffer: newBuffer,
            byteOffset: 0,
            length: result.length,
          );
          for (var i = 0; i < result.length; i++) {
            mappedArray.setElement(i, result[i]);
          }
          return mappedArray;
        },
      ),
    );

    // Method filter(callback, thisArg)
    setProperty(
      'filter',
      JSNativeFunction(
        functionName: 'filter',
        hasContextBound: true, // TypedArray has 'this' bound via closure
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSError('filter requires a callback function');
          }

          final callback = args[0];
          if (callback is! JSFunction) {
            throw JSTypeError('Callback must be a function');
          }

          final thisArg = args.length > 1
              ? args[1]
              : JSValueFactory.undefined();

          final result = <double>[];
          for (var i = 0; i < length; i++) {
            final value = JSValueFactory.number(getElement(i));
            final index = JSValueFactory.number(i.toDouble());
            final keep = _callCallback(callback, [value, index, this], thisArg);
            if (keep.toBoolean()) {
              result.add(getElement(i));
            }
          }

          // Create a new TypedArray of the same type avec les elements filtres
          final newBuffer = JSArrayBuffer(result.length * bytesPerElement);
          final filtered = createSubarray(
            buffer: newBuffer,
            byteOffset: 0,
            length: result.length,
          );
          for (var i = 0; i < result.length; i++) {
            filtered.setElement(i, result[i]);
          }
          return filtered;
        },
      ),
    );

    // Method reduce(callback, initialValue)
    setProperty(
      'reduce',
      JSNativeFunction(
        functionName: 'reduce',
        hasContextBound: true, // TypedArray has 'this' bound via closure
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSError('reduce requires a callback function');
          }

          final callback = args[0];
          if (callback is! JSFunction) {
            throw JSTypeError('Callback must be a function');
          }

          if (length == 0 && args.length < 2) {
            throw JSTypeError('Reduce of empty array with no initial value');
          }

          var accumulator = args.length > 1
              ? args[1]
              : JSValueFactory.number(getElement(0));
          final startIndex = args.length > 1 ? 0 : 1;

          for (var i = startIndex; i < length; i++) {
            final value = JSValueFactory.number(getElement(i));
            final index = JSValueFactory.number(i.toDouble());
            accumulator = _callCallback(callback, [
              accumulator,
              value,
              index,
              this,
            ], JSValueFactory.undefined());
          }

          return accumulator;
        },
      ),
    );

    // Method find(callback, thisArg)
    setProperty(
      'find',
      JSNativeFunction(
        functionName: 'find',
        hasContextBound: true, // TypedArray has 'this' bound via closure
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSError('find requires a callback function');
          }

          final callback = args[0];
          if (callback is! JSFunction) {
            throw JSTypeError('Callback must be a function');
          }

          final thisArg = args.length > 1
              ? args[1]
              : JSValueFactory.undefined();

          for (var i = 0; i < length; i++) {
            final value = JSValueFactory.number(getElement(i));
            final index = JSValueFactory.number(i.toDouble());
            final found = _callCallback(callback, [
              value,
              index,
              this,
            ], thisArg);
            if (found.toBoolean()) {
              return value;
            }
          }

          return JSValueFactory.undefined();
        },
      ),
    );

    // Method findIndex(callback, thisArg)
    setProperty(
      'findIndex',
      JSNativeFunction(
        functionName: 'findIndex',
        hasContextBound: true, // TypedArray has 'this' bound via closure
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSError('findIndex requires a callback function');
          }

          final callback = args[0];
          if (callback is! JSFunction) {
            throw JSTypeError('Callback must be a function');
          }

          final thisArg = args.length > 1
              ? args[1]
              : JSValueFactory.undefined();

          for (var i = 0; i < length; i++) {
            final value = JSValueFactory.number(getElement(i));
            final index = JSValueFactory.number(i.toDouble());
            final found = _callCallback(callback, [
              value,
              index,
              this,
            ], thisArg);
            if (found.toBoolean()) {
              return JSValueFactory.number(i.toDouble());
            }
          }

          return JSValueFactory.number(-1.0);
        },
      ),
    );

    // Method every(callback, thisArg)
    setProperty(
      'every',
      JSNativeFunction(
        functionName: 'every',
        hasContextBound: true, // TypedArray has 'this' bound via closure
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSError('every requires a callback function');
          }

          final callback = args[0];
          if (callback is! JSFunction) {
            throw JSTypeError('Callback must be a function');
          }

          final thisArg = args.length > 1
              ? args[1]
              : JSValueFactory.undefined();

          for (var i = 0; i < length; i++) {
            final value = JSValueFactory.number(getElement(i));
            final index = JSValueFactory.number(i.toDouble());
            final result = _callCallback(callback, [
              value,
              index,
              this,
            ], thisArg);
            if (!result.toBoolean()) {
              return JSValueFactory.boolean(false);
            }
          }

          return JSValueFactory.boolean(true);
        },
      ),
    );

    // Method some(callback, thisArg)
    setProperty(
      'some',
      JSNativeFunction(
        functionName: 'some',
        hasContextBound: true, // TypedArray has 'this' bound via closure
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSError('some requires a callback function');
          }

          final callback = args[0];
          if (callback is! JSFunction) {
            throw JSTypeError('Callback must be a function');
          }

          final thisArg = args.length > 1
              ? args[1]
              : JSValueFactory.undefined();

          for (var i = 0; i < length; i++) {
            final value = JSValueFactory.number(getElement(i));
            final index = JSValueFactory.number(i.toDouble());
            final result = _callCallback(callback, [
              value,
              index,
              this,
            ], thisArg);
            if (result.toBoolean()) {
              return JSValueFactory.boolean(true);
            }
          }

          return JSValueFactory.boolean(false);
        },
      ),
    );

    // Method slice(begin, end)
    setProperty(
      'slice',
      JSNativeFunction(
        functionName: 'slice',
        nativeImpl: (args) {
          final begin = args.isNotEmpty ? _toSafeInt(args[0].toNumber()) : 0;
          final end = args.length > 1
              ? _toSafeInt(args[1].toNumber(), maxValue: length)
              : length;

          // Normalize negative indices
          final normalizedBegin = begin < 0 ? length + begin : begin;
          final normalizedEnd = end < 0 ? length + end : end;

          // Clamp the indices
          final clampedBegin = normalizedBegin.clamp(0, length);
          final clampedEnd = normalizedEnd.clamp(0, length);

          final sliceLength = (clampedEnd - clampedBegin).clamp(0, length);

          // Create a new TypedArray with copied values
          final newBuffer = JSArrayBuffer(sliceLength * bytesPerElement);
          final sliced = createSubarray(
            buffer: newBuffer,
            byteOffset: 0,
            length: sliceLength,
          );

          for (var i = 0; i < sliceLength; i++) {
            sliced.setElement(i, getElement(clampedBegin + i));
          }

          return sliced;
        },
      ),
    );

    // Method fill(value, start, end)
    setProperty(
      'fill',
      JSNativeFunction(
        functionName: 'fill',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSError('fill requires a value');
          }

          final value = args[0].toNumber();
          final start = args.length > 1 ? _toSafeInt(args[1].toNumber()) : 0;
          final end = args.length > 2
              ? _toSafeInt(args[2].toNumber(), maxValue: length)
              : length;

          // Normalize negative indices
          final normalizedStart = start < 0 ? length + start : start;
          final normalizedEnd = end < 0 ? length + end : end;

          // Clamp the indices
          final clampedStart = normalizedStart.clamp(0, length);
          final clampedEnd = normalizedEnd.clamp(0, length);

          for (var i = clampedStart; i < clampedEnd; i++) {
            setElement(i, value);
          }

          return this;
        },
        hasContextBound: true, // TypedArray has its own fill implementation
      ),
    );

    // Method reverse()
    setProperty(
      'reverse',
      JSNativeFunction(
        functionName: 'reverse',
        nativeImpl: (args) {
          var left = 0;
          var right = length - 1;

          while (left < right) {
            final temp = getElement(left);
            setElement(left, getElement(right));
            setElement(right, temp);
            left++;
            right--;
          }

          return this;
        },
        hasContextBound: true, // TypedArray has its own reverse implementation
      ),
    );

    // Support pour Symbol.iterator (pour for...of)
    setProperty(
      JSSymbol.iterator.toString(),
      JSNativeFunction(
        functionName: 'Symbol.iterator',
        nativeImpl: (args) {
          return JSTypedArrayIterator(this, IteratorKind.valueKind);
        },
      ),
    );

    // Method keys()
    setProperty(
      'keys',
      JSNativeFunction(
        functionName: 'keys',
        nativeImpl: (args) {
          return JSTypedArrayIterator(this, IteratorKind.keys);
        },
      ),
    );

    // Method values()
    setProperty(
      'values',
      JSNativeFunction(
        functionName: 'values',
        nativeImpl: (args) {
          return JSTypedArrayIterator(this, IteratorKind.valueKind);
        },
      ),
    );

    // Method entries()
    setProperty(
      'entries',
      JSNativeFunction(
        functionName: 'entries',
        nativeImpl: (args) {
          return JSTypedArrayIterator(this, IteratorKind.entries);
        },
      ),
    );
  }

  /// Nombre de bytes par element
  int get bytesPerElement;

  /// Nom du type
  String get typeName;

  /// Get un element a un index donne
  double getElement(int index);

  /// Definir un element a un index donne
  void setElement(int index, double value);

  /// Create a subarray of the same type
  JSTypedArray createSubarray({
    required JSArrayBuffer buffer,
    required int byteOffset,
    required int length,
  });

  /// Override pour supporter l'acces par index (arr[0], arr[1], etc.)
  @override
  JSValue getProperty(String key) {
    // Essayer de parser comme un index numerique
    final index = int.tryParse(key);
    if (index != null && index >= 0 && index < length) {
      return JSValueFactory.number(getElement(index));
    }

    // Check for array prototype methods
    final arrayMethod = _getArrayMethod(key);
    if (arrayMethod != null) {
      return arrayMethod;
    }

    // Ifnon, utiliser le comportement by default
    final result = super.getProperty(key);
    return result;
  }

  /// Override pour supporter l'assignation par index (arr[0] = value)
  @override
  void setProperty(String key, JSValue value) {
    // Essayer de parser comme un index numerique
    final index = int.tryParse(key);
    if (index != null && index >= 0 && index < length) {
      setElement(index, value.toNumber());
      return;
    }
    // Ifnon, utiliser le comportement by default
    super.setProperty(key, value);
  }

  /// Helper method to get array prototype methods for TypedArrays
  JSValue? _getArrayMethod(String name) {
    switch (name) {
      case 'join':
        return JSNativeFunction(
          functionName: 'join',
          nativeImpl: (args) {
            String separator = ',';
            // If 'join' is in _needsThisBinding, args[0] is 'this', args[1] is separator
            int separatorIndex = args.isNotEmpty && args[0] == this ? 1 : 0;
            if (args.length > separatorIndex &&
                !args[separatorIndex].isUndefined) {
              separator = JSConversion.jsToString(args[separatorIndex]);
            }

            final parts = <String>[];
            for (int i = 0; i < length; i++) {
              final element = getElement(i);
              if (element.isNaN || element.isInfinite) {
                parts.add('null');
              } else {
                parts.add(
                  JSConversion.jsToString(JSValueFactory.number(element)),
                );
              }
            }

            return JSValueFactory.string(parts.join(separator));
          },
        );
      case 'toString':
        return JSNativeFunction(
          functionName: 'toString',
          nativeImpl: (args) {
            final parts = <String>[];
            for (int i = 0; i < length; i++) {
              final element = getElement(i);
              if (element.isNaN || element.isInfinite) {
                parts.add('null');
              } else {
                parts.add(
                  JSConversion.jsToString(JSValueFactory.number(element)),
                );
              }
            }

            return JSValueFactory.string(parts.join(','));
          },
        );
      // Add other array methods as needed
      default:
        return null;
    }
  }

  @override
  String toString() => '[$typeName]';
}

/// Iterateur pour TypedArrays
class JSTypedArrayIterator extends JSIterator {
  final JSTypedArray typedArray;
  int currentIndex = 0;
  final IteratorKind kind;

  JSTypedArrayIterator(this.typedArray, this.kind) : super() {
    // Exposer la methode next comme properte JavaScript
    setProperty(
      'next',
      JSNativeFunction(
        functionName: 'next',
        nativeImpl: (args) => next(args.isNotEmpty ? args[0] : null),
      ),
    );
  }

  @override
  JSValue next([JSValue? value]) {
    if (currentIndex >= typedArray.length) {
      // Iterateur epuise
      return JSIteratorResult.create(JSValueFactory.undefined(), true);
    }

    final index = currentIndex++;
    switch (kind) {
      case IteratorKind.valueKind:
        final elementValue = JSValueFactory.number(
          typedArray.getElement(index),
        );
        return JSIteratorResult.create(elementValue, false);

      case IteratorKind.keys:
        return JSIteratorResult.create(
          JSValueFactory.number(index.toDouble()),
          false,
        );

      case IteratorKind.entries:
        final elementValue = JSValueFactory.number(
          typedArray.getElement(index),
        );
        final entry = JSValueFactory.array([
          JSValueFactory.number(index.toDouble()),
          elementValue,
        ]);
        return JSIteratorResult.create(entry, false);
    }
  }

  @override
  JSValue? returnMethod([JSValue? value]) {
    // Marquer l'iterateur comme termine
    currentIndex = typedArray.length;
    return JSIteratorResult.create(value ?? JSValueFactory.undefined(), true);
  }

  @override
  String toString() => '[TypedArray Iterator]';
}

/// Int8Array : tableau d'entiers signes 8 bits
class JSInt8Array extends JSTypedArray {
  JSInt8Array({
    required super.buffer,
    required super.byteOffset,
    required super.length,
  }) : super(byteLength: length * 1);

  /// Constructeur depuis une longueur
  factory JSInt8Array.fromLength(int length) {
    final buffer = JSArrayBuffer(length * 1);
    return JSInt8Array(buffer: buffer, byteOffset: 0, length: length);
  }

  /// Constructeur depuis un array ou iterable
  factory JSInt8Array.fromArray(List<double> values) {
    final array = JSInt8Array.fromLength(values.length);
    for (var i = 0; i < values.length; i++) {
      array.setElement(i, values[i]);
    }
    return array;
  }

  @override
  int get bytesPerElement => 1;

  @override
  String get typeName => 'Int8Array';

  @override
  double getElement(int index) {
    if (index < 0 || index >= length) {
      return double.nan;
    }
    final byteIndex = byteOffset + index;
    final byte = buffer.data[byteIndex];
    // Interpreter comme signed int8 (-128 a 127)
    return (byte > 127 ? byte - 256 : byte).toDouble();
  }

  @override
  void setElement(int index, double value) {
    if (index < 0 || index >= length) {
      return;
    }
    final byteIndex = byteOffset + index;
    // Convert to int8 (-128 to 127) with wraparound
    var intValue = _toSafeInt(value);
    intValue = intValue & 0xFF; // Wrap to 0-255
    if (intValue >= 128) intValue -= 256; // Ifgn extend
    buffer.data[byteIndex] = intValue;
  }

  @override
  JSTypedArray createSubarray({
    required JSArrayBuffer buffer,
    required int byteOffset,
    required int length,
  }) {
    return JSInt8Array(buffer: buffer, byteOffset: byteOffset, length: length);
  }
}

/// Uint8Array : tableau d'entiers non signes 8 bits
class JSUint8Array extends JSTypedArray {
  JSUint8Array({
    required super.buffer,
    required super.byteOffset,
    required super.length,
  }) : super(byteLength: length * 1);

  /// Constructeur depuis une longueur
  factory JSUint8Array.fromLength(int length) {
    final buffer = JSArrayBuffer(length * 1);
    return JSUint8Array(buffer: buffer, byteOffset: 0, length: length);
  }

  /// Constructeur depuis un array
  factory JSUint8Array.fromArray(List<double> values) {
    final array = JSUint8Array.fromLength(values.length);
    for (var i = 0; i < values.length; i++) {
      array.setElement(i, values[i]);
    }
    return array;
  }

  @override
  int get bytesPerElement => 1;

  @override
  String get typeName => 'Uint8Array';

  @override
  double getElement(int index) {
    if (index < 0 || index >= length) {
      return double.nan;
    }
    final byteIndex = byteOffset + index;
    final result = buffer.data[byteIndex].toDouble();
    return result;
  }

  @override
  void setElement(int index, double value) {
    if (index < 0 || index >= length) {
      return;
    }
    final byteIndex = byteOffset + index;
    // Convert to uint8 (0 to 255) with wraparound
    var intValue = _toSafeInt(value);
    intValue = intValue & 0xFF; // Wrap around for unsigned
    buffer.data[byteIndex] = intValue;
  }

  @override
  JSTypedArray createSubarray({
    required JSArrayBuffer buffer,
    required int byteOffset,
    required int length,
  }) {
    return JSUint8Array(buffer: buffer, byteOffset: byteOffset, length: length);
  }
}

/// Uint8ClampedArray : comme Uint8Array mais avec clamping sur les valeurs
class JSUint8ClampedArray extends JSTypedArray {
  JSUint8ClampedArray({
    required super.buffer,
    required super.byteOffset,
    required super.length,
  }) : super(byteLength: length * 1);

  factory JSUint8ClampedArray.fromLength(int length) {
    final buffer = JSArrayBuffer(length * 1);
    return JSUint8ClampedArray(buffer: buffer, byteOffset: 0, length: length);
  }

  factory JSUint8ClampedArray.fromArray(List<double> values) {
    final array = JSUint8ClampedArray.fromLength(values.length);
    for (var i = 0; i < values.length; i++) {
      array.setElement(i, values[i]);
    }
    return array;
  }

  @override
  int get bytesPerElement => 1;

  @override
  String get typeName => 'Uint8ClampedArray';

  @override
  double getElement(int index) {
    if (index < 0 || index >= length) {
      return double.nan;
    }
    final byteIndex = byteOffset + index;
    return buffer.data[byteIndex].toDouble();
  }

  @override
  void setElement(int index, double value) {
    if (index < 0 || index >= length) {
      return;
    }
    final byteIndex = byteOffset + index;
    // ToUint8Clamp algorithm (ECMAScript spec)
    int intValue;
    if (value.isNaN) {
      intValue = 0;
    } else if (value <= 0) {
      intValue = 0;
    } else if (value >= 255) {
      intValue = 255;
    } else {
      final f = value.floor();
      final half = f + 0.5;
      if (half < value) {
        intValue = f + 1;
      } else if (value < half) {
        intValue = f;
      } else {
        // value == half
        intValue = f.isOdd ? f + 1 : f;
      }
    }
    buffer.data[byteIndex] = intValue;
  }

  @override
  JSTypedArray createSubarray({
    required JSArrayBuffer buffer,
    required int byteOffset,
    required int length,
  }) {
    return JSUint8ClampedArray(
      buffer: buffer,
      byteOffset: byteOffset,
      length: length,
    );
  }
}

/// Int16Array : tableau d'entiers signes 16 bits
class JSInt16Array extends JSTypedArray {
  JSInt16Array({
    required super.buffer,
    required super.byteOffset,
    required super.length,
  }) : super(byteLength: length * 2);

  factory JSInt16Array.fromLength(int length) {
    final buffer = JSArrayBuffer(length * 2);
    return JSInt16Array(buffer: buffer, byteOffset: 0, length: length);
  }

  factory JSInt16Array.fromArray(List<double> values) {
    final array = JSInt16Array.fromLength(values.length);
    for (var i = 0; i < values.length; i++) {
      array.setElement(i, values[i]);
    }
    return array;
  }

  @override
  int get bytesPerElement => 2;

  @override
  String get typeName => 'Int16Array';

  @override
  double getElement(int index) {
    if (index < 0 || index >= length) {
      return double.nan;
    }
    final byteIndex = byteOffset + index * 2;
    // Little-endian
    final low = buffer.data[byteIndex];
    final high = buffer.data[byteIndex + 1];
    final value = low | (high << 8);
    // Interpreter comme signed int16 (-32768 a 32767)
    return (value > 32767 ? value - 65536 : value).toDouble();
  }

  @override
  void setElement(int index, double value) {
    if (index < 0 || index >= length) {
      return;
    }
    final byteIndex = byteOffset + index * 2;
    // Convert to int16
    var intValue = _toSafeInt(value).clamp(-32768, 32767);
    if (intValue < 0) intValue += 65536;
    // Little-endian
    buffer.data[byteIndex] = intValue & 0xFF;
    buffer.data[byteIndex + 1] = (intValue >> 8) & 0xFF;
  }

  @override
  JSTypedArray createSubarray({
    required JSArrayBuffer buffer,
    required int byteOffset,
    required int length,
  }) {
    return JSInt16Array(buffer: buffer, byteOffset: byteOffset, length: length);
  }
}

/// Uint16Array : tableau d'entiers non signes 16 bits
class JSUint16Array extends JSTypedArray {
  JSUint16Array({
    required super.buffer,
    required super.byteOffset,
    required super.length,
  }) : super(byteLength: length * 2);

  factory JSUint16Array.fromLength(int length) {
    final buffer = JSArrayBuffer(length * 2);
    return JSUint16Array(buffer: buffer, byteOffset: 0, length: length);
  }

  factory JSUint16Array.fromArray(List<double> values) {
    final array = JSUint16Array.fromLength(values.length);
    for (var i = 0; i < values.length; i++) {
      array.setElement(i, values[i]);
    }
    return array;
  }

  @override
  int get bytesPerElement => 2;

  @override
  String get typeName => 'Uint16Array';

  @override
  double getElement(int index) {
    if (index < 0 || index >= length) {
      return double.nan;
    }
    final byteIndex = byteOffset + index * 2;
    // Little-endian
    final low = buffer.data[byteIndex];
    final high = buffer.data[byteIndex + 1];
    return (low | (high << 8)).toDouble();
  }

  @override
  void setElement(int index, double value) {
    if (index < 0 || index >= length) {
      return;
    }
    final byteIndex = byteOffset + index * 2;
    // For Uint16, convert to unsigned 16-bit
    var intValue = _toSafeInt(value);
    intValue =
        intValue & 0xFFFF; // Mask to 16 bits (handles negative wraparound)
    // Little-endian
    buffer.data[byteIndex] = intValue & 0xFF;
    buffer.data[byteIndex + 1] = (intValue >> 8) & 0xFF;
  }

  @override
  JSTypedArray createSubarray({
    required JSArrayBuffer buffer,
    required int byteOffset,
    required int length,
  }) {
    return JSUint16Array(
      buffer: buffer,
      byteOffset: byteOffset,
      length: length,
    );
  }
}

/// Int32Array : tableau d'entiers signes 32 bits
class JSInt32Array extends JSTypedArray {
  JSInt32Array({
    required super.buffer,
    required super.byteOffset,
    required super.length,
  }) : super(byteLength: length * 4);

  factory JSInt32Array.fromLength(int length) {
    final buffer = JSArrayBuffer(length * 4);
    return JSInt32Array(buffer: buffer, byteOffset: 0, length: length);
  }

  factory JSInt32Array.fromArray(List<double> values) {
    final array = JSInt32Array.fromLength(values.length);
    for (var i = 0; i < values.length; i++) {
      array.setElement(i, values[i]);
    }
    return array;
  }

  @override
  int get bytesPerElement => 4;

  @override
  String get typeName => 'Int32Array';

  @override
  double getElement(int index) {
    if (index < 0 || index >= length) {
      return double.nan;
    }
    final byteIndex = byteOffset + index * 4;
    // Little-endian
    final b0 = buffer.data[byteIndex];
    final b1 = buffer.data[byteIndex + 1];
    final b2 = buffer.data[byteIndex + 2];
    final b3 = buffer.data[byteIndex + 3];
    final value = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
    // Interpreter comme signed int32
    return (value > 2147483647 ? value - 4294967296 : value).toDouble();
  }

  @override
  void setElement(int index, double value) {
    if (index < 0 || index >= length) {
      return;
    }
    final byteIndex = byteOffset + index * 4;
    // Convert to int32 with wraparound
    var intValue = _toSafeInt(value);
    intValue = intValue & 0xFFFFFFFF; // Wrap to 32 bits
    if (intValue >= 0x80000000) intValue -= 0x100000000; // Ifgn extend
    // Little-endian
    buffer.data[byteIndex] = intValue & 0xFF;
    buffer.data[byteIndex + 1] = (intValue >> 8) & 0xFF;
    buffer.data[byteIndex + 2] = (intValue >> 16) & 0xFF;
    buffer.data[byteIndex + 3] = (intValue >> 24) & 0xFF;
  }

  @override
  JSTypedArray createSubarray({
    required JSArrayBuffer buffer,
    required int byteOffset,
    required int length,
  }) {
    return JSInt32Array(buffer: buffer, byteOffset: byteOffset, length: length);
  }
}

/// Uint32Array : tableau d'entiers non signes 32 bits
class JSUint32Array extends JSTypedArray {
  JSUint32Array({
    required super.buffer,
    required super.byteOffset,
    required super.length,
  }) : super(byteLength: length * 4);

  factory JSUint32Array.fromLength(int length) {
    final buffer = JSArrayBuffer(length * 4);
    return JSUint32Array(buffer: buffer, byteOffset: 0, length: length);
  }

  factory JSUint32Array.fromArray(List<double> values) {
    final array = JSUint32Array.fromLength(values.length);
    for (var i = 0; i < values.length; i++) {
      array.setElement(i, values[i]);
    }
    return array;
  }

  @override
  int get bytesPerElement => 4;

  @override
  String get typeName => 'Uint32Array';

  @override
  double getElement(int index) {
    if (index < 0 || index >= length) {
      return double.nan;
    }
    final byteIndex = byteOffset + index * 4;
    // Little-endian
    final b0 = buffer.data[byteIndex];
    final b1 = buffer.data[byteIndex + 1];
    final b2 = buffer.data[byteIndex + 2];
    final b3 = buffer.data[byteIndex + 3];
    return (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)).toDouble();
  }

  @override
  void setElement(int index, double value) {
    if (index < 0 || index >= length) {
      return;
    }
    final byteIndex = byteOffset + index * 4;
    // For Uint32, convert to unsigned 32-bit
    var intValue = _toSafeInt(value);
    intValue =
        intValue & 0xFFFFFFFF; // Mask to 32 bits (handles negative wraparound)
    // Little-endian
    buffer.data[byteIndex] = intValue & 0xFF;
    buffer.data[byteIndex + 1] = (intValue >> 8) & 0xFF;
    buffer.data[byteIndex + 2] = (intValue >> 16) & 0xFF;
    buffer.data[byteIndex + 3] = (intValue >> 24) & 0xFF;
  }

  @override
  JSTypedArray createSubarray({
    required JSArrayBuffer buffer,
    required int byteOffset,
    required int length,
  }) {
    return JSUint32Array(
      buffer: buffer,
      byteOffset: byteOffset,
      length: length,
    );
  }
}

/// Float16Array : tableau de flottants 16 bits (half-precision IEEE 754)
class JSFloat16Array extends JSTypedArray {
  JSFloat16Array({
    required super.buffer,
    required super.byteOffset,
    required super.length,
  }) : super(byteLength: length * 2);

  factory JSFloat16Array.fromLength(int length) {
    final buffer = JSArrayBuffer(length * 2);
    return JSFloat16Array(buffer: buffer, byteOffset: 0, length: length);
  }

  factory JSFloat16Array.fromArray(List<double> values) {
    final array = JSFloat16Array.fromLength(values.length);
    for (var i = 0; i < values.length; i++) {
      array.setElement(i, values[i]);
    }
    return array;
  }

  @override
  int get bytesPerElement => 2;

  @override
  String get typeName => 'Float16Array';

  /// Convert double to float16 (16-bit representation)
  static int doubleToFloat16(double value) {
    if (value.isNaN) {
      return 0x7E00; // NaN representation in float16
    }
    if (value.isInfinite) {
      return value.isNegative ? 0xFC00 : 0x7C00; // -inf or +inf
    }
    if (value == 0.0) {
      return value.isNegative ? 0x8000 : 0x0000; // -0 or +0
    }

    // Handle denormalized numbers and normalized numbers
    final sign = value.isNegative ? 1 : 0;
    final absValue = value.abs();

    // Find exponent and mantissa
    final log2 = math.log(absValue) / math.ln2;
    var exponent = log2.floor();
    var mantissa = absValue / (1 << exponent);

    // Adjust for float16 bias (15)
    exponent += 15;

    if (exponent <= 0) {
      // Denormalized number
      mantissa = absValue / 6.103515625e-5; // 2^(-14)
      exponent = 0;
    } else if (exponent >= 31) {
      // Overflow to infinity
      return sign == 1 ? 0xFC00 : 0x7C00;
    }

    // Convert mantissa to 10-bit integer
    var mantissaInt = ((mantissa - 1.0) * 1024).round();
    if (exponent == 0) {
      mantissaInt = (absValue / 6.103515625e-5).round();
    }

    // Clamp mantissa
    mantissaInt = mantissaInt.clamp(0, 1023);

    // Combine sign, exponent, and mantissa
    return (sign << 15) | (exponent << 10) | mantissaInt;
  }

  /// Convert float16 to double
  static double float16ToDouble(int float16) {
    final sign = (float16 >> 15) & 0x1;
    final exponent = (float16 >> 10) & 0x1F;
    final mantissa = float16 & 0x3FF;

    if (exponent == 0) {
      // Denormalized number or zero
      if (mantissa == 0) {
        return sign == 1 ? -0.0 : 0.0;
      }
      // Denormalized: (-1)^sign * mantissa * 2^(-14)
      return (sign == 1 ? -1.0 : 1.0) * mantissa * 6.103515625e-5;
    } else if (exponent == 31) {
      // Infinity or NaN
      if (mantissa == 0) {
        return sign == 1 ? double.negativeInfinity : double.infinity;
      } else {
        return double.nan;
      }
    }

    // Normalized number: (-1)^sign * (1 + mantissa/1024) * 2^(exponent-15)
    final mantissaValue = 1.0 + (mantissa / 1024.0);
    final exponentValue = exponent - 15;
    final result = mantissaValue * (1 << exponentValue);
    return sign == 1 ? -result : result;
  }

  @override
  double getElement(int index) {
    if (index < 0 || index >= length) {
      return double.nan;
    }
    final byteIndex = byteOffset + index * 2;
    // Read 16-bit value (little-endian)
    final low = buffer.data[byteIndex];
    final high = buffer.data[byteIndex + 1];
    final float16 = (high << 8) | low;
    return float16ToDouble(float16);
  }

  @override
  void setElement(int index, double value) {
    if (index < 0 || index >= length) {
      return;
    }
    final byteIndex = byteOffset + index * 2;
    final float16 = doubleToFloat16(value);
    // Write 16-bit value (little-endian)
    buffer.data[byteIndex] = float16 & 0xFF;
    buffer.data[byteIndex + 1] = (float16 >> 8) & 0xFF;
  }

  @override
  JSTypedArray createSubarray({
    required JSArrayBuffer buffer,
    required int byteOffset,
    required int length,
  }) {
    return JSFloat16Array(
      buffer: buffer,
      byteOffset: byteOffset,
      length: length,
    );
  }
}

/// Float32Array : tableau de flottants 32 bits (IEEE 754)
class JSFloat32Array extends JSTypedArray {
  JSFloat32Array({
    required super.buffer,
    required super.byteOffset,
    required super.length,
  }) : super(byteLength: length * 4);

  factory JSFloat32Array.fromLength(int length) {
    final buffer = JSArrayBuffer(length * 4);
    return JSFloat32Array(buffer: buffer, byteOffset: 0, length: length);
  }

  factory JSFloat32Array.fromArray(List<double> values) {
    final array = JSFloat32Array.fromLength(values.length);
    for (var i = 0; i < values.length; i++) {
      array.setElement(i, values[i]);
    }
    return array;
  }

  @override
  int get bytesPerElement => 4;

  @override
  String get typeName => 'Float32Array';

  @override
  double getElement(int index) {
    if (index < 0 || index >= length) {
      return double.nan;
    }
    final byteIndex = byteOffset + index * 4;
    // Create a temporary Float32List for conversion
    final bytes = Uint8List(4);
    for (var i = 0; i < 4; i++) {
      bytes[i] = buffer.data[byteIndex + i];
    }
    final float32List = Float32List.view(bytes.buffer);
    return float32List[0];
  }

  @override
  void setElement(int index, double value) {
    if (index < 0 || index >= length) {
      return;
    }
    final byteIndex = byteOffset + index * 4;
    // Convert to float32
    final float32List = Float32List(1);
    float32List[0] = value;
    final bytes = float32List.buffer.asUint8List();
    for (var i = 0; i < 4; i++) {
      buffer.data[byteIndex + i] = bytes[i];
    }
  }

  @override
  JSTypedArray createSubarray({
    required JSArrayBuffer buffer,
    required int byteOffset,
    required int length,
  }) {
    return JSFloat32Array(
      buffer: buffer,
      byteOffset: byteOffset,
      length: length,
    );
  }
}

/// Float64Array : tableau de flottants 64 bits (IEEE 754)
class JSFloat64Array extends JSTypedArray {
  JSFloat64Array({
    required super.buffer,
    required super.byteOffset,
    required super.length,
  }) : super(byteLength: length * 8);

  factory JSFloat64Array.fromLength(int length) {
    final buffer = JSArrayBuffer(length * 8);
    return JSFloat64Array(buffer: buffer, byteOffset: 0, length: length);
  }

  factory JSFloat64Array.fromArray(List<double> values) {
    final array = JSFloat64Array.fromLength(values.length);
    for (var i = 0; i < values.length; i++) {
      array.setElement(i, values[i]);
    }
    return array;
  }

  @override
  int get bytesPerElement => 8;

  @override
  String get typeName => 'Float64Array';

  @override
  double getElement(int index) {
    if (index < 0 || index >= length) {
      return double.nan;
    }
    final byteIndex = byteOffset + index * 8;
    // Create a temporary Float64List for conversion
    final bytes = Uint8List(8);
    for (var i = 0; i < 8; i++) {
      bytes[i] = buffer.data[byteIndex + i];
    }
    final float64List = Float64List.view(bytes.buffer);
    return float64List[0];
  }

  @override
  void setElement(int index, double value) {
    if (index < 0 || index >= length) {
      return;
    }
    final byteIndex = byteOffset + index * 8;
    // Stocker directement le float64
    final float64List = Float64List(1);
    float64List[0] = value;
    final bytes = float64List.buffer.asUint8List();
    for (var i = 0; i < 8; i++) {
      buffer.data[byteIndex + i] = bytes[i];
    }
  }

  @override
  JSTypedArray createSubarray({
    required JSArrayBuffer buffer,
    required int byteOffset,
    required int length,
  }) {
    return JSFloat64Array(
      buffer: buffer,
      byteOffset: byteOffset,
      length: length,
    );
  }
}

/// DataView : vue flexible sur un ArrayBuffer
/// Permet de lire/ecrire des types differents a des positions arbitraires
class JSDataView extends JSObject {
  final JSArrayBuffer buffer;
  final int byteOffset;
  final int byteLength;

  JSDataView({required this.buffer, this.byteOffset = 0, int? byteLength})
    : byteLength = byteLength ?? (buffer.byteLength - byteOffset) {
    _setupProperties();
  }

  void _setupProperties() {
    setProperty('buffer', buffer);
    setProperty('byteOffset', JSValueFactory.number(byteOffset.toDouble()));
    setProperty('byteLength', JSValueFactory.number(byteLength.toDouble()));

    // getInt8(byteOffset)
    setProperty(
      'getInt8',
      JSNativeFunction(
        functionName: 'getInt8',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSError('getInt8 requires byteOffset');
          }
          final offset = _toSafeInt(args[0].toNumber());
          if (offset < 0 || offset >= byteLength) {
            throw JSError('Offset is out of bounds');
          }
          final byte = buffer.data[byteOffset + offset];
          final value = byte > 127 ? byte - 256 : byte;
          return JSValueFactory.number(value.toDouble());
        },
      ),
    );

    // getUint8(byteOffset)
    setProperty(
      'getUint8',
      JSNativeFunction(
        functionName: 'getUint8',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSError('getUint8 requires byteOffset');
          }
          final offset = _toSafeInt(args[0].toNumber());
          if (offset < 0 || offset >= byteLength) {
            throw JSError('Offset is out of bounds');
          }
          return JSValueFactory.number(
            buffer.data[byteOffset + offset].toDouble(),
          );
        },
      ),
    );

    // setInt8(byteOffset, value)
    setProperty(
      'setInt8',
      JSNativeFunction(
        functionName: 'setInt8',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSError('setInt8 requires byteOffset and value');
          }
          final offset = _toSafeInt(args[0].toNumber());
          final value = _toSafeInt(args[1].toNumber());
          if (offset < 0 || offset >= byteLength) {
            throw JSError('Offset is out of bounds');
          }
          var clamped = value.clamp(-128, 127);
          if (clamped < 0) clamped += 256;
          buffer.data[byteOffset + offset] = clamped;
          return JSValueFactory.undefined();
        },
      ),
    );

    // setUint8(byteOffset, value)
    setProperty(
      'setUint8',
      JSNativeFunction(
        functionName: 'setUint8',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSError('setUint8 requires byteOffset and value');
          }
          final offset = _toSafeInt(args[0].toNumber());
          final value = _toSafeInt(args[1].toNumber());
          if (offset < 0 || offset >= byteLength) {
            throw JSError('Offset is out of bounds');
          }
          buffer.data[byteOffset + offset] = value.clamp(0, 255);
          return JSValueFactory.undefined();
        },
      ),
    );

    // getInt16(byteOffset, littleEndian)
    setProperty(
      'getInt16',
      JSNativeFunction(
        functionName: 'getInt16',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSError('getInt16 requires byteOffset');
          }
          final offset = _toSafeInt(args[0].toNumber());
          final littleEndian = args.length > 1 ? args[1].toBoolean() : false;

          if (offset < 0 || offset + 1 >= byteLength) {
            throw JSError('Offset is out of bounds');
          }

          final b0 = buffer.data[byteOffset + offset];
          final b1 = buffer.data[byteOffset + offset + 1];

          final value = littleEndian ? (b0 | (b1 << 8)) : ((b0 << 8) | b1);

          // Interpreter comme signed int16
          final signed = value > 32767 ? value - 65536 : value;
          return JSValueFactory.number(signed.toDouble());
        },
      ),
    );

    // getUint16(byteOffset, littleEndian)
    setProperty(
      'getUint16',
      JSNativeFunction(
        functionName: 'getUint16',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSError('getUint16 requires byteOffset');
          }
          final offset = _toSafeInt(args[0].toNumber());
          final littleEndian = args.length > 1 ? args[1].toBoolean() : false;

          if (offset < 0 || offset + 1 >= byteLength) {
            throw JSError('Offset is out of bounds');
          }

          final b0 = buffer.data[byteOffset + offset];
          final b1 = buffer.data[byteOffset + offset + 1];

          final value = littleEndian ? (b0 | (b1 << 8)) : ((b0 << 8) | b1);

          return JSValueFactory.number(value.toDouble());
        },
      ),
    );

    // setInt16(byteOffset, value, littleEndian)
    setProperty(
      'setInt16',
      JSNativeFunction(
        functionName: 'setInt16',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSError('setInt16 requires byteOffset and value');
          }
          final offset = _toSafeInt(args[0].toNumber());
          var value = _toSafeInt(args[1].toNumber());
          final littleEndian = args.length > 2 ? args[2].toBoolean() : false;

          if (offset < 0 || offset + 1 >= byteLength) {
            throw JSError('Offset is out of bounds');
          }

          value = value.clamp(-32768, 32767);
          if (value < 0) value += 65536;

          if (littleEndian) {
            buffer.data[byteOffset + offset] = value & 0xFF;
            buffer.data[byteOffset + offset + 1] = (value >> 8) & 0xFF;
          } else {
            buffer.data[byteOffset + offset] = (value >> 8) & 0xFF;
            buffer.data[byteOffset + offset + 1] = value & 0xFF;
          }

          return JSValueFactory.undefined();
        },
      ),
    );

    // setUint16(byteOffset, value, littleEndian)
    setProperty(
      'setUint16',
      JSNativeFunction(
        functionName: 'setUint16',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSError('setUint16 requires byteOffset and value');
          }
          final offset = _toSafeInt(args[0].toNumber());
          var value = _toSafeInt(args[1].toNumber());
          final littleEndian = args.length > 2 ? args[2].toBoolean() : false;

          if (offset < 0 || offset + 1 >= byteLength) {
            throw JSError('Offset is out of bounds');
          }

          value = value.clamp(0, 65535);

          if (littleEndian) {
            buffer.data[byteOffset + offset] = value & 0xFF;
            buffer.data[byteOffset + offset + 1] = (value >> 8) & 0xFF;
          } else {
            buffer.data[byteOffset + offset] = (value >> 8) & 0xFF;
            buffer.data[byteOffset + offset + 1] = value & 0xFF;
          }

          return JSValueFactory.undefined();
        },
      ),
    );

    // getInt32(byteOffset, littleEndian)
    setProperty(
      'getInt32',
      JSNativeFunction(
        functionName: 'getInt32',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSError('getInt32 requires byteOffset');
          }
          final offset = _toSafeInt(args[0].toNumber());
          final littleEndian = args.length > 1 ? args[1].toBoolean() : false;

          if (offset < 0 || offset + 3 >= byteLength) {
            throw JSError('Offset is out of bounds');
          }

          final b0 = buffer.data[byteOffset + offset];
          final b1 = buffer.data[byteOffset + offset + 1];
          final b2 = buffer.data[byteOffset + offset + 2];
          final b3 = buffer.data[byteOffset + offset + 3];

          final value = littleEndian
              ? (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24))
              : ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3);

          // Interpreter comme signed int32
          final signed = value > 2147483647 ? value - 4294967296 : value;
          return JSValueFactory.number(signed.toDouble());
        },
      ),
    );

    // getUint32(byteOffset, littleEndian)
    setProperty(
      'getUint32',
      JSNativeFunction(
        functionName: 'getUint32',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSError('getUint32 requires byteOffset');
          }
          final offset = _toSafeInt(args[0].toNumber());
          final littleEndian = args.length > 1 ? args[1].toBoolean() : false;

          if (offset < 0 || offset + 3 >= byteLength) {
            throw JSError('Offset is out of bounds');
          }

          final b0 = buffer.data[byteOffset + offset];
          final b1 = buffer.data[byteOffset + offset + 1];
          final b2 = buffer.data[byteOffset + offset + 2];
          final b3 = buffer.data[byteOffset + offset + 3];

          final value = littleEndian
              ? (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24))
              : ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3);

          return JSValueFactory.number(value.toDouble());
        },
      ),
    );

    // setInt32(byteOffset, value, littleEndian)
    setProperty(
      'setInt32',
      JSNativeFunction(
        functionName: 'setInt32',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSError('setInt32 requires byteOffset and value');
          }
          final offset = _toSafeInt(args[0].toNumber());
          var value = _toSafeInt(args[1].toNumber());
          final littleEndian = args.length > 2 ? args[2].toBoolean() : false;

          if (offset < 0 || offset + 3 >= byteLength) {
            throw JSError('Offset is out of bounds');
          }

          value = value.clamp(-2147483648, 2147483647);
          if (value < 0) value += 4294967296;

          if (littleEndian) {
            buffer.data[byteOffset + offset] = value & 0xFF;
            buffer.data[byteOffset + offset + 1] = (value >> 8) & 0xFF;
            buffer.data[byteOffset + offset + 2] = (value >> 16) & 0xFF;
            buffer.data[byteOffset + offset + 3] = (value >> 24) & 0xFF;
          } else {
            buffer.data[byteOffset + offset] = (value >> 24) & 0xFF;
            buffer.data[byteOffset + offset + 1] = (value >> 16) & 0xFF;
            buffer.data[byteOffset + offset + 2] = (value >> 8) & 0xFF;
            buffer.data[byteOffset + offset + 3] = value & 0xFF;
          }

          return JSValueFactory.undefined();
        },
      ),
    );

    // setUint32(byteOffset, value, littleEndian)
    setProperty(
      'setUint32',
      JSNativeFunction(
        functionName: 'setUint32',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSError('setUint32 requires byteOffset and value');
          }
          final offset = _toSafeInt(args[0].toNumber());
          var value = _toSafeInt(args[1].toNumber());
          final littleEndian = args.length > 2 ? args[2].toBoolean() : false;

          if (offset < 0 || offset + 3 >= byteLength) {
            throw JSError('Offset is out of bounds');
          }

          value = value.clamp(0, 4294967295);

          if (littleEndian) {
            buffer.data[byteOffset + offset] = value & 0xFF;
            buffer.data[byteOffset + offset + 1] = (value >> 8) & 0xFF;
            buffer.data[byteOffset + offset + 2] = (value >> 16) & 0xFF;
            buffer.data[byteOffset + offset + 3] = (value >> 24) & 0xFF;
          } else {
            buffer.data[byteOffset + offset] = (value >> 24) & 0xFF;
            buffer.data[byteOffset + offset + 1] = (value >> 16) & 0xFF;
            buffer.data[byteOffset + offset + 2] = (value >> 8) & 0xFF;
            buffer.data[byteOffset + offset + 3] = value & 0xFF;
          }

          return JSValueFactory.undefined();
        },
      ),
    );

    // getFloat32(byteOffset, littleEndian)
    setProperty(
      'getFloat32',
      JSNativeFunction(
        functionName: 'getFloat32',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSError('getFloat32 requires byteOffset');
          }
          final offset = _toSafeInt(args[0].toNumber());
          final littleEndian = args.length > 1 ? args[1].toBoolean() : false;

          if (offset < 0 || offset + 3 >= byteLength) {
            throw JSError('Offset is out of bounds');
          }

          final bytes = Uint8List(4);
          for (var i = 0; i < 4; i++) {
            bytes[i] = buffer.data[byteOffset + offset + i];
          }

          // Convert to Float32
          final float32List = littleEndian
              ? Float32List.view(bytes.buffer)
              : Float32List.view(
                  Uint8List.fromList([
                    bytes[3],
                    bytes[2],
                    bytes[1],
                    bytes[0],
                  ]).buffer,
                );

          return JSValueFactory.number(float32List[0]);
        },
      ),
    );

    // getFloat64(byteOffset, littleEndian)
    setProperty(
      'getFloat64',
      JSNativeFunction(
        functionName: 'getFloat64',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSError('getFloat64 requires byteOffset');
          }
          final offset = _toSafeInt(args[0].toNumber());
          final littleEndian = args.length > 1 ? args[1].toBoolean() : false;

          if (offset < 0 || offset + 7 >= byteLength) {
            throw JSError('Offset is out of bounds');
          }

          final bytes = Uint8List(8);
          for (var i = 0; i < 8; i++) {
            bytes[i] = buffer.data[byteOffset + offset + i];
          }

          // Convert to Float64
          final float64List = littleEndian
              ? Float64List.view(bytes.buffer)
              : Float64List.view(
                  Uint8List.fromList([
                    bytes[7],
                    bytes[6],
                    bytes[5],
                    bytes[4],
                    bytes[3],
                    bytes[2],
                    bytes[1],
                    bytes[0],
                  ]).buffer,
                );

          return JSValueFactory.number(float64List[0]);
        },
      ),
    );

    // setFloat32(byteOffset, value, littleEndian)
    setProperty(
      'setFloat32',
      JSNativeFunction(
        functionName: 'setFloat32',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSError('setFloat32 requires byteOffset and value');
          }
          final offset = _toSafeInt(args[0].toNumber());
          final value = args[1].toNumber();
          final littleEndian = args.length > 2 ? args[2].toBoolean() : false;

          if (offset < 0 || offset + 3 >= byteLength) {
            throw JSError('Offset is out of bounds');
          }

          // Convertir en bytes
          final float32List = Float32List(1);
          float32List[0] = value;
          final bytes = float32List.buffer.asUint8List();

          if (littleEndian) {
            for (var i = 0; i < 4; i++) {
              buffer.data[byteOffset + offset + i] = bytes[i];
            }
          } else {
            for (var i = 0; i < 4; i++) {
              buffer.data[byteOffset + offset + i] = bytes[3 - i];
            }
          }

          return JSValueFactory.undefined();
        },
      ),
    );

    // setFloat64(byteOffset, value, littleEndian)
    setProperty(
      'setFloat64',
      JSNativeFunction(
        functionName: 'setFloat64',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSError('setFloat64 requires byteOffset and value');
          }
          final offset = _toSafeInt(args[0].toNumber());
          final value = args[1].toNumber();
          final littleEndian = args.length > 2 ? args[2].toBoolean() : false;

          if (offset < 0 || offset + 7 >= byteLength) {
            throw JSError('Offset is out of bounds');
          }

          // Convertir en bytes
          final float64List = Float64List(1);
          float64List[0] = value;
          final bytes = float64List.buffer.asUint8List();

          if (littleEndian) {
            for (var i = 0; i < 8; i++) {
              buffer.data[byteOffset + offset + i] = bytes[i];
            }
          } else {
            for (var i = 0; i < 8; i++) {
              buffer.data[byteOffset + offset + i] = bytes[7 - i];
            }
          }

          return JSValueFactory.undefined();
        },
      ),
    );
  }

  @override
  String toString() => '[object DataView]';
}

/// BigInt64Array: 64-bit signed integer array using BigInt values
class JSBigInt64Array extends JSTypedArray {
  JSBigInt64Array({
    required super.buffer,
    required super.byteOffset,
    required super.length,
  }) : super(byteLength: length * 8);

  factory JSBigInt64Array.fromLength(int length) {
    final buffer = JSArrayBuffer(length * 8);
    return JSBigInt64Array(buffer: buffer, byteOffset: 0, length: length);
  }

  factory JSBigInt64Array.fromArray(List<BigInt> values) {
    final array = JSBigInt64Array.fromLength(values.length);
    for (var i = 0; i < values.length; i++) {
      array.setBigIntElement(i, values[i]);
    }
    return array;
  }

  @override
  int get bytesPerElement => 8;

  @override
  String get typeName => 'BigInt64Array';

  /// Get element as BigInt
  BigInt getBigIntElement(int index) {
    if (index < 0 || index >= length) {
      return BigInt.zero;
    }
    final byteIndex = byteOffset + index * 8;
    final bytes = Int64List(1);
    final byteView = bytes.buffer.asUint8List();
    for (var i = 0; i < 8; i++) {
      byteView[i] = buffer.data[byteIndex + i];
    }
    return BigInt.from(bytes[0]);
  }

  /// Set element from BigInt
  void setBigIntElement(int index, BigInt value) {
    if (index < 0 || index >= length) {
      return;
    }
    final byteIndex = byteOffset + index * 8;
    // Clamp to signed 64-bit range
    final int64Value = value.toSigned(64).toInt();
    final bytes = Int64List(1);
    bytes[0] = int64Value;
    final byteView = bytes.buffer.asUint8List();
    for (var i = 0; i < 8; i++) {
      buffer.data[byteIndex + i] = byteView[i];
    }
  }

  @override
  double getElement(int index) {
    // Return as double for compatibility
    return getBigIntElement(index).toDouble();
  }

  @override
  void setElement(int index, double value) {
    // Convert double to BigInt
    setBigIntElement(index, BigInt.from(value.truncate()));
  }

  @override
  JSTypedArray createSubarray({
    required JSArrayBuffer buffer,
    required int byteOffset,
    required int length,
  }) {
    return JSBigInt64Array(
      buffer: buffer,
      byteOffset: byteOffset,
      length: length,
    );
  }
}

/// BigUint64Array: 64-bit unsigned integer array using BigInt values
class JSBigUint64Array extends JSTypedArray {
  JSBigUint64Array({
    required super.buffer,
    required super.byteOffset,
    required super.length,
  }) : super(byteLength: length * 8);

  factory JSBigUint64Array.fromLength(int length) {
    final buffer = JSArrayBuffer(length * 8);
    return JSBigUint64Array(buffer: buffer, byteOffset: 0, length: length);
  }

  factory JSBigUint64Array.fromArray(List<BigInt> values) {
    final array = JSBigUint64Array.fromLength(values.length);
    for (var i = 0; i < values.length; i++) {
      array.setBigIntElement(i, values[i]);
    }
    return array;
  }

  @override
  int get bytesPerElement => 8;

  @override
  String get typeName => 'BigUint64Array';

  /// Get element as BigInt
  BigInt getBigIntElement(int index) {
    if (index < 0 || index >= length) {
      return BigInt.zero;
    }
    final byteIndex = byteOffset + index * 8;
    final bytes = Uint64List(1);
    final byteView = bytes.buffer.asUint8List();
    for (var i = 0; i < 8; i++) {
      byteView[i] = buffer.data[byteIndex + i];
    }
    return BigInt.from(bytes[0]);
  }

  /// Set element from BigInt
  void setBigIntElement(int index, BigInt value) {
    if (index < 0 || index >= length) {
      return;
    }
    final byteIndex = byteOffset + index * 8;
    // Clamp to unsigned 64-bit range
    final uint64Value = value.toUnsigned(64).toInt();
    final bytes = Uint64List(1);
    bytes[0] = uint64Value;
    final byteView = bytes.buffer.asUint8List();
    for (var i = 0; i < 8; i++) {
      buffer.data[byteIndex + i] = byteView[i];
    }
  }

  @override
  double getElement(int index) {
    // Return as double for compatibility
    return getBigIntElement(index).toDouble();
  }

  @override
  void setElement(int index, double value) {
    // Convert double to BigInt
    setBigIntElement(index, BigInt.from(value.truncate()));
  }

  @override
  JSTypedArray createSubarray({
    required JSArrayBuffer buffer,
    required int byteOffset,
    required int length,
  }) {
    return JSBigUint64Array(
      buffer: buffer,
      byteOffset: byteOffset,
      length: length,
    );
  }
}
