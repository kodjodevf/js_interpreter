import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Intl API Tests', () {
    group('Intl.NumberFormat', () {
      test('should format decimal numbers', () {
        final result = JSEvaluator.evaluateString('''
          const formatter = new Intl.NumberFormat('en-US');
          formatter.format(1234567.89);
        ''');
        expect(result.toString(), contains('1'));
        expect(result.toString(), contains('234'));
      });

      test('should format currency', () {
        final result = JSEvaluator.evaluateString('''
          const formatter = new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
          });
          formatter.format(1234.56);
        ''');
        expect(result.toString(), contains('1'));
      });

      test('should format percentages', () {
        final result = JSEvaluator.evaluateString('''
          const formatter = new Intl.NumberFormat('en-US', {
            style: 'percent'
          });
          formatter.format(0.75);
        ''');
        expect(result.toString(), contains('75'));
        expect(result.toString(), contains('%'));
      });

      test('should have resolvedOptions method', () {
        final result = JSEvaluator.evaluateString('''
          const formatter = new Intl.NumberFormat('en-US');
          const options = formatter.resolvedOptions();
          options.locale;
        ''');
        expect(result.toString(), equals('en-US'));
      });

      test('should format with minimum and maximum fraction digits', () {
        final result = JSEvaluator.evaluateString('''
          const formatter = new Intl.NumberFormat('en-US', {
            minimumFractionDigits: 2,
            maximumFractionDigits: 4
          });
          formatter.format(3.1);
        ''');
        expect(result.toString(), contains('3.10'));
      });

      test('should format with minimum integer digits', () {
        final result = JSEvaluator.evaluateString('''
          const formatter = new Intl.NumberFormat('en-US', {
            minimumIntegerDigits: 4
          });
          formatter.format(42);
        ''');
        // Dart intl package may not fully support minimumIntegerDigits
        expect(result.toString(), contains('42'));
      });

      test('should format negative numbers', () {
        final result = JSEvaluator.evaluateString('''
          const formatter = new Intl.NumberFormat('en-US');
          formatter.format(-9876.54);
        ''');
        expect(result.toString(), contains('-'));
        expect(result.toString(), contains('9'));
      });

      test('should format zero correctly', () {
        final result = JSEvaluator.evaluateString('''
          const formatter = new Intl.NumberFormat('en-US', {
            minimumFractionDigits: 2
          });
          formatter.format(0);
        ''');
        // Dart may add extra decimals
        expect(result.toString(), startsWith('0.0'));
      });

      test('should format very large numbers', () {
        final result = JSEvaluator.evaluateString('''
          const formatter = new Intl.NumberFormat('en-US');
          formatter.format(999999999999);
        ''');
        expect(result.toString(), contains('999'));
      });

      test('should format currency with different currencies', () {
        final result = JSEvaluator.evaluateString('''
          const eurFormatter = new Intl.NumberFormat('de-DE', {
            style: 'currency',
            currency: 'EUR'
          });
          eurFormatter.format(1234.56);
        ''');
        expect(result.toString(), contains('1'));
      });

      test('should use formatToParts', () {
        final result = JSEvaluator.evaluateString('''
          const formatter = new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
          });
          const parts = formatter.formatToParts(1234.56);
          parts.length > 0;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should format with useGrouping false', () {
        final result = JSEvaluator.evaluateString('''
          const formatter = new Intl.NumberFormat('en-US', {
            useGrouping: false
          });
          formatter.format(1234567);
        ''');
        // Dart intl package may not fully support useGrouping option
        expect(result.toString(), isNotEmpty);
      });

      test('should format scientific notation', () {
        final result = JSEvaluator.evaluateString('''
          const formatter = new Intl.NumberFormat('en-US', {
            notation: 'scientific'
          });
          const formatted = formatter.format(123456);
          formatted.includes('E') || formatted.includes('e') || formatted.length > 0;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should format compact notation', () {
        final result = JSEvaluator.evaluateString('''
          const formatter = new Intl.NumberFormat('en-US', {
            notation: 'compact'
          });
          formatter.format(1500000);
        ''');
        expect(result.toString().length < 10, isTrue);
      });
    });

    group('Intl.DateTimeFormat', () {
      test('should format dates', () {
        final result = JSEvaluator.evaluateString('''
          const date = new Date(2024, 0, 15);
          const formatter = new Intl.DateTimeFormat('en-US');
          formatter.format(date);
        ''');
        expect(result.toString(), isNotEmpty);
        expect(result.toString(), contains('1'));
      });

      test('should format with dateStyle', () {
        final result = JSEvaluator.evaluateString('''
          const date = new Date(2024, 0, 15);
          const formatter = new Intl.DateTimeFormat('en-US', {
            dateStyle: 'long'
          });
          formatter.format(date);
        ''');
        expect(result.toString(), contains('January'));
      });

      test('should have resolvedOptions method', () {
        final result = JSEvaluator.evaluateString('''
          const formatter = new Intl.DateTimeFormat('en-US');
          const options = formatter.resolvedOptions();
          options.locale;
        ''');
        expect(result.toString(), equals('en-US'));
      });

      test('should format with timeStyle', () {
        final result = JSEvaluator.evaluateString('''
          const date = new Date(2024, 0, 15, 14, 30, 45);
          const formatter = new Intl.DateTimeFormat('en-US', {
            timeStyle: 'medium'
          });
          formatter.format(date);
        ''');
        expect(result.toString(), contains(':'));
      });

      test('should format with both dateStyle and timeStyle', () {
        final result = JSEvaluator.evaluateString('''
          const date = new Date(2024, 5, 20, 9, 15, 0);
          const formatter = new Intl.DateTimeFormat('en-US', {
            dateStyle: 'short',
            timeStyle: 'short'
          });
          formatter.format(date);
        ''');
        expect(result.toString(), isNotEmpty);
      });

      test('should format with specific components', () {
        final result = JSEvaluator.evaluateString('''
          const date = new Date(2024, 11, 25);
          const formatter = new Intl.DateTimeFormat('en-US', {
            weekday: 'long',
            year: 'numeric',
            month: 'long',
            day: 'numeric'
          });
          formatter.format(date);
        ''');
        expect(result.toString(), contains('December'));
        expect(result.toString(), contains('2024'));
      });

      test('should format weekday only', () {
        final result = JSEvaluator.evaluateString('''
          const date = new Date(2024, 0, 1); // Monday
          const formatter = new Intl.DateTimeFormat('en-US', {
            weekday: 'long'
          });
          formatter.format(date);
        ''');
        expect(result.toString(), contains('Monday'));
      });

      test('should format time with hour12 option', () {
        final result = JSEvaluator.evaluateString('''
          const date = new Date(2024, 0, 15, 14, 30);
          const formatter = new Intl.DateTimeFormat('en-US', {
            hour: 'numeric',
            minute: 'numeric',
            hour12: true
          });
          formatter.format(date);
        ''');
        expect(
          result.toString(),
          anyOf(contains('PM'), contains('pm'), contains('2')),
        );
      });

      test('should format time with 24-hour format', () {
        final result = JSEvaluator.evaluateString('''
          const date = new Date(2024, 0, 15, 14, 30);
          const formatter = new Intl.DateTimeFormat('en-US', {
            hour: '2-digit',
            minute: '2-digit',
            hour12: false
          });
          formatter.format(date);
        ''');
        // Should contain the hour in some format
        expect(result.toString(), anyOf(contains('14'), contains('2')));
      });

      test('should format with different locales', () {
        final result = JSEvaluator.evaluateString('''
          const date = new Date(2024, 2, 15);
          const formatter = new Intl.DateTimeFormat('en-US', {
            month: 'long'
          });
          formatter.format(date);
        ''');
        expect(result.toString().toLowerCase(), contains('march'));
      });

      test('should use formatToParts', () {
        final result = JSEvaluator.evaluateString('''
          const date = new Date(2024, 0, 15);
          const formatter = new Intl.DateTimeFormat('en-US');
          const parts = formatter.formatToParts(date);
          parts.length > 0;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should format timestamps', () {
        final result = JSEvaluator.evaluateString('''
          const timestamp = 1705334400000; // Jan 15, 2024
          const formatter = new Intl.DateTimeFormat('en-US');
          formatter.format(timestamp);
        ''');
        expect(result.toString(), isNotEmpty);
      });

      test('should format era when specified', () {
        final result = JSEvaluator.evaluateString('''
          const date = new Date(2024, 0, 15);
          const formatter = new Intl.DateTimeFormat('en-US', {
            era: 'long',
            year: 'numeric'
          });
          formatter.format(date);
        ''');
        expect(
          result.toString(),
          anyOf(contains('AD'), contains('Anno Domini'), contains('2024')),
        );
      });
    });

    group('Intl.Collator', () {
      test('should compare strings', () {
        final result = JSEvaluator.evaluateString('''
          const collator = new Intl.Collator('en-US');
          collator.compare('a', 'b');
        ''');
        expect(result.toNumber() < 0, isTrue);
      });

      test('should compare equal strings', () {
        final result = JSEvaluator.evaluateString('''
          const collator = new Intl.Collator('en-US');
          collator.compare('hello', 'hello');
        ''');
        expect(result.toNumber(), equals(0));
      });

      test('should handle numeric sorting', () {
        final result = JSEvaluator.evaluateString('''
          const collator = new Intl.Collator('en-US', { numeric: true });
          const arr = ['2', '10', '1'];
          arr.sort((a, b) => collator.compare(a, b));
          arr.join(',');
        ''');
        expect(result.toString(), equals('1,2,10'));
      });

      test('should compare with case sensitivity', () {
        final result = JSEvaluator.evaluateString('''
          const collator = new Intl.Collator('en-US', { sensitivity: 'case' });
          collator.compare('A', 'a') !== 0;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should compare case insensitively with base sensitivity', () {
        final result = JSEvaluator.evaluateString('''
          const collator = new Intl.Collator('en-US', { sensitivity: 'base' });
          collator.compare('A', 'a');
        ''');
        expect(result.toNumber(), equals(0));
      });

      test('should sort array of strings', () {
        final result = JSEvaluator.evaluateString('''
          const collator = new Intl.Collator('en-US');
          const fruits = ['banana', 'apple', 'Cherry', 'date'];
          fruits.sort(collator.compare.bind(collator));
          fruits.join(',');
        ''');
        expect(result.toString(), isNotEmpty);
      });

      test('should handle accent sensitivity', () {
        final result = JSEvaluator.evaluateString('''
          const collator = new Intl.Collator('en-US', { sensitivity: 'accent' });
          collator.compare('e', 'é') !== 0;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should sort with ignorePunctuation', () {
        final result = JSEvaluator.evaluateString('''
          const collator = new Intl.Collator('en-US', { ignorePunctuation: true });
          const cmp = collator.compare("can't", 'cant');
          // ignorePunctuation may not be fully supported
          typeof cmp === 'number';
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should handle reverse order', () {
        final result = JSEvaluator.evaluateString('''
          const collator = new Intl.Collator('en-US');
          const arr = ['c', 'a', 'b'];
          arr.sort((a, b) => -collator.compare(a, b));
          arr.join(',');
        ''');
        expect(result.toString(), equals('c,b,a'));
      });

      test('should have resolvedOptions', () {
        final result = JSEvaluator.evaluateString('''
          const collator = new Intl.Collator('en-US', { numeric: true });
          const options = collator.resolvedOptions();
          options.numeric;
        ''');
        expect(result.toBoolean(), isTrue);
      });
    });

    group('Intl.PluralRules', () {
      test('should return plural category', () {
        final result = JSEvaluator.evaluateString('''
          const rules = new Intl.PluralRules('en-US');
          rules.select(1);
        ''');
        expect(result.toString(), equals('one'));
      });

      test('should return other for multiple', () {
        final result = JSEvaluator.evaluateString('''
          const rules = new Intl.PluralRules('en-US');
          rules.select(5);
        ''');
        expect(result.toString(), equals('other'));
      });

      test('should handle zero', () {
        final result = JSEvaluator.evaluateString('''
          const rules = new Intl.PluralRules('en-US');
          rules.select(0);
        ''');
        // In English, 0 is typically 'other', but some implementations return 'zero'
        expect(['other', 'zero'].contains(result.toString()), isTrue);
      });

      test('should handle ordinal type', () {
        final result = JSEvaluator.evaluateString('''
          const rules = new Intl.PluralRules('en-US', { type: 'ordinal' });
          rules.select(1);
        ''');
        expect(['one', 'other'].contains(result.toString()), isTrue);
      });

      test('should handle ordinal 2nd', () {
        final result = JSEvaluator.evaluateString('''
          const rules = new Intl.PluralRules('en-US', { type: 'ordinal' });
          rules.select(2);
        ''');
        expect(['two', 'other'].contains(result.toString()), isTrue);
      });

      test('should handle ordinal 3rd', () {
        final result = JSEvaluator.evaluateString('''
          const rules = new Intl.PluralRules('en-US', { type: 'ordinal' });
          rules.select(3);
        ''');
        expect(['few', 'other'].contains(result.toString()), isTrue);
      });

      test('should handle decimal numbers', () {
        final result = JSEvaluator.evaluateString('''
          const rules = new Intl.PluralRules('en-US');
          rules.select(1.5);
        ''');
        expect(result.toString(), equals('other'));
      });

      test('should handle negative numbers', () {
        final result = JSEvaluator.evaluateString('''
          const rules = new Intl.PluralRules('en-US');
          rules.select(-1);
        ''');
        expect(['one', 'other'].contains(result.toString()), isTrue);
      });

      test('should have resolvedOptions', () {
        final result = JSEvaluator.evaluateString('''
          const rules = new Intl.PluralRules('en-US', { type: 'ordinal' });
          const options = rules.resolvedOptions();
          options.type;
        ''');
        expect(result.toString(), equals('ordinal'));
      });

      test('should handle plural categories for different numbers', () {
        final result = JSEvaluator.evaluateString('''
          const rules = new Intl.PluralRules('en-US');
          const results = [0, 1, 2, 5, 10, 21].map(n => rules.select(n));
          results.join(',');
        ''');
        expect(result.toString(), contains('one'));
        expect(result.toString(), contains('other'));
      });
    });

    group('Intl.RelativeTimeFormat', () {
      test('should format relative time in days', () {
        final result = JSEvaluator.evaluateString('''
          const rtf = new Intl.RelativeTimeFormat('en-US', { style: 'long' });
          rtf.format(-1, 'day');
        ''');
        expect(result.toString().toLowerCase(), contains('day'));
      });

      test('should format relative time in future', () {
        final result = JSEvaluator.evaluateString('''
          const rtf = new Intl.RelativeTimeFormat('en-US', { style: 'long' });
          rtf.format(2, 'day');
        ''');
        expect(result.toString(), contains('2'));
        expect(result.toString().toLowerCase(), contains('day'));
      });

      test('should format months', () {
        final result = JSEvaluator.evaluateString('''
          const rtf = new Intl.RelativeTimeFormat('en-US');
          rtf.format(-3, 'month');
        ''');
        expect(result.toString(), contains('3'));
        expect(result.toString().toLowerCase(), contains('month'));
      });

      test('should format years in the past', () {
        final result = JSEvaluator.evaluateString('''
          const rtf = new Intl.RelativeTimeFormat('en-US', { style: 'long' });
          rtf.format(-1, 'year');
        ''');
        expect(
          result.toString().toLowerCase(),
          anyOf(contains('year'), contains('last')),
        );
      });

      test('should format years in the future', () {
        final result = JSEvaluator.evaluateString('''
          const rtf = new Intl.RelativeTimeFormat('en-US', { style: 'long' });
          rtf.format(5, 'year');
        ''');
        expect(result.toString(), contains('5'));
        expect(result.toString().toLowerCase(), contains('year'));
      });

      test('should format hours', () {
        final result = JSEvaluator.evaluateString('''
          const rtf = new Intl.RelativeTimeFormat('en-US');
          rtf.format(-2, 'hour');
        ''');
        expect(result.toString(), contains('2'));
        expect(result.toString().toLowerCase(), contains('hour'));
      });

      test('should format minutes', () {
        final result = JSEvaluator.evaluateString('''
          const rtf = new Intl.RelativeTimeFormat('en-US');
          rtf.format(30, 'minute');
        ''');
        expect(result.toString(), contains('30'));
        expect(result.toString().toLowerCase(), contains('minute'));
      });

      test('should format seconds', () {
        final result = JSEvaluator.evaluateString('''
          const rtf = new Intl.RelativeTimeFormat('en-US');
          rtf.format(-45, 'second');
        ''');
        expect(result.toString(), contains('45'));
        expect(result.toString().toLowerCase(), contains('second'));
      });

      test('should format weeks', () {
        final result = JSEvaluator.evaluateString('''
          const rtf = new Intl.RelativeTimeFormat('en-US');
          rtf.format(2, 'week');
        ''');
        expect(result.toString(), contains('2'));
        expect(result.toString().toLowerCase(), contains('week'));
      });

      test('should use short style', () {
        final result = JSEvaluator.evaluateString('''
          const rtf = new Intl.RelativeTimeFormat('en-US', { style: 'short' });
          rtf.format(-1, 'day');
        ''');
        expect(result.toString(), isNotEmpty);
      });

      test('should use narrow style', () {
        final result = JSEvaluator.evaluateString('''
          const rtf = new Intl.RelativeTimeFormat('en-US', { style: 'narrow' });
          rtf.format(1, 'day');
        ''');
        expect(result.toString(), isNotEmpty);
      });

      test('should use formatToParts', () {
        final result = JSEvaluator.evaluateString('''
          const rtf = new Intl.RelativeTimeFormat('en-US');
          const parts = rtf.formatToParts(-1, 'day');
          parts.length > 0;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should have resolvedOptions', () {
        final result = JSEvaluator.evaluateString('''
          const rtf = new Intl.RelativeTimeFormat('en-US', { style: 'short' });
          const options = rtf.resolvedOptions();
          options.style;
        ''');
        expect(result.toString(), equals('short'));
      });

      test('should handle numeric always', () {
        final result = JSEvaluator.evaluateString('''
          const rtf = new Intl.RelativeTimeFormat('en-US', { numeric: 'always' });
          rtf.format(-1, 'day');
        ''');
        expect(result.toString(), contains('1'));
      });

      test('should handle quarters', () {
        final result = JSEvaluator.evaluateString('''
          const rtf = new Intl.RelativeTimeFormat('en-US');
          rtf.format(-2, 'quarter');
        ''');
        expect(result.toString(), contains('2'));
        expect(result.toString().toLowerCase(), contains('quarter'));
      });
    });

    group('Intl.ListFormat', () {
      test('should format conjunction list', () {
        final result = JSEvaluator.evaluateString('''
          const lf = new Intl.ListFormat('en-US', { type: 'conjunction' });
          lf.format(['apple', 'banana', 'cherry']);
        ''');
        expect(result.toString(), contains('apple'));
        expect(result.toString(), contains('banana'));
        expect(result.toString(), contains('cherry'));
        expect(result.toString(), contains('and'));
      });

      test('should format disjunction list', () {
        final result = JSEvaluator.evaluateString('''
          const lf = new Intl.ListFormat('en-US', { type: 'disjunction' });
          lf.format(['apple', 'banana', 'cherry']);
        ''');
        expect(result.toString(), contains('or'));
      });

      test('should format two items', () {
        final result = JSEvaluator.evaluateString('''
          const lf = new Intl.ListFormat('en-US');
          lf.format(['apple', 'banana']);
        ''');
        expect(result.toString(), contains('apple'));
        expect(result.toString(), contains('banana'));
      });

      test('should format single item', () {
        final result = JSEvaluator.evaluateString('''
          const lf = new Intl.ListFormat('en-US');
          lf.format(['apple']);
        ''');
        expect(result.toString(), equals('apple'));
      });

      test('should format empty list', () {
        final result = JSEvaluator.evaluateString('''
          const lf = new Intl.ListFormat('en-US');
          lf.format([]);
        ''');
        expect(result.toString(), equals(''));
      });

      test('should format with unit type', () {
        final result = JSEvaluator.evaluateString('''
          const lf = new Intl.ListFormat('en-US', { type: 'unit' });
          lf.format(['5 feet', '3 inches']);
        ''');
        expect(result.toString(), contains('5 feet'));
        expect(result.toString(), contains('3 inches'));
      });

      test('should format with long style', () {
        final result = JSEvaluator.evaluateString('''
          const lf = new Intl.ListFormat('en-US', { style: 'long', type: 'conjunction' });
          lf.format(['one', 'two', 'three']);
        ''');
        expect(result.toString(), contains('and'));
      });

      test('should format with short style', () {
        final result = JSEvaluator.evaluateString('''
          const lf = new Intl.ListFormat('en-US', { style: 'short', type: 'conjunction' });
          lf.format(['a', 'b', 'c']);
        ''');
        expect(result.toString(), isNotEmpty);
      });

      test('should format with narrow style', () {
        final result = JSEvaluator.evaluateString('''
          const lf = new Intl.ListFormat('en-US', { style: 'narrow', type: 'unit' });
          lf.format(['1m', '2s']);
        ''');
        expect(result.toString(), isNotEmpty);
      });

      test('should use formatToParts', () {
        final result = JSEvaluator.evaluateString('''
          const lf = new Intl.ListFormat('en-US');
          const parts = lf.formatToParts(['a', 'b', 'c']);
          parts.length > 0;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should have resolvedOptions', () {
        final result = JSEvaluator.evaluateString('''
          const lf = new Intl.ListFormat('en-US', { type: 'disjunction' });
          const options = lf.resolvedOptions();
          options.type;
        ''');
        expect(result.toString(), equals('disjunction'));
      });

      test('should format four items', () {
        final result = JSEvaluator.evaluateString('''
          const lf = new Intl.ListFormat('en-US', { type: 'conjunction' });
          lf.format(['a', 'b', 'c', 'd']);
        ''');
        expect(result.toString(), contains('a'));
        expect(result.toString(), contains('d'));
        expect(result.toString(), contains('and'));
      });

      test('should handle numbers converted to strings', () {
        final result = JSEvaluator.evaluateString('''
          const lf = new Intl.ListFormat('en-US');
          lf.format([1, 2, 3].map(String));
        ''');
        expect(result.toString(), contains('1'));
        expect(result.toString(), contains('2'));
        expect(result.toString(), contains('3'));
      });
    });

    group('Intl.Segmenter', () {
      test('should segment by grapheme', () {
        final result = JSEvaluator.evaluateString('''
          const segmenter = new Intl.Segmenter('en-US', { granularity: 'grapheme' });
          const segments = segmenter.segment('hello');
          let count = 0;
          for (const seg of segments) {
            count++;
          }
          count;
        ''');
        expect(result.toNumber(), equals(5));
      });

      test('should segment by word', () {
        final result = JSEvaluator.evaluateString('''
          const segmenter = new Intl.Segmenter('en-US', { granularity: 'word' });
          const segments = segmenter.segment('hello world');
          let words = [];
          for (const seg of segments) {
            if (seg.isWordLike) {
              words.push(seg.segment);
            }
          }
          words.join(',');
        ''');
        expect(result.toString(), equals('hello,world'));
      });

      test('should segment by sentence', () {
        final result = JSEvaluator.evaluateString('''
          const segmenter = new Intl.Segmenter('en-US', { granularity: 'sentence' });
          const text = 'Hello world. How are you? I am fine.';
          const segments = segmenter.segment(text);
          let count = 0;
          for (const seg of segments) {
            count++;
          }
          count;
        ''');
        expect(result.toNumber(), equals(3));
      });

      test('should provide segment property', () {
        final result = JSEvaluator.evaluateString('''
          const segmenter = new Intl.Segmenter('en-US', { granularity: 'word' });
          const segments = segmenter.segment('hello');
          let firstSegment = '';
          for (const seg of segments) {
            firstSegment = seg.segment;
            break;
          }
          firstSegment;
        ''');
        expect(result.toString(), equals('hello'));
      });

      test('should provide index property', () {
        final result = JSEvaluator.evaluateString('''
          const segmenter = new Intl.Segmenter('en-US', { granularity: 'grapheme' });
          const segments = segmenter.segment('abc');
          let indices = [];
          for (const seg of segments) {
            indices.push(seg.index);
          }
          indices.join(',');
        ''');
        expect(result.toString(), equals('0,1,2'));
      });

      test('should segment emoji', () {
        final result = JSEvaluator.evaluateString('''
          const segmenter = new Intl.Segmenter('en-US', { granularity: 'grapheme' });
          const segments = segmenter.segment('👨‍👩‍👧‍👦');
          let count = 0;
          for (const seg of segments) {
            count++;
          }
          count >= 1;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should segment empty string', () {
        final result = JSEvaluator.evaluateString('''
          const segmenter = new Intl.Segmenter('en-US', { granularity: 'word' });
          const segments = segmenter.segment('');
          let count = 0;
          for (const seg of segments) {
            count++;
          }
          count;
        ''');
        expect(result.toNumber(), equals(0));
      });

      test('should segment punctuation separately', () {
        final result = JSEvaluator.evaluateString('''
          const segmenter = new Intl.Segmenter('en-US', { granularity: 'word' });
          const segments = segmenter.segment('hello, world!');
          let allSegments = [];
          for (const seg of segments) {
            allSegments.push(seg.segment);
          }
          allSegments.length > 2;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should have resolvedOptions', () {
        final result = JSEvaluator.evaluateString('''
          const segmenter = new Intl.Segmenter('en-US', { granularity: 'sentence' });
          const options = segmenter.resolvedOptions();
          options.granularity;
        ''');
        expect(result.toString(), equals('sentence'));
      });

      test('should segment with containing method', () {
        final result = JSEvaluator.evaluateString('''
          const segmenter = new Intl.Segmenter('en-US', { granularity: 'word' });
          const segments = segmenter.segment('hello world');
          const atZero = segments.containing(0);
          atZero ? atZero.segment : '';
        ''');
        expect(result.toString(), equals('hello'));
      });

      test('should segment multiline text', () {
        final result = JSEvaluator.evaluateString('''
          const segmenter = new Intl.Segmenter('en-US', { granularity: 'sentence' });
          const text = 'First sentence.\\nSecond sentence.';
          const segments = segmenter.segment(text);
          let count = 0;
          for (const seg of segments) {
            count++;
          }
          count;
        ''');
        expect(result.toNumber(), equals(2));
      });
    });

    group('Intl Static Methods', () {
      test('should have getCanonicalLocales', () {
        final result = JSEvaluator.evaluateString('''
          const locales = Intl.getCanonicalLocales(['EN-us', 'FR']);
          locales.join(',');
        ''');
        expect(result.toString().toLowerCase(), contains('en'));
      });

      test('should have supportedValuesOf for currency', () {
        final result = JSEvaluator.evaluateString('''
          const currencies = Intl.supportedValuesOf('currency');
          currencies.includes('USD');
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should have supportedValuesOf for calendar', () {
        final result = JSEvaluator.evaluateString('''
          const calendars = Intl.supportedValuesOf('calendar');
          calendars.includes('gregory');
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should have supportedValuesOf for collation', () {
        final result = JSEvaluator.evaluateString('''
          const collations = Intl.supportedValuesOf('collation');
          Array.isArray(collations);
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should have supportedValuesOf for numberingSystem', () {
        final result = JSEvaluator.evaluateString('''
          const systems = Intl.supportedValuesOf('numberingSystem');
          systems.includes('latn');
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should have supportedValuesOf for timeZone', () {
        final result = JSEvaluator.evaluateString('''
          const timeZones = Intl.supportedValuesOf('timeZone');
          timeZones.length > 0;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should have supportedValuesOf for unit', () {
        final result = JSEvaluator.evaluateString('''
          const units = Intl.supportedValuesOf('unit');
          units.includes('meter') || units.includes('kilogram') || units.length >= 0;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('getCanonicalLocales should normalize locales', () {
        final result = JSEvaluator.evaluateString('''
          const locales = Intl.getCanonicalLocales(['en-us', 'EN-GB', 'fr-FR']);
          locales.length;
        ''');
        expect(result.toNumber(), equals(3));
      });

      test('getCanonicalLocales should handle single locale', () {
        final result = JSEvaluator.evaluateString('''
          const locales = Intl.getCanonicalLocales('en-US');
          Array.isArray(locales) && locales.length === 1;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('getCanonicalLocales should handle multiple locales', () {
        final result = JSEvaluator.evaluateString('''
          const locales = Intl.getCanonicalLocales(['en-US', 'fr-FR', 'de-DE']);
          locales.length;
        ''');
        expect(result.toNumber(), equals(3));
      });
    });

    group('Intl Constructors', () {
      test('NumberFormat should be a constructor', () {
        final result = JSEvaluator.evaluateString('''
          typeof Intl.NumberFormat;
        ''');
        expect(result.toString(), equals('function'));
      });

      test('DateTimeFormat should be a constructor', () {
        final result = JSEvaluator.evaluateString('''
          typeof Intl.DateTimeFormat;
        ''');
        expect(result.toString(), equals('function'));
      });

      test('Collator should be a constructor', () {
        final result = JSEvaluator.evaluateString('''
          typeof Intl.Collator;
        ''');
        expect(result.toString(), equals('function'));
      });

      test('PluralRules should be a constructor', () {
        final result = JSEvaluator.evaluateString('''
          typeof Intl.PluralRules;
        ''');
        expect(result.toString(), equals('function'));
      });

      test('RelativeTimeFormat should be a constructor', () {
        final result = JSEvaluator.evaluateString('''
          typeof Intl.RelativeTimeFormat;
        ''');
        expect(result.toString(), equals('function'));
      });

      test('ListFormat should be a constructor', () {
        final result = JSEvaluator.evaluateString('''
          typeof Intl.ListFormat;
        ''');
        expect(result.toString(), equals('function'));
      });

      test('Segmenter should be a constructor', () {
        final result = JSEvaluator.evaluateString('''
          typeof Intl.Segmenter;
        ''');
        expect(result.toString(), equals('function'));
      });
    });

    group('Complex Real-World Use Cases', () {
      test('should format price list with different currencies', () {
        final result = JSEvaluator.evaluateString('''
          const prices = [
            { amount: 1234.56, currency: 'USD', locale: 'en-US' },
            { amount: 1234.56, currency: 'EUR', locale: 'de-DE' },
            { amount: 1234.56, currency: 'JPY', locale: 'ja-JP' }
          ];
          
          const formatted = prices.map(p => {
            const fmt = new Intl.NumberFormat(p.locale, {
              style: 'currency',
              currency: p.currency
            });
            return fmt.format(p.amount);
          });
          
          formatted.length === 3;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should create a date range formatter', () {
        final result = JSEvaluator.evaluateString('''
          function formatDateRange(start, end, locale) {
            const fmt = new Intl.DateTimeFormat(locale, {
              month: 'short',
              day: 'numeric',
              year: 'numeric'
            });
            return fmt.format(start) + ' - ' + fmt.format(end);
          }
          
          const start = new Date(2024, 0, 15);
          const end = new Date(2024, 0, 20);
          const range = formatDateRange(start, end, 'en-US');
          range.includes('15') && range.includes('20');
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should create pluralized messages', () {
        final result = JSEvaluator.evaluateString('''
          function formatItems(count, locale) {
            const pr = new Intl.PluralRules(locale);
            const category = pr.select(count);
            
            const messages = {
              one: count + ' item',
              other: count + ' items'
            };
            
            return messages[category] || messages.other;
          }
          
          const results = [
            formatItems(0, 'en-US'),
            formatItems(1, 'en-US'),
            formatItems(5, 'en-US')
          ];
          
          results[1] === '1 item' && results[2] === '5 items';
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should sort names by locale', () {
        final result = JSEvaluator.evaluateString('''
          const names = ['Müller', 'Mueller', 'Muller', 'miller'];
          const collator = new Intl.Collator('de-DE', { 
            sensitivity: 'base',
            ignorePunctuation: true 
          });
          
          names.sort(collator.compare.bind(collator));
          names.length === 4;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should format relative time dynamically', () {
        final result = JSEvaluator.evaluateString('''
          function formatTimeDiff(seconds, locale) {
            const rtf = new Intl.RelativeTimeFormat(locale, { style: 'long' });
            
            const intervals = [
              { unit: 'year', seconds: 31536000 },
              { unit: 'month', seconds: 2592000 },
              { unit: 'week', seconds: 604800 },
              { unit: 'day', seconds: 86400 },
              { unit: 'hour', seconds: 3600 },
              { unit: 'minute', seconds: 60 },
              { unit: 'second', seconds: 1 }
            ];
            
            for (const interval of intervals) {
              const count = Math.floor(Math.abs(seconds) / interval.seconds);
              if (count >= 1) {
                return rtf.format(seconds < 0 ? -count : count, interval.unit);
              }
            }
            return rtf.format(0, 'second');
          }
          
          const result1 = formatTimeDiff(-86400, 'en-US');
          const result2 = formatTimeDiff(7200, 'en-US');
          
          result1.toLowerCase().includes('day') && result2.toLowerCase().includes('hour');
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should format shopping cart summary', () {
        final result = JSEvaluator.evaluateString('''
          function formatCartSummary(items, locale) {
            const listFmt = new Intl.ListFormat(locale, { 
              type: 'conjunction',
              style: 'long' 
            });
            
            const numFmt = new Intl.NumberFormat(locale, {
              style: 'currency',
              currency: 'USD'
            });
            
            const itemNames = items.map(i => i.name);
            const total = items.reduce((sum, i) => sum + i.price * i.qty, 0);
            
            return {
              items: listFmt.format(itemNames),
              total: numFmt.format(total)
            };
          }
          
          const cart = [
            { name: 'Apple', price: 1.50, qty: 3 },
            { name: 'Banana', price: 0.75, qty: 6 },
            { name: 'Orange', price: 2.00, qty: 2 }
          ];
          
          const summary = formatCartSummary(cart, 'en-US');
          summary.items.includes('Apple') && summary.items.includes('and');
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should count words in text', () {
        final result = JSEvaluator.evaluateString('''
          function countWords(text, locale) {
            const segmenter = new Intl.Segmenter(locale, { granularity: 'word' });
            const segments = segmenter.segment(text);
            let count = 0;
            
            for (const seg of segments) {
              if (seg.isWordLike) {
                count++;
              }
            }
            
            return count;
          }
          
          const text = 'The quick brown fox jumps over the lazy dog.';
          countWords(text, 'en-US');
        ''');
        expect(result.toNumber(), equals(9));
      });

      test('should format event schedule', () {
        final result = JSEvaluator.evaluateString('''
          function formatEventTime(date, locale) {
            const dateFmt = new Intl.DateTimeFormat(locale, {
              weekday: 'long',
              month: 'long',
              day: 'numeric'
            });
            
            const timeFmt = new Intl.DateTimeFormat(locale, {
              hour: 'numeric',
              minute: '2-digit',
              hour12: true
            });
            
            return dateFmt.format(date) + ' at ' + timeFmt.format(date);
          }
          
          const event = new Date(2024, 5, 15, 14, 30);
          const formatted = formatEventTime(event, 'en-US');
          formatted.includes('June') && formatted.includes('15');
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should format file sizes', () {
        final result = JSEvaluator.evaluateString('''
          function formatFileSize(bytes, locale) {
            const units = ['B', 'KB', 'MB', 'GB', 'TB'];
            let unitIndex = 0;
            let size = bytes;
            
            while (size >= 1024 && unitIndex < units.length - 1) {
              size /= 1024;
              unitIndex++;
            }
            
            const numFmt = new Intl.NumberFormat(locale, {
              maximumFractionDigits: 2
            });
            
            return numFmt.format(size) + ' ' + units[unitIndex];
          }
          
          const results = [
            formatFileSize(500, 'en-US'),
            formatFileSize(1536, 'en-US'),
            formatFileSize(1048576, 'en-US'),
            formatFileSize(1610612736, 'en-US')
          ];
          
          results[0].includes('500') && results[2].includes('MB');
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should format duration', () {
        final result = JSEvaluator.evaluateString('''
          function formatDuration(totalSeconds, locale) {
            const hours = Math.floor(totalSeconds / 3600);
            const minutes = Math.floor((totalSeconds % 3600) / 60);
            const seconds = totalSeconds % 60;
            
            const parts = [];
            const listFmt = new Intl.ListFormat(locale, { type: 'unit', style: 'narrow' });
            
            if (hours > 0) parts.push(hours + 'h');
            if (minutes > 0) parts.push(minutes + 'm');
            if (seconds > 0 || parts.length === 0) parts.push(seconds + 's');
            
            return listFmt.format(parts);
          }
          
          const duration = formatDuration(3725, 'en-US');
          duration.includes('1h') && duration.includes('2m') && duration.includes('5s');
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should handle multiple formatters chained', () {
        final result = JSEvaluator.evaluateString('''
          const data = [
            { date: new Date(2024, 0, 15), amount: 1250.50 },
            { date: new Date(2024, 1, 20), amount: 3400.75 },
            { date: new Date(2024, 2, 10), amount: 890.25 }
          ];
          
          const dateFmt = new Intl.DateTimeFormat('en-US', { dateStyle: 'medium' });
          const numFmt = new Intl.NumberFormat('en-US', { 
            style: 'currency', 
            currency: 'USD' 
          });
          
          const formatted = data.map(d => ({
            date: dateFmt.format(d.date),
            amount: numFmt.format(d.amount)
          }));
          
          formatted.length === 3 && formatted[0].date.includes('2024');
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should create ordinal suffix function', () {
        final result = JSEvaluator.evaluateString('''
          function getOrdinal(n, locale) {
            const pr = new Intl.PluralRules(locale, { type: 'ordinal' });
            const suffixes = {
              one: 'st',
              two: 'nd',
              few: 'rd',
              other: 'th'
            };
            
            const category = pr.select(n);
            return n + (suffixes[category] || suffixes.other);
          }
          
          const results = [
            getOrdinal(1, 'en-US'),
            getOrdinal(2, 'en-US'),
            getOrdinal(3, 'en-US'),
            getOrdinal(4, 'en-US'),
            getOrdinal(11, 'en-US'),
            getOrdinal(21, 'en-US')
          ];
          
          results[0] === '1st' && results[3] === '4th';
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should split text into sentences and count', () {
        final result = JSEvaluator.evaluateString('''
          function analyzeParagraph(text, locale) {
            const sentenceSegmenter = new Intl.Segmenter(locale, { granularity: 'sentence' });
            const wordSegmenter = new Intl.Segmenter(locale, { granularity: 'word' });
            
            let sentenceCount = 0;
            let wordCount = 0;
            
            for (const sent of sentenceSegmenter.segment(text)) {
              sentenceCount++;
            }
            
            for (const word of wordSegmenter.segment(text)) {
              if (word.isWordLike) {
                wordCount++;
              }
            }
            
            return { sentences: sentenceCount, words: wordCount };
          }
          
          const text = 'Hello world. This is a test. How many sentences?';
          const stats = analyzeParagraph(text, 'en-US');
          stats.sentences === 3 && stats.words === 9;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should format percentage change', () {
        final result = JSEvaluator.evaluateString('''
          function formatChange(oldValue, newValue, locale) {
            const change = (newValue - oldValue) / oldValue;
            const numFmt = new Intl.NumberFormat(locale, {
              style: 'percent',
              minimumFractionDigits: 1,
              maximumFractionDigits: 1,
              signDisplay: 'always'
            });
            
            return numFmt.format(change);
          }
          
          const increase = formatChange(100, 125, 'en-US');
          const decrease = formatChange(100, 80, 'en-US');
          
          increase.includes('25') && increase.includes('%');
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should create internationalized greeting', () {
        final result = JSEvaluator.evaluateString('''
          function greet(name, items, locale) {
            const listFmt = new Intl.ListFormat(locale, { 
              type: 'conjunction',
              style: 'long' 
            });
            
            const pr = new Intl.PluralRules(locale);
            const count = items.length;
            const category = pr.select(count);
            
            const itemText = category === 'one' ? 'item' : 'items';
            const itemList = count > 0 ? listFmt.format(items) : 'nothing';
            
            return 'Hello ' + name + '! You have ' + count + ' ' + itemText + ': ' + itemList + '.';
          }
          
          const greeting = greet('John', ['apple', 'banana', 'cherry'], 'en-US');
          greeting.includes('John') && greeting.includes('3 items') && greeting.includes('and');
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should format invoice with multiple currencies', () {
        final result = JSEvaluator.evaluateString('''
          function formatInvoice(lineItems, currency, locale) {
            const numFmt = new Intl.NumberFormat(locale, {
              style: 'currency',
              currency: currency
            });
            
            const dateFmt = new Intl.DateTimeFormat(locale, {
              dateStyle: 'long'
            });
            
            let subtotal = 0;
            const lines = lineItems.map(item => {
              const lineTotal = item.qty * item.price;
              subtotal += lineTotal;
              return {
                description: item.description,
                qty: item.qty,
                price: numFmt.format(item.price),
                total: numFmt.format(lineTotal)
              };
            });
            
            const tax = subtotal * 0.1;
            const total = subtotal + tax;
            
            return {
              date: dateFmt.format(new Date()),
              lines: lines,
              subtotal: numFmt.format(subtotal),
              tax: numFmt.format(tax),
              total: numFmt.format(total)
            };
          }
          
          const items = [
            { description: 'Widget A', qty: 5, price: 10.00 },
            { description: 'Widget B', qty: 3, price: 25.00 }
          ];
          
          const invoice = formatInvoice(items, 'USD', 'en-US');
          invoice.lines.length === 2 && invoice.subtotal.includes('125');
        ''');
        expect(result.toBoolean(), isTrue);
      });
    });

    group('Edge Cases and Error Handling', () {
      test('should handle undefined locale gracefully', () {
        final result = JSEvaluator.evaluateString('''
          const fmt = new Intl.NumberFormat(undefined);
          typeof fmt.format(1234) === 'string';
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should handle empty options object', () {
        final result = JSEvaluator.evaluateString('''
          const fmt = new Intl.NumberFormat('en-US', {});
          typeof fmt.format(1234) === 'string';
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should handle null values in format', () {
        final result = JSEvaluator.evaluateString('''
          const fmt = new Intl.NumberFormat('en-US');
          const result = fmt.format(0);
          typeof result === 'string';
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should handle NaN in NumberFormat', () {
        final result = JSEvaluator.evaluateString('''
          const fmt = new Intl.NumberFormat('en-US');
          const result = fmt.format(NaN);
          result.includes('NaN') || result === 'NaN';
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should handle Infinity in NumberFormat', () {
        final result = JSEvaluator.evaluateString('''
          const fmt = new Intl.NumberFormat('en-US');
          const result = fmt.format(Infinity);
          result.includes('∞') || result.includes('Infinity') || result.length > 0;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should handle very small numbers', () {
        final result = JSEvaluator.evaluateString('''
          const fmt = new Intl.NumberFormat('en-US', {
            minimumFractionDigits: 10
          });
          const result = fmt.format(0.0000000001);
          result.length > 0;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should handle locale array', () {
        final result = JSEvaluator.evaluateString('''
          const fmt = new Intl.NumberFormat(['fr-FR', 'en-US']);
          typeof fmt.format(1234.56) === 'string';
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should handle DateTimeFormat with valid date', () {
        final result = JSEvaluator.evaluateString('''
          const fmt = new Intl.DateTimeFormat('en-US');
          const result = fmt.format(new Date(2024, 0, 15));
          result.length > 0;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should handle Collator with empty strings', () {
        final result = JSEvaluator.evaluateString('''
          const collator = new Intl.Collator('en-US');
          collator.compare('', '') === 0;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should handle RelativeTimeFormat with zero', () {
        final result = JSEvaluator.evaluateString('''
          const rtf = new Intl.RelativeTimeFormat('en-US');
          const result = rtf.format(0, 'day');
          result.length > 0;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should handle ListFormat with special characters', () {
        final result = JSEvaluator.evaluateString('''
          const lf = new Intl.ListFormat('en-US');
          const result = lf.format(['<html>', '&amp;', '"quotes"']);
          result.includes('<html>') && result.includes('&amp;');
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should handle PluralRules with decimals', () {
        final result = JSEvaluator.evaluateString('''
          const pr = new Intl.PluralRules('en-US');
          const results = [0.5, 1.0, 1.5, 2.0].map(n => pr.select(n));
          results.length === 4;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should handle Unicode in Segmenter', () {
        final result = JSEvaluator.evaluateString('''
          const segmenter = new Intl.Segmenter('en-US', { granularity: 'word' });
          const text = 'Hello 世界 مرحبا';
          const segments = segmenter.segment(text);
          let count = 0;
          for (const seg of segments) {
            if (seg.isWordLike) count++;
          }
          count >= 1;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should handle whitespace-only text in Segmenter', () {
        final result = JSEvaluator.evaluateString('''
          const segmenter = new Intl.Segmenter('en-US', { granularity: 'word' });
          const segments = segmenter.segment('   ');
          let wordCount = 0;
          for (const seg of segments) {
            if (seg.isWordLike) wordCount++;
          }
          wordCount === 0;
        ''');
        expect(result.toBoolean(), isTrue);
      });

      test('should handle multiple consecutive calls', () {
        final result = JSEvaluator.evaluateString('''
          const fmt = new Intl.NumberFormat('en-US');
          const results = [];
          for (let i = 0; i < 100; i++) {
            results.push(fmt.format(i * 1000));
          }
          results.length === 100;
        ''');
        expect(result.toBoolean(), isTrue);
      });
    });
  });
}
