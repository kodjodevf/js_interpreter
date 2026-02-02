import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('Object with numeric key and function array', () {
    test('Simple object with numeric key', () {
      final interpreter = JSInterpreter();

      final code = '''
        var obj = {1: "hello"};
        obj[1];
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('hello'));
    });

    test('Object with numeric key and array value', () {
      final interpreter = JSInterpreter();

      final code = '''
        var obj = {1: [function() { return 42; }]};
        obj[1][0]();
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(42));
    });

    test('Function call with object argument containing function', () {
      final interpreter = JSInterpreter();

      final code = '''
        function wrapper(funcs) {
          return funcs[1][0]('test');
        }
        
        var result = wrapper({1: [function(x) { return x + '!'; }]});
        result;
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('test!'));
    });

    test('IIFE with object argument', () {
      final interpreter = JSInterpreter();

      final code = '''
        (function(modules) {
          return modules[1][0]();
        })({1: [function() {
          'use strict';
          return 42;
        }]});
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(42));
    });

    test('Multi-line IIFE with object argument', () {
      final interpreter = JSInterpreter();

      final code = '''
        (function(modules) {
          return modules[1][0]();
        })({1: [function() {
          'use strict'
          
          var x = 10;
          return x * 2;
        }]});
      ''';

      final result = interpreter.eval(code);
      expect(result.toNumber(), equals(20));
    });

    test('Exact', () {
      final interpreter = JSInterpreter();

      final code = '''
        (function(){return (function(){
          function r(e,n,t){
            function o(i,f){
              if(!n[i]){
                var p=n[i]={exports:{}};
                e[i][0].call(p.exports,function(r){return o(r)},p,p.exports,r,e,n,t);
              }
              return n[i].exports;
            }
            return o;
          }
          return r;
        })()({1:[function(require,module,exports){
'use strict'

var x = 42;
}]})})();
      ''';

      expect(() => interpreter.eval(code), returnsNormally);
    });
  });
}
