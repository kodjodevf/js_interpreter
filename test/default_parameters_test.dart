import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Default Parameters Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('should support default parameters in function declarations', () {
      interpreter.eval('''
        function greet(name = "World", prefix = "Hello") {
          return prefix + ", " + name + "!";
        }
      ''');

      final result1 = interpreter.eval('greet()');
      expect(result1.toString(), equals('Hello, World!'));

      final result2 = interpreter.eval('greet("Alice")');
      expect(result2.toString(), equals('Hello, Alice!'));

      final result3 = interpreter.eval('greet("Bob", "Hi")');
      expect(result3.toString(), equals('Hi, Bob!'));
    });

    test('should support default parameters in function expressions', () {
      interpreter.eval('''
        const greet = function(name = "World", prefix = "Hello") {
          return prefix + ", " + name + "!";
        };
      ''');

      final result1 = interpreter.eval('greet()');
      expect(result1.toString(), equals('Hello, World!'));

      final result2 = interpreter.eval('greet("Alice")');
      expect(result2.toString(), equals('Hello, Alice!'));
    });

    test('should support mixed parameters with and without defaults', () {
      interpreter.eval('''
        function test(a, b = 10, c) {
          return a + b + c;
        }
      ''');

      final result = interpreter.eval('test(1, 2, 3)');
      expect(result.toString(), equals('6'));
    });

    test('should handle undefined arguments with defaults', () {
      interpreter.eval('''
        function test(a = "default") {
          return a;
        }
      ''');

      final result1 = interpreter.eval('test(undefined)');
      expect(result1.toString(), equals('default'));

      final result2 = interpreter.eval('test()');
      expect(result2.toString(), equals('default'));
    });

    test('direct eval in default parameters keeps a separate scope', () {
      final result = interpreter.eval('''
        (() => {
          var c = "global";
          var f;

          f = function f(a = eval("var c = 1"), b = c, probe = () => c) {
            return [b, probe(), c];
          };
          var first = f().toString();

          f = function f(a = eval("f")) {
            return a === f;
          };
          return [first, f(), c].toString();
        })()
      ''');

      expect(result.toString(), equals('1,1,1,true,global'));
    });

    test('arrow parameter scope keeps eval vars separate from body vars', () {
      final result = interpreter.eval('''
        (() => {
          var c = "global";
          var f = (a = eval("var c = 1"), probe = () => c) => {
            var c = 2;
            return [c, probe()];
          };
          return [f().toString(), c].toString();
        })()
      ''');

      expect(result.toString(), equals('2,1,global'));
    });

    test('nested default eval sees outer eval-created parameter bindings', () {
      final result = interpreter.eval('''
        (() => {
          var c = "global";
          var f = function(a = eval("var c = 1"), probe = (d = eval("c")) => d) {
            return [probe(), c];
          };
          return [f().toString(), c].toString();
        })()
      ''');

      expect(result.toString(), equals('1,1,global'));
    });
  });
}
