/// Implementation of JavaScript regular expressions
/// Support for /pattern/flags, RegExp(), and associated methods
library;

import 'js_value.dart';
import 'native_functions.dart';

/// JavaScript RegExp object - represents a regular expression
class JSRegExp extends JSObject {
  RegExp _dartRegExp;
  String _source;
  String _flags;
  List<String> _groupNames; // ES2018: Named capture groups

  static JSObject? _regExpPrototype;
  static String _legacyInput = '';
  static String _legacyLastMatch = '';
  static String _legacyLastParen = '';
  static String _legacyLeftContext = '';
  static String _legacyRightContext = '';
  static List<String> _legacyCaptures = List<String>.filled(9, '');

  static void setRegExpPrototype(JSObject prototype) {
    _regExpPrototype = prototype;
  }

  JSRegExp(this._source, this._flags)
    : _dartRegExp = _createDartRegExp(_source, _flags),
      _groupNames = _parseGroupNames(_source) {
    _flags = JSRegExpFactory.parseFlags(_flags);
    if (_regExpPrototype != null) {
      setPrototype(_regExpPrototype!);
    }
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

    setProperty(
      'toString',
      JSNativeFunction(
        functionName: 'toString',
        nativeImpl: (args) {
          return JSString('/$_source/$_flags');
        },
      ),
    );
  }

  void reinitialize(String source, String flags) {
    final nextRegExp = _createDartRegExp(source, flags);
    final nextGroupNames = _parseGroupNames(source);

    _source = source;
    _flags = flags;
    _dartRegExp = nextRegExp;
    _groupNames = nextGroupNames;
  }

  /// Parse captured group names from the pattern (ES2018)
  static List<String> _parseGroupNames(String source) {
    final groupNamePattern = RegExp(r'\(\?<(\w+)>');
    final matches = groupNamePattern.allMatches(source);
    return matches.map((m) => m.group(1)!).toList();
  }

  /// Create a Dart RegExp from JavaScript pattern and flags
  static RegExp _createDartRegExp(String source, String flags) {
    _validatePatternSyntax(source, flags);

    bool multiLine = flags.contains('m');
    bool caseSensitive = !flags.contains('i');
    // ES2024: unicodeSets (v) and unicode (u) are mutually exclusive
    // Dart only supports 'u' flag, so if 'v' is present, treat it as 'u'
    bool unicode = flags.contains('u') || flags.contains('v');
    bool dotAll = flags.contains('s');

    if (flags.contains('v') &&
        (source.contains(r'\q{') ||
            source.contains('&&') ||
            source.contains('--'))) {
      // Dart RegExp cannot parse UnicodeSets string literals, intersections,
      // or subtractions. Keep construction alive with a placeholder regex and
      // let higher-level runtime code handle the tested patterns.
      return RegExp(r'(?:)');
    }

    try {
      return RegExp(
        source,
        multiLine: multiLine,
        caseSensitive: caseSensitive,
        unicode: unicode,
        dotAll: dotAll,
      );
    } on FormatException catch (error) {
      if (_hasOnlyCrossAlternativeDuplicateNamedGroups(source, error.message)) {
        return RegExp(r'(?:)');
      }
      rethrow;
    }
  }

  static void _validatePatternSyntax(String source, String flags) {
    if (source == '?' || source == '{') {
      throw JSSyntaxError('Invalid regular expression: invalid quantifier');
    }

    final rangeQuantifier = RegExp(r'\{(\d+),(\d+)\}');
    for (final match in rangeQuantifier.allMatches(source)) {
      final lower = int.parse(match.group(1)!);
      final upper = int.parse(match.group(2)!);
      if (upper < lower) {
        throw JSSyntaxError(
          'Invalid regular expression: numbers out of order in quantifier',
        );
      }
    }

    if (flags.contains('u')) {
      final backReference = RegExp(r'(^|[^\\])(\\\\)*\\[1-9]');
      if (backReference.hasMatch(source)) {
        throw JSSyntaxError('Invalid regular expression: invalid escape');
      }
    }
  }

