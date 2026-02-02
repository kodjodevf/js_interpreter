import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Generator Basics Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('function* syntax is recognized', () {
      final code = '''
        function* gen() {
          return 42;
        }
        
        typeof gen
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('function'));
    });

    test('Calling generator function returns a generator object', () {
      final code = '''
        function* gen() {
          return 42;
        }
        
        var g = gen();
        typeof g
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('object'));
    });

    test('Generator has next() method', () {
      final code = '''
        function* gen() {
          return 42;
        }
        
        var g = gen();
        typeof g.next
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('function'));
    });

    test('Generator has return() method', () {
      final code = '''
        function* gen() {
          return 42;
        }
        
        var g = gen();
        typeof g['return']
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('function'));
    });

    test('Generator has throw() method', () {
      final code = '''
        function* gen() {
          return 42;
        }
        
        var g = gen();
        typeof g['throw']
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('function'));
    });

    test('Calling next() returns object with value and done', () {
      final code = '''
        function* gen() {
          return 42;
        }
        
        var g = gen();
        var result = g.next();
        [typeof result, typeof result.value, typeof result.done]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toString(), equals('object'));
      expect(result.elements[1].toString(), equals('number')); // Now returns 42
      expect(result.elements[2].toString(), equals('boolean'));
    });

    test('Generator toString', () {
      final code = '''
        function* gen() {
          return 42;
        }
        
        var g = gen();
        String(g)
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('Generator'));
    });
  });

  group('Generator Yield Tests (Basic)', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('yield keyword works correctly', () {
      // Parsing and yield execution work now
      final code = '''
        function* gen() {
          yield 1;
        }
        
        var g = gen();
        var result = g.next();
        result.done
      ''';

      final result = interpreter.eval(code);
      expect(
        result.toBoolean(),
        equals(false),
      ); // The generator is not finished after the first yield
    });
  });

  group('Generator Return Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Generator return() completes generator', () {
      final code = '''
        function* gen() {
          return 42;
        }
        
        var g = gen();
        var result = g['return'](100);
        [result.value, result.done]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(100));
      expect(result.elements[1].toBoolean(), equals(true));
    });

    test('Generator return() on completed generator', () {
      final code = '''
        function* gen() {
          return 42;
        }
        
        var g = gen();
        g.next(); // Complete the generator
        var result = g['return'](100);
        [result.value, result.done]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(100));
      expect(result.elements[1].toBoolean(), equals(true));
    });
  });
}
