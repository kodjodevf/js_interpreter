/// Complete tests for ES2024 features (ECMAScript 2024)
/// Without simplification, in accordance with the full specification
library;

import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });

  group('ES2024 Object.groupBy() Tests', () {
    test('should group array elements by property', () {
      final code = '''
        const items = [
          { type: 'fruit', name: 'apple' },
          { type: 'vegetable', name: 'carrot' },
          { type: 'fruit', name: 'banana' },
          { type: 'vegetable', name: 'broccoli' }
        ];
        const grouped = Object.groupBy(items, item => item.type);
        const result = {
          fruitCount: grouped.fruit.length,
          vegCount: grouped.vegetable.length,
          firstFruit: grouped.fruit[0].name,
          firstVeg: grouped.vegetable[0].name
        };
        result;
      ''';

      final result = interpreter.eval(code);
      final map = (result as JSObject).toMap();
      expect(map['fruitCount'], equals(2));
      expect(map['vegCount'], equals(2));
      expect(map['firstFruit'], equals('apple'));
      expect(map['firstVeg'], equals('carrot'));
    });

    test('should group by numeric keys', () {
      final code = '''
        const numbers = [1, 2, 3, 4, 5, 6];
        const grouped = Object.groupBy(numbers, n => n % 2 === 0 ? 'even' : 'odd');
        const result = {
          evenCount: grouped.even.length,
          oddCount: grouped.odd.length
        };
        result;
      ''';

      final result = interpreter.eval(code);
      final map = (result as JSObject).toMap();
      expect(map['evenCount'], equals(3));
      expect(map['oddCount'], equals(3));
    });

    test('should handle empty arrays', () {
      final code = '''
        const grouped = Object.groupBy([], x => x);
        Object.keys(grouped).length;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(0));
    });

    test('should convert keys to strings', () {
      final code = '''
        const items = [1, 2, 3];
        const grouped = Object.groupBy(items, x => x > 1);
        const result = {
          hasTrue: grouped.hasOwnProperty('true'),
          hasFalse: grouped.hasOwnProperty('false')
        };
        result;
      ''';

      final result = interpreter.eval(code);
      final map = (result as JSObject).toMap();
      expect(map['hasTrue'], isTrue);
      expect(map['hasFalse'], isTrue);
    });

    test('should handle null group keys', () {
      final code = '''
        const items = [1, 2, 3];
        const grouped = Object.groupBy(items, x => x === 2 ? null : 'other');
        const result = {
          hasNull: grouped.hasOwnProperty('null'),
          nullCount: grouped['null'] ? grouped['null'].length : 0,
          otherCount: grouped.other.length
        };
        result;
      ''';

      final result = interpreter.eval(code);
      final map = (result as JSObject).toMap();
      expect(map['hasNull'], isTrue);
      expect(map['nullCount'], equals(1));
      expect(map['otherCount'], equals(2));
    });

    test('should work with complex grouping logic', () {
      final code = '''
        const items = [
          { score: 95 },
          { score: 75 },
          { score: 85 },
          { score: 65 },
          { score: 55 }
        ];
        const grouped = Object.groupBy(items, item => {
          if (item.score >= 90) return 'A';
          if (item.score >= 80) return 'B';
          if (item.score >= 70) return 'C';
          return 'F';
        });
        const result = {
          aCount: grouped.A ? grouped.A.length : 0,
          bCount: grouped.B ? grouped.B.length : 0,
          cCount: grouped.C ? grouped.C.length : 0,
          fCount: grouped.F ? grouped.F.length : 0
        };
        result;
      ''';

      final result = interpreter.eval(code);
      final map = (result as JSObject).toMap();
      expect(map['aCount'], equals(1));
      expect(map['bCount'], equals(1));
      expect(map['cCount'], equals(1));
      expect(map['fCount'], equals(2));
    });

    test('should throw error if callback is not a function', () {
      final code = '''
        try {
          Object.groupBy([1, 2, 3], 'not a function');
          false;
        } catch (e) {
          true;
        }
      ''';

      final result = interpreter.eval(code);
      expect(result.toBoolean(), isTrue);
    });
  });

  group('ES2024 Map.groupBy() Tests', () {
    test('should group array elements into a Map', () {
      final code = '''
        const items = [
          { type: 'fruit', name: 'apple' },
          { type: 'vegetable', name: 'carrot' },
          { type: 'fruit', name: 'banana' }
        ];
        const grouped = Map.groupBy(items, item => item.type);
        const result = {
          hasFruit: grouped.has('fruit'),
          hasVeg: grouped.has('vegetable'),
          fruitCount: grouped.get('fruit').length
        };
        result;
      ''';

      final result = interpreter.eval(code);
      final map = (result as JSObject).toMap();
      expect(map['hasFruit'], isTrue);
      expect(map['hasVeg'], isTrue);
      expect(map['fruitCount'], equals(2));
    });

    test('should allow non-string keys in Map', () {
      final code = '''
        const items = [1, 2, 3, 4, 5];
        const grouped = Map.groupBy(items, x => x % 2);
        const result = {
          has0: grouped.has(0),
          has1: grouped.has(1),
          evenCount: grouped.get(0).length,
          oddCount: grouped.get(1).length
        };
        result;
      ''';

      final result = interpreter.eval(code);
      final map = (result as JSObject).toMap();
      expect(map['has0'], isTrue);
      expect(map['has1'], isTrue);
      expect(map['evenCount'], equals(2));
      expect(map['oddCount'], equals(3));
    });

    test('should handle object keys in Map', () {
      final code = '''
        const key1 = { id: 1 };
        const key2 = { id: 2 };
        const items = ['a', 'b', 'c'];
        let counter = 0;
        const grouped = Map.groupBy(items, x => {
          counter++;
          return counter <= 2 ? key1 : key2;
        });
        const result = {
          mapSize: grouped.size,
          hasKey1: grouped.has(key1),
          hasKey2: grouped.has(key2)
        };
        result;
      ''';

      final result = interpreter.eval(code);
      final map = (result as JSObject).toMap();
      expect(map['mapSize'], equals(2));
      expect(map['hasKey1'], isTrue);
      expect(map['hasKey2'], isTrue);
    });

    test('should handle empty arrays', () {
      final code = '''
        const grouped = Map.groupBy([], x => x);
        grouped.size;
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(0));
    });

    test('should work with complex objects as keys', () {
      final code = '''
        const items = [1, 2, 3, 4, 5, 6];
        const grouped = Map.groupBy(items, x => ({ range: Math.floor(x / 3) }));
        grouped.size;
      ''';

      final result = interpreter.eval(code);
      // Each object is unique, so we expect multiple keys
      expect(result.toNumber(), greaterThan(0));
    });
  });

  group('ES2024 Promise.withResolvers() Tests', () {
    test('should return an object with promise, resolve, and reject', () {
      final code = '''
        const { promise, resolve, reject } = Promise.withResolvers();
        const result = {
          hasPromise: promise !== undefined,
          hasResolve: resolve !== undefined,
          hasReject: reject !== undefined,
          hasResolveFunc: typeof resolve === 'function',
          hasRejectFunc: typeof reject === 'function'
        };
        result;
      ''';

      final result = interpreter.eval(code);
      final map = (result as JSObject).toMap();
      expect(map['hasPromise'], isTrue);
      expect(map['hasResolve'], isTrue);
      expect(map['hasReject'], isTrue);
      expect(map['hasResolveFunc'], isTrue);
      expect(map['hasRejectFunc'], isTrue);
    });

    test('should allow external promise resolution', () async {
      final code = '''
        const { promise, resolve, reject } = Promise.withResolvers();
        let result = 'pending';
        promise.then(value => { result = value; });
        resolve('resolved');
        result;
      ''';

      final result = await interpreter.evalAsync(code);
      // The result should be 'resolved' after async resolution
      expect(result.toString(), equals('resolved'));
    });

    test('should allow external promise rejection', () async {
      final code = '''
        const { promise, resolve, reject } = Promise.withResolvers();
        let result = 'pending';
        promise['catch'](error => { result = error; });
        reject('error occurred');
        result;
      ''';

      final result = await interpreter.evalAsync(code);
      // The result should be 'error occurred' after async rejection
      expect(result.toString(), equals('error occurred'));
    });

    test('should create independent promise resolvers', () {
      final code = '''
        const { promise: p1, resolve: r1 } = Promise.withResolvers();
        const { promise: p2, resolve: r2 } = Promise.withResolvers();
        const result = {
          different: p1 !== p2,
          independentResolve: r1 !== r2
        };
        result;
      ''';

      final result = interpreter.eval(code);
      final map = (result as JSObject).toMap();
      expect(map['different'], isTrue);
      expect(map['independentResolve'], isTrue);
    });

    test('should work in practical async scenario', () async {
      final code = '''
        function createTimeoutPromise(ms) {
          const { promise, resolve } = Promise.withResolvers();
          setTimeout(() => resolve('done'), ms);
          return promise;
        }
        const p = createTimeoutPromise(10);
        await p;
      ''';

      final result = await interpreter.evalAsync(code);
      expect(result.toString(), equals('done'));
    });

    test('should work with Promise.race', () async {
      final code = '''
        const { promise: p1, resolve: r1 } = Promise.withResolvers();
        const { promise: p2, resolve: r2 } = Promise.withResolvers();
        const race = Promise.race([p1, p2]);
        r1('first');
        await race;
      ''';

      final result = await interpreter.evalAsync(code);
      expect(result.toString(), equals('first'));
    });
  });

  group('ES2024 RegExp unicodeSets flag (v) Tests', () {
    test('should recognize v flag in RegExp', () {
      final code = '''
        const re = /test/v;
        const result = {
          hasUnicodeSets: re.unicodeSets,
          flags: re.flags
        };
        result;
      ''';

      final result = interpreter.eval(code);
      final map = (result as JSObject).toMap();
      expect(map['hasUnicodeSets'], isTrue);
      expect(map['flags'], contains('v'));
    });

    test('should work with RegExp constructor', () {
      final code = '''
        const re = new RegExp('test', 'v');
        re.unicodeSets;
      ''';

      final result = interpreter.eval(code);
      expect(result.toBoolean(), isTrue);
    });

    test('should work alongside other flags', () {
      final code = '''
        const re = /test/giv;
        const result = {
          global: re.global,
          ignoreCase: re.ignoreCase,
          unicodeSets: re.unicodeSets,
          flags: re.flags
        };
        result;
      ''';

      final result = interpreter.eval(code);
      final map = (result as JSObject).toMap();
      expect(map['global'], isTrue);
      expect(map['ignoreCase'], isTrue);
      expect(map['unicodeSets'], isTrue);
      expect(map['flags'], contains('v'));
    });

    test('should be mutually exclusive with u flag', () {
      final code = '''
        const re1 = /test/u;
        const re2 = /test/v;
        const result = {
          re1Unicode: re1.unicode,
          re1UnicodeSets: re1.unicodeSets,
          re2Unicode: re2.unicode,
          re2UnicodeSets: re2.unicodeSets
        };
        result;
      ''';

      final result = interpreter.eval(code);
      final map = (result as JSObject).toMap();
      expect(map['re1Unicode'], isTrue);
      expect(map['re1UnicodeSets'], isFalse);
      expect(map['re2Unicode'], isFalse);
      expect(map['re2UnicodeSets'], isTrue);
    });

    test('should match patterns correctly with v flag', () {
      final code = '''
        const re = /test/v;
        const result = {
          matchesTest: re.test('test'),
          matchesOther: re.test('other')
        };
        result;
      ''';

      final result = interpreter.eval(code);
      final map = (result as JSObject).toMap();
      expect(map['matchesTest'], isTrue);
      expect(map['matchesOther'], isFalse);
    });

    test('should work with String methods', () {
      final code = '''
        const re = /world/v;
        const str = 'hello world';
        const result = {
          matches: str.match(re) !== null,
          replaced: str.replace(re, 'everyone')
        };
        result;
      ''';

      final result = interpreter.eval(code);
      final map = (result as JSObject).toMap();
      expect(map['matches'], isTrue);
      expect(map['replaced'], equals('hello everyone'));
    });
  });

  group('ES2024 Combined Features Tests', () {
    test('should combine Object.groupBy with Map operations', () {
      final code = '''
        const items = [
          { category: 'A', value: 10 },
          { category: 'B', value: 20 },
          { category: 'A', value: 15 },
          { category: 'B', value: 25 }
        ];
        const grouped = Object.groupBy(items, item => item.category);
        const result = {
          categoriesCount: Object.keys(grouped).length,
          aTotal: grouped.A.reduce((sum, item) => sum + item.value, 0),
          bTotal: grouped.B.reduce((sum, item) => sum + item.value, 0)
        };
        result;
      ''';

      final result = interpreter.eval(code);
      final map = (result as JSObject).toMap();
      expect(map['categoriesCount'], equals(2));
      expect(map['aTotal'], equals(25));
      expect(map['bTotal'], equals(45));
    });

    test('should use Map.groupBy with Promise.withResolvers', () {
      final code = '''
        const items = [1, 2, 3, 4, 5];
        const grouped = Map.groupBy(items, x => x % 2);
        const { promise, resolve } = Promise.withResolvers();
        const result = {
          mapSize: grouped.size,
          hasPromise: promise !== undefined
        };
        result;
      ''';

      final result = interpreter.eval(code);
      final map = (result as JSObject).toMap();
      expect(map['mapSize'], equals(2));
      expect(map['hasPromise'], isTrue);
    });

    test('should use RegExp v flag with grouping', () {
      final code = '''
        const items = ['test1', 'test2', 'other1', 'test3'];
        const re = /test/v;
        const grouped = Object.groupBy(items, item => re.test(item) ? 'matches' : 'others');
        const result = {
          matchCount: grouped.matches.length,
          otherCount: grouped.others.length
        };
        result;
      ''';

      final result = interpreter.eval(code);
      final map = (result as JSObject).toMap();
      expect(map['matchCount'], equals(3));
      expect(map['otherCount'], equals(1));
    });

    test('should demonstrate real-world grouping scenario', () {
      final code = '''
        const transactions = [
          { date: '2024-01', amount: 100, type: 'debit' },
          { date: '2024-01', amount: 50, type: 'credit' },
          { date: '2024-02', amount: 200, type: 'debit' },
          { date: '2024-02', amount: 75, type: 'credit' },
          { date: '2024-03', amount: 150, type: 'debit' }
        ];
        const byMonth = Object.groupBy(transactions, tx => tx.date);
        const result = {
          monthsCount: Object.keys(byMonth).length,
          jan: byMonth['2024-01'].length,
          feb: byMonth['2024-02'].length,
          mar: byMonth['2024-03'].length
        };
        result;
      ''';

      final result = interpreter.eval(code);
      final map = (result as JSObject).toMap();
      expect(map['monthsCount'], equals(3));
      expect(map['jan'], equals(2));
      expect(map['feb'], equals(2));
      expect(map['mar'], equals(1));
    });

    test('should verify all ES2024 features are available', () {
      final code = '''
        const result = {
          hasObjectGroupBy: typeof Object.groupBy === 'function',
          hasMapGroupBy: typeof Map.groupBy === 'function',
          hasPromiseWithResolvers: typeof Promise.withResolvers === 'function',
          canCreateRegExpV: /test/v.unicodeSets === true
        };
        result;
      ''';

      final result = interpreter.eval(code);
      final map = (result as JSObject).toMap();
      expect(map['hasObjectGroupBy'], isTrue);
      expect(map['hasMapGroupBy'], isTrue);
      expect(map['hasPromiseWithResolvers'], isTrue);
      expect(map['canCreateRegExpV'], isTrue);
    });
  });
}
