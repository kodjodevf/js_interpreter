/// Date Object implementation for JavaScript
/// Provides complete Date functionality
library;

import 'js_value.dart';
import 'native_functions.dart';

const Map<String, int> _monthNumbers = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

const int _millisecondsPerSecondInt = 1000;
const int _millisecondsPerMinuteInt = 60 * _millisecondsPerSecondInt;
const int _millisecondsPerHourInt = 60 * _millisecondsPerMinuteInt;
const int _millisecondsPerDayInt = 24 * _millisecondsPerHourInt;

int? _toIntegerOrNull(JSValue value) {
  final number = value.toNumber();
  if (number.isNaN || number.isInfinite) {
    return null;
  }
  return number.truncate();
}

double? _toIntegerNumberOrNull(JSValue value) {
  final number = value.toNumber();
  if (number.isNaN || number.isInfinite) {
    return null;
  }
  return number.truncateToDouble();
}

int _floorDiv(int value, int divisor) {
  var quotient = value ~/ divisor;
  if ((value ^ divisor) < 0 && value % divisor != 0) {
    quotient -= 1;
  }
  return quotient;
}

int _daysFromCivil(int year, int month, int day) {
  var adjustedYear = year;
  if (month <= 2) {
    adjustedYear -= 1;
  }
  final era = adjustedYear >= 0
      ? adjustedYear ~/ 400
      : _floorDiv(adjustedYear - 399, 400);
  final yearOfEra = adjustedYear - era * 400;
  final monthPrime = month > 2 ? month - 3 : month + 9;
  final dayOfYear = ((153 * monthPrime) + 2) ~/ 5 + day - 1;
  final dayOfEra =
      yearOfEra * 365 + yearOfEra ~/ 4 - yearOfEra ~/ 100 + dayOfYear;
  return era * 146097 + dayOfEra - 719468;
}

double _timeClip(double time) {
  if (!time.isFinite || time.abs() > 8.64e15) {
    return double.nan;
  }
  if (time == 0) {
    return 0;
  }
  return time.truncateToDouble();
}

int _makeDay(int year, int month, int day) {
  final yearDelta = _floorDiv(month, 12);
  final normalizedYear = year + yearDelta;
  final normalizedMonth = month - yearDelta * 12;
  return _daysFromCivil(normalizedYear, normalizedMonth + 1, 1) + day - 1;
}

double _makeTime(
  double hour,
  double minute,
  double second,
  double millisecond,
) {
  return hour * _millisecondsPerHourInt.toDouble() +
      minute * _millisecondsPerMinuteInt.toDouble() +
      second * _millisecondsPerSecondInt.toDouble() +
      millisecond;
}

double _makeDate(double day, double time) {
  return day * _millisecondsPerDayInt.toDouble() + time;
}

double _dateUtcMilliseconds(
  double year,
  double month,
  double day,
  double hour,
  double minute,
  double second,
  double millisecond,
) {
  final normalizedYear = year >= 0 && year <= 99 ? year + 1900 : year;
  final dayValue = _makeDay(
    normalizedYear.toInt(),
    month.toInt(),
    day.toInt(),
  ).toDouble();
  final timeValue = _makeTime(hour, minute, second, millisecond);
  return _timeClip(_makeDate(dayValue, timeValue));
}

bool _matchesUtcComponents(
  DateTime value,
  int year,
  int month,
  int day,
  int hour,
  int minute,
  int second,
  int millisecond,
) {
  final utc = value.toUtc();
  return utc.year == year &&
      utc.month == month &&
      utc.day == day &&
      utc.hour == hour &&
      utc.minute == minute &&
      utc.second == second &&
      utc.millisecond == millisecond;
}

bool _matchesLocalComponents(
  DateTime value,
  int year,
  int month,
  int day,
  int hour,
  int minute,
  int second,
  int millisecond,
) {
  return value.year == year &&
      value.month == month &&
      value.day == day &&
      value.hour == hour &&
      value.minute == minute &&
      value.second == second &&
      value.millisecond == millisecond;
}

int _parseMilliseconds(String? fraction) {
  if (fraction == null || fraction.isEmpty) {
    return 0;
  }
  final normalized = fraction.length >= 3
      ? fraction.substring(0, 3)
      : fraction.padRight(3, '0');
  return int.parse(normalized);
}

