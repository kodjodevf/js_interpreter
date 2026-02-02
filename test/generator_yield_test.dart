import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Generator Yield Execution', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('should yield multiple values in sequence', () {
      final code = '''
        function* numbers() {
          yield 1;
          yield 2;
          yield 3;
        }
        
        const gen1 = numbers();
        const a = gen1.next();
        const b = gen1.next();
        const c = gen1.next();
        const d = gen1.next();
        
        [a.value, b.value, c.value, d.done];
      ''';

      var result = interpreter.eval(code);
      expect(result.toString(), equals('1,2,3,true'));
    });

    test('should preserve state between yields', () {
      final code = '''
        function* counter() {
          let count = 0;
          yield count++;
          yield count++;
          yield count++;
        }
        
        const genA = counter();
        const a1 = genA.next();
        const a2 = genA.next();
        const a3 = genA.next();
        
        [a1.value, a2.value, a3.value];
      ''';

      var result = interpreter.eval(code);
      expect(result.toString(), equals('0,1,2'));
    });
    test('should support return statement in generator', () {
      final code = '''
        function* genReturn1() {
          yield 1;
          return 42;
          yield 2; // unreachable
        }
        
        const gRet1 = genReturn1();
        const a = gRet1.next();
        a.value;
      ''';

      var result = interpreter.eval(code);
      expect(result.toString(), equals('1'));

      final code2 = '''
        function* genReturn2() {
          yield 1;
          return 42;
          yield 2; // unreachable
        }
        
        const gRet2 = genReturn2();
        gRet2.next();
        const b = gRet2.next();
        b.value;
      ''';

      result = interpreter.eval(code2);
      expect(result.toString(), equals('42'));
    });

    test('should yield inside if statement', () {
      final code = '''
        function* conditional(flag) {
          if (flag) {
            yield 'yes';
          } else {
            yield 'no';
          }
          yield 'done';
        }
        
        const g1 = conditional(true);
        g1.next().value;
      ''';

      var result = interpreter.eval(code);
      expect(result.toString(), equals('yes'));

      final code2 = '''
        function* conditional(flag) {
          if (flag) {
            yield 'yes';
          } else {
            yield 'no';
          }
          yield 'done';
        }
        
        const g2 = conditional(false);
        g2.next().value;
      ''';

      result = interpreter.eval(code2);
      expect(result.toString(), equals('no'));
    });

    test('should handle empty generator', () {
      final code = '''
        function* empty() {
          // no yield
        }
        
        const gen = empty();
        const r = gen.next();
        r.done;
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('true'));
    });

    test('should yield undefined when no argument', () {
      final code = '''
        function* genUndef() {
          yield;
          yield undefined;
        }
        
        const gU = genUndef();
        const a = gU.next();
        a.value === undefined;
      ''';

      final result = interpreter.eval(code);
      expect(result.toString(), equals('true'));
    });

    test('should handle expressions after yield', () {
      final code = '''
        function* math() {
          const a = yield 5;
          const b = a * 2;
          yield b;
          return b + 1;
        }
        
        const genM1 = math();
        genM1.next().value;
      ''';

      var result = interpreter.eval(code);
      expect(result.toString(), equals('5'));

      final code2 = '''
        const genM2 = math();
        genM2.next();      
        genM2.next(3).value;
      ''';

      result = interpreter.eval(code2);
      expect(result.toString(), equals('6'));
    });

    test('should support generator.return() method', () {
      final code = '''
        function* genRet() {
          yield 1;
          yield 2;
          yield 3;
        }
        
        const gR1 = genRet();
        gR1.next();
        const b = gR1['return'](99);
        b.value;
      ''';

      var result = interpreter.eval(code);
      expect(result.toString(), equals('99'));

      final code2 = '''
        const gR2 = genRet();
        gR2.next();
        gR2['return'](99);
        const c = gR2.next();
        c.done;
      ''';

      result = interpreter.eval(code2);
      expect(result.toString(), equals('true'));
    });
  });
}
