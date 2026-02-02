import 'package:intl/intl.dart' as intl;
import 'package:intl/date_symbol_data_local.dart';
import 'package:js_interpreter/src/runtime/date_object.dart';
import 'js_value.dart';
import 'native_functions.dart';
import 'js_symbol.dart';

/// Helper to get string option value or null if undefined
String? _getStringOption(JSObject options, String key) {
  final value = options.getProperty(key);
  if (value.isUndefined) return null;
  return value.toString();
}

/// Helper to get bool option value or default
bool _getBoolOption(JSObject options, String key, bool defaultValue) {
  final value = options.getProperty(key);
  if (value.isUndefined) return defaultValue;
  return value.toBoolean();
}

/// Helper to get int option value or null
int? _getIntOption(JSObject options, String key) {
  final value = options.getProperty(key);
  if (value.isUndefined) return null;
  return value.toNumber().toInt();
}

/// JavaScript Intl API implementation using Dart's intl package
class IntlObject {
  static bool _localesInitialized = false;

  /// Initialize locale data (call once at startup)
  static Future<void> initializeLocales() async {
    if (!_localesInitialized) {
      await initializeDateFormatting();
      _localesInitialized = true;
    }
  }

  /// Create the Intl global object
  static JSObject createIntlObject() {
    final intlObj = JSObject();

    // Intl.DateTimeFormat
    intlObj.setProperty('DateTimeFormat', _createDateTimeFormat());

    // Intl.NumberFormat
    intlObj.setProperty('NumberFormat', _createNumberFormat());

    // Intl.Collator
    intlObj.setProperty('Collator', _createCollator());

    // Intl.PluralRules
    intlObj.setProperty('PluralRules', _createPluralRules());

    // Intl.RelativeTimeFormat
    intlObj.setProperty('RelativeTimeFormat', _createRelativeTimeFormat());

    // Intl.ListFormat
    intlObj.setProperty('ListFormat', _createListFormat());

    // Intl.Segmenter
    intlObj.setProperty('Segmenter', _createSegmenter());

    // Intl.getCanonicalLocales
    intlObj.setProperty(
      'getCanonicalLocales',
      JSNativeFunction(
        functionName: 'getCanonicalLocales',
        nativeImpl: (args) {
          if (args.isEmpty) {
            return JSArray([]);
          }
          final input = args[0];
          final locales = <JSValue>[];

          if (input is JSArray) {
            for (final locale in input.elements) {
              locales.add(JSString(_canonicalizeLocale(locale.toString())));
            }
          } else {
            locales.add(JSString(_canonicalizeLocale(input.toString())));
          }

          return JSArray(locales);
        },
      ),
    );

    // Intl.supportedValuesOf
    intlObj.setProperty(
      'supportedValuesOf',
      JSNativeFunction(
        functionName: 'supportedValuesOf',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSRangeError('key is required');
          }
          final key = args[0].toString();
          return _getSupportedValues(key);
        },
      ),
    );

    return intlObj;
  }

  /// Canonicalize a locale string
  static String _canonicalizeLocale(String locale) {
    // Basic canonicalization: lowercase language, uppercase region
    final parts = locale.split(RegExp(r'[-_]'));
    if (parts.isEmpty) return locale;

    final result = <String>[];
    result.add(parts[0].toLowerCase()); // language

    if (parts.length > 1) {
      for (int i = 1; i < parts.length; i++) {
        final part = parts[i];
        if (part.length == 2) {
          result.add(part.toUpperCase()); // region
        } else if (part.length == 4) {
          result.add(
            part[0].toUpperCase() + part.substring(1).toLowerCase(),
          ); // script
        } else {
          result.add(part.toLowerCase());
        }
      }
    }

    return result.join('-');
  }

  /// Get supported values for a key
  static JSArray _getSupportedValues(String key) {
    final values = <JSValue>[];
    switch (key) {
      case 'calendar':
        values.addAll(
          [
            'buddhist',
            'chinese',
            'coptic',
            'dangi',
            'ethiopic',
            'gregory',
            'hebrew',
            'indian',
            'islamic',
            'iso8601',
            'japanese',
            'persian',
            'roc',
          ].map((v) => JSString(v)),
        );
        break;
      case 'collation':
        values.addAll(
          [
            'big5han',
            'compat',
            'dict',
            'emoji',
            'eor',
            'gb2312',
            'phonebk',
            'phonetic',
            'pinyin',
            'reformed',
            'search',
            'searchjl',
            'standard',
            'stroke',
            'trad',
            'unihan',
            'zhuyin',
          ].map((v) => JSString(v)),
        );
        break;
      case 'currency':
        values.addAll(
          [
            'AED',
            'AFN',
            'ALL',
            'AMD',
            'ANG',
            'AOA',
            'ARS',
            'AUD',
            'AWG',
            'AZN',
            'BAM',
            'BBD',
            'BDT',
            'BGN',
            'BHD',
            'BIF',
            'BMD',
            'BND',
            'BOB',
            'BRL',
            'BSD',
            'BTN',
            'BWP',
            'BYN',
            'BZD',
            'CAD',
            'CDF',
            'CHF',
            'CLP',
            'CNY',
            'COP',
            'CRC',
            'CUC',
            'CUP',
            'CVE',
            'CZK',
            'DJF',
            'DKK',
            'DOP',
            'DZD',
            'EGP',
            'ERN',
            'ETB',
            'EUR',
            'FJD',
            'FKP',
            'GBP',
            'GEL',
            'GHS',
            'GIP',
            'GMD',
            'GNF',
            'GTQ',
            'GYD',
            'HKD',
            'HNL',
            'HRK',
            'HTG',
            'HUF',
            'IDR',
            'ILS',
            'INR',
            'IQD',
            'IRR',
            'ISK',
            'JMD',
            'JOD',
            'JPY',
            'KES',
            'KGS',
            'KHR',
            'KMF',
            'KPW',
            'KRW',
            'KWD',
            'KYD',
            'KZT',
            'LAK',
            'LBP',
            'LKR',
            'LRD',
            'LSL',
            'LYD',
            'MAD',
            'MDL',
            'MGA',
            'MKD',
            'MMK',
            'MNT',
            'MOP',
            'MRU',
            'MUR',
            'MVR',
            'MWK',
            'MXN',
            'MYR',
            'MZN',
            'NAD',
            'NGN',
            'NIO',
            'NOK',
            'NPR',
            'NZD',
            'OMR',
            'PAB',
            'PEN',
            'PGK',
            'PHP',
            'PKR',
            'PLN',
            'PYG',
            'QAR',
            'RON',
            'RSD',
            'RUB',
            'RWF',
            'SAR',
            'SBD',
            'SCR',
            'SDG',
            'SEK',
            'SGD',
            'SHP',
            'SLL',
            'SOS',
            'SRD',
            'SSP',
            'STN',
            'SYP',
            'SZL',
            'THB',
            'TJS',
            'TMT',
            'TND',
            'TOP',
            'TRY',
            'TTD',
            'TWD',
            'TZS',
            'UAH',
            'UGX',
            'USD',
            'UYU',
            'UZS',
            'VES',
            'VND',
            'VUV',
            'WST',
            'XAF',
            'XCD',
            'XOF',
            'XPF',
            'YER',
            'ZAR',
            'ZMW',
            'ZWL',
          ].map((v) => JSString(v)),
        );
        break;
      case 'numberingSystem':
        values.addAll(
          [
            'adlm',
            'ahom',
            'arab',
            'arabext',
            'bali',
            'beng',
            'bhks',
            'brah',
            'cakm',
            'cham',
            'deva',
            'fullwide',
            'gong',
            'gonm',
            'gujr',
            'guru',
            'hanidec',
            'hmng',
            'java',
            'kali',
            'khmr',
            'knda',
            'lana',
            'lanatham',
            'laoo',
            'latn',
            'lepc',
            'limb',
            'mathbold',
            'mathdbl',
            'mathmono',
            'mathsanb',
            'mathsans',
            'mlym',
            'modi',
            'mong',
            'mroo',
            'mtei',
            'mymr',
            'mymrshan',
            'mymrtlng',
            'newa',
            'nkoo',
            'olck',
            'orya',
            'osma',
            'rohg',
            'saur',
            'shrd',
            'sind',
            'sinh',
            'sora',
            'sund',
            'takr',
            'talu',
            'tamldec',
            'telu',
            'thai',
            'tibt',
            'tirh',
            'vaii',
            'wara',
            'wcho',
          ].map((v) => JSString(v)),
        );
        break;
      case 'timeZone':
        values.addAll(
          [
            'Africa/Abidjan',
            'Africa/Cairo',
            'Africa/Johannesburg',
            'Africa/Lagos',
            'America/Argentina/Buenos_Aires',
            'America/Chicago',
            'America/Denver',
            'America/Los_Angeles',
            'America/Mexico_City',
            'America/New_York',
            'America/Sao_Paulo',
            'America/Toronto',
            'Asia/Bangkok',
            'Asia/Dubai',
            'Asia/Hong_Kong',
            'Asia/Jakarta',
            'Asia/Kolkata',
            'Asia/Seoul',
            'Asia/Shanghai',
            'Asia/Singapore',
            'Asia/Tokyo',
            'Australia/Melbourne',
            'Australia/Sydney',
            'Europe/Amsterdam',
            'Europe/Berlin',
            'Europe/Istanbul',
            'Europe/London',
            'Europe/Madrid',
            'Europe/Moscow',
            'Europe/Paris',
            'Europe/Rome',
            'Pacific/Auckland',
            'Pacific/Honolulu',
            'UTC',
          ].map((v) => JSString(v)),
        );
        break;
      case 'unit':
        values.addAll(
          [
            'acre',
            'bit',
            'byte',
            'celsius',
            'centimeter',
            'day',
            'degree',
            'fahrenheit',
            'fluid-ounce',
            'foot',
            'gallon',
            'gigabit',
            'gigabyte',
            'gram',
            'hectare',
            'hour',
            'inch',
            'kilobit',
            'kilobyte',
            'kilogram',
            'kilometer',
            'liter',
            'megabit',
            'megabyte',
            'meter',
            'mile',
            'mile-scandinavian',
            'milliliter',
            'millimeter',
            'millisecond',
            'minute',
            'month',
            'ounce',
            'percent',
            'petabyte',
            'pound',
            'second',
            'stone',
            'terabit',
            'terabyte',
            'week',
            'yard',
            'year',
          ].map((v) => JSString(v)),
        );
        break;
      default:
        throw JSRangeError('Invalid key: $key');
    }
    return JSArray(values);
  }

  // ==================== DateTimeFormat ====================

  static JSNativeFunction _createDateTimeFormat() {
    return JSNativeFunction(
      functionName: 'DateTimeFormat',
      nativeImpl: (args) {
        final locale = args.isNotEmpty ? args[0].toString() : 'en';
        final options = args.length > 1 && args[1] is JSObject
            ? args[1] as JSObject
            : JSObject();

        return _DateTimeFormatInstance(locale, options);
      },
      expectedArgs: 0,
      isConstructor: true, // Intl.DateTimeFormat is a constructor
    );
  }

  // ==================== NumberFormat ====================

  static JSNativeFunction _createNumberFormat() {
    return JSNativeFunction(
      functionName: 'NumberFormat',
      nativeImpl: (args) {
        final locale = args.isNotEmpty ? args[0].toString() : 'en';
        final options = args.length > 1 && args[1] is JSObject
            ? args[1] as JSObject
            : JSObject();

        return _NumberFormatInstance(locale, options);
      },
      expectedArgs: 0,
      isConstructor: true, // Intl.NumberFormat is a constructor
    );
  }

  // ==================== Collator ====================

  static JSNativeFunction _createCollator() {
    return JSNativeFunction(
      functionName: 'Collator',
      nativeImpl: (args) {
        final locale = args.isNotEmpty ? args[0].toString() : 'en';
        final options = args.length > 1 && args[1] is JSObject
            ? args[1] as JSObject
            : JSObject();

        return _CollatorInstance(locale, options);
      },
      expectedArgs: 0,
      isConstructor: true, // Intl.Collator is a constructor
    );
  }

  // ==================== PluralRules ====================

  static JSNativeFunction _createPluralRules() {
    return JSNativeFunction(
      functionName: 'PluralRules',
      nativeImpl: (args) {
        final locale = args.isNotEmpty ? args[0].toString() : 'en';
        final options = args.length > 1 && args[1] is JSObject
            ? args[1] as JSObject
            : JSObject();

        return _PluralRulesInstance(locale, options);
      },
      expectedArgs: 0,
      isConstructor: true, // Intl.PluralRules is a constructor
    );
  }

  // ==================== RelativeTimeFormat ====================

  static JSNativeFunction _createRelativeTimeFormat() {
    return JSNativeFunction(
      functionName: 'RelativeTimeFormat',
      nativeImpl: (args) {
        final locale = args.isNotEmpty ? args[0].toString() : 'en';
        final options = args.length > 1 && args[1] is JSObject
            ? args[1] as JSObject
            : JSObject();

        return _RelativeTimeFormatInstance(locale, options);
      },
      expectedArgs: 0,
      isConstructor: true, // Intl.RelativeTimeFormat is a constructor
    );
  }

  // ==================== ListFormat ====================

  static JSNativeFunction _createListFormat() {
    return JSNativeFunction(
      functionName: 'ListFormat',
      nativeImpl: (args) {
        final locale = args.isNotEmpty ? args[0].toString() : 'en';
        final options = args.length > 1 && args[1] is JSObject
            ? args[1] as JSObject
            : JSObject();

        return _ListFormatInstance(locale, options);
      },
      expectedArgs: 0,
      isConstructor: true, // Intl.ListFormat is a constructor
    );
  }

  // ==================== Segmenter ====================

  static JSNativeFunction _createSegmenter() {
    return JSNativeFunction(
      functionName: 'Segmenter',
      nativeImpl: (args) {
        final locale = args.isNotEmpty ? args[0].toString() : 'en';
        final options = args.length > 1 && args[1] is JSObject
            ? args[1] as JSObject
            : JSObject();

        return _SegmenterInstance(locale, options);
      },
      expectedArgs: 0,
      isConstructor: true, // Intl.Segmenter is a constructor
    );
  }
}

