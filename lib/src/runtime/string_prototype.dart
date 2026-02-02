library;

import 'js_value.dart';
import 'js_regexp.dart';
import 'js_symbol.dart';
import 'native_functions.dart';
import 'iterator_protocol.dart';

/// Function executor callback type for calling JavaScript functions
typedef FunctionExecutor =
    JSValue Function(JSValue function, List<JSValue> args);

/// String prototype with all the methods
class StringPrototype {
  /// Function executor for calling JavaScript functions
  static FunctionExecutor? _functionExecutor;

  /// Sets the function executor (called by evaluator)
  static void setFunctionExecutor(FunctionExecutor executor) {
    _functionExecutor = executor;
  }

  /// String.prototype.length (property)
  static JSValue length(String str) {
    return JSValueFactory.number(str.length);
  }

  /// Helper: ToIntegerOrInfinity equivalent - converts to integer, NaN becomes 0
  static int _toIntegerOrZero(JSValue? arg) {
    if (arg == null || arg.isUndefined) {
      return 0;
    }
    final num = arg.toNumber();
    // NaN becomes 0
    if (num.isNaN) {
      return 0;
    }
    // Infinity stays as special case
    if (num.isInfinite) {
      return num.isNegative
          ? -9007199254740991
          : 9007199254740991; // Safe integer limits
    }
    return num.truncate();
  }

  /// String.prototype.charAt(index)
  static JSValue charAt(List<JSValue> args, String str) {
    // ToIntegerOrZero: undefined/NaN -> 0
    final index = _toIntegerOrZero(args.isEmpty ? null : args[0]);

    if (index < 0 || index >= str.length) {
      return JSValueFactory.string('');
    }

    return JSValueFactory.string(str[index]);
  }

  /// String.prototype.charCodeAt(index)
  static JSValue charCodeAt(List<JSValue> args, String str) {
    // ToIntegerOrZero: undefined/NaN -> 0
    final index = _toIntegerOrZero(args.isEmpty ? null : args[0]);

    if (index < 0 || index >= str.length) {
      return JSValueFactory.number(double.nan);
    }

    return JSValueFactory.number(str.codeUnitAt(index).toDouble());
  }

  /// ES6: String.prototype.codePointAt(index)
  /// Returns the Unicode code point at the given index, handling surrogate pairs
  static JSValue codePointAt(List<JSValue> args, String str) {
    // ToIntegerOrZero: undefined/NaN -> 0
    final index = _toIntegerOrZero(args.isEmpty ? null : args[0]);

    if (index < 0 || index >= str.length) {
      return JSValueFactory.undefined();
    }

    final first = str.codeUnitAt(index);

    // Check if it's a high surrogate (0xD800-0xDBFF)
    if (first >= 0xD800 && first <= 0xDBFF && index + 1 < str.length) {
      final second = str.codeUnitAt(index + 1);

      // Check if it's a low surrogate (0xDC00-0xDFFF)
      if (second >= 0xDC00 && second <= 0xDFFF) {
        // Combine surrogate pair into code point
        final codePoint =
            ((first - 0xD800) << 10) + (second - 0xDC00) + 0x10000;
        return JSValueFactory.number(codePoint.toDouble());
      }
    }

    // Not a surrogate pair, return the code unit as-is
    return JSValueFactory.number(first.toDouble());
  }

  /// String.prototype.substring(start, end?)
  static JSValue substring(List<JSValue> args, String str) {
    if (args.isEmpty) {
      return JSValueFactory.string(str);
    }

    var start = args[0].toNumber().floor();
    var end = args.length > 1 ? args[1].toNumber().floor() : str.length;

    // Normaliser selon ECMAScript
    start = start.clamp(0, str.length);
    end = end.clamp(0, str.length);

    if (start > end) {
      final temp = start;
      start = end;
      end = temp;
    }

    return JSValueFactory.string(str.substring(start, end));
  }

  /// String.prototype.slice(start, end?)
  static JSValue slice(List<JSValue> args, String str) {
    if (args.isEmpty) {
      return JSValueFactory.string(str);
    }

    var start = args[0].toNumber().floor();
    var end = args.length > 1 ? args[1].toNumber().floor() : str.length;

    // Handle negative indices
    if (start < 0) start = (str.length + start).clamp(0, str.length);
    if (end < 0) end = (str.length + end).clamp(0, str.length);

    start = start.clamp(0, str.length);
    end = end.clamp(0, str.length);

    if (start >= end) return JSValueFactory.string('');

    return JSValueFactory.string(str.substring(start, end));
  }

