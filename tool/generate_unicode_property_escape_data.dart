import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';

void main() {
  final repoRoot = Directory.current;
  final sourceDir = Directory(
    '${repoRoot.path}/test262/test/built-ins/RegExp/property-escapes/generated',
  );
  final stringSourceDir = Directory('${sourceDir.path}/strings');
  final outputFile = File(
    '${repoRoot.path}/lib/src/runtime/unicode_property_escape_data.dart',
  );

  if (!sourceDir.existsSync()) {
    stderr.writeln('Missing source directory: ${sourceDir.path}');
    exitCode = 1;
    return;
  }

  final entries = <String, List<int>>{};
  final stringEntries = <String, List<List<int>>>{};
  final files =
      sourceDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.js'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));

  for (final file in files) {
    final content = file.readAsStringSync();
    final propertyBodies = _extractPositivePropertyBodies(content);
    if (propertyBodies.isEmpty) {
      continue;
    }

    final intervals = _mergeIntervals([
      ..._extractLoneCodePointIntervals(content),
      ..._extractRangeIntervals(content),
    ]);
    final flattened = <int>[];
    for (final interval in intervals) {
      flattened
        ..add(interval.$1)
        ..add(interval.$2);
    }

    for (final body in propertyBodies) {
      final existing = entries[body];
      if (existing != null && !_listsEqual(existing, flattened)) {
        stderr.writeln('Conflicting interval data for $body in ${file.path}');
        exitCode = 1;
        return;
      }
      entries[body] = flattened;
    }
  }

  if (stringSourceDir.existsSync()) {
    final stringFiles =
        stringSourceDir
            .listSync()
            .whereType<File>()
            .where(
              (file) =>
                  file.path.endsWith('.js') &&
                  !file.path.contains('-negative-'),
            )
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));

    for (final file in stringFiles) {
      final content = file.readAsStringSync();
      final propertyBodies = _extractPositiveStringPropertyBodies(content);
      if (propertyBodies.isEmpty) {
        continue;
      }

      final sequences = _extractMatchStringSequences(content);
      for (final body in propertyBodies) {
        final existing = stringEntries[body];
        if (existing != null && !_sequenceListsEqual(existing, sequences)) {
          stderr.writeln(
            'Conflicting string-property data for $body in ${file.path}',
          );
          exitCode = 1;
          return;
        }
        stringEntries[body] = sequences;
      }
    }
  }

  // --- Deduplication ---
  // Build unique interval sets indexed by a canonical string key.
  final uniqueLists = <List<int>>[];
  final keyToIndex = <String, int>{};
  final aliasToIndex = <String, int>{};

  for (final alias in entries.keys) {
    final list = entries[alias]!;
    final key = list.join(',');
    if (!keyToIndex.containsKey(key)) {
      keyToIndex[key] = uniqueLists.length;
      uniqueLists.add(list);
    }
    aliasToIndex[alias] = keyToIndex[key]!;
  }

  final sortedAliases = aliasToIndex.keys.toList()..sort();

  // --- Encode each unique list as delta-LEB128 blob ---
  final allBytes = BytesBuilder();
  final blobLengths = <int>[];
  for (final list in uniqueLists) {
    final blob = _encodeDeltaLeb128(list);
    allBytes.add(blob);
    blobLengths.add(blob.length);
  }
  final packed = base64Encode(allBytes.toBytes());

  final buffer = StringBuffer()
    ..writeln('library;')
    ..writeln()
    ..writeln('// GENERATED — do not edit by hand.')
    ..writeln(
      '// Run: dart run tool/generate_unicode_property_escape_data.dart',
    )
    ..writeln()
    ..writeln("import 'dart:convert';")
    ..writeln("import 'dart:typed_data';")
    ..writeln()
    ..writeln('class UnicodePropertyEscapeData {')
    ..writeln('  // alias → index into decoded interval lists')
    ..writeln('  static const Map<String, int> _aliasIndex = {');

  for (final alias in sortedAliases) {
    buffer.writeln(
      "    '${_escapeDartString(alias)}': ${aliasToIndex[alias]},",
    );
  }

  buffer
    ..writeln('  };')
    ..writeln()
    ..writeln(
      '  // Byte length of each delta-LEB128 encoded blob (one per unique interval set).',
    )
    ..writeln('  static const List<int> _blobLengths = [');

  const chunkSize = 20;
  for (var i = 0; i < blobLengths.length; i += chunkSize) {
    final end = min(i + chunkSize, blobLengths.length);
    buffer.writeln('    ${blobLengths.sublist(i, end).join(', ')},');
  }

  final sortedStringAliases = stringEntries.keys.toList()..sort();
  final stringBytes = BytesBuilder();
  final stringBlobLengths = <int>[];
  for (final alias in sortedStringAliases) {
    final blob = _encodeStringSequences(stringEntries[alias]!);
    stringBytes.add(blob);
    stringBlobLengths.add(blob.length);
  }
  final packedStrings = base64Encode(stringBytes.toBytes());

  buffer
    ..writeln('  ];')
    ..writeln()
    ..writeln('  // All blobs concatenated and base64-encoded.')
    ..writeln(
      '  // Encoding: delta-LEB128 — each interval list [s0,e0,s1,e1,…]',
    )
    ..writeln('  // is stored as [s0, e0-s0, s1-e0-1, e1-s1, …] (all ≥ 0),')
    ..writeln('  // then each value as unsigned LEB128 bytes.')
    ..writeln('  static const String _packed =');

  const lineWidth = 76;
  for (var i = 0; i < packed.length; i += lineWidth) {
    final end = min(i + lineWidth, packed.length);
    final isLast = end == packed.length;
    buffer.writeln("      '${packed.substring(i, end)}'${isLast ? ';' : ''}");
  }

  buffer
    ..writeln()
    ..writeln('  // String-property alias -> encoded sequence blob index.')
    ..writeln('  static const Map<String, int> _stringAliasIndex = {');

  for (var index = 0; index < sortedStringAliases.length; index++) {
    final alias = sortedStringAliases[index];
    buffer.writeln("    '${_escapeDartString(alias)}': $index,");
  }

  buffer
    ..writeln('  };')
    ..writeln()
    ..writeln('  static const List<int> _stringBlobLengths = [');

  for (var i = 0; i < stringBlobLengths.length; i += chunkSize) {
    final end = min(i + chunkSize, stringBlobLengths.length);
    buffer.writeln('    ${stringBlobLengths.sublist(i, end).join(', ')},');
  }

  buffer
    ..writeln('  ];')
    ..writeln()
    ..writeln('  // All encoded string-property sequence blobs, concatenated.')
    ..writeln(
      '  // Each sequence is a stream of ULEB128 code points terminated by 0.',
    )
    ..writeln('  static const String _stringPacked =');

  for (var i = 0; i < packedStrings.length; i += lineWidth) {
    final end = min(i + lineWidth, packedStrings.length);
    final isLast = end == packedStrings.length;
    buffer.writeln(
      "      '${packedStrings.substring(i, end)}'${isLast ? ';' : ''}",
    );
  }

  buffer
    ..writeln()
    ..writeln('  static List<Uint32List>? _cache;')
    ..writeln('  static List<_UnicodeStringTrieNode>? _stringTrieCache;')
    ..writeln()
    ..writeln('  /// Decoded interval tables, lazily initialised on first use.')
    ..writeln('  static List<Uint32List> get _data {')
    ..writeln('    if (_cache != null) return _cache!;')
    ..writeln('    final raw = base64Decode(_packed);')
    ..writeln('    final lists = <Uint32List>[];')
    ..writeln('    var pos = 0;')
    ..writeln('    for (final len in _blobLengths) {')
    ..writeln('      lists.add(_decode(raw, pos, pos + len));')
    ..writeln('      pos += len;')
    ..writeln('    }')
    ..writeln('    return _cache = lists;')
    ..writeln('  }')
    ..writeln()
    ..writeln(
      '  static Uint32List _decode(Uint8List bytes, int pos, int end) {',
    )
    ..writeln('    final result = <int>[];')
    ..writeln('    while (pos < end) {')
    ..writeln('      var v = 0;')
    ..writeln('      var shift = 0;')
    ..writeln('      while (true) {')
    ..writeln('        final b = bytes[pos++];')
    ..writeln('        v |= (b & 0x7F) << shift;')
    ..writeln('        if (b & 0x80 == 0) break;')
    ..writeln('        shift += 7;')
    ..writeln('      }')
    ..writeln('      result.add(v);')
    ..writeln('    }')
    ..writeln('    final n = result.length;')
    ..writeln('    final out = Uint32List(n);')
    ..writeln('    for (var i = 0; i < n; i++) {')
    ..writeln('      if (i == 0) {')
    ..writeln('        out[0] = result[0];')
    ..writeln('      } else if (i.isOdd) {')
    ..writeln('        out[i] = out[i - 1] + result[i]; // end = start + width')
    ..writeln('      } else {')
    ..writeln(
      '        out[i] = out[i - 1] + result[i] + 1; // next start = prev_end + gap + 1',
    )
    ..writeln('      }')
    ..writeln('    }')
    ..writeln('    return out;')
    ..writeln('  }')
    ..writeln()
    ..writeln('  static List<_UnicodeStringTrieNode> get _stringTries {')
    ..writeln('    if (_stringTrieCache != null) return _stringTrieCache!;')
    ..writeln('    final raw = base64Decode(_stringPacked);')
    ..writeln('    final tries = <_UnicodeStringTrieNode>[];')
    ..writeln('    var pos = 0;')
    ..writeln('    for (final len in _stringBlobLengths) {')
    ..writeln(
      '      tries.add(_buildStringTrie(_decodeStringSequences(raw, pos, pos + len)));',
    )
    ..writeln('      pos += len;')
    ..writeln('    }')
    ..writeln('    return _stringTrieCache = tries;')
    ..writeln('  }')
    ..writeln()
    ..writeln('  static List<List<int>> _decodeStringSequences(')
    ..writeln('    Uint8List bytes,')
    ..writeln('    int pos,')
    ..writeln('    int end,')
    ..writeln('  ) {')
    ..writeln('    final sequences = <List<int>>[];')
    ..writeln('    var current = <int>[];')
    ..writeln('    while (pos < end) {')
    ..writeln('      var value = 0;')
    ..writeln('      var shift = 0;')
    ..writeln('      while (true) {')
    ..writeln('        final b = bytes[pos++];')
    ..writeln('        value |= (b & 0x7F) << shift;')
    ..writeln('        if (b & 0x80 == 0) break;')
    ..writeln('        shift += 7;')
    ..writeln('      }')
    ..writeln('      if (value == 0) {')
    ..writeln('        sequences.add(current);')
    ..writeln('        current = <int>[];')
    ..writeln('      } else {')
    ..writeln('        current.add(value);')
    ..writeln('      }')
    ..writeln('    }')
    ..writeln('    return sequences;')
    ..writeln('  }')
    ..writeln()
    ..writeln('  static _UnicodeStringTrieNode _buildStringTrie(')
    ..writeln('    List<List<int>> sequences,')
    ..writeln('  ) {')
    ..writeln('    final root = _UnicodeStringTrieNode();')
    ..writeln('    for (final sequence in sequences) {')
    ..writeln('      var node = root;')
    ..writeln('      for (final codePoint in sequence) {')
    ..writeln('        node = node.children.putIfAbsent(')
    ..writeln('          codePoint,')
    ..writeln('          _UnicodeStringTrieNode.new,')
    ..writeln('        );')
    ..writeln('      }')
    ..writeln('      node.terminal = true;')
    ..writeln('    }')
    ..writeln('    return root;')
    ..writeln('  }')
    ..writeln()
    ..writeln(
      '  /// Returns true if [codePoint] is in the interval set for [propertyBody].',
    )
    ..writeln('  static bool contains(String propertyBody, int codePoint) {')
    ..writeln('    final index = _aliasIndex[propertyBody];')
    ..writeln('    if (index == null) return false;')
    ..writeln('    final intervals = _data[index];')
    ..writeln('    var low = 0;')
    ..writeln('    var high = intervals.length ~/ 2 - 1;')
    ..writeln('    while (low <= high) {')
    ..writeln('      final mid = (low + high) >> 1;')
    ..writeln('      final start = intervals[mid * 2];')
    ..writeln('      final end = intervals[mid * 2 + 1];')
    ..writeln('      if (codePoint < start) {')
    ..writeln('        high = mid - 1;')
    ..writeln('      } else if (codePoint > end) {')
    ..writeln('        low = mid + 1;')
    ..writeln('      } else {')
    ..writeln('        return true;')
    ..writeln('      }')
    ..writeln('    }')
    ..writeln('    return false;')
    ..writeln('  }')
    ..writeln()
    ..writeln(
      '  static bool matchesStringProperty(String propertyBody, String input) {',
    )
    ..writeln('    final index = _stringAliasIndex[propertyBody];')
    ..writeln('    if (index == null || input.isEmpty) return false;')
    ..writeln('    final trie = _stringTries[index];')
    ..writeln('    final runes = input.runes.toList(growable: false);')
    ..writeln('    final reachable = Uint8List(runes.length + 1);')
    ..writeln('    reachable[0] = 1;')
    ..writeln('    for (var start = 0; start < runes.length; start++) {')
    ..writeln('      if (reachable[start] == 0) continue;')
    ..writeln('      var node = trie;')
    ..writeln('      for (var index = start; index < runes.length; index++) {')
    ..writeln('        final next = node.children[runes[index]];')
    ..writeln('        if (next == null) break;')
    ..writeln('        node = next;')
    ..writeln('        if (node.terminal) {')
    ..writeln('          reachable[index + 1] = 1;')
    ..writeln('        }')
    ..writeln('      }')
    ..writeln('    }')
    ..writeln('    return reachable[runes.length] != 0;')
    ..writeln('  }')
    ..writeln()
    ..writeln('  /// Returns true if [propertyBody] is a known alias.')
    ..writeln('  static bool isKnown(String propertyBody) =>')
    ..writeln('      _aliasIndex.containsKey(propertyBody);')
    ..writeln()
    ..writeln('  static bool isKnownStringProperty(String propertyBody) =>')
    ..writeln('      _stringAliasIndex.containsKey(propertyBody);')
    ..writeln('}');

  buffer
    ..writeln()
    ..writeln('class _UnicodeStringTrieNode {')
    ..writeln('  bool terminal = false;')
    ..writeln('  final Map<int, _UnicodeStringTrieNode> children = {};')
    ..writeln('}');

  outputFile.writeAsStringSync(buffer.toString());
  stdout.writeln(
    'Wrote ${outputFile.path}: '
    '${sortedAliases.length} aliases → ${uniqueLists.length} sets, '
    '${allBytes.length} raw bytes → ${packed.length} base64 chars, '
    '${sortedStringAliases.length} string properties.',
  );
}

