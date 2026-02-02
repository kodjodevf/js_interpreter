/// Complete Temporal API Implementation for ES2024
/// Comprehensive support for date, time, duration, timezone handling
library;

import 'js_value.dart';
import 'native_functions.dart';

// ============================================================================
// Utility Functions
// ============================================================================

bool _isLeapYear(int year) {
  return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
}

int _daysInMonth(int year, int month) {
  final daysPerMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month == 2 && _isLeapYear(year)) return 29;
  return daysPerMonth[month - 1];
}

int _daysInYear(int year) {
  return _isLeapYear(year) ? 366 : 365;
}

DateTime _makeDateTime(
  int year,
  int month,
  int day,
  int hour,
  int minute,
  int second,
  int millisecond,
) {
  return DateTime(year, month, day, hour, minute, second, millisecond);
}

// ============================================================================
// PlainDate
// ============================================================================

class JSTemporalPlainDate extends JSValue {
  final int year;
  final int month;
  final int day;

  JSTemporalPlainDate({
    required this.year,
    required this.month,
    required this.day,
  }) {
    _validate();
  }

  void _validate() {
    if (month < 1 || month > 12) throw JSRangeError('Invalid month: $month');
    final max = _daysInMonth(year, month);
    if (day < 1 || day > max) {
      throw JSRangeError('Invalid day: $day for month $month');
    }
  }

  JSTemporalPlainDate add(int years, int months, int days) {
    int y = year + years;
    int m = month + months;
    int d = day;

    while (m > 12) {
      m -= 12;
      y++;
    }
    while (m < 1) {
      m += 12;
      y--;
    }

    final maxDay = _daysInMonth(y, m);
    if (d > maxDay) d = maxDay;

    d += days;
    while (d > _daysInMonth(y, m)) {
      d -= _daysInMonth(y, m);
      m++;
      if (m > 12) {
        m = 1;
        y++;
      }
    }
    while (d < 1) {
      m--;
      if (m < 1) {
        m = 12;
        y--;
      }
      d += _daysInMonth(y, m);
    }

    return JSTemporalPlainDate(year: y, month: m, day: d);
  }

  JSTemporalPlainDate subtract(int years, int months, int days) {
    return add(-years, -months, -days);
  }

  int compare(JSTemporalPlainDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  int dayOfWeek() {
    final dt = _makeDateTime(year, month, day, 0, 0, 0, 0);
    return dt.weekday == 7 ? 0 : dt.weekday; // Sunday = 0, Monday = 1, ...
  }

  int dayOfYear() {
    int days = 0;
    for (int m = 1; m < month; m++) {
      days += _daysInMonth(year, m);
    }
    return days + day;
  }

  JSTemporalPlainDateTime toPlainDateTime(JSTemporalPlainTime time) {
    return JSTemporalPlainDateTime(date: this, time: time);
  }

  @override
  JSValueType get type => JSValueType.object;
  @override
  dynamic get primitiveValue => toString();
  @override
  bool toBoolean() => true;
  @override
  double toNumber() => _makeDateTime(
    year,
    month,
    day,
    0,
    0,
    0,
    0,
  ).millisecondsSinceEpoch.toDouble();
  @override
  String toString() =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  @override
  bool equals(JSValue other) =>
      other is JSTemporalPlainDate &&
      year == other.year &&
      month == other.month &&
      day == other.day;
  @override
  bool strictEquals(JSValue other) => equals(other);
  @override
  JSObject toObject() {
    final obj = JSObject();
    obj.setProperty('year', JSNumber(year.toDouble()));
    obj.setProperty('month', JSNumber(month.toDouble()));
    obj.setProperty('day', JSNumber(day.toDouble()));
    obj.setProperty('dayOfWeek', JSNumber(dayOfWeek().toDouble()));
    obj.setProperty('dayOfYear', JSNumber(dayOfYear().toDouble()));
    return obj;
  }
}

// ============================================================================
// PlainTime
// ============================================================================

class JSTemporalPlainTime extends JSValue {
  final int hour;
  final int minute;
  final int second;
  final int millisecond;
  final int microsecond;
  final int nanosecond;

  JSTemporalPlainTime({
    required this.hour,
    required this.minute,
    required this.second,
    this.millisecond = 0,
    this.microsecond = 0,
    this.nanosecond = 0,
  }) {
    _validate();
  }

