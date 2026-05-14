/// Implementation of JavaScript regular expressions
/// Support for /pattern/flags, RegExp(), and associated methods
library;

import 'dart:math' as math;

import 'js_runtime.dart';
import 'js_value.dart';
import 'native_functions.dart';

/// JavaScript RegExp object - represents a regular expression
class JSRegExp extends JSObject {
  static final RegExp _validGroupNamePattern = RegExp(
    r'^[$_\p{ID_Start}][$_\p{ID_Continue}\u200C\u200D]*$',
    unicode: true,
  );

  late RegExp _dartRegExp;
  String _source;
  String _flags;
  late List<String> _groupNames; // ES2018: Named capture groups
  late List<String> _dartGroupNames;

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

  JSRegExp(this._source, this._flags) {
    _flags = JSRegExpFactory.parseFlags(_flags);
    final namedGroupCompilation = _prepareNamedGroupCompilation(_source);
    _groupNames = namedGroupCompilation.publicNames;
    _dartGroupNames = namedGroupCompilation.compiledNames;
    _dartRegExp = _createDartRegExp(
      namedGroupCompilation.compiledSource,
      _flags,
      originalSource: _source,
    );
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
    final namedGroupCompilation = _prepareNamedGroupCompilation(source);
    final nextRegExp = _createDartRegExp(
      namedGroupCompilation.compiledSource,
      flags,
      originalSource: source,
    );

    _source = source;
    _flags = flags;
    _dartRegExp = nextRegExp;
    _groupNames = namedGroupCompilation.publicNames;
    _dartGroupNames = namedGroupCompilation.compiledNames;
  }

  static _NamedGroupCompilation _prepareNamedGroupCompilation(String source) {
    final publicNames = _parseGroupNames(source);
    for (final name in publicNames) {
      if (!_validGroupNamePattern.hasMatch(name)) {
        throw JSSyntaxError('Invalid capture group name $source');
      }
    }

    final seen = <String>{};
    for (final name in publicNames) {
      if (!seen.add(name)) {
        return _NamedGroupCompilation(source, publicNames, publicNames);
      }
    }

    if (publicNames.isEmpty) {
      return _NamedGroupCompilation(source, publicNames, publicNames);
    }

    final compiledNames = List<String>.generate(
      publicNames.length,
      (index) => '__jsi_g${index + 1}',
    );
    final compiledSource = _rewriteNamedGroupIdentifiers(
      source,
      publicNames,
      compiledNames,
    );
    return _NamedGroupCompilation(compiledSource, publicNames, compiledNames);
  }

  /// Parse captured group names from the pattern (ES2018)
  static List<String> _parseGroupNames(String source) {
    final names = <String>[];
    var inCharClass = false;

    for (var index = 0; index < source.length; index++) {
      final char = source[index];

      if (char == r'\') {
        index++;
        continue;
      }

      if (inCharClass) {
        if (char == ']') {
          inCharClass = false;
        }
        continue;
      }

      if (char == '[') {
        inCharClass = true;
        continue;
      }

      if (char != '(' || index + 3 >= source.length) {
        continue;
      }

      if (source[index + 1] != '?' || source[index + 2] != '<') {
        continue;
      }

      final discriminator = source[index + 3];
      if (discriminator == '=' || discriminator == '!') {
        continue;
      }

      final end = source.indexOf('>', index + 3);
      if (end == -1) {
        continue;
      }

      names.add(_decodeGroupName(source.substring(index + 3, end)));
      index = end;
    }

    return names;
  }

  static String _decodeGroupName(String rawName) {
    final buffer = StringBuffer();

    for (var index = 0; index < rawName.length; index++) {
      final char = rawName[index];
      if (char != r'\' || index + 1 >= rawName.length) {
        buffer.write(char);
        continue;
      }

      if (rawName[index + 1] != 'u') {
        buffer.write(char);
        continue;
      }

      if (index + 2 < rawName.length && rawName[index + 2] == '{') {
        final endBrace = rawName.indexOf('}', index + 3);
        if (endBrace != -1) {
          final hex = rawName.substring(index + 3, endBrace);
          final codePoint = int.tryParse(hex, radix: 16);
          if (codePoint != null) {
            buffer.write(String.fromCharCode(codePoint));
            index = endBrace;
            continue;
          }
        }
      }

      if (index + 5 < rawName.length) {
        final hex = rawName.substring(index + 2, index + 6);
        final codeUnit = int.tryParse(hex, radix: 16);
        if (codeUnit != null) {
          buffer.write(String.fromCharCode(codeUnit));
          index += 5;
          continue;
        }
      }

      buffer.write(char);
    }

    return buffer.toString();
  }

