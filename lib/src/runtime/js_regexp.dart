/// Implementation of JavaScript regular expressions
/// Support for /pattern/flags, RegExp(), and associated methods
library;

import 'js_value.dart';
import 'native_functions.dart';

/// JavaScript RegExp object - represents a regular expression
class JSRegExp extends JSObject {
  final RegExp _dartRegExp;
  final String _source;
  final String _flags;
  final List<String> _groupNames; // ES2018: Named capture groups

  JSRegExp(this._source, this._flags)
    : _dartRegExp = _createDartRegExp(_source, _flags),
      _groupNames = _parseGroupNames(_source) {
    // Initialize RegExp properties
    setProperty('source', JSValueFactory.string(_source));
    setProperty('flags', JSValueFactory.string(_flags));
    setProperty('global', JSValueFactory.boolean(global));
    setProperty('ignoreCase', JSValueFactory.boolean(ignoreCase));
    setProperty('multiline', JSValueFactory.boolean(multiline));
    setProperty('sticky', JSValueFactory.boolean(sticky));
    setProperty('unicode', JSValueFactory.boolean(unicode));
    setProperty('unicodeSets', JSValueFactory.boolean(unicodeSets)); // ES2024
    setProperty('dotAll', JSValueFactory.boolean(dotAll));
    setProperty('hasIndices', JSValueFactory.boolean(hasIndices)); // ES2022
    setProperty('lastIndex', JSValueFactory.number(0));

    // Add RegExp methods
    setProperty(
      'test',
      JSNativeFunction(
        functionName: 'test',
        nativeImpl: (args) {
          if (args.isEmpty) return JSValueFactory.boolean(false);
          final input = args[0].toString();
          return JSValueFactory.boolean(test(input));
        },
      ),
    );

    setProperty(
      'exec',
      JSNativeFunction(
        functionName: 'exec',
        nativeImpl: (args) {
          if (args.isEmpty) return JSValueFactory.nullValue();
          final input = args[0].toString();
          return exec(input);
        },
      ),
    );
  }

  /// Parse captured group names from the pattern (ES2018)
  static List<String> _parseGroupNames(String source) {
    final groupNamePattern = RegExp(r'\(\?<(\w+)>');
    final matches = groupNamePattern.allMatches(source);
    return matches.map((m) => m.group(1)!).toList();
  }

  /// Create a Dart RegExp from JavaScript pattern and flags
  static RegExp _createDartRegExp(String source, String flags) {
    bool multiLine = flags.contains('m');
    bool caseSensitive = !flags.contains('i');
    // ES2024: unicodeSets (v) and unicode (u) are mutually exclusive
    // Dart only supports 'u' flag, so if 'v' is present, treat it as 'u'
    bool unicode = flags.contains('u') || flags.contains('v');
    bool dotAll = flags.contains('s');

    return RegExp(
      source,
      multiLine: multiLine,
      caseSensitive: caseSensitive,
      unicode: unicode,
      dotAll: dotAll,
    );
  }

  /// JavaScript RegExp properties
  String get source => _source;
  String get flags => _flags;
  bool get global => _flags.contains('g');
  bool get ignoreCase => _flags.contains('i');
  bool get multiline => _flags.contains('m');
  bool get sticky => _flags.contains('y');
  bool get unicode => _flags.contains('u');
  bool get unicodeSets => _flags.contains('v'); // ES2024: Unicode sets
  bool get dotAll => _flags.contains('s');
  bool get hasIndices => _flags.contains('d'); // ES2022: Match indices

  /// Access to the underlying Dart RegExp for String methods
  RegExp get dartRegExp => _dartRegExp;

  // Property lastIndex for the global flag
  int lastIndex = 0;

  @override
  JSValue getProperty(String name) {
    switch (name) {
      case 'source':
        return JSValueFactory.string(source);
      case 'flags':
        return JSValueFactory.string(flags);
      case 'global':
        return JSValueFactory.boolean(global);
      case 'ignoreCase':
        return JSValueFactory.boolean(ignoreCase);
      case 'multiline':
        return JSValueFactory.boolean(multiline);
      case 'sticky':
        return JSValueFactory.boolean(sticky);
      case 'unicode':
        return JSValueFactory.boolean(unicode);
      case 'dotAll':
        return JSValueFactory.boolean(dotAll);
      case 'hasIndices': // ES2022
        return JSValueFactory.boolean(hasIndices);
      case 'lastIndex':
        return JSValueFactory.number(lastIndex.toDouble());
      default:
        return super.getProperty(name);
    }
  }

