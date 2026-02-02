import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('String.prototype.replaceAll() Implementation', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('String.prototype.replaceAll() with string search value', () {
      final result = interpreter.eval('''
        const str = 'hello world hello';
        str.replaceAll('hello', 'hi')
      ''');

      expect(result.toString(), equals('hi world hi'));
    });

    test('String.prototype.replaceAll() with no matches', () {
      final result = interpreter.eval('''
        const str = 'hello world';
        str.replaceAll('xyz', 'abc')
      ''');

      expect(result.toString(), equals('hello world'));
    });

    test('String.prototype.replaceAll() with RegExp', () {
      final result = interpreter.eval('''
        const str = 'test123test456';
        str.replaceAll(/\\d+/g, 'NUM')
      ''');

      expect(result.toString(), equals('testNUMtestNUM'));
    });

    test('String.prototype.replaceAll() with empty string', () {
      final result = interpreter.eval('''
        const str = 'abc';
        str.replaceAll('', '-')
      ''');

      expect(result.toString(), equals('-a-b-c-'));
    });

    test('String.prototype.replaceAll() throws on insufficient arguments', () {
      expect(
        () => interpreter.eval('"test".replaceAll("t")'),
        throwsA(isA<JSException>()),
      );
    });
  });
}
