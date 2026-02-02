import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('WeakMap Implementation', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('WeakMap constructor creates weak map', () {
      final result = interpreter.eval('new WeakMap()');
      expect(result.toString(), contains('[object WeakMap]'));
    });

    test('WeakMap.set stores object keys', () {
      final result = interpreter.eval('''
        var weakMap = new WeakMap();
        var key = {};
        weakMap.set(key, "value");
        weakMap.get(key);
      ''');
      expect(result.toString(), equals('value'));
    });

    test('WeakMap.get returns undefined for non-existent key', () {
      final result = interpreter.eval('''
        var weakMap = new WeakMap();
        var key = {};
        weakMap.get(key);
      ''');
      expect(result.toString(), equals('undefined'));
    });

    test('WeakMap.has returns true for existing key', () {
      final result = interpreter.eval('''
        var weakMap = new WeakMap();
        var key = {};
        weakMap.set(key, "value");
        weakMap.has(key);
      ''');
      expect(result.toString(), equals('true'));
    });

    test('WeakMap.has returns false for non-existent key', () {
      final result = interpreter.eval('''
        var weakMap = new WeakMap();
        var key = {};
        weakMap.has(key);
      ''');
      expect(result.toString(), equals('false'));
    });

    test('WeakMap.delete removes key and returns true', () {
      final result = interpreter.eval('''
        var weakMap = new WeakMap();
        var key = {};
        weakMap.set(key, "value");
        weakMap["delete"](key);
      ''');
      expect(result.toString(), equals('true'));
    });

    test('WeakMap.delete returns false for non-existent key', () {
      final result = interpreter.eval('''
        var weakMap = new WeakMap();
        var key = {};
        weakMap["delete"](key);
      ''');
      expect(result.toString(), equals('false'));
    });

    test('WeakMap rejects primitive keys', () {
      expect(() {
        interpreter.eval('''
          var weakMap = new WeakMap();
          weakMap.set("string", "value");
        ''');
      }, throwsA(isA<JSException>()));
    });
  });

  group('WeakSet Implementation', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('WeakSet constructor creates weak set', () {
      final result = interpreter.eval('new WeakSet()');
      expect(result.toString(), contains('[object WeakSet]'));
    });

    test('WeakSet.add stores object values', () {
      final result = interpreter.eval('''
        var weakSet = new WeakSet();
        var value = {};
        weakSet.add(value);
        weakSet.has(value);
      ''');
      expect(result.toString(), equals('true'));
    });

    test('WeakSet.has returns false for non-existent value', () {
      final result = interpreter.eval('''
        var weakSet = new WeakSet();
        var value = {};
        weakSet.has(value);
      ''');
      expect(result.toString(), equals('false'));
    });

    test('WeakSet.delete removes value and returns true', () {
      final result = interpreter.eval('''
        var weakSet = new WeakSet();
        var value = {};
        weakSet.add(value);
        weakSet["delete"](value);
      ''');
      expect(result.toString(), equals('true'));
    });

    test('WeakSet.delete returns false for non-existent value', () {
      final result = interpreter.eval('''
        var weakSet = new WeakSet();
        var value = {};
        weakSet["delete"](value);
      ''');
      expect(result.toString(), equals('false'));
    });

    test('WeakSet rejects primitive values', () {
      expect(() {
        interpreter.eval('''
          var weakSet = new WeakSet();
          weakSet.add("string");
        ''');
      }, throwsA(isA<JSException>()));
    });
  });
}