  /// String.prototype.concat(...strings)
  static JSValue concat(List<JSValue> args, String str) {
    // Detect if thisBinding was prepended (when concat is in thisBindingMethods)
    List<JSValue> realArgs = args;
    if (args.isNotEmpty && args[0] is JSString) {
      final firstArgStr = (args[0] as JSString).value;
      if (identical(firstArgStr, str)) {
        // thisBinding was prepended, skip it
        realArgs = args.sublist(1);
      }
    }

    final buffer = StringBuffer(str);
    for (final arg in realArgs) {
      buffer.write(JSConversion.jsToString(arg));
    }
    return JSValueFactory.string(buffer.toString());
  }

  /// String.prototype.indexOf(searchString, fromIndex?)
  static JSValue indexOf(List<JSValue> args, String str) {
    if (args.isEmpty) {
      return JSValueFactory.number(-1);
    }

    final searchString = JSConversion.jsToString(args[0]);
    var fromIndex = 0;
    if (args.length > 1) {
      final fromIndexNum = args[1].toNumber();
      if (fromIndexNum.isNaN) {
        fromIndex = 0;
      } else if (fromIndexNum.isInfinite) {
        fromIndex = fromIndexNum.isNegative ? 0 : str.length;
      } else {
        fromIndex = fromIndexNum.floor().clamp(0, str.length).toInt();
      }
    }

    final result = str.indexOf(searchString, fromIndex);
    return JSValueFactory.number(result.toDouble());
  }

  /// String.prototype.lastIndexOf(searchString, fromIndex?)
  static JSValue lastIndexOf(List<JSValue> args, String str) {
    if (args.isEmpty) {
      return JSValueFactory.number(-1);
    }

    final searchString = JSConversion.jsToString(args[0]);
    var fromIndex = str.length;
    if (args.length > 1) {
      final fromIndexNum = args[1].toNumber();
      if (fromIndexNum.isNaN) {
        fromIndex = str.length;
      } else if (fromIndexNum.isInfinite) {
        fromIndex = fromIndexNum.isNegative ? 0 : str.length;
      } else {
        fromIndex = fromIndexNum.floor().clamp(0, str.length).toInt();
      }
    }

    final result = str.lastIndexOf(searchString, fromIndex);
    return JSValueFactory.number(result.toDouble());
  }

  /// String.prototype.toLowerCase()
  static JSValue toLowerCase(List<JSValue> args, String str) {
    return JSValueFactory.string(str.toLowerCase());
  }

  /// String.prototype.toUpperCase()
  static JSValue toUpperCase(List<JSValue> args, String str) {
    return JSValueFactory.string(str.toUpperCase());
  }

  /// String.prototype.split(separator?, limit?)
  static JSValue split(List<JSValue> args, String str) {
    if (args.isEmpty) {
      return JSValueFactory.array([JSValueFactory.string(str)]);
    }

    final separator = args[0];
    var limit = -1; // -1 means no limit
    if (args.length > 1 && !args[1].isUndefined) {
      final limitNum = args[1].toNumber();
      if (!limitNum.isNaN) {
        limit = limitNum.floor();
      }
    }

    List<String> parts;

    // Support for regex
    if (separator is JSRegExp) {
      final regex = separator.dartRegExp;
      parts = str.split(regex);
    } else {
      final separatorStr = JSConversion.jsToString(separator);
      if (separatorStr.isEmpty) {
        // Split into individual characters
        parts = str.split('');
      } else {
        parts = str.split(separatorStr);
      }
    }

    if (limit >= 0 && parts.length > limit) {
      parts = parts.take(limit).toList();
    }

    final jsArray = parts.map((s) => JSValueFactory.string(s)).toList();
    return JSValueFactory.array(jsArray);
  }

  /// String.prototype.substr(start, length?)
  static JSValue substr(List<JSValue> args, String str) {
    if (args.isEmpty) {
      return JSValueFactory.string(str);
    }

    final start = args[0].toNumber().floor();
    final length = args.length > 1 ? args[1].toNumber().floor() : null;

    // Handle negative start (count from end)
    var actualStart = start;
    if (actualStart < 0) {
      actualStart = str.length + actualStart;
    }
    actualStart = actualStart.clamp(0, str.length);

    if (length == null) {
      // Return from start to end
      return JSValueFactory.string(str.substring(actualStart));
    } else {
      // Return specified length
      final end = (actualStart + length).clamp(0, str.length);
      return JSValueFactory.string(str.substring(actualStart, end.toInt()));
    }
  }