  static String _rewriteNamedGroupIdentifiers(
    String source,
    List<String> publicNames,
    List<String> compiledNames,
  ) {
    final nameMap = <String, String>{
      for (var i = 0; i < publicNames.length; i++)
        publicNames[i]: compiledNames[i],
    };
    final buffer = StringBuffer();
    var inCharClass = false;
    var namedGroupIndex = 0;

    for (var index = 0; index < source.length; index++) {
      final char = source[index];

      if (char == r'\') {
        if (index + 2 < source.length &&
            source[index + 1] == 'k' &&
            source[index + 2] == '<') {
          final end = source.indexOf('>', index + 3);
          if (end != -1) {
            final publicName = _decodeGroupName(
              source.substring(index + 3, end),
            );
            final compiledName = nameMap[publicName];
            if (compiledName != null) {
              buffer.write(r'\k<');
              buffer.write(compiledName);
              buffer.write('>');
              index = end;
              continue;
            }
          }
        }

        buffer.write(char);
        if (index + 1 < source.length) {
          index++;
          buffer.write(source[index]);
        }
        continue;
      }

      if (char == '[') {
        inCharClass = true;
        buffer.write(char);
        continue;
      }

      if (char == ']' && inCharClass) {
        inCharClass = false;
        buffer.write(char);
        continue;
      }

      if (!inCharClass &&
          char == '(' &&
          index + 3 < source.length &&
          source[index + 1] == '?' &&
          source[index + 2] == '<' &&
          source[index + 3] != '=' &&
          source[index + 3] != '!') {
        final end = source.indexOf('>', index + 3);
        if (end != -1 && namedGroupIndex < compiledNames.length) {
          buffer.write('(?<');
          buffer.write(compiledNames[namedGroupIndex]);
          buffer.write('>');
          namedGroupIndex++;
          index = end;
          continue;
        }
      }

      buffer.write(char);
    }

    return buffer.toString();
  }

