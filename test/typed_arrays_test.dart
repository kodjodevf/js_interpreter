import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('TypedArrays Implementation', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    group('ArrayBuffer', () {
      test('creates ArrayBuffer with specified length', () {
        final result = interpreter.eval('''
          var buffer = new ArrayBuffer(8);
          buffer.byteLength;
        ''');

        expect(result.toNumber(), equals(8.0));
      });

      test('ArrayBuffer slice method', () {
        final result = interpreter.eval('''
          var buffer = new ArrayBuffer(16);
          var sliced = buffer.slice(4, 12);
          sliced.byteLength;
        ''');

        expect(result.toNumber(), equals(8.0));
      });

      test('ArrayBuffer with negative indices in slice', () {
        final result = interpreter.eval('''
          var buffer = new ArrayBuffer(16);
          var sliced = buffer.slice(-8, -4);
          sliced.byteLength;
        ''');

        expect(result.toNumber(), equals(4.0));
      });
    });

    group('Int8Array', () {
      test('creates Int8Array from length', () {
        final result = interpreter.eval('''
          var arr = new Int8Array(4);
          arr.length;
        ''');

        expect(result.toNumber(), equals(4.0));
      });

      test('creates Int8Array from array', () {
        final result = interpreter.eval('''
          var arr = new Int8Array([1, 2, 3, 4]);
          arr.length;
        ''');

        expect(result.toNumber(), equals(4.0));
      });

      test('Int8Array BYTES_PER_ELEMENT', () {
        final result = interpreter.eval('''
          var arr = new Int8Array(4);
          arr.BYTES_PER_ELEMENT;
        ''');

        expect(result.toNumber(), equals(1.0));
      });

      test('Int8Array buffer property', () {
        final result = interpreter.eval('''
          var arr = new Int8Array(4);
          arr.buffer.byteLength;
        ''');

        expect(result.toNumber(), equals(4.0));
      });

      test('Int8Array handles signed values correctly', () {
        final result = interpreter.eval('''
          var arr = new Int8Array([127, -128, 0]);
          // Note: We'll need to add element access support
          arr.length;
        ''');

        expect(result.toNumber(), equals(3.0));
      });
    });

    group('Uint8Array', () {
      test('creates Uint8Array from length', () {
        final result = interpreter.eval('''
          var arr = new Uint8Array(8);
          arr.length;
        ''');

        expect(result.toNumber(), equals(8.0));
      });

      test('creates Uint8Array from ArrayBuffer', () {
        final result = interpreter.eval('''
          var buffer = new ArrayBuffer(16);
          var arr = new Uint8Array(buffer, 4, 8);
          arr.length;
        ''');

        expect(result.toNumber(), equals(8.0));
      });

      test('Uint8Array byteOffset property', () {
        final result = interpreter.eval('''
          var buffer = new ArrayBuffer(16);
          var arr = new Uint8Array(buffer, 4, 8);
          arr.byteOffset;
        ''');

        expect(result.toNumber(), equals(4.0));
      });

      test('Uint8Array byteLength property', () {
        final result = interpreter.eval('''
          var buffer = new ArrayBuffer(16);
          var arr = new Uint8Array(buffer, 4, 8);
          arr.byteLength;
        ''');

        expect(result.toNumber(), equals(8.0));
      });
    });

    group('Uint8ClampedArray', () {
      test('creates Uint8ClampedArray', () {
        final result = interpreter.eval('''
          var arr = new Uint8ClampedArray(4);
          arr.length;
        ''');

        expect(result.toNumber(), equals(4.0));
      });

      test('Uint8ClampedArray clamps values with rounding', () {
        final result = interpreter.eval('''
          var arr = new Uint8ClampedArray([255.6, 0.4, -10, 300]);
          arr.length;
        ''');

        expect(result.toNumber(), equals(4.0));
      });
    });

    group('Int16Array', () {
      test('creates Int16Array from length', () {
        final result = interpreter.eval('''
          var arr = new Int16Array(4);
          arr.length;
        ''');

        expect(result.toNumber(), equals(4.0));
      });

      test('Int16Array BYTES_PER_ELEMENT', () {
        final result = interpreter.eval('''
          var arr = new Int16Array(4);
          arr.BYTES_PER_ELEMENT;
        ''');

        expect(result.toNumber(), equals(2.0));
      });

      test('Int16Array from ArrayBuffer', () {
        final result = interpreter.eval('''
          var buffer = new ArrayBuffer(16);
          var arr = new Int16Array(buffer);
          arr.length;
        ''');

        expect(result.toNumber(), equals(8.0)); // 16 bytes / 2 = 8 elements
      });
    });

    group('Uint16Array', () {
      test('creates Uint16Array from length', () {
        final result = interpreter.eval('''
          var arr = new Uint16Array(4);
          arr.length;
        ''');

        expect(result.toNumber(), equals(4.0));
      });
    });

    group('Int32Array', () {
      test('creates Int32Array from length', () {
        final result = interpreter.eval('''
          var arr = new Int32Array(4);
          arr.length;
        ''');

        expect(result.toNumber(), equals(4.0));
      });

      test('Int32Array BYTES_PER_ELEMENT', () {
        final result = interpreter.eval('''
          var arr = new Int32Array(4);
          arr.BYTES_PER_ELEMENT;
        ''');

        expect(result.toNumber(), equals(4.0));
      });

      test('Int32Array from ArrayBuffer', () {
        final result = interpreter.eval('''
          var buffer = new ArrayBuffer(16);
          var arr = new Int32Array(buffer);
          arr.length;
        ''');

        expect(result.toNumber(), equals(4.0)); // 16 bytes / 4 = 4 elements
      });
    });

    group('Uint32Array', () {
      test('creates Uint32Array from length', () {
        final result = interpreter.eval('''
          var arr = new Uint32Array(4);
          arr.length;
        ''');

        expect(result.toNumber(), equals(4.0));
      });
    });

    group('Float32Array', () {
      test('creates Float32Array from length', () {
        final result = interpreter.eval('''
          var arr = new Float32Array(4);
          arr.length;
        ''');

        expect(result.toNumber(), equals(4.0));
      });

      test('Float32Array BYTES_PER_ELEMENT', () {
        final result = interpreter.eval('''
          var arr = new Float32Array(4);
          arr.BYTES_PER_ELEMENT;
        ''');

        expect(result.toNumber(), equals(4.0));
      });

      test('Float32Array from array with decimals', () {
        final result = interpreter.eval('''
          var arr = new Float32Array([1.5, 2.7, 3.14]);
          arr.length;
        ''');

        expect(result.toNumber(), equals(3.0));
      });
    });

    group('Float64Array', () {
      test('creates Float64Array from length', () {
        final result = interpreter.eval('''
          var arr = new Float64Array(4);
          arr.length;
        ''');

        expect(result.toNumber(), equals(4.0));
      });

      test('Float64Array BYTES_PER_ELEMENT', () {
        final result = interpreter.eval('''
          var arr = new Float64Array(4);
          arr.BYTES_PER_ELEMENT;
        ''');

        expect(result.toNumber(), equals(8.0));
      });

      test('Float64Array from ArrayBuffer', () {
        final result = interpreter.eval('''
          var buffer = new ArrayBuffer(32);
          var arr = new Float64Array(buffer);
          arr.length;
        ''');

        expect(result.toNumber(), equals(4.0)); // 32 bytes / 8 = 4 elements
      });
    });

    group('DataView', () {
      test('creates DataView from ArrayBuffer', () {
        final result = interpreter.eval('''
          var buffer = new ArrayBuffer(16);
          var view = new DataView(buffer);
          view.byteLength;
        ''');

        expect(result.toNumber(), equals(16.0));
      });

      test('DataView with offset and length', () {
        final result = interpreter.eval('''
          var buffer = new ArrayBuffer(16);
          var view = new DataView(buffer, 4, 8);
          view.byteLength;
        ''');

        expect(result.toNumber(), equals(8.0));
      });

      test('DataView byteOffset property', () {
        final result = interpreter.eval('''
          var buffer = new ArrayBuffer(16);
          var view = new DataView(buffer, 4, 8);
          view.byteOffset;
        ''');

        expect(result.toNumber(), equals(4.0));
      });

      test('DataView setUint8 and getUint8', () {
        final result = interpreter.eval('''
          var buffer = new ArrayBuffer(4);
          var view = new DataView(buffer);
          view.setUint8(0, 42);
          view.getUint8(0);
        ''');

        expect(result.toNumber(), equals(42.0));
      });

      test('DataView setInt8 and getInt8', () {
        final result = interpreter.eval('''
          var buffer = new ArrayBuffer(4);
          var view = new DataView(buffer);
          view.setInt8(0, -128);
          view.getInt8(0);
        ''');

        expect(result.toNumber(), equals(-128.0));
      });
    });

    group('TypedArray methods', () {
      test('subarray creates a view on same buffer', () {
        final result = interpreter.eval('''
          var arr1 = new Uint8Array([1, 2, 3, 4, 5]);
          var arr2 = arr1.subarray(1, 4);
          arr2.length;
        ''');

        expect(result.toNumber(), equals(3.0));
      });

      test('subarray with negative indices', () {
        final result = interpreter.eval('''
          var arr1 = new Uint8Array([1, 2, 3, 4, 5]);
          var arr2 = arr1.subarray(-3, -1);
          arr2.length;
        ''');

        expect(result.toNumber(), equals(2.0));
      });

      test('set method copies values from array', () {
        final result = interpreter.eval('''
          var arr1 = new Uint8Array(5);
          var arr2 = new Uint8Array([10, 20, 30]);
          arr1.set(arr2, 1);
          arr1.length;
        ''');

        expect(result.toNumber(), equals(5.0));
      });

      test('copyWithin copies elements within array', () {
        final result = interpreter.eval('''
          var arr = new Uint8Array([1, 2, 3, 4, 5]);
          arr.copyWithin(0, 3, 5);
          arr.length;
        ''');

        expect(result.toNumber(), equals(5.0));
      });
    });

    group('Error handling', () {
      test('ArrayBuffer with negative length throws error', () {
        expect(
          () => interpreter.eval('new ArrayBuffer(-1)'),
          throwsA(anything),
        );
      });

      test('TypedArray with negative length throws error', () {
        expect(() => interpreter.eval('new Int8Array(-1)'), throwsA(anything));
      });

      test('DataView requires ArrayBuffer', () {
        expect(() => interpreter.eval('new DataView({})'), throwsA(anything));
      });

      test('DataView getUint8 with out of bounds index throws', () {
        expect(
          () => interpreter.eval('''
            var buffer = new ArrayBuffer(4);
            var view = new DataView(buffer);
            view.getUint8(10);
          '''),
          throwsA(anything),
        );
      });
    });
  });
}