Set<String> _extractPositivePropertyBodies(String content) {
  final matches = RegExp(r'/\^\\p\{([^}]+)\}\+\$/u').allMatches(content);
  return {for (final match in matches) match.group(1)!};
}

Set<String> _extractPositiveStringPropertyBodies(String content) {
  final matches = RegExp(r'/\^\\p\{([^}]+)\}\+\$/v').allMatches(content);
  return {for (final match in matches) match.group(1)!};
}

List<List<int>> _extractMatchStringSequences(String content) {
  final match = RegExp(
    r'matchStrings:\s*\[(.*?)\]\s*(?:,\s*nonMatchStrings:|\}\);)',
    dotAll: true,
  ).firstMatch(content);
  if (match == null) {
    return const [];
  }

  final section = match.group(1)!;
  final sequences = <List<int>>[];
  for (final literal in RegExp(r'"(?:\\.|[^"\\])*"').allMatches(section)) {
    sequences.add(_decodeJsStringLiteral(literal.group(0)!).runes.toList());
  }
  return sequences;
}

List<(int, int)> _extractLoneCodePointIntervals(String content) {
  final sectionMatch = RegExp(
    r'loneCodePoints:\s*\[(.*?)\]\s*,\s*ranges:\s*\[',
    dotAll: true,
  ).firstMatch(content);
  if (sectionMatch == null) {
    return const [];
  }

  final intervals = <(int, int)>[];
  for (final match in RegExp(
    r'0x([0-9A-Fa-f]+)',
  ).allMatches(sectionMatch.group(1)!)) {
    final codePoint = int.parse(match.group(1)!, radix: 16);
    intervals.add((codePoint, codePoint));
  }
  return intervals;
}

