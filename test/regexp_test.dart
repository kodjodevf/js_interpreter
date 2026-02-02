import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('RegExp Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('RegExp Constructor', () {
      test('should create RegExp with pattern only', () {
        final result = interpreter.eval('new RegExp("hello")');
        expect(result.toString(), equals('/hello/'));
      });

      test('should create RegExp with pattern and flags', () {
        final result = interpreter.eval('new RegExp("hello", "gi")');
        expect(result.toString(), equals('/hello/gi'));
      });

      test('should handle empty pattern', () {
        final result = interpreter.eval('new RegExp("")');
        expect(result.toString(), equals('//'));
      });
    });

    group('RegExp Properties', () {
      test('should have correct source property', () {
        interpreter.eval('var regex = new RegExp("test")');
        final source = interpreter.eval('regex.source');
        expect(source.toString(), equals('test'));
      });

      test('should have correct flags property', () {
        interpreter.eval('var regex = new RegExp("test", "gim")');
        final flags = interpreter.eval('regex.flags');
        expect(flags.toString(), equals('gim'));
      });

      test('should have correct boolean flag properties', () {
        interpreter.eval('var regex = new RegExp("test", "gi")');

        final global = interpreter.eval('regex.global');
        expect(global.toBoolean(), isTrue);

        final ignoreCase = interpreter.eval('regex.ignoreCase');
        expect(ignoreCase.toBoolean(), isTrue);

        final multiline = interpreter.eval('regex.multiline');
        expect(multiline.toBoolean(), isFalse);
      });
    });

    group('RegExp test() method', () {
      test('should return true for matching strings', () {
        interpreter.eval('var regex = new RegExp("hello", "i")');
        final result = interpreter.eval('regex.test("Hello World")');
        expect(result.toBoolean(), isTrue);
      });

      test('should return false for non-matching strings', () {
        interpreter.eval('var regex = new RegExp("hello")');
        final result = interpreter.eval('regex.test("goodbye")');
        expect(result.toBoolean(), isFalse);
      });

      test('should respect case sensitivity', () {
        interpreter.eval('var regex = new RegExp("hello")');
        final result = interpreter.eval('regex.test("Hello")');
        expect(result.toBoolean(), isFalse);
      });

      test('should ignore case with i flag', () {
        interpreter.eval('var regex = new RegExp("hello", "i")');
        final result = interpreter.eval('regex.test("HELLO")');
        expect(result.toBoolean(), isTrue);
      });
    });

    group('RegExp exec() method', () {
      test('should return match array for matching strings', () {
        interpreter.eval('var regex = new RegExp("hello", "i")');
        interpreter.eval('var result = regex.exec("Hello World")');

        final match = interpreter.eval('result[0]');
        expect(match.toString(), equals('Hello'));

        final index = interpreter.eval('result.index');
        expect(index.toNumber(), equals(0));

        final input = interpreter.eval('result.input');
        expect(input.toString(), equals('Hello World'));
      });

      test('should return null for non-matching strings', () {
        interpreter.eval('var regex = new RegExp("hello")');
        final result = interpreter.eval('regex.exec("goodbye")');
        expect(result.isNull, isTrue);
      });

      test('should capture groups', () {
        interpreter.eval('var regex = new RegExp("(\\\\w+)\\\\s+(\\\\w+)")');
        interpreter.eval('var result = regex.exec("Hello World")');

        final fullMatch = interpreter.eval('result[0]');
        expect(fullMatch.toString(), equals('Hello World'));

        final group1 = interpreter.eval('result[1]');
        expect(group1.toString(), equals('Hello'));

        final group2 = interpreter.eval('result[2]');
        expect(group2.toString(), equals('World'));
      });
    });

    group('RegExp Global Flag', () {
      test('should handle global flag with test()', () {
        interpreter.eval('var regex = new RegExp("a", "g")');
        final result1 = interpreter.eval('regex.test("aaa")');
        expect(result1.toBoolean(), isTrue);

        final result2 = interpreter.eval('regex.test("aaa")');
        expect(result2.toBoolean(), isTrue);
      });
    });

    group('RegExp Edge Cases', () {
      test('should handle special regex characters', () {
        interpreter.eval(r'var regex = new RegExp("\\d+")');
        final result = interpreter.eval('regex.test("123")');
        expect(result.toBoolean(), isTrue);
      });

      test('should handle regex with dots', () {
        interpreter.eval('var regex = new RegExp("a.b")');
        final result = interpreter.eval('regex.test("axb")');
        expect(result.toBoolean(), isTrue);
      });
    });
  });
}
