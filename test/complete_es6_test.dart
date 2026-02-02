import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });

  group('ES6 Variable Declaration Destructuring Tests', () {
    test('Array destructuring in const declarations', () {
      final code = '''
        const arr1 = [1, 2, 3, 4, 5];

        // Basic destructuring
        const [a, b, c] = arr1;

        // Skipping elements
        const [x, , z] = arr1;

        // Rest operator
        const [first, ...rest] = arr1;

        [a, b, c, x, z, first, rest.length];
      ''';

      final result = interpreter.eval(code);
      final resultList = (result as JSArray).toList();

      expect(resultList.length, equals(7));
      expect(resultList[0], equals(1.0)); // a
      expect(resultList[1], equals(2.0)); // b
      expect(resultList[2], equals(3.0)); // c
      expect(resultList[3], equals(1.0)); // x
      expect(resultList[4], equals(3.0)); // z
      expect(resultList[5], equals(1.0)); // first
      expect(resultList[6], equals(4.0)); // rest.length
    });

    test('Object destructuring in const declarations', () {
      final code = '''
        const person1 = {
          name: 'John',
          age: 30,
          city: 'New York',
          job: 'Developer'
        };

        // Basic destructuring
        const {name, age} = person1;

        // Renaming
        const {city: location, job: profession} = person1;

        // Default values
        const {salary = 50000, bonus = 0} = person1;

        [name, age, location, profession, salary, bonus];
      ''';

      final result = interpreter.eval(code);
      final resultList = (result as JSArray).toList();

      expect(resultList.length, equals(6));
      expect(resultList[0], equals('John')); // name
      expect(resultList[1], equals(30.0)); // age
      expect(resultList[2], equals('New York')); // location
      expect(resultList[3], equals('Developer')); // profession
      expect(resultList[4], equals(50000.0)); // salary (default)
      expect(resultList[5], equals(0.0)); // bonus (default)
    });

    test('Nested object destructuring', () {
      final code = '''
        const user1 = {
          id: 1,
          profile: {
            name: 'Alice',
            email: 'alice@example.com'
          },
          settings: {
            theme: 'dark',
            notifications: true
          }
        };

        // Nested destructuring
        const {
          profile: {name, email},
          settings: {theme}
        } = user1;

        // Rest operator
        const {id, ...rest} = user1;

        [name, email, theme, id, typeof rest === 'object'];
      ''';

      final result = interpreter.eval(code);
      final resultList = (result as JSArray).toList();

      expect(resultList.length, equals(5));
      expect(resultList[0], equals('Alice')); // name
      expect(resultList[1], equals('alice@example.com')); // email
      expect(resultList[2], equals('dark')); // theme
      expect(resultList[3], equals(1.0)); // id
      expect(resultList[4], equals(true)); // rest is object
    });

    test('Array destructuring in let declarations', () {
      final code = '''
        let arr2 = [10, 20, 30];

        // Basic destructuring with let
        let [a2, b2, c2] = arr2;

        // Modify variables
        a2 = a2 + 5;
        b2 = b2 * 2;

        [a2, b2, c2];
      ''';

      final result = interpreter.eval(code);
      final resultList = (result as JSArray).toList();

      expect(resultList.length, equals(3));
      expect(resultList[0], equals(15.0)); // a + 5
      expect(resultList[1], equals(40.0)); // b * 2
      expect(resultList[2], equals(30.0)); // c
    });
  });
}
