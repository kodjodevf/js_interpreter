import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('Tests trailing comma dans objets', () {
    test('Objet simple avec trailing comma', () {
      final interpreter = JSInterpreter();

      final code = r'''
        var obj = {
          a: 1,
          b: 2,
        };
        obj.a;
      ''';

      try {
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(1));
      } catch (e) {
        rethrow;
      }
    });

    test('Objet avec trailing comma après expression complexe', () {
      final interpreter = JSInterpreter();

      final code = r'''
        var obj = {
          a: 1 + 2,
          b: true ? 3 : 4,
        };
        obj.b;
      ''';

      try {
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(3));
      } catch (e) {
        rethrow;
      }
    });
  });
}
