import 'js_value.dart';
import 'js_symbol.dart';
import 'native_functions.dart';

/// Interface for JavaScript iterators
/// Conforms to the ECMAScript iteration protocol
abstract class JSIterator extends JSObject {
  JSIterator() : super() {
    // Iterators are themselves iterable (return this for Symbol.iterator)
    setProperty(
      JSSymbol.iterator.toString(),
      JSNativeFunction(
        functionName: 'Symbol.iterator',
        nativeImpl: (args) => this,
      ),
    );
  }

  /// Method next() of the iterator
  /// Returns an IteratorResult {value, done}
  JSValue next([JSValue? value]);

  /// Optional return() method of the iterator
  JSValue? returnMethod([JSValue? value]) => null;

  /// Optional throw() method of the iterator
  JSValue? throwMethod([JSValue? exception]) => null;

  /// Marks this object as an iterator
  bool get isIterator => true;

  /// Iterators return themselves as an iterator
  JSIterator? getIterator() => this;
}

/// Iteration result {value, done}
class JSIteratorResult extends JSObject {
  final JSValue value;
  final bool done;

  JSIteratorResult(this.value, this.done) : super();

  /// Creates an IteratorResult object
  static JSValue create(JSValue value, bool done) {
    final result = JSValueFactory.object({});
    result.setProperty('value', value);
    result.setProperty('done', JSValueFactory.boolean(done));
    return result;
  }

  @override
  JSValue getProperty(String name) {
    switch (name) {
      case 'value':
        return value;
      case 'done':
        return JSValueFactory.boolean(done);
      default:
        return super.getProperty(name);
    }
  }
}

/// Implementation of an array iterator
class JSArrayIterator extends JSIterator {
  final JSArray array;
  int currentIndex = 0;
  final IteratorKind kind;

  JSArrayIterator(this.array, this.kind) : super() {
    // Expose the next method as a JavaScript property
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
    if (currentIndex >= array.length) {
      // Iterator exhausted
      return JSIteratorResult.create(JSValueFactory.undefined(), true);
    }

    final index = currentIndex++;
    switch (kind) {
      case IteratorKind.valueKind:
        final elementValue = array.getProperty(index.toString());
        return JSIteratorResult.create(elementValue, false);

      case IteratorKind.keys:
        return JSIteratorResult.create(JSValueFactory.number(index), false);

      case IteratorKind.entries:
        final elementValue = array.getProperty(index.toString());
        final entry = JSValueFactory.array([
          JSValueFactory.number(index),
          elementValue,
        ]);
        return JSIteratorResult.create(entry, false);
    }
  }

  @override
  JSValue? returnMethod([JSValue? value]) {
    // Mark iterator as terminated
    currentIndex = array.length;
    return JSIteratorResult.create(value ?? JSValueFactory.undefined(), true);
  }

  @override
  String toString() => '[object Array Iterator]';
}

/// Implementation of a string iterator
class JSStringIterator extends JSIterator {
  final String string;
  int currentIndex = 0;

  JSStringIterator(this.string) : super() {
    // Expose the next method as a JavaScript property
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
    if (currentIndex >= string.length) {
      return JSIteratorResult.create(JSValueFactory.undefined(), true);
    }

    // Support for Unicode - for non-BMP characters
    int codeUnit = string.codeUnitAt(currentIndex);
    String char;

    // Check if it's a surrogate pair
    if (codeUnit >= 0xD800 &&
        codeUnit <= 0xDBFF &&
        currentIndex + 1 < string.length) {
      final next = string.codeUnitAt(currentIndex + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        // Surrogate pair
        char = string.substring(currentIndex, currentIndex + 2);
        currentIndex += 2;
      } else {
        char = string[currentIndex++];
      }
    } else {
      char = string[currentIndex++];
    }

    return JSIteratorResult.create(JSValueFactory.string(char), false);
  }

  @override
  String toString() => '[object String Iterator]';
}

/// Implementation of a map iterator
class JSMapIterator extends JSIterator {
  final JSMap map;
  final IteratorKind kind;
  final Iterator<MapEntry<JSValue, JSValue>> _iterator;

  JSMapIterator(this.map, this.kind)
    : _iterator = map.entries.iterator,
      super() {
    // Set up the next method as a JavaScript property
    setProperty(
      'next',
      JSNativeFunction(functionName: 'next', nativeImpl: (args) => next()),
    );
  }

