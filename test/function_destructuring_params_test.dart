import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('Function parameters with destructuring', () {
    test('simple object destructuring parameter', () {
      final js = JSInterpreter();
      expect(
        () => js.eval('''
        function greet({name, age}) {
          return name + ' is ' + age;
        }
        var result = greet({name: 'Alice', age: 30});
      '''),
        returnsNormally,
      );

      final result = js.eval('result');
      expect(result.toString(), equals('Alice is 30'));
    });

    test('object destructuring with default values', () {
      final js = JSInterpreter();
      expect(
        () => js.eval('''
        function configure({xmlMode = false, decodeEntities = true}) {
          return 'xmlMode: ' + xmlMode + ', decodeEntities: ' + decodeEntities;
        }
        var result = configure({xmlMode: true});
      '''),
        returnsNormally,
      );

      final result = js.eval('result');
      expect(result.toString(), equals('xmlMode: true, decodeEntities: true'));
    });

    test('mixed destructuring and regular parameters', () {
      final js = JSInterpreter();
      expect(
        () => js.eval('''
        function process({x, y}, callback) {
          return callback(x + y);
        }
        var result = process({x: 10, y: 20}, function(sum) { return sum * 2; });
      '''),
        returnsNormally,
      );

      final result = js.eval('result');
      expect(result.toNumber(), equals(60));
    });

    test('onstructor pattern', () {
      final js = JSInterpreter();
      expect(
        () => js.eval('''
        class Tokenizer {
          constructor({ xmlMode = false, decodeEntities = true, }, cbs) {
            this.xmlMode = xmlMode;
            this.decodeEntities = decodeEntities;
            this.cbs = cbs;
          }
        }
        var t = new Tokenizer({xmlMode: true}, 'callback');
      '''),
        returnsNormally,
      );

      final xmlMode = js.eval('t.xmlMode');
      expect(xmlMode.toString(), equals('true'));
    });
  });
}