// ==================== DateTimeFormat Instance ====================

class _DateTimeFormatInstance extends JSObject {
  final String locale;
  final JSObject options;
  late final intl.DateFormat _formatter;

  _DateTimeFormatInstance(this.locale, this.options) {
    _initFormatter();
    _setupMethods();
  }

  void _initFormatter() {
    final dateStyle = _getStringOption(options, 'dateStyle');
    final timeStyle = _getStringOption(options, 'timeStyle');
    final hour12 = options.getProperty('hour12');
    final weekday = _getStringOption(options, 'weekday');
    final year = _getStringOption(options, 'year');
    final month = _getStringOption(options, 'month');
    final day = _getStringOption(options, 'day');
    final hour = _getStringOption(options, 'hour');
    final minute = _getStringOption(options, 'minute');
    final second = _getStringOption(options, 'second');

    String pattern = '';

    // Build pattern from options
    if (dateStyle != null || timeStyle != null) {
      // Use predefined styles
      if (dateStyle == 'full') {
        pattern = 'EEEE, MMMM d, y';
      } else if (dateStyle == 'long') {
        pattern = 'MMMM d, y';
      } else if (dateStyle == 'medium') {
        pattern = 'MMM d, y';
      } else if (dateStyle == 'short') {
        pattern = 'M/d/yy';
      }

      if (timeStyle != null) {
        if (pattern.isNotEmpty) pattern += ' ';
        if (timeStyle == 'full') {
          pattern += 'h:mm:ss a zzzz';
        } else if (timeStyle == 'long') {
          pattern += 'h:mm:ss a z';
        } else if (timeStyle == 'medium') {
          pattern += 'h:mm:ss a';
        } else if (timeStyle == 'short') {
          pattern += 'h:mm a';
        }
      }
    } else {
      // Build from individual components
      final parts = <String>[];

      if (weekday != null) {
        if (weekday == 'long') {
          parts.add('EEEE');
        } else if (weekday == 'short') {
          parts.add('EEE');
        } else if (weekday == 'narrow') {
          parts.add('EEEEE');
        }
      }

      if (year != null) {
        if (year == 'numeric') {
          parts.add('y');
        } else if (year == '2-digit') {
          parts.add('yy');
        }
      }

      if (month != null) {
        if (month == 'numeric') {
          parts.add('M');
        } else if (month == '2-digit') {
          parts.add('MM');
        } else if (month == 'long') {
          parts.add('MMMM');
        } else if (month == 'short') {
          parts.add('MMM');
        } else if (month == 'narrow') {
          parts.add('MMMMM');
        }
      }

      if (day != null) {
        if (day == 'numeric') {
          parts.add('d');
        } else if (day == '2-digit') {
          parts.add('dd');
        }
      }

      if (hour != null) {
        final use12 = hour12.isUndefined ? true : hour12.toBoolean();
        if (hour == 'numeric') {
          parts.add(use12 ? 'h' : 'H');
        } else if (hour == '2-digit') {
          parts.add(use12 ? 'hh' : 'HH');
        }
      }

      if (minute != null) {
        if (minute == 'numeric' || minute == '2-digit') {
          parts.add('mm');
        }
      }

      if (second != null) {
        if (second == 'numeric' || second == '2-digit') {
          parts.add('ss');
        }
      }

      if (hour != null && (hour12.isUndefined || hour12.toBoolean())) {
        parts.add('a');
      }

      pattern = parts.join(' ');
    }

    if (pattern.isEmpty) {
      pattern = 'M/d/y';
    }

    try {
      _formatter = intl.DateFormat(pattern, _normalizeLocale(locale));
    } catch (_) {
      _formatter = intl.DateFormat(pattern, 'en');
    }
  }

