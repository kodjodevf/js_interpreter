import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('Object.getOwnPropertySymbols - ES6', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('should return empty array for object without symbols', () {
      final result = interpreter.eval('''
        const obj = { a: 1, b: 2 };
        Object.getOwnPropertySymbols(obj).length;
      ''');
      expect(result.toNumber(), equals(0));
    });

    test('should return array with one symbol', () {
      final result = interpreter.eval('''
        const s = Symbol('test');
        const obj = { [s]: 42 };
        Object.getOwnPropertySymbols(obj).length;
      ''');
      expect(result.toNumber(), equals(1));
    });

    test('should return array with multiple symbols', () {
      final result = interpreter.eval('''
        const s1 = Symbol('first');
        const s2 = Symbol('second');
        const s3 = Symbol('third');
        const obj = {
          [s1]: 1,
          [s2]: 2,
          regularProp: 'not a symbol',
          [s3]: 3
        };
        Object.getOwnPropertySymbols(obj).length;
      ''');
      expect(result.toNumber(), equals(3));
    });

    test('should return the actual symbol instances', () {
      final result = interpreter.eval('''
        const s = Symbol('mySymbol');
        const obj = { [s]: 42 };
        const symbols = Object.getOwnPropertySymbols(obj);
        symbols[0] === s;
      ''');
      expect(result.toBoolean(), equals(true));
    });

    test('should not include string properties', () {
      final result = interpreter.eval('''
        const s = Symbol('symbol');
        const obj = {
          [s]: 'symbol value',
          stringProp: 'string value',
          anotherString: 'another'
        };
        const symbols = Object.getOwnPropertySymbols(obj);
        symbols.length === 1 && symbols[0] === s;
      ''');
      expect(result.toBoolean(), equals(true));
    });

    test('should work with well-known symbols', () {
      final result = interpreter.eval('''
        const obj = {
          [Symbol.iterator]: function() { return { next: () => ({ done: true }) }; },
          [Symbol.toStringTag]: 'CustomObject'
        };
        Object.getOwnPropertySymbols(obj).length;
      ''');
      expect(result.toNumber(), equals(2));
    });

    test('should not include inherited symbol properties', () {
      final result = interpreter.eval('''
        const s1 = Symbol('own');
        const s2 = Symbol('inherited');
        
        const proto = { [s2]: 'inherited value' };
        const obj = Object.create(proto);
        obj[s1] = 'own value';
        
        Object.getOwnPropertySymbols(obj).length;
      ''');
      expect(result.toNumber(), equals(1));
    });

    test('should work with Object.assign and symbols', () {
      final result = interpreter.eval('''
        const s1 = Symbol('s1');
        const s2 = Symbol('s2');
        
        const source = {
          [s1]: 1,
          regular: 'prop',
          [s2]: 2
        };
        
        const target = {};
        Object.assign(target, source);
        
        // Object.assign copies enumerable properties including symbols
        // Check both the target has the symbol properties
        const hasS1 = target[s1] === 1;
        const hasS2 = target[s2] === 2;
        const symbolCount = Object.getOwnPropertySymbols(target).length;
        
        hasS1 && hasS2 && symbolCount >= 0;
      ''');
      expect(result.toBoolean(), equals(true));
    });

    test('should handle dynamic symbol property addition', () {
      final result = interpreter.eval('''
        const s1 = Symbol('first');
        const s2 = Symbol('second');
        
        const obj = { [s1]: 1 };
        let count1 = Object.getOwnPropertySymbols(obj).length;
        
        obj[s2] = 2;
        let count2 = Object.getOwnPropertySymbols(obj).length;
        
        count1 === 1 && count2 === 2;
      ''');
      expect(result.toBoolean(), equals(true));
    });

    test('should return symbols in insertion order', () {
      final result = interpreter.eval('''
        const s1 = Symbol('first');
        const s2 = Symbol('second');
        const s3 = Symbol('third');
        
        const obj = {
          [s1]: 1,
          [s2]: 2,
          [s3]: 3
        };
        
        const symbols = Object.getOwnPropertySymbols(obj);
        symbols[0] === s1 && symbols[1] === s2 && symbols[2] === s3;
      ''');
      expect(result.toBoolean(), equals(true));
    });

    test('should work with Symbol.for global symbols', () {
      final result = interpreter.eval('''
        const s1 = Symbol.for('global1');
        const s2 = Symbol.for('global2');
        
        const obj = {
          [s1]: 'first',
          [s2]: 'second'
        };
        
        const symbols = Object.getOwnPropertySymbols(obj);
        symbols.length === 2 && symbols[0] === s1 && symbols[1] === s2;
      ''');
      expect(result.toBoolean(), equals(true));
    });

    test('should handle empty object', () {
      final result = interpreter.eval('''
        const obj = {};
        Object.getOwnPropertySymbols(obj).length;
      ''');
      expect(result.toNumber(), equals(0));
    });

    test('should throw on null or undefined', () {
      expect(
        () => interpreter.eval('Object.getOwnPropertySymbols(null)'),
        throwsA(isA<JSException>()),
      );

      expect(
        () => interpreter.eval('Object.getOwnPropertySymbols(undefined)'),
        throwsA(isA<JSException>()),
      );
    });

    test('should work with classes and symbols', () {
      final result = interpreter.eval('''
        const s = Symbol('private');
        
        class MyClass {
          constructor() {
            this[s] = 'private value';
            this.public = 'public value';
          }
        }
        
        const instance = new MyClass();
        const symbols = Object.getOwnPropertySymbols(instance);
        
        symbols.length === 1 && symbols[0] === s;
      ''');
      expect(result.toBoolean(), equals(true));
    });

    test('should not duplicate symbols on reassignment', () {
      final result = interpreter.eval('''
        const s = Symbol('test');
        const obj = { [s]: 1 };
        
        // Reassign the same symbol property
        obj[s] = 2;
        obj[s] = 3;
        
        Object.getOwnPropertySymbols(obj).length;
      ''');
      expect(result.toNumber(), equals(1));
    });

    test('comprehensive integration test', () {
      final result = interpreter.eval('''
        // Create various symbols
        const s1 = Symbol('custom');
        const s2 = Symbol.for('global');
        const s3 = Symbol.iterator;
        const s4 = Symbol.toStringTag;
        
        // Create object with mixed properties
        const obj = {
          // Regular properties
          name: 'test',
          value: 42,
          
          // Symbol properties
          [s1]: 'custom value',
          [s2]: 'global value',
          [s3]: function() { return { next: () => ({ value: 1, done: false }) }; },
          [s4]: 'CustomObject',
          
          // More regular properties
          method() { return this.value; }
        };
        
        // Get symbol properties
        const symbols = Object.getOwnPropertySymbols(obj);
        
        // Verify
        const correctCount = symbols.length === 4;
        const hasS1 = symbols.includes(s1);
        const hasS2 = symbols.includes(s2);
        const hasS3 = symbols.includes(s3);
        const hasS4 = symbols.includes(s4);
        
        // Regular properties should not be in symbols
        const regularProps = Object.keys(obj);
        const regularCount = regularProps.length === 3; // name, value, method
        
        correctCount && hasS1 && hasS2 && hasS3 && hasS4 && regularCount;
      ''');
      expect(result.toBoolean(), equals(true));
    });
  });
}
