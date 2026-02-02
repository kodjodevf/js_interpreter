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
  });
}