  @override
  void setProperty(String name, JSValue value) {
    if (name == 'lastIndex') {
      lastIndex = value.toNumber().floor();
    } else {
      super.setProperty(name, value);
    }
  }

  /// test() - tests if the regex matches a string
  bool test(String input) {
    if (global) {
      final match = _dartRegExp.firstMatch(input.substring(lastIndex));
      if (match != null) {
        lastIndex += match.end;
        return true;
      } else {
        lastIndex = 0;
        return false;
      }
    } else {
      return _dartRegExp.hasMatch(input);
    }
  }

  /// exec() - executes the regex and returns match details
  JSValue exec(String input) {
    RegExpMatch? match;

    if (global) {
      match = _dartRegExp.firstMatch(input.substring(lastIndex));
      if (match != null) {
        // Adjust indices for the complete string
        final adjustedMatch = _AdjustedMatch(match, lastIndex);
        lastIndex += match.end;
        return _createMatchArray(adjustedMatch, input, match);
      } else {
        lastIndex = 0;
        return JSValueFactory.nullValue();
      }
    } else {
      match = _dartRegExp.firstMatch(input);
      if (match != null) {
        return _createMatchArray(match, input, match);
      } else {
        return JSValueFactory.nullValue();
      }
    }
  }

  /// Creates a JavaScript array to represent a RegExp match
  JSArray _createMatchArray(
    Match match,
    String input,
    RegExpMatch regExpMatch,
  ) {
    final elements = <JSValue>[];

    // Add the complete match
    elements.add(JSValueFactory.string(match.group(0) ?? ''));

    // Add captured groups
    for (int i = 1; i <= match.groupCount; i++) {
      final group = match.group(i);
      elements.add(
        group != null
            ? JSValueFactory.string(group)
            : JSValueFactory.undefined(),
      );
    }

    // ES2018: Create the groups object with named capture groups
    final groupsObject = JSObject();
    for (final name in _groupNames) {
      final value = regExpMatch.namedGroup(name);
      groupsObject.setProperty(
        name,
        value != null
            ? JSValueFactory.string(value)
            : JSValueFactory.undefined(),
      );
    }

    // ES2022: Create the indices object if the 'd' flag is present
    JSObject? indicesObject;
    JSObject? indicesGroupsObject;
    if (hasIndices) {
      indicesObject = JSObject();
      indicesGroupsObject = JSObject();

      // Add indices for the complete match
      final fullMatchIndices = JSArray([
        JSValueFactory.number(match.start.toDouble()),
        JSValueFactory.number(match.end.toDouble()),
      ]);
      indicesObject.setProperty('0', fullMatchIndices);

      // Add indices for each captured group
      // Note: Dart's RegExp doesn't provide individual group positions easily
      // We'll use a simplified approach - store indices for groups that matched
      for (int i = 1; i <= match.groupCount; i++) {
        final groupValue = match.group(i);
        if (groupValue != null) {
          // Try to find position of this group in the input
          // This is a simplified implementation
          final fullMatch = match.group(0) ?? '';
          final groupPosInMatch = fullMatch.indexOf(groupValue);
          if (groupPosInMatch != -1) {
            final absStart = match.start + groupPosInMatch;
            final absEnd = absStart + groupValue.length;
            final groupIndices = JSArray([
              JSValueFactory.number(absStart.toDouble()),
              JSValueFactory.number(absEnd.toDouble()),
            ]);
            indicesObject.setProperty(i.toString(), groupIndices);
          } else {
            indicesObject.setProperty(i.toString(), JSValueFactory.undefined());
          }
        } else {
          indicesObject.setProperty(i.toString(), JSValueFactory.undefined());
        }
      }

      // Add indices for the named capture groups
      for (final name in _groupNames) {
        final value = regExpMatch.namedGroup(name);
        if (value != null) {
          // Find position in the full match
          final fullMatch = match.group(0) ?? '';
          final groupPosInMatch = fullMatch.indexOf(value);
          if (groupPosInMatch != -1) {
            final absStart = match.start + groupPosInMatch;
            final absEnd = absStart + value.length;
            final groupIndices = JSArray([
              JSValueFactory.number(absStart.toDouble()),
              JSValueFactory.number(absEnd.toDouble()),
            ]);
            indicesGroupsObject.setProperty(name, groupIndices);
          } else {
            indicesGroupsObject.setProperty(name, JSValueFactory.undefined());
          }
        } else {
          indicesGroupsObject.setProperty(name, JSValueFactory.undefined());
        }
      }

      // Add the groups object to indices
      indicesObject.setProperty('groups', indicesGroupsObject);
    }

    final result = _MatchArray(
      elements,
      match.start,
      input,
      groupsObject,
      indicesObject,
    );
    return result;
  }