  /// String.prototype.substring(start, end?)
  static JSValue substringMethod(List<JSValue> args, String str) {
    if (args.isEmpty) {
      return JSValueFactory.string(str);
    }

    final start = args[0].toNumber().floor();
    final end = args.length > 1 ? args[1].toNumber().floor() : str.length;

    // Clamp values
    final actualStart = start.clamp(0, str.length);
    final actualEnd = end.clamp(0, str.length);

    // Swap if start > end
    final from = actualStart < actualEnd ? actualStart : actualEnd;
    final to = actualStart < actualEnd ? actualEnd : actualStart;

    return JSValueFactory.string(str.substring(from.toInt(), to.toInt()));
  }

  /// String.prototype.replace(searchValue, replaceValue)
  static JSValue replace(List<JSValue> args, String str) {
    if (args.length < 2) {
      return JSValueFactory.string(str);
    }

    final searchValue = args[0];
    final replaceValueArg = args[1];

    // Check if replaceValue is a function
    final isFunction =
        replaceValueArg is JSFunction || replaceValueArg is JSNativeFunction;

    // Support for regex
    if (searchValue is JSRegExp) {
      final regex = searchValue.dartRegExp;

      if (isFunction) {
        // ES2018: Replace with function callback supporting named groups
        return _replaceWithFunction(
          str,
          searchValue,
          replaceValueArg,
          searchValue.global,
        );
      } else {
        // String replacement with special patterns
        final replaceValue = _processReplacementString(
          JSConversion.jsToString(replaceValueArg),
          searchValue,
        );

        if (searchValue.global) {
          // Replace all occurrences if global
          final result = str.replaceAllMapped(regex, (match) {
            return _substituteReplacementPatterns(replaceValue, match, str);
          });
          return JSValueFactory.string(result);
        } else {
          // Replace only the first occurrence
          final result = str.replaceFirstMapped(regex, (match) {
            return _substituteReplacementPatterns(replaceValue, match, str);
          });
          return JSValueFactory.string(result);
        }
      }
    } else {
      // Original method for strings
      final searchValueStr = JSConversion.jsToString(searchValue);

      // Replace only the first occurrence (comme JavaScript)
      final index = str.indexOf(searchValueStr);
      if (index == -1) {
        return JSValueFactory.string(str);
      }

      if (isFunction) {
        // Call function with: match, offset, string
        final List<JSValue> callArgs = [
          JSValueFactory.string(searchValueStr),
          JSValueFactory.number(index.toDouble()),
          JSValueFactory.string(str),
        ];

        JSValue result;
        if (replaceValueArg is JSNativeFunction) {
          result = replaceValueArg.nativeImpl(callArgs);
        } else if (_functionExecutor != null) {
          result = _functionExecutor!(replaceValueArg, callArgs);
        } else {
          // Fallback: just convert to string
          result = JSValueFactory.string(
            JSConversion.jsToString(replaceValueArg),
          );
        }

        final replacement = JSConversion.jsToString(result);
        final before = str.substring(0, index);
        final after = str.substring(index + searchValueStr.length);
        return JSValueFactory.string(before + replacement + after);
      } else {
        final replaceValue = JSConversion.jsToString(replaceValueArg);
        final before = str.substring(0, index);
        final after = str.substring(index + searchValueStr.length);
        final result = before + replaceValue + after;
        return JSValueFactory.string(result);
      }
    }
  }

