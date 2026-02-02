import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

/// Tests complets pour Array.prototype.includes() - ECMAScript 2016 (ES7)
///
/// Array.prototype.includes(searchElement, fromIndex?)
/// Returns true if element is found, false otherwise
/// Utilise la comparaison SameValueZero (strictEquals)
void main() {
  group('Array.prototype.includes() - ES2016', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('Basic usage', () {
      test('should find element in array', () {
        const code = '''
          const arr = [1, 2, 3, 4, 5];
          arr.includes(3);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should return false if element not found', () {
        const code = '''
          const arr = [1, 2, 3, 4, 5];
          arr.includes(9);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isFalse);
      });

      test('should return false for empty array', () {
        const code = '''
          const arr = [];
          arr.includes(1);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isFalse);
      });

      test('should find string in array', () {
        const code = '''
          const arr = ["apple", "banana", "cherry"];
          arr.includes("banana");
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should find boolean in array', () {
        const code = '''
          const arr = [true, false, true];
          arr.includes(false);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });
    });

    group('With fromIndex parameter', () {
      test('should search from positive fromIndex', () {
        const code = '''
          const arr = [1, 2, 3, 4, 5, 3];
          arr.includes(3, 3);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should not find element before fromIndex', () {
        const code = '''
          const arr = [1, 2, 3, 4, 5];
          arr.includes(3, 3);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isFalse);
      });

      test('should handle fromIndex at 0', () {
        const code = '''
          const arr = [1, 2, 3];
          arr.includes(1, 0);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should handle fromIndex at array end', () {
        const code = '''
          const arr = [1, 2, 3];
          arr.includes(3, 2);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should return false if fromIndex >= length', () {
        const code = '''
          const arr = [1, 2, 3];
          arr.includes(1, 10);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isFalse);
      });
    });

    group('Negative fromIndex', () {
      test('should search from negative index (from end)', () {
        const code = '''
          const arr = [1, 2, 3, 4, 5];
          arr.includes(3, -3);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should not find element before negative index', () {
        const code = '''
          const arr = [1, 2, 3, 4, 5];
          arr.includes(2, -2);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isFalse);
      });

      test('should handle large negative index', () {
        const code = '''
          const arr = [1, 2, 3];
          arr.includes(1, -100);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should search from start when negative index is too large', () {
        const code = '''
          const arr = [1, 2, 3, 4, 5];
          arr.includes(1, -10);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });
    });

    group('Special values (SameValueZero comparison)', () {
      test('should find NaN in array', () {
        const code = '''
          const arr = [1, NaN, 3];
          arr.includes(NaN);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should find undefined in array', () {
        const code = '''
          const arr = [1, undefined, 3];
          arr.includes(undefined);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should find null in array', () {
        const code = '''
          const arr = [1, null, 3];
          arr.includes(null);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should distinguish between null and undefined', () {
        const code = '''
          const arr = [1, null, 3];
          arr.includes(undefined);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isFalse);
      });

      test('should find 0 in array', () {
        const code = '''
          const arr = [1, 0, 3];
          arr.includes(0);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should treat +0 and -0 as equal', () {
        const code = '''
          const arr = [1, +0, 3];
          arr.includes(-0);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });
    });

    group('Type strictness', () {
      test('should not find string "1" when looking for number 1', () {
        const code = '''
          const arr = [1, 2, 3];
          arr.includes("1");
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isFalse);
      });

      test('should not find number 1 when looking for string "1"', () {
        const code = '''
          const arr = ["1", "2", "3"];
          arr.includes(1);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isFalse);
      });

      test('should not find boolean true when looking for 1', () {
        const code = '''
          const arr = [1, 2, 3];
          arr.includes(true);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isFalse);
      });

      test('should distinguish between different string values', () {
        const code = '''
          const arr = ["hello", "world"];
          arr.includes("Hello");
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isFalse);
      });
    });

    group('Object comparison (by reference)', () {
      test('should find object by reference', () {
        const code = '''
          const obj = {a: 1};
          const arr = [obj, {b: 2}];
          arr.includes(obj);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test(
        'should not find object with same content but different reference',
        () {
          const code = '''
          const arr = [{a: 1}, {b: 2}];
          arr.includes({a: 1});
        ''';
          final result = interpreter.eval(code);
          expect(result.toBoolean(), isFalse);
        },
      );

      test('should find array by reference', () {
        const code = '''
          const innerArr = [1, 2];
          const arr = [innerArr, [3, 4]];
          arr.includes(innerArr);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test(
        'should not find array with same content but different reference',
        () {
          const code = '''
          const arr = [[1, 2], [3, 4]];
          arr.includes([1, 2]);
        ''';
          final result = interpreter.eval(code);
          expect(result.toBoolean(), isFalse);
        },
      );
    });

    group('Edge cases', () {
      test('should handle single element array', () {
        const code = '''
          const arr = [42];
          arr.includes(42);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should handle sparse arrays', () {
        const code = '''
          const arr = [1, undefined, 3]; // array with explicit undefined
          arr.includes(undefined);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should handle array with many duplicate values', () {
        const code = '''
          const arr = [1, 1, 1, 1, 1];
          arr.includes(1);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should handle array with mixed types', () {
        const code = '''
          const arr = [1, "2", true, null, undefined, {a: 1}];
          arr.includes(true);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should return false when searching in empty array', () {
        const code = '''
          const arr = [];
          arr.includes(undefined);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isFalse);
      });
    });

    group('Return value verification', () {
      test('should return true (not truthy value)', () {
        const code = '''
          const arr = [1, 2, 3];
          const result = arr.includes(2);
          result === true;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should return false (not falsy value)', () {
        const code = '''
          const arr = [1, 2, 3];
          const result = arr.includes(9);
          result === false;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should be usable in if statement', () {
        const code = '''
          const arr = [1, 2, 3];
          let found = false;
          if (arr.includes(2)) {
            found = true;
          }
          found;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should be usable in ternary operator', () {
        const code = '''
          const arr = [1, 2, 3];
          const message = arr.includes(2) ? "found" : "not found";
          message;
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('found'));
      });
    });

    group('Real-world scenarios', () {
      test('should check if user has permission', () {
        const code = '''
          const permissions = ["read", "write", "execute"];
          const hasWritePermission = permissions.includes("write");
          const hasDeletePermission = permissions.includes("delete");
          hasWritePermission && !hasDeletePermission;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should validate allowed values', () {
        const code = '''
          const allowedColors = ["red", "green", "blue"];
          const userColor = "green";
          allowedColors.includes(userColor);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should check for duplicate before adding', () {
        const code = '''
          const tags = ["javascript", "programming"];
          const newTag = "javascript";
          let added = false;
          
          if (!tags.includes(newTag)) {
            tags.push(newTag);
            added = true;
          }
          
          added;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isFalse);
      });

      test('should filter items based on exclusion list', () {
        const code = '''
          const items = ["apple", "banana", "cherry", "date"];
          const excluded = ["banana", "date"];
          const filtered = [];
          
          for (let i = 0; i < items.length; i++) {
            if (!excluded.includes(items[i])) {
              filtered.push(items[i]);
            }
          }
          
          filtered.length;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(2));
      });

      test('should check multiple conditions', () {
        const code = '''
          const fruits = ["apple", "banana", "cherry"];
          const vegetables = ["carrot", "potato"];
          const item = "banana";
          
          const isFruit = fruits.includes(item);
          const isVegetable = vegetables.includes(item);
          
          isFruit && !isVegetable;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });
    });

    group('Comparison with indexOf', () {
      test('includes() finds NaN but indexOf() does not', () {
        const code = '''
          const arr = [1, NaN, 3];
          const includesResult = arr.includes(NaN);
          const indexOfResult = arr.indexOf(NaN);
          includesResult && indexOfResult === -1;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('both should find regular values', () {
        const code = '''
          const arr = [1, 2, 3];
          const includesResult = arr.includes(2);
          const indexOfResult = arr.indexOf(2);
          includesResult && indexOfResult === 1;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('includes() returns boolean, indexOf() returns number', () {
        const code = '''
          const arr = [1, 2, 3];
          const includesResult = arr.includes(2);
          const indexOfResult = arr.indexOf(2);
          typeof includesResult === "boolean" && typeof indexOfResult === "number";
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });
    });

    group('Performance and iteration', () {
      test('should work with large arrays', () {
        const code = '''
          const arr = [];
          for (let i = 0; i < 1000; i++) {
            arr.push(i);
          }
          arr.includes(500);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should stop searching when found', () {
        const code = '''
          const arr = [1, 2, 3, 4, 5];
          const result = arr.includes(2);
          result;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should search until end if not found', () {
        const code = '''
          const arr = [1, 2, 3, 4, 5];
          const result = arr.includes(9);
          result;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isFalse);
      });
    });

    group('Method chaining', () {
      test('should work in filter callback', () {
        const code = '''
          const allowed = ["apple", "banana"];
          const items = ["apple", "cherry", "banana", "date"];
          const filtered = items.filter(item => allowed.includes(item));
          filtered.length;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(2));
      });

      test('should work with map', () {
        const code = '''
          const blacklist = ["bad1", "bad2"];
          const items = ["good1", "bad1", "good2"];
          const results = items.map(item => !blacklist.includes(item));
          results[0] && !results[1] && results[2];
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should work with some', () {
        const code = '''
          const targets = ["apple", "banana"];
          const items = ["cherry", "date", "apple"];
          items.some(item => targets.includes(item));
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should work with every', () {
        const code = '''
          const allowed = ["a", "b", "c"];
          const items = ["a", "b"];
          items.every(item => allowed.includes(item));
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });
    });
  });
}