  @override
  JSValue next([JSValue? value]) {
    if (!_iterator.moveNext()) {
      return JSIteratorResult.create(JSValueFactory.undefined(), true);
    }

    final entry = _iterator.current;
    switch (kind) {
      case IteratorKind.valueKind:
        return JSIteratorResult.create(entry.value, false);
      case IteratorKind.keys:
        return JSIteratorResult.create(entry.key, false);
      case IteratorKind.entries:
        final pair = JSValueFactory.array([entry.key, entry.value]);
        return JSIteratorResult.create(pair, false);
    }
  }

  @override
  String toString() => '[object Map Iterator]';
}

/// Implementation d'un iterateur de set
class JSSetIterator extends JSIterator {
  final JSSet set;
  final IteratorKind kind;
  final Iterator<JSValue> _iterator;

  JSSetIterator(this.set, [this.kind = IteratorKind.valueKind])
    : _iterator = set.values.iterator,
      super() {
    // Set up the next method as a JavaScript property
    setProperty(
      'next',
      JSNativeFunction(functionName: 'next', nativeImpl: (args) => next()),
    );
  }

  @override
  JSValue next([JSValue? value]) {
    if (!_iterator.moveNext()) {
      return JSIteratorResult.create(JSValueFactory.undefined(), true);
    }

    final currentValue = _iterator.current;
    switch (kind) {
      case IteratorKind.valueKind:
        return JSIteratorResult.create(currentValue, false);
      case IteratorKind.keys:
        // For Set, keys and values are the same
        return JSIteratorResult.create(currentValue, false);
      case IteratorKind.entries:
        // For Set entries, return [value, value] pairs
        final pair = JSValueFactory.array([currentValue, currentValue]);
        return JSIteratorResult.create(pair, false);
    }
  }

  @override
  String toString() => '[object Set Iterator]';
}

enum IteratorKind {
  valueKind, // Renamed from values
  keys,
  entries,
}

/// Iteration protocol - extension to add Symbol.iterator
extension JSIterableExtension on JSObject {
  /// Add Symbol.iterator to an object
  void makeIterable(JSIterator Function() iteratorFactory) {
    setProperty(
      JSSymbol.iterator.toString(),
      JSValueFactory.function('Symbol.iterator', (
        context,
        thisBinding,
        arguments,
      ) {
        return iteratorFactory();
      }),
    );
  }

  /// Verifies if the object is iterable
  bool get isIterable {
    return hasProperty(JSSymbol.iterator.toString());
  }

  /// Gets the iterator for this object
  JSIterator? getIterator() {
    // If it's already an iterator, return it directly
    if (this is JSIterator) {
      return this as JSIterator;
    }

    // Handle known object types directly
    if (this is JSArray) {
      return JSArrayIterator(this as JSArray, IteratorKind.valueKind);
    }

    if (this is JSMap) {
      return JSMapIterator(this as JSMap, IteratorKind.valueKind);
    }

    if (this is JSSet) {
      return JSSetIterator(this as JSSet, IteratorKind.valueKind);
    }

    if (this is JSStringObject) {
      return JSStringIterator((this as JSStringObject).primitiveValue);
    }

    // For other objects, we cannot yet call the custom
    // Symbol.iterator function without access to the evaluator
    return null;
  }
}

/// Extension to allow iteration of primitive strings
extension JSStringIterableExtension on JSString {
  /// Support iteration for primitive strings
  JSStringIterator getIterator() => JSStringIterator(value);
}

/// Support iteration for Map
extension JSMapIterableExtension on JSMap {
  /// Initializes Symbol.iterator for maps
  void initializeIterator() {
    // [Symbol.iterator]() for values by default
    setProperty(
      JSSymbol.iterator.toString(),
      JSNativeFunction(
        functionName: 'Symbol.iterator',
        nativeImpl: (args) {
          return JSMapIterator(this, IteratorKind.entries);
        },
      ),
    );

    // Iteration methods
    setProperty(
      'values',
      JSNativeFunction(
        functionName: 'values',
        nativeImpl: (args) {
          return JSMapIterator(this, IteratorKind.valueKind);
        },
      ),
    );

    setProperty(
      'keys',
      JSNativeFunction(
        functionName: 'keys',
        nativeImpl: (args) {
          return JSMapIterator(this, IteratorKind.keys);
        },
      ),
    );

    setProperty(
      'entries',
      JSNativeFunction(
        functionName: 'entries',
        nativeImpl: (args) {
          return JSMapIterator(this, IteratorKind.entries);
        },
      ),
    );
  }
}

