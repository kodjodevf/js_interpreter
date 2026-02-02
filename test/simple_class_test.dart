import 'package:test/test.dart';
import 'package:js_interpreter/src/lexer/lexer.dart';
import 'package:js_interpreter/src/parser/parser.dart';
import 'package:js_interpreter/src/evaluator/evaluator.dart';
import 'package:js_interpreter/src/runtime/js_value.dart';

void main() {
  group('Simple Class Tests', () {
    test('basic class declaration and instantiation', () {
      const code = '''
        class Person {
          constructor(name) {
            this.name = name;
          }
          
          greet() {
            return "Hello, " + this.name;
          }
        }
        
        const person = new Person("Alice");
      ''';

      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      final ast = parser.parse();
      final evaluator = JSEvaluator();

      // Execute the code
      evaluator.evaluate(ast);

      // Check that the class was defined
      final personClass = evaluator.globalEnvironment.get('Person');
      expect(personClass, isA<JSClass>());

      // Check that the instance was created
      final personInstance = evaluator.globalEnvironment.get('person');
      expect(personInstance, isA<JSObject>());

      // Check the name property
      final nameProperty = (personInstance as JSObject).getProperty('name');
      expect(nameProperty.toString(), equals('Alice'));
    });

    test('static methods', () {
      const code = '''
        class MathUtils {
          static add(a, b) {
            return a + b;
          }
        }
        
        const sum = MathUtils.add(5, 3);
      ''';

      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      final ast = parser.parse();
      final evaluator = JSEvaluator();

      // Execute the code
      evaluator.evaluate(ast);

      // Check that the class was defined
      final mathUtilsClass = evaluator.globalEnvironment.get('MathUtils');
      expect(mathUtilsClass, isA<JSClass>());

      // Check the results of static methods
      final sumValue = evaluator.globalEnvironment.get('sum');
      expect(sumValue.toNumber(), equals(8.0));
    });

    test('class without constructor', () {
      const code = '''
        class Empty {
          getValue() {
            return 42;
          }
        }
        
        const empty = new Empty();
        const value = empty.getValue();
      ''';

      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      final ast = parser.parse();
      final evaluator = JSEvaluator();

      // Execute the code
      evaluator.evaluate(ast);

      // Check that the instance is correct
      final emptyInstance = evaluator.globalEnvironment.get('empty');
      expect(emptyInstance, isA<JSObject>());

      // Check the method
      final valueResult = evaluator.globalEnvironment.get('value');
      expect(valueResult.toNumber(), equals(42.0));
    });
  });
}
