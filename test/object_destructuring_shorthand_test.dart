import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });

  group('Object Destructuring Shorthand Detection', () {
    test('should handle shorthand property in arrow function parameter', () {
      const code = '''
        const obj = {x: 10, y: 20};
        const fn = ({x, y}) => x + y;
        fn(obj);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(30));
    });

    test('should handle mixed shorthand and regular properties', () {
      const code = '''
        const obj = {a: 1, b: 2, c: 3};
        const fn = ({a, b: renamed, c}) => a + renamed + c;
        fn(obj);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(6));
    });

    test('should handle shorthand with default values', () {
      const code = '''
        const obj = {x: 5};
        const fn = ({x = 0, y = 10}) => x + y;
        fn(obj);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(15));
    });

    test('should handle shorthand in variable destructuring', () {
      const code = '''
        const obj = {name: 'Alice', age: 30};
        const {name, age} = obj;
        name + ' is ' + age;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('Alice is 30'));
    });

    test('should handle nested shorthand', () {
      const code = '''
        const obj = {outer: {inner: 42}};
        const {outer: {inner}} = obj;
        inner;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(42));
    });

    test('should handle shorthand in Object.entries with arrow functions', () {
      const code = '''
        const obj = {a: 1, b: 2, c: 3};
        const result = Object.fromEntries(
          Object.entries(obj).map(([k, v]) => [k, v * 2])
        );
        JSON.stringify(result);
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('{"a":2,"b":4,"c":6}'));
    });

    test('should handle complex shorthand patterns', () {
      const code = '''
        const users = [
          {id: 1, name: 'Alice', email: 'alice@example.com'},
          {id: 2, name: 'Bob', email: 'bob@example.com'}
        ];
        
        const formatUser = ({id, name, email}) => 
          `User #\${id}: \${name} (\${email})`;
        
        users.map(formatUser).join(', ');
      ''';
      final result = interpreter.eval(code);
      expect(
        result.toString(),
        equals(
          'User #1: Alice (alice@example.com), User #2: Bob (bob@example.com)',
        ),
      );
    });

    test('should handle shorthand with rest properties', () {
      const code = '''
        const obj = {a: 1, b: 2, c: 3, d: 4};
        const {a, b, ...rest} = obj;
        JSON.stringify({a, b, rest});
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('{"a":1,"b":2,"rest":{"c":3,"d":4}}'));
    });

    test('should handle shorthand in function parameters with defaults', () {
      const code = '''
        function greet({name = 'Guest', greeting = 'Hello'}) {
          return greeting + ', ' + name + '!';
        }
        
        greet({name: 'Alice'}) + ' | ' + greet({greeting: 'Hi'});
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('Hello, Alice! | Hi, Guest!'));
    });

    test('should handle shorthand with computed property names', () {
      const code = '''
        const key = 'value';
        const obj = {[key]: 42, other: 10};
        const {other} = obj;
        other;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(10));
    });

    test('should handle multiple levels of nested shorthand', () {
      const code = '''
        const data = {
          user: {
            profile: {
              name: 'Alice',
              age: 30
            }
          }
        };
        
        const {user: {profile: {name, age}}} = data;
        name + ' is ' + age + ' years old';
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('Alice is 30 years old'));
    });

    test('should handle shorthand in array of objects', () {
      const code = '''
        const items = [
          {x: 1, y: 2},
          {x: 3, y: 4},
          {x: 5, y: 6}
        ];
        
        const sum = items.reduce((acc, {x, y}) => acc + x + y, 0);
        sum;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(21)); // 1+2+3+4+5+6 = 21
    });
  });
}
