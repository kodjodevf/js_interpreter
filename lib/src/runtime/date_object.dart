/// Date Object implementation for JavaScript
/// Provides complete Date functionality
library;

import 'js_value.dart';
import 'native_functions.dart';

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
            try {
              final parsed = DateTime.parse(arg.toString());
              return JSDate(parsed);
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

          try {
            final dateStr = args[0].toString();
            final parsed = DateTime.parse(dateStr);
            return JSValueFactory.number(
              parsed.millisecondsSinceEpoch.toDouble(),
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

          try {
            final year = args.isNotEmpty ? args[0].toNumber().floor() : 1970;
            final month = args.length > 1 ? args[1].toNumber().floor() + 1 : 1;
            final day = args.length > 2 ? args[2].toNumber().floor() : 1;
            final hour = args.length > 3 ? args[3].toNumber().floor() : 0;
            final minute = args.length > 4 ? args[4].toNumber().floor() : 0;
            final second = args.length > 5 ? args[5].toNumber().floor() : 0;
            final millisecond = args.length > 6
                ? args[6].toNumber().floor()
                : 0;

            final date = DateTime.utc(
              year,
              month,
              day,
              hour,
              minute,
              second,
              millisecond,
            );
            return JSValueFactory.number(
              date.millisecondsSinceEpoch.toDouble(),
            );
          } catch (e) {
            return JSValueFactory.number(double.nan);
          }
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
    return _dateTime.toIso8601String();
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
          return JSValueFactory.string(_dateTime.toUtc().toIso8601String());
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