  String _normalizeLocale(String locale) {
    return locale.replaceAll('-', '_');
  }

  void _setupMethods() {
    // format(date)
    setProperty(
      'format',
      JSNativeFunction(
        functionName: 'format',
        nativeImpl: (args) {
          if (args.isEmpty) {
            return JSString(_formatter.format(DateTime.now()));
          }
          final date = _toDateTime(args[0]);
          return JSString(_formatter.format(date));
        },
      ),
    );

    // formatToParts(date)
    setProperty(
      'formatToParts',
      JSNativeFunction(
        functionName: 'formatToParts',
        nativeImpl: (args) {
          final date = args.isEmpty ? DateTime.now() : _toDateTime(args[0]);
          return _formatToParts(date);
        },
      ),
    );

    // formatRange(startDate, endDate)
    setProperty(
      'formatRange',
      JSNativeFunction(
        functionName: 'formatRange',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError('formatRange requires two arguments');
          }
          final start = _toDateTime(args[0]);
          final end = _toDateTime(args[1]);
          return JSString(
            '${_formatter.format(start)} – ${_formatter.format(end)}',
          );
        },
      ),
    );

    // resolvedOptions()
    setProperty(
      'resolvedOptions',
      JSNativeFunction(
        functionName: 'resolvedOptions',
        nativeImpl: (args) {
          final resolved = JSObject();
          resolved.setProperty('locale', JSString(locale));
          resolved.setProperty('calendar', JSString('gregory'));
          resolved.setProperty('numberingSystem', JSString('latn'));
          resolved.setProperty('timeZone', JSString('UTC'));
          return resolved;
        },
      ),
    );
  }

  DateTime _toDateTime(JSValue value) {
    if (value is JSDate) {
      // Use toNumber() to get milliseconds, then convert to DateTime
      return DateTime.fromMillisecondsSinceEpoch(value.toNumber().toInt());
    } else if (value.isNumber) {
      return DateTime.fromMillisecondsSinceEpoch(value.toNumber().toInt());
    } else {
      return DateTime.parse(value.toString());
    }
  }

  JSArray _formatToParts(DateTime date) {
    final formatted = _formatter.format(date);
    final parts = <JSValue>[];

    // Ifmple implementation - split by spaces and punctuation
    final regex = RegExp(r'(\d+|[a-zA-Z]+|[^\w\s])');
    final matches = regex.allMatches(formatted);

    for (final match in matches) {
      final value = match.group(0)!;
      String type;

      if (RegExp(r'^\d+$').hasMatch(value)) {
        // Determine type based on value
        final num = int.parse(value);
        if (num > 31) {
          type = 'year';
        } else if (num > 12) {
          type = 'day';
        } else {
          type = 'month';
        }
      } else if (RegExp(r'^[a-zA-Z]+$').hasMatch(value)) {
        if (['AM', 'PM', 'am', 'pm'].contains(value)) {
          type = 'dayPeriod';
        } else if (value.length <= 3) {
          type = 'month';
        } else {
          type = 'weekday';
        }
      } else {
        type = 'literal';
      }

      final part = JSObject();
      part.setProperty('type', JSString(type));
      part.setProperty('value', JSString(value));
      parts.add(part);
    }

    return JSArray(parts);
  }

  @override
  String toString() => '[object Intl.DateTimeFormat]';
}

