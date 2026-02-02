import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('get keyword as identifier', () {
    test('get as variable name', () {
      final js = JSInterpreter();
      expect(() => js.eval('var get = 42;'), returnsNormally);
      final result = js.eval('get');
      expect(result.toNumber(), equals(42));
    });

    test('get as function name', () {
      final js = JSInterpreter();
      expect(() => js.eval('function get() { return 123; }'), returnsNormally);
      final result = js.eval('get()');
      expect(result.toNumber(), equals(123));
    });

    test('get in exports pattern', () {
      final js = JSInterpreter();
      expect(
        () => js.eval('''
        var exports = {};
        function get() { return "value"; }
        exports.get = get;
      '''),
        returnsNormally,
      );
      final result = js.eval('exports.get()');
      expect(result.toString(), equals('value'));
    });

    test('get as object property', () {
      final js = JSInterpreter();
      expect(
        () => js.eval('''
        var obj = { get: 100 };
      '''),
        returnsNormally,
      );
      final result = js.eval('obj.get');
      expect(result.toNumber(), equals(100));
    });
  });
}
