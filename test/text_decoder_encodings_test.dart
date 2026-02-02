import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('TextDecoder Encodings Support', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('UTF-8 encoding', () {
      final code = '''
        const decoder = new TextDecoder('utf-8');
        const bytes = [72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100];
        const result = decoder.decode(bytes);
        result;
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('Hello World'));
    });

    test('Latin1 encoding', () {
      final code = '''
        const decoder = new TextDecoder('latin1');
        const bytes = [72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100];
        const result = decoder.decode(bytes);
        result;
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('Hello World'));
    });

    test('ASCII encoding', () {
      final code = '''
        const decoder = new TextDecoder('ascii');
        const bytes = [72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100];
        const result = decoder.decode(bytes);
        result;
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('Hello World'));
    });

    test('Unsupported encoding throws error', () {
      final code = '''
        try {
          const decoder = new TextDecoder('unsupported-encoding');
          'no error';
        } catch (e) {
          e.message;
        }
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('not supported'));
    });

    test('Fatal option with invalid UTF-8', () {
      final code = '''
        try {
          const decoder = new TextDecoder('utf-8', { fatal: true });
          // Bytes with invalid UTF-8 sequence
          const bytes = [255, 254, 253];
          decoder.decode(bytes);
          'no error';
        } catch (e) {
          e.message;
        }
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('invalid UTF-8'));
    });

    test('Non-fatal option with invalid UTF-8', () {
      final code = '''
        const decoder = new TextDecoder('utf-8', { fatal: false });
        // Bytes with invalid UTF-8 sequence
        const bytes = [255, 254, 253];
        const result = decoder.decode(bytes);
        result.length > 0; // Should return replacement characters
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('true'));
    });
  });
}