DateTime? _parseIsoLikeDate(String input) {
  final match = RegExp(
    r'^([+-]?\d{4,6})(?:-(\d{2})(?:-(\d{2}))?)?(?:T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?(Z|[+-]\d{2}:\d{2})?)?$',
  ).firstMatch(input);
  if (match == null) {
    return null;
  }

  final year = int.parse(match.group(1)!);
  final month = match.group(2) != null ? int.parse(match.group(2)!) : 1;
  final day = match.group(3) != null ? int.parse(match.group(3)!) : 1;
  final hasTime = match.group(4) != null;
  final hour = hasTime ? int.parse(match.group(4)!) : 0;
  final minute = hasTime ? int.parse(match.group(5)!) : 0;
  final second = match.group(6) != null ? int.parse(match.group(6)!) : 0;
  final millisecond = _parseMilliseconds(match.group(7));
  final timezone = match.group(8);

  if (month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59) {
    return null;
  }

  if (!hasTime) {
    final utcValue = DateTime.utc(year, month, day);
    if (!_matchesUtcComponents(utcValue, year, month, day, 0, 0, 0, 0)) {
      return null;
    }
    return utcValue;
  }

  if (timezone == null || timezone.isEmpty) {
    final localValue = DateTime(
      year,
      month,
      day,
      hour,
      minute,
      second,
      millisecond,
    );
    if (!_matchesLocalComponents(
      localValue,
      year,
      month,
      day,
      hour,
      minute,
      second,
      millisecond,
    )) {
      return null;
    }
    return localValue;
  }

  final utcValue = DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second,
    millisecond,
  );
  if (!_matchesUtcComponents(
    utcValue,
    year,
    month,
    day,
    hour,
    minute,
    second,
    millisecond,
  )) {
    return null;
  }
  if (timezone == 'Z') {
    return utcValue;
  }

  final sign = timezone.startsWith('-') ? -1 : 1;
  final offsetHour = int.parse(timezone.substring(1, 3));
  final offsetMinute = int.parse(timezone.substring(4, 6));
  if (offsetHour > 23 || offsetMinute > 59) {
    return null;
  }
  final offset = Duration(hours: offsetHour, minutes: offsetMinute);
  return sign > 0 ? utcValue.subtract(offset) : utcValue.add(offset);
}

DateTime? _parseLegacyDate(String input) {
  final match = RegExp(
    r'^(?:[A-Za-z]{3}\s+)?([A-Za-z]{3})\s+(\d{1,2})\s+(\d{4})(?:\s+(\d{2}):(\d{2})(?::(\d{2}))?)?(?:\s+GMT([+-]\d{4}))?$',
  ).firstMatch(input);
  if (match == null) {
    return null;
  }

  final month = _monthNumbers[match.group(1)!.toLowerCase()];
  if (month == null) {
    return null;
  }
  final day = int.parse(match.group(2)!);
  final year = int.parse(match.group(3)!);
  final hour = match.group(4) != null ? int.parse(match.group(4)!) : 0;
  final minute = match.group(5) != null ? int.parse(match.group(5)!) : 0;
  final second = match.group(6) != null ? int.parse(match.group(6)!) : 0;
  if (hour > 23 || minute > 59 || second > 59) {
    return null;
  }

  final offset = match.group(7);
  if (offset == null) {
    final localValue = DateTime(year, month, day, hour, minute, second);
    if (!_matchesLocalComponents(
      localValue,
      year,
      month,
      day,
      hour,
      minute,
      second,
      0,
    )) {
      return null;
    }
    return localValue;
  }

  final sign = offset.startsWith('-') ? -1 : 1;
  final offsetHour = int.parse(offset.substring(1, 3));
  final offsetMinute = int.parse(offset.substring(3, 5));
  final utcValue = DateTime.utc(year, month, day, hour, minute, second);
  if (!_matchesUtcComponents(
    utcValue,
    year,
    month,
    day,
    hour,
    minute,
    second,
    0,
  )) {
    return null;
  }
  final duration = Duration(hours: offsetHour, minutes: offsetMinute);
  return sign > 0 ? utcValue.subtract(duration) : utcValue.add(duration);
}