  void _validate() {
    if (hour < 0 || hour > 23) throw JSRangeError('Invalid hour: $hour');
    if (minute < 0 || minute > 59) {
      throw JSRangeError('Invalid minute: $minute');
    }
    if (second < 0 || second > 59) {
      throw JSRangeError('Invalid second: $second');
    }
    if (millisecond < 0 || millisecond > 999) {
      throw JSRangeError('Invalid millisecond: $millisecond');
    }
    if (microsecond < 0 || microsecond > 999) {
      throw JSRangeError('Invalid microsecond: $microsecond');
    }
    if (nanosecond < 0 || nanosecond > 999) {
      throw JSRangeError('Invalid nanosecond: $nanosecond');
    }
  }

  JSTemporalPlainTime add(int hours, int minutes, int seconds, int ms) {
    int h = hour + hours;
    int m = minute + minutes;
    int s = second + seconds;
    int ms_ = millisecond + ms;

    while (ms_ >= 1000) {
      ms_ -= 1000;
      s++;
    }
    while (ms_ < 0) {
      ms_ += 1000;
      s--;
    }

    while (s >= 60) {
      s -= 60;
      m++;
    }
    while (s < 0) {
      s += 60;
      m--;
    }

    while (m >= 60) {
      m -= 60;
      h++;
    }
    while (m < 0) {
      m += 60;
      h--;
    }

    while (h >= 24) {
      h -= 24;
    }
    while (h < 0) {
      h += 24;
    }

    return JSTemporalPlainTime(
      hour: h,
      minute: m,
      second: s,
      millisecond: ms_,
      microsecond: microsecond,
      nanosecond: nanosecond,
    );
  }

  JSTemporalPlainTime subtract(int hours, int minutes, int seconds, int ms) {
    return add(-hours, -minutes, -seconds, -ms);
  }

  int compare(JSTemporalPlainTime other) {
    if (hour != other.hour) return hour.compareTo(other.hour);
    if (minute != other.minute) return minute.compareTo(other.minute);
    if (second != other.second) return second.compareTo(other.second);
    if (millisecond != other.millisecond) {
      return millisecond.compareTo(other.millisecond);
    }
    if (microsecond != other.microsecond) {
      return microsecond.compareTo(other.microsecond);
    }
    return nanosecond.compareTo(other.nanosecond);
  }

  @override
  JSValueType get type => JSValueType.object;
  @override
  dynamic get primitiveValue => toString();
  @override
  bool toBoolean() => true;
  @override
  double toNumber() =>
      (hour * 3600000 + minute * 60000 + second * 1000 + millisecond)
          .toDouble();
  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}.${millisecond.toString().padLeft(3, '0')}';
  @override
  bool equals(JSValue other) =>
      other is JSTemporalPlainTime &&
      hour == other.hour &&
      minute == other.minute &&
      second == other.second &&
      millisecond == other.millisecond;
  @override
  bool strictEquals(JSValue other) => equals(other);
  @override
  JSObject toObject() {
    final obj = JSObject();
    obj.setProperty('hour', JSNumber(hour.toDouble()));
    obj.setProperty('minute', JSNumber(minute.toDouble()));
    obj.setProperty('second', JSNumber(second.toDouble()));
    obj.setProperty('millisecond', JSNumber(millisecond.toDouble()));
    obj.setProperty('microsecond', JSNumber(microsecond.toDouble()));
    obj.setProperty('nanosecond', JSNumber(nanosecond.toDouble()));
    return obj;
  }
}

// ============================================================================
// PlainDateTime
// ============================================================================

class JSTemporalPlainDateTime extends JSValue {
  final JSTemporalPlainDate date;
  final JSTemporalPlainTime time;

  JSTemporalPlainDateTime({required this.date, required this.time});

  JSTemporalPlainDate getDate() => date;
  JSTemporalPlainTime getTime() => time;

  JSTemporalPlainDateTime add(
    int years,
    int months,
    int days,
    int hours,
    int minutes,
    int seconds,
    int ms,
  ) {
    final newDate = date.add(years, months, days);
    final newTime = time.add(hours, minutes, seconds, ms);
    return JSTemporalPlainDateTime(date: newDate, time: newTime);
  }

  JSTemporalPlainDateTime subtract(
    int years,
    int months,
    int days,
    int hours,
    int minutes,
    int seconds,
    int ms,
  ) {
    return add(-years, -months, -days, -hours, -minutes, -seconds, -ms);
  }