// ==================== NumberFormat Instance ====================

class _NumberFormatInstance extends JSObject {
  final String locale;
  final JSObject options;
  late final intl.NumberFormat _formatter;
  late final String _style;

  _NumberFormatInstance(this.locale, this.options) {
    _initFormatter();
    _setupMethods();
  }

  void _initFormatter() {
    _style = _getStringOption(options, 'style') ?? 'decimal';
    final currency = _getStringOption(options, 'currency');
    final currencyDisplay =
        _getStringOption(options, 'currencyDisplay') ?? 'symbol';
    final minimumFractionDigits = _getIntOption(
      options,
      'minimumFractionDigits',
    );
    final maximumFractionDigits = _getIntOption(
      options,
      'maximumFractionDigits',
    );
    // useGrouping option - not directly supported by intl package, kept for resolvedOptions
    final notation = _getStringOption(options, 'notation') ?? 'standard';
    final unit = _getStringOption(options, 'unit');

    final normalizedLocale = locale.replaceAll('-', '_');

    try {
      if (_style == 'currency' && currency != null) {
        if (currencyDisplay == 'code') {
          _formatter = intl.NumberFormat.currency(
            locale: normalizedLocale,
            name: currency,
            symbol: currency,
            decimalDigits: minimumFractionDigits,
          );
        } else {
          _formatter = intl.NumberFormat.simpleCurrency(
            locale: normalizedLocale,
            name: currency,
            decimalDigits: minimumFractionDigits,
          );
        }
      } else if (_style == 'percent') {
        _formatter = intl.NumberFormat.percentPattern(normalizedLocale);
      } else if (_style == 'unit' && unit != null) {
        _formatter = intl.NumberFormat.decimalPattern(normalizedLocale);
      } else if (notation == 'compact') {
        _formatter = intl.NumberFormat.compact(locale: normalizedLocale);
      } else if (notation == 'scientific') {
        _formatter = intl.NumberFormat.scientificPattern(normalizedLocale);
      } else {
        _formatter = intl.NumberFormat.decimalPatternDigits(
          locale: normalizedLocale,
          decimalDigits: maximumFractionDigits ?? 3,
        );
      }
    } catch (_) {
      _formatter = intl.NumberFormat.decimalPattern('en');
    }
  }