DateTime? _parseEcmaDateString(String raw) {
  final input = raw.trim();
  if (input.isEmpty) {
    return null;
  }
  return _parseIsoLikeDate(input) ?? _parseLegacyDate(input);
}

String _formatIsoString(DateTime value) {
  final utc = value.toUtc();
  final year = utc.year >= 0 && utc.year <= 9999
      ? utc.year.toString().padLeft(4, '0')
      : (utc.year < 0
            ? '-${(-utc.year).toString().padLeft(6, '0')}'
            : '+${utc.year.toString().padLeft(6, '0')}');
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  final hour = utc.hour.toString().padLeft(2, '0');
  final minute = utc.minute.toString().padLeft(2, '0');
  final second = utc.second.toString().padLeft(2, '0');
  final millisecond = utc.millisecond.toString().padLeft(3, '0');
  return '$year-$month-$day'
      'T$hour:$minute:$second.$millisecond'
      'Z';
}

/// JavaScript Date Object implementation
class DateObject {
  /// Creates the global Date constructor and prototype
  static JSNativeFunction createDateConstructor() {
    final dateImpl = JSNativeFunction(
      functionName: 'Date',
      nativeImpl: (args) {
        // Date() constructor implementation
        // Note: Date() vs new Date() dual behavior (string vs object) is handled
        // in visitCallExpression, not here. This function always returns a JSDate object.
        if (args.isEmpty) {
          // new Date() - current date/time
          return JSDate(DateTime.now());
        } else if (args.length == 1) {
          final arg = args[0];
          if (arg.type == JSValueType.number) {
            // new Date(milliseconds)
            final ms = arg.toNumber().floor();
            return JSDate(DateTime.fromMillisecondsSinceEpoch(ms));
          } else if (arg.type == JSValueType.string) {
            // new Date(dateString)
            final parsed = _parseEcmaDateString(arg.toString());
            if (parsed != null) {
              return JSDate(parsed.isUtc ? parsed.toLocal() : parsed);
            }
            try {
              final fallback = DateTime.parse(arg.toString());
              return JSDate(fallback.isUtc ? fallback.toLocal() : fallback);
            } catch (e) {
              return JSDate.invalid(); // Invalid Date
            }
          }
        } else {
          // new Date(year, month, day, hour, minute, second, millisecond)
          final year = args.isNotEmpty ? args[0].toNumber().floor() : 1970;
          final month = args.length > 1
              ? args[1].toNumber().floor() + 1
              : 1; // JS months are 0-based
          final day = args.length > 2 ? args[2].toNumber().floor() : 1;
          final hour = args.length > 3 ? args[3].toNumber().floor() : 0;
          final minute = args.length > 4 ? args[4].toNumber().floor() : 0;
          final second = args.length > 5 ? args[5].toNumber().floor() : 0;
          final millisecond = args.length > 6 ? args[6].toNumber().floor() : 0;

          try {
            final date = DateTime(
              year,
              month,
              day,
              hour,
              minute,
              second,
              millisecond,
            );
            return JSDate(date);
          } catch (e) {
            return JSDate.invalid(); // Invalid Date
          }
        }

        return JSDate(DateTime.now());
      },
      expectedArgs: 7,
      isConstructor: true, // Date is a constructor
    );

    // Add static methods to Date constructor
    _addStaticMethods(dateImpl);

    return dateImpl;
  }

