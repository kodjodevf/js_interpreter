import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });

  group('Rest Parameters', () {
    test('should handle rest parameters in function declarations', () {
      interpreter.eval('''
        function sum(a, b, ...rest) {
          let total = a + b;
          for (let i = 0; i < rest.length; i++) {
            total += rest[i];
          }
          return total;
        }
      ''');

      expect(interpreter.eval('sum(1, 2)').toString(), equals('3'));
      expect(interpreter.eval('sum(1, 2, 3)').toString(), equals('6'));
      expect(interpreter.eval('sum(1, 2, 3, 4, 5)').toString(), equals('15'));
    });

    test('should handle rest parameters with no extra arguments', () {
      interpreter.eval('''
        function onlyRest(...args) {
          return args.length;
        }
      ''');

      expect(interpreter.eval('onlyRest()').toString(), equals('0'));
      expect(interpreter.eval('onlyRest(1)').toString(), equals('1'));
      expect(interpreter.eval('onlyRest(1, 2, 3)').toString(), equals('3'));
    });

    test('should handle rest parameters with default values', () {
      interpreter.eval('''
        function mix(a = 10, b = 20, ...rest) {
          return a + "," + b + "," + rest.length;
        }
      ''');

      expect(interpreter.eval('mix()').toString(), equals('10,20,0'));
      expect(interpreter.eval('mix(1)').toString(), equals('1,20,0'));
      expect(interpreter.eval('mix(1, 2)').toString(), equals('1,2,0'));
      expect(interpreter.eval('mix(1, 2, 3, 4)').toString(), equals('1,2,2'));
    });

    test('should handle rest parameters in function expressions', () {
      interpreter.eval('''
        const collect = function(...items) {
          return items.join("-");
        };
      ''');

      expect(interpreter.eval('collect()').toString(), equals(''));
      expect(interpreter.eval('collect("a")').toString(), equals('a'));
      expect(
        interpreter.eval('collect("a", "b", "c")').toString(),
        equals('a-b-c'),
      );
    });

    test('should allow rest parameter to be empty array', () {
      interpreter.eval('''
        function testRest(a, ...rest) {
          return rest;
        }
      ''');

      final result = interpreter.eval('testRest(1)');
      expect(result.toString(), equals('')); // Empty array toString in JS is ""
    });
  });
}
