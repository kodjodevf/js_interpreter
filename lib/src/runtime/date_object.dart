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

String _formatUtcString(DateTime value) {
  const weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final utc = value.toUtc();
  final dayName = weekDays[utc.weekday - 1];
  final monthName = months[utc.month - 1];
  final day = utc.day.toString().padLeft(2, '0');
  final year = utc.year.toString().padLeft(4, '0');
  final hour = utc.hour.toString().padLeft(2, '0');
  final minute = utc.minute.toString().padLeft(2, '0');
  final second = utc.second.toString().padLeft(2, '0');
  return '$dayName, $day $monthName $year $hour:$minute:$second GMT';
}

int _makeFullYear(double year) {
  final truncated = year.truncate();
  if (truncated >= 0 && truncated <= 99) {
    return truncated + 1900;
  }
  return truncated;
}

JSDate _requireDateThis(List<JSValue> args, String methodName) {
  if (args.isEmpty || args[0] is! JSDate) {
    throw JSTypeError(
      'Date.prototype.$methodName called on incompatible receiver',
    );
  }
  return args[0] as JSDate;
}

void _defineDatePrototypeMethod(
  JSObject prototype,
  String name,
  NativeFunction nativeImpl, {
  int expectedArgs = 0,
}) {
  prototype.defineProperty(
    name,
    PropertyDescriptor(
      value: JSNativeFunction(
        functionName: name,
        nativeImpl: nativeImpl,
        expectedArgs: expectedArgs,
      ),
      writable: true,
      enumerable: false,
      configurable: true,
    ),
  );
}

