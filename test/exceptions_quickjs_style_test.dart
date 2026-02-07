import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('JavaScript Exceptions', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('exception handling pattern', () {
      final result = interpreter.eval('''
        (function() {
          function safeOperation(operation) {
            try {
              return { success: true, result: operation() };
            } catch (e) {
              return { success: false, error: e };
            }
          }
          
          function riskyOperation() {
            throw "Something went wrong";
          }
          
          let result1 = safeOperation(() => 42);
          let result2 = safeOperation(riskyOperation);
          
          return result1.success + ":" + result1.result + "|" + 
                 result2.success + ":" + result2.error;
        })()
      ''');
      expect(result.toString(), equals('true:42|false:Something went wrong'));
    });

    test('Exception propagation', () {
      final result = interpreter.eval('''
        (function() {
          function level1() {
            throw { name: "CustomError", message: "Deep error" };
          }
          
          function level2() {
            return level1();
          }
          
          function level3() {
            return level2();
          }
          
          try {
            level3();
          } catch (e) {
            return e.name + ": " + e.message;
          }
        })()
      ''');
      expect(result.toString(), equals('CustomError: Deep error'));
    });

    test('Complex finally semantics', () {
      final result = interpreter.eval('''
        (function() {
          function complexFinally() {
            let steps = [];
            
            try {
              steps.push("try");
              throw "error1";
            } catch (e) {
              steps.push("catch");
              throw "error2";
            } finally {
              steps.push("finally");
            }
            
            return steps;
          }
          
          try {
            complexFinally();
          } catch (e) {
            return "final error: " + e;
          }
        })()
      ''');
      expect(result.toString(), contains('error2'));
    });

    test('Exception scope and variable binding', () {
      final result = interpreter.eval('''
        (function() {
          let outer = "outer";
          let results = [];
          
          try {
            throw { type: "TestError", outer: outer };
          } catch (e) {
            results.push(e.type);
            results.push(e.outer);
            
            // Variable 'e' est locale au catch block
            let e2 = "local";
            results.push(e2);
          }
          
          results.push(outer); // outer est toujours accessible
          return results.join(",");
        })()
      ''');
      expect(result.toString(), equals('TestError,outer,local,outer'));
    });

    test('try/catch in loops and control flow', () {
      final result = interpreter.eval('''
        (function() {
          let results = [];
          
          for (let i = 0; i < 5; i++) {
            try {
              if (i === 2) throw "skip-" + i;
              if (i === 4) break;
              results.push("ok-" + i);
            } catch (e) {
              results.push("caught-" + i);
              continue;
            }
          }
          
          return results.join(",");
        })()
      ''');
      expect(result.toString(), equals('ok-0,ok-1,caught-2,ok-3'));
    });

    test('runtime error conversion to exceptions', () {
      final result = interpreter.eval('''
        (function() {
          let errors = [];
          
          // Test TypeError
          try {
            null.property;
          } catch (e) {
            errors.push("TypeError");
          }
          
          // Test ReferenceError
          try {
            undefinedVariable;
          } catch (e) {
            errors.push("ReferenceError");
          }
          
          // Test custom throw
          try {
            throw "CustomError";
          } catch (e) {
            errors.push("Custom");
          }
          
          return errors.join(",");
        })()
      ''');
      expect(result.toString(), equals('TypeError,ReferenceError,Custom'));
    });
  });
}