List<(int, int)> _extractRangeIntervals(String content) {
  final sectionMatch = RegExp(
    r'ranges:\s*\[(.*?)\]\s*\}\s*\);',
    dotAll: true,
  ).firstMatch(content);
  if (sectionMatch == null) {
    return const [];
  }

  final intervals = <(int, int)>[];
  for (final match in RegExp(
    r'\[\s*0x([0-9A-Fa-f]+),\s*0x([0-9A-Fa-f]+)\s*\]',
  ).allMatches(sectionMatch.group(1)!)) {
    intervals.add((
      int.parse(match.group(1)!, radix: 16),
      int.parse(match.group(2)!, radix: 16),
    ));
  }
  return intervals;
}

List<(int, int)> _mergeIntervals(List<(int, int)> intervals) {
  if (intervals.isEmpty) {
    return const [];
  }

  final sorted = [...intervals]
    ..sort((left, right) => left.$1.compareTo(right.$1));
  final merged = <(int, int)>[sorted.first];

  for (final interval in sorted.skip(1)) {
    final last = merged.last;
    if (interval.$1 <= last.$2 + 1) {
      merged[merged.length - 1] = (
        last.$1,
        interval.$2 > last.$2 ? interval.$2 : last.$2,
      );
    } else {
      merged.add(interval);
    }
  }

  return merged;
}