  void _setupMethods() {
    // format(number)
    setProperty(
      'format',
      JSNativeFunction(
        functionName: 'format',
        nativeImpl: (args) {
          if (args.isEmpty) {
            return JSString('NaN');
          }
          final num = args[0].toNumber();
          if (num.isNaN) return JSString('NaN');
          if (num.isInfinite) return JSString(num > 0 ? '∞' : '-∞');
          return JSString(_formatter.format(num));
        },
      ),
    );

    // formatToParts(number)
    setProperty(
      'formatToParts',
      JSNativeFunction(
        functionName: 'formatToParts',
        nativeImpl: (args) {
          if (args.isEmpty) {
            return JSArray([]);
          }
          final num = args[0].toNumber();
          return _formatToParts(num);
        },
      ),
    );

    // formatRange(start, end)
    setProperty(
      'formatRange',
      JSNativeFunction(
        functionName: 'formatRange',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError('formatRange requires two arguments');
          }
          final start = args[0].toNumber();
          final end = args[1].toNumber();
          return JSString(
            '${_formatter.format(start)}–${_formatter.format(end)}',
          );
        },
      ),
    );

    // resolvedOptions()
    setProperty(
      'resolvedOptions',
      JSNativeFunction(
        functionName: 'resolvedOptions',
        nativeImpl: (args) {
          final resolved = JSObject();
          resolved.setProperty('locale', JSString(locale));
          resolved.setProperty('numberingSystem', JSString('latn'));
          resolved.setProperty('style', JSString(_style));
          resolved.setProperty('useGrouping', JSBoolean(true));
          return resolved;
        },
      ),
    );
  }

  JSArray _formatToParts(double num) {
    final formatted = _formatter.format(num);
    final parts = <JSValue>[];

    // Parse the formatted string into parts
    final regex = RegExp(r'(\d+)|([.,])|([^\d.,]+)');
    final matches = regex.allMatches(formatted);

    bool seenDecimal = false;
    for (final match in matches) {
      final value = match.group(0)!;
      String type;

      if (RegExp(r'^\d+$').hasMatch(value)) {
        type = seenDecimal ? 'fraction' : 'integer';
      } else if (value == '.' || value == ',') {
        if (formatted.indexOf(value) == match.start &&
            formatted.contains(RegExp(r'\d.*[.,].*\d'))) {
          type = 'group';
        } else {
          type = 'decimal';
          seenDecimal = true;
        }
      } else if (value.trim().isEmpty) {
        type = 'literal';
      } else {
        type = _style == 'currency' ? 'currency' : 'literal';
      }

      final part = JSObject();
      part.setProperty('type', JSString(type));
      part.setProperty('value', JSString(value));
      parts.add(part);
    }

    return JSArray(parts);
  }

  @override
  String toString() => '[object Intl.NumberFormat]';
}

// ==================== Collator Instance ====================

class _CollatorInstance extends JSObject {
  final String locale;
  final JSObject options;
  late final String _sensitivity;
  late final bool _numeric;
  late final String _usage;

  _CollatorInstance(this.locale, this.options) {
    _sensitivity = _getStringOption(options, 'sensitivity') ?? 'variant';
    _numeric = _getBoolOption(options, 'numeric', false);
    _usage = _getStringOption(options, 'usage') ?? 'sort';
    _setupMethods();
  }

