import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('Class extends with member expression', () {
    test('extends module.ClassName', () {
      final js = JSInterpreter();
      expect(
        () => js.eval('''
        var module = {
          Base: class Base {
            constructor() {
              this.type = "base";
            }
          }
        };
        
        class Derived extends module.Base {
          constructor() {
            super();
            this.derivedType = "derived";
          }
        }
        
        var obj = new Derived();
      '''),
        returnsNormally,
      );

      final type = js.eval('obj.type');
      expect(type.toString(), equals('base'));
      final derivedType = js.eval('obj.derivedType');
      expect(derivedType.toString(), equals('derived'));
    });

    test('extends namespace.submodule.ClassName', () {
      final js = JSInterpreter();
      expect(
        () => js.eval('''
        var namespace = {
          submodule: {
            BaseClass: class BaseClass {
              getValue() { return 42; }
            }
          }
        };
        
        class MyClass extends namespace.submodule.BaseClass {
          getDoubleValue() { return this.getValue() * 2; }
        }
        
        var instance = new MyClass();
      '''),
        returnsNormally,
      );

      final result = js.eval('instance.getDoubleValue()');
      expect(result.toNumber(), equals(84));
    });
  });
}
