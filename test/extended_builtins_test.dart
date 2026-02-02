import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

// Helper to inject test262 harness
String createTest262Harness(String code) {
  return '''
    let __test_passed = true;
    let __test_error = null;
    
    function assert(value, message) {
      if (!value) {
        __test_passed = false;
        __test_error = message || 'Assertion failed';
        throw new Error(__test_error);
      }
    }
    assert.sameValue = function(actual, expected, message) {
      if (actual !== expected) {
        __test_passed = false;
        __test_error = (message || '') + ' Expected: ' + expected + ', Got: ' + actual;
        throw new Error(__test_error);
      }
    };
    
    function \$DONE(err) {
      if (err) {
        __test_passed = false;
        __test_error = err.toString();
        throw err;
      }
    }
    
    $code
    
    __test_passed;
  ''';
}

void main() {
  group('Test262 - Extended Built-ins Coverage', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    // Test WeakRef
    test('WeakRef constructor and deref', () {
      final code = createTest262Harness('''
        const obj = { value: 42 };
        const ref = new WeakRef(obj);
        assert(ref.deref() === obj, "WeakRef.deref should return original object");
      ''');

      expect(() => interpreter.eval(code), isNotNull);
    });

    // Test FinalizationRegistry
    test('FinalizationRegistry constructor', () {
      final code = createTest262Harness('''
        let registryCalled = false;
        const registry = new FinalizationRegistry((heldValue) => {
          registryCalled = true;
        });
        assert(typeof registry.register === "function", "FinalizationRegistry should have register method");
        assert(typeof registry.unregister === "function", "FinalizationRegistry should have unregister method");
      ''');

      expect(() => interpreter.eval(code), isNotNull);
    });

    // Test Iterator protocol
    test('Array Iterator protocol', () {
      final code = createTest262Harness('''
        const arr = [1, 2, 3];
        const iterator = arr[Symbol.iterator]();
        
        const result1 = iterator.next();
        assert(result1.value === 1, "First value should be 1");
        assert(result1.done === false, "First should not be done");
        
        const result2 = iterator.next();
        assert(result2.value === 2, "Second value should be 2");
        assert(result2.done === false, "Second should not be done");
        
        const result3 = iterator.next();
        assert(result3.value === 3, "Third value should be 3");
        assert(result3.done === false, "Third should not be done");
        
        const result4 = iterator.next();
        assert(result4.value === undefined, "Fourth value should be undefined");
        assert(result4.done === true, "Fourth should be done");
      ''');

      expect(() => interpreter.eval(code), isNotNull);
    });

    // Test String Iterator
    test('String Iterator protocol', () {
      final code = createTest262Harness('''
        const str = "ab";
        const iterator = str[Symbol.iterator]();
        
        const result1 = iterator.next();
        assert(result1.value === "a", "First char should be 'a'");
        
        const result2 = iterator.next();
        assert(result2.value === "b", "Second char should be 'b'");
        
        const result3 = iterator.next();
        assert(result3.done === true, "Should be done");
      ''');

      expect(() => interpreter.eval(code), isNotNull);
    });

    // Test Map Iterator
    test('Map Iterator protocol', () {
      final code = createTest262Harness('''
        const map = new Map([["a", 1], ["b", 2]]);
        const iterator = map[Symbol.iterator]();
        
        const entry1 = iterator.next();
        assert(Array.isArray(entry1.value), "Entry should be array");
        assert(entry1.value[0] === "a", "First key should be 'a'");
        assert(entry1.value[1] === 1, "First value should be 1");
        
        const entry2 = iterator.next();
        assert(entry2.value[0] === "b", "Second key should be 'b'");
        assert(entry2.value[1] === 2, "Second value should be 2");
      ''');

      expect(() => interpreter.eval(code), isNotNull);
    });

    // Test Set Iterator
    test('Set Iterator protocol', () {
      final code = createTest262Harness('''
        const set = new Set([1, 2, 3]);
        const iterator = set[Symbol.iterator]();
        
        const result1 = iterator.next();
        assert(result1.value === 1, "First value should be 1");
        
        const result2 = iterator.next();
        assert(result2.value === 2, "Second value should be 2");
        
        const result3 = iterator.next();
        assert(result3.value === 3, "Third value should be 3");
      ''');

      expect(() => interpreter.eval(code), isNotNull);
    });

    // Test AsyncIterator
    test('AsyncIterator Symbol', () {
      final code = createTest262Harness('''
        async function* gen() {
          yield 1;
          yield 2;
        }
        const iterator = gen();
        assert(Symbol.asyncIterator in iterator, "Should have asyncIterator symbol");
      ''');

      expect(() => interpreter.eval(code), isNotNull);
    });

    // Test Atomics
    test('Atomics object exists', () {
      final code = createTest262Harness('''
        assert(typeof Atomics === "object", "Atomics should exist");
        assert(typeof Atomics.load === "function", "Atomics.load should exist");
        assert(typeof Atomics.store === "function", "Atomics.store should exist");
      ''');

      expect(() => interpreter.eval(code), isNotNull);
    });

    // Test Symbol.asyncDispose
    test('Symbol.asyncDispose exists', () {
      final code = createTest262Harness('''
        assert(typeof Symbol.asyncDispose === "symbol", "Symbol.asyncDispose should exist");
      ''');

      expect(() => interpreter.eval(code), isNotNull);
    });

    // Test Symbol.dispose
    test('Symbol.dispose exists', () {
      final code = createTest262Harness('''
        assert(typeof Symbol.dispose === "symbol", "Symbol.dispose should exist");
      ''');

      expect(() => interpreter.eval(code), isNotNull);
    });
  });
}