void _installDatePrototypeMethods(JSObject prototype) {
  final toUtcStringFunction = JSNativeFunction(
    functionName: 'toUTCString',
    nativeImpl: (args) {
      final date = _requireDateThis(args, 'toUTCString');
      if (!date._isValid) return JSValueFactory.string('Invalid Date');
      return JSValueFactory.string(_formatUtcString(date._dateTime));
    },
    expectedArgs: 0,
  );

  _defineDatePrototypeMethod(
    prototype,
    'getTime',
    (args) =>
        JSValueFactory.number(_requireDateThis(args, 'getTime').toNumber()),
  );

  _defineDatePrototypeMethod(prototype, 'getFullYear', (args) {
    final date = _requireDateThis(args, 'getFullYear');
    if (!date._isValid) return JSValueFactory.number(double.nan);
    return JSValueFactory.number(date._dateTime.year.toDouble());
  });

  _defineDatePrototypeMethod(prototype, 'getYear', (args) {
    final date = _requireDateThis(args, 'getYear');
    if (!date._isValid) return JSValueFactory.number(double.nan);
    return JSValueFactory.number((date._dateTime.year - 1900).toDouble());
  });

  _defineDatePrototypeMethod(prototype, 'getMonth', (args) {
    final date = _requireDateThis(args, 'getMonth');
    if (!date._isValid) return JSValueFactory.number(double.nan);
    return JSValueFactory.number((date._dateTime.month - 1).toDouble());
  });

  _defineDatePrototypeMethod(prototype, 'getDate', (args) {
    final date = _requireDateThis(args, 'getDate');
    if (!date._isValid) return JSValueFactory.number(double.nan);
    return JSValueFactory.number(date._dateTime.day.toDouble());
  });

  _defineDatePrototypeMethod(prototype, 'getDay', (args) {
    final date = _requireDateThis(args, 'getDay');
    if (!date._isValid) return JSValueFactory.number(double.nan);
    return JSValueFactory.number(
      date._dateTime.weekday == 7 ? 0.0 : date._dateTime.weekday.toDouble(),
    );
  });

  _defineDatePrototypeMethod(prototype, 'getHours', (args) {
    final date = _requireDateThis(args, 'getHours');
    if (!date._isValid) return JSValueFactory.number(double.nan);
    return JSValueFactory.number(date._dateTime.hour.toDouble());
  });

  _defineDatePrototypeMethod(prototype, 'getMinutes', (args) {
    final date = _requireDateThis(args, 'getMinutes');
    if (!date._isValid) return JSValueFactory.number(double.nan);
    return JSValueFactory.number(date._dateTime.minute.toDouble());
  });

  _defineDatePrototypeMethod(prototype, 'getSeconds', (args) {
    final date = _requireDateThis(args, 'getSeconds');
    if (!date._isValid) return JSValueFactory.number(double.nan);
    return JSValueFactory.number(date._dateTime.second.toDouble());
  });

  _defineDatePrototypeMethod(prototype, 'getMilliseconds', (args) {
    final date = _requireDateThis(args, 'getMilliseconds');
    if (!date._isValid) return JSValueFactory.number(double.nan);
    return JSValueFactory.number(date._dateTime.millisecond.toDouble());
  });

  _defineDatePrototypeMethod(prototype, 'getTimezoneOffset', (args) {
    final date = _requireDateThis(args, 'getTimezoneOffset');
    if (!date._isValid) return JSValueFactory.number(double.nan);
    return JSValueFactory.number(
      -date._dateTime.timeZoneOffset.inMinutes.toDouble(),
    );
  });

  _defineDatePrototypeMethod(prototype, 'getUTCFullYear', (args) {
    final date = _requireDateThis(args, 'getUTCFullYear');
    if (!date._isValid) return JSValueFactory.number(double.nan);
    return JSValueFactory.number(date._dateTime.toUtc().year.toDouble());
  });

  _defineDatePrototypeMethod(prototype, 'getUTCMonth', (args) {
    final date = _requireDateThis(args, 'getUTCMonth');
    if (!date._isValid) return JSValueFactory.number(double.nan);
    return JSValueFactory.number((date._dateTime.toUtc().month - 1).toDouble());
  });

  _defineDatePrototypeMethod(prototype, 'getUTCDate', (args) {
    final date = _requireDateThis(args, 'getUTCDate');
    if (!date._isValid) return JSValueFactory.number(double.nan);
    return JSValueFactory.number(date._dateTime.toUtc().day.toDouble());
  });

  _defineDatePrototypeMethod(prototype, 'getUTCHours', (args) {
    final date = _requireDateThis(args, 'getUTCHours');
    if (!date._isValid) return JSValueFactory.number(double.nan);
    return JSValueFactory.number(date._dateTime.toUtc().hour.toDouble());
  });

  _defineDatePrototypeMethod(prototype, 'getUTCMinutes', (args) {
    final date = _requireDateThis(args, 'getUTCMinutes');
    if (!date._isValid) return JSValueFactory.number(double.nan);
    return JSValueFactory.number(date._dateTime.toUtc().minute.toDouble());
  });

  _defineDatePrototypeMethod(prototype, 'getUTCSeconds', (args) {
    final date = _requireDateThis(args, 'getUTCSeconds');
    if (!date._isValid) return JSValueFactory.number(double.nan);
    return JSValueFactory.number(date._dateTime.toUtc().second.toDouble());
  });

  _defineDatePrototypeMethod(prototype, 'getUTCMilliseconds', (args) {
    final date = _requireDateThis(args, 'getUTCMilliseconds');
    if (!date._isValid) return JSValueFactory.number(double.nan);
    return JSValueFactory.number(date._dateTime.toUtc().millisecond.toDouble());
  });

  _defineDatePrototypeMethod(prototype, 'setUTCFullYear', (args) {
    final date = _requireDateThis(args, 'setUTCFullYear');
    if (args.length < 2) {
      return JSValueFactory.number(date.toNumber());
    }

    final year = _toIntegerOrNull(args[1]);
    final utc = date._isValid
        ? date._dateTime.toUtc()
        : DateTime.fromMillisecondsSinceEpoch(0).toUtc();
    final month = args.length > 2
        ? _toIntegerOrNull(args[2])?.toInt()
        : utc.month - 1;
    final day = args.length > 3 ? _toIntegerOrNull(args[3])?.toInt() : utc.day;
    if (year == null || month == null || day == null) {
      date._isValid = false;
      return JSValueFactory.number(double.nan);
    }

    date._dateTime = DateTime.utc(
      year,
      month + 1,
      day,
      utc.hour,
      utc.minute,
      utc.second,
      utc.millisecond,
    ).toLocal();
    date._isValid = true;
    return JSValueFactory.number(date.toNumber());
  }, expectedArgs: 3);

  _defineDatePrototypeMethod(prototype, 'setUTCHours', (args) {
    final date = _requireDateThis(args, 'setUTCHours');
    if (args.length < 2) {
      return JSValueFactory.number(date.toNumber());
    }

    final utc = date._isValid
        ? date._dateTime.toUtc()
        : DateTime.fromMillisecondsSinceEpoch(0).toUtc();
    final hour = _toIntegerOrNull(args[1]);
    final minute = args.length > 2 ? _toIntegerOrNull(args[2]) : utc.minute;
    final second = args.length > 3 ? _toIntegerOrNull(args[3]) : utc.second;
    final millisecond = args.length > 4
        ? _toIntegerOrNull(args[4])
        : utc.millisecond;
    if (hour == null ||
        minute == null ||
        second == null ||
        millisecond == null) {
      date._isValid = false;
      return JSValueFactory.number(double.nan);
    }

    date._dateTime = DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      hour,
      minute,
      second,
      millisecond,
    ).toLocal();
    date._isValid = true;
    return JSValueFactory.number(date.toNumber());
  }, expectedArgs: 4);

  _defineDatePrototypeMethod(prototype, 'setTime', (args) {
    final date = _requireDateThis(args, 'setTime');
    if (args.length < 2) {
      return JSValueFactory.number(date.toNumber());
    }
    final value = args[1].toNumber();
    if (value.isNaN || value.isInfinite) {
      date._isValid = false;
      return JSValueFactory.number(double.nan);
    }
    date._dateTime = DateTime.fromMillisecondsSinceEpoch(value.truncate());
    date._isValid = true;
    return JSValueFactory.number(date.toNumber());
  }, expectedArgs: 1);

  _defineDatePrototypeMethod(prototype, 'setFullYear', (args) {
    final date = _requireDateThis(args, 'setFullYear');
    if (args.length < 2) {
      return JSValueFactory.number(date.toNumber());
    }

    final yearNumber = args[1].toNumber();
    final base = date._isValid ? date._dateTime : DateTime(1970, 1, 1);
    if (yearNumber.isNaN || yearNumber.isInfinite) {
      date._isValid = false;
      return JSValueFactory.number(double.nan);
    }

    final month = args.length > 2 ? _toIntegerOrNull(args[2]) : base.month - 1;
    final day = args.length > 3 ? _toIntegerOrNull(args[3]) : base.day;
    if (month == null || day == null) {
      date._isValid = false;
      return JSValueFactory.number(double.nan);
    }

    date._dateTime = DateTime(
      yearNumber.truncate(),
      month + 1,
      day,
      base.hour,
      base.minute,
      base.second,
      base.millisecond,
    );
    date._isValid = true;
    return JSValueFactory.number(date.toNumber());
  }, expectedArgs: 3);

  _defineDatePrototypeMethod(prototype, 'setYear', (args) {
    final date = _requireDateThis(args, 'setYear');
    final base = date._isValid ? date._dateTime : DateTime(1970, 1, 1);
    if (args.length < 2) {
      date._isValid = false;
      return JSValueFactory.number(double.nan);
    }

    final yearNumber = args[1].toNumber();
    if (yearNumber.isNaN || yearNumber.isInfinite) {
      date._isValid = false;
      return JSValueFactory.number(double.nan);
    }

    try {
      final updated = DateTime(
        _makeFullYear(yearNumber),
        base.month,
        base.day,
        base.hour,
        base.minute,
        base.second,
        base.millisecond,
      );
      final clipped = _timeClip(updated.millisecondsSinceEpoch.toDouble());
      if (clipped.isNaN) {
        date._isValid = false;
        return JSValueFactory.number(double.nan);
      }
      date._dateTime = DateTime.fromMillisecondsSinceEpoch(clipped.truncate());
      date._isValid = true;
      return JSValueFactory.number(date.toNumber());
    } catch (e) {
      date._isValid = false;
      return JSValueFactory.number(double.nan);
    }
  }, expectedArgs: 1);

  _defineDatePrototypeMethod(prototype, 'setDate', (args) {
    final date = _requireDateThis(args, 'setDate');
    if (args.length < 2) {
      return JSValueFactory.number(date.toNumber());
    }
    final day = _toIntegerOrNull(args[1]);
    if (day == null) {
      date._isValid = false;
      return JSValueFactory.number(double.nan);
    }
    final base = date._isValid ? date._dateTime : DateTime(1970, 1, 1);
    date._dateTime = DateTime(
      base.year,
      base.month,
      day,
      base.hour,
      base.minute,
      base.second,
      base.millisecond,
    );
    date._isValid = true;
    return JSValueFactory.number(date.toNumber());
  }, expectedArgs: 1);

  _defineDatePrototypeMethod(
    prototype,
    'toString',
    (args) =>
        JSValueFactory.string(_requireDateThis(args, 'toString').toString()),
  );

  _defineDatePrototypeMethod(prototype, 'toISOString', (args) {
    final date = _requireDateThis(args, 'toISOString');
    if (!date._isValid) return JSValueFactory.string('Invalid Date');
    return JSValueFactory.string(_formatIsoString(date._dateTime));
  });

  _defineDatePrototypeMethod(prototype, 'toJSON', (args) {
    final date = _requireDateThis(args, 'toJSON');
    if (!date._isValid) {
      return JSValueFactory.nullValue();
    }
    return JSValueFactory.string(_formatIsoString(date._dateTime));
  });

  _defineDatePrototypeMethod(
    prototype,
    'valueOf',
    (args) =>
        JSValueFactory.number(_requireDateThis(args, 'valueOf').toNumber()),
  );

  prototype.defineProperty(
    'toUTCString',
    PropertyDescriptor(
      value: toUtcStringFunction,
      writable: true,
      enumerable: false,
      configurable: true,
    ),
  );
  prototype.defineProperty(
    'toGMTString',
    PropertyDescriptor(
      value: toUtcStringFunction,
      writable: true,
      enumerable: false,
      configurable: true,
    ),
  );
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
            final clipped = _timeClip(arg.toNumber());
            if (clipped.isNaN) {
              return JSDate.invalid();
            }
            try {
              return JSDate(
                DateTime.fromMillisecondsSinceEpoch(clipped.truncate()),
              );
            } catch (e) {
              return JSDate.invalid(); // Invalid Date
            }
          }

          final dateStr = arg.toString();
          final parsed = _parseEcmaDateString(dateStr);
          if (parsed != null) {
            return JSDate(parsed.isUtc ? parsed.toLocal() : parsed);
          }
          try {
            final fallback = DateTime.parse(dateStr);
            return JSDate(fallback.isUtc ? fallback.toLocal() : fallback);
          } catch (e) {
            return JSDate.invalid(); // Invalid Date
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
      },
      expectedArgs: 7,
      isConstructor: true, // Date is a constructor
    );

    // Add static methods to Date constructor
    _addStaticMethods(dateImpl);
    final datePrototype = JSObject();
    _installDatePrototypeMethods(datePrototype);
    dateImpl.setProperty('prototype', datePrototype);
    datePrototype.defineConstructorProperty(dateImpl);
    JSDate.setDatePrototype(datePrototype);

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
  static JSObject? _datePrototype;

  static void setDatePrototype(JSObject prototype) {
    _datePrototype = prototype;
  }

  late DateTime _dateTime;
  bool _isValid = true;

  JSDate(DateTime dateTime) : super() {
    _dateTime = dateTime;
    if (_datePrototype != null) {
      setPrototype(_datePrototype!);
    }
  }

  /// Invalid Date constructor
  JSDate.invalid() : super() {
    _dateTime = DateTime.fromMillisecondsSinceEpoch(0);
    _isValid = false;
    if (_datePrototype != null) {
      setPrototype(_datePrototype!);
    }
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
}