/// Support iteration for Set
extension JSSetIterableExtension on JSSet {
  /// Initializes Symbol.iterator for sets
  void initializeIterator() {
    // [Symbol.iterator]() for values by default
    setProperty(
      JSSymbol.iterator.toString(),
      JSNativeFunction(
        functionName: 'Symbol.iterator',
        nativeImpl: (args) {
          return JSSetIterator(this, IteratorKind.valueKind);
        },
      ),
    );

    // Iteration methods
    setProperty(
      'values',
      JSNativeFunction(
        functionName: 'values',
        nativeImpl: (args) {
          return JSSetIterator(this, IteratorKind.valueKind);
        },
      ),
    );

    setProperty(
      'keys',
      JSNativeFunction(
        functionName: 'keys',
        nativeImpl: (args) {
          return JSSetIterator(this, IteratorKind.keys);
        },
      ),
    );

    setProperty(
      'entries',
      JSNativeFunction(
        functionName: 'entries',
        nativeImpl: (args) {
          return JSSetIterator(this, IteratorKind.entries);
        },
      ),
    );
  }
}

/// Support iteration for String
/// Now integrated directly into JSString via extension

/// Utilities for iteration
/// ES2020: Implementation of a regex match iterator for matchAll()
class JSRegExpMatchIterator extends JSIterator {
  final String string;
  final RegExp regex;
  final Iterator<RegExpMatch> _matchIterator;
  bool _exhausted = false;

  JSRegExpMatchIterator(this.string, this.regex)
    : _matchIterator = regex.allMatches(string).iterator,
      super() {
    // Expose the next method as a JavaScript property
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
    if (_exhausted || !_matchIterator.moveNext()) {
      _exhausted = true;
      return JSIteratorResult.create(JSValueFactory.undefined(), true);
    }

    final match = _matchIterator.current;

    // Create an array-like object with match properties
    // Format: [fullMatch, group1, group2, ..., groupN]
    final matchArray = <JSValue>[];

    // Add the complete match
    matchArray.add(JSValueFactory.string(match.group(0) ?? ''));

    // Add all capture groups
    for (int i = 1; i <= match.groupCount; i++) {
      final group = match.group(i);
      matchArray.add(
        group != null
            ? JSValueFactory.string(group)
            : JSValueFactory.undefined(),
      );
    }

    final resultArray = JSValueFactory.array(matchArray);

    // Add supplementary match properties
    // index: position of the match in the string
    resultArray.setProperty(
      'index',
      JSValueFactory.number(match.start.toDouble()),
    );

    // input: the original string
    resultArray.setProperty('input', JSValueFactory.string(string));

    // groups: object containing named groups (ES2018)
    final groupsObj = JSValueFactory.object({});
    // Retrieve named groups if they exist
    final pattern = regex.pattern;
    final namedGroupPattern = RegExp(r'\(\?<([^>]+)>');
    final namedMatches = namedGroupPattern.allMatches(pattern);

    for (final nameMatch in namedMatches) {
      final groupName = nameMatch.group(1);
      if (groupName != null) {
        try {
          final value = match.namedGroup(groupName);
          groupsObj.setProperty(
            groupName,
            value != null
                ? JSValueFactory.string(value)
                : JSValueFactory.undefined(),
          );
        } catch (e) {
          // Named group doesn't exist in this match
          groupsObj.setProperty(groupName, JSValueFactory.undefined());
        }
      }
    }

    resultArray.setProperty('groups', groupsObj);

    return JSIteratorResult.create(resultArray, false);
  }

  @override
  String toString() => '[object RegExp String Iterator]';
}

class IteratorUtils {
  /// Converts an iterable to an array
  static JSArray iterableToArray(JSObject iterable) {
    final iterator = iterable.getIterator();
    if (iterator == null) {
      throw JSException(JSValueFactory.string('Object is not iterable'));
    }

    final result = JSValueFactory.array([]);

    while (true) {
      final next = iterator.next();
      // next is a JSValue, so we must cast it to JSObject to access properties
      if (next is! JSObject) break;

      final done = next.getProperty('done').toBoolean();
      if (done) break;

      final value = next.getProperty('value');
      result.setProperty(result.length.toString(), value);
      // Increment length manually since we can't use push
      result.setProperty('length', JSValueFactory.number(result.length + 1));
    }

    return result;
  }

  /// Verifies if a value is iterable
  static bool isIterable(JSValue value) {
    // Primitive strings are iterable
    if (value.isString) return true;

    if (!value.isObject) return false;
    final obj = value as JSObject;
    return obj.hasProperty(JSSymbol.iterator.toString());
  }

  /// Gets the iterator for a value
  static JSIterator? getIterator(JSValue value) {
    if (!isIterable(value)) return null;

    // Special handling for primitive strings
    if (value.isString) {
      return (value as JSString).getIterator();
    }

    final obj = value as JSObject;
    return obj.getIterator();
  }
}
