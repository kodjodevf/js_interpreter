import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('JavaScript Exceptions - Complete System', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('Basic throw/catch', () {
      test('simple throw string and catch', () {
        final result = interpreter.eval('''
          try {
            throw "test error";
          } catch (e) {
            return e;
          }
        ''');
        expect(result.toString(), equals("test error"));
      });

      test('throw number and catch', () {
        final result = interpreter.eval('''
          try {
            throw 42;
          } catch (e) {
            return e;
          }
        ''');
        expect(result.toString(), equals("42"));
      });

      test('throw object and catch', () {
        final result = interpreter.eval('''
          try {
            throw { message: "error object", code: 500 };
          } catch (e) {
            return e.message + ":" + e.code;
          }
        ''');
        expect(result.toString(), equals("error object:500"));
      });

      test('catch parameter scope', () {
        final result = interpreter.eval('''
          let e = "outer";
          try {
            throw "inner";
          } catch (e) {
            return e;
          }
          return e;
        ''');
        expect(result.toString(), equals("inner"));
      });

      test('catch without parameter', () {
        final result = interpreter.eval('''
          try {
            throw "error";
          } catch () {
            return "caught";
          }
        ''');
        expect(result.toString(), equals("caught"));
      });
    });

    group('try/catch/finally', () {
      test('finally always executes', () {
        final result = interpreter.eval('''
          let result = "";
          try {
            result += "try";
            throw "error";
          } catch (e) {
            result += "catch";
          } finally {
            result += "finally";
          }
          return result;
        ''');
        expect(result.toString(), equals("trycatchfinally"));
      });

      test('finally executes without exception', () {
        final result = interpreter.eval('''
          let result = "";
          try {
            result += "try";
          } finally {
            result += "finally";
          }
          return result;
        ''');
        expect(result.toString(), equals("tryfinally"));
      });

      test('finally executes when catch throws', () {
        expect(() {
          interpreter.eval('''
            let result = "";
            try {
              throw "first";
            } catch (e) {
              throw "second";
            } finally {
              result += "finally";
            }
          ''');
        }, throwsA(isA<JSException>()));
      });

      test('return in try/catch/finally', () {
        final result = interpreter.eval('''
          function test() {
            try {
              return "try";
            } catch (e) {
              return "catch";
            } finally {
              return "finally";
            }
          }
          return test();
        ''');
        expect(result.toString(), equals("finally"));
      });
    });

    group('nested try/catch', () {
      test('nested try/catch blocks', () {
        final result = interpreter.eval('''
          let result = "";
          try {
            result += "outer-try";
            try {
              result += "inner-try";
              throw "inner-error";
            } catch (e) {
              result += "inner-catch";
              throw "outer-error";
            }
          } catch (e) {
            result += "outer-catch";
          }
          return result;
        ''');
        expect(
          result.toString(),
          equals("outer-tryinner-tryinner-catchouter-catch"),
        );
      });

      test('exception propagation through multiple levels', () {
        final result = interpreter.eval('''
          function level3() {
            throw "deep error";
          }
          
          function level2() {
            return level3();
          }
          
          function level1() {
            try {
              return level2();
            } catch (e) {
              return "caught: " + e;
            }
          }
          
          return level1();
        ''');
        expect(result.toString(), equals("caught: deep error"));
      });
    });

    group('Error objects', () {
      test('throw Error object', () {
        final result = interpreter.eval('''
          try {
            let err = { name: "CustomError", message: "Something went wrong" };
            throw err;
          } catch (e) {
            return e.name + ": " + e.message;
          }
        ''');
        expect(result.toString(), equals("CustomError: Something went wrong"));
      });

      test('runtime errors as exceptions', () {
        final result = interpreter.eval('''
          try {
            null.property; // Doit lancer TypeError
          } catch (e) {
            return "caught runtime error";
          }
        ''');
        expect(result.toString(), equals("caught runtime error"));
      });
    });

    group('Control flow with exceptions', () {
      test('break/continue in try/catch', () {
        final result = interpreter.eval('''
          let result = "";
          for (let i = 0; i < 5; i++) {
            try {
              if (i === 2) throw "skip";
              if (i === 4) break;
              result += i;
            } catch (e) {
              result += "x";
            }
          }
          return result;
        ''');
        expect(result.toString(), equals("01x3"));
      });

      test('return in try block', () {
        final result = interpreter.eval('''
          function test() {
            try {
              return "from-try";
            } catch (e) {
              return "from-catch";
            }
            return "unreachable";
          }
          return test();
        ''');
        expect(result.toString(), equals("from-try"));
      });
    });

    group('Complex scenarios', () {
      test('exception in function call', () {
        final result = interpreter.eval('''
          function throwError() {
            throw "function error";
          }
          
          try {
            let result = throwError();
          } catch (e) {
            return "caught: " + e;
          }
        ''');
        expect(result.toString(), equals("caught: function error"));
      });

      test('multiple exceptions in sequence', () {
        final result = interpreter.eval('''
          let results = [];
          
          for (let i = 0; i < 3; i++) {
            try {
              throw "error-" + i;
            } catch (e) {
              results.push(e);
            }
          }
          
          return results.join(",");
        ''');
        expect(result.toString(), equals("error-0,error-1,error-2"));
      });

      test('exception in array operations', () {
        final result = interpreter.eval('''
          try {
            let arr = [1, 2, 3];
            arr.forEach(function(item) {
              if (item === 2) throw "stop at " + item;
            });
          } catch (e) {
            return e;
          }
        ''');
        expect(result.toString(), equals("stop at 2"));
      });
    });

    group('compatibility', () {
      test('try without catch but with finally', () {
        expect(() {
          interpreter.eval('''
            try {
              throw "error";
            } finally {
              // no catch block
            }
          ''');
        }, throwsA(isA<JSException>()));
      });

      test('empty catch block', () {
        final result = interpreter.eval('''
          try {
            throw "error";
          } catch (e) {
            // empty catch
          }
          return "after";
        ''');
        expect(result.toString(), equals("after"));
      });

      test('JavaScript standard error types', () {
        final result = interpreter.eval('''
          let results = [];
          
          // Test different error scenarios
          try {
            nonExistentVariable;
          } catch (e) {
            results.push("ReferenceError");
          }
          
          try {
            null.property;
          } catch (e) {
            results.push("TypeError");
          }
          
          return results.join(",");
        ''');
        expect(result.toString(), equals("ReferenceError,TypeError"));
      });
    });
  });
}