  int compare(JSTemporalPlainDateTime other) {
    final dateComp = date.compare(other.date);
    if (dateComp != 0) return dateComp;
    return time.compare(other.time);
  }

  @override
  JSValueType get type => JSValueType.object;
  @override
  dynamic get primitiveValue => toString();
  @override
  bool toBoolean() => true;
  @override
  double toNumber() => _makeDateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
    time.second,
    time.millisecond,
  ).millisecondsSinceEpoch.toDouble();
  @override
  String toString() => '${date.toString()}T${time.toString()}';
  @override
  bool equals(JSValue other) =>
      other is JSTemporalPlainDateTime &&
      date.equals(other.date) &&
      time.equals(other.time);
  @override
  bool strictEquals(JSValue other) => equals(other);
  @override
  JSObject toObject() {
    final obj = JSObject();
    obj.setProperty('date', date.toObject());
    obj.setProperty('time', time.toObject());
    return obj;
  }
}

// ============================================================================
// ZonedDateTime
// ============================================================================

class JSTemporalZonedDateTime extends JSValue {
  final JSTemporalPlainDateTime plainDateTime;
  final String timeZone;
  final int offsetNanoseconds;

  JSTemporalZonedDateTime({
    required this.plainDateTime,
    required this.timeZone,
    this.offsetNanoseconds = 0,
  });

  @override
  JSValueType get type => JSValueType.object;
  @override
  dynamic get primitiveValue => toString();
  @override
  bool toBoolean() => true;
  @override
  double toNumber() => plainDateTime.toNumber();
  @override
  String toString() => '${plainDateTime.toString()}[$timeZone]';
  @override
  bool equals(JSValue other) =>
      other is JSTemporalZonedDateTime &&
      plainDateTime.equals(other.plainDateTime) &&
      timeZone == other.timeZone;
  @override
  bool strictEquals(JSValue other) => equals(other);
  @override
  JSObject toObject() {
    final obj = JSObject();
    obj.setProperty('plainDateTime', plainDateTime.toObject());
    obj.setProperty('timeZone', JSValueFactory.string(timeZone));
    obj.setProperty(
      'offsetNanoseconds',
      JSNumber(offsetNanoseconds.toDouble()),
    );
    return obj;
  }
}

// ============================================================================
// PlainYearMonth
// ============================================================================

class JSTemporalPlainYearMonth extends JSValue {
  final int year;
  final int month;

  JSTemporalPlainYearMonth({required this.year, required this.month}) {
    if (month < 1 || month > 12) throw JSRangeError('Invalid month: $month');
  }

  JSTemporalPlainYearMonth add(int years, int months) {
    int y = year + years;
    int m = month + months;

    while (m > 12) {
      m -= 12;
      y++;
    }
    while (m < 1) {
      m += 12;
      y--;
    }

    return JSTemporalPlainYearMonth(year: y, month: m);
  }

  int daysInMonth() => _daysInMonth(year, month);
  int daysInYear() => _daysInYear(year);

  @override
  JSValueType get type => JSValueType.object;
  @override
  dynamic get primitiveValue => toString();
  @override
  bool toBoolean() => true;
  @override
  double toNumber() => _makeDateTime(
    year,
    month,
    1,
    0,
    0,
    0,
    0,
  ).millisecondsSinceEpoch.toDouble();
  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}';
  @override
  bool equals(JSValue other) =>
      other is JSTemporalPlainYearMonth &&
      year == other.year &&
      month == other.month;
  @override
  bool strictEquals(JSValue other) => equals(other);
  @override
  JSObject toObject() {
    final obj = JSObject();
    obj.setProperty('year', JSNumber(year.toDouble()));
    obj.setProperty('month', JSNumber(month.toDouble()));
    obj.setProperty('daysInMonth', JSNumber(daysInMonth().toDouble()));
    obj.setProperty('daysInYear', JSNumber(daysInYear().toDouble()));
    return obj;
  }
}

// ============================================================================
// PlainMonthDay
// ============================================================================

class JSTemporalPlainMonthDay extends JSValue {
  final int month;
  final int day;
  final int? year; // optional reference year