  void _setupMethods() {
    // compare(string1, string2)
    setProperty(
      'compare',
      JSNativeFunction(
        functionName: 'compare',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError('compare requires two arguments');
          }
          final str1 = args[0].toString();
          final str2 = args[1].toString();
          return JSNumber(_compare(str1, str2).toDouble());
        },
      ),
    );

    // resolvedOptions()
    setProperty(
      'resolvedOptions',
      JSNativeFunction(
        functionName: 'resolvedOptions',
        nativeImpl: (args) {
          final resolved = JSObject();
          resolved.setProperty('locale', JSString(locale));
          resolved.setProperty('usage', JSString(_usage));
          resolved.setProperty('sensitivity', JSString(_sensitivity));
          resolved.setProperty('ignorePunctuation', JSBoolean(false));
          resolved.setProperty('collation', JSString('default'));
          resolved.setProperty('numeric', JSBoolean(_numeric));
          resolved.setProperty('caseFirst', JSString('false'));
          return resolved;
        },
      ),
    );
  }

  int _compare(String str1, String str2) {
    String s1 = str1;
    String s2 = str2;

    switch (_sensitivity) {
      case 'base':
        s1 = s1.toLowerCase();
        s2 = s2.toLowerCase();
        // Remove diacritics (basic implementation)
        s1 = _removeDiacritics(s1);
        s2 = _removeDiacritics(s2);
        break;
      case 'accent':
        s1 = s1.toLowerCase();
        s2 = s2.toLowerCase();
        break;
      case 'case':
        s1 = _removeDiacritics(s1);
        s2 = _removeDiacritics(s2);
        break;
      // 'variant' - compare as-is
    }

    if (_numeric) {
      return _numericCompare(s1, s2);
    }

    return s1.compareTo(s2);
  }

  String _removeDiacritics(String str) {
    const diacritics = 'aáaãaåaeceeeeìíiiñòóoõoøuúuuýÿ';
    const replacements = 'aaaaaaaceeeeiiiinooooooouuuuyy';

    var result = str;
    for (int i = 0; i < diacritics.length; i++) {
      result = result.replaceAll(diacritics[i], replacements[i]);
    }
    return result;
  }

  int _numericCompare(String str1, String str2) {
    final regex = RegExp(r'(\d+|\D+)');
    final parts1 = regex.allMatches(str1).map((m) => m.group(0)!).toList();
    final parts2 = regex.allMatches(str2).map((m) => m.group(0)!).toList();

    final maxLen = parts1.length > parts2.length
        ? parts1.length
        : parts2.length;

    for (int i = 0; i < maxLen; i++) {
      if (i >= parts1.length) return -1;
      if (i >= parts2.length) return 1;

      final p1 = parts1[i];
      final p2 = parts2[i];

      final n1 = int.tryParse(p1);
      final n2 = int.tryParse(p2);

      int cmp;
      if (n1 != null && n2 != null) {
        cmp = n1.compareTo(n2);
      } else {
        cmp = p1.compareTo(p2);
      }

      if (cmp != 0) return cmp;
    }

    return 0;
  }

  @override
  String toString() => '[object Intl.Collator]';
}

// ==================== PluralRules Instance ====================

class _PluralRulesInstance extends JSObject {
  final String locale;
  final JSObject options;
  late final String _type;

  _PluralRulesInstance(this.locale, this.options) {
    _type = _getStringOption(options, 'type') ?? 'cardinal';
    _setupMethods();
  }

  void _setupMethods() {
    // select(number)
    setProperty(
      'select',
      JSNativeFunction(
        functionName: 'select',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSTypeError('select requires one argument');
          }
          final num = args[0].toNumber();
          return JSString(_selectPlural(num));
        },
      ),
    );

    // selectRange(start, end)
    setProperty(
      'selectRange',
      JSNativeFunction(
        functionName: 'selectRange',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError('selectRange requires two arguments');
          }
          // Ifmplified - return 'other' for ranges
          return JSString('other');
        },
      ),
    );

    // resolvedOptions()
    setProperty(
      'resolvedOptions',
      JSNativeFunction(
        functionName: 'resolvedOptions',
        nativeImpl: (args) {
          final resolved = JSObject();
          resolved.setProperty('locale', JSString(locale));
          resolved.setProperty('type', JSString(_type));
          resolved.setProperty(
            'pluralCategories',
            JSArray([
              JSString('zero'),
              JSString('one'),
              JSString('two'),
              JSString('few'),
              JSString('many'),
              JSString('other'),
            ]),
          );
          return resolved;
        },
      ),
    );
  }

  String _selectPlural(double num) {
    if (_type == 'ordinal') {
      return _selectOrdinal(num.toInt());
    }
    return _selectCardinal(num);
  }

  String _selectCardinal(double num) {
    // English rules (simplified)
    if (num == 0) return 'zero';
    if (num == 1) return 'one';
    if (num == 2) return 'two';
    return 'other';
  }

  String _selectOrdinal(int num) {
    // English ordinal rules
    final mod10 = num % 10;
    final mod100 = num % 100;

    if (mod10 == 1 && mod100 != 11) return 'one';
    if (mod10 == 2 && mod100 != 12) return 'two';
    if (mod10 == 3 && mod100 != 13) return 'few';
    return 'other';
  }

  @override
  String toString() => '[object Intl.PluralRules]';
}

// ==================== RelativeTimeFormat Instance ====================

class _RelativeTimeFormatInstance extends JSObject {
  final String locale;
  final JSObject options;
  late final String _style;
  late final String _numeric;

  _RelativeTimeFormatInstance(this.locale, this.options) {
    _style = _getStringOption(options, 'style') ?? 'long';
    _numeric = _getStringOption(options, 'numeric') ?? 'always';
    _setupMethods();
  }

