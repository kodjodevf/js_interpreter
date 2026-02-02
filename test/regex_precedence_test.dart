import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Regex with operator precedence', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('new RegExp().source without parentheses', () {
      final result = interpreter.eval('new RegExp("hello", "i").source');
      expect(result.toString(), equals("hello"));
    });

    test('new RegExp().flags without parentheses', () {
      final result = interpreter.eval('new RegExp("hello", "gi").flags');
      expect(result.toString(), equals("gi"));
    });

    test('new RegExp().test() without parentheses', () {
      final result = interpreter.eval(
        'new RegExp("hello").test("hello world")',
      );
      expect(result.toBoolean(), equals(true));
    });

    test('new RegExp().exec() without parentheses', () {
      final result = interpreter.eval('new RegExp("(\\\\w+)").exec("hello")');
      // For arrays, you must access properties specifically
      final array = result as JSObject;
      final item0 = array.getProperty('0');
      final item1 = array.getProperty('1');
      expect(item0.toString(), equals("hello"));
      expect(item1.toString(), equals("hello"));
    });

    test('chained property access on new RegExp', () {
      final result = interpreter.eval('''
        const r = new RegExp("test", "g");
        r.source + ":" + r.flags
      ''');
      expect(result.toString(), equals("test:g"));
    });

    test('new RegExp with regex literal comparison', () {
      final result = interpreter.eval('''
        const regex1 = new RegExp("hello", "i");
        const regex2 = /hello/i;
        regex1.source === regex2.source && regex1.flags === regex2.flags
      ''');
      expect(result.toBoolean(), equals(true));
    });
  });
}