  JSTemporalPlainMonthDay({required this.month, required this.day, this.year}) {
    if (month < 1 || month > 12) throw JSRangeError('Invalid month: $month');
    final refYear = year ?? 2000;
    final max = _daysInMonth(refYear, month);
    if (day < 1 || day > max) {
      throw JSRangeError('Invalid day: $day for month $month');
    }
  }

  @override
  JSValueType get type => JSValueType.object;
  @override
  dynamic get primitiveValue => toString();
  @override
  bool toBoolean() => true;
  @override
  double toNumber() => (month * 31 + day).toDouble();
  @override
  String toString() =>
      '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  @override
  bool equals(JSValue other) =>
      other is JSTemporalPlainMonthDay &&
      month == other.month &&
      day == other.day;
  @override
  bool strictEquals(JSValue other) => equals(other);
  @override
  JSObject toObject() {
    final obj = JSObject();
    obj.setProperty('month', JSNumber(month.toDouble()));
    obj.setProperty('day', JSNumber(day.toDouble()));
    return obj;
  }
}

// ============================================================================
// Duration
// ============================================================================

class JSTemporalDuration extends JSValue {
  final int years;
  final int months;
  final int weeks;
  final int days;
  final int hours;
  final int minutes;
  final int seconds;
  final int milliseconds;
  final int microseconds;
  final int nanoseconds;

  JSTemporalDuration({
    this.years = 0,
    this.months = 0,
    this.weeks = 0,
    this.days = 0,
    this.hours = 0,
    this.minutes = 0,
    this.seconds = 0,
    this.milliseconds = 0,
    this.microseconds = 0,
    this.nanoseconds = 0,
  });

  int get sign {
    if (years != 0) return years > 0 ? 1 : -1;
    if (months != 0) return months > 0 ? 1 : -1;
    if (weeks != 0) return weeks > 0 ? 1 : -1;
    if (days != 0) return days > 0 ? 1 : -1;
    if (hours != 0) return hours > 0 ? 1 : -1;
    if (minutes != 0) return minutes > 0 ? 1 : -1;
    if (seconds != 0) return seconds > 0 ? 1 : -1;
    if (milliseconds != 0) return milliseconds > 0 ? 1 : -1;
    if (microseconds != 0) return microseconds > 0 ? 1 : -1;
    if (nanoseconds != 0) return nanoseconds > 0 ? 1 : -1;
    return 0;
  }

  bool get blank => sign == 0;

  double getTotalMilliseconds() {
    return (days * 24 * 60 * 60 * 1000) +
        (hours * 60 * 60 * 1000) +
        (minutes * 60 * 1000) +
        (seconds * 1000) +
        milliseconds +
        (microseconds / 1000) +
        (nanoseconds / 1000000);
  }

  JSTemporalDuration abs() {
    return JSTemporalDuration(
      years: years.abs(),
      months: months.abs(),
      weeks: weeks.abs(),
      days: days.abs(),
      hours: hours.abs(),
      minutes: minutes.abs(),
      seconds: seconds.abs(),
      milliseconds: milliseconds.abs(),
      microseconds: microseconds.abs(),
      nanoseconds: nanoseconds.abs(),
    );
  }

  @override
  JSValueType get type => JSValueType.object;
  @override
  dynamic get primitiveValue => getTotalMilliseconds();
  @override
  bool toBoolean() => !blank;
  @override
  double toNumber() => getTotalMilliseconds();
  @override
  String toString() =>
      'P${years}Y${months}M${weeks}W${days}DT${hours}H${minutes}M$seconds.${milliseconds}S';
  @override
  bool equals(JSValue other) =>
      other is JSTemporalDuration &&
      getTotalMilliseconds() == other.getTotalMilliseconds();
  @override
  bool strictEquals(JSValue other) => equals(other);
  @override
  JSObject toObject() {
    final obj = JSObject();
    obj.setProperty('years', JSNumber(years.toDouble()));
    obj.setProperty('months', JSNumber(months.toDouble()));
    obj.setProperty('weeks', JSNumber(weeks.toDouble()));
    obj.setProperty('days', JSNumber(days.toDouble()));
    obj.setProperty('hours', JSNumber(hours.toDouble()));
    obj.setProperty('minutes', JSNumber(minutes.toDouble()));
    obj.setProperty('seconds', JSNumber(seconds.toDouble()));
    obj.setProperty('milliseconds', JSNumber(milliseconds.toDouble()));
    obj.setProperty('microseconds', JSNumber(microseconds.toDouble()));
    obj.setProperty('nanoseconds', JSNumber(nanoseconds.toDouble()));
    obj.setProperty('sign', JSNumber(sign.toDouble()));
    obj.setProperty('blank', JSValueFactory.boolean(blank));
    return obj;
  }
}

