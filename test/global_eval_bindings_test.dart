import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('Global eval bindings', () {
    test('top-level lexical bindings shadow builtins across eval calls', () {
      final interpreter = JSInterpreter();

      interpreter.eval('''
        fetchApi = function fetchApi() { return 123; };
      ''');

      interpreter.eval('''
        const require = (moduleId) => {
          switch (moduleId) {
            case "@libs/fetch":
              return { fetchApi: fetchApi };
            default:
              return {};
          }
        };
      ''');

      expect(interpreter.eval('typeof require').toString(), 'function');

      final result = interpreter.eval('require("@libs/fetch").fetchApi()');

      expect(result.toString(), '123');
    });
  });
}
