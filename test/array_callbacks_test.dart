import "package:test/test.dart";
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  test("Array callbacks basic", () {
    final interpreter = JSInterpreter();
    final result = interpreter.eval(
      "var arr = [1, 2, 3]; arr.forEach != undefined",
    );
    expect(result.toBoolean(), isTrue);
  });
}