  /// ES2018: Replace with function callback supporting named groups
  static JSValue _replaceWithFunction(
    String str,
    JSRegExp jsRegex,
    JSValue replaceFunction,
    bool isGlobal,
  ) {
    final regex = jsRegex.dartRegExp;
    final matchesList = isGlobal
        ? regex.allMatches(str).toList()
        : [regex.firstMatch(str)].whereType<RegExpMatch>().toList();

    final buffer = StringBuffer();
    int lastIndex = 0;

    for (final match in matchesList) {
      // Add text before match
      buffer.write(str.substring(lastIndex, match.start));

      // Prepare callback arguments:
      // match, p1, p2, ..., pn, offset, string, groups
      final List<JSValue> callArgs = [];

      // 1. The matched substring
      callArgs.add(JSValueFactory.string(match.group(0) ?? ''));

      // 2. Captured groups (p1, p2, ..., pn)
      for (int i = 1; i <= match.groupCount; i++) {
        final group = match.group(i);
        callArgs.add(
          group != null
              ? JSValueFactory.string(group)
              : JSValueFactory.undefined(),
        );
      }

      // 3. The offset of the matched substring
      callArgs.add(JSValueFactory.number(match.start.toDouble()));

      // 4. The whole string being examined
      callArgs.add(JSValueFactory.string(str));

      // 5. ES2018: Named capture groups object
      final groupsObject = JSObject();
      // Parse group names from regex pattern
      final groupNames = _parseGroupNamesFromPattern(jsRegex.source);
      for (final name in groupNames) {
        final value = match.namedGroup(name);
        groupsObject.setProperty(
          name,
          value != null
              ? JSValueFactory.string(value)
              : JSValueFactory.undefined(),
        );
      }
      callArgs.add(groupsObject);

      // Call the replacement function
      JSValue result;
      if (replaceFunction is JSNativeFunction) {
        result = replaceFunction.nativeImpl(callArgs);
      } else if (_functionExecutor != null) {
        result = _functionExecutor!(replaceFunction, callArgs);
      } else {
        // Fallback: just convert to string
        result = JSValueFactory.string(
          JSConversion.jsToString(replaceFunction),
        );
      }

      // Add replacement text
      buffer.write(JSConversion.jsToString(result));
      lastIndex = match.end;
    }

    // Add remaining text
    buffer.write(str.substring(lastIndex));

    return JSValueFactory.string(buffer.toString());
  }

  /// Parse named group names from regex pattern
  static List<String> _parseGroupNamesFromPattern(String pattern) {
    final groupNamePattern = RegExp(r'\(\?<(\w+)>');
    final matches = groupNamePattern.allMatches(pattern);
    return matches.map((m) => m.group(1)!).toList();
  }

  /// Process replacement string for special patterns
  static String _processReplacementString(
    String replacement,
    JSRegExp jsRegex,
  ) {
    // Return as-is, will be processed during substitution
    return replacement;
  }

  /// Substitute replacement patterns like $1, $2, $&, $`, $', $&lt;name&gt;
  static String _substituteReplacementPatterns(
    String replacement,
    Match match,
    String originalString,
  ) {
    // JavaScript replacement patterns:
    // $$ - inserts $
    // $& - inserts matched substring
    // $` - inserts portion before match
    // $' - inserts portion after match
    // $n - inserts nth captured group (1-indexed)
    // $<name> - inserts named captured group (ES2018)

    final buffer = StringBuffer();
    int i = 0;

    while (i < replacement.length) {
      if (replacement[i] == r'$' && i + 1 < replacement.length) {
        final next = replacement[i + 1];

        if (next == r'$') {
          // $$ -> $
          buffer.write(r'$');
          i += 2;
        } else if (next == '&') {
          // $& -> matched substring
          buffer.write(match.group(0) ?? '');
          i += 2;
        } else if (next == '`') {
          // $` -> portion before match
          buffer.write(originalString.substring(0, match.start));
          i += 2;
        } else if (next == "'") {
          // $' -> portion after match
          buffer.write(originalString.substring(match.end));
          i += 2;
        } else if (next == '<' && match is RegExpMatch) {
          // ES2018: $<name> -> named captured group
          final nameEnd = replacement.indexOf('>', i + 2);
          if (nameEnd != -1) {
            final groupName = replacement.substring(i + 2, nameEnd);
            try {
              final value = match.namedGroup(groupName);
              buffer.write(value ?? '');
            } catch (e) {
              // Group doesn't exist, write nothing (JavaScript behavior)
              buffer.write('');
            }
            i = nameEnd + 1;
          } else {
            buffer.write(replacement[i]);
            i++;
          }
        } else if (RegExp(r'\d').hasMatch(next)) {
          // $n or $nn -> captured group
          // Try two digits first, then one digit
          int groupNum = 0;
          int endIndex = i + 1;

          // Try two-digit group number first
          if (i + 2 < replacement.length &&
              RegExp(r'\d').hasMatch(replacement[i + 2])) {
            final twoDigit = int.tryParse(replacement.substring(i + 1, i + 3));
            if (twoDigit != null &&
                twoDigit > 0 &&
                twoDigit <= match.groupCount) {
              groupNum = twoDigit;
              endIndex = i + 3;
            }
          }

          // If two-digit didn't work, try one digit
          if (groupNum == 0) {
            groupNum = int.parse(next);
            endIndex = i + 2;
          }

          if (groupNum > 0 && groupNum <= match.groupCount) {
            buffer.write(match.group(groupNum) ?? '');
          } else {
            // Invalid group number, write as-is
            buffer.write(replacement.substring(i, endIndex));
          }
          i = endIndex;
        } else {
          buffer.write(replacement[i]);
          i++;
        }
      } else {
        buffer.write(replacement[i]);
        i++;
      }
    }

    return buffer.toString();
  }

