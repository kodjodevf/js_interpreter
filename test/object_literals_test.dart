import 'package:test/test.dart';
import 'package:js_interpreter/src/evaluator/evaluator.dart';

void main() {
  group('Object Literals Tests', () {
    test('simple object literal', () {
      const code = '''
        var obj = {name: "John", age: 30};
        obj;
      ''';

      final result = JSEvaluator.evaluateString(code);
      expect(result.isObject, isTrue);
    });

    test('object property access', () {
      const code = '''
        var person = {
          name: "Alice",
          age: 25,
          city: "Paris"
        };
        person.name;
      ''';

      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('Alice'));
    });

    test('object with different value types', () {
      const code = '''
        var mixed = {
          str: "hello",
          num: 42,
          bool: true,
          nullVal: null,
          undefinedVal: undefined,
          arr: [1, 2, 3]
        };
        
        console.log("String:", mixed.str);
        console.log("Number:", mixed.num);
        console.log("Boolean:", mixed.bool);
        console.log("Null:", mixed.nullVal);
        console.log("Undefined:", mixed.undefinedVal);
        console.log("Array:", mixed.arr);
      ''';

      expect(() => JSEvaluator.evaluateString(code), returnsNormally);
    });

    test('object with string keys', () {
      const code = '''
        var obj = {
          "first name": "John",
          "last-name": "Doe",
          "123": "numeric key"
        };
        obj["first name"];
      ''';

      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('John'));
    });

    test('object with computed keys', () {
      const code = '''
        var key = "dynamic";
        var obj = {
          [key]: "value",
          [key + "2"]: "another value"
        };
        obj.dynamic;
      ''';

      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('value'));
    });

    test('nested objects', () {
      const code = '''
        var nested = {
          user: {
            name: "Bob",
            address: {
              street: "123 Main St",
              city: "New York"
            }
          },
          config: {
            debug: true,
            version: "1.0"
          }
        };
        nested.user.address.city;
      ''';

      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('New York'));
    });

    test('object assignment and modification', () {
      const code = '''
        var obj = {x: 10, y: 20};
        obj.x = 100;
        obj.z = 30;
        console.log("x:", obj.x, "y:", obj.y, "z:", obj.z);
        obj.x;
      ''';

      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('100'));
    });

    test('empty object', () {
      const code = '''
        var empty = {};
        empty;
      ''';

      final result = JSEvaluator.evaluateString(code);
      expect(result.isObject, isTrue);
    });

    test('object with function properties', () {
      const code = '''
        var obj = {
          greet: function(name) {
            return "Hello, " + name + "!";
          },
          value: 42
        };
        obj.greet("World");
      ''';

      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('Hello, World!'));
    });

    test('object example', () {
      const code = '''
        function createUser(name, age) {
          return {
            name: name,
            age: age,
            greet: function() {
              return "Hi, I'm " + this.name;
            },
            getInfo: function() {
              return {
                name: this.name,
                age: this.age,
                adult: this.age >= 18
              };
            }
          };
        }
        
        var user = createUser("Emma", 25);
        console.log("User:", user.name, user.age);
        user.name;
      ''';

      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('Emma'));
    });
  });
}
