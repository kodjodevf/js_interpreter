import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });

  group('Interoperability and Compatibility Tests', () {
    test('JSON Serialization and Parsing', () {
      final code = '''
        // Complex object to serialize
        const user = {
          id: 123,
          name: 'John Doe',
          email: 'john@example.com',
          profile: {
            age: 30,
            hobbies: ['reading', 'coding', 'gaming'],
            address: {
              street: '123 Main St',
              city: 'Anytown',
              country: 'USA'
            }
          },
          active: true,
          scores: [85, 92, 78, 96]
        };

        // Serialize to JSON
        const jsonString = JSON.stringify(user);

        // Parse back from JSON
        const parsedUser = JSON.parse(jsonString);

        // Verify data integrity
        const results = [
          parsedUser.id,                    // 123
          parsedUser.name,                  // 'John Doe'
          parsedUser.profile.age,           // 30
          parsedUser.profile.hobbies.length, // 3
          parsedUser.profile.address.city,   // 'Anytown'
          parsedUser.active,                // true
          parsedUser.scores[0],             // 85
          parsedUser.scores.length          // 4
        ];

        results;
      ''';

      final result = interpreter.eval(code);
      final results = (result as JSArray).toList();

      expect(results[0], equals(123.0));
      expect(results[1], equals('John Doe'));
      expect(results[2], equals(30.0));
      expect(results[3], equals(3.0));
      expect(results[4], equals('Anytown'));
      expect(results[5], equals(true));
      expect(results[6], equals(85.0));
      expect(results[7], equals(4.0));
    });

    test('Custom JSON Replacer and Reviver', () {
      final code = '''
        // Simple object with basic types
        const data = {
          name: 'Test Object',
          age: 25,
          active: true,
          tags: ['javascript', 'test']
        };

        // Simple replacer
        function simpleReplacer(key, value) {
          if (key === 'age') {
            return value * 2; // Double the age
          }
          return value;
        }

        // Simple reviver
        function simpleReviver(key, value) {
          if (key === 'age') {
            return value / 2; // Restore original age
          }
          return value;
        }

        // Serialize and parse
        const serialized = JSON.stringify(data, simpleReplacer);
        const deserialized = JSON.parse(serialized, simpleReviver);

        const results = [
          deserialized.name,           // 'Test Object'
          deserialized.age,            // 25 (original value)
          deserialized.active,         // true
          deserialized.tags.length     // 2
        ];

        results;
      ''';

      final result = interpreter.eval(code);
      final results = (result as JSArray).toList();

      expect(results[0], equals('Test Object'));
      expect(results[1], equals(25.0)); // original age
      expect(results[2], equals(true)); // active status
      expect(results[3], equals(2.0)); // tags array length
    });

    test('Cross-Object Communication and Events', () {
      final code = '''
        // Simple event system
        const EventBus = {
          events: {},

          on: function(event, callback) {
            if (!this.events[event]) {
              this.events[event] = [];
            }
            this.events[event].push(callback);
          },

          emit: function(event, data) {
            if (!this.events[event]) return;
            this.events[event].forEach(function(callback) {
              callback(data);
            });
          }
        };

        // Simple services
        function UserService() {
          this.users = [];
        }

        UserService.prototype.createUser = function(name, email) {
          const user = {
            id: Date.now(),
            name: name,
            email: email
          };
          this.users.push(user);
          EventBus.emit('user_created', user);
          return user;
        };

        function NotificationService() {
          this.notifications = [];
          this.receivedEvents = [];
        }

        NotificationService.prototype.init = function() {
          EventBus.on('user_created', this.handleUserCreated.bind(this));
        };

        NotificationService.prototype.handleUserCreated = function(user) {
          this.receivedEvents.push('user_created');
          const notification = {
            message: 'Welcome ' + user.name + '!'
          };
          this.notifications.push(notification);
        };

        // Initialize and test
        const userService = new UserService();
        const notificationService = new NotificationService();
        notificationService.init();

        const newUser = userService.createUser('Alice', 'alice@example.com');

        const results = [
          userService.users.length,              // 1
          notificationService.notifications.length, // 1
          notificationService.receivedEvents.length, // 1
          newUser.name,                          // 'Alice'
          notificationService.notifications[0].message // 'Welcome Alice!'
        ];

        results;
      ''';

      final result = interpreter.eval(code);
      final results = (result as JSArray).toList();

      expect(results[0], equals(1.0)); // users count
      expect(results[1], equals(1.0)); // notifications count
      expect(results[2], equals(1.0)); // events received
      expect(results[3], equals('Alice')); // user name
      expect(results[4], equals('Welcome Alice!')); // notification message
    });

    test('Module-like Code Organization', () {
      final code = '''
        // Module pattern for code organization
        const MathUtils = (function() {
          // Private variables
          let calculationCount = 0;

          // Private functions
          function validateNumber(n) {
            if (typeof n !== 'number' || isNaN(n)) {
              throw new Error('Invalid number: ' + n);
            }
          }

          // Public API
          return {
            add: function(a, b) {
              validateNumber(a);
              validateNumber(b);
              calculationCount++;
              return a + b;
            },

            multiply: function(a, b) {
              validateNumber(a);
              validateNumber(b);
              calculationCount++;
              return a * b;
            },

            getCalculationCount: function() {
              return calculationCount;
            },

            reset: function() {
              calculationCount = 0;
            }
          };
        })();

        // Another module
        const StringUtils = (function() {
          let operationCount = 0;

          function validateString(s) {
            if (typeof s !== 'string') {
              throw new Error('Invalid string: ' + s);
            }
          }

          return {
            capitalize: function(str) {
              validateString(str);
              operationCount++;
              return str.charAt(0).toUpperCase() + str.slice(1).toLowerCase();
            },

            reverse: function(str) {
              validateString(str);
              operationCount++;
              return str.split('').reverse().join('');
            },

            getOperationCount: function() {
              return operationCount;
            }
          };
        })();

        // Usage
        const sum = MathUtils.add(5, 3);           // 8
        const product = MathUtils.multiply(4, 2);  // 8
        const calcCount = MathUtils.getCalculationCount(); // 2

        const capitalized = StringUtils.capitalize('hello'); // 'Hello'
        const reversed = StringUtils.reverse('world');       // 'dlrow'
        const opCount = StringUtils.getOperationCount();     // 2

        [sum, product, calcCount, capitalized, reversed, opCount];
      ''';

      final result = interpreter.eval(code);
      final results = (result as JSArray).toList();

      expect(results[0], equals(8.0)); // sum
      expect(results[1], equals(8.0)); // product
      expect(results[2], equals(2.0)); // calculation count
      expect(results[3], equals('Hello')); // capitalized
      expect(results[4], equals('dlrow')); // reversed
      expect(results[5], equals(2.0)); // operation count
    });

    test('Browser-like Environment Simulation', () {
      final code = '''
        // Simulate browser environment
        const window = {
          location: {
            href: 'https://example.com/page',
            hostname: 'example.com',
            pathname: '/page',
            search: '?param=value',
            hash: '#section'
          },

          navigator: {
            userAgent: 'Mozilla/5.0 (compatible; JS Interpreter)',
            language: 'en-US',
            platform: 'JSInterpreter'
          },

          document: {
            title: 'Test Page',
            body: {
              innerHTML: '<h1>Hello World</h1>',
              style: {
                backgroundColor: 'white'
              }
            },

            getElementById: function(id) {
              // Mock implementation
              return {
                id: id,
                innerHTML: 'Mock element',
                style: { display: 'block' }
              };
            },

            querySelector: function(selector) {
              return {
                tagName: 'DIV',
                className: selector.replace('.', ''),
                textContent: 'Selected element'
              };
            }
          },

          console: {
            log: function() {
              // Mock console.log
              this.logs = this.logs || [];
              this.logs.push(Array.prototype.join.call(arguments, ' '));
            },

            logs: []
          },

          setTimeout: function(callback, delay) {
            // Mock setTimeout - execute immediately for testing
            callback();
            return 'timeout_id_' + Math.random();
          },

          localStorage: {
            data: {},

            setItem: function(key, value) {
              this.data[key] = value;
            },

            getItem: function(key) {
              return this.data[key] || null;
            },

            removeItem: function(key) {
              delete this.data[key];
            },

            clear: function() {
              this.data = {};
            }
          }
        };

        // Test browser-like functionality
        const currentURL = window.location.href;
        const userAgent = window.navigator.userAgent;
        const pageTitle = window.document.title;

        // Use localStorage
        window.localStorage.setItem('test', 'value');
        const storedValue = window.localStorage.getItem('test');

        // Use console
        window.console.log('Hello', 'World');
        const logCount = window.console.logs.length;

        // Use DOM methods
        const element = window.document.getElementById('test');
        const selected = window.document.querySelector('.test-class');

        const results = [
          currentURL,
          userAgent,
          pageTitle,
          storedValue,
          logCount,
          element.id,
          selected.className
        ];

        results;
      ''';

      final result = interpreter.eval(code);
      final results = (result as JSArray).toList();

      expect(results[0], equals('https://example.com/page')); // URL
      expect(
        results[1],
        equals('Mozilla/5.0 (compatible; JS Interpreter)'),
      ); // user agent
      expect(results[2], equals('Test Page')); // page title
      expect(results[3], equals('value')); // stored value
      expect(results[4], equals(1.0)); // log count
      expect(results[5], equals('test')); // element id
      expect(results[6], equals('test-class')); // selected class
    });
  });
}
