import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });

  group('Advanced Use Cases and Complex Patterns', () {
    test('Builder Pattern Implementation', () {
      final code = '''
        // Builder pattern for complex object creation
        function UserBuilder() {
          this.user = {};

          this.setName = function(name) {
            this.user.name = name;
            return this;
          };

          this.setAge = function(age) {
            this.user.age = age;
            return this;
          };

          this.setEmail = function(email) {
            this.user.email = email;
            return this;
          };

          this.addHobby = function(hobby) {
            if (!this.user.hobbies) {
              this.user.hobbies = [];
            }
            this.user.hobbies.push(hobby);
            return this;
          };

          this.setActive = function(active) {
            this.user.active = active;
            return this;
          };

          this.build = function() {
            return this.user;
          };
        }

        // Usage
        const user = new UserBuilder()
          .setName('Alice')
          .setAge(25)
          .setEmail('alice@example.com')
          .addHobby('reading')
          .addHobby('coding')
          .setActive(true)
          .build();

        [user.name, user.age, user.email, user.hobbies.length, user.active];
      ''';

      final result = interpreter.eval(code);
      final results = (result as JSArray).toList();

      expect(results[0], equals('Alice'));
      expect(results[1], equals(25.0));
      expect(results[2], equals('alice@example.com'));
      expect(results[3], equals(2.0));
      expect(results[4], equals(true));
    });

    test('Strategy Pattern for Algorithms', () {
      final code = '''
        // Strategy pattern for different sorting algorithms
        const Sorter = {
          strategies: {
            bubbleSort: function(arr) {
              const result = arr.slice();
              for (let i = 0; i < result.length - 1; i++) {
                for (let j = 0; j < result.length - i - 1; j++) {
                  if (result[j] > result[j + 1]) {
                    const temp = result[j];
                    result[j] = result[j + 1];
                    result[j + 1] = temp;
                  }
                }
              }
              return result;
            },

            quickSort: function(arr) {
              if (arr.length <= 1) {
                return arr.slice();
              }

              const pivot = arr[0];
              const left = [];
              const right = [];

              for (let i = 1; i < arr.length; i++) {
                if (arr[i] < pivot) {
                  left.push(arr[i]);
                } else {
                  right.push(arr[i]);
                }
              }

              return this.quickSort(left).concat([pivot]).concat(this.quickSort(right));
            }
          },

          sort: function(data, strategy) {
            if (this.strategies[strategy]) {
              return this.strategies[strategy](data);
            }
            throw new Error('Unknown sorting strategy: ' + strategy);
          }
        };

        // Test data
        const numbers = [64, 34, 25, 12, 22, 11, 90];

        const bubbleSorted = Sorter.sort(numbers, 'bubbleSort');
        const quickSorted = Sorter.sort(numbers, 'quickSort');

        // Both should produce the same result
        const expected = [11, 12, 22, 25, 34, 64, 90];

        [bubbleSorted.length, quickSorted.length, bubbleSorted[0], bubbleSorted[6]];
      ''';

      final result = interpreter.eval(code);
      final results = (result as JSArray).toList();

      expect(results[0], equals(7.0)); // bubble sorted length
      expect(results[1], equals(7.0)); // quick sorted length
      expect(results[2], equals(11.0)); // first element
      expect(results[3], equals(90.0)); // last element
    });

    test('Decorator Pattern for Object Enhancement', () {
      final code = '''
        // Base component
        function Coffee() {
          this.cost = function() {
            return 5;
          };

          this.description = function() {
            return 'Coffee';
          };
        }

        // Decorator base
        function CoffeeDecorator(coffee) {
          this.coffee = coffee;
        }

        CoffeeDecorator.prototype.cost = function() {
          return this.coffee.cost();
        };

        CoffeeDecorator.prototype.description = function() {
          return this.coffee.description();
        };

        // Concrete decorators
        function MilkDecorator(coffee) {
          CoffeeDecorator.call(this, coffee);
        }

        MilkDecorator.prototype = Object.create(CoffeeDecorator.prototype);
        MilkDecorator.prototype.constructor = MilkDecorator;

        MilkDecorator.prototype.cost = function() {
          return this.coffee.cost() + 1.5;
        };

        MilkDecorator.prototype.description = function() {
          return this.coffee.description() + ', milk';
        };

        function SugarDecorator(coffee) {
          CoffeeDecorator.call(this, coffee);
        }

        SugarDecorator.prototype = Object.create(CoffeeDecorator.prototype);
        SugarDecorator.prototype.constructor = SugarDecorator;

        SugarDecorator.prototype.cost = function() {
          return this.coffee.cost() + 0.5;
        };

        SugarDecorator.prototype.description = function() {
          return this.coffee.description() + ', sugar';
        };

        // Usage
        const coffee = new Coffee();
        const coffeeWithMilk = new MilkDecorator(coffee);
        const fancyCoffee = new SugarDecorator(new MilkDecorator(coffee));

        const results = [
          coffee.cost(),                    // 5
          coffee.description(),             // 'Coffee'
          coffeeWithMilk.cost(),            // 6.5
          coffeeWithMilk.description(),     // 'Coffee, milk'
          fancyCoffee.cost(),               // 7.0
          fancyCoffee.description()         // 'Coffee, milk, sugar'
        ];

        results;
      ''';

      final result = interpreter.eval(code);
      final results = (result as JSArray).toList();

      expect(results[0], equals(5.0)); // base coffee cost
      expect(results[1], equals('Coffee')); // base description
      expect(results[2], equals(6.5)); // coffee with milk cost
      expect(
        results[3],
        equals('Coffee, milk'),
      ); // coffee with milk description
      expect(results[4], equals(7.0)); // fancy coffee cost
      expect(
        results[5],
        equals('Coffee, milk, sugar'),
      ); // fancy coffee description
    });

    test('Iterator Pattern Implementation', () {
      final code = '''
        // Custom iterator for a collection
        function ListIterator(items) {
          this.items = items;
          this.index = 0;
        }

        ListIterator.prototype.hasNext = function() {
          return this.index < this.items.length;
        };

        ListIterator.prototype.next = function() {
          if (!this.hasNext()) {
            throw new Error('No more elements');
          }
          return this.items[this.index++];
        };

        ListIterator.prototype.reset = function() {
          this.index = 0;
        };

        // Collection with iterator
        function NumberList() {
          this.numbers = [];
        }

        NumberList.prototype.add = function(number) {
          this.numbers.push(number);
        };

        NumberList.prototype.iterator = function() {
          return new ListIterator(this.numbers);
        };

        NumberList.prototype.sum = function() {
          const iterator = this.iterator();
          let sum = 0;
          while (iterator.hasNext()) {
            sum += iterator.next();
          }
          return sum;
        };

        NumberList.prototype.filter = function(predicate) {
          const iterator = this.iterator();
          const result = new NumberList();
          while (iterator.hasNext()) {
            const item = iterator.next();
            if (predicate(item)) {
              result.add(item);
            }
          }
          return result;
        };

        // Usage
        const list = new NumberList();
        list.add(1);
        list.add(2);
        list.add(3);
        list.add(4);
        list.add(5);

        const sum = list.sum();  // 15

        const evenList = list.filter(function(n) {
          return n % 2 === 0;
        });

        const evenSum = evenList.sum();  // 6 (2 + 4)

        [sum, evenSum, evenList.numbers.length];
      ''';

      final result = interpreter.eval(code);
      final results = (result as JSArray).toList();

      expect(results[0], equals(15.0)); // sum of all numbers
      expect(results[1], equals(6.0)); // sum of even numbers
      expect(results[2], equals(2.0)); // count of even numbers
    });

    test('Command Pattern for Undo/Redo', () {
      final code = '''
        // Simplified Command pattern
        function Calculator() {
          this.value = 0;
          this.history = [];
        }

        Calculator.prototype.add = function(value) {
          this.history.push({ type: 'add', value: value, previous: this.value });
          this.value += value;
          return this.value;
        };

        Calculator.prototype.multiply = function(value) {
          this.history.push({ type: 'multiply', value: value, previous: this.value });
          this.value *= value;
          return this.value;
        };

        Calculator.prototype.undo = function() {
          if (this.history.length > 0) {
            const lastCommand = this.history.pop();
            this.value = lastCommand.previous;
          }
          return this.value;
        };

        // Usage
        const calc = new Calculator();

        calc.add(5);        // 5
        calc.multiply(3);   // 15
        calc.add(10);       // 25

        calc.undo();  // Back to 15
        calc.undo();  // Back to 5

        [calc.value, calc.history.length];
      ''';

      final result = interpreter.eval(code);
      final results = (result as JSArray).toList();

      expect(
        results[0],
        equals(5.0),
      ); // final calculator value after undo operations
      expect(results[1], equals(1.0)); // remaining history length
    });

    test('Template Method Pattern', () {
      final code = '''
        // Simplified template method pattern
        function DataProcessor() {
          this.process = function(data) {
            this.validate(data);
            const processed = this.transform(data);
            return this.format(processed);
          };

          this.validate = function(data) {
            if (!data) {
              throw new Error('Data is required');
            }
          };
        }

        // Concrete implementations
        function NumberProcessor() {
          DataProcessor.call(this);

          this.transform = function(data) {
            if (typeof data === 'string') {
              return parseInt(data) || 0;
            }
            return data;
          };

          this.format = function(data) {
            return 'Number: ' + data;
          };
        }

        function StringProcessor() {
          DataProcessor.call(this);

          this.transform = function(data) {
            return data + '_transformed';
          };

          this.format = function(data) {
            return 'String: ' + data;
          };
        }

        // Usage
        const numProcessor = new NumberProcessor();
        const strProcessor = new StringProcessor();

        const numResult = numProcessor.process('42');
        const strResult = strProcessor.process('hello');

        [numResult, strResult];
      ''';

      final result = interpreter.eval(code);
      final results = (result as JSArray).toList();

      expect(results[0], equals('Number: 42'));
      expect(results[1], equals('String: hello_transformed'));
    });

    test('Composite Pattern for Tree Structures', () {
      final code = '''
        // Component
        function FileSystemComponent(name) {
          this.name = name;
        }

        FileSystemComponent.prototype.getSize = function() {
          throw new Error('getSize() must be implemented');
        };

        FileSystemComponent.prototype.display = function(indent) {
          throw new Error('display() must be implemented');
        };

        // Leaf - File
        function File(name, size) {
          FileSystemComponent.call(this, name);
          this.size = size;
        }

        File.prototype = Object.create(FileSystemComponent.prototype);
        File.prototype.constructor = File;

        File.prototype.getSize = function() {
          return this.size;
        };

        File.prototype.display = function(indent) {
          return indent + 'File: ' + this.name + ' (' + this.size + ' bytes)';
        };

        // Composite - Directory
        function Directory(name) {
          FileSystemComponent.call(this, name);
          this.children = [];
        }

        Directory.prototype = Object.create(FileSystemComponent.prototype);
        Directory.prototype.constructor = Directory;

        Directory.prototype.add = function(component) {
          this.children.push(component);
        };

        Directory.prototype.getSize = function() {
          let total = 0;
          for (let i = 0; i < this.children.length; i++) {
            total += this.children[i].getSize();
          }
          return total;
        };

        Directory.prototype.display = function(indent) {
          let result = indent + 'Directory: ' + this.name + '/\\n';
          for (let i = 0; i < this.children.length; i++) {
            result += this.children[i].display(indent + '  ') + '\\n';
          }
          return result;
        };

        // Usage
        const root = new Directory('root');
        const documents = new Directory('documents');
        const pictures = new Directory('pictures');

        root.add(documents);
        root.add(pictures);

        documents.add(new File('resume.txt', 1024));
        documents.add(new File('letter.doc', 2048));

        pictures.add(new File('vacation.jpg', 5120));
        pictures.add(new File('family.png', 3072));

        const totalSize = root.getSize();
        const hasChildren = root.children.length > 0;

        [totalSize, hasChildren, documents.children.length, pictures.children.length];
      ''';

      final result = interpreter.eval(code);
      final results = (result as JSArray).toList();

      expect(results[0], equals(11264.0)); // total size
      expect(results[1], equals(true)); // root has children
      expect(results[2], equals(2.0)); // documents has 2 children
      expect(results[3], equals(2.0)); // pictures has 2 children
    });
  });
}