  /// Add static methods to Date constructor
  static void _addStaticMethods(JSNativeFunction dateConstructor) {
    // Date.now() - returns current timestamp
    dateConstructor.setProperty(
      'now',
      JSNativeFunction(
        functionName: 'now',
        nativeImpl: (args) {
          return JSValueFactory.number(
            DateTime.now().millisecondsSinceEpoch.toDouble(),
          );
        },
      ),
    );

    // Date.parse(dateString) - parses date string
    dateConstructor.setProperty(
      'parse',
      JSNativeFunction(
        functionName: 'parse',
        nativeImpl: (args) {
          if (args.isEmpty) {
            return JSValueFactory.number(double.nan);
          }

          final dateStr = args[0].toString();
          final parsed = _parseEcmaDateString(dateStr);
          if (parsed != null) {
            return JSValueFactory.number(
              parsed.millisecondsSinceEpoch.toDouble(),
            );
          }

          try {
            final fallback = DateTime.parse(dateStr);
            return JSValueFactory.number(
              fallback.millisecondsSinceEpoch.toDouble(),
            );
          } catch (e) {
            return JSValueFactory.number(double.nan);
          }
        },
      ),
    );

    // Date.UTC(year, month, day, hour, minute, second, millisecond)
    dateConstructor.setProperty(
      'UTC',
      JSNativeFunction(
        functionName: 'UTC',
        nativeImpl: (args) {
          if (args.isEmpty) {
            return JSValueFactory.number(double.nan);
          }

          final year = _toIntegerNumberOrNull(args[0]);
          final month = args.length > 1 ? _toIntegerNumberOrNull(args[1]) : 0.0;
          final day = args.length > 2 ? _toIntegerNumberOrNull(args[2]) : 1.0;
          final hour = args.length > 3 ? _toIntegerNumberOrNull(args[3]) : 0.0;
          final minute = args.length > 4
              ? _toIntegerNumberOrNull(args[4])
              : 0.0;
          final second = args.length > 5
              ? _toIntegerNumberOrNull(args[5])
              : 0.0;
          final millisecond = args.length > 6
              ? _toIntegerNumberOrNull(args[6])
              : 0.0;

          if ([
            year,
            month,
            day,
            hour,
            minute,
            second,
            millisecond,
          ].any((value) => value == null)) {
            return JSValueFactory.number(double.nan);
          }

          return JSValueFactory.number(
            _dateUtcMilliseconds(
              year!,
              month!,
              day!,
              hour!,
              minute!,
              second!,
              millisecond!,
            ),
          );
        },
      ),
    );
  }
}

/// JavaScript Date value type
class JSDate extends JSObject {
  late DateTime _dateTime;
  bool _isValid = true;

  JSDate(DateTime dateTime) : super() {
    _dateTime = dateTime;
    _setupPrototypeMethods();
  }

  /// Invalid Date constructor
  JSDate.invalid() : super() {
    _dateTime = DateTime.fromMillisecondsSinceEpoch(0);
    _isValid = false;
    _setupPrototypeMethods();
  }

  @override
  String toString() {
    if (!_isValid) return 'Invalid Date';
    return _dateTime.toString();
  }

  /// Returns the date as an ISO string
  String toISOString() {
    if (!_isValid) return 'Invalid Date';
    return _formatIsoString(_dateTime);
  }

  @override
  double toNumber() {
    if (!_isValid) return double.nan;
    return _dateTime.millisecondsSinceEpoch.toDouble();
  }

  @override
  bool toBoolean() => _isValid && _dateTime.millisecondsSinceEpoch != 0;

  @override
  dynamic get primitiveValue => _isValid ? _dateTime : null;