  /// String.prototype.replaceAll(searchValue, replaceValue)
  /// ES2021: Replace all occurrences of a substring or regex pattern
  /// Supports replacement functions as callbacks
  static JSValue replaceAll(List<JSValue> args, String str) {
    if (args.length < 2) {
      throw JSTypeError(
        'String.prototype.replaceAll requires at least 2 arguments',
      );
    }

    final searchValue = args[0];
    final replacer = args[1];

    // Support for regex
    if (searchValue is JSRegExp) {
      final regex = searchValue.dartRegExp;

      // ES2021: The regex must have the 'g' flag (global)
      if (!searchValue.global) {
        throw JSTypeError(
          'String.prototype.replaceAll called with a non-global RegExp argument',
        );
      }

      // If replacer is a function
      if (replacer.isFunction) {
        final replacerFunc = replacer;

        final result = str.replaceAllMapped(regex, (match) {
          final matchArgs = <JSValue>[
            JSValueFactory.string(match.group(0) ?? ''), // entire match
          ];

          // Add captured groups
          for (int i = 1; i <= match.groupCount; i++) {
            final group = match.group(i);
            matchArgs.add(
              group != null
                  ? JSValueFactory.string(group)
                  : JSValueFactory.undefined(),
            );
          }

          // Add offset and original string
          matchArgs.add(JSValueFactory.number(match.start.toDouble()));
          matchArgs.add(JSValueFactory.string(str));

          // Call the replacement function
          final replaceResult = _callReplacerFunction(replacerFunc, matchArgs);
          return JSConversion.jsToString(replaceResult);
        });

        return JSValueFactory.string(result);
      } else {
        // Replacer is a string
        final replaceValue = JSConversion.jsToString(replacer);
        final result = str.replaceAll(regex, replaceValue);
        return JSValueFactory.string(result);
      }
    } else {
      // For strings, replace all occurrences
      final searchValueStr = JSConversion.jsToString(searchValue);

      // If replacer is a function
      if (replacer.isFunction) {
        final replacerFunc = replacer;
        final result = StringBuffer();
        int lastIndex = 0;

        while (true) {
          final index = str.indexOf(searchValueStr, lastIndex);
          if (index == -1) {
            result.write(str.substring(lastIndex));
            break;
          }

          // Add text before the match
          result.write(str.substring(lastIndex, index));

          // Call the replacement function
          final matchArgs = [
            JSValueFactory.string(searchValueStr),
            JSValueFactory.number(index.toDouble()),
            JSValueFactory.string(str),
          ];
          final replaceResult = _callReplacerFunction(replacerFunc, matchArgs);
          result.write(JSConversion.jsToString(replaceResult));

          lastIndex = index + searchValueStr.length;
        }

        return JSValueFactory.string(result.toString());
      } else {
        // Replacer is a string
        final replaceValue = JSConversion.jsToString(replacer);
        final result = str.replaceAll(searchValueStr, replaceValue);
        return JSValueFactory.string(result);
      }
    }
  }

  /// Helper to call a replacement function
  static JSValue _callReplacerFunction(JSValue func, List<JSValue> args) {
    if (func is JSFunction) {
      // Call via evaluator if available
      // For now, return empty string if no evaluator
      return JSValueFactory.string('');
    } else if (func is JSNativeFunction) {
      return func.call(args);
    }
    return JSValueFactory.string('');
  }

  /// String.prototype.match(pattern)
  static JSValue match(List<JSValue> args, String str) {
    if (args.isEmpty) {
      return JSValueFactory.nullValue();
    }

    final pattern = args[0];
    JSRegExp regex;

    // Convert to regex if not already
    if (pattern is JSRegExp) {
      regex = pattern;
    } else {
      // Create a regex from a string
      final patternStr = JSConversion.jsToString(pattern);
      regex = JSRegExpFactory.create(patternStr, '');
    }

    if (regex.global) {
      // Trouver toutes les occurrences
      final matches = regex.dartRegExp.allMatches(str);
      final results = matches
          .map((match) => JSValueFactory.string(match.group(0)!))
          .toList();

      if (results.isEmpty) {
        return JSValueFactory.nullValue();
      }

      return JSValueFactory.array(results);
    } else {
      // Find first occurrence and return array with groups
      return regex.exec(str);
    }
  }

