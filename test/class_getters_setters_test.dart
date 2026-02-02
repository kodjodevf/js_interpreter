import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Class Getters and Setters', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Class instance getter', () {
      final result = interpreter.eval('''
        class TestClass {
          constructor() {
            this._value = 42;
          }

          get value() {
            return this._value;
          }
        }

        const instance = new TestClass();
        instance.value
      ''');
      expect(result.toString(), '42');
    });

    test('Class instance setter', () {
      final result = interpreter.eval('''
        class TestClass {
          constructor() {
            this._value = 42;
          }

          get value() {
            return this._value;
          }

          set value(newValue) {
            this._value = newValue * 2;
          }
        }

        const instance = new TestClass();
        instance.value = 10;
        instance.value
      ''');
      expect(result.toString(), '20');
    });

    test('Class static getter', () {
      final result = interpreter.eval('''
        class TestClass {
          static get pi() {
            return 3.14;
          }
        }

        TestClass.pi
      ''');
      expect(result.toString(), '3.14');
    });

    test('Class static setter', () {
      final result = interpreter.eval('''
        class TestClass {
          static get value() {
            return TestClass._staticValue || 0;
          }

          static set value(newValue) {
            TestClass._staticValue = newValue + 1;
          }
        }

        TestClass.value = 5;
        TestClass.value
      ''');
      expect(result.toString(), '6');
    });
  });
}