// ============================================================================
// Instant
// ============================================================================

class JSTemporalInstant extends JSValue {
  final int epochNanoseconds;

  JSTemporalInstant({required this.epochNanoseconds});

  static JSTemporalInstant now() {
    final ns = DateTime.now().millisecondsSinceEpoch * 1000000;
    return JSTemporalInstant(epochNanoseconds: ns);
  }

  @override
  JSValueType get type => JSValueType.object;
  @override
  dynamic get primitiveValue => epochNanoseconds;
  @override
  bool toBoolean() => true;
  @override
  double toNumber() => (epochNanoseconds / 1000000).toDouble();
  @override
  String toString() {
    final ms = epochNanoseconds ~/ 1000000;
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return dt.toIso8601String();
  }

  @override
  bool equals(JSValue other) =>
      other is JSTemporalInstant && epochNanoseconds == other.epochNanoseconds;
  @override
  bool strictEquals(JSValue other) => equals(other);
  @override
  JSObject toObject() {
    final obj = JSObject();
    obj.setProperty('epochNanoseconds', JSNumber(epochNanoseconds.toDouble()));
    return obj;
  }
}

// ============================================================================
// Temporal Namespace
// ============================================================================

/// Wrap a Temporal object (e.g., PlainDate) to add JavaScript method properties
JSObject _wrapTemporalObject(JSValue value) {
  final wrapper = JSObject();

  // Copy basic properties
  wrapper.setProperty('__value', value);

  // Add methods based on type
  if (value is JSTemporalPlainDate) {
    wrapper.setProperty(
      'add',
      JSNativeFunction(
        functionName: 'add',
        nativeImpl: (args) {
          if (args.isEmpty || args[0] is! JSObject) {
            throw JSTypeError('add requires an object argument');
          }
          final obj = args[0] as JSObject;
          final years = obj.getProperty('years').toNumber().toInt();
          final months = obj.getProperty('months').toNumber().toInt();
          final days = obj.getProperty('days').toNumber().toInt();
          return _wrapTemporalObject(value.add(years, months, days));
        },
      ),
    );
    wrapper.setProperty(
      'subtract',
      JSNativeFunction(
        functionName: 'subtract',
        nativeImpl: (args) {
          if (args.isEmpty || args[0] is! JSObject) {
            throw JSTypeError('subtract requires an object argument');
          }
          final obj = args[0] as JSObject;
          final years = obj.getProperty('years').toNumber().toInt();
          final months = obj.getProperty('months').toNumber().toInt();
          final days = obj.getProperty('days').toNumber().toInt();
          return _wrapTemporalObject(value.subtract(years, months, days));
        },
      ),
    );
    wrapper.setProperty(
      'compare',
      JSNativeFunction(
        functionName: 'compare',
        nativeImpl: (args) {
          if (args.isEmpty) throw JSTypeError('compare requires an argument');
          late JSTemporalPlainDate other;
          if (args[0] is JSTemporalPlainDate) {
            other = args[0] as JSTemporalPlainDate;
          } else if (args[0] is JSObject) {
            final obj = args[0] as JSObject;
            if (obj.hasProperty('__value') &&
                obj.getProperty('__value') is JSTemporalPlainDate) {
              other = obj.getProperty('__value') as JSTemporalPlainDate;
            } else {
              throw JSTypeError('Invalid argument to compare');
            }
          } else {
            throw JSTypeError('Invalid argument to compare');
          }
          return JSNumber(value.compare(other).toDouble());
        },
      ),
    );
    // Copy read-only properties
    wrapper.setProperty('year', JSNumber(value.year.toDouble()));
    wrapper.setProperty('month', JSNumber(value.month.toDouble()));
    wrapper.setProperty('day', JSNumber(value.day.toDouble()));
    wrapper.setProperty('dayOfWeek', JSNumber(value.dayOfWeek().toDouble()));
    wrapper.setProperty('dayOfYear', JSNumber(value.dayOfYear().toDouble()));
  } else if (value is JSTemporalPlainTime) {
    wrapper.setProperty(
      'add',
      JSNativeFunction(
        functionName: 'add',
        nativeImpl: (args) {
          if (args.isEmpty || args[0] is! JSObject) {
            throw JSTypeError('add requires an object argument');
          }
          final obj = args[0] as JSObject;
          final hours = obj.getProperty('hours').toNumber().toInt();
          final minutes = obj.getProperty('minutes').toNumber().toInt();
          final seconds = obj.getProperty('seconds').toNumber().toInt();
          final ms = obj.getProperty('milliseconds').toNumber().toInt();
          return _wrapTemporalObject(value.add(hours, minutes, seconds, ms));
        },
      ),
    );
    wrapper.setProperty(
      'subtract',
      JSNativeFunction(
        functionName: 'subtract',
        nativeImpl: (args) {
          if (args.isEmpty || args[0] is! JSObject) {
            throw JSTypeError('subtract requires an object argument');
          }
          final obj = args[0] as JSObject;
          final hours = obj.getProperty('hours').toNumber().toInt();
          final minutes = obj.getProperty('minutes').toNumber().toInt();
          final seconds = obj.getProperty('seconds').toNumber().toInt();
          final ms = obj.getProperty('milliseconds').toNumber().toInt();
          return _wrapTemporalObject(
            value.subtract(hours, minutes, seconds, ms),
          );
        },
      ),
    );
    wrapper.setProperty(
      'compare',
      JSNativeFunction(
        functionName: 'compare',
        nativeImpl: (args) {
          if (args.isEmpty) throw JSTypeError('compare requires an argument');
          late JSTemporalPlainTime other;
          if (args[0] is JSTemporalPlainTime) {
            other = args[0] as JSTemporalPlainTime;
          } else if (args[0] is JSObject) {
            final obj = args[0] as JSObject;
            if (obj.hasProperty('__value') &&
                obj.getProperty('__value') is JSTemporalPlainTime) {
              other = obj.getProperty('__value') as JSTemporalPlainTime;
            } else {
              throw JSTypeError('Invalid argument to compare');
            }
          } else {
            throw JSTypeError('Invalid argument to compare');
          }
          return JSNumber(value.compare(other).toDouble());
        },
      ),
    );
    // Copy read-only properties
    wrapper.setProperty('hour', JSNumber(value.hour.toDouble()));
    wrapper.setProperty('minute', JSNumber(value.minute.toDouble()));
    wrapper.setProperty('second', JSNumber(value.second.toDouble()));
    wrapper.setProperty('millisecond', JSNumber(value.millisecond.toDouble()));
  } else if (value is JSTemporalPlainDateTime) {
    wrapper.setProperty(
      'add',
      JSNativeFunction(
        functionName: 'add',
        nativeImpl: (args) {
          if (args.isEmpty || args[0] is! JSObject) {
            throw JSTypeError('add requires an object argument');
          }
          final obj = args[0] as JSObject;
          return _wrapTemporalObject(
            value.add(
              obj.getProperty('years').toNumber().toInt(),
              obj.getProperty('months').toNumber().toInt(),
              obj.getProperty('days').toNumber().toInt(),
              obj.getProperty('hours').toNumber().toInt(),
              obj.getProperty('minutes').toNumber().toInt(),
              obj.getProperty('seconds').toNumber().toInt(),
              obj.getProperty('milliseconds').toNumber().toInt(),
            ),
          );
        },
      ),
    );
    wrapper.setProperty(
      'subtract',
      JSNativeFunction(
        functionName: 'subtract',
        nativeImpl: (args) {
          if (args.isEmpty || args[0] is! JSObject) {
            throw JSTypeError('subtract requires an object argument');
          }
          final obj = args[0] as JSObject;
          return _wrapTemporalObject(
            value.subtract(
              obj.getProperty('years').toNumber().toInt(),
              obj.getProperty('months').toNumber().toInt(),
              obj.getProperty('days').toNumber().toInt(),
              obj.getProperty('hours').toNumber().toInt(),
              obj.getProperty('minutes').toNumber().toInt(),
              obj.getProperty('seconds').toNumber().toInt(),
              obj.getProperty('milliseconds').toNumber().toInt(),
            ),
          );
        },
      ),
    );
    wrapper.setProperty(
      'compare',
      JSNativeFunction(
        functionName: 'compare',
        nativeImpl: (args) {
          if (args.isEmpty) throw JSTypeError('compare requires an argument');
          late JSTemporalPlainDateTime other;
          if (args[0] is JSTemporalPlainDateTime) {
            other = args[0] as JSTemporalPlainDateTime;
          } else if (args[0] is JSObject) {
            final obj = args[0] as JSObject;
            if (obj.hasProperty('__value') &&
                obj.getProperty('__value') is JSTemporalPlainDateTime) {
              other = obj.getProperty('__value') as JSTemporalPlainDateTime;
            } else {
              throw JSTypeError('Invalid argument to compare');
            }
          } else {
            throw JSTypeError('Invalid argument to compare');
          }
          return JSNumber(value.compare(other).toDouble());
        },
      ),
    );
    // Copy date and time properties
    wrapper.setProperty('year', JSNumber(value.date.year.toDouble()));
    wrapper.setProperty('month', JSNumber(value.date.month.toDouble()));
    wrapper.setProperty('day', JSNumber(value.date.day.toDouble()));
    wrapper.setProperty('hour', JSNumber(value.time.hour.toDouble()));
    wrapper.setProperty('minute', JSNumber(value.time.minute.toDouble()));
    wrapper.setProperty('second', JSNumber(value.time.second.toDouble()));
    wrapper.setProperty(
      'millisecond',
      JSNumber(value.time.millisecond.toDouble()),
    );
  }

  // Copy toString as a method
  wrapper.setProperty(
    'toString',
    JSNativeFunction(
      functionName: 'toString',
      nativeImpl: (_) => JSValueFactory.string(value.toString()),
    ),
  );

  return wrapper;
}