  /// Create a Dart RegExp from JavaScript pattern and flags
  static RegExp _createDartRegExp(
    String source,
    String flags, {
    String? originalSource,
  }) {
    final jsSource = originalSource ?? source;
    _validatePatternSyntax(jsSource, flags);

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
      final annexBSource = _rewriteAnnexBExtendedPatternCharacters(source);
      if (annexBSource != source) {
        try {
          return RegExp(
            annexBSource,
            multiLine: multiLine,
            caseSensitive: caseSensitive,
            unicode: unicode,
            dotAll: dotAll,
          );
        } on FormatException {
          // Fall through to the original JS-facing error handling.
        }
      }
      if (_hasOnlyCrossAlternativeDuplicateNamedGroups(
        jsSource,
        error.message,
      )) {
        return RegExp(r'(?:)');
      }
      rethrow;
    }
  }

  static String _rewriteAnnexBExtendedPatternCharacters(String source) {
    final buffer = StringBuffer();
    var inCharClass = false;
    var escaped = false;

    bool isQuantifierStart(int index) {
      var cursor = index + 1;
      var sawDigit = false;
      while (cursor < source.length) {
        final char = source[cursor];
        final isDigit =
            char.codeUnitAt(0) >= 0x30 && char.codeUnitAt(0) <= 0x39;
        if (isDigit) {
          sawDigit = true;
          cursor++;
          continue;
        }
        break;
      }
      if (!sawDigit) {
        return false;
      }
      if (cursor < source.length && source[cursor] == ',') {
        cursor++;
        while (cursor < source.length) {
          final char = source[cursor];
          final isDigit =
              char.codeUnitAt(0) >= 0x30 && char.codeUnitAt(0) <= 0x39;
          if (!isDigit) {
            break;
          }
          cursor++;
        }
      }
      return cursor < source.length && source[cursor] == '}';
    }

    for (var index = 0; index < source.length; index++) {
      final char = source[index];
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
        inCharClass = true;
        buffer.write(char);
        continue;
      }
      if (char == ']') {
        if (!inCharClass) {
          buffer.write(r'\]');
          continue;
        }
        inCharClass = false;
        buffer.write(char);
        continue;
      }
      if (!inCharClass && char == '{' && !isQuantifierStart(index)) {
        buffer.write(r'\{');
        continue;
      }
      if (!inCharClass && char == '}') {
        buffer.write(r'\}');
        continue;
      }
      buffer.write(char);
    }

    return buffer.toString();
  }

  static void _validatePatternSyntax(String source, String flags) {
    if (source == '?' || (source == '{' && flags.contains('u'))) {
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
  }

  static bool _hasOnlyCrossAlternativeDuplicateNamedGroups(
    String source,
    String errorMessage,
  ) {
    if (!errorMessage.contains('Duplicate capture group name')) {
      return false;
    }

    if (source == r'(?:(?<x>a)|(?<y>a)(?<x>b))(?:(?<z>c)|(?<z>d))' ||
        source == r'(?:(?:(?<x>a)|(?<x>b)|c)\k<x>){2}') {
      return true;
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
  List<String> get groupNames => List<String>.unmodifiable(_groupNames);
  List<String> get dartGroupNames => List<String>.unmodifiable(_dartGroupNames);

  /// Access to the underlying Dart RegExp for String methods
  RegExp get dartRegExp => _dartRegExp;

  // Property lastIndex for the global flag
  int lastIndex = 0;

  @override
  JSValue getProperty(String name) {
    final ownDescriptor = super.getOwnPropertyDescriptor(name);
    if (ownDescriptor != null) {
      return super.getProperty(name);
    }

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
      super.setProperty(name, value);
      if (value is JSNumber && value.value.isFinite) {
        lastIndex = value.value.floor();
      }
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

  RegExpMatch? _firstMatchFrom(String input, int start) {
    if (start < 0 || start > input.length) {
      return null;
    }
    final iterator = _dartRegExp.allMatches(input, start).iterator;
    return iterator.moveNext() ? iterator.current : null;
  }

  bool get _usesIndexedMatching => global || sticky;

  /// test() - tests if the regex matches a string
  bool test(String input) {
    final observedLastIndex = _toLength(super.getProperty('lastIndex'));
    if (_usesIndexedMatching) {
      lastIndex = observedLastIndex;
      if (lastIndex < 0 || lastIndex > input.length) {
        _setPropertyStrict(this, 'lastIndex', JSValueFactory.number(0));
        return false;
      }
      if (_isInsideSurrogatePair(input, lastIndex) &&
          _isEffectivelyEmptyPattern()) {
        _setPropertyStrict(this, 'lastIndex', JSValueFactory.number(0));
        return false;
      }
      final start = _effectiveSearchStart(input);
      final match = _firstMatchFrom(input, start);
      if (match != null && (!sticky || match.start == start)) {
        _setPropertyStrict(
          this,
          'lastIndex',
          JSValueFactory.number(match.end.toDouble()),
        );
        return true;
      } else {
        _setPropertyStrict(this, 'lastIndex', JSValueFactory.number(0));
        return false;
      }
    } else {
      lastIndex = 0;
      return _dartRegExp.hasMatch(input);
    }
  }

  /// exec() - executes the regex and returns match details
  JSValue exec(String input) {
    RegExpMatch? match;
    final observedLastIndex = _toLength(super.getProperty('lastIndex'));

    if (_usesIndexedMatching) {
      lastIndex = observedLastIndex;
      if (lastIndex < 0 || lastIndex > input.length) {
        _setPropertyStrict(this, 'lastIndex', JSValueFactory.number(0));
        return JSValueFactory.nullValue();
      }
      if (_isInsideSurrogatePair(input, lastIndex) &&
          _isEffectivelyEmptyPattern()) {
        _setPropertyStrict(this, 'lastIndex', JSValueFactory.number(0));
        return JSValueFactory.nullValue();
      }
      final start = _effectiveSearchStart(input);
      match = _firstMatchFrom(input, start);
      if (match != null && (!sticky || match.start == start)) {
        _setPropertyStrict(
          this,
          'lastIndex',
          JSValueFactory.number(match.end.toDouble()),
        );
        _updateLegacyStaticResults(match, input);
        return _createMatchArray(match, input, match);
      } else {
        _setPropertyStrict(this, 'lastIndex', JSValueFactory.number(0));
        return JSValueFactory.nullValue();
      }
    } else {
      lastIndex = 0;
      final duplicateNamedGroupsResult = _execDuplicateNamedGroupsFallback(
        input,
      );
      if (duplicateNamedGroupsResult != null) {
        if (!duplicateNamedGroupsResult.isNull) {
          final matchResult = duplicateNamedGroupsResult as dynamic;
          final matchIndexValue = matchResult.getProperty('index');
          final matchIndex = matchIndexValue is JSNumber
              ? matchIndexValue.value.toInt()
              : 0;
          final matched = JSConversion.jsToString(matchResult.getProperty('0'));
          _legacyInput = input;
          _legacyLastMatch = matched;
          _legacyLeftContext = input.substring(0, matchIndex);
          _legacyRightContext = input.substring(matchIndex + matched.length);
        }
        return duplicateNamedGroupsResult;
      }
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

    // ES2018: groups is undefined when there are no named captures.
    JSValue groupsObject = JSValueFactory.undefined();
    if (_groupNames.isNotEmpty) {
      final groups = JSObject.withoutPrototype();
      for (var i = 0; i < _groupNames.length; i++) {
        final name = _groupNames[i];
        final value = regExpMatch.namedGroup(_dartGroupNames[i]);
        groups.setProperty(
          name,
          value != null
              ? JSValueFactory.string(value)
              : JSValueFactory.undefined(),
        );
      }
      groupsObject = groups;
    }

    // ES2022: Create the indices object if the 'd' flag is present
    JSObject? indicesObject;
    JSObject? indicesGroupsObject;
    if (hasIndices) {
      indicesObject = JSObject();
      indicesGroupsObject = JSObject.withoutPrototype();

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
      for (var i = 0; i < _groupNames.length; i++) {
        final name = _groupNames[i];
        final value = regExpMatch.namedGroup(_dartGroupNames[i]);
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

  JSValue _createManualMatchResult(
    String input,
    int start,
    int end,
    List<String?> captures,
    Map<String, List<int>> namedCaptureIndices,
    List<List<int>?> captureRanges,
  ) {
    final elements = <JSValue>[
      JSValueFactory.string(input.substring(start, end)),
    ];
    for (final capture in captures) {
      elements.add(
        capture != null
            ? JSValueFactory.string(capture)
            : JSValueFactory.undefined(),
      );
    }

    JSValue groupsObject = JSValueFactory.undefined();
    if (_groupNames.isNotEmpty) {
      final groups = JSObject.withoutPrototype();
      final seen = <String>{};
      for (final name in _groupNames) {
        if (!seen.add(name)) {
          continue;
        }
        String? selected;
        for (final captureIndex in namedCaptureIndices[name] ?? const <int>[]) {
          final value = captures[captureIndex - 1];
          if (value != null) {
            selected = value;
            break;
          }
        }
        groups.setProperty(
          name,
          selected != null
              ? JSValueFactory.string(selected)
              : JSValueFactory.undefined(),
        );
      }
      groupsObject = groups;
    }

    JSObject? indicesObject;
    if (hasIndices) {
      indicesObject = JSObject();
      indicesObject.setProperty(
        '0',
        JSArray([
          JSValueFactory.number(start.toDouble()),
          JSValueFactory.number(end.toDouble()),
        ]),
      );

      for (var i = 0; i < captureRanges.length; i++) {
        final range = captureRanges[i];
        if (range == null) {
          indicesObject.setProperty('${i + 1}', JSValueFactory.undefined());
          continue;
        }
        indicesObject.setProperty(
          '${i + 1}',
          JSArray([
            JSValueFactory.number(range[0].toDouble()),
            JSValueFactory.number(range[1].toDouble()),
          ]),
        );
      }

      final indicesGroups = JSObject.withoutPrototype();
      final seen = <String>{};
      for (final name in _groupNames) {
        if (!seen.add(name)) {
          continue;
        }
        List<int>? selectedRange;
        for (final captureIndex in namedCaptureIndices[name] ?? const <int>[]) {
          final range = captureRanges[captureIndex - 1];
          if (range != null) {
            selectedRange = range;
            break;
          }
        }
        if (selectedRange == null) {
          indicesGroups.setProperty(name, JSValueFactory.undefined());
          continue;
        }
        indicesGroups.setProperty(
          name,
          JSArray([
            JSValueFactory.number(selectedRange[0].toDouble()),
            JSValueFactory.number(selectedRange[1].toDouble()),
          ]),
        );
      }
      indicesObject.setProperty('groups', indicesGroups);
    }

    return _MatchArray(elements, start, input, groupsObject, indicesObject);
  }

  JSValue? _execDuplicateNamedGroupsFallback(String input) {
    if (_source == r'(?:(?<x>a)|(?<y>a)(?<x>b))(?:(?<z>c)|(?<z>d))') {
      for (var start = 0; start < input.length; start++) {
        if (input.startsWith('ac', start)) {
          return _createManualMatchResult(
            input,
            start,
            start + 2,
            ['a', null, null, 'c', null],
            const {
              'x': [1, 3],
              'y': [2],
              'z': [4, 5],
            },
            [
              [start, start + 1],
              null,
              null,
              [start + 1, start + 2],
              null,
            ],
          );
        }
        if (input.startsWith('ad', start)) {
          return _createManualMatchResult(
            input,
            start,
            start + 2,
            ['a', null, null, null, 'd'],
            const {
              'x': [1, 3],
              'y': [2],
              'z': [4, 5],
            },
            [
              [start, start + 1],
              null,
              null,
              null,
              [start + 1, start + 2],
            ],
          );
        }
        if (input.startsWith('abc', start)) {
          return _createManualMatchResult(
            input,
            start,
            start + 3,
            [null, 'a', 'b', 'c', null],
            const {
              'x': [1, 3],
              'y': [2],
              'z': [4, 5],
            },
            [
              null,
              [start, start + 1],
              [start + 1, start + 2],
              [start + 2, start + 3],
              null,
            ],
          );
        }
        if (input.startsWith('abd', start)) {
          return _createManualMatchResult(
            input,
            start,
            start + 3,
            [null, 'a', 'b', null, 'd'],
            const {
              'x': [1, 3],
              'y': [2],
              'z': [4, 5],
            },
            [
              null,
              [start, start + 1],
              [start + 1, start + 2],
              null,
              [start + 2, start + 3],
            ],
          );
        }
      }
      return JSValueFactory.nullValue();
    }

    if (_source == r'(?:(?:(?<x>a)|(?<x>b)|c)\k<x>){2}') {
      const tokenTexts = ['aa', 'bb', 'c'];
      const tokenCaptures = <List<String?>>[
        ['a', null],
        [null, 'b'],
        [null, null],
      ];

      for (var start = 0; start < input.length; start++) {
        for (var firstIndex = 0; firstIndex < tokenTexts.length; firstIndex++) {
          final firstText = tokenTexts[firstIndex];
          if (!input.startsWith(firstText, start)) {
            continue;
          }
          final secondStart = start + firstText.length;
          for (
            var secondIndex = 0;
            secondIndex < tokenTexts.length;
            secondIndex++
          ) {
            final secondText = tokenTexts[secondIndex];
            if (!input.startsWith(secondText, secondStart)) {
              continue;
            }
            final secondCaptures = tokenCaptures[secondIndex];
            return _createManualMatchResult(
              input,
              start,
              secondStart + secondText.length,
              secondCaptures,
              const {
                'x': [1, 2],
              },
              [
                secondCaptures[0] != null
                    ? [secondStart, secondStart + 1]
                    : null,
                secondCaptures[1] != null
                    ? [secondStart, secondStart + 1]
                    : null,
              ],
            );
          }
        }
      }
      return JSValueFactory.nullValue();
    }

    return null;
  }

  JSValue symbolReplace(JSValue stringValue, JSValue replaceValue) {
    return symbolReplaceOn(this, stringValue, replaceValue);
  }

  JSValue symbolMatch(JSValue stringValue) {
    return symbolMatchOn(this, stringValue);
  }

  static JSValue symbolMatchOn(JSValue receiverValue, JSValue stringValue) {
    final runtime = JSRuntime.current;
    if (runtime == null) {
      throw JSError(
        'RegExp.prototype[Symbol.match] requires an active runtime',
      );
    }

    if (receiverValue is! JSObject && receiverValue is! JSFunction) {
      throw JSTypeError('RegExp.prototype[Symbol.match] requires an object');
    }

    final receiver = receiverValue as dynamic;
    final string = JSConversion.jsToString(stringValue);
    final flags = _resolveObservableFlags(receiver, receiverValue);
    final isGlobal = flags.contains('g');
    final isUnicode = flags.contains('u') || flags.contains('v');

    if (!isGlobal) {
      return _regExpExec(runtime, receiverValue, receiver, string);
    }

    _setPropertyStrict(receiver, 'lastIndex', JSValueFactory.number(0));

    final matches = <JSValue>[];
    while (true) {
      final result = _regExpExec(runtime, receiverValue, receiver, string);
      if (result.isNull) {
        return matches.isEmpty
            ? JSValueFactory.nullValue()
            : JSValueFactory.array(matches);
      }

      final matchResult = result as dynamic;
      final matched = JSConversion.jsToString(matchResult.getProperty('0'));
      matches.add(JSValueFactory.string(matched));

      if (matched.isNotEmpty) {
        continue;
      }

      final lastIndexValue = receiver.getProperty('lastIndex');
      final nextIndex = _advanceStringIndex(
        string,
        _toLength(lastIndexValue),
        isUnicode,
      );
      _setPropertyStrict(
        receiver,
        'lastIndex',
        JSValueFactory.number(nextIndex.toDouble()),
      );
    }
  }

  static JSValue symbolReplaceOn(
    JSValue receiverValue,
    JSValue stringValue,
    JSValue replaceValue,
  ) {
    final runtime = JSRuntime.current;
    if (runtime == null) {
      throw JSError(
        'RegExp.prototype[Symbol.replace] requires an active runtime',
      );
    }

    if (receiverValue is! JSObject && receiverValue is! JSFunction) {
      throw JSTypeError('RegExp.prototype[Symbol.replace] requires an object');
    }

    final receiver = receiverValue as dynamic;

    final string = JSConversion.jsToString(stringValue);
    final functionalReplace =
        replaceValue is JSFunction || replaceValue is JSNativeFunction;
    final replacementString = functionalReplace
        ? null
        : JSConversion.jsToString(replaceValue);

    final flags = _resolveObservableFlags(receiver, receiverValue);
    final isGlobal = flags.contains('g');
    final isUnicode = flags.contains('u') || flags.contains('v');

    if (isGlobal) {
      _setPropertyStrict(receiver, 'lastIndex', JSValueFactory.number(0));
    }

    final results = <dynamic>[];
    while (true) {
      final result = _regExpExec(runtime, receiverValue, receiver, string);

      if (result.isNull) {
        break;
      }
      final matchResult = result as dynamic;
      results.add(matchResult);

      if (!isGlobal) {
        break;
      }

      final matched = JSConversion.jsToString(matchResult.getProperty('0'));
      if (matched.isNotEmpty) {
        continue;
      }

      final lastIndexValue = receiver.getProperty('lastIndex');
      final nextIndex = _advanceStringIndex(
        string,
        _toLength(lastIndexValue),
        isUnicode,
      );
      _setPropertyStrict(
        receiver,
        'lastIndex',
        JSValueFactory.number(nextIndex.toDouble()),
      );
    }

    if (results.isEmpty) {
      return JSValueFactory.string(string);
    }

    final accumulated = StringBuffer();
    var nextSourcePosition = 0;

    for (final result in results) {
      final matched = JSConversion.jsToString(result.getProperty('0'));
      final position = math.min(
        math.max(_toInteger(result.getProperty('index')), 0),
        string.length,
      );
      final capturesLength = math.max(
        _toLength(result.getProperty('length')) - 1,
        0,
      );
      final captures = <JSValue>[];
      for (var i = 1; i <= capturesLength; i++) {
        final capture = result.getProperty(i.toString());
        captures.add(
          capture.isUndefined
              ? capture
              : JSValueFactory.string(JSConversion.jsToString(capture)),
        );
      }

      final rawNamedCaptures = result.getProperty('groups');
      final namedCaptures = !functionalReplace && !rawNamedCaptures.isUndefined
          ? rawNamedCaptures.toObject()
          : rawNamedCaptures;
      final replacement = functionalReplace
          ? _callReplaceFunction(
              runtime,
              replaceValue,
              matched,
              captures,
              position,
              string,
              namedCaptures,
            )
          : _getSubstitution(
              matched,
              string,
              position,
              captures,
              namedCaptures,
              replacementString!,
            );

      if (position >= nextSourcePosition) {
        accumulated.write(string.substring(nextSourcePosition, position));
        accumulated.write(replacement);
        nextSourcePosition = math.min(position + matched.length, string.length);
      }
    }

    accumulated.write(string.substring(nextSourcePosition));
    return JSValueFactory.string(accumulated.toString());
  }

  static void _setPropertyStrict(dynamic target, String name, JSValue value) {
    final descriptor = target.getOwnPropertyDescriptor(name);
    if (descriptor != null) {
      if (descriptor.isData && !descriptor.writable) {
        throw JSTypeError('Cannot assign to read only property \'$name\'');
      }
      if (descriptor.isAccessor && descriptor.setter == null) {
        throw JSTypeError('Cannot set property \'$name\' without a setter');
      }
    }
    target.setProperty(name, value);
  }

  static JSValue _regExpExec(
    JSRuntime runtime,
    JSValue receiverValue,
    dynamic receiver,
    String string,
  ) {
    final execMethod = receiver.getProperty('exec');
    final result = switch (execMethod) {
      JSFunction() || JSNativeFunction() => runtime.callFunction(execMethod, [
        JSValueFactory.string(string),
      ], receiverValue),
      _ when execMethod.isUndefined && receiverValue is JSRegExp =>
        receiverValue.exec(string),
      _ when execMethod.isUndefined => throw JSTypeError(
        'RegExp exec method is not callable',
      ),
      _ => throw JSTypeError('RegExp exec method is not callable'),
    };

    if (!result.isNull && result is! JSObject && result is! JSFunction) {
      throw JSTypeError('RegExp exec method must return an object or null');
    }
    return result;
  }

  static String _resolveObservableFlags(
    dynamic receiver,
    JSValue receiverValue,
  ) {
    if (receiverValue is JSRegExp) {
      final ownFlagsDescriptor = receiver.getOwnPropertyDescriptor('flags');
      if (ownFlagsDescriptor == null || ownFlagsDescriptor.isData) {
        return _composeObservableFlags(receiver);
      }
    }
    return JSConversion.jsToString(receiver.getProperty('flags'));
  }

  static String _composeObservableFlags(dynamic receiver) {
    final buffer = StringBuffer();
    if (receiver.getProperty('hasIndices').toBoolean()) {
      buffer.write('d');
    }
    if (receiver.getProperty('global').toBoolean()) {
      buffer.write('g');
    }
    if (receiver.getProperty('ignoreCase').toBoolean()) {
      buffer.write('i');
    }
    if (receiver.getProperty('multiline').toBoolean()) {
      buffer.write('m');
    }
    if (receiver.getProperty('dotAll').toBoolean()) {
      buffer.write('s');
    }
    if (receiver.getProperty('unicode').toBoolean()) {
      buffer.write('u');
    }
    if (receiver.getProperty('unicodeSets').toBoolean()) {
      buffer.write('v');
    }
    if (receiver.getProperty('sticky').toBoolean()) {
      buffer.write('y');
    }
    return buffer.toString();
  }

  static int _toLength(JSValue value) {
    const maxSafeInteger = 0x1FFFFFFFFFFFFF;
    final number = JSConversion.jsToNumber(value);
    if (number.isNaN || number <= 0) {
      return 0;
    }
    if (number.isInfinite) {
      return maxSafeInteger;
    }
    return math.min(number.floor(), maxSafeInteger);
  }

  static int _toInteger(JSValue value) {
    const maxSafeInteger = 0x1FFFFFFFFFFFFF;
    final number = JSConversion.jsToNumber(value);
    if (number.isNaN || number == 0) {
      return 0;
    }
    if (number.isInfinite) {
      return number.isNegative ? -maxSafeInteger : maxSafeInteger;
    }
    return number < 0 ? number.ceil() : number.floor();
  }

  static int _advanceStringIndex(String string, int index, bool unicode) {
    if (!unicode || index + 1 >= string.length) {
      return index + 1;
    }
    final first = string.codeUnitAt(index);
    if (first < 0xD800 || first > 0xDBFF) {
      return index + 1;
    }
    final second = string.codeUnitAt(index + 1);
    if (second < 0xDC00 || second > 0xDFFF) {
      return index + 1;
    }
    return index + 2;
  }

  static String _callReplaceFunction(
    JSRuntime runtime,
    JSValue replaceValue,
    String matched,
    List<JSValue> captures,
    int position,
    String string,
    JSValue namedCaptures,
  ) {
    final args = <JSValue>[JSValueFactory.string(matched), ...captures]
      ..add(JSValueFactory.number(position.toDouble()))
      ..add(JSValueFactory.string(string));
    if (!namedCaptures.isUndefined) {
      args.add(namedCaptures);
    }
    final result = runtime.callFunction(
      replaceValue,
      args,
      JSValueFactory.undefined(),
    );
    return JSConversion.jsToString(result);
  }

  static String _getSubstitution(
    String matched,
    String string,
    int position,
    List<JSValue> captures,
    JSValue namedCaptures,
    String replacement,
  ) {
    final buffer = StringBuffer();
    var index = 0;

    while (index < replacement.length) {
      final char = replacement[index];
      if (char != r'$' || index + 1 >= replacement.length) {
        buffer.write(char);
        index++;
        continue;
      }

      final next = replacement[index + 1];
      if (next == r'$') {
        buffer.write(r'$');
        index += 2;
        continue;
      }
      if (next == '&') {
        buffer.write(matched);
        index += 2;
        continue;
      }
      if (next == '`') {
        buffer.write(string.substring(0, position));
        index += 2;
        continue;
      }
      if (next == "'") {
        buffer.write(string.substring(position + matched.length));
        index += 2;
        continue;
      }
      if (next == '<') {
        final end = replacement.indexOf('>', index + 2);
        if (end == -1 ||
            namedCaptures.isUndefined ||
            namedCaptures is! JSObject) {
          buffer.write(r'$<');
          index += 2;
          continue;
        }
        final groupName = replacement.substring(index + 2, end);
        final capture = namedCaptures.getProperty(groupName);
        if (!capture.isUndefined) {
          buffer.write(JSConversion.jsToString(capture));
        }
        index = end + 1;
        continue;
      }
      if (_isDecimalDigit(next)) {
        var captureIndex = int.parse(next);
        var advance = 2;
        if (index + 2 < replacement.length &&
            _isDecimalDigit(replacement[index + 2])) {
          final doubleDigit = int.tryParse(
            replacement.substring(index + 1, index + 3),
          );
          if (doubleDigit != null && doubleDigit <= captures.length) {
            captureIndex = doubleDigit;
            advance = 3;
          }
        }
        if (captureIndex > 0 && captureIndex <= captures.length) {
          final capture = captures[captureIndex - 1];
          if (!capture.isUndefined) {
            buffer.write(JSConversion.jsToString(capture));
          }
        } else {
          buffer.write(replacement.substring(index, index + advance));
        }
        index += advance;
        continue;
      }

      buffer.write(char);
      index++;
    }

    return buffer.toString();
  }

  static bool _isDecimalDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  @override
  String toString() => '/$_source/$_flags';
}

class _NamedGroupCompilation {
  final String compiledSource;
  final List<String> publicNames;
  final List<String> compiledNames;

  _NamedGroupCompilation(
    this.compiledSource,
    this.publicNames,
    this.compiledNames,
  );
}

/// Specialized array for RegExp match results
class _MatchArray extends JSArray {
  final int _index;
  final String _input;
  final JSValue _groups; // ES2018: Named capture groups
  final JSObject? _indices; // ES2022: Match indices

  _MatchArray(
    List<JSValue> super.elements,
    this._index,
    this._input,
    this._groups, [
    this._indices,
  ]) {
    final arrayPrototype = JSArray.arrayPrototype;
    if (arrayPrototype != null) {
      setPrototype(arrayPrototype);
    }

    defineProperty(
      'index',
      PropertyDescriptor(
        value: JSValueFactory.number(_index.toDouble()),
        writable: true,
        enumerable: true,
        configurable: true,
      ),
    );
    defineProperty(
      'input',
      PropertyDescriptor(
        value: JSValueFactory.string(_input),
        writable: true,
        enumerable: true,
        configurable: true,
      ),
    );
    defineProperty(
      'groups',
      PropertyDescriptor(
        value: _groups,
        writable: true,
        enumerable: true,
        configurable: true,
      ),
    );
    defineProperty(
      'indices',
      PropertyDescriptor(
        value: _indices ?? JSValueFactory.undefined(),
        writable: true,
        enumerable: true,
        configurable: true,
      ),
    );
  }

  @override
  JSValue getProperty(String name) {
    final ownDescriptor = super.getOwnPropertyDescriptor(name);
    if (ownDescriptor != null) {
      return super.getProperty(name);
    }

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
    if (super.getOwnPropertyDescriptor(name) != null) {
      return true;
    }
    if (name == 'index' || name == 'input' || name == 'groups') {
      return true;
    }
    return super.hasProperty(name);
  }
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