  /// Setup Date prototype methods
  void _setupPrototypeMethods() {
    // getTime() - returns timestamp
    super.setProperty(
      'getTime',
      JSNativeFunction(
        functionName: 'getTime',
        nativeImpl: (args) => JSValueFactory.number(toNumber()),
      ),
    );

    // getFullYear() - returns year
    super.setProperty(
      'getFullYear',
      JSNativeFunction(
        functionName: 'getFullYear',
        nativeImpl: (args) => JSValueFactory.number(_dateTime.year.toDouble()),
      ),
    );

    // getMonth() - returns month (0-based)
    super.setProperty(
      'getMonth',
      JSNativeFunction(
        functionName: 'getMonth',
        nativeImpl: (args) =>
            JSValueFactory.number((_dateTime.month - 1).toDouble()),
      ),
    );

    // getDate() - returns day of month
    super.setProperty(
      'getDate',
      JSNativeFunction(
        functionName: 'getDate',
        nativeImpl: (args) => JSValueFactory.number(_dateTime.day.toDouble()),
      ),
    );

    // getDay() - returns day of week (0=Sunday)
    super.setProperty(
      'getDay',
      JSNativeFunction(
        functionName: 'getDay',
        nativeImpl: (args) => JSValueFactory.number(
          _dateTime.weekday == 7 ? 0.0 : _dateTime.weekday.toDouble(),
        ),
      ),
    );

    // getHours() - returns hour
    super.setProperty(
      'getHours',
      JSNativeFunction(
        functionName: 'getHours',
        nativeImpl: (args) => JSValueFactory.number(_dateTime.hour.toDouble()),
      ),
    );

    // getMinutes() - returns minutes
    super.setProperty(
      'getMinutes',
      JSNativeFunction(
        functionName: 'getMinutes',
        nativeImpl: (args) =>
            JSValueFactory.number(_dateTime.minute.toDouble()),
      ),
    );

    // getSeconds() - returns seconds
    super.setProperty(
      'getSeconds',
      JSNativeFunction(
        functionName: 'getSeconds',
        nativeImpl: (args) =>
            JSValueFactory.number(_dateTime.second.toDouble()),
      ),
    );

    // getMilliseconds() - returns milliseconds
    super.setProperty(
      'getMilliseconds',
      JSNativeFunction(
        functionName: 'getMilliseconds',
        nativeImpl: (args) =>
            JSValueFactory.number(_dateTime.millisecond.toDouble()),
      ),
    );

    // getTimezoneOffset() - returns timezone offset in minutes
    super.setProperty(
      'getTimezoneOffset',
      JSNativeFunction(
        functionName: 'getTimezoneOffset',
        nativeImpl: (args) => JSValueFactory.number(
          -_dateTime.timeZoneOffset.inMinutes.toDouble(),
        ),
      ),
    );

    // UTC methods
    // getUTCFullYear() - returns UTC year
    super.setProperty(
      'getUTCFullYear',
      JSNativeFunction(
        functionName: 'getUTCFullYear',
        nativeImpl: (args) =>
            JSValueFactory.number(_dateTime.toUtc().year.toDouble()),
      ),
    );

    // getUTCMonth() - returns UTC month (0-based)
    super.setProperty(
      'getUTCMonth',
      JSNativeFunction(
        functionName: 'getUTCMonth',
        nativeImpl: (args) =>
            JSValueFactory.number((_dateTime.toUtc().month - 1).toDouble()),
      ),
    );

    // getUTCDate() - returns UTC day of month
    super.setProperty(
      'getUTCDate',
      JSNativeFunction(
        functionName: 'getUTCDate',
        nativeImpl: (args) =>
            JSValueFactory.number(_dateTime.toUtc().day.toDouble()),
      ),
    );

    // getUTCHours() - returns UTC hour
    super.setProperty(
      'getUTCHours',
      JSNativeFunction(
        functionName: 'getUTCHours',
        nativeImpl: (args) =>
            JSValueFactory.number(_dateTime.toUtc().hour.toDouble()),
      ),
    );

    // getUTCMinutes() - returns UTC minutes
    super.setProperty(
      'getUTCMinutes',
      JSNativeFunction(
        functionName: 'getUTCMinutes',
        nativeImpl: (args) =>
            JSValueFactory.number(_dateTime.toUtc().minute.toDouble()),
      ),
    );

    // getUTCSeconds() - returns UTC seconds
    super.setProperty(
      'getUTCSeconds',
      JSNativeFunction(
        functionName: 'getUTCSeconds',
        nativeImpl: (args) =>
            JSValueFactory.number(_dateTime.toUtc().second.toDouble()),
      ),
    );

    // getUTCMilliseconds() - returns UTC milliseconds
    super.setProperty(
      'getUTCMilliseconds',
      JSNativeFunction(
        functionName: 'getUTCMilliseconds',
        nativeImpl: (args) =>
            JSValueFactory.number(_dateTime.toUtc().millisecond.toDouble()),
      ),
    );

    // setUTCFullYear(year, month, day) - sets UTC year
    super.setProperty(
      'setUTCFullYear',
      JSNativeFunction(
        functionName: 'setUTCFullYear',
        nativeImpl: (args) {
          if (args.isNotEmpty) {
            final year = args[0].toNumber().floor();
            final month = args.length > 1
                ? args[1].toNumber().floor() + 1
                : _dateTime.toUtc().month;
            final day = args.length > 2
                ? args[2].toNumber().floor()
                : _dateTime.toUtc().day;

            try {
              final utcDateTime = DateTime.utc(
                year,
                month,
                day,
                _dateTime.toUtc().hour,
                _dateTime.toUtc().minute,
                _dateTime.toUtc().second,
                _dateTime.toUtc().millisecond,
              );
              _dateTime = utcDateTime;
              _isValid = true;
            } catch (e) {
              _isValid = false;
            }
          }
          return JSValueFactory.number(toNumber());
        },
      ),
    );

    super.setProperty(
      'setUTCHours',
      JSNativeFunction(
        functionName: 'setUTCHours',
        nativeImpl: (args) {
          if (args.isEmpty) {
            return JSValueFactory.number(toNumber());
          }

          final utc = _dateTime.toUtc();
          final hour = _toIntegerOrNull(args[0]);
          final minute = args.length > 1
              ? _toIntegerOrNull(args[1])
              : utc.minute;
          final second = args.length > 2
              ? _toIntegerOrNull(args[2])
              : utc.second;
          final millisecond = args.length > 3
              ? _toIntegerOrNull(args[3])
              : utc.millisecond;

          if (hour == null ||
              minute == null ||
              second == null ||
              millisecond == null) {
            _isValid = false;
            return JSValueFactory.number(double.nan);
          }

          _dateTime = DateTime.utc(
            utc.year,
            utc.month,
            utc.day,
            hour,
            minute,
            second,
            millisecond,
          ).toLocal();
          _isValid = true;
          return JSValueFactory.number(toNumber());
        },
      ),
    );

    // setTime(milliseconds) - sets time from timestamp
    super.setProperty(
      'setTime',
      JSNativeFunction(
        functionName: 'setTime',
        nativeImpl: (args) {
          if (args.isNotEmpty) {
            final ms = args[0].toNumber().floor();
            _dateTime = DateTime.fromMillisecondsSinceEpoch(ms);
            _isValid = true;
          }
          return JSValueFactory.number(toNumber());
        },
      ),
    );

    // setFullYear(year, month, day) - sets year
    super.setProperty(
      'setFullYear',
      JSNativeFunction(
        functionName: 'setFullYear',
        nativeImpl: (args) {
          if (args.isNotEmpty) {
            final year = args[0].toNumber().floor();
            final month = args.length > 1
                ? args[1].toNumber().floor() + 1
                : _dateTime.month;
            final day = args.length > 2
                ? args[2].toNumber().floor()
                : _dateTime.day;

            try {
              _dateTime = DateTime(
                year,
                month,
                day,
                _dateTime.hour,
                _dateTime.minute,
                _dateTime.second,
                _dateTime.millisecond,
              );
              _isValid = true;
            } catch (e) {
              _isValid = false;
            }
          }
          return JSValueFactory.number(toNumber());
        },
      ),
    );

    // setDate(day) - sets day of month
    super.setProperty(
      'setDate',
      JSNativeFunction(
        functionName: 'setDate',
        nativeImpl: (args) {
          if (args.isNotEmpty) {
            final day = args[0].toNumber().floor();
            try {
              _dateTime = DateTime(
                _dateTime.year,
                _dateTime.month,
                day,
                _dateTime.hour,
                _dateTime.minute,
                _dateTime.second,
                _dateTime.millisecond,
              );
              _isValid = true;
            } catch (e) {
              _isValid = false;
            }
          }
          return JSValueFactory.number(toNumber());
        },
      ),
    );
    super.setProperty(
      'toString',
      JSNativeFunction(
        functionName: 'toString',
        nativeImpl: (args) => JSValueFactory.string(toString()),
      ),
    );

    // toISOString() - returns ISO string
    super.setProperty(
      'toISOString',
      JSNativeFunction(
        functionName: 'toISOString',
        nativeImpl: (args) {
          if (!_isValid) return JSValueFactory.string('Invalid Date');
          return JSValueFactory.string(_formatIsoString(_dateTime));
        },
      ),
    );

    super.setProperty(
      'toJSON',
      JSNativeFunction(
        functionName: 'toJSON',
        nativeImpl: (args) {
          if (!_isValid) {
            return JSValueFactory.nullValue();
          }
          return JSValueFactory.string(_formatIsoString(_dateTime));
        },
      ),
    );

    // valueOf() - returns primitive value (timestamp)
    super.setProperty(
      'valueOf',
      JSNativeFunction(
        functionName: 'valueOf',
        nativeImpl: (args) => JSValueFactory.number(toNumber()),
      ),
    );
  }
}
