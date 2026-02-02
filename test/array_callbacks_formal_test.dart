import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Array Callback Methods Tests', () {
    test('Array.prototype.forEach basic functionality', () {
      final result = JSEvaluator.evaluateString('''
        var sum = 0;
        var arr = [1, 2, 3, 4];
        arr.forEach(function(item) {
          sum += item;
        });
        sum;
      ''');

      expect(result, isA<JSNumber>());
      expect((result as JSNumber).value, equals(10));
    });

    test('Array.prototype.map with transformation', () {
      final result = JSEvaluator.evaluateString('''
        var arr = [1, 2, 3];
        arr.map(function(x) {
          return x * 2;
        });
      ''');

      expect(result, isA<JSArray>());
      expect(result.toString(), equals('2,4,6'));
    });

    test('Array.prototype.filter with condition', () {
      final result = JSEvaluator.evaluateString('''
        var arr = [1, 2, 3, 4, 5];
        arr.filter(function(x) {
          return x > 2;
        });
      ''');

      expect(result, isA<JSArray>());
      expect(result.toString(), equals('3,4,5'));
    });

    test('Array.prototype.find returns first match', () {
      final result = JSEvaluator.evaluateString('''
        var arr = [1, 2, 3, 4, 5];
        arr.find(function(x) {
          return x > 3;
        });
      ''');

      expect(result, isA<JSNumber>());
      expect((result as JSNumber).value, equals(4));
    });

    test('Array.prototype.find returns undefined when not found', () {
      final result = JSEvaluator.evaluateString('''
        var arr = [1, 2, 3];
        arr.find(function(x) {
          return x > 10;
        });
      ''');

      expect(result, isA<JSUndefined>());
    });

    test('Array.prototype.reduce with initial value', () {
      final result = JSEvaluator.evaluateString('''
        var arr = [1, 2, 3, 4];
        arr.reduce(function(acc, x) {
          return acc + x;
        }, 0);
      ''');

      expect(result, isA<JSNumber>());
      expect((result as JSNumber).value, equals(10));
    });

    test('Array.prototype.reduce without initial value', () {
      final result = JSEvaluator.evaluateString('''
        var arr = [1, 2, 3, 4];
        arr.reduce(function(acc, x) {
          return acc * x;
        });
      ''');

      expect(result, isA<JSNumber>());
      expect((result as JSNumber).value, equals(24));
    });

    test('Array callbacks with arrow functions', () {
      final result = JSEvaluator.evaluateString('''
        var arr = [1, 2, 3];
        arr.map(x => x * 3);
      ''');

      expect(result, isA<JSArray>());
      expect(result.toString(), equals('3,6,9'));
    });

    test('Array callbacks with index parameter', () {
      final result = JSEvaluator.evaluateString('''
        var arr = [10, 20, 30];
        arr.map(function(item, index) {
          return item + index;
        });
      ''');

      expect(result, isA<JSArray>());
      expect(result.toString(), equals('10,21,32'));
    });

    test('Array callbacks with this binding', () {
      final result = JSEvaluator.evaluateString('''
        var arr = [1, 2, 3];
        var multiplier = { factor: 5 };
        arr.map(function(x) {
          return x * this.factor;
        }, multiplier);
      ''');

      expect(result, isA<JSArray>());
      expect(result.toString(), equals('5,10,15'));
    });

    test('Array.prototype.forEach with index and array parameters', () {
      final result = JSEvaluator.evaluateString('''
        var results = [];
        var arr = ["a", "b"];
        arr.forEach(function(item, index, array) {
          results.push(item + index + array.length);
        });
        results;
      ''');

      expect(result, isA<JSArray>());
      expect(result.toString(), equals('a02,b12'));
    });

    test(
      'Array.prototype.reduce error on empty array without initial value',
      () {
        expect(() {
          JSEvaluator.evaluateString('''
          var arr = [];
          arr.reduce(function(acc, x) {
            return acc + x;
          });
        ''');
        }, throwsA(isA<JSError>()));
      },
    );
  });
}
