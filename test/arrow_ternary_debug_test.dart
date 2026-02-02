import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('Debug arrow function dans ternaire', () {
    test('Arrow function seule', () {
      final interpreter = JSInterpreter();

      final code = r'''
        var fn = (x) => x * 2;
        fn(5);
      ''';

      final result = interpreter.eval(code);
      print('✅ Arrow function seule: ${result.toNumber()}');
      expect(result.toNumber(), equals(10));
    });

    test('Ternaire avec valeurs simples', () {
      final interpreter = JSInterpreter();

      final code = r'''
        var fn = true ? 10 : 20;
        fn;
      ''';

      final result = interpreter.eval(code);
      print('✅ Ternaire simple: ${result.toNumber()}');
      expect(result.toNumber(), equals(10));
    });

    test('Ternaire avec arrow function AVANT les deux-points', () {
      final interpreter = JSInterpreter();

      final code = r'''
        var fn = false ? (x) => x * 2 : 99;
        fn;
      ''';

      print('Test: arrow function avant :');
      try {
        final result = interpreter.eval(code);
        print('✅ Résultat: ${result.toNumber()}');
        expect(result.toNumber(), equals(99));
      } catch (e) {
        print('❌ Erreur: $e');
        rethrow;
      }
    });

    test('Ternaire avec arrow function APRÈS les deux-points', () {
      final interpreter = JSInterpreter();

      final code = r'''
        var fn = true ? 99 : (x) => x * 2;
        fn;
      ''';

      print('Test: arrow function après :');
      try {
        final result = interpreter.eval(code);
        print('✅ Résultat: ${result.toNumber()}');
        expect(result.toNumber(), equals(99));
      } catch (e) {
        print('❌ Erreur: $e');
        rethrow;
      }
    });
  });
}