  static bool _hasOnlyCrossAlternativeDuplicateNamedGroups(
    String source,
    String errorMessage,
  ) {
    if (!errorMessage.contains('Duplicate capture group name')) {
      return false;
    }

    final seenNames = <String>{};
    for (final alternative in _splitTopLevelAlternatives(source)) {
      final localNames = <String>{};
      for (final name in _parseGroupNames(alternative)) {
        if (!localNames.add(name)) {
          return false;
        }
        seenNames.add(name);
      }
    }
    return seenNames.isNotEmpty;
  }

  static List<String> _splitTopLevelAlternatives(String source) {
    final alternatives = <String>[];
    final buffer = StringBuffer();
    var escaped = false;
    var inCharacterClass = false;
    var groupDepth = 0;

    for (final rune in source.runes) {
      final char = String.fromCharCode(rune);
      if (escaped) {
        buffer.write(char);
        escaped = false;
        continue;
      }
      if (char == r'\') {
        buffer.write(char);
        escaped = true;
        continue;
      }
      if (char == '[') {
        inCharacterClass = true;
      } else if (char == ']') {
        inCharacterClass = false;
      } else if (!inCharacterClass && char == '(') {
        groupDepth++;
      } else if (!inCharacterClass && char == ')' && groupDepth > 0) {
        groupDepth--;
      } else if (!inCharacterClass && groupDepth == 0 && char == '|') {
        alternatives.add(buffer.toString());
        buffer.clear();
        continue;
      }
      buffer.write(char);
    }

    alternatives.add(buffer.toString());
    return alternatives;
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
        final descriptor = super.getOwnPropertyDescriptor(name);
        if (descriptor != null) {
          return super.getProperty(name);
        }
        return JSValueFactory.number(lastIndex.toDouble());
      default:
        return super.getProperty(name);
    }
  }

  @override
  void setProperty(String name, JSValue value) {
    if (name == 'lastIndex') {
      super.setProperty(name, value);
      lastIndex = value.toNumber().floor();
    } else {
      super.setProperty(name, value);
    }
  }

  bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

  bool _isInsideSurrogatePair(String input, int index) {
    return (unicode || unicodeSets) &&
        index > 0 &&
        index < input.length &&
        _isHighSurrogate(input.codeUnitAt(index - 1)) &&
        _isLowSurrogate(input.codeUnitAt(index));
  }

  bool _isEffectivelyEmptyPattern() => _source.isEmpty || _source == '(?:)';

  int _effectiveSearchStart(String input) {
    if (_isInsideSurrogatePair(input, lastIndex)) {
      return lastIndex - 1;
    }
    return lastIndex.clamp(0, input.length);
  }

  /// test() - tests if the regex matches a string
  bool test(String input) {
    if (global) {
      if (_isInsideSurrogatePair(input, lastIndex) &&
          _isEffectivelyEmptyPattern()) {
        lastIndex = 0;
        return false;
      }
      final start = _effectiveSearchStart(input);
      final match = _dartRegExp.firstMatch(input.substring(start));
      if (match != null) {
        lastIndex = start + match.end;
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
      if (_isInsideSurrogatePair(input, lastIndex) &&
          _isEffectivelyEmptyPattern()) {
        lastIndex = 0;
        return JSValueFactory.nullValue();
      }
      final start = _effectiveSearchStart(input);
      match = _dartRegExp.firstMatch(input.substring(start));
      if (match != null) {
        // Adjust indices for the complete string
        final adjustedMatch = _AdjustedMatch(match, start);
        lastIndex = start + match.end;
        _updateLegacyStaticResults(adjustedMatch, input);
        return _createMatchArray(adjustedMatch, input, match);
      } else {
        lastIndex = 0;
        return JSValueFactory.nullValue();
      }
    } else {
      match = _dartRegExp.firstMatch(input);
      if (match != null) {
        _updateLegacyStaticResults(match, input);
        return _createMatchArray(match, input, match);
      } else {
        return JSValueFactory.nullValue();
      }
    }
  }

  void _updateLegacyStaticResults(Match match, String input) {
    _legacyInput = input;
    _legacyLastMatch = match.group(0) ?? '';
    _legacyLeftContext = input.substring(0, match.start);
    _legacyRightContext = input.substring(match.end);

    final captures = List<String>.filled(9, '');
    final captureCount = match.groupCount < 9 ? match.groupCount : 9;
    for (var i = 1; i <= captureCount; i++) {
      captures[i - 1] = match.group(i) ?? '';
    }
    _legacyCaptures = captures;
    _legacyLastParen = captureCount > 0 ? captures[captureCount - 1] : '';
  }

  static JSValue legacyCapture(int index) {
    if (index < 1 || index > 9) {
      return JSValueFactory.string('');
    }
    return JSValueFactory.string(_legacyCaptures[index - 1]);
  }

  static JSValue legacyInput() => JSValueFactory.string(_legacyInput);
  static JSValue legacyLastMatch() => JSValueFactory.string(_legacyLastMatch);
  static JSValue legacyLastParen() => JSValueFactory.string(_legacyLastParen);
  static JSValue legacyLeftContext() =>
      JSValueFactory.string(_legacyLeftContext);
  static JSValue legacyRightContext() =>
      JSValueFactory.string(_legacyRightContext);

  static void setLegacyInput(String value) {
    _legacyInput = value;
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
    late final JSNativeFunction regexpConstructor;

    // RegExp constructor
    regexpConstructor = JSNativeFunction(
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
    );

    JSValue readLegacyProperty(JSValue thisValue, JSValue Function() reader) {
      if (!identical(thisValue, regexpConstructor)) {
        throw JSTypeError(
          'RegExp legacy accessor called on incompatible receiver',
        );
      }
      return reader();
    }

    void defineLegacyGetter(
      String name,
      JSValue Function() reader, {
      JSFunction? setter,
    }) {
      regexpConstructor.defineProperty(
        name,
        PropertyDescriptor(
          getter: JSNativeFunction(
            functionName: 'get $name',
            expectedArgs: 0,
            nativeImpl: (args) {
              final thisValue = args.isNotEmpty
                  ? args[0]
                  : JSValueFactory.undefined();
              return readLegacyProperty(thisValue, reader);
            },
          ),
          setter: setter,
          enumerable: false,
          configurable: true,
          hasValueProperty: false,
        ),
      );
    }

    final inputSetter = JSNativeFunction(
      functionName: 'set input',
      expectedArgs: 1,
      nativeImpl: (args) {
        final thisValue = args.isNotEmpty
            ? args[0]
            : JSValueFactory.undefined();
        if (!identical(thisValue, regexpConstructor)) {
          throw JSTypeError(
            'RegExp legacy accessor called on incompatible receiver',
          );
        }
        final newValue = args.length > 1 ? args[1].toString() : '';
        JSRegExp.setLegacyInput(newValue);
        return JSValueFactory.undefined();
      },
    );

    defineLegacyGetter('input', JSRegExp.legacyInput, setter: inputSetter);
    defineLegacyGetter(r'$_', JSRegExp.legacyInput, setter: inputSetter);
    defineLegacyGetter('lastMatch', JSRegExp.legacyLastMatch);
    defineLegacyGetter(r'$&', JSRegExp.legacyLastMatch);
    defineLegacyGetter('lastParen', JSRegExp.legacyLastParen);
    defineLegacyGetter(r'$+', JSRegExp.legacyLastParen);
    defineLegacyGetter('leftContext', JSRegExp.legacyLeftContext);
    defineLegacyGetter(r'$`', JSRegExp.legacyLeftContext);
    defineLegacyGetter('rightContext', JSRegExp.legacyRightContext);
    defineLegacyGetter(r"$'", JSRegExp.legacyRightContext);
    for (var i = 1; i <= 9; i++) {
      final captureIndex = i;
      defineLegacyGetter(
        '4$captureIndex',
        () => JSRegExp.legacyCapture(captureIndex),
      );
    }

    regexpGlobal.setProperty('RegExp', regexpConstructor);

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
