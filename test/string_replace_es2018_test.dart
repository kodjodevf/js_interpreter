/// Test suite for ES2018 String.prototype.replace() enhancements
/// Tests full support for:
/// - Function callbacks with all parameters including groups
/// - Named group replacement syntax $&lt;name&gt;
/// - Numbered group replacement $1, $2, etc.
/// - Special replacement patterns $&, $`, $'
library;

import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  late JSInterpreter interpreter;

  setUp(() {
    interpreter = JSInterpreter();
  });

  group('ES2018 String.replace() - Named Group Syntax', () {
    test(r'should replace with $<name> syntax', () {
      const code = r'''
        const regex = /(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})/;
        const result = '2023-10-15'.replace(regex, '$<day>/$<month>/$<year>');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('15/10/2023'));
    });

    test('should replace multiple named groups', () {
      const code = r'''
        const regex = /(?<firstName>\w+) (?<lastName>\w+)/;
        const result = 'John Doe'.replace(regex, '$<lastName>, $<firstName>');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('Doe, John'));
    });

    test('should handle named groups with underscores', () {
      const code = r'''
        const regex = /(?<first_name>\w+) (?<last_name>\w+)/;
        const result = 'Jane Smith'.replace(regex, '$<last_name>, $<first_name>');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('Smith, Jane'));
    });

    test('should handle named groups with numbers', () {
      const code = r'''
        const regex = /(?<group1>\d+)-(?<group2>\d+)/;
        const result = '123-456'.replace(regex, '$<group2>:$<group1>');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('456:123'));
    });

    test('should handle undefined named groups', () {
      const code = r'''
        const regex = /(?<num>\d+)|(?<word>[a-z]+)/;
        const result1 = '123'.replace(regex, 'num=$<num> word=$<word>');
        const result2 = 'abc'.replace(regex, 'num=$<num> word=$<word>');
        result1 + ' | ' + result2;
      ''';
      final result = interpreter.eval(code);
      // Unmatched groups should be replaced with empty string in replacement pattern
      expect(result.toString(), equals('num=123 word= | num= word=abc'));
    });
  });

  group('ES2018 String.replace() - Function Callbacks', () {
    test('should call function with match and offset', () {
      const code = '''
        const regex = /\\d+/;
        let capturedOffset;
        let capturedString;
        const result = 'abc123def'.replace(regex, function(match, offset, string) {
          capturedOffset = offset;
          capturedString = string;
          return '[' + match + ']';
        });
        result + '|' + capturedOffset + '|' + capturedString;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('abc[123]def|3|abc123def'));
    });

    test('should call function with captured groups', () {
      const code = r'''
        const regex = /(\w+)@(\w+)\.(\w+)/;
        const result = 'user@example.com'.replace(regex, function(match, p1, p2, p3, offset, string) {
          return p1 + ' AT ' + p2 + ' DOT ' + p3;
        });
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('user AT example DOT com'));
    });

    test('should call function with groups object (ES2018)', () {
      const code = '''
        const regex = /(?<firstName>\\w+) (?<lastName>\\w+)/;
        const result = 'John Doe'.replace(regex, function(match, p1, p2, offset, string, groups) {
          return groups.lastName + ', ' + groups.firstName;
        });
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('Doe, John'));
    });

    test('should call function multiple times with global flag', () {
      const code = r'''
        const regex = /\d+/g;
        let count = 0;
        const result = '10 + 20 = 30'.replace(regex, function(match) {
          count++;
          return '[' + match + ']';
        });
        result + ' count=' + count;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('[10] + [20] = [30] count=3'));
    });

    test('should transform with function using named groups', () {
      const code = '''
        const regex = /(?<value>\\d+)(?<unit>px|em|rem)/g;
        const result = 'font-size: 16px; margin: 2em; padding: 1rem'.replace(regex, function(match, p1, p2, offset, string, groups) {
          const num = parseInt(groups.value);
          return (num * 2) + groups.unit;
        });
        result;
      ''';
      final result = interpreter.eval(code);
      expect(
        result.toString(),
        equals('font-size: 32px; margin: 4em; padding: 2rem'),
      );
    });

    test('should handle empty groups in callback', () {
      const code = r'''
        const regex = /(?<required>\w+)(?<optional>\d*)/;
        const result = 'test'.replace(regex, function(match, p1, p2, offset, string, groups) {
          return groups.required + ':' + (groups.optional || 'none');
        });
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('test:none'));
    });
  });

  group('ES2018 String.replace() - Numbered Groups', () {
    test(r'should replace with $1, $2 syntax', () {
      const code = r'''
        const regex = /(\w+)@(\w+)\.(\w+)/;
        const result = 'user@example.com'.replace(regex, '$1 at $2 dot $3');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('user at example dot com'));
    });

    test('should replace with two-digit group numbers', () {
      const code = r'''
        const regex = /(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)/;
        const result = '12345678901'.replace(regex, '$11-$10-$9-$1');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('1-0-9-1'));
    });

    test('should handle invalid group numbers', () {
      const code = r'''
        const regex = /(\w+)/;
        const result = 'test'.replace(regex, '$1 $2 $99');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals(r'test $2 $99'));
    });

    test('should mix numbered and named groups', () {
      const code = r'''
        const regex = /(?<name>[a-z]+)(\d+)/;
        const result = 'test123'.replace(regex, 'name=$<name> num=$2');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('name=test num=123'));
    });
  });

  group('ES2018 String.replace() - Special Patterns', () {
    test(r'should replace with $& (full match)', () {
      const code = r'''
        const regex = /\d+/;
        const result = 'abc123def'.replace(regex, '[$&]');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('abc[123]def'));
    });

    test(r'should replace with $` (before match)', () {
      const code = r'''
        const regex = /\d+/;
        const result = 'abc123def'.replace(regex, '[$`]');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('abc[abc]def'));
    });

    test("should replace with \$' (after match)", () {
      const code = r'''
        const regex = /\d+/;
        const result = 'abc123def'.replace(regex, "[$']");
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('abc[def]def'));
    });

    test(r'should escape $$ as single $', () {
      const code = r'''
        const regex = /\d+/;
        const result = 'Price: 123'.replace(regex, '$$$$1');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('Price: \$\$1'));
    });

    test('should combine multiple special patterns', () {
      const code = r'''
        const regex = /\d+/;
        const result = 'abc123def'.replace(regex, '$`-$&-$' + "'" + '');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('abcabc-123-defdef'));
    });
  });

  group('ES2018 String.replace() - Complex Scenarios', () {
    test('should format phone numbers', () {
      const code = r'''
        const regex = /(?<area>\d{3})(?<prefix>\d{3})(?<line>\d{4})/;
        const result = '5551234567'.replace(regex, '($<area>) $<prefix>-$<line>');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('(555) 123-4567'));
    });

    test('should convert date formats', () {
      const code = r'''
        const regex = /(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})/g;
        const result = 'Dates: 2023-10-15 and 2024-01-20'.replace(regex, '$<month>/$<day>/$<year>');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('Dates: 10/15/2023 and 01/20/2024'));
    });

    test('should sanitize HTML with callback', () {
      const code = '''
        const regex = /(?<tag><[^>]+>)/g;
        const result = 'Hello <b>world</b>!'.replace(regex, function(match, p1, offset, string, groups) {
          return '[TAG]';
        });
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('Hello [TAG]world[TAG]!'));
    });

    test('should parse and transform URLs', () {
      const code = r'''
        const regex = /(?<protocol>https?):\/\/(?<domain>[^\/]+)(?<path>\/.*)?/;
        const result = 'Visit https://example.com/page'.replace(regex, 
          'Protocol: $<protocol>, Domain: $<domain>, Path: $<path>');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(
        result.toString(),
        equals('Visit Protocol: https, Domain: example.com, Path: /page'),
      );
    });

    test('should capitalize with callback and groups', () {
      const code = '''
        const regex = /(?<word>\\b\\w+\\b)/g;
        const result = 'hello world from javascript'.replace(regex, function(match, p1, offset, string, groups) {
          const word = groups.word;
          return word.charAt(0).toUpperCase() + word.slice(1);
        });
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('Hello World From Javascript'));
    });

    test('should handle nested replacements', () {
      const code = r'''
        const regex1 = /(?<inner>\d+)/g;
        const regex2 = /\[(\d+)\]/g;
        let result = 'Values: 10, 20, 30'.replace(regex1, '[$<inner>]');
        result = result.replace(regex2, '($1)');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('Values: (10), (20), (30)'));
    });
  });

  group('ES2018 String.replace() - Edge Cases', () {
    test('should handle string search with function', () {
      const code = '''
        let callCount = 0;
        const result = 'hello world hello'.replace('hello', function(match, offset, string) {
          callCount++;
          return 'HI';
        });
        result + ' calls=' + callCount;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('HI world hello calls=1'));
    });

    test('should handle empty named group capture', () {
      const code = r'''
        const regex = /(?<text>\w*)x/;
        const result = 'x test'.replace(regex, 'text=[$<text>]');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('text=[] test'));
    });

    test('should handle groups object without named groups', () {
      const code = r'''
        const regex = /(\d+)/;
        const result = '123'.replace(regex, function(match, p1, offset, string, groups) {
          return 'hasGroups=' + (typeof groups === 'object');
        });
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('hasGroups=true'));
    });

    test('should preserve non-matching named group syntax', () {
      const code = r'''
        const regex = /\d+/;
        const result = '123'.replace(regex, '$<nonexistent>');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals(''));
    });

    test('should handle replacement function returning non-string', () {
      const code = '''
        const regex = /\\d+/;
        const result = 'Value: 42'.replace(regex, function(match) {
          return 99;
        });
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('Value: 99'));
    });

    test('should handle unicode in named groups', () {
      const code = r'''
        const regex = /(?<emoji>😀)/;
        const result = 'Hello 😀 World'.replace(regex, '[$<emoji>]');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('Hello [😀] World'));
    });
  });

  group('ES2018 String.replace() - Practical Examples', () {
    test('should mask credit card numbers', () {
      const code = r'''
        const regex = /(?<first>\d{4})(?<middle>\d{4})(?<third>\d{4})(?<last>\d{4})/;
        const result = '1234567890123456'.replace(regex, '****-****-****-$<last>');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('****-****-****-3456'));
    });

    test('should convert snake_case to camelCase', () {
      const code = '''
        const regex = /_(?<letter>[a-z])/g;
        const result = 'hello_world_from_javascript'.replace(regex, function(match, p1, offset, string, groups) {
          return groups.letter.toUpperCase();
        });
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('helloWorldFromJavascript'));
    });

    test('should parse CSV with named groups', () {
      const code = r'''
        const regex = /(?<name>[^,]+),(?<age>\d+),(?<city>[^,]+)/;
        const result = 'John,30,NYC'.replace(regex, 'Name: $<name>, Age: $<age>, City: $<city>');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('Name: John, Age: 30, City: NYC'));
    });

    test('should extract and format markdown links', () {
      const code = r'''
        const regex = /\[(?<text>[^\]]+)\]\((?<url>[^\)]+)\)/g;
        const result = 'Check [Google](https://google.com) and [MDN](https://mdn.com)'.replace(
          regex, '<a href="$<url>">$<text></a>');
        result;
      ''';
      final result = interpreter.eval(code);
      expect(
        result.toString(),
        equals(
          'Check <a href="https://google.com">Google</a> and <a href="https://mdn.com">MDN</a>',
        ),
      );
    });

    test('should normalize whitespace with callback', () {
      const code = r'''
        const regex = /\s+/g;
        const result = 'Hello    world  \n  from   JS'.replace(regex, function(match) {
          return ' ';
        });
        result;
      ''';
      final result = interpreter.eval(code);
      expect(result.toString(), equals('Hello world from JS'));
    });
  });
}