  void _setupMethods() {
    // format(value, unit)
    setProperty(
      'format',
      JSNativeFunction(
        functionName: 'format',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError('format requires two arguments');
          }
          final value = args[0].toNumber();
          final unit = args[1].toString();
          return JSString(_formatRelativeTime(value, unit));
        },
      ),
    );

    // formatToParts(value, unit)
    setProperty(
      'formatToParts',
      JSNativeFunction(
        functionName: 'formatToParts',
        nativeImpl: (args) {
          if (args.length < 2) {
            throw JSTypeError('formatToParts requires two arguments');
          }
          final value = args[0].toNumber();
          final unit = args[1].toString();
          return _formatToPartsRelative(value, unit);
        },
      ),
    );

    // resolvedOptions()
    setProperty(
      'resolvedOptions',
      JSNativeFunction(
        functionName: 'resolvedOptions',
        nativeImpl: (args) {
          final resolved = JSObject();
          resolved.setProperty('locale', JSString(locale));
          resolved.setProperty('style', JSString(_style));
          resolved.setProperty('numeric', JSString(_numeric));
          resolved.setProperty('numberingSystem', JSString('latn'));
          return resolved;
        },
      ),
    );
  }

  String _formatRelativeTime(double value, String unit) {
    final absValue = value.abs();
    final intValue = absValue.toInt();

    // Handle "auto" numeric option
    if (_numeric == 'auto' && intValue == 1) {
      if (value < 0) {
        switch (unit) {
          case 'day':
          case 'days':
            return 'yesterday';
          case 'week':
          case 'weeks':
            return 'last week';
          case 'month':
          case 'months':
            return 'last month';
          case 'year':
          case 'years':
            return 'last year';
        }
      } else {
        switch (unit) {
          case 'day':
          case 'days':
            return 'tomorrow';
          case 'week':
          case 'weeks':
            return 'next week';
          case 'month':
          case 'months':
            return 'next month';
          case 'year':
          case 'years':
            return 'next year';
        }
      }
    }

    String unitStr;
    switch (_style) {
      case 'short':
        unitStr = _getShortUnit(unit, intValue);
        break;
      case 'narrow':
        unitStr = _getNarrowUnit(unit);
        break;
      default:
        unitStr = _getLongUnit(unit, intValue);
    }

    if (value < 0) {
      return '$intValue $unitStr ago';
    } else {
      return 'in $intValue $unitStr';
    }
  }

  String _getLongUnit(String unit, int value) {
    final normalized = unit.replaceAll(RegExp(r's$'), '');
    return value == 1 ? normalized : '${normalized}s';
  }

  String _getShortUnit(String unit, int value) {
    switch (unit.replaceAll(RegExp(r's$'), '')) {
      case 'second':
        return 'sec.';
      case 'minute':
        return 'min.';
      case 'hour':
        return 'hr.';
      case 'day':
        return value == 1 ? 'day' : 'days';
      case 'week':
        return 'wk.';
      case 'month':
        return 'mo.';
      case 'year':
        return 'yr.';
      default:
        return unit;
    }
  }

  String _getNarrowUnit(String unit) {
    switch (unit.replaceAll(RegExp(r's$'), '')) {
      case 'second':
        return 's';
      case 'minute':
        return 'm';
      case 'hour':
        return 'h';
      case 'day':
        return 'd';
      case 'week':
        return 'w';
      case 'month':
        return 'mo';
      case 'year':
        return 'y';
      default:
        return unit;
    }
  }

  JSArray _formatToPartsRelative(double value, String unit) {
    final formatted = _formatRelativeTime(value, unit);
    final parts = <JSValue>[];

    // Split into parts
    final regex = RegExp(r'(\d+)|([a-zA-Z.]+)|(\s+)');
    for (final match in regex.allMatches(formatted)) {
      final val = match.group(0)!;
      String type;

      if (RegExp(r'^\d+$').hasMatch(val)) {
        type = 'integer';
      } else if (val.trim().isEmpty) {
        type = 'literal';
      } else if (['ago', 'in'].contains(val)) {
        type = 'literal';
      } else {
        type = 'unit';
      }

      final part = JSObject();
      part.setProperty('type', JSString(type));
      part.setProperty('value', JSString(val));
      if (type == 'unit') {
        part.setProperty('unit', JSString(unit));
      }
      parts.add(part);
    }

    return JSArray(parts);
  }

  @override
  String toString() => '[object Intl.RelativeTimeFormat]';
}

// ==================== ListFormat Instance ====================

class _ListFormatInstance extends JSObject {
  final String locale;
  final JSObject options;
  late final String _style;
  late final String _type;

  _ListFormatInstance(this.locale, this.options) {
    _style = _getStringOption(options, 'style') ?? 'long';
    _type = _getStringOption(options, 'type') ?? 'conjunction';
    _setupMethods();
  }

  void _setupMethods() {
    // format(list)
    setProperty(
      'format',
      JSNativeFunction(
        functionName: 'format',
        nativeImpl: (args) {
          if (args.isEmpty) {
            return JSString('');
          }
          final list = _toStringList(args[0]);
          return JSString(_formatList(list));
        },
      ),
    );

    // formatToParts(list)
    setProperty(
      'formatToParts',
      JSNativeFunction(
        functionName: 'formatToParts',
        nativeImpl: (args) {
          if (args.isEmpty) {
            return JSArray([]);
          }
          final list = _toStringList(args[0]);
          return _formatToParts(list);
        },
      ),
    );

    // resolvedOptions()
    setProperty(
      'resolvedOptions',
      JSNativeFunction(
        functionName: 'resolvedOptions',
        nativeImpl: (args) {
          final resolved = JSObject();
          resolved.setProperty('locale', JSString(locale));
          resolved.setProperty('type', JSString(_type));
          resolved.setProperty('style', JSString(_style));
          return resolved;
        },
      ),
    );
  }

  List<String> _toStringList(JSValue value) {
    if (value is JSArray) {
      return value.elements.map((e) => e.toString()).toList();
    }
    return [value.toString()];
  }

