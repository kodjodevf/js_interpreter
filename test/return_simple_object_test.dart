import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  test('return objet littéral simple', () {
    final interpreter = JSInterpreter();

    final code = r'''
      function test() {
        return {a: 1, b: 2};
      }
      test();
    ''';

    print('Test: return objet simple');
    try {
      final result = interpreter.eval(code);
      print('✅ Réussi! Type: ${result.type}');
    } catch (e) {
      print('❌ Erreur: $e');
      rethrow;
    }
  });
}
