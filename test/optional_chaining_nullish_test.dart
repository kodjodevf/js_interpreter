import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Optional Chaining and Nullish Coalescing', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Optional chaining with property access', () {
      final result = interpreter.eval('''
        const obj = { prop: 'value' };
        const nullObj = null;
        const result1 = obj?.prop;
        const result2 = nullObj?.prop;
        [result1, result2]
      ''');
      expect(result.toString(), 'value,');
    });

    test('Optional chaining with method call', () {
      final result = interpreter.eval('''
        const obj = { method: function() { return 'called'; } };
        const nullObj = null;
        const result1 = obj?.method();
        const result2 = nullObj?.method();
        [result1, result2]
      ''');
      expect(result.toString(), 'called,');
    });

    test('Optional chaining with computed property and parenthesized call', () {
      final result = interpreter.eval('''
        const obj = {
          method() { return this.value; },
          value: 42
        };
        (obj?.['method'])();
      ''');
      expect(result.toNumber(), equals(42));
    });

    test('Optional chaining delete short-circuits on nullish base', () {
      final result = interpreter.eval('''
        const nullObj = null;
        const obj = { nested: { value: 1 } };
        const result1 = delete nullObj?.nested.value;
        const result2 = delete nullObj?.nested['value'];
        const result3 = delete obj?.nested.value;
        [result1, result2, result3, JSON.stringify(obj)]
      ''');
      expect(result.toString(), 'true,true,true,{"nested":{}}');
    });

    test('Nullish coalescing operator', () {
      final result = interpreter.eval('''
        const nullValue = null;
        const undefinedValue = undefined;
        const zeroValue = 0;
        const emptyString = '';
        const result1 = nullValue ?? 'default';
        const result2 = undefinedValue ?? 'default';
        const result3 = zeroValue ?? 'default';
        const result4 = emptyString ?? 'default';
        [result1, result2, result3, result4]
      ''');
      expect(result.toString(), 'default,default,0,');
    });

    test('Combined optional chaining and nullish coalescing', () {
      final result = interpreter.eval('''
        const obj = { nested: { value: 'test' } };
        const nullObj = null;
        const result1 = obj?.nested?.value ?? 'default';
        const result2 = nullObj?.nested?.value ?? 'default';
        [result1, result2]
      ''');
      expect(result.toString(), 'test,default');
    });
  });
}
