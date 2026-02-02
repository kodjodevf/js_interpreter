import 'package:test/test.dart';
import 'package:js_interpreter/src/evaluator/evaluator.dart';

void main() {
  group('String Methods Complete Tests', () {
    test('string length property', () {
      const code = '''
        var str = "Hello World";
        str.length;
      ''';
      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('11'));
    });

    test('string charAt method', () {
      const code = '''
        var str = "JavaScript";
        str.charAt(0) + str.charAt(4) + str.charAt(100);
      ''';
      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('JS'));
    });

    test('string charCodeAt method', () {
      const code = '''
        var str = "ABC";
        str.charCodeAt(0);
      ''';
      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('65'));
    });

    test('string substring method', () {
      const code = '''
        var str = "Hello World";
        str.substring(0, 5) + "|" + str.substring(6);
      ''';
      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('Hello|World'));
    });

    test('string slice method', () {
      const code = '''
        var str = "Hello World";
        str.slice(0, 5) + "|" + str.slice(-5);
      ''';
      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('Hello|World'));
    });

    test('string indexOf and lastIndexOf', () {
      const code = '''
        var str = "Hello World Hello";
        var first = str.indexOf("Hello");
        var last = str.lastIndexOf("Hello");
        var notFound = str.indexOf("xyz");
        console.log("First:", first, "Last:", last, "Not found:", notFound);
        first + "," + last + "," + notFound;
      ''';
      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('0,12,-1'));
    });

    test('string toLowerCase and toUpperCase', () {
      const code = '''
        var str = "Hello World";
        str.toLowerCase() + "|" + str.toUpperCase();
      ''';
      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('hello world|HELLO WORLD'));
    });

    test('string split method', () {
      const code = '''
        var str = "a,b,c,d";
        var parts = str.split(",");
        console.log("Parts:", parts);
        parts.length;
      ''';
      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('4'));
    });

    test('string replace method', () {
      const code = '''
        var str = "Hello World Hello";
        str.replace("Hello", "Hi");
      ''';
      final result = JSEvaluator.evaluateString(code);
      expect(
        result.toString(),
        equals('Hi World Hello'),
      ); // Only the first occurrence
    });

    test('string includes method', () {
      const code = '''
        var str = "Hello World";
        var hasHello = str.includes("Hello");
        var hasXyz = str.includes("xyz");
        console.log("Has Hello:", hasHello, "Has xyz:", hasXyz);
        hasHello;
      ''';
      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('true'));
    });

    test('string startsWith and endsWith', () {
      const code = '''
        var str = "Hello World";
        var starts = str.startsWith("Hello");
        var ends = str.endsWith("World");
        console.log("Starts with Hello:", starts, "Ends with World:", ends);
        starts && ends;
      ''';
      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('true'));
    });

    test('string trim method', () {
      const code = '''
        var str = "   Hello World   ";
        var trimmed = str.trim();
        console.log("Original length:", str.length, "Trimmed length:", trimmed.length);
        trimmed;
      ''';
      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('Hello World'));
    });

    test('string repeat method', () {
      const code = '''
        var str = "Ha";
        str.repeat(3);
      ''';
      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('HaHaHa'));
    });

    test('complete string processing example', () {
      const code = '''
        function processEmail(email) {
          // Normaliser
          var cleaned = email.trim().toLowerCase();
          
          // Check basic format
          var atIndex = cleaned.indexOf("@");
          if (atIndex === -1) {
            return null;
          }
          
          // Extraire les parties
          var username = cleaned.substring(0, atIndex);
          var domain = cleaned.substring(atIndex + 1);
          
          // Checks
          var hasValidUsername = username.length > 0 && !username.includes("..");
          var hasValidDomain = domain.length > 0 && domain.includes(".");
          
          return {
            original: email,
            cleaned: cleaned,
            username: username,
            domain: domain,
            valid: hasValidUsername && hasValidDomain,
            info: {
              usernameLength: username.length,
              domainLength: domain.length,
              totalLength: cleaned.length
            }
          };
        }
        
        var result = processEmail("  John.Doe@Example.COM  ");
        console.log("Original:", result.original);
        console.log("Cleaned:", result.cleaned);
        console.log("Username:", result.username);
        console.log("Domain:", result.domain);
        console.log("Valid:", result.valid);
        console.log("Info:", result.info.usernameLength, result.info.domainLength);
        
        result.valid;
      ''';
      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('true'));
    });

    test('string chaining methods', () {
      const code = '''
        var text = "  Hello, World!  ";
        var processed = text
          .trim()
          .toLowerCase()
          .replace("world", "javascript")
          .toUpperCase();
        
        console.log("Result:", processed);
        processed;
      ''';
      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('HELLO, JAVASCRIPT!'));
    });

    test('string split with empty separator', () {
      const code = '''
        var str = "abc";
        var chars = str.split("");
        console.log("Characters:", chars);
        chars.length;
      ''';
      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('3'));
    });

    test('edge cases', () {
      const code = '''
        var empty = "";
        var results = {
          emptyLength: empty.length,
          emptyCharAt: empty.charAt(0),
          emptySubstring: empty.substring(0, 5),
          emptyIndexOf: empty.indexOf("x")
        };
        
        console.log("Empty string tests:", results.emptyLength, results.emptyCharAt, results.emptyIndexOf);
        results.emptyLength;
      ''';
      final result = JSEvaluator.evaluateString(code);
      expect(result.toString(), equals('0'));
    });
  });
}
