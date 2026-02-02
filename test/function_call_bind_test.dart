import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });

  group('Function.prototype.call.bind', () {
    test('Function.prototype.call should exist', () {
      final result = interpreter.eval('typeof Function.prototype.call');
      expect(result.toString(), equals('function'));
    });

    test('Function.prototype.call should have bind method', () {
      final result = interpreter.eval('typeof Function.prototype.call.bind');
      expect(result.toString(), equals('function'));
    });

    test('Function.prototype.call.bind should work', () {
      final result = interpreter.eval('''
        var __hasOwnProperty = Function.prototype.call.bind(Object.prototype.hasOwnProperty);
        typeof __hasOwnProperty
      ''');
      expect(result.toString(), equals('function'));
    });

    test('Simple direct bind with call', () {
      final result = interpreter.eval('''
        function add(a, b) { return a + b; }
        var add5 = add.bind(null, 5);
        add5(3)
      ''');
      expect(result.toString(), equals('8'));
    });

    test('Verify Array.prototype.join exists', () {
      final result = interpreter.eval('typeof Array.prototype.join');
      expect(result.toString(), equals('function'));
    });

    test('Direct call to Array.prototype.join', () {
      final result = interpreter.eval('''
        Array.prototype.join.call([1, 2, 3], '-')
      ''');
      expect(result.toString(), equals('1-2-3'));
    });

    test('Function.prototype.call.bind with Array.prototype.join', () {
      final result = interpreter.eval('''
        var __join = Function.prototype.call.bind(Array.prototype.join);
        __join([1, 2, 3], '-')
      ''');
      expect(result.toString(), equals('1-2-3'));
    });

    test('Function.prototype.call.bind with Array.prototype.push', () {
      final result = interpreter.eval('''
        var __push = Function.prototype.call.bind(Array.prototype.push);
        var arr = [1, 2];
        __push(arr, 3);
        arr.length
      ''');
      expect(result.toString(), equals('3'));
    });
  });
}
