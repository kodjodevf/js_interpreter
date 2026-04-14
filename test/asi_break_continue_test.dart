import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('Tests ASI pour break et continue', () {
    test('break avec accolades sans point-virgule', () {
      final interpreter = JSInterpreter();

      final code = r'''
        var x = 0;
        for (var i = 0; i < 10; i++) {
          if (i === 5) {
            break
          }
          x++;
        }
        x;
      ''';

      final result = interpreter.eval(code);
      print('✅ break avec accolades: ${result.toNumber()}');
      expect(result.toNumber(), equals(5));
    });

    test('break sans accolades (if one-liner)', () {
      final interpreter = JSInterpreter();

      final code = r'''
        var x = 0;
        for (var i = 0; i < 10; i++) {
          if (i === 5) break
          x++;
        }
        x;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(5));
    });

    test('Pattern exact ', () {
      final interpreter = JSInterpreter();

      final code = r'''
        var units = 10;
        var bytes = [];
        
        for (var i = 0; i < 20; i++) {
          if ((units -= 1) < 0) break
          bytes.push(i);
        }
        
        bytes.length;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(10));
    });

    test('continue sans accolades', () {
      final interpreter = JSInterpreter();

      final code = r'''
        var x = 0;
        for (var i = 0; i < 10; i++) {
          if (i === 5) continue
          x++;
        }
        x;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(9));
    });

    test('break sans label sort de la boucle meme avec un label interne', () {
      final interpreter = JSInterpreter();

      final code = r'''
        var count = 0;
        while (1) label: break
        count = 1;
        count;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(1));
    });

    test('break avec ASI dans un bloc labelise interne ne boucle pas', () {
      final interpreter = JSInterpreter();

      final code = r'''
        var i = 0;
        while (i < 3) label: {
          if (i > 0)
            break
          i++;
        }
        i;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(1));
    });

    test('Object.getOwnPropertyNames inclut length pour un tableau sparse', () {
      final interpreter = JSInterpreter();

      final result = interpreter.eval(
        r'Object.getOwnPropertyNames([ ...[ , ] ]).toString()',
      );
      expect(result.toString(), equals('0,length'));
    });
  });
}
