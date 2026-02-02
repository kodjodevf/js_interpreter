import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Array.sort avec compareFn Tests', () {
    test('Array.sort sans compareFn utilise le tri alphabétique', () {
      final result = JSEvaluator.evaluateString('''
        var arr = [3, 1, 10, 2];
        arr.sort();
      ''');

      expect(result, isA<JSArray>());
      final array = result as JSArray;
      expect(
        array.toString(),
        equals('1,10,2,3'),
      ); // Alphabetical sort (JS format)
    });

    test('Array.sort avec function expression pour tri numérique', () {
      final result = JSEvaluator.evaluateString('''
        var arr = [3, 1, 10, 2];
        arr.sort(function(a, b) {
          return a - b;
        });
      ''');

      expect(result, isA<JSArray>());
      final array = result as JSArray;
      expect(array.toString(), equals('1,2,3,10')); // Numeric sort (JS format)
    });

    test('Array.sort avec arrow function pour tri décroissant', () {
      final result = JSEvaluator.evaluateString('''
        var numbers = [5, 2, 8, 1, 9];
        numbers.sort((a, b) => b - a);
      ''');

      expect(result, isA<JSArray>());
      final array = result as JSArray;
      expect(
        array.toString(),
        equals('9,8,5,2,1'),
      ); // Descending sort (JS format)
    });

    test('Array.sort avec fonction de comparaison personnalisée', () {
      final result = JSEvaluator.evaluateString('''
        var words = ["banana", "apple", "cherry", "date"];
        words.sort(function(a, b) {
          return a.length - b.length;
        });
      ''');

      expect(result, isA<JSArray>());
      final array = result as JSArray;
      expect(
        array.toString(),
        equals('date,apple,banana,cherry'),
      ); // Tri par longueur (JS format)
    });

    test('Array.sort avec logique de tri complexe', () {
      final result = JSEvaluator.evaluateString('''
        var items = [3, 1, 4, 1, 5, 2, 6];
        items.sort(function(a, b) {
          // Pairs en premier, puis impairs
          var aEven = a % 2 === 0;
          var bEven = b % 2 === 0;
          if (aEven && !bEven) return -1;
          if (!aEven && bEven) return 1;
          return a - b;
        });
      ''');

      expect(result, isA<JSArray>());
      final array = result as JSArray;
      expect(
        array.toString(),
        equals('2,4,6,1,1,3,5'),
      ); // Pairs puis impairs (JS format)
    });

    test('Array.sort avec compareFn non-fonction utilise tri par défaut', () {
      final result = JSEvaluator.evaluateString('''
        var arr = [3, 1, 10, 2];
        arr.sort("not a function");
      ''');

      expect(result, isA<JSArray>());
      final array = result as JSArray;
      expect(
        array.toString(),
        equals('1,10,2,3'),
      ); // Default alphabetical sort (JS format)
    });
  });
}
