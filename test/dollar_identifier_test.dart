import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  test('Support du caractère \$ dans les identificateurs', () {
    final interpreter = JSInterpreter();

    // Test 1: Variable declaration with $
    final result1 = interpreter.eval(r'const $ = 42; $;');
    expect(result1.toNumber(), equals(42));
    print(r'✅ Test 1: const $ = 42');

    // Test 2: Variable starting with $
    final result2 = interpreter.eval(r'const $var = "hello"; $var;');
    expect(result2.toString(), equals('hello'));
    print(r'✅ Test 2: const $var = "hello"');

    // Test 3: Variable avec $ au milieu
    final result3 = interpreter.eval(r'const my$var = 100; my$var;');
    expect(result3.toNumber(), equals(100));
    print(r'✅ Test 3: const my$var = 100');

    print(r'🎉 Le support de $ dans les identificateurs fonctionne!');
  });
}
