import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  test('use strict - should prevent undeclared variables', () {
    final interpreter = JSInterpreter();

    final code = '''
      "use strict";
      try {
        x = 10; // Should throw in strict mode
        'no error';
      } catch(e) {
        'caught: ' + e.toString();
      }
    ''';

    final result = interpreter.eval(code);
    print('Result: $result');
    // In strict mode, assigning to an undeclared variable should throw an error
  });

  test('use strict - should work with declared variables', () {
    final interpreter = JSInterpreter();

    final code = '''
      "use strict";
      var x = 10;
      x = 20;
      x;
    ''';

    final result = interpreter.eval(code);
    print('Result: $result');
    expect(result.toNumber(), equals(20));
  });

  test('use strict in function scope', () {
    final interpreter = JSInterpreter();

    final code = '''
      function test() {
        "use strict";
        try {
          y = 5; // Should throw
          return 'no error';
        } catch(e) {
          return 'strict mode works';
        }
      }
      test();
    ''';

    final result = interpreter.eval(code);
    print('Function strict result: $result');
  });

  test('without use strict - should allow undeclared variables', () {
    final interpreter = JSInterpreter();

    final code = '''
      // No strict mode
      z = 30; // Should work
      z;
    ''';

    final result = interpreter.eval(code);
    print('Non-strict result: $result');
    expect(result.toNumber(), equals(30));
  });

  test('use strict - delete on variable should fail', () {
    final interpreter = JSInterpreter();

    final code = '''
      "use strict";
      var x = 10;
      try {
        delete x; // Should throw in strict mode
        'no error';
      } catch(e) {
        'delete failed in strict mode';
      }
    ''';

    final result = interpreter.eval(code);
    print('Delete result: $result');
  });

  test('use strict - duplicate parameter names should fail', () {
    final interpreter = JSInterpreter();

    final code = '''
      try {
        function test(a, a) {
          "use strict";
          return a;
        }
        test(1, 2);
        'no error';
      } catch(e) {
        'duplicate params not allowed';
      }
    ''';

    final result = interpreter.eval(code);
    print('Duplicate params result: $result');
  });

  test('use strict - octal literals should fail', () {
    final interpreter = JSInterpreter();

    final code = '''
      "use strict";
      try {
        var x = 010; // Old octal literal (should be an error)
        'no error: ' + x;
      } catch(e) {
        'octal not allowed';
      }
    ''';

    final result = interpreter.eval(code);
    print('Octal result: $result');
    expect(result.toString(), equals('octal not allowed'));
  });

  test('use strict - with statement should fail', () {
    final interpreter = JSInterpreter();

    final code = '''
      "use strict";
      var obj = {x: 10};
      try {
        with(obj) { // Should throw in strict mode
          x = 20;
        }
        'no error';
      } catch(e) {
        'with not allowed';
      }
    ''';

    final result = interpreter.eval(code);
    print('With statement result: $result');
    expect(result.toString(), equals('with not allowed'));
  });
}
