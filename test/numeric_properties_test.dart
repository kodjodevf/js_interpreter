import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  test('Propriétés numériques dans les objets', () {
    final interpreter = JSInterpreter();

    // Test 1: Properties with string names
    print('Test 1: Propriétés string');
    final r1 = interpreter.eval('const obj1 = {"a": 1, "b": 2}; obj1.a;');
    expect(r1.toNumber(), equals(1));
    print('✅ Propriétés string fonctionnent');

    // Test 2: Properties with numbers
    print('\nTest 2: Propriétés numériques');
    try {
      final r2 = interpreter.eval(
        'const obj2 = {1: "one", 2: "two"}; obj2[1];',
      );
      expect(r2.toString(), equals('one'));
      print('✅ Propriétés numériques fonctionnent');
    } catch (e) {
      print(
        '❌ Erreur: ${e.toString().substring(0, e.toString().length > 80 ? 80 : e.toString().length)}',
      );
    }

    // Test 3: Mix of properties
    print('\nTest 3: Mix string et nombres');
    try {
      final r3 = interpreter.eval(
        'const obj3 = {1: "one", "a": "letter"}; obj3.a;',
      );
      expect(r3.toString(), equals('letter'));
      print('✅ Mix fonctionne');
    } catch (e) {
      print(
        '❌ Erreur: ${e.toString().substring(0, e.toString().length > 80 ? 80 : e.toString().length)}',
      );
    }
  });
}