  @override
  String toString() => '/$_source/$_flags';
}

/// Specialized array for RegExp match results
class _MatchArray extends JSArray {
  final int _index;
  final String _input;
  final JSObject _groups; // ES2018: Named capture groups
  final JSObject? _indices; // ES2022: Match indices

  _MatchArray(
    List<JSValue> super.elements,
    this._index,
    this._input,
    this._groups, [
    this._indices,
  ]);

  @override
  JSValue getProperty(String name) {
    switch (name) {
      case 'index':
        return JSValueFactory.number(_index.toDouble());
      case 'input':
        return JSValueFactory.string(_input);
      case 'groups':
        return _groups; // ES2018: Return the groups object
      case 'indices': // ES2022: Return indices object
        return _indices ?? JSValueFactory.undefined();
      default:
        return super.getProperty(name);
    }
  }

  @override
  bool hasProperty(String name) {
    if (name == 'index' || name == 'input' || name == 'groups') {
      return true;
    }
    return super.hasProperty(name);
  }
}

/// Helper class to adjust match indices for global regex
class _AdjustedMatch implements Match {
  final Match _original;
  final int _offset;

  _AdjustedMatch(this._original, this._offset);

  @override
  int get start => _original.start + _offset;

  @override
  int get end => _original.end + _offset;

  @override
  String? group(int group) => _original.group(group);

  @override
  int get groupCount => _original.groupCount;

  @override
  String? operator [](int group) => _original[group];

  @override
  List<String?> groups(List<int> groupIndices) =>
      _original.groups(groupIndices);

  @override
  String get input => _original.input;

  @override
  Pattern get pattern => _original.pattern;
}

/// Factory to create JavaScript RegExp
class JSRegExpFactory {
  /// Create a RegExp from a pattern and flags
  static JSRegExp create(String pattern, [String flags = '']) {
    return JSRegExp(pattern, flags);
  }

  /// Parse flags and validate their validity
  static String parseFlags(String flags) {
    // ES2024: added flag 'v' (unicodeSets) and 'd' (hasIndices)
    final validFlags = {'g', 'i', 'm', 's', 'u', 'v', 'y', 'd'};
    final uniqueFlags = <String>{};

    for (int i = 0; i < flags.length; i++) {
      final flag = flags[i];
      if (!validFlags.contains(flag)) {
        throw JSSyntaxError('Invalid regular expression flag "$flag"');
      }
      if (uniqueFlags.contains(flag)) {
        throw JSSyntaxError('Duplicate regular expression flag "$flag"');
      }
      uniqueFlags.add(flag);
    }

    // ES2024: 'u' and 'v' are mutually exclusive
    if (uniqueFlags.contains('u') && uniqueFlags.contains('v')) {
      throw JSSyntaxError('Flags "u" and "v" are mutually exclusive');
    }

    // Return the sorted flags for consistency
    final sortedFlags = uniqueFlags.toList()..sort();
    return sortedFlags.join('');
  }
}

/// Global RegExp object
class RegExpGlobal {
  /// Create the global RegExp object with its constructor
  static JSObject createRegExpGlobal() {
    final regexpGlobal = JSObject();

    // RegExp constructor
    regexpGlobal.setProperty(
      'RegExp',
      JSNativeFunction(
        functionName: 'RegExp',
        nativeImpl: (args) {
          String pattern = '';
          String flags = '';

          if (args.isNotEmpty) {
            final firstArg = args[0];
            if (firstArg is JSRegExp) {
              // RegExp(regex) or RegExp(regex, flags)
              pattern = firstArg._source;
              if (args.length > 1) {
                flags = args[1].toString();
              } else {
                flags = firstArg._flags;
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
      ),
    );

    return regexpGlobal;
  }
}

/// Extension of JSValue types for RegExp support
extension JSValueRegExpExtension on JSValue {
  /// Check if this value is a RegExp
  bool get isRegExp => this is JSRegExp;

  /// Cast to JSRegExp (throws an error if it's not a RegExp)
  JSRegExp get asRegExp {
    if (this is JSRegExp) {
      return this as JSRegExp;
    }
    throw JSError('Value is not a RegExp');
  }
}
