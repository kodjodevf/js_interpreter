import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Complete Prototype System Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('instanceof Operator', () {
      test('basic instanceof with Object', () {
        final result = interpreter.eval('''
          var obj = {};
          obj instanceof Object;
        ''');
        expect(result.toBoolean(), equals(true));
      });

      test('instanceof with arrays', () {
        final result = interpreter.eval('''
          var arr = [1, 2, 3];
          arr instanceof Array;
        ''');
        expect(result.toBoolean(), equals(true));
      });

      test('primitives instanceof returns false', () {
        final result = interpreter.eval('''
          var tests = [];
          tests.push(5 instanceof Number);
          tests.push("hello" instanceof String);
          tests.push(true instanceof Boolean);
          tests.push(null instanceof Object);
          tests.push(undefined instanceof Object);
          tests.join(',');
        ''');
        expect(result.toString(), equals('false,false,false,false,false'));
      });

      test('instanceof with function constructors', () {
        final result = interpreter.eval('''
          function Person(name) {
            this.name = name;
          }
          var person = new Person("Alice");
          person instanceof Person;
        ''');
        expect(result.toBoolean(), equals(true));
      });

      test('instanceof traverses prototype chain', () {
        final result = interpreter.eval('''
          function Animal() {}
          function Dog() {}
          Dog.prototype = new Animal();
          
          var dog = new Dog();
          var results = [];
          results.push(dog instanceof Dog);
          results.push(dog instanceof Animal);
          results.push(dog instanceof Object);
          results.join(',');
        ''');
        expect(result.toString(), equals('true,true,true'));
      });
    });

    group('String.prototype Methods', () {
      test('string auto-boxing works', () {
        final result = interpreter.eval('''
          var str = "hello";
          str.length;
        ''');
        expect(result.toNumber(), equals(5));
      });

      test('charAt method', () {
        final result = interpreter.eval('''
          "hello".charAt(1);
        ''');
        expect(result.toString(), equals('e'));
      });

      test('substring method', () {
        final result = interpreter.eval('''
          "hello world".substring(0, 5);
        ''');
        expect(result.toString(), equals('hello'));
      });

      test('indexOf method', () {
        final result = interpreter.eval('''
          "hello world".indexOf("world");
        ''');
        expect(result.toNumber(), equals(6));
      });

      test('split method', () {
        final result = interpreter.eval('''
          "a,b,c".split(",").join("|");
        ''');
        expect(result.toString(), equals('a|b|c'));
      });

      test('toUpperCase and toLowerCase', () {
        final result = interpreter.eval('''
          var str = "Hello World";
          var upper = str.toUpperCase();
          var lower = str.toLowerCase();
          upper + "|" + lower;
        ''');
        expect(result.toString(), equals('HELLO WORLD|hello world'));
      });

      test('string method chaining', () {
        final result = interpreter.eval('''
          "  Hello World  ".trim().toUpperCase().substring(0, 5);
        ''');
        expect(result.toString(), equals('HELLO'));
      });

      test('includes, startsWith, endsWith', () {
        final result = interpreter.eval('''
          var str = "hello world";
          var results = [];
          results.push(str.includes("world"));
          results.push(str.startsWith("hello"));
          results.push(str.endsWith("world"));
          results.join(',');
        ''');
        expect(result.toString(), equals('true,true,true'));
      });

      test('replace method', () {
        final result = interpreter.eval('''
          "hello world".replace("world", "universe");
        ''');
        expect(result.toString(), equals('hello universe'));
      });

      test('repeat method', () {
        final result = interpreter.eval('''
          "ha".repeat(3);
        ''');
        expect(result.toString(), equals('hahaha'));
      });
    });

    group('Object.prototype Methods', () {
      test('toString method', () {
        final result = interpreter.eval('''
          var obj = {};
          obj.toString();
        ''');
        expect(result.toString(), equals('[object Object]'));
      });

      test('hasOwnProperty method', () {
        final result = interpreter.eval('''
          var obj = {x: 10, y: 20};
          var results = [];
          results.push(obj.hasOwnProperty("x"));
          results.push(obj.hasOwnProperty("z"));
          results.join(',');
        ''');
        expect(result.toString(), equals('true,false'));
      });

      test('valueOf method', () {
        final result = interpreter.eval('''
          var obj = {x: 42};
          obj.valueOf() === obj;
        ''');
        expect(result.toBoolean(), equals(true));
      });

      test('isPrototypeOf method', () {
        final result = interpreter.eval('''
          var parent = {};
          var child = Object.create(parent);
          parent.isPrototypeOf(child);
        ''');
        expect(result.toBoolean(), equals(true));
      });
    });

    group('Function.prototype Methods', () {
      test('function call method', () {
        final result = interpreter.eval('''
          function greet(name) {
            return "Hello, " + name + "!";
          }
          greet.call(null, "World");
        ''');
        expect(result.toString(), equals('Hello, World!'));
      });

      test('function apply method', () {
        final result = interpreter.eval('''
          function sum(a, b, c) {
            return a + b + c;
          }
          sum.apply(null, [1, 2, 3]);
        ''');
        expect(result.toNumber(), equals(6));
      });

      test('function bind method', () {
        final result = interpreter.eval('''
          function multiply(a, b) {
            return a * b;
          }
          var double = multiply.bind(null, 2);
          double(5);
        ''');
        expect(result.toNumber(), equals(10));
      });
    });

    group('Prototype Chain Inheritance', () {
      test('prototype chain lookup', () {
        final result = interpreter.eval('''
          function Animal(name) {
            this.name = name;
          }
          Animal.prototype.speak = function() {
            return this.name + " makes a sound";
          };
          
          function Dog(name) {
            Animal.call(this, name);
          }
          Dog.prototype = Object.create(Animal.prototype);
          Dog.prototype.constructor = Dog;
          Dog.prototype.bark = function() {
            return this.name + " barks";
          };
          
          var dog = new Dog("Rex");
          var results = [];
          results.push(dog.name);
          results.push(dog.speak());
          results.push(dog.bark());
          results.join('|');
        ''');
        expect(result.toString(), equals('Rex|Rex makes a sound|Rex barks'));
      });

      test('Object.create with null prototype', () {
        final result = interpreter.eval('''
          var obj = Object.create(null);
          obj.x = 42;
          var results = [];
          results.push(obj.x);
          results.push(obj.toString === undefined);
          results.push(obj.hasOwnProperty === undefined);
          results.join(',');
        ''');
        expect(result.toString(), equals('42,true,true'));
      });

      test('constructor property', () {
        final result = interpreter.eval('''
          function MyConstructor() {}
          var obj = new MyConstructor();
          obj.constructor === MyConstructor;
        ''');
        expect(result.toBoolean(), equals(true));
      });
    });

    group('Auto-boxing and Primitive Wrappers', () {
      test('string primitive auto-boxing', () {
        final result = interpreter.eval('''
          var str = "hello";
          var results = [];
          results.push(str.length);
          results.push(str.charAt(0));
          results.push(str.toUpperCase());
          results.join('|');
        ''');
        expect(result.toString(), equals('5|h|HELLO'));
      });

      test('number primitive auto-boxing', () {
        final result = interpreter.eval('''
          var num = 42.567;
          var results = [];
          results.push(num.toString());
          results.push(num.toFixed(2));
          results.join('|');
        ''');
        expect(result.toString(), equals('42.567|42.57'));
      });

      test('boolean primitive methods', () {
        final result = interpreter.eval('''
          var bool = true;
          bool.toString();
        ''');
        expect(result.toString(), equals('true'));
      });
    });

    group('Complex Prototype Scenarios', () {
      test('multiple inheritance levels', () {
        final result = interpreter.eval('''
          function GrandParent() {
            this.level = "grandparent";
          }
          GrandParent.prototype.getLevel = function() {
            return this.level;
          };
          
          function Parent() {
            GrandParent.call(this);
            this.level = "parent";
          }
          Parent.prototype = Object.create(GrandParent.prototype);
          Parent.prototype.constructor = Parent;
          
          function Child() {
            Parent.call(this);
            this.level = "child";
          }
          Child.prototype = Object.create(Parent.prototype);
          Child.prototype.constructor = Child;
          
          var child = new Child();
          var results = [];
          results.push(child instanceof Child);
          results.push(child instanceof Parent);
          results.push(child instanceof GrandParent);
          results.push(child instanceof Object);
          results.push(child.getLevel());
          results.join(',');
        ''');
        expect(result.toString(), equals('true,true,true,true,child'));
      });

      test('prototype property shadowing', () {
        final result = interpreter.eval('''
          function Base() {}
          Base.prototype.value = "base";
          
          function Derived() {}
          Derived.prototype = Object.create(Base.prototype);
          Derived.prototype.value = "derived";
          
          var obj = new Derived();
          obj.value;
        ''');
        expect(result.toString(), equals('derived'));
      });

      test('dynamic prototype modification', () {
        final result = interpreter.eval('''
          function MyClass() {}
          var obj = new MyClass();
          
          // Add a method to the prototype after creation
          MyClass.prototype.newMethod = function() {
            return "new method called";
          };
          
          obj.newMethod();
        ''');
        expect(result.toString(), equals('new method called'));
      });
    });
  });
}
