import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Class Computed Properties', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('simple computed method name', () {
      final code = '''
        class MyClass {
          ['greet']() {
            return 'Hello World';
          }
        }

        const instance = new MyClass();
        instance.greet();
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('Hello World'));
    });

    test('computed static method names', () {
      final code = '''
        const staticMethod = 'create';

        class Factory {
          static [staticMethod](value) {
            return new Factory(value);
          }

          constructor(value) {
            this.value = value;
          }
        }

        const instance = Factory.create('test');
        instance.value;
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('test'));
    });

    test('computed property with expression', () {
      final code = '''
        const prefix = 'get';
        const suffix = 'Value';

        class ComputedProps {
          [prefix + suffix]() {
            return 42;
          }
        }

        const instance = new ComputedProps();
        instance.getValue();
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('42'));
    });
  });
}
