import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('ES6 Destructuring - Variable Declarations', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('Object Destructuring', () {
      test('should destructure simple object properties', () {
        const code = '''
          const obj = {x: 10, y: 20};
          const {x, y} = obj;
          x + y;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(30));
      });

      test('should support property renaming', () {
        const code = '''
          const obj = {x: 10, y: 20};
          const {x: a, y: b} = obj;
          a + b;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(30));
      });

      test('should support default values', () {
        const code = '''
          const {a = 5, b = 10} = {a: 3};
          a + b;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(13));
      });

      test('should support rest properties', () {
        const code = '''
          const {x, ...rest} = {x: 1, y: 2, z: 3};
          rest.y + rest.z;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(5));
      });

      test('should support object rest from string primitives', () {
        final result = interpreter.eval('''
          let rest;
          ({...rest} = 'foo');
          rest[0] + rest[1] + rest[2];
        ''');

        expect(result.toString(), equals('foo'));
      });

      test('should skip non-enumerable properties in object rest', () {
        final result = interpreter.eval('''
          let rest;
          const obj = {a: 1, b: 2};
          Object.defineProperty(obj, 'hidden', { value: 3, enumerable: false });
          ({...rest} = obj);
          Object.getOwnPropertyDescriptor(rest, 'hidden') === undefined && rest.a + rest.b;
        ''');

        expect(result.toNumber(), equals(3));
      });

      test('should support nested object destructuring', () {
        const code = '''
          const data = {user: {name: 'Alice', age: 30}};
          const {user: {name, age}} = data;
          name + ' is ' + age;
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('Alice is 30'));
      });
    });

    group('Array Destructuring', () {
      test('should destructure array elements', () {
        const code = '''
          const arr = [1, 2, 3, 4, 5];
          const [a, b, c] = arr;
          a + b + c;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(6));
      });

      test('should support array holes', () {
        const code = '''
          const arr = [1, 2, 3, 4, 5];
          const [a, , c] = arr;
          a + c;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(4));
      });

      test('should support rest elements', () {
        const code = '''
          const arr = [1, 2, 3, 4, 5];
          const [a, b, ...rest] = arr;
          rest[0] + rest[1] + rest[2];
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(12));
      });

      test('should support default values in arrays', () {
        const code = '''
          const [a = 1, b = 2, c = 3] = [10];
          a + b + c;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(15));
      });

      test('should support nested array destructuring', () {
        const code = '''
          const arr = [1, [2, 3], 4];
          const [a, [b, c], d] = arr;
          a + b + c + d;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(10));
      });
    });

    group('Mixed Destructuring', () {
      test('should support mixed object and array destructuring', () {
        const code = '''
          const data = {items: [1, 2, 3]};
          const {items: [first, second]} = data;
          first + second;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(3));
      });

      test('should support nested mixed destructuring', () {
        const code = '''
          const data = {users: [{name: 'Alice', age: 30}]};
          const {users: [{name, age}]} = data;
          name + ' is ' + age;
        ''';
        final result = interpreter.eval(code);
        expect(result.toString(), equals('Alice is 30'));
      });
    });

    group('Different Variable Kinds', () {
      test('should work with let', () {
        const code = '''
          const obj = {x: 10, y: 20};
          let {x, y} = obj;
          x = x + 5;
          y = y + 10;
          x + y;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(45));
      });

      test('should work with var', () {
        const code = '''
          var {a, b} = {a: 1, b: 2};
          a + b;
        ''';
        final result = interpreter.eval(code);
        expect(result.toNumber(), equals(3));
      });
    });
  });

  group('ES6 Destructuring - Assignments', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('should support object destructuring assignment', () {
      const code = '''
        let x, y;
        ({x, y} = {x: 10, y: 20});
        x + y;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(30));
    });

    test('should evaluate computed property names in object destructuring', () {
      final result = interpreter.eval('''
        let value;
        const key = 'answer';
        ({ [key]: value } = { answer: 42 });
        value;
      ''');

      expect(result.toNumber(), equals(42));
    });

    test('should read numeric property keys from array sources', () {
      final result = interpreter.eval('''
        let value;
        ({ 1: value } = [1, 2, 3]);
        value;
      ''');

      expect(result.toNumber(), equals(2));
    });

    test('should support nested object patterns inside array rest', () {
      final result = interpreter.eval('''
        let value;
        [...{ 1: value }] = [1, 2, 3];
        value;
      ''');

      expect(result.toNumber(), equals(2));
    });

    test(
      'should forward computed property name errors in object destructuring',
      () {
        expect(
          () => interpreter.eval('''
          let a, x;
          0, ({ [a.b]: x } = {});
        '''),
          throwsA(isA<JSException>()),
        );
      },
    );

    test('should support array destructuring assignment', () {
      const code = '''
        let a, b;
        [a, b] = [1, 2];
        a + b;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(3));
    });

    test('should exhaust iterables for array rest assignment', () {
      final result =
          interpreter.eval('''
        let x;
        let count = 0;
          function* values() {
            count += 1;
            yield 1;
            count += 1;
            yield 2;
            count += 1;
            yield 3;
          }

          [...x] = values();
        ({ count, size: x.length, last: x[2] });
      ''')
              as JSObject;

      expect(result.getProperty('count').toNumber(), equals(3));
      expect(result.getProperty('size').toNumber(), equals(3));
      expect(result.getProperty('last').toNumber(), equals(3));
    });

    test('should close iterators for empty array assignment patterns', () {
      final result = interpreter.eval('''
        let closed = 0;
        const iterable = {
          [Symbol.iterator]() {
            return {
              next() {
                return { value: 1, done: false };
              },
              return() {
                closed += 1;
                return {};
              }
            };
          }
        };

        [] = iterable;
        closed;
      ''');

      expect(result.toNumber(), equals(1));
    });

    test('should evaluate array member targets before iterator advance', () {
      final result = interpreter.eval('''
        var log = [];

        function source() {
          log.push('source');
          var iterator = {
            next: function() {
              log.push('iterator-step');
              return {
                get done() {
                  log.push('iterator-done');
                  return true;
                }
              };
            }
          };
          var source = {};
          source[Symbol.iterator] = function() {
            log.push('iterator');
            return iterator;
          };
          return source;
        }

        function target() {
          log.push('target');
          return {
            set q(v) {
              log.push('set');
            }
          };
        }

        function targetKey() {
          log.push('target-key');
          return {
            toString: function() {
              log.push('target-key-tostring');
              return 'q';
            }
          };
        }

        [target()[targetKey()]] = source();
        log.join(',');
      ''');

      expect(
        result.toString(),
        equals(
          'source,iterator,target,target-key,iterator-step,iterator-done,target-key-tostring,set',
        ),
      );
    });

    test(
      'should evaluate object member targets before reading source values',
      () {
        final result = interpreter.eval('''
        var log = [];

        function source() {
          log.push('source');
          return {
            get p() {
              log.push('get');
            }
          };
        }

        function target() {
          log.push('target');
          return {
            set q(v) {
              log.push('set');
            }
          };
        }

        function sourceKey() {
          log.push('source-key');
          return {
            toString: function() {
              log.push('source-key-tostring');
              return 'p';
            }
          };
        }

        function targetKey() {
          log.push('target-key');
          return {
            toString: function() {
              log.push('target-key-tostring');
              return 'q';
            }
          };
        }

        ({ [sourceKey()]: target()[targetKey()] } = source());
        log.join(',');
      ''');

        expect(
          result.toString(),
          equals(
            'source,source-key,source-key-tostring,target,target-key,get,target-key-tostring,set',
          ),
        );
      },
    );

    test('should support swapping variables', () {
      const code = '''
        let a = 1, b = 2;
        [a, b] = [b, a];
        a * 10 + b;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(21));
    });

    test(
      'should reject arguments and eval in strict destructuring assignment',
      () {
        expect(
          () => interpreter.eval('''
          "use strict";
          [arguments] = [];
        '''),
          throwsA(isA<JSSyntaxError>()),
        );

        expect(
          () => interpreter.eval('''
          "use strict";
          ({ eval } = {});
        '''),
          throwsA(isA<JSSyntaxError>()),
        );
      },
    );

    test(
      'should reject invalid rest placement in destructuring assignment',
      () {
        expect(
          () => interpreter.eval('''
          [...rest,] = [];
        '''),
          throwsA(isA<JSSyntaxError>()),
        );

        expect(
          () => interpreter.eval('''
          ({...rest, value} = {});
        '''),
          throwsA(isA<JSSyntaxError>()),
        );
      },
    );

    test(
      'should reject escaped reserved words in destructuring assignment shorthand',
      () {
        expect(
          () => interpreter.eval(r'''
          ({ bre\u0061k } = { break: 1 });
        '''),
          throwsA(isA<JSSyntaxError>()),
        );
      },
    );

    test('should respect TDZ for destructuring assignment targets', () {
      expect(
        () => interpreter.eval('''
          [x] = [];
          let x;
        '''),
        throwsA(isA<JSReferenceError>()),
      );

      expect(
        () => interpreter.eval('''
          [...x] = [];
          let x;
        '''),
        throwsA(isA<JSReferenceError>()),
      );

      expect(
        () => interpreter.eval('''
          ({ a: x } = {});
          let x;
        '''),
        throwsA(isA<JSReferenceError>()),
      );

      expect(
        () => interpreter.eval('''
          (function() {
            ({ a: x } = {});
          })();
          let x;
        '''),
        throwsA(anyOf(isA<JSReferenceError>(), isA<JSException>())),
      );
    });

    test(
      'should infer names for anonymous defaults in destructuring assignment',
      () {
        final result =
            interpreter.eval('''
          let fn, cls, xCls2;
          [fn = function() {}, cls = class {}, xCls2 = class { static name() {} }] = [];

          const fnDesc = Object.getOwnPropertyDescriptor(fn, 'name');
          const clsDesc = Object.getOwnPropertyDescriptor(cls, 'name');

          ({
            fnName: fn.name,
            fnWritable: fnDesc.writable,
            fnEnumerable: fnDesc.enumerable,
            fnConfigurable: fnDesc.configurable,
            clsName: cls.name,
            clsWritable: clsDesc.writable,
            clsEnumerable: clsDesc.enumerable,
            clsConfigurable: clsDesc.configurable,
            xCls2Named: xCls2.name === 'xCls2'
          });
        ''')
                as JSObject;

        expect(result.getProperty('fnName').toString(), equals('fn'));
        expect(result.getProperty('fnWritable').toBoolean(), isFalse);
        expect(result.getProperty('fnEnumerable').toBoolean(), isFalse);
        expect(result.getProperty('fnConfigurable').toBoolean(), isTrue);
        expect(result.getProperty('clsName').toString(), equals('cls'));
        expect(result.getProperty('clsWritable').toBoolean(), isFalse);
        expect(result.getProperty('clsEnumerable').toBoolean(), isFalse);
        expect(result.getProperty('clsConfigurable').toBoolean(), isTrue);
        expect(result.getProperty('xCls2Named').toBoolean(), isFalse);
      },
    );
  });

  group('ES6 Destructuring - For-of Loops', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('should support object destructuring in for-of', () {
      const code = '''
        const users = [
          {name: 'Alice', age: 30},
          {name: 'Bob', age: 25},
          {name: 'Charlie', age: 35}
        ];
        let sum = 0;
        for (const {age} of users) {
          sum += age;
        }
        sum;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(90));
    });

    test('should support array destructuring in for-of', () {
      const code = '''
        const pairs = [[1, 2], [3, 4], [5, 6]];
        let sum = 0;
        for (const [a, b] of pairs) {
          sum += a + b;
        }
        sum;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(21));
    });

    test('should support nested destructuring in for-of', () {
      const code = '''
        const data = [
          {point: {x: 1, y: 2}},
          {point: {x: 3, y: 4}}
        ];
        let sum = 0;
        for (const {point: {x, y}} of data) {
          sum += x + y;
        }
        sum;
      ''';
      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(10));
    });
  });

  group('ES6 Destructuring - For-in Loops', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('should support destructuring in for-in', () {
      const code = '''
        const obj = {a: 1, b: 2, c: 3};
        let result = '';
        for (const key in obj) {
          result += key;
        }
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('abc'));
    });
  });
}