  /// ES2020: String.prototype.matchAll(pattern)
  /// Returns an iterator of all matches (with capture groups)
  static JSValue matchAll(List<JSValue> args, String str) {
    final pattern = args.isEmpty ? JSValueFactory.undefined() : args[0];
    JSRegExp jsRegex;

    // Convert to regex if not already
    if (pattern is JSRegExp) {
      jsRegex = pattern;
    } else if (pattern.isNull || pattern.isUndefined) {
      // null/undefined devient regex vide avec flag global
      jsRegex = JSRegExpFactory.create('', 'g');
    } else {
      // Create a regex from a string
      final patternStr = JSConversion.jsToString(pattern);
      // matchAll requiert le flag 'g' (global)
      // If the pattern doesn't have 'g' flag, add it
      jsRegex = JSRegExpFactory.create(patternStr, 'g');
    }

    // ES2020: matchAll DOIT avoir le flag 'g'
    if (!jsRegex.global) {
      throw JSTypeError('matchAll requires a global RegExp (use /pattern/g)');
    }

    // Return an iterator of matches
    return JSRegExpMatchIterator(str, jsRegex.dartRegExp);
  }

  /// String.prototype.search(regexp)
  static JSValue search(List<JSValue> args, String str) {
    if (args.isEmpty) {
      return JSValueFactory.number(-1);
    }

    final pattern = args[0];
    JSRegExp regex;

    // Convert to regex if not already
    if (pattern is JSRegExp) {
      regex = pattern;
    } else {
      // Create a regex from a string
      final patternStr = JSConversion.jsToString(pattern);
      regex = JSRegExpFactory.create(patternStr, '');
    }

    final match = regex.dartRegExp.firstMatch(str);
    return JSValueFactory.number(match?.start ?? -1);
  }

  /// String.prototype.includes(searchString, position?)
  static JSValue includes(List<JSValue> args, String str) {
    if (args.isEmpty) {
      return JSValueFactory.boolean(false);
    }

    final searchString = JSConversion.jsToString(args[0]);
    final position = args.length > 1 ? args[1].toNumber().floor() : 0;

    final startIndex = position.clamp(0, str.length);
    final result = str.substring(startIndex).contains(searchString);

    return JSValueFactory.boolean(result);
  }

  /// String.prototype.startsWith(searchString, position?)
  static JSValue startsWith(List<JSValue> args, String str) {
    if (args.isEmpty) {
      return JSValueFactory.boolean(false);
    }

    final searchString = JSConversion.jsToString(args[0]);
    final position = args.length > 1 ? args[1].toNumber().floor() : 0;

    final startIndex = position.clamp(0, str.length);
    final result = str.substring(startIndex).startsWith(searchString);

    return JSValueFactory.boolean(result);
  }

  /// String.prototype.endsWith(searchString, length?)
  static JSValue endsWith(List<JSValue> args, String str) {
    if (args.isEmpty) {
      return JSValueFactory.boolean(false);
    }

    final searchString = JSConversion.jsToString(args[0]);
    final length = args.length > 1 ? args[1].toNumber().floor() : str.length;

    final endIndex = length.clamp(0, str.length);
    final result = str.substring(0, endIndex).endsWith(searchString);

    return JSValueFactory.boolean(result);
  }

  /// String.prototype.trim()
  static JSValue trim(List<JSValue> args, String str) {
    return JSValueFactory.string(str.trim());
  }

  /// ES2019: String.prototype.trimStart() - Remove leading whitespace
  static JSValue trimStart(List<JSValue> args, String str) {
    return JSValueFactory.string(str.trimLeft());
  }

  /// ES2019: String.prototype.trimEnd() - Remove trailing whitespace
  static JSValue trimEnd(List<JSValue> args, String str) {
    return JSValueFactory.string(str.trimRight());
  }

  /// ES2019: String.prototype.trimLeft() - Alias for trimStart()
  static JSValue trimLeft(List<JSValue> args, String str) {
    return trimStart(args, str);
  }

  /// ES2019: String.prototype.trimRight() - Alias for trimEnd()
  static JSValue trimRight(List<JSValue> args, String str) {
    return trimEnd(args, str);
  }

