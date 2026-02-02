import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Function this Binding Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Function.prototype.call with this binding', () {
      final code = '''
        function greet(name) {
          return "Hello " + name + "! I am " + this.name;
        }
        
        var person = { name: "Alice" };
        var result = greet.call(person, "Bob");
      ''';

      interpreter.eval(code);
      final result = interpreter.evalExpression('result');
      expect(result.toString(), equals('Hello Bob! I am Alice'));
    });

    test('Function.prototype.apply with this binding', () {
      final code = '''
        function introduce(greeting, punctuation) {
          return greeting + "! I am " + this.name + punctuation;
        }
        
        var person = { name: "Charlie" };
        var result = introduce.apply(person, ["Hello", "!"]);
      ''';

      interpreter.eval(code);
      final result = interpreter.evalExpression('result');
      expect(result.toString(), equals('Hello! I am Charlie!'));
    });

    test('Function.prototype.bind with this binding', () {
      final code = '''
        function sayHello(greeting) {
          return greeting + ", " + this.name + "!";
        }
        
        var person = { name: "David" };
        var boundSayHello = sayHello.bind(person);
        var result = boundSayHello("Hi");
      ''';

      interpreter.eval(code);
      final result = interpreter.evalExpression('result');
      expect(result.toString(), equals('Hi, David!'));
    });

    test('Method call preserves this binding', () {
      final code = '''
        var obj = {
          name: "Emma",
          getName: function() {
            return this.name;
          }
        };
        
        var result = obj.getName();
      ''';

      interpreter.eval(code);
      final result = interpreter.evalExpression('result');
      expect(result.toString(), equals('Emma'));
    });

    test('call with different this context', () {
      final code = '''
        var obj1 = { name: "First" };
        var obj2 = { name: "Second" };
        
        function getName() {
          return this.name;
        }
        
        var result1 = getName.call(obj1);
        var result2 = getName.call(obj2);
      ''';

      interpreter.eval(code);
      final result1 = interpreter.evalExpression('result1');
      final result2 = interpreter.evalExpression('result2');

      expect(result1.toString(), equals('First'));
      expect(result2.toString(), equals('Second'));
    });

    test('bind with partial application and this', () {
      final code = '''
        function fullName(title, suffix) {
          return title + " " + this.first + " " + this.last + " " + suffix;
        }
        
        var person = { first: "John", last: "Doe" };
        var boundFullName = fullName.bind(person, "Mr.");
        var result = boundFullName("Jr.");
      ''';

      interpreter.eval(code);
      final result = interpreter.evalExpression('result');
      expect(result.toString(), equals('Mr. John Doe Jr.'));
    });

    test('apply with null/undefined this', () {
      final code = '''
        function getThis() {
          return this;
        }
        
        var globalThis = this;
        var result1 = getThis.call(null);
        var result2 = getThis.apply(undefined);
      ''';

      interpreter.eval(code);
      final globalThis = interpreter.evalExpression('globalThis');
      final result1 = interpreter.evalExpression('result1');
      final result2 = interpreter.evalExpression('result2');

      // In non-strict mode, null/undefined this should be converted to global object
      expect(result1 == globalThis, isTrue);
      expect(result2 == globalThis, isTrue);
    });

    test('complex this binding scenario', () {
      final code = '''
        var calculator = {
          value: 0,
          add: function(x) {
            this.value += x;
            return this;
          },
          multiply: function(x) {
            this.value *= x;
            return this;
          },
          getValue: function() {
            return this.value;
          }
        };
        
        // Method chaining
        calculator.add(5).multiply(3).add(2);
        var result = calculator.getValue();
      ''';

      interpreter.eval(code);
      final result = interpreter.evalExpression('result');
      expect(result.toNumber(), equals(17.0)); // (0 + 5) * 3 + 2 = 17
    });
  });
}
