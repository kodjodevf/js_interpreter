import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('flatMap() comprehensive tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('should work with numbers', () {
      const code = '''
        const arr = [1, 2, 3];
        const result = arr.flatMap(x => [x, x * 2]);
        JSON.stringify(result);
      ''';
      final result = interpreter.eval(code);
      print('Numbers test: ${result.toString()}');
      expect(result.toString(), equals('[1,2,2,4,3,6]'));
    });

    test('should work with strings', () {
      const code = '''
        const words = ['hello', 'world'];
        const result = words.flatMap(word => word.split(''));
        JSON.stringify(result);
      ''';
      final result = interpreter.eval(code);
      print('Strings test: ${result.toString()}');
      expect(
        result.toString(),
        equals('["h","e","l","l","o","w","o","r","l","d"]'),
      );
    });

    test('should handle filtering', () {
      const code = '''
        const numbers = [1, 2, 3, 4, 5, 6];
        const evens = numbers.flatMap(n => n % 2 === 0 ? [n] : []);
        JSON.stringify(evens);
      ''';
      final result = interpreter.eval(code);
      print('Filtering test: ${result.toString()}');
      expect(result.toString(), equals('[2,4,6]'));
    });

    test('should flatten only one level', () {
      const code = '''
        const arr = [1, 2, 3];
        const nested = arr.flatMap(x => [[x]]);
        JSON.stringify(nested);
      ''';
      final result = interpreter.eval(code);
      print('One level test: ${result.toString()}');
      expect(result.toString(), equals('[[1],[2],[3]]'));
    });

    test('should work with index parameter', () {
      const code = '''
        const arr = ['a', 'b', 'c'];
        const result = arr.flatMap((item, idx) => [item, idx]);
        JSON.stringify(result);
      ''';
      final result = interpreter.eval(code);
      print('Index parameter test: ${result.toString()}');
      expect(result.toString(), equals('["a",0,"b",1,"c",2]'));
    });

    test('should handle non-array return values', () {
      const code = '''
        const arr = [1, 2, 3];
        const result = arr.flatMap(x => x * 2);
        JSON.stringify(result);
      ''';
      final result = interpreter.eval(code);
      print('Non-array return test: ${result.toString()}');
      expect(result.toString(), equals('[2,4,6]'));
    });

    test('should handle empty arrays', () {
      const code = '''
        const arr = [];
        const result = arr.flatMap(x => [x, x * 2]);
        JSON.stringify(result);
      ''';
      final result = interpreter.eval(code);
      print('Empty array test: ${result.toString()}');
      expect(result.toString(), equals('[]'));
    });

    test('should work with complex transformations', () {
      const code = '''
        const data = [
          {name: 'Alice', scores: [85, 90]},
          {name: 'Bob', scores: [75, 80]}
        ];
        const allScores = data.flatMap(person => person.scores);
        JSON.stringify(allScores);
      ''';
      final result = interpreter.eval(code);
      print('Complex transformation test: ${result.toString()}');
      expect(result.toString(), equals('[85,90,75,80]'));
    });

    test('should duplicate and transform', () {
      const code = '''
        const arr = [1, 2, 3];
        const result = arr.flatMap(x => [x, x, x]);
        JSON.stringify(result);
      ''';
      final result = interpreter.eval(code);
      print('Duplicate test: ${result.toString()}');
      expect(result.toString(), equals('[1,1,1,2,2,2,3,3,3]'));
    });

    test('should work with mixed return types', () {
      const code = '''
        const arr = [1, 2, 3];
        const result = arr.flatMap(x => x === 2 ? [x, x + 10, x + 20] : [x]);
        JSON.stringify(result);
      ''';
      final result = interpreter.eval(code);
      print('Mixed return test: ${result.toString()}');
      expect(result.toString(), equals('[1,2,12,22,3]'));
    });

    test('comparison with map + flat', () {
      const code = '''
        const arr = [1, 2, 3];
        
        // Using flatMap
        const flatMapResult = arr.flatMap(x => [x, x * 2]);
        
        // Using map + flat
        const mapFlatResult = arr.map(x => [x, x * 2]).flat();
        
        JSON.stringify(flatMapResult) === JSON.stringify(mapFlatResult);
      ''';
      final result = interpreter.eval(code);
      print('Comparison test: ${result.toString()}');
      expect(result.toBoolean(), equals(true));
    });
  });
}
