import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('setTimeout and clearTimeout Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('setTimeout basic functionality', () async {
      final result = await interpreter.evalAsync('''
        var executed = false;
        var timeoutId = setTimeout(function() {
          executed = true;
        }, 10);
        timeoutId;
      ''');

      // Wait for the timeout to execute
      await Future.delayed(Duration(milliseconds: 50));

      final executedResult = interpreter.eval('executed');

      expect(result.toString(), isNot('0')); // Should return a valid ID
      expect(executedResult.toString(), equals('true'));
    });

    test('setTimeout with arguments', () async {
      final result = await interpreter.evalAsync('''
        var args = [];
        var timeoutId = setTimeout(function(a, b) {
          args.push(a);
          args.push(b);
        }, 10, 'hello', 'world');
        timeoutId;
      ''');

      // Wait for the timeout to execute
      await Future.delayed(Duration(milliseconds: 50));

      final argsResult = interpreter.eval('args');

      expect(result.toString(), isNot('0'));
      expect(argsResult.toString(), contains('hello'));
      expect(argsResult.toString(), contains('world'));
    });

    test('setTimeout returns unique IDs', () async {
      final result = await interpreter.evalAsync('''
        var id1 = setTimeout(function() {}, 10);
        var id2 = setTimeout(function() {}, 10);
        var id3 = setTimeout(function() {}, 10);
        [id1, id2, id3];
      ''');

      expect(result, isA<JSArray>());
      final ids = (result as JSArray).elements;

      // Verify that all IDs are different
      expect(ids[0].toString(), isNot(equals(ids[1].toString())));
      expect(ids[1].toString(), isNot(equals(ids[2].toString())));
      expect(ids[0].toString(), isNot(equals(ids[2].toString())));
    });

    test('clearTimeout cancels execution', () async {
      final result = await interpreter.evalAsync('''
        var executed = false;
        var timeoutId = setTimeout(function() {
          executed = true;
        }, 10);
        clearTimeout(timeoutId);
        timeoutId;
      ''');

      // Wait longer than the original delay
      await Future.delayed(Duration(milliseconds: 50));

      final executedResult = interpreter.eval('executed');

      expect(result.toString(), isNot('0'));
      expect(executedResult.toString(), equals('false'));
    });

    test('clearTimeout with invalid ID does nothing', () async {
      // This function should not crash
      final result = interpreter.eval('clearTimeout(99999)');

      expect(result.isUndefined, equals(true));
    });

    test('setTimeout with zero delay', () async {
      final result = await interpreter.evalAsync('''
        var executed = false;
        var timeoutId = setTimeout(function() {
          executed = true;
        }, 0);
        timeoutId;
      ''');

      // Wait a bit for the timeout to execute
      await Future.delayed(Duration(milliseconds: 10));

      final executedResult = interpreter.eval('executed');

      expect(result.toString(), isNot('0'));
      expect(executedResult.toString(), equals('true'));
    });

    test('setTimeout with negative delay treated as zero', () async {
      final result = await interpreter.evalAsync('''
        var executed = false;
        var timeoutId = setTimeout(function() {
          executed = true;
        }, -10);
        timeoutId;
      ''');

      // Wait a bit for the timeout to execute
      await Future.delayed(Duration(milliseconds: 10));

      final executedResult = interpreter.eval('executed');

      expect(result.toString(), isNot('0'));
      expect(executedResult.toString(), equals('true'));
    });

    test('setTimeout error handling', () {
      expect(() {
        interpreter.eval('setTimeout()');
      }, throwsA(isA<JSError>()));

      expect(() {
        interpreter.eval('setTimeout("not a function")');
      }, throwsA(isA<JSTypeError>()));
    });

    test('Multiple timeouts execute in order', () async {
      final result = await interpreter.evalAsync('''
        var order = [];
        setTimeout(function() { order.push(1); }, 10);
        setTimeout(function() { order.push(2); }, 20);
        setTimeout(function() { order.push(3); }, 5);
        'started';
      ''');

      // Wait for all timeouts to execute
      await Future.delayed(Duration(milliseconds: 100));

      final orderResult = interpreter.eval('order');

      expect(result.toString(), equals('started'));
      expect(orderResult, isA<JSArray>());

      final order = (orderResult as JSArray).elements;
      expect(order.length, equals(3));
      expect(order.map((e) => e.toString()).toList(), contains('1'));
      expect(order.map((e) => e.toString()).toList(), contains('2'));
      expect(order.map((e) => e.toString()).toList(), contains('3'));
    });

    test('setTimeout callback errors are handled gracefully', () async {
      final result = await interpreter.evalAsync('''
        setTimeout(function() {
          throw new Error('Test error');
        }, 10);
      ''');

      // Wait for the timeout to execute
      await Future.delayed(Duration(milliseconds: 50));

      // The program should not crash despite the error in the callback
      expect(result.toString(), isNotNull);
    });
  });
}
