import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('ES6+ Class Features Summary', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('basic class with field declarations works', () {
      final code = '''
        class SimpleClass {
          publicField = "default";
          
          constructor(value) {
            this.publicField = value;
          }
          
          getValue() {
            return this.publicField;
          }
        }
        
        let instance = new SimpleClass("test");
        instance.getValue();
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('test'));
    });

    test('class with static methods works', () {
      final code = '''
        class StaticClass {
          static getStaticValue() {
            return "static method result";
          }
        }
        
        StaticClass.getStaticValue();
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals("static method result"));
    });

    test('all new syntax parses correctly', () {
      final code = '''
        // Test that all new syntax parses without execution errors
        class ModernClass {
          // Public field declarations
          publicField = "public";
          
          // Private field declarations  
          #privateField = "private";
          
          // Static fields
          static staticField = "static";
          static #privateStaticField = "privateStatic";
          
          // Static initialization block
          static {
            console.log("Static block");
          }
          
          constructor(value) {
            this.publicField = value;
          }
          
          // Private method
          #privateMethod() {
            return "private";
          }
          
          // Getter
          get value() {
            return this.publicField;
          }
          
          // Setter
          set value(newValue) {
            this.publicField = newValue;
          }
          
          // Computed property method name
          ["computed" + "Method"]() {
            return "computed";
          }
        }
        
        // Just creating the class is enough to test parsing
        "syntax parsing successful";
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('syntax parsing successful'));
    });

    test('class inheritance still works', () {
      final code = '''
        class BaseClass {
          constructor(name) {
            this.name = name;
          }
          
          getName() {
            return this.name;
          }
        }
        
        class DerivedClass extends BaseClass {
          constructor(name, age) {
            super(name);
            this.age = age;
          }
          
          getInfo() {
            return this.getName() + " is " + this.age;
          }
        }
        
        let derived = new DerivedClass("Alice", 25);
        derived.getInfo();
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('Alice is 25'));
    });
  });
}
