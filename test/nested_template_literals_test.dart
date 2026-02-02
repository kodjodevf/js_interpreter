import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('Nested template literals', () {
    test('simple nested template in interpolation', () {
      final js = JSInterpreter();
      expect(
        () => js.eval('''
        var inner = 'world';
        var outer = `Hello \${`nested \${inner}`}!`;
      '''),
        returnsNormally,
      );

      final result = js.eval('outer');
      expect(result.toString(), equals('Hello nested world!'));
    });

    test('nested template in ternary operator', () {
      final js = JSInterpreter();
      expect(
        () => js.eval('''
        var flag = true;
        var name = 'Alice';
        var result = `Result: \${flag ? `Name: \${name}` : 'None'}`;
      '''),
        returnsNormally,
      );

      final result = js.eval('result');
      expect(result.toString(), equals('Result: Name: Alice'));
    });

    test('nested template in ternary alternate branch', () {
      final js = JSInterpreter();
      expect(
        () => js.eval('''
        var flag = false;
        var value = 42;
        var result = `Test: \${flag ? 'yes' : `value is \${value}`}`;
      '''),
        returnsNormally,
      );

      final result = js.eval('result');
      expect(result.toString(), equals('Test: value is 42'));
    });

    test('nested template pattern', () {
      final js = JSInterpreter();
      expect(
        () => js.eval('''
        function isVoid(x) { return x === 'void'; }
        function getChildren(x) { return 'children'; }
        
        var tn = 'div';
        var options = 'attrs';
        var result = `<\${tn}\${options}>\${isVoid(tn) ? '' : `\${getChildren(tn)}</\${tn}>`}`;
      '''),
        returnsNormally,
      );

      final result = js.eval('result');
      expect(result.toString(), equals('<divattrs>children</div>'));
    });

    test('multiple levels of nesting', () {
      final js = JSInterpreter();
      expect(
        () => js.eval('''
        var a = 1, b = 2, c = 3;
        var result = `Level1: \${`Level2: \${`Level3: \${a + b + c}`}`}`;
      '''),
        returnsNormally,
      );

      final result = js.eval('result');
      expect(result.toString(), equals('Level1: Level2: Level3: 6'));
    });
  });
}