  /// String.prototype.repeat(count)
  static JSValue repeat(List<JSValue> args, String str) {
    if (args.isEmpty) {
      return JSValueFactory.string('');
    }

    final count = args[0].toNumber().floor();
    if (count < 0 || count == double.infinity) {
      throw JSError('Invalid count value');
    }

    return JSValueFactory.string(str * count);
  }

  /// ES2022: String.prototype.at(index)
  /// Returns character at given index, supporting negative indexing
  static JSValue at(List<JSValue> args, String str) {
    if (args.isEmpty) {
      throw JSTypeError('String.prototype.at requires 1 argument');
    }

    // ES spec: Convert argument to number using ToNumber
    final numValue = args[0].toNumber();

    // ES2022: NaN is treated as 0
    if (numValue.isNaN) {
      return JSValueFactory.undefined();
    }

    final index = numValue.toInt();
    final normalizedIndex = index < 0 ? str.length + index : index;

    if (normalizedIndex < 0 || normalizedIndex >= str.length) {
      return JSValueFactory.undefined();
    }

    return JSValueFactory.string(str[normalizedIndex]);
  }

  /// String.prototype.padStart(targetLength, padString?)
  static JSValue padStart(List<JSValue> args, String str) {
    if (args.isEmpty) {
      return JSValueFactory.string(str);
    }

    final targetLengthNum = args[0].toNumber();

    // If targetLength is NaN or negative, return string unchanged
    if (targetLengthNum.isNaN || targetLengthNum < 0) {
      return JSValueFactory.string(str);
    }

    // For Infinity, return string unchanged
    if (targetLengthNum.isInfinite) {
      return JSValueFactory.string(str);
    }

    final targetLength = targetLengthNum.floor();

    // If target length <= current length, return string unchanged
    if (targetLength <= str.length) {
      return JSValueFactory.string(str);
    }

    // PadString defaults to a space
    final padString = args.length > 1 && !args[1].isUndefined
        ? JSConversion.jsToString(args[1])
        : ' ';

    // If padString is empty, return string unchanged
    if (padString.isEmpty) {
      return JSValueFactory.string(str);
    }

    final padLength = targetLength - str.length;

    // Repeat padString as many times as needed
    final fullPad = padString * ((padLength / padString.length).ceil());

    // Truncate to exact number of characters needed
    final padding = fullPad.substring(0, padLength);

    return JSValueFactory.string(padding + str);
  }

  /// String.prototype.padEnd(targetLength, padString?)
  static JSValue padEnd(List<JSValue> args, String str) {
    if (args.isEmpty) {
      return JSValueFactory.string(str);
    }

    final targetLength = args[0].toNumber().floor();

    // If target length <= current length, return string unchanged
    if (targetLength <= str.length) {
      return JSValueFactory.string(str);
    }

    // PadString defaults to a space
    final padString = args.length > 1 && !args[1].isUndefined
        ? JSConversion.jsToString(args[1])
        : ' ';

    // If padString is empty, return string unchanged
    if (padString.isEmpty) {
      return JSValueFactory.string(str);
    }

    final padLength = targetLength - str.length;

    // Repeat padString as many times as needed
    final fullPad = padString * ((padLength / padString.length).ceil());

    // Truncate to exact number of characters needed
    final padding = fullPad.substring(0, padLength);

    return JSValueFactory.string(str + padding);
  }

  /// Creates a native function for a string method
  static JSNativeFunction createMethod(String methodName, Function method) {
    return JSNativeFunction(
      functionName: methodName,
      nativeImpl: (args) {
        // The 'this' will be passed by the evaluator
        throw JSError('String method $methodName called incorrectly');
      },
    );
  }

