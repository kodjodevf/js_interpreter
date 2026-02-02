import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('ES6 Destructuring - Variable Declarations', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('Object Destructuring', () {
      test('should destructure simple object properties', () {
        const code = '''
          const obj = {x: 10, y: 20};
          const {x, y} = obj;
          x + y;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(30));
      });

      test('should support property renaming', () {
        const code = '''
          const obj = {x: 10, y: 20};
          const {x: a, y: b} = obj;
          a + b;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(30));
      });

      test('should support default values', () {
        const code = '''
          const {a = 5, b = 10} = {a: 3};
          a + b;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(13));
      });

      test('should support rest properties', () {
        const code = '''
          const {x, ...rest} = {x: 1, y: 2, z: 3};
          rest.y + rest.z;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(5));
      });

      test('should support nested object destructuring', () {
        const code = '''
          const data = {user: {name: 'Alice', age: 30}};
          const {user: {name, age}} = data;
          name + ' is ' + age;
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('Alice is 30'));
      });
    });

    group('Array Destructuring', () {
      test('should destructure array elements', () {
        const code = '''
          const arr = [1, 2, 3, 4, 5];
          const [a, b, c] = arr;
          a + b + c;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(6));
      });

      test('should support array holes', () {
        const code = '''
          const arr = [1, 2, 3, 4, 5];
          const [a, , c] = arr;
          a + c;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(4));
      });

      test('should support rest elements', () {
        const code = '''
          const arr = [1, 2, 3, 4, 5];
          const [a, b, ...rest] = arr;
          rest[0] + rest[1] + rest[2];
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(12));
      });

      test('should support default values in arrays', () {
        const code = '''
          const [a = 1, b = 2, c = 3] = [10];
          a + b + c;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(15));
      });

      test('should support nested array destructuring', () {
        const code = '''
          const arr = [1, [2, 3], 4];
          const [a, [b, c], d] = arr;
          a + b + c + d;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(10));
      });
    });

    group('Mixed Destructuring', () {
      test('should support mixed object and array destructuring', () {
        const code = '''
          const data = {items: [1, 2, 3]};
          const {items: [first, second]} = data;
          first + second;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(3));
      });

      test('should support nested mixed destructuring', () {
        const code = '''
          const data = {users: [{name: 'Alice', age: 30}]};
          const {users: [{name, age}]} = data;
          name + ' is ' + age;
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('Alice is 30'));
      });
    });

    group('Different Variable Kinds', () {
      test('should work with let', () {
        const code = '''
          const obj = {x: 10, y: 20};
          let {x, y} = obj;
          x = x + 5;
          y = y + 10;
          x + y;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(45));
      });

      test('should work with var', () {
        const code = '''
          var {a, b} = {a: 1, b: 2};
          a + b;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(3));
      });
    });
  });

  group('ES6 Destructuring - Assignments', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('should support object destructuring assignment', () {
      const code = '''
        let x, y;
        ({x, y} = {x: 10, y: 20});
        x + y;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(30));
    });

    test('should support array destructuring assignment', () {
      const code = '''
        let a, b;
        [a, b] = [1, 2];
        a + b;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(3));
    });

    test('should support swapping variables', () {
      const code = '''
        let a = 1, b = 2;
        [a, b] = [b, a];
        a * 10 + b;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(21));
    });
  });

  group('ES6 Destructuring - For-of Loops', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('should support object destructuring in for-of', () {
      const code = '''
        const users = [
          {name: 'Alice', age: 30},
          {name: 'Bob', age: 25},
          {name: 'Charlie', age: 35}
        ];
        let sum = 0;
        for (const {age} of users) {
          sum += age;
        }
        sum;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(90));
    });

    test('should support array destructuring in for-of', () {
      const code = '''
        const pairs = [[1, 2], [3, 4], [5, 6]];
        let sum = 0;
        for (const [a, b] of pairs) {
          sum += a + b;
        }
        sum;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(21));
    });

    test('should support nested destructuring in for-of', () {
      const code = '''
        const data = [
          {point: {x: 1, y: 2}},
          {point: {x: 3, y: 4}}
        ];
        let sum = 0;
        for (const {point: {x, y}} of data) {
          sum += x + y;
        }
        sum;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(10));
    });
  });

  group('ES6 Destructuring - For-in Loops', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('should support destructuring in for-in', () {
      const code = '''
        const obj = {a: 1, b: 2, c: 3};
        let result = '';
        for (const key in obj) {
          result += key;
        }
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('abc'));
    });
  });
}
