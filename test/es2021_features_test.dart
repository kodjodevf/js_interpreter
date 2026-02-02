import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });

  group('ES2021 String.prototype.replaceAll()', () {
    test('replaceAll with string pattern and string replacement', () {
      final result = interpreter.eval('''
        const str = "hello world, hello universe";
        str.replaceAll("hello", "goodbye");
      ''');
      expect(result.toString(), 'goodbye world, goodbye universe');
    });

    test('replaceAll with empty string', () {
      final result = interpreter.eval('''
        "test".replaceAll("", "-");
      ''');
      expect(result.toString(), '-t-e-s-t-');
    });

    test('replaceAll with regex pattern (with global flag)', () {
      final result = interpreter.eval('''
        const str = "foo1 bar2 baz3";
        str.replaceAll(/\\d/g, "X");
      ''');
      expect(result.toString(), 'fooX barX bazX');
    });

    test('replaceAll with regex without global flag throws error', () {
      expect(
        () => interpreter.eval('''
          "test".replaceAll(/t/, "x");
        '''),
        throwsA(isA<JSException>()),
      );
    });

    test('replaceAll with no matches returns original string', () {
      final result = interpreter.eval('''
        "hello".replaceAll("xyz", "abc");
      ''');
      expect(result.toString(), 'hello');
    });

    test('replaceAll with case-sensitive pattern', () {
      final result = interpreter.eval('''
        "Hello HELLO hello".replaceAll("hello", "hi");
      ''');
      expect(result.toString(), 'Hello HELLO hi');
    });

    test('replaceAll with special characters', () {
      final result = interpreter.eval('''
        "a.b.c".replaceAll(".", "-");
      ''');
      expect(result.toString(), 'a-b-c');
    });

    test('replaceAll replaces all occurrences, not just first', () {
      final result = interpreter.eval('''
        const count = "aaa".replaceAll("a", "b");
        count;
      ''');
      expect(result.toString(), 'bbb');
    });
  });

  group('ES2021 Logical Assignment Operators', () {
    test('&&= (AND assignment) - assigns if left is truthy', () {
      final result = interpreter.eval('''
        let x = 1;
        x &&= 2;
        x;
      ''');
      expect(result.toNumber(), 2);
    });

    test('&&= (AND assignment) - does not assign if left is falsy', () {
      final result = interpreter.eval('''
        let x = 0;
        x &&= 2;
        x;
      ''');
      expect(result.toNumber(), 0);
    });

    test('&&= (AND assignment) - with object property', () {
      final result = interpreter.eval('''
        const obj = { a: 1 };
        obj.a &&= 42;
        obj.a;
      ''');
      expect(result.toNumber(), 42);
    });

    test('||= (OR assignment) - assigns if left is falsy', () {
      final result = interpreter.eval('''
        let x = 0;
        x ||= 42;
        x;
      ''');
      expect(result.toNumber(), 42);
    });

    test('||= (OR assignment) - does not assign if left is truthy', () {
      final result = interpreter.eval('''
        let x = 1;
        x ||= 42;
        x;
      ''');
      expect(result.toNumber(), 1);
    });

    test('||= (OR assignment) - with object property', () {
      final result = interpreter.eval('''
        const obj = {};
        obj.a ||= 10;
        obj.a;
      ''');
      expect(result.toNumber(), 10);
    });

    test('??= (Nullish coalescing assignment) - assigns if left is null', () {
      final result = interpreter.eval('''
        let x = null;
        x ??= 42;
        x;
      ''');
      expect(result.toNumber(), 42);
    });

    test(
      '??= (Nullish coalescing assignment) - assigns if left is undefined',
      () {
        final result = interpreter.eval('''
        let x;
        x ??= 42;
        x;
      ''');
        expect(result.toNumber(), 42);
      },
    );

    test(
      '??= (Nullish coalescing assignment) - does not assign if left is 0 (falsy but not nullish)',
      () {
        final result = interpreter.eval('''
        let x = 0;
        x ??= 42;
        x;
      ''');
        expect(result.toNumber(), 0);
      },
    );

    test(
      '??= (Nullish coalescing assignment) - does not assign if left is empty string',
      () {
        final result = interpreter.eval('''
        let x = "";
        x ??= "default";
        x;
      ''');
        expect(result.toString(), '');
      },
    );

    test('??= (Nullish coalescing assignment) - with object property', () {
      final result = interpreter.eval('''
        const obj = { a: undefined };
        obj.a ??= 100;
        obj.a;
      ''');
      expect(result.toNumber(), 100);
    });

    test('Logical assignment operators - short-circuit evaluation', () {
      final result = interpreter.eval('''
        let count = 0;
        function increment() { count++; return 10; }
        
        let a = 0;
        a &&= increment(); // Should not call increment because a is falsy
        
        let b = 1;
        b ||= increment(); // Should not call increment because b is truthy
        
        let c = null;
        c ??= increment(); // Should call increment because c is nullish
        
        count; // Should be 1
      ''');
      expect(result.toNumber(), 1);
    });
  });

  group('ES2021 Numeric Separators', () {
    test('Numeric separator in decimal number', () {
      final result = interpreter.eval('1_000_000');
      expect(result.toNumber(), 1000000);
    });

    test('Numeric separator with multiple underscores', () {
      final result = interpreter.eval('1_2_3_4_5');
      expect(result.toNumber(), 12345);
    });

    test('Numeric separator in decimal fraction', () {
      final result = interpreter.eval('0.000_001');
      expect(result.toNumber(), 0.000001);
    });

    test('Numeric separator in hexadecimal', () {
      final result = interpreter.eval('0xFF_FF_FF');
      expect(result.toNumber(), 0xFFFFFF);
    });

    test('Numeric separator in binary', () {
      final result = interpreter.eval('0b1010_1010');
      expect(result.toNumber(), 170); // 0b10101010 = 170
    });

    test('Numeric separator in octal', () {
      final result = interpreter.eval('0o7_7_7');
      expect(result.toNumber(), 511); // 0o777 = 511
    });

    test('Numeric separator in exponential notation', () {
      final result = interpreter.eval('1_000e3');
      expect(result.toNumber(), 1000000);
    });

    test('Numeric separator with BigInt', () {
      final result = interpreter.eval('1_000_000_000_000n');
      expect(result.isBigInt, isTrue);
      expect(
        result.toString(),
        '1000000000000n',
      ); // BigInt toString includes 'n'
    });

    test('Numeric separators in arithmetic', () {
      final result = interpreter.eval('1_000 + 2_000');
      expect(result.toNumber(), 3000);
    });
  });

  group('ES2021 Promise.any()', () {
    test('Promise.any resolves with first fulfilled promise', () async {
      final result = await interpreter.evalAsync('''
        Promise.any([
          Promise.reject("Error 1"),
          Promise.resolve(42),
          Promise.resolve(100)
        ])
      ''');
      expect(result.toNumber(), 42);
    });

    test(
      'Promise.any resolves with first fulfilled even if others reject later',
      () async {
        final result = await interpreter.evalAsync('''
        Promise.any([
          new Promise((resolve) => setTimeout(() => resolve(1), 100)),
          Promise.resolve(42),
          Promise.reject("Error")
        ])
      ''');
        expect(result.toNumber(), 42);
      },
    );

    test(
      'Promise.any rejects with AggregateError if all promises reject',
      () async {
        final result = await interpreter.evalAsync('''
        Promise.any([
          Promise.reject("Error 1"),
          Promise.reject("Error 2"),
          Promise.reject("Error 3")
        ]).then(null, e => e.name)
      ''');
        expect(result.toString(), 'AggregateError');
      },
    );

    test('Promise.any with empty array rejects with AggregateError', () async {
      final result = await interpreter.evalAsync('''
        Promise.any([]).then(null, e => e.name)
      ''');
      expect(result.toString(), 'AggregateError');
    });

    test('Promise.any with non-promise values resolves immediately', () async {
      final result = await interpreter.evalAsync('''
        Promise.any([1, 2, 3])
      ''');
      expect(result.toNumber(), 1);
    });

    test('Promise.any with mix of promises and values', () async {
      final result = await interpreter.evalAsync('''
        Promise.any([
          Promise.reject("Error"),
          42,
          Promise.resolve(100)
        ])
      ''');
      expect(result.toNumber(), 42);
    });
  });

  group('ES2021 AggregateError', () {
    test('AggregateError constructor with array of errors', () {
      final result = interpreter.eval('''
        const error = new AggregateError(
          [new Error("Error 1"), new Error("Error 2")],
          "Multiple errors occurred"
        );
        error.name;
      ''');
      expect(result.toString(), 'AggregateError');
    });

    test('AggregateError has errors property', () {
      final result = interpreter.eval('''
        const error = new AggregateError(
          ["Error 1", "Error 2", "Error 3"],
          "Test error"
        );
        error.errors.length;
      ''');
      expect(result.toNumber(), 3);
    });

    test('AggregateError has message property', () {
      final result = interpreter.eval('''
        const error = new AggregateError([], "Custom message");
        error.message;
      ''');
      expect(result.toString(), 'Custom message');
    });

    test('AggregateError with default message', () {
      final result = interpreter.eval('''
        const error = new AggregateError([]);
        error.message;
      ''');
      expect(result.toString(), 'All promises were rejected');
    });

    test('AggregateError errors can be accessed', () {
      final result = interpreter.eval('''
        const error = new AggregateError(
          ["First", "Second", "Third"]
        );
        error.errors[1];
      ''');
      expect(result.toString(), 'Second');
    });

    test('AggregateError can be thrown and caught', () {
      final result = interpreter.eval('''
        try {
          throw new AggregateError(["e1", "e2"], "Test");
        } catch (e) {
          e.name + ": " + e.message;
        }
      ''');
      expect(result.toString(), 'AggregateError: Test');
    });
  });

  group('ES2021 Integration Tests', () {
    test('Complete example with multiple ES2021 features', () async {
      final result = await interpreter.evalAsync('''
        // Numeric separators
        const largeNumber = 1_000_000;
        
        // Logical assignment
        let config = null;
        config ??= { timeout: 30_000 };
        
        // String.prototype.replaceAll
        const text = "foo foo foo";
        const replaced = text.replaceAll("foo", "bar");
        
        // Promise.any
        const fastest = await Promise.any([
          Promise.reject("slow"),
          Promise.resolve(config.timeout),
          Promise.resolve(largeNumber)
        ]);
        
        fastest;
      ''');
      expect(result.toNumber(), 30000);
    });

    test('Error handling with AggregateError', () async {
      final result = await interpreter.evalAsync('''
        Promise.any([
          Promise.reject("DB error"),
          Promise.reject("API error"),
          Promise.reject("Network error")
        ]).then(null, e => e.errors.length + " errors caught")
      ''');
      expect(result.toString(), '3 errors caught');
    });

    test('Logical assignment with numeric separators', () {
      final result = interpreter.eval('''
        let budget = 0;
        budget ||= 100_000;
        
        let spent = 50_000;
        let remaining = budget - spent;
        remaining;
      ''');
      expect(result.toNumber(), 50000);
    });
  });
}
