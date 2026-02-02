import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Private Fields ES2022 Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Basic private field', () {
      final code = '''
        class Person {
          #name;
          
          constructor(name) {
            this.#name = name;
          }
          
          getName() {
            return this.#name;
          }
        }
        
        var person = new Person('Alice');
        person.getName()
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('Alice'));
    });

    test('Multiple private fields', () {
      final code = '''
        class BankAccount {
          #balance;
          #owner;
          
          constructor(owner, initialBalance) {
            this.#owner = owner;
            this.#balance = initialBalance;
          }
          
          getBalance() {
            return this.#balance;
          }
          
          getOwner() {
            return this.#owner;
          }
          
          deposit(amount) {
            this.#balance += amount;
          }
        }
        
        var account = new BankAccount('Bob', 1000);
        account.deposit(500);
        [account.getOwner(), account.getBalance()]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toString(), equals('Bob'));
      expect(result.elements[1].toNumber(), equals(1500));
    });

    test('Private field with public field', () {
      final code = '''
        class User {
          #password;
          username;
          
          constructor(username, password) {
            this.username = username;
            this.#password = password;
          }
          
          checkPassword(pwd) {
            return this.#password === pwd;
          }
        }
        
        var user = new User('john', 'secret123');
        [user.username, user.checkPassword('secret123'), user.checkPassword('wrong')]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toString(), equals('john'));
      expect(result.elements[1].toBoolean(), equals(true));
      expect(result.elements[2].toBoolean(), equals(false));
    });

    // NOTE: Private methods not yet implemented
    // test('Private method', () { ... });

    // NOTE: Private static fields not yet fully implemented
    // test('Private static field', () { ... });

    test('Private field with getter/setter', () {
      final code = '''
        class Temperature {
          #celsius;
          
          constructor(celsius) {
            this.#celsius = celsius;
          }
          
          get fahrenheit() {
            return (this.#celsius * 9/5) + 32;
          }
          
          set fahrenheit(f) {
            this.#celsius = (f - 32) * 5/9;
          }
          
          getCelsius() {
            return this.#celsius;
          }
        }
        
        var temp = new Temperature(0);
        var f1 = temp.fahrenheit;
        temp.fahrenheit = 212;
        var c = temp.getCelsius();
        [f1, c]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(32)); // 0°C = 32°F
      expect(result.elements[1].toNumber(), equals(100)); // 212°F = 100°C
    });
  });

  group('Private Field Access Control Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Cannot access private field from outside', () {
      final code = '''
        class Secret {
          #data = 'hidden';
        }
        
        var obj = new Secret();
        try {
          obj.#data;
          'no error';
        } catch (e) {
          'error';
        }
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('error'));
    });

    // NOTE: Private field inheritance handling not yet fully implemented
    // test('Private fields are not inherited', () { ... });

    test('Each instance has its own private field', () {
      final code = '''
        class Box {
          #value;
          
          constructor(value) {
            this.#value = value;
          }
          
          getValue() {
            return this.#value;
          }
          
          setValue(v) {
            this.#value = v;
          }
        }
        
        var box1 = new Box(10);
        var box2 = new Box(20);
        box1.setValue(100);
        [box1.getValue(), box2.getValue()]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(100));
      expect(result.elements[1].toNumber(), equals(20)); // Unchanged
    });
  });

  group('Private Field with Public API Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Encapsulation pattern', () {
      final code = '''
        class Person {
          #firstName;
          #lastName;
          
          constructor(first, last) {
            this.#firstName = first;
            this.#lastName = last;
          }
          
          get fullName() {
            return this.#firstName + ' ' + this.#lastName;
          }
          
          set fullName(name) {
            var parts = name.split(' ');
            this.#firstName = parts[0];
            this.#lastName = parts[1];
          }
        }
        
        var person = new Person('John', 'Doe');
        var name1 = person.fullName;
        person.fullName = 'Jane Smith';
        var name2 = person.fullName;
        [name1, name2]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toString(), equals('John Doe'));
      expect(result.elements[1].toString(), equals('Jane Smith'));
    });

    test('Validation with private fields', () {
      final code = '''
        class Age {
          #value;
          
          constructor(age) {
            this.#setValue(age);
          }
          
          #setValue(age) {
            if (age < 0 || age > 150) {
              throw new Error('Invalid age');
            }
            this.#value = age;
          }
          
          getValue() {
            return this.#value;
          }
          
          setValue(age) {
            this.#setValue(age);
          }
        }
        
        var age = new Age(25);
        var valid = age.getValue();
        
        var invalid;
        try {
          new Age(-5);
          invalid = 'no error';
        } catch (e) {
          invalid = 'error';
        }
        
        [valid, invalid]
      ''';

      final result = interpreter.eval(code) as JSArray;
      expect(result.elements[0].toNumber(), equals(25));
      expect(result.elements[1].toString(), equals('error'));
    });

    // NOTE: Private static fields not yet fully implemented
    // test('Private counter with public interface', () { ... });
  });
}