  String _formatList(List<String> list) {
    if (list.isEmpty) return '';
    if (list.length == 1) return list[0];

    String conjunction;
    switch (_type) {
      case 'disjunction':
        conjunction = _style == 'short' ? ' or ' : ' or ';
        break;
      case 'unit':
        conjunction = _style == 'narrow' ? ' ' : ', ';
        break;
      default: // conjunction
        conjunction = _style == 'short' ? ', & ' : ', and ';
    }

    if (list.length == 2) {
      final simpleConj = _type == 'disjunction' ? ' or ' : ' and ';
      return '${list[0]}$simpleConj${list[1]}';
    }

    final allButLast = list.sublist(0, list.length - 1);
    final last = list.last;
    return '${allButLast.join(', ')}$conjunction$last';
  }

  JSArray _formatToParts(List<String> list) {
    final parts = <JSValue>[];

    for (int i = 0; i < list.length; i++) {
      final element = JSObject();
      element.setProperty('type', JSString('element'));
      element.setProperty('value', JSString(list[i]));
      parts.add(element);

      if (i < list.length - 1) {
        final literal = JSObject();
        literal.setProperty('type', JSString('literal'));
        if (i == list.length - 2) {
          final conj = _type == 'disjunction' ? ' or ' : ' and ';
          literal.setProperty(
            'value',
            JSString(
              list.length == 2 ? conj : ', $conj'.replaceFirst(', ', ''),
            ),
          );
        } else {
          literal.setProperty('value', JSString(', '));
        }
        parts.add(literal);
      }
    }

    return JSArray(parts);
  }

  @override
  String toString() => '[object Intl.ListFormat]';
}

// ==================== Segmenter Instance ====================

class _SegmenterInstance extends JSObject {
  final String locale;
  final JSObject options;
  late final String _granularity;

  _SegmenterInstance(this.locale, this.options) {
    _granularity = _getStringOption(options, 'granularity') ?? 'grapheme';
    _setupMethods();
  }

  void _setupMethods() {
    // segment(string)
    setProperty(
      'segment',
      JSNativeFunction(
        functionName: 'segment',
        nativeImpl: (args) {
          if (args.isEmpty) {
            throw JSTypeError('segment requires one argument');
          }
          final str = args[0].toString();
          return _createSegments(str);
        },
      ),
    );

    // resolvedOptions()
    setProperty(
      'resolvedOptions',
      JSNativeFunction(
        functionName: 'resolvedOptions',
        nativeImpl: (args) {
          final resolved = JSObject();
          resolved.setProperty('locale', JSString(locale));
          resolved.setProperty('granularity', JSString(_granularity));
          return resolved;
        },
      ),
    );
  }

  JSObject _createSegments(String str) {
    final segments = JSObject();
    final segmentList = _segmentString(str);

    // Make it iterable
    segments.setProperty(
      JSSymbol.iterator.toString(),
      JSNativeFunction(
        functionName: '[Symbol.iterator]',
        nativeImpl: (args) {
          int index = 0;
          final iterator = JSObject();

          iterator.setProperty(
            'next',
            JSNativeFunction(
              functionName: 'next',
              nativeImpl: (args) {
                final result = JSObject();
                if (index < segmentList.length) {
                  result.setProperty('value', segmentList[index]);
                  result.setProperty('done', JSBoolean(false));
                  index++;
                } else {
                  result.setProperty('value', JSValueFactory.undefined());
                  result.setProperty('done', JSBoolean(true));
                }
                return result;
              },
            ),
          );

          return iterator;
        },
      ),
    );

    // containing(index)
    segments.setProperty(
      'containing',
      JSNativeFunction(
        functionName: 'containing',
        nativeImpl: (args) {
          if (args.isEmpty) {
            return JSValueFactory.undefined();
          }
          final index = args[0].toNumber().toInt();
          if (index < 0 || index >= str.length) {
            return JSValueFactory.undefined();
          }

          // Find the segment containing this index
          for (final seg in segmentList) {
            final segObj = seg as JSObject;
            final segIndex = segObj.getProperty('index').toNumber().toInt();
            final segment = segObj.getProperty('segment').toString();

            if (index >= segIndex && index < segIndex + segment.length) {
              return segObj;
            }
          }

          return JSValueFactory.undefined();
        },
      ),
    );

    return segments;
  }

  List<JSValue> _segmentString(String str) {
    final segments = <JSValue>[];

    switch (_granularity) {
      case 'word':
        final regex = RegExp(r'\b\w+\b|\s+|[^\w\s]+');
        for (final match in regex.allMatches(str)) {
          final segment = JSObject();
          segment.setProperty('segment', JSString(match.group(0)!));
          segment.setProperty('index', JSNumber(match.start.toDouble()));
          segment.setProperty('input', JSString(str));
          segment.setProperty(
            'isWordLike',
            JSBoolean(RegExp(r'^\w+$').hasMatch(match.group(0)!)),
          );
          segments.add(segment);
        }
        break;

      case 'sentence':
        final regex = RegExp(r'[^.!?]*[.!?]+\s*|[^.!?]+$');
        for (final match in regex.allMatches(str)) {
          if (match.group(0)!.isNotEmpty) {
            final segment = JSObject();
            segment.setProperty('segment', JSString(match.group(0)!));
            segment.setProperty('index', JSNumber(match.start.toDouble()));
            segment.setProperty('input', JSString(str));
            segments.add(segment);
          }
        }
        break;

      default: // grapheme
        // Use characters (grapheme clusters)
        int index = 0;
        for (final char in str.runes) {
          final segment = JSObject();
          segment.setProperty('segment', JSString(String.fromCharCode(char)));
          segment.setProperty('index', JSNumber(index.toDouble()));
          segment.setProperty('input', JSString(str));
          segments.add(segment);
          index += String.fromCharCode(char).length;
        }
    }

    return segments;
  }

  @override
  String toString() => '[object Intl.Segmenter]';
}
