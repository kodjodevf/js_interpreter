import 'package:test/test.dart';
import 'package:js_interpreter/src/lexer/lexer.dart';
import 'package:js_interpreter/src/parser/parser.dart';
import 'package:js_interpreter/src/evaluator/evaluator.dart';
import 'package:js_interpreter/src/runtime/js_value.dart';

void main() {
  group('Class Support Tests', () {
    test('basic class declaration', () {
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
        const greeting = person.greet();
      ''';

      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      final ast = parser.parse();
      final evaluator = JSEvaluator();

      // Execute the code
      evaluator.evaluate(ast);

      // Verify that the class was defined
      final personClass = evaluator.globalEnvironment.get('Person');
      expect(personClass, isA<JSClass>());

      // Verify that the instance was created
      final personInstance = evaluator.globalEnvironment.get('person');
      expect(personInstance, isA<JSObject>());

      // Verify the name property
      final nameProperty = (personInstance as JSObject).getProperty('name');
      expect(nameProperty.toString(), equals('Alice'));

      // Verify that the greet method works
      final greetingValue = evaluator.globalEnvironment.get('greeting');
      expect(greetingValue.toString(), equals('Hello, Alice'));
    });

    test('class inheritance with extends', () {
      const code = '''
        class Animal {
          constructor(name) {
            this.name = name;
          }
          
          speak() {
            return this.name + " makes a sound";
          }
        }
        
        class Dog extends Animal {
          constructor(name, breed) {
            super(name);
            this.breed = breed;
          }
          
          speak() {
            return this.name + " barks";
          }
        }
        
        const dog = new Dog("Rex", "Labrador");
        const sound = dog.speak();
      ''';

      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      final ast = parser.parse();
      final evaluator = JSEvaluator();

      // Execute the code
      evaluator.evaluate(ast);

      // Verify that the classes were defined
      final animalClass = evaluator.globalEnvironment.get('Animal');
      expect(animalClass, isA<JSClass>());

      final dogClass = evaluator.globalEnvironment.get('Dog');
      expect(dogClass, isA<JSClass>());

      // Verify inheritance
      expect((dogClass as JSClass).superClass, equals(animalClass));

      // Verify the instance
      final dogInstance = evaluator.globalEnvironment.get('dog');
      expect(dogInstance, isA<JSObject>());

      // Verify the properties
      final nameProperty = (dogInstance as JSObject).getProperty('name');
      expect(nameProperty.toString(), equals('Rex'));

      final breedProperty = dogInstance.getProperty('breed');
      expect(breedProperty.toString(), equals('Labrador'));

      // Verify the overridden method
      final soundValue = evaluator.globalEnvironment.get('sound');
      expect(soundValue.toString(), equals('Rex barks'));
    });

    test('static methods', () {
      const code = '''
        class MathUtils {
          static add(a, b) {
            return a + b;
          }
          
          static multiply(a, b) {
            return a * b;
          }
        }
        
        const sum = MathUtils.add(5, 3);
        const product = MathUtils.multiply(4, 7);
      ''';

      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      final ast = parser.parse();
      final evaluator = JSEvaluator();

      // Execute the code
      evaluator.evaluate(ast);

      // Verify that the class was defined
      final mathUtilsClass = evaluator.globalEnvironment.get('MathUtils');
      expect(mathUtilsClass, isA<JSClass>());

      // Verify the results of the static methods
      final sumValue = evaluator.globalEnvironment.get('sum');
      expect(sumValue.toNumber(), equals(8.0));

      final productValue = evaluator.globalEnvironment.get('product');
      expect(productValue.toNumber(), equals(28.0));
    });

    test('class constructor without parameters', () {
      const code = '''
        class Empty {
          constructor() {
            this.value = 42;
          }
        }
        
        const empty = new Empty();
      ''';

      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      final ast = parser.parse();
      final evaluator = JSEvaluator();

      // Execute the code
      evaluator.evaluate(ast);

      // Verify the instance
      final emptyInstance = evaluator.globalEnvironment.get('empty');
      expect(emptyInstance, isA<JSObject>());

      // Verify the property
      final valueProperty = (emptyInstance as JSObject).getProperty('value');
      expect(valueProperty.toNumber(), equals(42.0));
    });
  });
}
