import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  final interpreter = JSInterpreter();

  test('Array.join() handles undefined/null elements correctly', () {
    // Test Array(n) join
    final result1 = interpreter.eval('Array(3).join("0")');
    expect(result1.toString(), equals('00'));

    // Test array with undefined elements
    final result2 = interpreter.eval(
      '[undefined, undefined, undefined].join("0")',
    );
    expect(result2.toString(), equals('00'));

    // Test array with null elements
    final result3 = interpreter.eval('[null, null, null].join("0")');
    expect(result3.toString(), equals('00'));

    // Test mixed array
    final result4 = interpreter.eval('[1, undefined, 3, null].join("-")');
    expect(result4.toString(), equals('1--3-'));

    // Test default separator
    final result5 = interpreter.eval('[1, undefined, 3].join()');
    expect(result5.toString(), equals('1,,3'));
  });
}
