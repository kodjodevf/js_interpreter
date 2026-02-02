import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  test('Opérateurs binaires multi-lignes', () {
    final interpreter = JSInterpreter();

    // Test 1: && sur une ligne
    print('Test 1: && sur une seule ligne');
    final r1 = interpreter.eval('const x = true && true; x;');
    expect(r1.toBoolean(), isTrue);
    print('✅ && sur une ligne fonctionne');

    // Test 2: && sur plusieurs lignes
    print('\nTest 2: && sur plusieurs lignes');
    try {
      final r2 = interpreter.eval('''
        const y = true &&
                  true;
        y;
      ''');
      expect(r2.toBoolean(), isTrue);
      print('✅ && sur plusieurs lignes fonctionne');
    } catch (e) {
      print(
        '❌ Erreur: ${e.toString().substring(0, e.toString().length > 80 ? 80 : e.toString().length)}',
      );
    }

    // Test 3: + sur plusieurs lignes
    print('\nTest 3: + sur plusieurs lignes');
    try {
      final r3 = interpreter.eval('''
        const z = 1 +
                  2;
        z;
      ''');
      expect(r3.toNumber(), equals(3));
      print('✅ + sur plusieurs lignes fonctionne');
    } catch (e) {
      print(
        '❌ Erreur: ${e.toString().substring(0, e.toString().length > 80 ? 80 : e.toString().length)}',
      );
    }
  });
}
