import 'package:js_interpreter/js_interpreter.dart';

void main() {
  final interpreter = JSInterpreter();

  // Test 1: await as parameter name
  try {
    interpreter.eval('async function foo (await) { }');
    print('Test 1 FAIL: Should have thrown');
  } catch (e) {
    print('Test 1 PASS: $e');
  }

  // Test 2: await in body
  try {
    interpreter.eval('''
async function asyncFn() {
  void await;
}
    ''');
    print('Test 2 FAIL: Should have thrown');
  } catch (e) {
    print('Test 2 PASS: $e');
  }
}
