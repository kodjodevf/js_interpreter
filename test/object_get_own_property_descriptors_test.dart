import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

/// Tests complets pour Object.getOwnPropertyDescriptors() - ECMAScript 2017 (ES8)
///
/// Object.getOwnPropertyDescriptors(obj)
/// Returns an object containing all own property descriptors of an object
void main() {
  group('Object.getOwnPropertyDescriptors() - ES2017', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('Basic usage', () {
      test('should return descriptors for simple object', () {
        const code = '''
          const obj = {a: 1, b: 2};
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          Object.keys(descriptors).length === 2 &&
          descriptors.a.value === 1 &&
          descriptors.b.value === 2;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should return empty object for empty object', () {
        const code = '''
          const obj = {};
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          Object.keys(descriptors).length === 0;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should include all descriptor properties', () {
        const code = '''
          const obj = {prop: 42};
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          const desc = descriptors.prop;
          desc.value === 42 &&
          desc.writable === true &&
          desc.enumerable === true &&
          desc.configurable === true;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });
    });

    group('Data properties', () {
      test('should handle writable property', () {
        const code = '''
          const obj = {};
          Object.defineProperty(obj, 'writable', {
            value: 10,
            writable: true,
            enumerable: true,
            configurable: true
          });
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          descriptors.writable.writable === true;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should handle non-writable property', () {
        const code = '''
          const obj = {};
          Object.defineProperty(obj, 'readonly', {
            value: 10,
            writable: false,
            enumerable: true,
            configurable: true
          });
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          descriptors.readonly.writable === false;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should handle enumerable property', () {
        const code = '''
          const obj = {visible: true};
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          descriptors.visible.enumerable === true;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should handle non-enumerable property', () {
        const code = '''
          const obj = {};
          Object.defineProperty(obj, 'hidden', {
            value: 42,
            writable: true,
            enumerable: false,
            configurable: true
          });
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          descriptors.hidden.enumerable === false;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should handle configurable property', () {
        const code = '''
          const obj = {prop: 1};
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          descriptors.prop.configurable === true;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should handle non-configurable property', () {
        const code = '''
          const obj = {};
          Object.defineProperty(obj, 'fixed', {
            value: 100,
            writable: true,
            enumerable: true,
            configurable: false
          });
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          descriptors.fixed.configurable === false;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });
    });

    group('Accessor properties (getters/setters)', () {
      test('should handle getter', () {
        const code = '''
          const obj = {
            _value: 10,
            get value() { return this._value; }
          };
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          typeof descriptors.value.get === 'function' &&
          descriptors.value.set === undefined;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should handle setter', () {
        const code = '''
          const obj = {
            _value: 10,
            set value(v) { this._value = v; }
          };
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          typeof descriptors.value.set === 'function' &&
          descriptors.value.get === undefined;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should handle both getter and setter', () {
        const code = '''
          const obj = {
            _value: 10,
            get value() { return this._value; },
            set value(v) { this._value = v; }
          };
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          typeof descriptors.value.get === 'function' &&
          typeof descriptors.value.set === 'function';
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should not have value/writable for accessors', () {
        const code = '''
          const obj = {
            get prop() { return 42; }
          };
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          descriptors.prop.value === undefined &&
          descriptors.prop.writable === undefined;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should have enumerable/configurable for accessors', () {
        const code = '''
          const obj = {
            get prop() { return 42; }
          };
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          typeof descriptors.prop.enumerable === 'boolean' &&
          typeof descriptors.prop.configurable === 'boolean';
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });
    });

    group('Mixed properties', () {
      test('should handle both data and accessor properties', () {
        const code = '''
          const obj = {
            data: 42,
            _value: 10,
            get accessor() { return this._value; }
          };
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          Object.keys(descriptors).length === 3 &&
          descriptors.data.value === 42 &&
          typeof descriptors.accessor.get === 'function';
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should handle enumerable and non-enumerable', () {
        const code = '''
          const obj = {visible: 1};
          Object.defineProperty(obj, 'hidden', {
            value: 2,
            enumerable: false
          });
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          descriptors.visible.enumerable === true &&
          descriptors.hidden.enumerable === false;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should include all property types', () {
        const code = '''
          const obj = {
            regular: 1,
            _backing: 0,
            get computed() { return this._backing * 2; },
            set computed(v) { this._backing = v / 2; }
          };
          Object.defineProperty(obj, 'secret', {
            value: 42,
            enumerable: false
          });
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          Object.keys(descriptors).length === 4;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });
    });

    group('Return value structure', () {
      test('should return a plain object', () {
        const code = '''
          const obj = {a: 1};
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          typeof descriptors === 'object' && descriptors !== null;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should have descriptor objects as values', () {
        const code = '''
          const obj = {a: 1, b: 2};
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          typeof descriptors.a === 'object' &&
          typeof descriptors.b === 'object';
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('each descriptor should have correct keys', () {
        const code = '''
          const obj = {prop: 42};
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          const desc = descriptors.prop;
          'value' in desc &&
          'writable' in desc &&
          'enumerable' in desc &&
          'configurable' in desc;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });
    });

    group('Real-world use cases', () {
      test('should enable shallow copy with descriptors', () {
        const code = '''
          const original = {
            value: 42,
            _internal: 0,
            get doubled() { return this.value * 2; }
          };
          
          const copy = Object.defineProperties(
            {},
            Object.getOwnPropertyDescriptors(original)
          );
          
          copy.value === 42 && copy.doubled === 84;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should preserve property attributes when copying', () {
        const code = '''
          const original = {};
          Object.defineProperty(original, 'readonly', {
            value: 10,
            writable: false,
            enumerable: true,
            configurable: true
          });
          
          const copy = Object.defineProperties(
            {},
            Object.getOwnPropertyDescriptors(original)
          );
          
          const desc = Object.getOwnPropertyDescriptor(copy, 'readonly');
          desc.writable === false && desc.value === 10;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should work with Object.assign for mixin pattern', () {
        const code = '''
          const mixin = {
            _value: 0,
            get value() { return this._value; },
            set value(v) { this._value = v; },
            increment() { this._value++; }
          };
          
          const target = {};
          Object.defineProperties(
            target,
            Object.getOwnPropertyDescriptors(mixin)
          );
          
          target.value = 5;
          target.increment();
          target.value === 6;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should inspect object structure', () {
        const code = '''
          const obj = {
            public: 'visible',
            _private: 'hidden'
          };
          Object.defineProperty(obj, 'secret', {
            value: 42,
            enumerable: false
          });
          
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          const allKeys = Object.keys(descriptors);
          
          allKeys.length === 3 &&
          allKeys.includes('public') &&
          allKeys.includes('_private') &&
          allKeys.includes('secret');
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });
    });

    group('Edge cases', () {
      test('should handle object with no own properties', () {
        const code = '''
          const obj = Object.create({inherited: 1});
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          Object.keys(descriptors).length === 0;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should only return own properties, not inherited', () {
        const code = '''
          const proto = {inherited: 1};
          const obj = Object.create(proto);
          obj.own = 2;
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          Object.keys(descriptors).length === 1 &&
          'own' in descriptors &&
          !('inherited' in descriptors);
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should handle objects with many properties', () {
        const code = '''
          const obj = {};
          for (let i = 0; i < 10; i++) {
            obj['prop' + i] = i;
          }
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          Object.keys(descriptors).length === 10;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should handle property names with special characters', () {
        const code = '''
          const obj = {
            'normal': 1,
            'with-dash': 2,
            'with space': 3,
            '123numeric': 4
          };
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          Object.keys(descriptors).length === 4;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });
    });

    group('Error handling', () {
      test('should throw on null', () {
        const code = '''
          try {
            Object.getOwnPropertyDescriptors(null);
            false;
          } catch (e) {
            e.name === 'TypeError';
          }
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should throw on undefined', () {
        const code = '''
          try {
            Object.getOwnPropertyDescriptors(undefined);
            false;
          } catch (e) {
            e.name === 'TypeError';
          }
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });
    });

    group('Comparison with other methods', () {
      test('should be more complete than Object.keys', () {
        const code = '''
          const obj = {visible: 1};
          Object.defineProperty(obj, 'hidden', {
            value: 2,
            enumerable: false
          });
          
          const keys = Object.keys(obj);
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          
          keys.length === 1 &&
          Object.keys(descriptors).length === 2;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('should provide more info than Object.getOwnPropertyNames', () {
        const code = '''
          const obj = {prop: 42};
          const names = Object.getOwnPropertyNames(obj);
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          
          names.length === 1 &&
          Object.keys(descriptors).length === 1 &&
          typeof descriptors.prop.value !== 'undefined';
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });

      test('each property descriptor matches getOwnPropertyDescriptor', () {
        const code = '''
          const obj = {a: 1, b: 2};
          const descriptors = Object.getOwnPropertyDescriptors(obj);
          const descA = Object.getOwnPropertyDescriptor(obj, 'a');
          
          descriptors.a.value === descA.value &&
          descriptors.a.writable === descA.writable &&
          descriptors.a.enumerable === descA.enumerable &&
          descriptors.a.configurable === descA.configurable;
        ''';
        final result = interpreter.eval(code);
        expect(result.toBoolean(), isTrue);
      });
    });
  });
}
