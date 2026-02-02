import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  test('Async methods in classes should parse correctly', () {
    final jsCode = '''
class TestClass {
  async testMethod() {
    return 'async result';
  }

  async anotherMethod(param) {
    return param + ' processed';
  }
}

const instance = new TestClass();
''';

    final interpreter = JSInterpreter();
    expect(() => interpreter.eval(jsCode), returnsNormally);
  });

  test('Class with async methods should instantiate', () {
    final jsCode = '''
class AsyncClass {
  async getData() {
    return 42;
  }
}

const obj = new AsyncClass();
typeof obj.getData;
''';

    final interpreter = JSInterpreter();
    final result = interpreter.eval(jsCode);
    expect(result.toString(), equals('function'));
  });
}
