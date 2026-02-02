import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Complete Loop Support Summary', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('All loop types working', () {
      final result = interpreter.eval('''
        var result = {
          forLoop: 0,
          doWhile: 0,
          forIn: 0,
          forOf: 0,
          nestedWithLabels: 0
        };
        
        // Classic for loop
        for (var i = 1; i <= 3; i++) {
          result.forLoop += i;
        }
        
        // Do-while loop
        var j = 1;
        do {
          result.doWhile += j;
          j++;
        } while (j <= 3);
        
        // For-in loop
        var obj = {a: 10, b: 20, c: 30};
        for (var key in obj) {
          result.forIn += obj[key];
        }
        
        // For-of loop
        var arr = [100, 200, 300];
        for (var value of arr) {
          result.forOf += value;
        }
        
        // Nested loops with labels
        outer: for (var x = 1; x <= 3; x++) {
          for (var y = 1; y <= 3; y++) {
            result.nestedWithLabels += x * y;
            if (x === 2 && y === 2) break outer;
          }
        }
        
        result;
      ''');

      expect(result.type.name, equals('object'));

      // Check each loop type
      final obj = result.toObject();
      expect(obj.getProperty('forLoop').toNumber(), equals(6)); // 1+2+3
      expect(obj.getProperty('doWhile').toNumber(), equals(6)); // 1+2+3
      expect(obj.getProperty('forIn').toNumber(), equals(60)); // 10+20+30
      expect(obj.getProperty('forOf').toNumber(), equals(600)); // 100+200+300
      expect(
        obj.getProperty('nestedWithLabels').toNumber(),
        equals(12),
      ); // 1+2+3+2+4
    });

    test('Break and continue work in all loops', () {
      final result = interpreter.eval('''
        var breakTest = 0;
        var continueTest = 0;
        
        // Break test
        for (var i = 1; i <= 10; i++) {
          if (i > 5) break;
          breakTest += i;
        }
        
        // Continue test  
        for (var j = 1; j <= 5; j++) {
          if (j === 3) continue;
          continueTest += j;
        }
        
        ({breakTest: breakTest, continueTest: continueTest});
      ''');

      final obj = result.toObject();
      expect(obj.getProperty('breakTest').toNumber(), equals(15)); // 1+2+3+4+5
      expect(obj.getProperty('continueTest').toNumber(), equals(12)); // 1+2+4+5
    });

    test('Labeled break and continue work', () {
      final result = interpreter.eval('''
        var sum = 0;
        
        outer: for (var i = 1; i <= 5; i++) {
          inner: for (var j = 1; j <= 5; j++) {
            if (i * j === 6) continue outer;
            if (i * j > 10) break outer;
            sum += i * j;
          }
        }
        
        sum;
      ''');

      expect(
        result.toNumber(),
        equals(36),
      ); // Sum calculated manually: 1+2+3+4+5+2+4+3+4+8 = 36
    });
  });
}
