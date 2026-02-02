import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  test('Tableau avec trailing comma', () {
    final interpreter = JSInterpreter();

    final code = r'''
      var arr = [1, 2, 3,];
      arr[0];
    ''';

    print('Test: tableau avec trailing comma');
    try {
      final result = interpreter.eval(code);
      print('✅ Résultat: ${result.toNumber()}');
      expect(result.toNumber(), equals(1));
    } catch (e) {
      print('❌ Erreur: $e');
      rethrow;
    }
  });
}
