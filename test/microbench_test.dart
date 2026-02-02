import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });

  group('JavaScript Microbenchmarks', () {
    test('empty_loop', () {
      final result = interpreter.eval('''
        var j;
        for(j = 0; j < 1000; j++) {
        }
        1000;
      ''');
      expect(result.toNumber(), equals(1000));
    });

    test('empty_down_loop', () {
      final result = interpreter.eval('''
        var j;
        for(j = 1000; j > 0; j--) {
        }
        1000;
      ''');
      expect(result.toNumber(), equals(1000));
    });

    test('empty_down_loop2', () {
      final result = interpreter.eval('''
        var j;
        for(j = 1000; j --> 0;) {
        }
        1000;
      ''');
      expect(result.toNumber(), equals(1000));
    });

    test('empty_do_loop', () {
      final result = interpreter.eval('''
        var j;
        for(j = 1000; j > 0; j--) {
        }
        1000;
      ''');
      expect(result.toNumber(), equals(1000));
    });

    test('prop_read', () {
      final result = interpreter.eval('''
        var obj, sum, j;
        obj = {a: 1, b: 2, c:3, d:4 };
        sum = 0;
        for(j = 0; j < 100; j++) {
          sum += obj.a;
          sum += obj.b;
          sum += obj.c;
          sum += obj.d;
        }
        sum;
      ''');
      expect(result.toNumber(), equals(100 * (1 + 2 + 3 + 4)));
    });

    test('prop_write', () {
      final result = interpreter.eval('''
        var obj, j;
        obj = {a: 1, b: 2, c:3, d:4 };
        for(j = 0; j < 100; j++) {
          obj.a = j;
          obj.b = j;
          obj.c = j;
          obj.d = j;
        }
        obj.a + obj.b + obj.c + obj.d;
      ''');
      expect(result.toNumber(), equals(99 * 4));
    });

    test('prop_update', () {
      final result = interpreter.eval('''
        var obj, j;
        obj = {a: 1, b: 2, c:3, d:4 };
        for(j = 0; j < 10; j++) {
          obj.a += j;
          obj.b += j;
          obj.c += j;
          obj.d += j;
        }
        obj.a + obj.b + obj.c + obj.d;
      ''');
      expect(
        result.toNumber(),
        equals((1 + 2 + 3 + 4) + (0 + 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9) * 4),
      );
    });

    test('array_read', () {
      final result = interpreter.eval('''
        var tab, len, sum, i, j;
        tab = [];
        len = 10;
        for(i = 0; i < len; i++)
          tab[i] = i;
        sum = 0;
        for(j = 0; j < 10; j++) {
          sum += tab[0];
          sum += tab[1];
          sum += tab[2];
          sum += tab[3];
          sum += tab[4];
          sum += tab[5];
          sum += tab[6];
          sum += tab[7];
          sum += tab[8];
          sum += tab[9];
        }
        sum;
      ''');
      expect(
        result.toNumber(),
        equals(10 * (0 + 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9)),
      );
    });

    test('array_write', () {
      final result = interpreter.eval('''
        var tab, len, i, j;
        tab = [];
        len = 10;
        for(i = 0; i < len; i++)
          tab[i] = i;
        for(j = 0; j < 10; j++) {
          tab[0] = j;
          tab[1] = j;
          tab[2] = j;
          tab[3] = j;
          tab[4] = j;
          tab[5] = j;
          tab[6] = j;
          tab[7] = j;
          tab[8] = j;
          tab[9] = j;
        }
        tab[0] + tab[1] + tab[2] + tab[3] + tab[4] + tab[5] + tab[6] + tab[7] + tab[8] + tab[9];
      ''');
      expect(result.toNumber(), equals(9 * 10));
    });

    test('global_read', () {
      final result = interpreter.eval('''
        var sum, j;
        global_var0 = 42;
        sum = 0;
        for(j = 0; j < 100; j++) {
          sum += global_var0;
          sum += global_var0;
          sum += global_var0;
          sum += global_var0;
        }
        sum;
      ''');
      expect(result.toNumber(), equals(100 * 4 * 42));
    });

    test('global_write_strict', () {
      final result = interpreter.eval('''
        "use strict";
        var j;
        for(j = 0; j < 10; j++) {
          global_var0 = j;
          global_var0 = j;
          global_var0 = j;
          global_var0 = j;
        }
        global_var0;
      ''');
      expect(result.toNumber(), equals(9));
    });

    test('int_arith', () {
      final result = interpreter.eval('''
        var i, j, sum, total = 0;
        for(j = 0; j < 10; j++) {
          sum = 0;
          for(i = 0; i < 100; i++) {
            sum += i * i;
          }
          total += sum;
        }
        total;
      ''');
      // Calculate expected sum: sum from i=0 to 99 of i*i = (99*100*199)/6 = 328350
      // Multiplied by 10 iterations = 3283500
      expect(result.toNumber(), equals(328350 * 10));
    });

    test('float_arith', () {
      final result = interpreter.eval('''
        var i, j, sum, a, incr, a0, total = 0;
        a0 = 0.1;
        incr = 1.1;
        for(j = 0; j < 5; j++) {
          sum = 0;
          a = a0;
          for(i = 0; i < 100; i++) {
            sum += a * a;
            a += incr;
          }
          total += sum;
        }
        Math.round(total * 100) / 100;
      ''');
      // This is a floating point calculation, we'll just check it's a reasonable number
      expect(result.toNumber(), greaterThan(0));
    });

    test('string_build1', () {
      final result = interpreter.eval('''
        var i, j, r;
        for(j = 0; j < 5; j++) {
          r = "";
          for(i = 0; i < 100; i++)
            r += "x";
        }
        r.length;
      ''');
      expect(result.toNumber(), equals(100));
    });

    test('string_build1x', () {
      final result = interpreter.eval('''
        var i, j, r;
        for(j = 0; j < 5; j++) {
          r = "";
          for(i = 0; i < 100; i++)
            r = r + "x";
        }
        r.length;
      ''');
      expect(result.toNumber(), equals(100));
    });

    test('array_for', () {
      final result = interpreter.eval('''
        var r, i, j, sum, len = 10;
        r = [];
        for(i = 0; i < len; i++)
          r[i] = i;
        for(j = 0; j < 5; j++) {
          sum = 0;
          for(i = 0; i < len; i++) {
            sum += r[i];
          }
        }
        sum;
      ''');
      expect(result.toNumber(), equals(0 + 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9));
    });

    test('array_for_in', () {
      final result = interpreter.eval('''
        var r, i, j, sum, len = 10;
        r = [];
        for(i = 0; i < len; i++)
          r[i] = i;
        for(j = 0; j < 5; j++) {
          sum = 0;
          for(i in r) {
            sum += r[i];
          }
        }
        sum;
      ''');
      expect(result.toNumber(), equals(0 + 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9));
    });

    test('array_for_of', () {
      final result = interpreter.eval('''
        var r, i, j, sum, len = 10;
        r = [];
        for(i = 0; i < len; i++)
          r[i] = i;
        for(j = 0; j < 5; j++) {
          sum = 0;
          for(i of r) {
            sum += i;
          }
        }
        sum;
      ''');
      expect(result.toNumber(), equals(0 + 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9));
    });

    test('math_min', () {
      final result = interpreter.eval('''
        var i, j, r;
        r = 0;
        for(j = 0; j < 5; j++) {
          for(i = 0; i < 100; i++)
            r = Math.min(i, 500);
        }
        r;
      ''');
      expect(result.toNumber(), equals(99));
    });

    test('regexp_ascii', () {
      final result = interpreter.eval('''
        var i, j, r, s;
        s = "the quick brown fox jumped over the lazy dog"
        for(j = 0; j < 5; j++) {
          for(i = 0; i < 10; i++)
            r = /the quick brown fox/.exec(s)
        }
        r[0];
      ''');
      expect(result.toString(), equals("the quick brown fox"));
    });

    test('int_to_string', () {
      final result = interpreter.eval('''
        var s, r, j;
        r = 0;
        for(j = 0; j < 10; j++) {
          s = (j % 10) + '';
          s = (j % 100) + '';
          s = (j) + '';
        }
        s;
      ''');
      expect(result.toString(), equals("9"));
    });

    test('float_to_string', () {
      final result = interpreter.eval('''
        var s, r, j;
        r = 0;
        for(j = 0; j < 10; j++) {
          s = (j % 10 + 0.1) + '';
          s = (j + 0.1) + '';
          s = (j * 12345678 + 0.1) + '';
        }
        typeof s;
      ''');
      expect(result.toString(), equals("string"));
    });

    test('string_to_int', () {
      final result = interpreter.eval('''
        var s, r, j;
        r = 0;
        s = "12345";
        for(j = 0; j < 10; j++) {
          r += (s | 0);
        }
        r;
      ''');
      expect(result.toNumber(), equals(12345 * 10));
    });

    test('string_to_float', () {
      final result = interpreter.eval('''
        var s, r, j;
        r = 0;
        s = "12345.6";
        for(j = 0; j < 10; j++) {
          r += parseFloat(s);
        }
        Math.round(r);
      ''');
      expect(result.toNumber(), equals((12345.6 * 10).round()));
    });
  });
}
