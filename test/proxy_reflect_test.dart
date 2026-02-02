import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Proxy and Reflect Implementation', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Proxy constructor creates proxy object', () {
      final result = interpreter.eval('''
        const target = { name: 'test' };
        const handler = {};
        const proxy = new Proxy(target, handler);
        proxy.name;
      ''');

      expect(result.toString(), equals('test'));
    });

    test('Proxy get trap works', () {
      final result = interpreter.eval('''
        const target = { name: 'original' };
        const handler = {
          get: function(target, property) {
            if (property === 'name') {
              return 'intercepted';
            }
            return target[property];
          }
        };
        const proxy = new Proxy(target, handler);
        proxy.name;
      ''');

      expect(result.toString(), equals('intercepted'));
    });

    test('Reflect.get works', () {
      final result = interpreter.eval('''
        const obj = { name: 'test' };
        Reflect.get(obj, 'name');
      ''');

      expect(result.toString(), equals('test'));
    });

    test('Reflect.set works', () {
      final result = interpreter.eval('''
        const obj = { name: 'original' };
        Reflect.set(obj, 'name', 'updated');
        obj.name;
      ''');

      expect(result.toString(), equals('updated'));
    });
  });
}
