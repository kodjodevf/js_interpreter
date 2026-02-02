import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Class New Features Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('private fields syntax parsing', () {
      final code = '''
        class MyClass {
          #privateField = 42;
          
          constructor(value) {
            this.#privateField = value;
          }
          
          getPrivateField() {
            return this.#privateField;
          }
        }
        
        let instance = new MyClass(100);
        instance.getPrivateField();
      ''';

      expect(() => interpreter.eval(code), returnsNormally);
    });

    test('class field declarations parsing', () {
      final code = '''
        class MyClass {
          publicField = "default";
          anotherField = 42;
          
          constructor() {
            // constructor code
          }
        }
        
        let instance = new MyClass();
      ''';

      expect(() => interpreter.eval(code), returnsNormally);
    });

    test('static blocks parsing', () {
      final code = '''
        class MyClass {
          static {
            // Static initialization code
            console.log("Static block executed");
          }
          
          static staticMethod() {
            return "static";
          }
        }
      ''';

      expect(() => interpreter.eval(code), returnsNormally);
    });

    test('getters and setters parsing', () {
      final code = '''
        class MyClass {
          #_value = 0;
          
          get value() {
            return this.#_value;
          }
          
          set value(newValue) {
            this.#_value = newValue;
          }
        }
        
        let instance = new MyClass();
      ''';

      expect(() => interpreter.eval(code), returnsNormally);
    });

    test('computed properties parsing', () {
      final code = '''
        const methodName = "dynamicMethod";
        
        class MyClass {
          [methodName]() {
            return "computed";
          }
          
          ["computed" + "Property"] = "value";
        }
        
        let instance = new MyClass();
      ''';

      expect(() => interpreter.eval(code), returnsNormally);
    });

    test('mixed class features parsing', () {
      final code = '''
        class ComplexClass {
          publicField = "public";
          #privateField = "private";
          
          static staticField = "static";
          static #privateStaticField = "private static";
          
          static {
            console.log("Static initialization");
          }
          
          constructor(value) {
            this.publicField = value;
            this.#privateField = value + "_private";
          }
          
          get value() {
            return this.#privateField;
          }
          
          set value(newValue) {
            this.#privateField = newValue;
          }
          
          static getStaticValue() {
            return ComplexClass.staticField;
          }
          
          #privateMethod() {
            return "private method";
          }
          
          ["computed" + "Method"]() {
            return "computed";
          }
        }
        
        let instance = new ComplexClass("test");
      ''';

      expect(() => interpreter.eval(code), returnsNormally);
    });

    test('basic class still works', () {
      final code = '''
        class SimpleClass {
          constructor(name) {
            this.name = name;
          }
          
          getName() {
            return this.name;
          }
        }
        
        let instance = new SimpleClass("test");
        instance.getName();
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('test'));
    });
  });
}
