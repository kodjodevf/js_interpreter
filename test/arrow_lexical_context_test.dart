import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('Arrow lexical context', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('arrow functions capture lexical this for direct body and eval', () {
      final result = interpreter.eval('''
        "use strict";
        function outer() {
          const direct = () => this;
          const viaEval = () => eval("this");
          return [direct(), viaEval()];
        }
        outer.call("this_val");
      ''');

      expect(result.toString(), equals('this_val,this_val'));
    });

    test('arrow functions capture lexical new.target', () {
      final result = interpreter.eval('''
        "use strict";
        function Outer() {
          const getNewTarget = () => eval("new.target");
          return getNewTarget() === Outer;
        }
        new Outer();
      ''');

      expect(result.toBoolean(), isTrue);
    });

    test('arrow functions preserve constructor identity for new.target', () {
      final result = interpreter.eval('''
        "use strict";
        function F() {
          return (() => eval("new.target"))();
        }
        new F() === F;
      ''');

      expect(result.toBoolean(), isTrue);
    });

    test('direct eval inside arrow can access lexical super', () {
      final result = interpreter.eval('''
        "use strict";
        const base = { f() { return this; } };
        const derived = {
          f() {
            return (() => eval("super.f()"))();
          }
        };
        derived.__proto__ = base;
        derived.f() === derived;
      ''');

      expect(result.toBoolean(), isTrue);
    });
  });
}