String _escapeDartString(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

bool _listsEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

bool _sequenceListsEqual(List<List<int>> left, List<List<int>> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (!_listsEqual(left[i], right[i])) return false;
  }
  return true;
}

String _decodeJsStringLiteral(String literal) {
  final buffer = StringBuffer();
  for (var i = 1; i < literal.length - 1; i++) {
    final char = literal[i];
    if (char != r'\') {
      buffer.write(char);
      continue;
    }

    final next = literal[++i];
    switch (next) {
      case '"':
        buffer.write('"');
        break;
      case r'\':
        buffer.write(r'\');
        break;
      case 'b':
        buffer.writeCharCode(0x08);
        break;
      case 'f':
        buffer.writeCharCode(0x0C);
        break;
      case 'n':
        buffer.writeCharCode(0x0A);
        break;
      case 'r':
        buffer.writeCharCode(0x0D);
        break;
      case 't':
        buffer.writeCharCode(0x09);
        break;
      case 'x':
        buffer.writeCharCode(
          int.parse(literal.substring(i + 1, i + 3), radix: 16),
        );
        i += 2;
        break;
      case 'u':
        if (literal[i + 1] == '{') {
          final end = literal.indexOf('}', i + 2);
          buffer.writeCharCode(
            int.parse(literal.substring(i + 2, end), radix: 16),
          );
          i = end;
        } else {
          buffer.writeCharCode(
            int.parse(literal.substring(i + 1, i + 5), radix: 16),
          );
          i += 4;
        }
        break;
      default:
        buffer.write(next);
    }
  }
  return buffer.toString();
}

/// Delta-LEB128 encode a sorted flat interval list [s0,e0,s1,e1,…].
/// Stored deltas: d0=s0, d1=e0-s0, d2=s1-e0-1, d3=e1-s1, …  (all ≥ 0).
List<int> _encodeDeltaLeb128(List<int> intervals) {
  final bytes = <int>[];
  for (var i = 0; i < intervals.length; i++) {
    final int delta;
    if (i == 0) {
      delta = intervals[0];
    } else if (i.isOdd) {
      delta = intervals[i] - intervals[i - 1]; // interval width
    } else {
      delta = intervals[i] - intervals[i - 1] - 1; // gap between intervals
    }
    _writeLeb128(delta, bytes);
  }
  return bytes;
}

void _writeLeb128(int value, List<int> out) {
  do {
    var byte = value & 0x7F;
    value >>>= 7;
    if (value != 0) byte |= 0x80;
    out.add(byte);
  } while (value != 0);
}

List<int> _encodeStringSequences(List<List<int>> sequences) {
  final bytes = <int>[];
  for (final sequence in sequences) {
    for (final codePoint in sequence) {
      _writeLeb128(codePoint, bytes);
    }
    _writeLeb128(0, bytes);
  }
  return bytes;
}
