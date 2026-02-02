import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  test('Basic ES5 JavaScript Syntax Test', () {
    final code = """
      // ===== VARIABLES =====
      var varVariable = 'var';
      var number = 42;
      var boolean = true;
      var nullValue = null;
      var array = [1, 2, 3];

      // ===== OPERATORS =====
      var sum = 10 + 5;
      var equal = (10 == '10');
      var strictEqual = (10 === '10');
      var greaterThan = (10 > 5);
      var andResult = (true && false);
      var orResult = (true || false);

      // ===== CONTROL STRUCTURES =====
      var ifResult;
      if (number > 40) {
        ifResult = 'greater';
      } else {
        ifResult = 'smaller';
      }

      // For loop
      var forSum = 0;
      for (var i = 0; i < 5; i++) {
        forSum += i;
      }

      // ===== FONCTIONS =====
      function declaredFunction(param1, param2) {
        return param1 + param2;
      }

      // ===== OBJETS =====
      var person = {
        name: 'John',
        age: 30,
        greet: function() {
          return 'Hello, my name is ' + this.name;
        }
      };

      // ===== ARRAYS =====
      var fruits = ['apple', 'banana', 'orange'];
      var firstFruit = fruits[0];
      fruits.push('mango');

      // ===== RESULTS =====
      [
        varVariable, number, boolean, nullValue, array[0],
        sum, equal, strictEqual, greaterThan, andResult, orResult,
        ifResult, forSum,
        declaredFunction(5, 3),
        person.name, person.greet(),
        firstFruit, fruits.length
      ];
    """;

    final result = JSInterpreter().eval(code);
    final resultList = (result as JSArray).toList();

    // Verification of results
    expect(resultList.length, equals(18));

    // Variables
    expect(resultList[0], equals('var'));
    expect(resultList[1], equals(42.0));
    expect(resultList[2], equals(true));
    expect(resultList[3], isNull);
    expect(resultList[4], equals(1.0));

    // Operators
    expect(resultList[5], equals(15.0)); // sum
    expect(resultList[6], equals(true)); // equal
    expect(resultList[7], equals(false)); // strictEqual
    expect(resultList[8], equals(true)); // greaterThan
    expect(resultList[9], equals(false)); // andResult
    expect(resultList[10], equals(true)); // orResult

    // Control structures
    expect(resultList[11], equals('greater')); // ifResult
    expect(resultList[12], equals(10.0)); // forSum

    // Fonctions
    expect(resultList[13], equals(8.0)); // declaredFunction(5, 3)

    // Objets
    expect(resultList[14], equals('John')); // person.name
    expect(resultList[15], equals('Hello, my name is John')); // person.greet()

    // Arrays
    expect(resultList[16], equals('apple')); // firstFruit
    expect(resultList[17], equals(4.0)); // fruits.length after push

    print('✅ Basic ES5 JavaScript syntax test passed!');
    print('Total test values: ${resultList.length}');
  });
}
