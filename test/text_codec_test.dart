import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('TextEncoder/TextDecoder Support', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('TextEncoder basic encoding', () {
      final result = interpreter.eval('''
        const encoder = new TextEncoder();
        const bytes = encoder.encode('Hello');
        bytes.length
      ''');
      expect(result.toString(), '5');
    });

    test('TextEncoder encoding ASCII', () {
      final result = interpreter.eval('''
        const encoder = new TextEncoder();
        const bytes = encoder.encode('ABC');
        [bytes[0], bytes[1], bytes[2]]
      ''');
      expect(result.toString(), '65,66,67');
    });

    test('TextEncoder encoding UTF-8', () {
      final result = interpreter.eval('''
        const encoder = new TextEncoder();
        const bytes = encoder.encode('café');
        bytes.length
      ''');
      expect(result.toString(), '5'); // c=1, a=1, f=1, é=2 bytes in UTF-8
    });

    test('TextEncoder encoding empty string', () {
      final result = interpreter.eval('''
        const encoder = new TextEncoder();
        const bytes = encoder.encode('');
        bytes.length
      ''');
      expect(result.toString(), '0');
    });

    test('TextEncoder properties', () {
      final result = interpreter.eval('''
        const encoder = new TextEncoder();
        encoder.encoding
      ''');
      expect(result.toString(), 'utf-8');
    });

    test('TextEncoder encodeInto', () {
      final result = interpreter.eval('''
        const encoder = new TextEncoder();
        const dest = [];
        const result = encoder.encodeInto('Hello', dest);
        [result.read, result.written]
      ''');
      expect(result.toString(), '5,5');
    });

    test('TextDecoder basic decoding', () {
      final result = interpreter.eval('''
        const decoder = new TextDecoder();
        const bytes = [72, 101, 108, 108, 111]; // "Hello"
        const text = decoder.decode(bytes);
        text
      ''');
      expect(result.toString(), 'Hello');
    });

    test('TextDecoder decoding UTF-8', () {
      final result = interpreter.eval('''
        const decoder = new TextDecoder();
        const bytes = [99, 97, 102, 195, 169]; // "café"
        const text = decoder.decode(bytes);
        text
      ''');
      expect(result.toString(), 'café');
    });

    test('TextDecoder decoding empty array', () {
      final result = interpreter.eval('''
        const decoder = new TextDecoder();
        const text = decoder.decode([]);
        text
      ''');
      expect(result.toString(), '');
    });

    test('TextDecoder properties', () {
      final result = interpreter.eval('''
        const decoder = new TextDecoder();
        [decoder.encoding, decoder.fatal, decoder.ignoreBOM]
      ''');
      expect(result.toString(), 'utf-8,false,false');
    });

    test('TextDecoder with options', () {
      final result = interpreter.eval('''
        const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });
        [decoder.encoding, decoder.fatal, decoder.ignoreBOM]
      ''');
      expect(result.toString(), 'utf-8,true,true');
    });

    test('TextDecoder round trip', () {
      final result = interpreter.eval('''
        const encoder = new TextEncoder();
        const decoder = new TextDecoder();

        const original = 'Hello, 世界! 🌍';
        const bytes = encoder.encode(original);
        const decoded = decoder.decode(bytes);

        decoded === original
      ''');
      expect(result.toString(), 'true');
    });

    test('TextDecoder invalid encoding throws error', () {
      expect(
        () => interpreter.eval('new TextDecoder("invalid")'),
        throwsA(isA<JSError>()),
      );
    });

    test('TextEncoder encodeInto with small buffer', () {
      final result = interpreter.eval('''
        const encoder = new TextEncoder();
        const dest = [];
        const result = encoder.encodeInto('Hi', dest);
        [result.read, result.written]
      ''');
      expect(result.toString(), '2,2');
    });

    test('TextDecoder with undefined input', () {
      final result = interpreter.eval('''
        const decoder = new TextDecoder();
        const text = decoder.decode();
        text
      ''');
      expect(result.toString(), '');
    });

    test('TextEncoder/TextDecoder integration', () {
      final result = interpreter.eval('''
        // Encoder du texte
        const encoder = new TextEncoder();
        const bytes = encoder.encode('Test 123');

        // Decode the text
        const decoder = new TextDecoder();
        const decoded = decoder.decode(bytes);

        // Check that it's identical
        decoded
      ''');
      expect(result.toString(), 'Test 123');
    });
  });
}