JSObject getTemporalNamespace() {
  final temporal = JSObject();

  // Temporal.now
  final now = JSObject();
  now.setProperty(
    'instant',
    JSNativeFunction(
      functionName: 'Temporal.now.instant',
      nativeImpl: (_) => JSTemporalInstant.now(),
    ),
  );
  now.setProperty(
    'plainDateISO',
    JSNativeFunction(
      functionName: 'Temporal.now.plainDateISO',
      nativeImpl: (_) {
        final today = DateTime.now();
        return JSTemporalPlainDate(
          year: today.year,
          month: today.month,
          day: today.day,
        );
      },
    ),
  );
  now.setProperty(
    'plainTimeISO',
    JSNativeFunction(
      functionName: 'Temporal.now.plainTimeISO',
      nativeImpl: (_) {
        final now = DateTime.now();
        return JSTemporalPlainTime(
          hour: now.hour,
          minute: now.minute,
          second: now.second,
          millisecond: now.millisecond,
        );
      },
    ),
  );
  now.setProperty(
    'plainDateTimeISO',
    JSNativeFunction(
      functionName: 'Temporal.now.plainDateTimeISO',
      nativeImpl: (_) {
        final now = DateTime.now();
        return JSTemporalPlainDateTime(
          date: JSTemporalPlainDate(
            year: now.year,
            month: now.month,
            day: now.day,
          ),
          time: JSTemporalPlainTime(
            hour: now.hour,
            minute: now.minute,
            second: now.second,
            millisecond: now.millisecond,
          ),
        );
      },
    ),
  );
  temporal.setProperty('now', now);

  // Constructors
  temporal.setProperty(
    'PlainDate',
    JSNativeFunction(
      functionName: 'Temporal.PlainDate',
      nativeImpl: (args) {
        final year = args.isNotEmpty ? args[0].toNumber().toInt() : 1;
        final month = args.length > 1 ? args[1].toNumber().toInt() : 1;
        final day = args.length > 2 ? args[2].toNumber().toInt() : 1;
        final date = JSTemporalPlainDate(year: year, month: month, day: day);
        return _wrapTemporalObject(date);
      },
    ),
  );

  temporal.setProperty(
    'PlainTime',
    JSNativeFunction(
      functionName: 'Temporal.PlainTime',
      nativeImpl: (args) {
        final hour = args.isNotEmpty ? args[0].toNumber().toInt() : 0;
        final minute = args.length > 1 ? args[1].toNumber().toInt() : 0;
        final second = args.length > 2 ? args[2].toNumber().toInt() : 0;
        final millisecond = args.length > 3 ? args[3].toNumber().toInt() : 0;
        final time = JSTemporalPlainTime(
          hour: hour,
          minute: minute,
          second: second,
          millisecond: millisecond,
        );
        return _wrapTemporalObject(time);
      },
    ),
  );

  temporal.setProperty(
    'PlainDateTime',
    JSNativeFunction(
      functionName: 'Temporal.PlainDateTime',
      nativeImpl: (args) {
        final year = args.isNotEmpty ? args[0].toNumber().toInt() : 1;
        final month = args.length > 1 ? args[1].toNumber().toInt() : 1;
        final day = args.length > 2 ? args[2].toNumber().toInt() : 1;
        final hour = args.length > 3 ? args[3].toNumber().toInt() : 0;
        final minute = args.length > 4 ? args[4].toNumber().toInt() : 0;
        final second = args.length > 5 ? args[5].toNumber().toInt() : 0;
        final millisecond = args.length > 6 ? args[6].toNumber().toInt() : 0;

        final date = JSTemporalPlainDate(year: year, month: month, day: day);
        final time = JSTemporalPlainTime(
          hour: hour,
          minute: minute,
          second: second,
          millisecond: millisecond,
        );
        final dt = JSTemporalPlainDateTime(date: date, time: time);
        return _wrapTemporalObject(dt);
      },
    ),
  );

  temporal.setProperty(
    'PlainYearMonth',
    JSNativeFunction(
      functionName: 'Temporal.PlainYearMonth',
      nativeImpl: (args) {
        final year = args.isNotEmpty ? args[0].toNumber().toInt() : 1;
        final month = args.length > 1 ? args[1].toNumber().toInt() : 1;
        return JSTemporalPlainYearMonth(year: year, month: month);
      },
    ),
  );

  temporal.setProperty(
    'PlainMonthDay',
    JSNativeFunction(
      functionName: 'Temporal.PlainMonthDay',
      nativeImpl: (args) {
        final month = args.isNotEmpty ? args[0].toNumber().toInt() : 1;
        final day = args.length > 1 ? args[1].toNumber().toInt() : 1;
        return JSTemporalPlainMonthDay(month: month, day: day);
      },
    ),
  );

  temporal.setProperty(
    'Duration',
    JSNativeFunction(
      functionName: 'Temporal.Duration',
      nativeImpl: (args) {
        if (args.isNotEmpty && args[0] is JSObject) {
          final obj = args[0] as JSObject;
          return JSTemporalDuration(
            years: obj.getProperty('years').toNumber().toInt(),
            months: obj.getProperty('months').toNumber().toInt(),
            weeks: obj.getProperty('weeks').toNumber().toInt(),
            days: obj.getProperty('days').toNumber().toInt(),
            hours: obj.getProperty('hours').toNumber().toInt(),
            minutes: obj.getProperty('minutes').toNumber().toInt(),
            seconds: obj.getProperty('seconds').toNumber().toInt(),
            milliseconds: obj.getProperty('milliseconds').toNumber().toInt(),
          );
        }
        return JSTemporalDuration();
      },
    ),
  );

  temporal.setProperty(
    'Instant',
    JSNativeFunction(
      functionName: 'Temporal.Instant',
      nativeImpl: (args) {
        final ns = args.isNotEmpty ? args[0].toNumber().toInt() : 0;
        return JSTemporalInstant(epochNanoseconds: ns);
      },
    ),
  );

  temporal.setProperty(
    'ZonedDateTime',
    JSNativeFunction(
      functionName: 'Temporal.ZonedDateTime',
      nativeImpl: (args) {
        if (args.length < 2) {
          throw JSTypeError('ZonedDateTime requires at least 2 arguments');
        }

        final instant = args[0] is JSTemporalInstant
            ? args[0] as JSTemporalInstant
            : JSTemporalInstant(epochNanoseconds: args[0].toNumber().toInt());

        final timeZone = args[1].toString();

        final ms = instant.epochNanoseconds ~/ 1000000;
        final dt = DateTime.fromMillisecondsSinceEpoch(ms);

        final date = JSTemporalPlainDate(
          year: dt.year,
          month: dt.month,
          day: dt.day,
        );
        final time = JSTemporalPlainTime(
          hour: dt.hour,
          minute: dt.minute,
          second: dt.second,
          millisecond: dt.millisecond,
        );

        return JSTemporalZonedDateTime(
          plainDateTime: JSTemporalPlainDateTime(date: date, time: time),
          timeZone: timeZone,
        );
      },
    ),
  );

  return temporal;
}
