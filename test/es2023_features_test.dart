import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });

  group('ES2023: Array.prototype.findLast()', () {
    test('should find last element matching predicate', () {
      const code = '''
        const arr = [1, 2, 3, 4, 5, 4, 3, 2, 1];
        arr.findLast(x => x > 3);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(4));
    });

    test('should return undefined if no element matches', () {
      const code = '''
        const arr = [1, 2, 3];
        arr.findLast(x => x > 10);
      ''';
      final result = interpreter.eval(code);
      expect(result.isUndefined, isTrue);
    });

    test('should iterate from end to start', () {
      const code = '''
        const arr = [1, 2, 3, 4, 5];
        const indices = [];
        arr.findLast((x, i) => {
          indices.push(i);
          return x === 2;
        });
        JSON.stringify(indices);
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('[4,3,2,1]'));
    });

    test('should pass element, index, and array to callback', () {
      const code = '''
        const arr = [10, 20, 30];
        let lastElement, lastIndex, sameArray;
        arr.findLast((el, idx, ar) => {
          lastElement = el;
          lastIndex = idx;
          sameArray = ar === arr;
          return el === 20;
        });
        JSON.stringify({el: lastElement, idx: lastIndex, same: sameArray});
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('{"el":20,"idx":1,"same":true}'));
    });

    test('should work with thisArg', () {
      const code = '''
        const context = {threshold: 3};
        const arr = [1, 2, 3, 4, 5];
        arr.findLast(function(x) {
          return x > this.threshold;
        }, context);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(5));
    });

    test('should find last even number', () {
      const code = '''
        const arr = [1, 3, 5, 8, 10, 7, 9];
        arr.findLast(x => x % 2 === 0);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(10));
    });

    test('should work with objects', () {
      const code = '''
        const users = [
          {id: 1, name: 'Alice', active: true},
          {id: 2, name: 'Bob', active: false},
          {id: 3, name: 'Charlie', active: true}
        ];
        const lastActive = users.findLast(u => u.active);
        lastActive.name;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('Charlie'));
    });
  });

  group('ES2023: Array.prototype.findLastIndex()', () {
    test('should find last index matching predicate', () {
      const code = '''
        const arr = [1, 2, 3, 4, 5, 4, 3, 2, 1];
        arr.findLastIndex(x => x > 3);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(5));
    });

    test('should return -1 if no element matches', () {
      const code = '''
        const arr = [1, 2, 3];
        arr.findLastIndex(x => x > 10);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(-1));
    });

    test('should iterate from end to start', () {
      const code = '''
        const arr = [1, 2, 3, 4, 5];
        const indices = [];
        arr.findLastIndex((x, i) => {
          indices.push(i);
          return x === 2;
        });
        JSON.stringify(indices);
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('[4,3,2,1]'));
    });

    test('should find last index of even number', () {
      const code = '''
        const arr = [1, 3, 5, 8, 10, 7, 9];
        arr.findLastIndex(x => x % 2 === 0);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(4));
    });

    test('should work with thisArg', () {
      const code = '''
        const context = {max: 3};
        const arr = [1, 2, 3, 4, 5, 2];
        arr.findLastIndex(function(x) {
          return x <= this.max;
        }, context);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(5));
    });

    test('should find last occurrence in duplicates', () {
      const code = '''
        const arr = ['a', 'b', 'c', 'b', 'a'];
        arr.findLastIndex(x => x === 'b');
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(3));
    });
  });

  group('ES2023: Array.prototype.toReversed()', () {
    test('should return reversed copy without mutating original', () {
      const code = '''
        const original = [1, 2, 3, 4, 5];
        const reversed = original.toReversed();
        JSON.stringify({original, reversed});
      ''';
      final result = interpreter.eval(code);
      expect(
        result.toString(),
        equals('{"original":[1,2,3,4,5],"reversed":[5,4,3,2,1]}'),
      );
    });

    test('should work with empty array', () {
      const code = '''
        const arr = [];
        const reversed = arr.toReversed();
        reversed.length;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(0));
    });

    test('should work with single element', () {
      const code = '''
        const arr = [42];
        JSON.stringify(arr.toReversed());
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('[42]'));
    });

    test('should work with strings', () {
      const code = '''
        const arr = ['a', 'b', 'c', 'd'];
        JSON.stringify(arr.toReversed());
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('["d","c","b","a"]'));
    });

    test('should work with mixed types', () {
      const code = '''
        const arr = [1, 'two', true, null, undefined];
        const reversed = arr.toReversed();
        reversed.length;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(5));
    });

    test('should be chainable', () {
      const code = '''
        const arr = [1, 2, 3];
        JSON.stringify(arr.toReversed().toReversed());
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('[1,2,3]'));
    });
  });

  group('ES2023: Array.prototype.toSorted()', () {
    test('should return sorted copy without mutating original', () {
      const code = '''
        const original = [3, 1, 4, 1, 5, 9, 2, 6];
        const sorted = original.toSorted();
        JSON.stringify({original, sorted});
      ''';
      final result = interpreter.eval(code);
      expect(
        result.toString(),
        equals('{"original":[3,1,4,1,5,9,2,6],"sorted":[1,1,2,3,4,5,6,9]}'),
      );
    });

    test('should use default alphabetic sort', () {
      const code = '''
        const arr = ['banana', 'apple', 'cherry', 'date'];
        JSON.stringify(arr.toSorted());
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('["apple","banana","cherry","date"]'));
    });

    test('should work with custom compare function', () {
      const code = '''
        const arr = [10, 5, 40, 25, 1000, 1];
        JSON.stringify(arr.toSorted((a, b) => a - b));
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('[1,5,10,25,40,1000]'));
    });

    test('should sort in descending order with compare function', () {
      const code = '''
        const arr = [3, 1, 4, 1, 5];
        JSON.stringify(arr.toSorted((a, b) => b - a));
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('[5,4,3,1,1]'));
    });

    test('should work with empty array', () {
      const code = '''
        const arr = [];
        JSON.stringify(arr.toSorted());
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('[]'));
    });

    test('should sort objects by property', () {
      const code = '''
        const users = [
          {name: 'Charlie', age: 30},
          {name: 'Alice', age: 25},
          {name: 'Bob', age: 35}
        ];
        const sorted = users.toSorted((a, b) => a.age - b.age);
        JSON.stringify(sorted.map(u => u.name));
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('["Alice","Charlie","Bob"]'));
    });

    test('should handle numbers correctly with compare function', () {
      const code = '''
        const arr = [10, 2, 30, 4];
        JSON.stringify(arr.toSorted((a, b) => a - b));
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('[2,4,10,30]'));
    });
  });

  group('ES2023: Array.prototype.toSpliced()', () {
    test('should return spliced copy without mutating original', () {
      const code = '''
        const original = [1, 2, 3, 4, 5];
        const spliced = original.toSpliced(2, 2);
        JSON.stringify({original, spliced});
      ''';
      final result = interpreter.eval(code);
      expect(
        result.toString(),
        equals('{"original":[1,2,3,4,5],"spliced":[1,2,5]}'),
      );
    });

    test('should insert elements without deleting', () {
      const code = '''
        const arr = [1, 2, 5];
        JSON.stringify(arr.toSpliced(2, 0, 3, 4));
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('[1,2,3,4,5]'));
    });

    test('should delete and insert elements', () {
      const code = '''
        const arr = [1, 2, 3, 4, 5];
        JSON.stringify(arr.toSpliced(1, 3, 'a', 'b'));
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('[1,"a","b",5]'));
    });

    test('should work with negative start index', () {
      const code = '''
        const arr = [1, 2, 3, 4, 5];
        JSON.stringify(arr.toSpliced(-2, 1, 99));
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('[1,2,3,99,5]'));
    });

    test('should delete from start to end with no items', () {
      const code = '''
        const arr = [1, 2, 3, 4, 5];
        JSON.stringify(arr.toSpliced(2));
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('[1,2]'));
    });

    test('should work with empty array', () {
      const code = '''
        const arr = [];
        JSON.stringify(arr.toSpliced(0, 0, 1, 2, 3));
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('[1,2,3]'));
    });

    test('should handle start beyond array length', () {
      const code = '''
        const arr = [1, 2, 3];
        JSON.stringify(arr.toSpliced(10, 0, 4));
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('[1,2,3,4]'));
    });

    test('should replace single element', () {
      const code = '''
        const arr = ['a', 'b', 'c'];
        JSON.stringify(arr.toSpliced(1, 1, 'X'));
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('["a","X","c"]'));
    });
  });

  group('ES2023: Array.prototype.with()', () {
    test('should return copy with element replaced', () {
      const code = '''
        const original = [1, 2, 3, 4, 5];
        const modified = original.with(2, 99);
        JSON.stringify({original, modified});
      ''';
      final result = interpreter.eval(code);
      expect(
        result.toString(),
        equals('{"original":[1,2,3,4,5],"modified":[1,2,99,4,5]}'),
      );
    });

    test('should work with negative index', () {
      const code = '''
        const arr = [1, 2, 3, 4, 5];
        JSON.stringify(arr.with(-1, 99));
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('[1,2,3,4,99]'));
    });

    test('should work with negative index from middle', () {
      const code = '''
        const arr = [1, 2, 3, 4, 5];
        JSON.stringify(arr.with(-3, 99));
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('[1,2,99,4,5]'));
    });

    test('should replace at index 0', () {
      const code = '''
        const arr = ['a', 'b', 'c'];
        JSON.stringify(arr.with(0, 'X'));
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('["X","b","c"]'));
    });

    test('should replace at last index', () {
      const code = '''
        const arr = [10, 20, 30];
        JSON.stringify(arr.with(2, 999));
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('[10,20,999]'));
    });

    test('should throw RangeError for out of bounds positive index', () {
      const code = '''
        const arr = [1, 2, 3];
        try {
          arr.with(10, 99);
          'no error';
        } catch (e) {
          e.name;
        }
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('RangeError'));
    });

    test('should throw RangeError for out of bounds negative index', () {
      const code = '''
        const arr = [1, 2, 3];
        try {
          arr.with(-10, 99);
          'no error';
        } catch (e) {
          e.name;
        }
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('RangeError'));
    });

    test('should work with undefined as value', () {
      const code = '''
        const arr = [1, 2, 3];
        const modified = arr.with(1, undefined);
        modified[1] === undefined;
      ''';
      final result = interpreter.eval(code);
      expect(result.toBoolean(), isTrue);
    });

    test('should be chainable', () {
      const code = '''
        const arr = [1, 2, 3, 4, 5];
        JSON.stringify(arr.with(0, 10).with(4, 50));
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('[10,2,3,4,50]'));
    });
  });

  group('ES2023: Hashbang Grammar', () {
    test('should skip hashbang at start of file', () {
      const code = '''#!/usr/bin/env node
const x = 42;
x;
''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(42));
    });

    test('should skip hashbang with path', () {
      const code = '''#!/usr/local/bin/node
const message = 'Hello, World!';
message;
''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('Hello, World!'));
    });

    test('should skip hashbang with arguments', () {
      const code = '''#!/usr/bin/env node --harmony
const arr = [1, 2, 3];
arr.length;
''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(3));
    });

    test('should work with empty program after hashbang', () {
      const code = '''#!/usr/bin/env node
''';
      final result = interpreter.eval(code);
      expect(result.isUndefined, isTrue);
    });

    test('should work with complex program after hashbang', () {
      const code = '''#!/usr/bin/env node
function factorial(n) {
  if (n <= 1) return 1;
  return n * factorial(n - 1);
}
factorial(5);
''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(120));
    });

    test('should not treat # in middle of file as hashbang', () {
      const code = '''
const x = 10;
// This is not a hashbang: #!/usr/bin/env node
const y = 20;
x + y;
''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(30));
    });
  });

  group('ES2023: Combined Features', () {
    test('should combine findLast with toSorted', () {
      const code = '''
        const arr = [5, 2, 8, 1, 9, 3];
        const sorted = arr.toSorted((a, b) => a - b);
        sorted.findLast(x => x < 7);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(5));
    });

    test('should combine toReversed with findLastIndex', () {
      const code = '''
        const arr = [1, 2, 3, 4, 5];
        const reversed = arr.toReversed();
        reversed.findLastIndex(x => x > 2);
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(2));
    });

    test('should chain multiple non-mutating methods', () {
      const code = '''
        const arr = [3, 1, 4, 1, 5, 9, 2, 6];
        const result = arr
          .toSorted((a, b) => a - b)
          .toReversed()
          .toSpliced(0, 2)
          .with(0, 99);
        JSON.stringify(result);
      ''';
      final result = interpreter.eval(code);
      // arr sorted: [1, 1, 2, 3, 4, 5, 6, 9]
      // reversed: [9, 6, 5, 4, 3, 2, 1, 1]
      // toSpliced(0, 2): removes first 2 → [5, 4, 3, 2, 1, 1]
      // with(0, 99): [99, 4, 3, 2, 1, 1]
      expect(result.toString(), equals('[99,4,3,2,1,1]'));
    });

    test('should verify original arrays remain unchanged', () {
      const code = '''
        const original = [3, 1, 4];
        const a = original.toReversed();
        const b = original.toSorted();
        const c = original.toSpliced(1, 1);
        const d = original.with(0, 99);
        
        // Verify original unchanged
        JSON.stringify({
          original,
          allUnchanged: JSON.stringify(original) === '[3,1,4]'
        });
      ''';
      final result = interpreter.eval(code);
      expect(
        result.toString(),
        equals('{"original":[3,1,4],"allUnchanged":true}'),
      );
    });

    test('should use ES2023 methods in practical scenario', () {
      const code = '''
        const transactions = [
          {id: 1, amount: 100, date: '2023-01-01'},
          {id: 2, amount: 200, date: '2023-01-02'},
          {id: 3, amount: 150, date: '2023-01-03'},
          {id: 4, amount: 300, date: '2023-01-04'},
          {id: 5, amount: 250, date: '2023-01-05'}
        ];
        
        // Find last transaction over 200
        const lastLarge = transactions.findLast(t => t.amount > 200);
        
        // Get sorted by amount (non-mutating)
        const sortedByAmount = transactions.toSorted((a, b) => a.amount - b.amount);
        
        // Replace middle transaction
        const modified = sortedByAmount.with(2, {id: 99, amount: 999, date: '2023-99-99'});
        
        JSON.stringify({
          lastLargeId: lastLarge.id,
          firstInSorted: sortedByAmount[0].amount,
          modifiedMiddle: modified[2].amount
        });
      ''';
      final result = interpreter.eval(code);
      expect(
        result.toString(),
        equals('{"lastLargeId":5,"firstInSorted":100,"modifiedMiddle":999}'),
      );
    });
  });
}
