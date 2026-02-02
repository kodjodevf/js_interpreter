import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('Set Object Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Basic Set operations', () {
      // Create a global set for tests
      interpreter.eval('var globalSet = new Set()');
      interpreter.eval('globalSet.add("a")');
      interpreter.eval('globalSet.add("b")');
      interpreter.eval('globalSet.add("c")');

      expect(interpreter.eval('globalSet.size').primitiveValue, equals(3));
      expect(
        interpreter.eval('globalSet.has("a")').primitiveValue,
        equals(true),
      );
      expect(
        interpreter.eval('globalSet.has("b")').primitiveValue,
        equals(true),
      );
      expect(
        interpreter.eval('globalSet.has("d")').primitiveValue,
        equals(false),
      );
    });

    test('Set delete operation', () {
      interpreter.eval('var globalSet2 = new Set()');
      interpreter.eval('globalSet2.add("x")');
      interpreter.eval('globalSet2.add("y")');
      interpreter.eval('var globalDeleted = globalSet2["delete"]("x")');

      expect(interpreter.eval('globalDeleted').primitiveValue, equals(true));
      expect(
        interpreter.eval('globalSet2.has("x")').primitiveValue,
        equals(false),
      );
      expect(interpreter.eval('globalSet2.size').primitiveValue, equals(1));
    });

    test('Set clear operation', () {
      interpreter.eval('var globalSet3 = new Set()');
      interpreter.eval('globalSet3.add("a")');
      interpreter.eval('globalSet3.add("b")');
      interpreter.eval('globalSet3["clear"]()');

      expect(interpreter.eval('globalSet3.size').primitiveValue, equals(0));
      expect(
        interpreter.eval('globalSet3.has("a")').primitiveValue,
        equals(false),
      );
    });

    test('Set with object values', () {
      interpreter.eval('var globalSet4 = new Set()');
      interpreter.eval('var globalKey1 = {}');
      interpreter.eval('var globalKey2 = {name: "test"}');
      interpreter.eval('globalSet4.add(globalKey1)');
      interpreter.eval('globalSet4.add(globalKey2)');

      expect(
        interpreter.eval('globalSet4.has(globalKey1)').primitiveValue,
        equals(true),
      );
      expect(
        interpreter.eval('globalSet4.has(globalKey2)').primitiveValue,
        equals(true),
      );
      expect(interpreter.eval('globalSet4.size').primitiveValue, equals(2));
    });

    test('Set with array values', () {
      interpreter.eval('var globalSet5 = new Set()');
      interpreter.eval('var globalArr1 = [1, 2, 3]');
      interpreter.eval('var globalArr2 = ["a", "b"]');
      interpreter.eval('globalSet5.add(globalArr1)');
      interpreter.eval('globalSet5.add(globalArr2)');

      expect(
        interpreter.eval('globalSet5.has(globalArr1)').primitiveValue,
        equals(true),
      );
      expect(
        interpreter.eval('globalSet5.has(globalArr2)').primitiveValue,
        equals(true),
      );
      expect(interpreter.eval('globalSet5.size').primitiveValue, equals(2));
    });

    test('Set with number values', () {
      interpreter.eval('var globalSet6 = new Set()');
      interpreter.eval('globalSet6.add(42)');
      interpreter.eval('globalSet6.add(3.14)');
      interpreter.eval('globalSet6.add(0)');

      expect(
        interpreter.eval('globalSet6.has(42)').primitiveValue,
        equals(true),
      );
      expect(
        interpreter.eval('globalSet6.has(3.14)').primitiveValue,
        equals(true),
      );
      expect(
        interpreter.eval('globalSet6.has(0)').primitiveValue,
        equals(true),
      );
      expect(interpreter.eval('globalSet6.size').primitiveValue, equals(3));
    });

    test('Set initialization with iterable', () {
      interpreter.eval('var globalSet7 = new Set(["key1", "key2", 42])');

      expect(
        interpreter.eval('globalSet7.has("key1")').primitiveValue,
        equals(true),
      );
      expect(
        interpreter.eval('globalSet7.has("key2")').primitiveValue,
        equals(true),
      );
      expect(
        interpreter.eval('globalSet7.has(42)').primitiveValue,
        equals(true),
      );
      expect(interpreter.eval('globalSet7.size').primitiveValue, equals(3));
    });

    test('Set duplicate handling', () {
      interpreter.eval('var globalSet8 = new Set()');
      interpreter.eval('globalSet8.add("duplicate")');
      interpreter.eval('globalSet8.add("duplicate")');
      interpreter.eval('globalSet8.add("duplicate")');

      expect(interpreter.eval('globalSet8.size').primitiveValue, equals(1));
      expect(
        interpreter.eval('globalSet8.has("duplicate")').primitiveValue,
        equals(true),
      );
    });

    test('Set chaining (add returns set)', () {
      interpreter.eval('var globalSet9 = new Set()');
      interpreter.eval('var globalResult = globalSet9.add("a")');

      // add should return the set itself for chaining
      expect(
        interpreter.eval('globalResult').toString(),
        equals('[object Set]'),
      );
      expect(
        interpreter.eval('globalSet9.has("a")').primitiveValue,
        equals(true),
      );
    });

    test('Set delete non-existent element', () {
      interpreter.eval('var globalSet10 = new Set()');
      interpreter.eval('globalSet10.add("a")');
      interpreter.eval(
        'var globalDeleted2 = globalSet10["delete"]("nonexistent")',
      );

      expect(interpreter.eval('globalDeleted2').primitiveValue, equals(false));
      expect(interpreter.eval('globalSet10.size').primitiveValue, equals(1));
    });
  });
}
