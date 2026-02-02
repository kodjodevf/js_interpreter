import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Getters and Setters Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('Object Literal Getters/Setters', () {
      test('should support getter in object literal', () {
        final result = interpreter.eval('''
          let obj = {
            _value: 10,
            get value() {
              return this._value;
            }
          };
          obj.value;
        ''');
        expect(result.toString(), '10');
      });

      test('should support setter in object literal', () {
        final result = interpreter.eval('''
          let obj = {
            _value: 0,
            set value(val) {
              this._value = val;
            }
          };
          obj.value = 42;
          obj._value;
        ''');
        expect(result.toString(), '42');
      });

      test('should support getter and setter together', () {
        final result = interpreter.eval('''
          let obj = {
            _value: 0,
            get value() {
              return this._value * 2;
            },
            set value(val) {
              this._value = val;
            }
          };
          obj.value = 21;
          obj.value;
        ''');
        expect(result.toString(), '42');
      });

      test('should have correct this context in getter/setter', () {
        final result = interpreter.eval('''
          let obj = {
            name: 'Test',
            _counter: 0,
            get info() {
              this._counter++;
              return this.name + ' (' + this._counter + ')';
            }
          };
          obj.info + ' - ' + obj.info;
        ''');
        expect(result.toString(), 'Test (1) - Test (2)');
      });
    });

    group('Object.defineProperty with get/set', () {
      test('should support Object.defineProperty with getter', () {
        final result = interpreter.eval('''
          let obj = { _value: 100 };
          Object.defineProperty(obj, 'value', {
            get: function() {
              return this._value;
            }
          });
          obj.value;
        ''');
        expect(result.toString(), '100');
      });

      test('should support Object.defineProperty with setter', () {
        final result = interpreter.eval('''
          let obj = { _value: 0 };
          Object.defineProperty(obj, 'value', {
            set: function(val) {
              this._value = val * 2;
            }
          });
          obj.value = 25;
          obj._value;
        ''');
        expect(result.toString(), '50');
      });

      test('should support Object.defineProperty with both get and set', () {
        final result = interpreter.eval('''
          let obj = {};
          Object.defineProperty(obj, 'temperature', {
            get: function() {
              return this._celsius || 0;
            },
            set: function(celsius) {
              this._celsius = celsius;
            }
          });
          obj.temperature = 25;
          obj.temperature;
        ''');
        expect(result.toString(), '25');
      });
    });

    group('Property Descriptors', () {
      test('should support Object.getOwnPropertyDescriptor', () {
        final result = interpreter.eval('''
          let obj = {
            get value() { return 42; }
          };
          let desc = Object.getOwnPropertyDescriptor(obj, 'value');
          typeof desc.get;
        ''');
        expect(result.toString(), 'function');
      });

      test('should detect getter-only properties', () {
        final result = interpreter.eval('''
          let obj = {
            get readOnly() { return 'read-only'; }
          };
          let desc = Object.getOwnPropertyDescriptor(obj, 'readOnly');
          desc.set === undefined;
        ''');
        expect(result.toString(), 'true');
      });

      test('should detect setter-only properties', () {
        final result = interpreter.eval('''
          let obj = {};
          Object.defineProperty(obj, 'writeOnly', {
            set: function(val) { this._hidden = val; }
          });
          let desc = Object.getOwnPropertyDescriptor(obj, 'writeOnly');
          desc.get === undefined && typeof desc.set === 'function';
        ''');
        expect(result.toString(), 'true');
      });
    });

    group('Inheritance and Prototype', () {
      test('should inherit getters from prototype', () {
        final result = interpreter.eval('''
          function Parent() {
            this._value = 0;
          }
          Object.defineProperty(Parent.prototype, 'value', {
            get: function() { return this._value; },
            set: function(val) { this._value = val; }
          });
          
          let child = new Parent();
          child.value = 42;
          child.value;
        ''');
        expect(result.toString(), '42');
      });

      test('should override inherited getters', () {
        final result = interpreter.eval('''
          function Parent() {}
          Object.defineProperty(Parent.prototype, 'value', {
            get: function() { return 'parent'; }
          });
          
          let child = new Parent();
          Object.defineProperty(child, 'value', {
            get: function() { return 'child'; }
          });
          
          child.value;
        ''');
        expect(result.toString(), 'child');
      });
    });

    group('References circulaires :', () {
      test('Protection contre stack overflow', () {
        // Test with direct circular reference
        final result = interpreter.eval('''
          var obj = {};
          obj.test = obj;  // Simple circular reference

          Object.defineProperty(obj, 'self', {
            get: function() {
              return this.self; // Circular reference in getter
            }
          });
          
          // Accessing the circular getter should not cause stack overflow
          obj.self;
          'safe';
        ''');

        // Le test devrait terminer sans erreur
        expect(result.toString(), equals('safe'));
      });

      test('Protection avec cycle indirect', () {
        final result = interpreter.eval('''
          var a = {}, b = {};
          
          Object.defineProperty(a, 'prop', {
            get: function() { return b.prop; }
          });
          
          Object.defineProperty(b, 'prop', {
            get: function() { return a.prop; }
          });
          
          // Access should return undefined instead of causing stack overflow
          var result = a.prop;
          typeof result;
        ''');

        expect(result.toString(), equals('undefined'));
      });

      test('Getter normal après cycle détecté', () {
        final result = interpreter.eval('''
          var obj = {};
          
          Object.defineProperty(obj, 'circular', {
            get: function() { return this.circular; }
          });
          
          Object.defineProperty(obj, 'normal', {
            get: function() { return 42; }
          });
          
          // First access triggers the protection
          obj.circular;
          
          // Second access to another property should work normally
          obj.normal;
        ''');

        expect(result.toNumber(), equals(42));
      });
    });

    group('Héritage de prototype :', () {
      test('Héritage de getters/setters', () {
        final result = interpreter.eval('''
          // Create a prototype with getter/setter
          var proto = {};
          Object.defineProperty(proto, 'value', {
            get: function() { return this._value || 0; },
            set: function(v) { this._value = v; }
          });
          
          // Create an object that inherits from the prototype
          var obj = Object.create(proto);
          
          // Test accessing the inherited getter
          obj.value = 100;
          obj.value;
        ''');

        expect(result.toNumber(), equals(100));
      });

      test('Override de getter dans objet dérivé', () {
        final result = interpreter.eval('''
          var parent = {};
          Object.defineProperty(parent, 'prop', {
            get: function() { return 'parent'; }
          });
          
          var child = Object.create(parent);
          Object.defineProperty(child, 'prop', {
            get: function() { return 'child'; }
          });
          
          child.prop;
        ''');

        expect(result.toString(), equals('child'));
      });

      test('Chaîne de prototypes', () {
        final result = interpreter.eval('''
          var grand = {};
          Object.defineProperty(grand, 'inherited', {
            get: function() { return 'grand'; }
          });
          
          var parent = Object.create(grand);
          var child = Object.create(parent);
          
          child.inherited;
        ''');

        expect(result.toString(), equals('grand'));
      });
    });

    group('Edge Cases', () {
      test('should handle getter that throws error', () {
        expect(() {
          interpreter.eval('''
            let obj = {
              get error() {
                throw new Error('Getter error');
              }
            };
            obj.error;
          ''');
        }, throwsA(isA<JSError>()));
      });

      test('should handle setter that throws error', () {
        expect(() {
          interpreter.eval('''
            let obj = {
              set error(val) {
                throw new Error('Setter error');
              }
            };
            obj.error = 42;
          ''');
        }, throwsA(isA<JSError>()));
      });

      test('should handle undefined getter return', () {
        final result = interpreter.eval('''
          let obj = {
            get undef() {
              // returns undefined implicitly
            }
          };
          obj.undef;
        ''');
        expect(result.isUndefined, true);
      });

      test('should handle getter with no return', () {
        final result = interpreter.eval('''
          let obj = {
            get noReturn() {
              let x = 42;
            }
          };
          obj.noReturn;
        ''');
        expect(result.isUndefined, true);
      });

      test('should handle multiple getters/setters on same object', () {
        final result = interpreter.eval('''
          let obj = {
            _a: 1,
            _b: 2,
            get a() { return this._a; },
            set a(val) { this._a = val; },
            get b() { return this._b; },
            set b(val) { this._b = val; }
          };
          obj.a = 10;
          obj.b = 20;
          obj.a + obj.b;
        ''');
        expect(result.toString(), '30');
      });
    });

    group('Enumeration and Introspection', () {
      test('should enumerate getters/setters in for...in', () {
        final result = interpreter.eval('''
          let obj = {
            regular: 1,
            get computed() { return 2; }
          };
          let keys = [];
          for (let key in obj) {
            keys.push(key);
          }
          keys.length;
        ''');
        expect(result.toString(), '2');
      });

      test('should list getters/setters in Object.keys', () {
        final result = interpreter.eval('''
          let obj = {
            regular: 1,
            get computed() { return 2; }
          };
          Object.keys(obj).length;
        ''');
        expect(result.toString(), '2');
      });

      test('should detect property configurability', () {
        final result = interpreter.eval('''
          let obj = {};
          Object.defineProperty(obj, 'configurable', {
            get: function() { return 'yes'; },
            configurable: true
          });
          Object.defineProperty(obj, 'nonConfigurable', {
            get: function() { return 'no'; },
            configurable: false
          });
          
          let desc1 = Object.getOwnPropertyDescriptor(obj, 'configurable');
          let desc2 = Object.getOwnPropertyDescriptor(obj, 'nonConfigurable');
          desc1.configurable && !desc2.configurable;
        ''');
        expect(result.toString(), 'true');
      });
    });

    group('Performance and Complex Cases', () {
      test('should handle nested getter calls', () {
        final result = interpreter.eval('''
          let obj = {
            _level1: {
              _level2: {
                _value: 42
              }
            },
            get level1() {
              return this._level1;
            },
            get deepValue() {
              return this.level1._level2._value;
            }
          };
          obj.deepValue;
        ''');
        expect(result.toString(), '42');
      });

      test('should handle getter chains', () {
        final result = interpreter.eval('''
          let obj = {
            _base: 10,
            get doubled() { return this._base * 2; },
            get tripled() { return this.doubled + this._base; },
            get final() { return this.tripled * 2; }
          };
          obj.final;
        ''');
        expect(result.toString(), '60');
      });

      test('should handle circular getter references safely', () {
        // This test might cause infinite recursion if not handled properly
        expect(() {
          interpreter.eval('''
            let obj = {
              get a() { return this.b; },
              get b() { return this.a; }
            };
            obj.a;
          ''');
        }, returnsNormally);
      });
    });
  });
}
