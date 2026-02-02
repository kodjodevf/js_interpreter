import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Symbol Implementation', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Symbol constructor creates unique symbols', () {
      final result = interpreter.eval('''
        const sym1 = Symbol();
        const sym2 = Symbol();
        const sym3 = Symbol('test');
        const sym4 = Symbol('test');

        [sym1 === sym2, sym3 === sym4, typeof sym1, typeof sym3]
      ''');

      final results = (result as JSArray).elements;
      expect(results[0].toString(), equals('false')); // sym1 !== sym2
      expect(
        results[1].toString(),
        equals('false'),
      ); // sym3 !== sym4 (same description but different)
      expect(results[2].toString(), equals('symbol'));
      expect(results[3].toString(), equals('symbol'));
    });

    test('Symbol.for and Symbol.keyFor work correctly', () {
      final result = interpreter.eval('''
        const sym1 = Symbol.for('test');
        const sym2 = Symbol.for('test');
        const key = Symbol.keyFor(sym1);

        [sym1 === sym2, key]
      ''');

      final results = (result as JSArray).elements;
      expect(results[0].toString(), equals('true')); // Same symbol from registry
      expect(results[1].toString(), equals('test')); // The key is found
    });

    test('Symbol description property', () {
      final result = interpreter.eval('''
        const sym1 = Symbol();
        const sym2 = Symbol('my description');

        [sym1.toString(), sym2.toString()]
      ''');

      final results = (result as JSArray).elements;
      expect(results[0].toString(), equals('Symbol()'));
      expect(results[1].toString(), equals('Symbol(my description)'));
    });

    test('Symbol cannot be converted to number', () {
      expect(
        () => interpreter.eval('Number(Symbol())'),
        throwsA(isA<JSTypeError>()),
      );
    });

    test('globalThis provides access to global object', () {
      final result = interpreter.eval('''
        globalThis.testVar = 'hello';
        const result = globalThis.testVar;
        result
      ''');

      expect(result.toString(), equals('hello'));
    });

    test('globalThis allows accessing global variables', () {
      interpreter.setGlobal('myGlobalVar', 'test value');
      final result = interpreter.eval('globalThis.myGlobalVar');
      expect(result.toString(), equals('test value'));
    });
  });
}