  /// Gets a property/method for a string (auto-boxing)
  static JSValue getStringProperty(String str, String propertyName) {
    switch (propertyName) {
      case 'length':
        return length(str);
      case 'charAt':
        return JSNativeFunction(
          functionName: 'charAt',
          nativeImpl: (args) => charAt(args, str),
        );
      case 'charCodeAt':
        return JSNativeFunction(
          functionName: 'charCodeAt',
          nativeImpl: (args) => charCodeAt(args, str),
        );
      case 'codePointAt':
        return JSNativeFunction(
          functionName: 'codePointAt',
          nativeImpl: (args) => codePointAt(args, str),
        );
      case 'substring':
        return JSNativeFunction(
          functionName: 'substring',
          nativeImpl: (args) => substring(args, str),
        );
      case 'slice':
        return JSNativeFunction(
          functionName: 'slice',
          nativeImpl: (args) => slice(args, str),
        );
      case 'concat':
        return JSNativeFunction(
          functionName: 'concat',
          nativeImpl: (args) => concat(args, str),
          hasContextBound: true,
        );
      case 'indexOf':
        return JSNativeFunction(
          functionName: 'indexOf',
          nativeImpl: (args) => indexOf(args, str),
          hasContextBound: true,
        );
      case 'lastIndexOf':
        return JSNativeFunction(
          functionName: 'lastIndexOf',
          nativeImpl: (args) => lastIndexOf(args, str),
          hasContextBound: true,
        );
      case 'toLowerCase':
        return JSNativeFunction(
          functionName: 'toLowerCase',
          nativeImpl: (args) => toLowerCase(args, str),
        );
      case 'toUpperCase':
        return JSNativeFunction(
          functionName: 'toUpperCase',
          nativeImpl: (args) => toUpperCase(args, str),
        );
      case 'split':
        return JSNativeFunction(
          functionName: 'split',
          nativeImpl: (args) => split(args, str),
        );
      case 'replace':
        return JSNativeFunction(
          functionName: 'replace',
          nativeImpl: (args) => replace(args, str),
        );
      case 'replaceAll':
        return JSNativeFunction(
          functionName: 'replaceAll',
          nativeImpl: (args) => replaceAll(args, str),
        );
      case 'match':
        return JSNativeFunction(
          functionName: 'match',
          nativeImpl: (args) => match(args, str),
        );
      case 'matchAll':
        return JSNativeFunction(
          functionName: 'matchAll',
          nativeImpl: (args) => matchAll(args, str),
        );
      case 'search':
        return JSNativeFunction(
          functionName: 'search',
          nativeImpl: (args) => search(args, str),
        );
      case 'includes':
        return JSNativeFunction(
          functionName: 'includes',
          nativeImpl: (args) => includes(args, str),
          hasContextBound: true, // String bound via closure
        );
      case 'startsWith':
        return JSNativeFunction(
          functionName: 'startsWith',
          nativeImpl: (args) => startsWith(args, str),
          hasContextBound: true,
        );
      case 'endsWith':
        return JSNativeFunction(
          functionName: 'endsWith',
          nativeImpl: (args) => endsWith(args, str),
          hasContextBound: true,
        );
      case 'trim':
        return JSNativeFunction(
          functionName: 'trim',
          nativeImpl: (args) => trim(args, str),
        );
      case 'trimStart':
        return JSNativeFunction(
          functionName: 'trimStart',
          nativeImpl: (args) => trimStart(args, str),
        );
      case 'trimEnd':
        return JSNativeFunction(
          functionName: 'trimEnd',
          nativeImpl: (args) => trimEnd(args, str),
        );
      case 'trimLeft':
        return JSNativeFunction(
          functionName: 'trimLeft',
          nativeImpl: (args) => trimLeft(args, str),
        );
      case 'trimRight':
        return JSNativeFunction(
          functionName: 'trimRight',
          nativeImpl: (args) => trimRight(args, str),
        );
      case 'repeat':
        return JSNativeFunction(
          functionName: 'repeat',
          nativeImpl: (args) => repeat(args, str),
        );
      case 'at':
        return JSNativeFunction(
          functionName: 'at',
          nativeImpl: (args) => at(args, str),
          hasContextBound: true, // String bound via closure
        );
      case 'padStart':
        return JSNativeFunction(
          functionName: 'padStart',
          nativeImpl: (args) => padStart(args, str),
        );
      case 'padEnd':
        return JSNativeFunction(
          functionName: 'padEnd',
          nativeImpl: (args) => padEnd(args, str),
        );
      case 'substr':
        return JSNativeFunction(
          functionName: 'substr',
          nativeImpl: (args) => substr(args, str),
        );
      case 'valueOf':
        return JSNativeFunction(
          functionName: 'valueOf',
          nativeImpl: (args) => JSValueFactory.string(str),
        );
      case 'toString':
        return JSNativeFunction(
          functionName: 'toString',
          nativeImpl: (args) => JSValueFactory.string(str),
        );
      default:
        // Check for Symbol.iterator
        if (propertyName == JSSymbol.iterator.toString()) {
          return JSNativeFunction(
            functionName: 'Symbol.iterator',
            nativeImpl: (args) {
              // Return an iterator for the string
              return JSStringIterator(str);
            },
          );
        }
        return JSValueFactory.undefined();
    }
  }
}
