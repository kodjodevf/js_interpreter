import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Promise Implementation', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Promise constructor creates pending promise', () {
      final result = interpreter.eval('''
        var promise = new Promise(function(resolve, reject) {
          // Promise should be pending initially
        });
        promise;
      ''');

      expect(result.toString(), contains('[object Promise]'));
    });

    test('Promise.resolve creates resolved promise', () {
      final result = interpreter.eval('''
        var promise = Promise.resolve(42);
        promise;
      ''');

      expect(result.toString(), contains('[object Promise]'));
    });

    test('Promise.reject creates rejected promise', () {
      final result = interpreter.eval('''
        var promise = Promise.reject("error");
        promise;
      ''');

      expect(result.toString(), contains('[object Promise]'));
    });

    test('Promise.all with empty array', () {
      final result = interpreter.eval('''
        var promise = Promise.all([]);
        promise;
      ''');

      expect(result.toString(), contains('[object Promise]'));
    });

    test('Promise.race with empty array', () {
      final result = interpreter.eval('''
        var promise = Promise.race([]);
        promise;
      ''');

      expect(result.toString(), contains('[object Promise]'));
    });

    test('Promise.then method exists', () {
      final result = interpreter.eval('''
        var promise = Promise.resolve(42);
        typeof promise.then;
      ''');

      expect(result.toString(), equals('function'));
    });

    test('Promise.catch method exists', () {
      final result = interpreter.eval('''
        var promise = Promise.resolve(42);
        typeof promise["catch"];
      ''');

      expect(result.toString(), equals('function'));
    });

    test('Promise.finally method exists', () {
      final result = interpreter.eval('''
        var promise = Promise.resolve(42);
        typeof promise["finally"];
      ''');

      expect(result.toString(), equals('function'));
    });
  });
}
