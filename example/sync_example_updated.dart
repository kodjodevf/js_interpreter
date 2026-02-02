/// Synchronous JavaScript Evaluation Examples
///
/// Demonstrates basic synchronous JavaScript evaluation patterns
/// without async/await, focusing on core JavaScript features.
library;

import 'package:js_interpreter/js_interpreter.dart';

void main() {
  final interpreter = JSInterpreter();

  print('=== Basic Arithmetic & Strings ===');

  final result1 = interpreter.eval('''
    const a = 10;
    const b = 20;
    const sum = a + b;
    const message = "Sum is " + sum;
    message;
  ''');
  print('Result: $result1');

  print('\n=== Objects and Properties ===');

  final result2 = interpreter.eval('''
    const person = {
      name: "Alice",
      age: 30,
      city: "Paris",
      greet: function() {
        return "Hello, I'm " + this.name;
      }
    };
    
    person.greet();
  ''');
  print('Greeting: $result2');

  print('\n=== Arrays and Iteration ===');

  final result3 = interpreter.eval('''
    (function() {
      const numbers = [1, 2, 3, 4, 5];
      let total = 0;
      
      for (let i = 0; i < numbers.length; i++) {
        total += numbers[i];
      }
      
      return ({total: total, count: numbers.length, average: total / numbers.length});
    })()
  ''');
  print('Array stats: $result3');

  print('\n=== Functions ===');

  final result4 = interpreter.eval('''
    function factorial(n) {
      if (n <= 1) return 1;
      return n * factorial(n - 1);
    }
    
    const result = factorial(5);
    result;
  ''');
  print('Factorial(5): $result4');

  print('\n=== Arrow Functions ===');

  final result5 = interpreter.eval('''
    const double = x => x * 2;
    const triple = x => x * 3;
    
    const numbers = [1, 2, 3, 4, 5];
    const doubled = numbers.map(double);
    const tripled = numbers.map(triple);
    
    { doubled, tripled };
  ''');
  print('Arrow functions: $result5');

  print('\n=== Classes ===');

  final result6 = interpreter.eval('''
    class Calculator {
      constructor(name) {
        this.name = name;
      }
      
      add(a, b) {
        return a + b;
      }
      
      multiply(a, b) {
        return a * b;
      }
      
      describe() {
        return this.name + " calculator";
      }
    }
    
    const calc = new Calculator("Scientific");
    ({
      description: calc.describe(),
      add: calc.add(5, 3),
      multiply: calc.multiply(4, 7)
    });
  ''');
  print('Classes: $result6');

  print('\n=== Map/Filter/Reduce ===');

  final result7 = interpreter.eval('''
    (function() {
      const numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      
      const evenNumbers = numbers.filter(n => n % 2 === 0);
      const squared = evenNumbers.map(n => n * n);
      const total = squared.reduce((a, b) => a + b, 0);
      
      return ({
        original: numbers.length,
        even: evenNumbers.length,
        squared: squared,
        sum: total
      });
    })()
  ''');
  print('Map/Filter/Reduce: $result7');

  print('\n=== Destructuring ===');

  final result8 = interpreter.eval('''
    const person = { name: "Bob", age: 25, city: "London" };
    const { name, age } = person;
    
    const arr = [10, 20, 30, 40];
    const [first, second] = arr;
    
    ({
      personName: name,
      personAge: age,
      firstElement: first,
      secondElement: second
    });
  ''');
  print('Destructuring: $result8');

  print('\n=== Spread Operator ===');

  final result9 = interpreter.eval('''
    const arr1 = [1, 2, 3];
    const arr2 = [4, 5, 6];
    const combined = [...arr1, ...arr2];
    
    const obj1 = { a: 1, b: 2 };
    const obj2 = { c: 3, d: 4 };
    const merged = { ...obj1, ...obj2 };
    
    ({ combined, merged });
  ''');
  print('Spread: $result9');

  print('\n=== Template Strings ===');

  final result10 = interpreter.eval('''
    const name = "Charlie";
    const age = 35;
    const city = "Berlin";
    
    const message = `Hello, I'm \${name}, \${age} years old from \${city}`;
    message;
  ''');
  print('Template: $result10');

  print('\n=== Conditional & Ternary ===');

  final result11 = interpreter.eval('''
    const scores = [45, 65, 85, 92];
    
    const grades = scores.map(score => {
      if (score >= 90) return 'A';
      if (score >= 80) return 'B';
      if (score >= 70) return 'C';
      if (score >= 60) return 'D';
      return 'F';
    });
    
    ({ scores, grades });
  ''');
  print('Conditionals: $result11');

  print('\n=== Math Operations ===');

  final result12 = interpreter.eval('''
    {
      sqrt: Math.sqrt(16),
      pow: Math.pow(2, 8),
      floor: Math.floor(3.7),
      ceil: Math.ceil(3.2),
      round: Math.round(3.5),
      max: Math.max(10, 5, 8, 3),
      min: Math.min(10, 5, 8, 3),
      random: Math.random() > 0 ? "random" : "error",
      pi: Math.PI
    };
  ''');
  print('Math: $result12');

  print('\n=== String Methods ===');

  final result13 = interpreter.eval('''
    const str = "  Hello World  ";
    
    ({
      trim: str.trim(),
      upper: str.toUpperCase(),
      lower: str.toLowerCase(),
      includes: str.includes("World"),
      startsWith: str.trim().startsWith("Hello"),
      split: str.trim().split(" "),
      length: str.length,
      charAt0: str.charAt(2)
    });
  ''');
  print('Strings: $result13');

  print('\n=== JSON Stringify/Parse ===');

  final result14 = interpreter.eval('''
    const data = {
      name: "Diana",
      skills: ["Dart", "JavaScript", "Python"],
      verified: true,
      rating: 4.8
    };
    
    const jsonString = JSON.stringify(data);
    const parsed = JSON.parse(jsonString);
    
    ({
      original: data.name,
      jsonString: jsonString,
      parsedName: parsed.name,
      skillCount: parsed.skills.length
    });
  ''');
  print('JSON: $result14');

  print('\n=== Switch Statement ===');

  final result15 = interpreter.eval('''
    function getDayName(dayNumber) {
      switch(dayNumber) {
        case 1: return "Monday";
        case 2: return "Tuesday";
        case 3: return "Wednesday";
        case 4: return "Thursday";
        case 5: return "Friday";
        case 6: return "Saturday";
        case 7: return "Sunday";
        default: return "Invalid day";
      }
    }
    
    ({
      day1: getDayName(1),
      day6: getDayName(6),
      day9: getDayName(9)
    });
  ''');
  print('Switch: $result15');

  print('\n=== Object Methods ===');

  final result16 = interpreter.eval('''
    const person = {
      firstName: "Eve",
      lastName: "Johnson",
      fullName: function() {
        return this.firstName + " " + this.lastName;
      },
      updateFirstName: function(newName) {
        this.firstName = newName;
        return this;
      }
    };
    
    ({
      fullName: person.fullName(),
      keys: Object.keys(person).length,
      hasFirstName: person.hasOwnProperty("firstName")
    });
  ''');
  print('Object Methods: $result16');

  print('\n=== Regular Expressions ===');

  final result17 = interpreter.eval('''
    const email = "user@example.com";
    const emailRegex = /^[^@]+@[^@]+\\.[^@]+\$/;
    
    const phone = "123-456-7890";
    const phoneRegex = /^\\d{3}-\\d{3}-\\d{4}\$/;
    
    ({
      emailValid: emailRegex.test(email),
      phoneValid: phoneRegex.test(phone),
      emailMatch: email.match(/([a-z]+)/).length > 0
    });
  ''');
  print('RegExp: $result17');

  print('\n=== Closures ===');

  final result18 = interpreter.eval('''
    function makeCounter(start) {
      let count = start;
      
      return {
        increment: function() {
          return ++count;
        },
        decrement: function() {
          return --count;
        },
        current: function() {
          return count;
        }
      };
    }
    
    const counter = makeCounter(10);
    ({
      initial: counter.current(),
      afterInc: counter.increment(),
      afterDec: counter.decrement(),
      final: counter.current()
    });
  ''');
  print('Closures: $result18');

  print('\n=== Done! ===');
}
