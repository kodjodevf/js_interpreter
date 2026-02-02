import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });

  group('Computed Property Names', () {
    group('Basic Computed Properties', () {
      test('simple variable as property key', () {
        final result = interpreter.eval('''
          const key = "dynamicKey";
          const obj = {
            [key]: "value"
          };
          obj.dynamicKey;
        ''');
        expect(result.toString(), equals('value'));
      });

      test('expression as property key', () {
        final result = interpreter.eval('''
          const obj = {
            ["prop" + "Name"]: "value"
          };
          obj.propName;
        ''');
        expect(result.toString(), equals('value'));
      });

      test('number expression as property key', () {
        final result = interpreter.eval('''
          const obj = {
            [1 + 1]: "value"
          };
          obj[2];
        ''');
        expect(result.toString(), equals('value'));
      });

      test('multiple computed properties', () {
        interpreter.eval('''
          const key1 = "first";
          const key2 = "second";
          const obj = {
            [key1]: "value1",
            [key2]: "value2",
            normal: "value3"
          };
        ''');
        expect(interpreter.eval('obj.first').toString(), equals('value1'));
        expect(interpreter.eval('obj.second').toString(), equals('value2'));
        expect(interpreter.eval('obj.normal').toString(), equals('value3'));
      });
    });

    group('Computed Properties with Symbol', () {
      test('Symbol.iterator as computed property', () {
        interpreter.eval('''
          const iterable = {
            [Symbol.iterator]: function() {
              let i = 0;
              return {
                next: function() {
                  if (i < 3) {
                    return { value: i++, done: false };
                  }
                  return { done: true };
                }
              };
            }
          };
        ''');

        // Check that Symbol.iterator is defined
        final hasIterator = interpreter.eval(
          'typeof iterable[Symbol.iterator]',
        );
        expect(hasIterator.toString(), equals('function'));

        // Test iteration
        final result = interpreter.eval('''
          const results = [];
          const iter = iterable[Symbol.iterator]();
          let item;
          while (!(item = iter.next()).done) {
            results.push(item.value);
          }
          results;
        ''');
        final arr = result as JSArray;
        expect(arr.elements.length, equals(3));
        expect(arr.elements[0].toNumber(), equals(0));
        expect(arr.elements[1].toNumber(), equals(1));
        expect(arr.elements[2].toNumber(), equals(2));
      });

      test('custom symbol as property key', () {
        final result = interpreter.eval('''
          const sym = Symbol("customSymbol");
          const obj = {
            [sym]: "symbolValue"
          };
          obj[sym];
        ''');
        expect(result.toString(), equals('symbolValue'));
      });

      test('Symbol.toStringTag as computed property', () {
        final result = interpreter.eval('''
          const obj = {
            [Symbol.toStringTag]: "CustomObject"
          };
          obj[Symbol.toStringTag];
        ''');
        expect(result.toString(), equals('CustomObject'));
      });
    });

    group('Computed Method Names', () {
      test('method with computed name', () {
        final result = interpreter.eval('''
          const methodName = "greet";
          const obj = {
            [methodName]() {
              return "Hello!";
            }
          };
          obj.greet();
        ''');
        expect(result.toString(), equals('Hello!'));
      });

      test('method with expression as name', () {
        final result = interpreter.eval('''
          const prefix = "get";
          const obj = {
            [prefix + "Name"]() {
              return "John";
            }
          };
          obj.getName();
        ''');
        expect(result.toString(), equals('John'));
      });

      test('method with Symbol.iterator', () {
        interpreter.eval('''
          const obj = {
            [Symbol.iterator]() {
              let i = 0;
              return {
                next: () => {
                  if (i < 2) {
                    return { value: i++, done: false };
                  }
                  return { done: true };
                }
              };
            }
          };
        ''');

        final result = interpreter.eval('''
          const arr = [];
          for (const val of obj) {
            arr.push(val);
          }
          arr;
        ''');
        final arr = result as JSArray;
        expect(arr.elements.length, equals(2));
        expect(arr.elements[0].toNumber(), equals(0));
        expect(arr.elements[1].toNumber(), equals(1));
      });

      test('multiple methods with computed names', () {
        interpreter.eval('''
          const obj = {
            ["method" + "1"]() { return "first"; },
            ["method" + "2"]() { return "second"; }
          };
        ''');
        expect(interpreter.eval('obj.method1()').toString(), equals('first'));
        expect(interpreter.eval('obj.method2()').toString(), equals('second'));
      });

      test('method with parameters and computed name', () {
        final result = interpreter.eval('''
          const operation = "add";
          const obj = {
            [operation](a, b) {
              return a + b;
            }
          };
          obj.add(5, 3);
        ''');
        expect(result.toNumber(), equals(8));
      });
    });

    group('Complex Expressions', () {
      test('function call as property key', () {
        final result = interpreter.eval('''
          function getKey() {
            return "computedKey";
          }
          const obj = {
            [getKey()]: "value"
          };
          obj.computedKey;
        ''');
        expect(result.toString(), equals('value'));
      });

      test('ternary expression as property key', () {
        final result = interpreter.eval('''
          const flag = true;
          const obj = {
            [flag ? "keyA" : "keyB"]: "value"
          };
          obj.keyA;
        ''');
        expect(result.toString(), equals('value'));
      });

      test('template literal as property key', () {
        final result = interpreter.eval(r'''
          const prefix = "prop";
          const obj = {
            [`${prefix}Name`]: "value"
          };
          obj.propName;
        ''');
        expect(result.toString(), equals('value'));
      });

      test('array access as property key', () {
        final result = interpreter.eval('''
          const keys = ["first", "second"];
          const obj = {
            [keys[0]]: "value"
          };
          obj.first;
        ''');
        expect(result.toString(), equals('value'));
      });
    });

    group('Mixed Properties', () {
      test('mix of computed and normal properties', () {
        interpreter.eval('''
          const key = "dynamic";
          const obj = {
            normal: "value1",
            [key]: "value2",
            another: "value3",
            [key + "2"]: "value4"
          };
        ''');
        expect(interpreter.eval('obj.normal').toString(), equals('value1'));
        expect(interpreter.eval('obj.dynamic').toString(), equals('value2'));
        expect(interpreter.eval('obj.another').toString(), equals('value3'));
        expect(interpreter.eval('obj.dynamic2').toString(), equals('value4'));
      });

      test('mix of computed methods and normal methods', () {
        interpreter.eval('''
          const methodName = "computed";
          const obj = {
            normal() { return "normalMethod"; },
            [methodName]() { return "computedMethod"; }
          };
        ''');
        expect(
          interpreter.eval('obj.normal()').toString(),
          equals('normalMethod'),
        );
        expect(
          interpreter.eval('obj.computed()').toString(),
          equals('computedMethod'),
        );
      });

      test('computed property and method together', () {
        interpreter.eval('''
          const key = "data";
          const obj = {
            [key]: "value",
            [key + "Method"]() {
              return this[key];
            }
          };
        ''');
        expect(interpreter.eval('obj.data').toString(), equals('value'));
        expect(
          interpreter.eval('obj.dataMethod()').toString(),
          equals('value'),
        );
      });
    });

    group('Edge Cases', () {
      test('computed property key with side effects', () {
        final result = interpreter.eval('''
          let counter = 0;
          function getKey() {
            counter++;
            return "key" + counter;
          }
          const obj = {
            [getKey()]: "value1",
            [getKey()]: "value2"
          };
          [obj.key1, obj.key2, counter];
        ''');
        final arr = result as JSArray;
        expect(arr.elements[0].toString(), equals('value1'));
        expect(arr.elements[1].toString(), equals('value2'));
        expect(arr.elements[2].toNumber(), equals(2));
      });

      test('empty string as computed property key', () {
        final result = interpreter.eval('''
          const obj = {
            [""]: "emptyKey"
          };
          obj[""];
        ''');
        expect(result.toString(), equals('emptyKey'));
      });

      test('numeric computed property key', () {
        final result = interpreter.eval('''
          const obj = {
            [42]: "answer"
          };
          obj[42];
        ''');
        expect(result.toString(), equals('answer'));
      });

      test('computed property overwriting', () {
        final result = interpreter.eval('''
          const key = "prop";
          const obj = {
            [key]: "first",
            [key]: "second"
          };
          obj.prop;
        ''');
        expect(result.toString(), equals('second'));
      });
    });

    group('Integration with yield* delegation', () {
      test(
        'using computed property for Symbol.iterator in generator delegation',
        () {
          final result = interpreter.eval('''
          // Define a separate generator function
          function* iteratorGen() {
            yield 1;
            yield 2;
            yield 3;
          }
          
          const iterable = {
            [Symbol.iterator]: function() {
              return iteratorGen();
            }
          };
          
          function* gen() {
            yield* iterable;
            yield 4;
          }
          
          const results = [];
          const g = gen();
          let item;
          while (!(item = g.next()).done) {
            results.push(item.value);
          }
          results;
        ''');
          final arr = result as JSArray;
          expect(arr.elements.length, equals(4));
          expect(arr.elements[0].toNumber(), equals(1));
          expect(arr.elements[1].toNumber(), equals(2));
          expect(arr.elements[2].toNumber(), equals(3));
          expect(arr.elements[3].toNumber(), equals(4));
        },
      );
    });
  });
}
