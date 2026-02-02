import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('Multi-line new expression tests', () {
    test('Simple new with argument on same line', () {
      final interpreter = JSInterpreter();

      final code = '''
        function MyError(msg) {
          this.message = msg;
        }
        
        throw new MyError('test');
      ''';

      expect(() => interpreter.eval(code), throwsA(isA<Exception>()));
    });

    test('New with argument on next line', () {
      final interpreter = JSInterpreter();

      final code = '''
        function MyError(msg) {
          this.message = msg;
        }
        
        throw new MyError(
          'test'
        );
      ''';

      expect(() => interpreter.eval(code), throwsA(isA<Exception>()));
    });

    test('New TypeError multi-line', () {
      final interpreter = JSInterpreter();

      final code = '''
        var arg = 42;
        var encodingOrOffset = 'utf8';
        
        if (typeof arg === 'number') {
          if (typeof encodingOrOffset === 'string') {
            throw new TypeError(
              'The "string" argument must be of type string. Received type number'
            )
          }
        }
      ''';

      expect(() => interpreter.eval(code), throwsA(isA<Exception>()));
    });

    test('New with multiple arguments multi-line', () {
      final interpreter = JSInterpreter();

      final code = '''
        function MyClass(a, b, c) {
          this.a = a;
          this.b = b;
          this.c = c;
        }
        
        var obj = new MyClass(
          1,
          2,
          3
        );
        
        obj.a;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(1));
    });
  });
}
