import 'package:test/test.dart';
import 'package:js_interpreter/src/evaluator/evaluator.dart';
import 'package:js_interpreter/src/parser/parser.dart';

void main() {
  group('Arrow Functions', () {
    late JSEvaluator evaluator;

    setUp(() {
      evaluator = JSEvaluator();
    });

    test('Single parameter arrow function', () {
      final code = 'x => x * 2';
      final ast = JSParser.parseExpression(code);
      final result = ast.accept(evaluator);

      expect(result.type.toString(), contains('function'));
    });

    test('Multiple parameters arrow function', () {
      final code = '(x, y) => x + y';
      final ast = JSParser.parseExpression(code);
      final result = ast.accept(evaluator);

      expect(result.type.toString(), contains('function'));
    });

    test('Sequence expression parsing', () {
      final code = 'a, b, c';
      final ast = JSParser.parseExpression(code);

      expect(ast.runtimeType.toString(), 'SequenceExpression');
    });
  });
}
