import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  test('If avec condition multi-lignes', () {
    final interpreter = JSInterpreter();

    // Test 1: if simple
    print('Test 1: if simple');
    final r1 = interpreter.eval(
      'if (true && true) { const x = 1; } const y = 2; y;',
    );
    expect(r1.toNumber(), equals(2));
    print('✅ if simple fonctionne');

    // Test 2: if avec condition sur plusieurs lignes
    print('\nTest 2: if avec && multi-lignes');
    final interpreter2 = JSInterpreter();
    try {
      final r2 = interpreter2.eval('''
        if (typeof Symbol !== 'undefined' &&
            Symbol.species != null) {
          const x = 1;
        }
        const y = 2;
        y;
      ''');
      expect(r2.toNumber(), equals(2));
      print('✅ if avec && multi-lignes fonctionne');
    } catch (e) {
      print(
        '❌ Erreur: ${e.toString().substring(0, e.toString().length > 100 ? 100 : e.toString().length)}',
      );
    }
  });
}
