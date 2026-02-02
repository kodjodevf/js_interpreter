import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Function Object Properties', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('function should have length property', () {
      interpreter.eval('''
        function testFunc(a, b, c) {
          return a + b + c;
        }
      ''');

      final result = interpreter.eval('testFunc.length');
      expect(result.toNumber(), equals(3.0));
    });

    test('function should have name property', () {
      interpreter.eval('''
        function namedFunction() {
          return 42;
        }
      ''');

      final result = interpreter.eval('namedFunction.name');
      expect(result.toString(), equals('namedFunction'));
    });

    test('anonymous function should have name "anonymous"', () {
      interpreter.eval('''
        var anonFunc = function() {
          return 42;
        };
      ''');

      final result = interpreter.eval('anonFunc.name');
      expect(result.toString(), equals('anonFunc'));
    });

    test('function should have prototype property', () {
      interpreter.eval('''
        function TestConstructor() {}
      ''');

      // Verifies that the prototype property exists
      final hasPrototype = interpreter.eval(
        'TestConstructor.hasOwnProperty("prototype")',
      );
      expect(hasPrototype.toBoolean(), isTrue);

      // Verifies that prototype.constructor points to the function
      final result = interpreter.eval(
        'TestConstructor.prototype.constructor === TestConstructor',
      );
      expect(result.toBoolean(), isTrue);
    });

    test('function should have call method', () {
      interpreter.eval('''
        function testFunc() {
          return "called";
        }
      ''');

      // Verifies that the call method exists
      final hasCall = interpreter.eval('typeof testFunc.call');
      expect(hasCall.toString(), equals('function'));
    });

    test('function should have apply method', () {
      interpreter.eval('''
        function testFunc() {
          return "applied";
        }
      ''');

      // Verifies that the apply method exists
      final hasApply = interpreter.eval('typeof testFunc.apply');
      expect(hasApply.toString(), equals('function'));
    });

    test('function should have bind method', () {
      interpreter.eval('''
        function testFunc() {
          return "bound";
        }
      ''');

      // Verifies that the bind method exists
      final hasBind = interpreter.eval('typeof testFunc.bind');
      expect(hasBind.toString(), equals('function'));
    });

    test('arrow function should have proper properties', () {
      interpreter.eval('''
        var arrow = (x, y) => x + y;
      ''');

      final length = interpreter.eval('arrow.length');
      expect(length.toNumber(), equals(2.0));

      final name = interpreter.eval('arrow.name');
      expect(name.toString(), equals('arrow'));
    });

    test('function properties should be properly typed', () {
      interpreter.eval('''
        function complexFunc(a, b, c, d, e) {
          return a + b + c + d + e;
        }
      ''');

      // Test length
      final lengthType = interpreter.eval('typeof complexFunc.length');
      expect(lengthType.toString(), equals('number'));

      // Test name
      final nameType = interpreter.eval('typeof complexFunc.name');
      expect(nameType.toString(), equals('string'));

      // Test prototype
      final prototypeType = interpreter.eval('typeof complexFunc.prototype');
      expect(prototypeType.toString(), equals('object'));
    });

    test('nested function should maintain proper properties', () {
      interpreter.eval('''
        function outer() {
          function inner(x) {
            return x * 2;
          }
          return inner;
        }
        var innerFunc = outer();
      ''');

      final length = interpreter.eval('innerFunc.length');
      expect(length.toNumber(), equals(1.0));

      final name = interpreter.eval('innerFunc.name');
      expect(name.toString(), equals('inner'));
    });
  });
}
