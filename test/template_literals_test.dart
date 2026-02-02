import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Template Literals Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('Basic Template Literals', () {
      test('should handle simple template without interpolation', () {
        final result = interpreter.eval('`Hello World`');
        expect(result.toString(), equals('Hello World'));
      });

      test('should handle empty template', () {
        final result = interpreter.eval('``');
        expect(result.toString(), equals(''));
      });

      test('should handle template with newlines', () {
        final result = interpreter.eval('`Line 1\nLine 2\nLine 3`');
        expect(result.toString(), contains('\n'));
        expect(result.toString(), equals('Line 1\nLine 2\nLine 3'));
      });

      test('should handle template with special characters', () {
        final result = interpreter.eval(r'`Tab:\t Quote:" Backslash:\\ Done`');
        expect(result.toString(), contains('\t'));
        expect(result.toString(), contains('\\'));
      });

      test('should handle escaped backticks', () {
        final result = interpreter.eval(r'`Escaped backtick: \``');
        expect(result.toString(), equals('Escaped backtick: `'));
      });
    });

    group('Template Literals with Interpolation', () {
      test('should interpolate simple variables', () {
        interpreter.eval('var name = "Alice";');
        final result = interpreter.eval(r'`Hello ${name}!`');
        expect(result.toString(), equals('Hello Alice!'));
      });

      test('should interpolate arithmetic expressions', () {
        interpreter.eval('var x = 10; var y = 5;');
        final result = interpreter.eval(r'`Sum: ${x + y}`');
        expect(result.toString(), equals('Sum: 15'));
      });

      test('should handle multiple interpolations', () {
        interpreter.eval('var first = "John"; var last = "Doe";');
        final result = interpreter.eval(r'`Hello ${first} ${last}!`');
        expect(result.toString(), equals('Hello John Doe!'));
      });

      test('should interpolate complex expressions with parentheses', () {
        interpreter.eval('var x = 10; var y = 5;');
        final result = interpreter.eval(r'`Result: ${(x + y) * 2}`');
        expect(result.toString(), equals('Result: 30'));
      });

      test('should interpolate boolean expressions', () {
        interpreter.eval('var age = 25;');
        final result = interpreter.eval(r'`Adult: ${age >= 18}`');
        expect(result.toString(), equals('Adult: true'));
      });

      test('should interpolate comparison expressions', () {
        interpreter.eval('var x = 10; var y = 5;');
        final result = interpreter.eval(r'`Greater: ${x > y}`');
        expect(result.toString(), equals('Greater: true'));
      });
    });

    group('Template Literals with Objects and Functions', () {
      test('should interpolate object properties', () {
        interpreter.eval('var user = {name: "Bob", age: 30};');
        final result = interpreter.eval(r'`User: ${user.name}`');
        expect(result.toString(), equals('User: Bob'));
      });

      test('should interpolate multiple object properties', () {
        interpreter.eval('var user = {name: "Bob", age: 30};');
        final result = interpreter.eval(r'`${user.name} (${user.age})`');
        expect(result.toString(), equals('Bob (30)'));
      });

      test('should interpolate function calls', () {
        interpreter.eval('function greet(n) { return "Hi " + n; }');
        interpreter.eval('var name = "Alice";');
        final result = interpreter.eval(r'`Message: ${greet(name)}`');
        expect(result.toString(), equals('Message: Hi Alice'));
      });
    });

    group('Template Literals Edge Cases', () {
      test('should handle null interpolation', () {
        interpreter.eval('var nullVar = null;');
        final result = interpreter.eval(r'`Value: ${nullVar}`');
        expect(result.toString(), equals('Value: null'));
      });

      test('should handle undefined interpolation', () {
        interpreter.eval('var undefinedVar;');
        final result = interpreter.eval(r'`Value: ${undefinedVar}`');
        expect(result.toString(), equals('Value: undefined'));
      });

      test('should handle template assignment to variable', () {
        interpreter.eval('var message = `Hello Template Literals!`;');
        final result = interpreter.eval('message');
        expect(result.toString(), equals('Hello Template Literals!'));
      });

      test('should handle template concatenation', () {
        final result = interpreter.eval('`Hello` + " " + `World`');
        expect(result.toString(), equals('Hello World'));
      });

      test('should handle escaped dollar signs', () {
        interpreter.eval('var x = 10;');
        final result = interpreter.eval(r'`Price: \$${x}`');
        expect(result.toString(), equals('Price: \$10'));
      });

      test('should handle templates with newlines and interpolation', () {
        interpreter.eval('var name = "Alice";');
        final result = interpreter.eval(r'`Hello ${name}!\nWelcome!`');
        expect(result.toString(), equals('Hello Alice!\nWelcome!'));
      });
    });

    group('Template Literals Integration', () {
      test('should work with complex nested expressions', () {
        interpreter.eval('''
          var user = {
            name: "Alice",
            scores: [85, 92, 78],
            getAverage: function() {
              var sum = 0;
              for (var i = 0; i < this.scores.length; i++) {
                sum += this.scores[i];
              }
              return sum / this.scores.length;
            }
          };
        ''');

        final result = interpreter.eval(
          r'`${user.name}: ${user.getAverage()}`',
        );
        expect(result.toString(), equals('Alice: 85'));
      });

      test('should maintain type coercion in interpolation', () {
        interpreter.eval('var num = 42; var bool = true; var arr = [1,2,3];');
        final result = interpreter.eval(r'`${num} ${bool} ${arr}`');
        expect(
          result.toString(),
          equals('42 true 1,2,3'),
        ); // JavaScript converts arrays to comma-separated strings
      });
    });
  });
}
