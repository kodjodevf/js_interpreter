import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('ES6 Class Advanced Tests - Complete Coverage', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('complex multi-level inheritance with super calls', () {
      final code = '''
        class Vehicle {
          constructor(type) {
            this.type = type;
            this.wheels = 0;
          }
          
          getInfo() {
            return this.type + " with " + this.wheels + " wheels";
          }
          
          start() {
            return this.type + " starting";
          }
        }
        
        class MotorVehicle extends Vehicle {
          constructor(type, engine) {
            super(type);
            this.engine = engine;
            this.wheels = 4;
          }
          
          start() {
            return super.start() + " with " + this.engine + " engine";
          }
          
          getEngine() {
            return this.engine;
          }
        }
        
        class Car extends MotorVehicle {
          constructor(brand, engine, doors) {
            super("Car", engine);
            this.brand = brand;
            this.doors = doors;
          }
          
          start() {
            return this.brand + " " + super.start();
          }
          
          getFullInfo() {
            return super.getInfo() + ", " + this.doors + " doors, brand: " + this.brand;
          }
        }
        
        const myCar = new Car("Toyota", "V6", 4);
        const info = myCar.getFullInfo();
        const startMsg = myCar.start();
        const engine = myCar.getEngine();
        
        [info, startMsg, engine];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('Car with 4 wheels'));
      expect(result.toString(), contains('4 doors'));
      expect(result.toString(), contains('Toyota'));
      expect(result.toString(), contains('Toyota Car starting with V6 engine'));
      expect(result.toString(), contains('V6'));
    });

    test('static methods and static inheritance', () {
      final code = '''
        class MathOperations {
          static add(a, b) {
            return a + b;
          }
          
          static multiply(a, b) {
            return a * b;
          }
          
          static calculate(a, b, operation) {
            if (operation === "add") {
              return this.add(a, b);
            }
            return this.multiply(a, b);
          }
        }
        
        class AdvancedMath extends MathOperations {
          static power(a, b) {
            let result = 1;
            for (let i = 0; i < b; i++) {
              result = this.multiply(result, a);
            }
            return result;
          }
          
          static addAndPower(a, b, exp) {
            const sum = this.add(a, b);
            return this.power(sum, exp);
          }
        }
        
        const sum = MathOperations.add(10, 5);
        const product = MathOperations.calculate(10, 5, "multiply");
        const power = AdvancedMath.power(2, 8);
        const combined = AdvancedMath.addAndPower(3, 2, 3);
        
        [sum, product, power, combined];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('15'));
      expect(result.toString(), contains('50'));
      expect(result.toString(), contains('256'));
      expect(result.toString(), contains('125')); // (3+2)^3 = 5^3 = 125
    });

    test('getters and setters with validation', () {
      final code = '''
        class Temperature {
          constructor(celsius) {
            this._celsius = celsius;
          }
          
          get celsius() {
            return this._celsius;
          }
          
          set celsius(value) {
            if (value < -273.15) {
              throw new Error("Temperature cannot be below absolute zero");
            }
            this._celsius = value;
          }
          
          get fahrenheit() {
            return (this._celsius * 9/5) + 32;
          }
          
          set fahrenheit(value) {
            this.celsius = (value - 32) * 5/9;
          }
          
          get kelvin() {
            return this._celsius + 273.15;
          }
        }
        
        const temp = new Temperature(25);
        const c1 = temp.celsius;
        const f1 = temp.fahrenheit;
        const k1 = temp.kelvin;
        
        temp.celsius = 0;
        const c2 = temp.celsius;
        const f2 = temp.fahrenheit;
        
        temp.fahrenheit = 212;
        const c3 = temp.celsius;
        
        [c1, f1, k1, c2, f2, c3];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('25'));
      expect(result.toString(), contains('77'));
      expect(result.toString(), contains('298.15'));
      expect(result.toString(), contains('0'));
      expect(result.toString(), contains('32'));
      expect(result.toString(), contains('100'));
    });

    test('method chaining with fluent interface', () {
      final code = '''
        class QueryBuilder {
          constructor() {
            this.query = "";
            this.params = [];
          }
          
          select(fields) {
            this.query = "SELECT " + fields;
            return this;
          }
          
          from(table) {
            this.query = this.query + " FROM " + table;
            return this;
          }
          
          where(condition) {
            this.query = this.query + " WHERE " + condition;
            return this;
          }
          
          orderBy(field) {
            this.query = this.query + " ORDER BY " + field;
            return this;
          }
          
          build() {
            return this.query;
          }
        }
        
        const query1 = new QueryBuilder()
          .select("*")
          .from("users")
          .where("age > 18")
          .orderBy("name")
          .build();
          
        const query2 = new QueryBuilder()
          .select("name, email")
          .from("customers")
          .build();
        
        [query1, query2];
      ''';

      final result = interpreter.eval(code);
      expect(
        result.toString(),
        contains('SELECT * FROM users WHERE age > 18 ORDER BY name'),
      );
      expect(result.toString(), contains('SELECT name, email FROM customers'));
    });

    test('super in nested method calls and constructor chains', () {
      final code = '''
        class Counter {
          constructor(start) {
            this.count = start || 0;
          }
          
          increment() {
            this.count++;
            return this.count;
          }
          
          getValue() {
            return this.count;
          }
        }
        
        class DoubleCounter extends Counter {
          constructor(start) {
            super(start);
            this.multiplier = 2;
          }
          
          increment() {
            super.increment();
            super.increment();
            return this.getValue();
          }
        }
        
        class TripleCounter extends DoubleCounter {
          constructor(start) {
            super(start);
            this.multiplier = 3;
          }
          
          increment() {
            super.increment();
            this.count++;
            return this.getValue();
          }
        }
        
        const counter1 = new Counter(10);
        counter1.increment();
        counter1.increment();
        const v1 = counter1.getValue();
        
        const counter2 = new DoubleCounter(10);
        counter2.increment();
        const v2 = counter2.getValue();
        
        const counter3 = new TripleCounter(10);
        counter3.increment();
        const v3 = counter3.getValue();
        
        [v1, v2, v3];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('12'));
      expect(result.toString(), contains('12'));
      expect(result.toString(), contains('13'));
    });

    test('instanceof with inheritance hierarchy', () {
      final code = '''
        class Animal {
          constructor(name) {
            this.name = name;
          }
        }
        
        class Mammal extends Animal {
          constructor(name, furColor) {
            super(name);
            this.furColor = furColor;
          }
        }
        
        class Dog extends Mammal {
          constructor(name, furColor, breed) {
            super(name, furColor);
            this.breed = breed;
          }
        }
        
        const dog = new Dog("Rex", "brown", "Labrador");
        
        const isDog = dog instanceof Dog;
        const isMammal = dog instanceof Mammal;
        const isAnimal = dog instanceof Animal;
        const isObject = dog instanceof Object;
        
        [isDog, isMammal, isAnimal, isObject];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('true'));
    });

    test('static properties and methods with this context', () {
      final code = '''
        class Database {
          static connection = null;
          static queryCount = 0;
          
          static connect() {
            this.connection = "connected";
            return this.connection;
          }
          
          static query(sql) {
            if (this.connection === null) {
              this.connect();
            }
            this.queryCount++;
            return "Executed: " + sql + " (Query #" + this.queryCount + ")";
          }
          
          static getStats() {
            return {
              connected: this.connection !== null,
              queries: this.queryCount
            };
          }
        }
        
        const result1 = Database.query("SELECT * FROM users");
        const result2 = Database.query("INSERT INTO logs");
        const stats = Database.getStats();
        
        [result1, result2, stats.queries];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('Query #1'));
      expect(result.toString(), contains('Query #2'));
      expect(result.toString(), contains('2'));
    });

    test('class expressions and anonymous classes', () {
      final code = '''
        const MyClass = class {
          constructor(value) {
            this.value = value;
          }
          
          getValue() {
            return this.value;
          }
        };
        
        const instance1 = new MyClass(42);
        const v1 = instance1.getValue();
        
        const NamedClass = class CustomName {
          constructor(name) {
            this.name = name;
          }
          
          getName() {
            return this.name;
          }
        };
        
        const instance2 = new NamedClass("Test");
        const v2 = instance2.getName();
        
        [v1, v2];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('42'));
      expect(result.toString(), contains('Test'));
    });

    test('complex constructor logic with multiple super calls scenarios', () {
      final code = '''
        class Shape {
          constructor(color) {
            this.color = color;
            this.area = 0;
          }
          
          getColor() {
            return this.color;
          }
        }
        
        class Rectangle extends Shape {
          constructor(color, width, height) {
            super(color);
            this.width = width;
            this.height = height;
            this.area = width * height;
          }
          
          getArea() {
            return this.area;
          }
        }
        
        class Square extends Rectangle {
          constructor(color, side) {
            super(color, side, side);
            this.side = side;
          }
          
          getSide() {
            return this.side;
          }
        }
        
        const square = new Square("red", 5);
        const color = square.getColor();
        const area = square.getArea();
        const side = square.getSide();
        
        [color, area, side];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('red'));
      expect(result.toString(), contains('25'));
      expect(result.toString(), contains('5'));
    });

    test('mixins pattern with multiple inheritance simulation', () {
      final code = '''
        class Base {
          constructor() {
            this.baseValue = "base";
          }
        }
        
        function Flyable(superClass) {
          return class extends superClass {
            fly() {
              return this.name + " is flying";
            }
          };
        }
        
        function Swimmable(superClass) {
          return class extends superClass {
            swim() {
              return this.name + " is swimming";
            }
          };
        }
        
        class Duck extends Swimmable(Flyable(Base)) {
          constructor(name) {
            super();
            this.name = name;
          }
        }
        
        const duck = new Duck("Donald");
        const flyMsg = duck.fly();
        const swimMsg = duck.swim();
        const baseVal = duck.baseValue;
        
        [flyMsg, swimMsg, baseVal];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('Donald is flying'));
      expect(result.toString(), contains('Donald is swimming'));
      expect(result.toString(), contains('base'));
    });

    test('protected-like behavior using naming conventions', () {
      final code = '''
        class Account {
          constructor(balance) {
            this._balance = balance;
          }
          
          _validateAmount(amount) {
            return amount > 0 && amount <= this._balance;
          }
          
          withdraw(amount) {
            if (this._validateAmount(amount)) {
              this._balance -= amount;
              return true;
            }
            return false;
          }
          
          getBalance() {
            return this._balance;
          }
        }
        
        class SavingsAccount extends Account {
          constructor(balance, interestRate) {
            super(balance);
            this._interestRate = interestRate;
          }
          
          addInterest() {
            const interest = this._balance * this._interestRate;
            this._balance += interest;
            return this._balance;
          }
          
          withdraw(amount) {
            if (amount > 500) {
              return false;
            }
            return super.withdraw(amount);
          }
        }
        
        const account = new SavingsAccount(1000, 0.05);
        const w1 = account.withdraw(200);
        const b1 = account.getBalance();
        const w2 = account.withdraw(600);
        const b2 = account.getBalance();
        const newBalance = account.addInterest();
        
        [w1, b1, w2, b2, newBalance];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('true'));
      expect(result.toString(), contains('800'));
      expect(result.toString(), contains('false'));
      expect(result.toString(), contains('840'));
    });

    test('class with computed method names and symbols', () {
      final code = '''
        const methodName = "dynamicMethod";
        const prefix = "get";
        
        class DynamicClass {
          constructor(value) {
            this.value = value;
          }
          
          [methodName]() {
            return "dynamic: " + this.value;
          }
          
          [prefix + "Value"]() {
            return this.value;
          }
          
          ["computed" + "Name"]() {
            return "computed";
          }
        }
        
        const obj = new DynamicClass(42);
        const r1 = obj.dynamicMethod();
        const r2 = obj.getValue();
        const r3 = obj.computedName();
        
        [r1, r2, r3];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('dynamic: 42'));
      expect(result.toString(), contains('42'));
      expect(result.toString(), contains('computed'));
    });

    test('class factory pattern', () {
      final code = '''
        class Product {
          constructor(name, price) {
            this.name = name;
            this.price = price;
          }
          
          static create(type, name, price) {
            if (type === "book") {
              return new Book(name, price);
            } else if (type === "electronic") {
              return new Electronic(name, price);
            }
            return new Product(name, price);
          }
          
          getInfo() {
            return this.name + ": \$" + this.price;
          }
        }
        
        class Book extends Product {
          constructor(name, price) {
            super(name, price);
            this.type = "Book";
          }
          
          getInfo() {
            return this.type + " - " + super.getInfo();
          }
        }
        
        class Electronic extends Product {
          constructor(name, price) {
            super(name, price);
            this.type = "Electronic";
          }
          
          getInfo() {
            return this.type + " - " + super.getInfo();
          }
        }
        
        const book = Product.create("book", "JavaScript Guide", 29.99);
        const electronic = Product.create("electronic", "Laptop", 999.99);
        const generic = Product.create("other", "Item", 5.99);
        
        const info1 = book.getInfo();
        const info2 = electronic.getInfo();
        const info3 = generic.getInfo();
        
        [info1, info2, info3];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('Book - JavaScript Guide: \$29.99'));
      expect(result.toString(), contains('Electronic - Laptop: \$999.99'));
      expect(result.toString(), contains('Item: \$5.99'));
    });

    test('singleton pattern with static instance', () {
      final code = '''
        class Singleton {
          static instance = null;
          
          constructor(value) {
            if (Singleton.instance !== null) {
              return Singleton.instance;
            }
            this.value = value;
            Singleton.instance = this;
          }
          
          getValue() {
            return this.value;
          }
          
          setValue(newValue) {
            this.value = newValue;
          }
        }
        
        const s1 = new Singleton(42);
        const v1 = s1.getValue();
        
        const s2 = new Singleton(100);
        const v2 = s2.getValue();
        
        s1.setValue(99);
        const v3 = s2.getValue();
        
        const areSame = s1 === s2;
        
        [v1, v2, v3, areSame];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('42'));
      expect(result.toString(), contains('99'));
      expect(result.toString(), contains('true'));
    });

    test('builder pattern with method chaining', () {
      final code = '''
        class Person {
          constructor(builder) {
            this.name = builder.name;
            this.age = builder.age;
            this.email = builder.email;
            this.phone = builder.phone;
          }
          
          getInfo() {
            let info = "Name: " + this.name;
            if (this.age !== undefined) info += ", Age: " + this.age;
            if (this.email !== undefined) info += ", Email: " + this.email;
            if (this.phone !== undefined) info += ", Phone: " + this.phone;
            return info;
          }
        }
        
        class PersonBuilder {
          constructor(name) {
            this.name = name;
          }
          
          setAge(age) {
            this.age = age;
            return this;
          }
          
          setEmail(email) {
            this.email = email;
            return this;
          }
          
          setPhone(phone) {
            this.phone = phone;
            return this;
          }
          
          build() {
            return new Person(this);
          }
        }
        
        const person1 = new PersonBuilder("Alice")
          .setAge(30)
          .setEmail("alice@example.com")
          .build();
          
        const person2 = new PersonBuilder("Bob")
          .setAge(25)
          .build();
        
        const info1 = person1.getInfo();
        const info2 = person2.getInfo();
        
        [info1, info2];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('Alice'));
      expect(result.toString(), contains('30'));
      expect(result.toString(), contains('alice@example.com'));
      expect(result.toString(), contains('Bob'));
      expect(result.toString(), contains('25'));
    });

    test('observer pattern with classes', () {
      final code = '''
        class Subject {
          constructor() {
            this.observers = [];
          }
          
          addObserver(observer) {
            this.observers.push(observer);
          }
          
          removeObserver(observer) {
            const index = this.observers.indexOf(observer);
            if (index > -1) {
              this.observers.splice(index, 1);
            }
          }
          
          notify(data) {
            for (let i = 0; i < this.observers.length; i++) {
              this.observers[i].update(data);
            }
          }
        }
        
        class Observer {
          constructor(name) {
            this.name = name;
            this.data = null;
          }
          
          update(data) {
            this.data = data;
          }
          
          getData() {
            return this.name + ": " + this.data;
          }
        }
        
        const subject = new Subject();
        const obs1 = new Observer("Observer1");
        const obs2 = new Observer("Observer2");
        
        subject.addObserver(obs1);
        subject.addObserver(obs2);
        
        subject.notify("First notification");
        const r1 = obs1.getData();
        const r2 = obs2.getData();
        
        subject.notify("Second notification");
        const r3 = obs1.getData();
        const r4 = obs2.getData();
        
        [r1, r2, r3, r4];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('Observer1: First notification'));
      expect(result.toString(), contains('Observer2: First notification'));
      expect(result.toString(), contains('Observer1: Second notification'));
      expect(result.toString(), contains('Observer2: Second notification'));
    });

    test('getters and setters in inheritance chain', () {
      final code = '''
        class Person {
          constructor(firstName, lastName) {
            this._firstName = firstName;
            this._lastName = lastName;
          }
          
          get fullName() {
            return this._firstName + " " + this._lastName;
          }
          
          set fullName(name) {
            const parts = name.split(" ");
            this._firstName = parts[0];
            this._lastName = parts[1];
          }
        }
        
        class Employee extends Person {
          constructor(firstName, lastName, id) {
            super(firstName, lastName);
            this._id = id;
          }
          
          get fullName() {
            return super.fullName + " (ID: " + this._id + ")";
          }
          
          get id() {
            return this._id;
          }
          
          set id(newId) {
            if (newId > 0) {
              this._id = newId;
            }
          }
        }
        
        const emp = new Employee("John", "Doe", 123);
        const name1 = emp.fullName;
        
        emp.fullName = "Jane Smith";
        const name2 = emp.fullName;
        
        emp.id = 456;
        const id1 = emp.id;
        
        [name1, name2, id1];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('John Doe (ID: 123)'));
      expect(result.toString(), contains('Jane Smith (ID: 123)'));
      expect(result.toString(), contains('456'));
    });

    test('class with array and object methods', () {
      final code = '''
        class Collection {
          constructor() {
            this.items = [];
          }
          
          add(item) {
            this.items.push(item);
            return this;
          }
          
          remove(item) {
            const index = this.items.indexOf(item);
            if (index > -1) {
              this.items.splice(index, 1);
            }
            return this;
          }
          
          map(fn) {
            return this.items.map(fn);
          }
          
          filter(fn) {
            return this.items.filter(fn);
          }
          
          reduce(fn, initial) {
            return this.items.reduce(fn, initial);
          }
          
          size() {
            return this.items.length;
          }
        }
        
        const collection = new Collection();
        collection.add(1).add(2).add(3).add(4).add(5);
        
        const doubled = collection.map(x => x * 2);
        const evens = collection.filter(x => x % 2 === 0);
        const sum = collection.reduce((acc, x) => acc + x, 0);
        const size = collection.size();
        
        [doubled.join(","), evens.join(","), sum, size];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('2,4,6,8,10'));
      expect(result.toString(), contains('2,4'));
      expect(result.toString(), contains('15'));
      expect(result.toString(), contains('5'));
    });

    test('class with private-like properties and methods', () {
      final code = '''
        class BankAccount {
          constructor(accountNumber, initialBalance) {
            this._accountNumber = accountNumber;
            this._balance = initialBalance;
            this._transactions = [];
          }
          
          _addTransaction(type, amount) {
            this._transactions.push({
              type: type,
              amount: amount,
              balance: this._balance
            });
          }
          
          deposit(amount) {
            if (amount > 0) {
              this._balance += amount;
              this._addTransaction("deposit", amount);
              return true;
            }
            return false;
          }
          
          withdraw(amount) {
            if (amount > 0 && amount <= this._balance) {
              this._balance -= amount;
              this._addTransaction("withdrawal", amount);
              return true;
            }
            return false;
          }
          
          getBalance() {
            return this._balance;
          }
          
          getTransactionCount() {
            return this._transactions.length;
          }
          
          getLastTransaction() {
            if (this._transactions.length > 0) {
              const last = this._transactions[this._transactions.length - 1];
              return last.type + ": " + last.amount;
            }
            return "No transactions";
          }
        }
        
        const account = new BankAccount("123456", 1000);
        account.deposit(500);
        account.withdraw(200);
        account.deposit(100);
        
        const balance = account.getBalance();
        const count = account.getTransactionCount();
        const last = account.getLastTransaction();
        
        [balance, count, last];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('1400'));
      expect(result.toString(), contains('3'));
      expect(result.toString(), contains('deposit: 100'));
    });

    test('class with static and instance properties interaction', () {
      final code = '''
        class Counter {
          static totalInstances = 0;
          static totalCount = 0;
          
          constructor(initialValue) {
            this.value = initialValue || 0;
            Counter.totalInstances++;
          }
          
          increment() {
            this.value++;
            Counter.totalCount++;
            return this.value;
          }
          
          static getStats() {
            return "Instances: " + this.totalInstances + ", Total Count: " + this.totalCount;
          }
          
          static reset() {
            this.totalCount = 0;
          }
        }
        
        const c1 = new Counter(10);
        const c2 = new Counter(20);
        
        c1.increment();
        c1.increment();
        c2.increment();
        
        const v1 = c1.value;
        const v2 = c2.value;
        const stats1 = Counter.getStats();
        
        Counter.reset();
        c1.increment();
        const stats2 = Counter.getStats();
        
        [v1, v2, stats1, stats2];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('12'));
      expect(result.toString(), contains('21'));
      expect(result.toString(), contains('Instances: 2, Total Count: 3'));
      expect(result.toString(), contains('Instances: 2, Total Count: 1'));
    });

    test('complex class with all ES6 features combined', () {
      final code = '''
        class EventEmitter {
          constructor() {
            this._events = {};
            this._maxListeners = 10;
          }
          
          on(event, listener) {
            if (!this._events[event]) {
              this._events[event] = [];
            }
            if (this._events[event].length < this._maxListeners) {
              this._events[event].push(listener);
            }
            return this;
          }
          
          emit(event, data) {
            if (this._events[event]) {
              for (let i = 0; i < this._events[event].length; i++) {
                this._events[event][i](data);
              }
            }
            return this;
          }
          
          get eventCount() {
            let count = 0;
            for (let key in this._events) {
              count++;
            }
            return count;
          }
        }
        
        class TypedEventEmitter extends EventEmitter {
          constructor(allowedTypes) {
            super();
            this.allowedTypes = allowedTypes;
          }
          
          on(event, listener) {
            if (this.allowedTypes.indexOf(event) === -1) {
              throw new Error("Event type not allowed: " + event);
            }
            return super.on(event, listener);
          }
          
          static create(types) {
            return new TypedEventEmitter(types);
          }
        }
        
        let result1 = "";
        let result2 = "";
        
        const emitter = TypedEventEmitter.create(["data", "error"]);
        
        emitter
          .on("data", function(msg) { result1 = "Data: " + msg; })
          .on("error", function(msg) { result2 = "Error: " + msg; });
        
        emitter.emit("data", "Hello");
        const r1 = result1;
        
        emitter.emit("error", "Something went wrong");
        const r2 = result2;
        
        const count = emitter.eventCount;
        
        [r1, r2, count];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), contains('Data: Hello'));
      expect(result.toString(), contains('Error: Something went wrong'));
      expect(result.toString(), contains('2'));
    });
  });
}
