/// Comprehensive test suite for ES2019 (ES10) features
///
/// ES2019 includes:
/// 1. Array.prototype.flat() and flatMap()
/// 2. Object.fromEntries()
/// 3. String.prototype.trimStart() and trimEnd()
/// 4. Optional catch binding
/// 5. Symbol.prototype.description
/// 6. Well-formed JSON.stringify()
/// 7. Function.prototype.toString() revision
library;

import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });

  group('ES2019 - Array.prototype.flat()', () {
    group('Basic flat() Behavior', () {
      test('should flatten array by default depth 1', () {
        const code = '''
          const arr = [1, 2, [3, 4]];
          const result = arr.flat();
          JSON.stringify(result);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('[1,2,3,4]'));
      });

      test('should flatten nested arrays with depth 1', () {
        const code = '''
          const arr = [1, [2, [3, [4]]]];
          const result = arr.flat(1);
          JSON.stringify(result);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('[1,2,[3,[4]]]'));
      });

      test('should flatten nested arrays with depth 2', () {
        const code = '''
          const arr = [1, [2, [3, [4]]]];
          const result = arr.flat(2);
          JSON.stringify(result);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('[1,2,3,[4]]'));
      });

      test('should flatten deeply nested arrays with Infinity', () {
        const code = '''
          const arr = [1, [2, [3, [4, [5]]]]];
          const result = arr.flat(Infinity);
          JSON.stringify(result);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('[1,2,3,4,5]'));
      });

      test('should handle empty slots in arrays', () {
        const code = '''
          const arr = [1, 2, , 4, 5];
          const result = arr.flat();
          JSON.stringify(result);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('[1,2,4,5]'));
      });

      test('should handle empty arrays', () {
        const code = '''
          const arr = [[], [[]], [[], [[]]]];
          const result = arr.flat(Infinity);
          JSON.stringify(result);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('[]'));
      });
    });

    group('flat() Edge Cases', () {
      test('should treat negative depth as 0', () {
        const code = '''
          const arr = [1, [2, 3]];
          const result = arr.flat(-1);
          JSON.stringify(result);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('[1,[2,3]]'));
      });

      test('should treat depth 0 as no flattening', () {
        const code = '''
          const arr = [1, [2, [3]]];
          const result = arr.flat(0);
          JSON.stringify(result);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('[1,[2,[3]]]'));
      });

      test('should not modify original array', () {
        const code = '''
          const arr = [1, [2, 3]];
          const result = arr.flat();
          const unchanged = JSON.stringify(arr);
          const flattened = JSON.stringify(result);
          unchanged + '|' + flattened;
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('[1,[2,3]]|[1,2,3]'));
      });
    });
  });

  group('ES2019 - Array.prototype.flatMap()', () {
    group('Basic flatMap() Behavior', () {
      test('should map and flatten by depth 1', () {
        const code = '''
          const arr = [1, 2, 3];
          const result = arr.flatMap(x => [x, x * 2]);
          JSON.stringify(result);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('[1,2,2,4,3,6]'));
      });

      test('should work with callback returning arrays', () {
        const code = '''
          const arr = ['hello', 'world'];
          const result = arr.flatMap(str => str.split(''));
          JSON.stringify(result);
        ''';
        final result = interpreter.eval(code);
        expect(
          result.toString(),
          equals('["h","e","l","l","o","w","o","r","l","d"]'),
        );
      });

      test('should filter and map simultaneously', () {
        const code = '''
          const arr = [1, 2, 3, 4, 5];
          const result = arr.flatMap(x => x % 2 === 0 ? [x] : []);
          JSON.stringify(result);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('[2,4]'));
      });

      test('should flatten only one level deep', () {
        const code = '''
          const arr = [1, 2, 3];
          const result = arr.flatMap(x => [[x * 2]]);
          JSON.stringify(result);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('[[2],[4],[6]]'));
      });

      test('should pass index and array to callback', () {
        const code = '''
          const arr = ['a', 'b', 'c'];
          const result = arr.flatMap((item, index, array) => [item + index]);
          JSON.stringify(result);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('["a0","b1","c2"]'));
      });
    });

    group('flatMap() Edge Cases', () {
      test('should handle empty arrays', () {
        const code = '''
          const arr = [];
          const result = arr.flatMap(x => [x, x * 2]);
          JSON.stringify(result);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('[]'));
      });

      test('should work with non-array return values', () {
        const code = '''
          const arr = [1, 2, 3];
          const result = arr.flatMap(x => x);
          JSON.stringify(result);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('[1,2,3]'));
      });
    });
  });

  group('ES2019 - Object.fromEntries()', () {
    group('Basic fromEntries() Behavior', () {
      test('should create object from array of entries', () {
        const code = '''
          const entries = [['a', 1], ['b', 2], ['c', 3]];
          const obj = Object.fromEntries(entries);
          JSON.stringify(obj);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('{"a":1,"b":2,"c":3}'));
      });

      test('should work with Map', () {
        const code = '''
          const map = new Map([['foo', 'bar'], ['baz', 42]]);
          const obj = Object.fromEntries(map);
          JSON.stringify(obj);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('{"foo":"bar","baz":42}'));
      });

      test('should convert entries to object', () {
        const code = '''
          const entries = [['name', 'John'], ['age', 30], ['city', 'NYC']];
          const obj = Object.fromEntries(entries);
          obj.name + ',' + obj.age + ',' + obj.city;
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('John,30,NYC'));
      });

      test('should invert Object.entries()', () {
        const code = '''
          const original = {x: 1, y: 2, z: 3};
          const entries = Object.entries(original);
          const inverted = Object.fromEntries(entries);
          JSON.stringify(inverted);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('{"x":1,"y":2,"z":3}'));
      });
    });

    group('fromEntries() Edge Cases', () {
      test('should handle empty array', () {
        const code = '''
          const obj = Object.fromEntries([]);
          JSON.stringify(obj);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('{}'));
      });

      test('should handle duplicate keys (last wins)', () {
        const code = '''
          const entries = [['a', 1], ['a', 2], ['a', 3]];
          const obj = Object.fromEntries(entries);
          obj.a;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(3));
      });

      test('should convert keys to strings', () {
        const code = '''
          const entries = [[1, 'one'], [2, 'two'], [true, 'yes']];
          const obj = Object.fromEntries(entries);
          obj[1] + ',' + obj[2] + ',' + obj['true'];
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('one,two,yes'));
      });
    });

    group('fromEntries() Practical Use Cases', () {
      test('should transform object values', () {
        const code = '''
          const obj = {a: 1, b: 2, c: 3};
          const doubled = Object.fromEntries(
            Object.entries(obj).map(([k, v]) => [k, v * 2])
          );
          JSON.stringify(doubled);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('{"a":2,"b":4,"c":6}'));
      });

      test('should filter object properties', () {
        const code = '''
          const obj = {a: 1, b: 2, c: 3, d: 4};
          const filtered = Object.fromEntries(
            Object.entries(obj).filter(([k, v]) => v % 2 === 0)
          );
          JSON.stringify(filtered);
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('{"b":2,"d":4}'));
      });

      test('should convert query string to object', () {
        const code = '''
          const params = [['name', 'John'], ['age', '30']];
          const query = Object.fromEntries(params);
          query.name + '|' + query.age;
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('John|30'));
      });
    });
  });

  group('ES2019 - String.prototype.trimStart() and trimEnd()', () {
    group('trimStart() Behavior', () {
      test('should remove leading whitespace', () {
        const code = '''
          const str = '   hello';
          str.trimStart();
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('hello'));
      });

      test('should remove leading tabs and newlines', () {
        const code = r'''
          const str = '\t\n  hello';
          str.trimStart();
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('hello'));
      });

      test('should not remove trailing whitespace', () {
        const code = '''
          const str = '  hello  ';
          str.trimStart();
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('hello  '));
      });

      test('should handle empty string', () {
        const code = '''
          const str = '';
          str.trimStart();
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals(''));
      });

      test('should handle string with only whitespace', () {
        const code = '''
          const str = '   ';
          str.trimStart();
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals(''));
      });

      test('should have trimLeft() as alias', () {
        const code = '''
          const str = '  hello';
          str.trimLeft();
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('hello'));
      });
    });

    group('trimEnd() Behavior', () {
      test('should remove trailing whitespace', () {
        const code = '''
          const str = 'hello   ';
          str.trimEnd();
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('hello'));
      });

      test('should remove trailing tabs and newlines', () {
        const code = r'''
          const str = 'hello\t\n  ';
          str.trimEnd();
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('hello'));
      });

      test('should not remove leading whitespace', () {
        const code = '''
          const str = '  hello  ';
          str.trimEnd();
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('  hello'));
      });

      test('should handle empty string', () {
        const code = '''
          const str = '';
          str.trimEnd();
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals(''));
      });

      test('should handle string with only whitespace', () {
        const code = '''
          const str = '   ';
          str.trimEnd();
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals(''));
      });

      test('should have trimRight() as alias', () {
        const code = '''
          const str = 'hello  ';
          str.trimRight();
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('hello'));
      });
    });

    group('trim() Comparison', () {
      test('should compare trim(), trimStart(), and trimEnd()', () {
        const code = '''
          const str = '  hello  ';
          const full = str.trim();
          const start = str.trimStart();
          const end = str.trimEnd();
          full + '|' + start + '|' + end;
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('hello|hello  |  hello'));
      });
    });
  });

  group('ES2019 - Optional Catch Binding', () {
    test('should allow catch without parameter', () {
      const code = '''
        let result = 'start';
        try {
          throw new Error('test');
        } catch {
          result = 'caught';
        }
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('caught'));
    });

    test('should work with multiple statements in catch', () {
      const code = '''
        let count = 0;
        try {
          throw new Error('test');
        } catch {
          count++;
          count++;
        }
        count;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(2));
    });

    test('should work with nested try-catch', () {
      const code = '''
        let result = 'none';
        try {
          try {
            throw new Error('inner');
          } catch {
            result = 'inner-caught';
            throw new Error('outer');
          }
        } catch {
          result += '-outer-caught';
        }
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('inner-caught-outer-caught'));
    });

    test('should execute finally block', () {
      const code = '''
        let result = '';
        try {
          throw new Error('test');
        } catch {
          result += 'catch';
        } finally {
          result += '-finally';
        }
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('catch-finally'));
    });

    test('should not require error variable when not needed', () {
      const code = '''
        function parseJSON(str) {
          try {
            return JSON.parse(str);
          } catch {
            return null;
          }
        }
        parseJSON('invalid') === null;
      ''';
      final result = interpreter.eval(code);
      expect(result.toBoolean(), isTrue);
    });
  });

  group('ES2019 - Symbol.prototype.description', () {
    test('should return description of symbol', () {
      const code = '''
        const sym = Symbol('mySymbol');
        sym.description;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('mySymbol'));
    });

    test('should return undefined for symbol without description', () {
      const code = '''
        const sym = Symbol();
        sym.description === undefined;
      ''';
      final result = interpreter.eval(code);
      expect(result.toBoolean(), isTrue);
    });

    test('should return empty string for empty description', () {
      const code = '''
        const sym = Symbol('');
        sym.description;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals(''));
    });

    test('should work with well-known symbols', () {
      const code = '''
        Symbol.iterator.description;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('Symbol.iterator'));
    });

    test('should not be writable', () {
      const code = '''
        const sym = Symbol('test');
        const original = sym.description;
        try {
          sym.description = 'changed';
        } catch {}
        sym.description === original;
      ''';
      final result = interpreter.eval(code);
      expect(result.toBoolean(), isTrue);
    });
  });

  group('ES2019 - Well-formed JSON.stringify()', () {
    test('should handle unpaired surrogates', () {
      const code = r'''
        const str = '\uD800';
        const result = JSON.stringify(str);
        result;
      ''';
      final result = interpreter.eval(code);
      // Should escape unpaired surrogates
      expect(result.toString(), contains('\\u'));
    });

    test('should stringify normal characters correctly', () {
      const code = '''
        const obj = {text: 'hello'};
        JSON.stringify(obj);
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('{"text":"hello"}'));
    });

    test('should handle emoji correctly', () {
      const code = '''
        const obj = {emoji: '😀'};
        JSON.stringify(obj);
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), contains('😀'));
    });
  });

  group('ES2019 - Function.prototype.toString()', () {
    test('should return exact source text of function', () {
      const code = '''
        function myFunc(  a,  b  ) {
          return a + b;
        }
        const str = myFunc.toString();
        str.includes('myFunc') && str.includes('a + b');
      ''';
      final result = interpreter.eval(code);
      expect(result.toBoolean(), isTrue);
    });

    test('should work with arrow functions', () {
      const code = '''
        const arrow = (x) => x * 2;
        const str = arrow.toString();
        str.includes('=>') && str.includes('x * 2');
      ''';
      final result = interpreter.eval(code);
      expect(result.toBoolean(), isTrue);
    });

    test('should work with methods', () {
      const code = '''
        const obj = {
          method() { return 42; }
        };
        const str = obj.method.toString();
        str.includes('method') && str.includes('42');
      ''';
      final result = interpreter.eval(code);
      expect(result.toBoolean(), isTrue);
    });
  });

  group('ES2019 - Integration Tests', () {
    test('should use flat() with Object.fromEntries()', () {
      const code = '''
        const nested = [[['a', 1]], [['b', 2]]];
        const flattened = nested.flat(1);
        const obj = Object.fromEntries(flattened);
        JSON.stringify(obj);
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('{"a":1,"b":2}'));
    });

    test('should use flatMap() with trimStart()', () {
      const code = '''
        const arr = ['  hello', '  world'];
        const result = arr.flatMap(s => [s.trimStart()]);
        JSON.stringify(result);
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('["hello","world"]'));
    });

    test('should combine multiple ES2019 features', () {
      const code = '''
        const data = [[' a ', 1], [' b ', 2]];
        const obj = Object.fromEntries(
          data.flatMap(([k, v]) => [[k.trimStart().trimEnd(), v * 2]])
        );
        JSON.stringify(obj);
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('{"a":2,"b":4}'));
    });
  });
}
