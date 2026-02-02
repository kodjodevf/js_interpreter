import 'package:test/test.dart';
import 'package:js_interpreter/src/lexer/lexer.dart';
import 'package:js_interpreter/src/parser/parser.dart';
import 'package:js_interpreter/src/evaluator/evaluator.dart';

void main() {
  group('Class Constructor Tests', () {
    test('Basic constructor with this binding', () {
      const code = '''
        class Person {
          constructor(name, age) {
            this.name = name;
            this.age = age;
          }
        }
        
        var person = new Person("Alice", 30);
        person.name + " " + person.age;
      ''';

      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      final ast = parser.parse();
      final evaluator = JSEvaluator();

      final result = evaluator.evaluate(ast);
      expect(result.toString(), equals('Alice 30'));
    });

    test('Constructor with methods', () {
      const code = '''
        class Person {
          constructor(name, age) {
            this.name = name;
            this.age = age;
          }
          
          getInfo() {
            return this.name + " is " + this.age + " years old";
          }
        }
        
        var person = new Person("Bob", 25);
        person.getInfo();
      ''';

      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      final ast = parser.parse();
      final evaluator = JSEvaluator();

      final result = evaluator.evaluate(ast);
      expect(result.toString(), equals('Bob is 25 years old'));
    });

    test('Constructor returning object', () {
      const code = '''
        class CustomReturn {
          constructor(value) {
            this.value = value;
            return { custom: true, value: value };
          }
        }
        
        var result = new CustomReturn(42);
        result.custom + " " + result.value;
      ''';

      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      final ast = parser.parse();
      final evaluator = JSEvaluator();

      final result = evaluator.evaluate(ast);
      expect(result.toString(), equals('true 42'));
    });

    test('Constructor returning primitive (should return instance)', () {
      const code = '''
        class PrimitiveReturn {
          constructor(value) {
            this.value = value;
            return 123; // primitive return should be ignored
          }
        }
        
        var result = new PrimitiveReturn(42);
        result.value;
      ''';

      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      final ast = parser.parse();
      final evaluator = JSEvaluator();

      final result = evaluator.evaluate(ast);
      expect(result.toString(), equals('42'));
    });

    test('Inheritance with constructors', () {
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
        
        var dog = new Dog("Rex", "Golden Retriever");
        dog.name + " " + dog.breed + " " + dog.speak();
      ''';

      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      final ast = parser.parse();
      final evaluator = JSEvaluator();

      final result = evaluator.evaluate(ast);
      expect(result.toString(), equals('Rex Golden Retriever Rex barks'));
    });

    test('Constructor without parameters', () {
      const code = '''
        class Empty {
          constructor() {
            this.value = "empty";
          }
        }
        
        var obj = new Empty();
        obj.value;
      ''';

      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      final ast = parser.parse();
      final evaluator = JSEvaluator();

      final result = evaluator.evaluate(ast);
      expect(result.toString(), equals('empty'));
    });

    test('Multiple instances', () {
      const code = '''
        class Counter {
          constructor() {
            this.count = 0;
          }
          
          increment() {
            this.count = this.count + 1;
            return this.count;
          }
        }
        
        var c1 = new Counter();
        var c2 = new Counter();
        c1.increment();
        c1.increment();
        c2.increment();
        c1.count + " " + c2.count;
      ''';

      final lexer = JSLexer(code);
      final tokens = lexer.tokenize();
      final parser = JSParser(tokens);
      final ast = parser.parse();
      final evaluator = JSEvaluator();

      final result = evaluator.evaluate(ast);
      expect(result.toString(), equals('2 1'));
    });
  });
}
