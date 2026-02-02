import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Private Methods & Static Fields ES2022', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('Private Methods', () {
      test('Basic private method', () {
        final result = interpreter.eval('''
          class Person {
            #name;
            
            constructor(name) {
              this.#name = name;
            }
            
            #formatName() {
              return this.#name.toUpperCase();
            }
            
            getFormattedName() {
              return this.#formatName();
            }
          }
          
          const person = new Person('alice');
          person.getFormattedName()
        ''');
        expect(result.toString(), 'ALICE');
      });

      test('Private method calling another private method', () {
        final result = interpreter.eval('''
          class Calculator {
            #validate(n) {
              return typeof n === 'number';
            }
            
            #add(a, b) {
              if (!this.#validate(a) || !this.#validate(b)) {
                return NaN;
              }
              return a + b;
            }
            
            calculate(a, b) {
              return this.#add(a, b);
            }
          }
          
          const calc = new Calculator();
          [calc.calculate(5, 3), calc.calculate('a', 'b')]
        ''');
        expect(result.toString(), '8,NaN');
      });

      test('Private method with private field', () {
        final result = interpreter.eval('''
          class BankAccount {
            #balance = 0;
            
            #isValidAmount(amount) {
              return amount > 0;
            }
            
            deposit(amount) {
              if (this.#isValidAmount(amount)) {
                this.#balance += amount;
                return true;
              }
              return false;
            }
            
            getBalance() {
              return this.#balance;
            }
          }
          
          const account = new BankAccount();
          account.deposit(100);
          account.deposit(-50);
          account.getBalance()
        ''');
        expect(result.toNumber(), 100);
      });

      test('Private getter', () {
        final result = interpreter.eval('''
          class User {
            #firstName;
            #lastName;
            
            constructor(first, last) {
              this.#firstName = first;
              this.#lastName = last;
            }
            
            get #fullName() {
              return this.#firstName + ' ' + this.#lastName;
            }
            
            getDisplayName() {
              return this.#fullName;
            }
          }
          
          const user = new User('John', 'Doe');
          user.getDisplayName()
        ''');
        expect(result.toString(), 'John Doe');
      });

      test('Private setter', () {
        final result = interpreter.eval('''
          class Temperature {
            #celsius = 0;
            
            set #fahrenheit(f) {
              this.#celsius = (f - 32) * 5 / 9;
            }
            
            get #fahrenheit() {
              return (this.#celsius * 9 / 5) + 32;
            }
            
            setTempF(f) {
              this.#fahrenheit = f;
            }
            
            getTempC() {
              return this.#celsius;
            }
          }
          
          const temp = new Temperature();
          temp.setTempF(32);
          Math.round(temp.getTempC())
        ''');
        expect(result.toNumber(), 0);
      });
    });

    group('Static Fields', () {
      test('Public static field', () {
        final result = interpreter.eval('''
          class Counter {
            static count = 0;
            
            constructor() {
              Counter.count++;
            }
          }
          
          new Counter();
          new Counter();
          new Counter();
          Counter.count
        ''');
        expect(result.toNumber(), 3);
      });

      test('Static field with initializer', () {
        final result = interpreter.eval('''
          class Config {
            static version = '1.0.0';
            static maxUsers = 100;
            static enabled = true;
          }
          
          [Config.version, Config.maxUsers, Config.enabled]
        ''');
        expect(result.toString(), '1.0.0,100,true');
      });

      test('Multiple static fields', () {
        final result = interpreter.eval('''
          class MathConstants {
            static PI = 3.14159;
            static E = 2.71828;
            static PHI = 1.61803;
          }
          
          MathConstants.PI + MathConstants.E
        ''');
        expect(result.toNumber().toStringAsFixed(5), '5.85987');
      });

      test('Static field accessed in static method', () {
        final result = interpreter.eval('''
          class Settings {
            static theme = 'dark';
            
            static getTheme() {
              return Settings.theme;
            }
            
            static setTheme(newTheme) {
              Settings.theme = newTheme;
            }
          }
          
          const original = Settings.getTheme();
          Settings.setTheme('light');
          const changed = Settings.getTheme();
          [original, changed]
        ''');
        expect(result.toString(), 'dark,light');
      });

      test('Static field accessed in instance method', () {
        final result = interpreter.eval('''
          class Product {
            static taxRate = 0.2;
            
            constructor(price) {
              this.price = price;
            }
            
            getTotalPrice() {
              return this.price * (1 + Product.taxRate);
            }
          }
          
          const product = new Product(100);
          product.getTotalPrice()
        ''');
        expect(result.toNumber(), 120);
      });
    });

    group('Private Static Fields', () {
      test('Basic private static field', () {
        final result = interpreter.eval('''
          class DatabaseConnection {
            static #instanceCount = 0;
            
            constructor() {
              DatabaseConnection.#instanceCount++;
            }
            
            static getInstanceCount() {
              return DatabaseConnection.#instanceCount;
            }
          }
          
          new DatabaseConnection();
          new DatabaseConnection();
          DatabaseConnection.getInstanceCount()
        ''');
        expect(result.toNumber(), 2);
      });

      test('Private static field with private static method', () {
        final result = interpreter.eval('''
          class IDGenerator {
            static #counter = 0;
            
            static #increment() {
              return ++IDGenerator.#counter;
            }
            
            static generateID() {
              return 'ID_' + IDGenerator.#increment();
            }
          }
          
          const id1 = IDGenerator.generateID();
          const id2 = IDGenerator.generateID();
          const id3 = IDGenerator.generateID();
          [id1, id2, id3]
        ''');
        expect(result.toString(), 'ID_1,ID_2,ID_3');
      });

      test('Private static field encapsulation', () {
        final result = interpreter.eval('''
          class Logger {
            static #logs = [];
            
            static log(message) {
              Logger.#logs.push(message);
            }
            
            static getLogCount() {
              return Logger.#logs.length;
            }
            
            static clear() {
              Logger.#logs = [];
            }
          }
          
          Logger.log('Message 1');
          Logger.log('Message 2');
          Logger.log('Message 3');
          const count = Logger.getLogCount();
          Logger.clear();
          [count, Logger.getLogCount()]
        ''');
        expect(result.toString(), '3,0');
      });
    });

    group('Private Static Methods', () {
      test('Basic private static method', () {
        final result = interpreter.eval('''
          class Validator {
            static #isValidEmail(email) {
              return email.includes('@');
            }
            
            static validate(email) {
              return Validator.#isValidEmail(email);
            }
          }
          
          [Validator.validate('test@example.com'), Validator.validate('invalid')]
        ''');
        expect(result.toString(), 'true,false');
      });

      test('Private static method with private static field', () {
        final result = interpreter.eval('''
          class Cache {
            static #data = {};
            static #hits = 0;
            static #misses = 0;
            
            static #recordHit() {
              Cache.#hits++;
            }
            
            static #recordMiss() {
              Cache.#misses++;
            }
            
            static get(key) {
              if (key in Cache.#data) {
                Cache.#recordHit();
                return Cache.#data[key];
              }
              Cache.#recordMiss();
              return undefined;
            }
            
            static set(key, value) {
              Cache.#data[key] = value;
            }
            
            static getStats() {
              return {
                hits: Cache.#hits,
                misses: Cache.#misses
              };
            }
          }
          
          Cache.set('a', 1);
          Cache.get('a');
          Cache.get('a');
          Cache.get('b');
          Cache.getStats()
        ''');
        final stats = result as JSObject;
        expect(stats.getProperty('hits').toNumber(), 2);
        expect(stats.getProperty('misses').toNumber(), 1);
      });
    });

    group('Complex Combinations', () {
      test('All features together', () {
        final result = interpreter.eval('''
          class SecureCounter {
            // Private instance field
            #value = 0;
            
            // Private static field
            static #totalInstances = 0;
            
            // Public static field
            static maxValue = 100;
            
            constructor(initial) {
              this.#value = initial || 0;
              SecureCounter.#totalInstances++;
            }
            
            // Private instance method
            #isAtMax() {
              return this.#value >= SecureCounter.maxValue;
            }
            
            // Public instance method using private method
            increment() {
              if (!this.#isAtMax()) {
                this.#value++;
                return true;
              }
              return false;
            }
            
            // Public instance getter
            get value() {
              return this.#value;
            }
            
            // Private static method
            static #validateInitial(val) {
              return val >= 0 && val <= SecureCounter.maxValue;
            }
            
            // Public static method using private static field and method
            static create(initial) {
              if (SecureCounter.#validateInitial(initial)) {
                return new SecureCounter(initial);
              }
              return null;
            }
            
            static getInstanceCount() {
              return SecureCounter.#totalInstances;
            }
          }
          
          const c1 = SecureCounter.create(50);
          const c2 = SecureCounter.create(75);
          c1.increment();
          c1.increment();
          
          [c1.value, c2.value, SecureCounter.getInstanceCount()]
        ''');
        expect(result.toString(), '52,75,2');
      });

      test('Inheritance with private members', () {
        final result = interpreter.eval('''
          class Base {
            #basePrivate = 'base';
            
            #getBasePrivate() {
              return this.#basePrivate;
            }
            
            getBase() {
              return this.#getBasePrivate();
            }
          }
          
          class Derived extends Base {
            #derivedPrivate = 'derived';
            
            #getDerivedPrivate() {
              return this.#derivedPrivate;
            }
            
            getBoth() {
              return this.getBase() + '-' + this.#getDerivedPrivate();
            }
          }
          
          const obj = new Derived();
          obj.getBoth()
        ''');
        expect(result.toString(), 'base-derived');
      });

      test('Static initialization with private members', () {
        final result = interpreter.eval('''
          class App {
            static #initialized = false;
            static #config = null;
            
            static #setConfig() {
              App.#config = { version: '1.0' };
              App.#initialized = true;
            }
            
            static init() {
              if (!App.#initialized) {
                App.#setConfig();
              }
              return App.#initialized;
            }
            
            static getVersion() {
              if (App.#config) {
                return App.#config.version;
              }
              return null;
            }
          }
          
          const init1 = App.init();
          const version = App.getVersion();
          const init2 = App.init();
          
          [init1, version, init2]
        ''');
        expect(result.toString(), 'true,1.0,true');
      });
    });
  });
}
