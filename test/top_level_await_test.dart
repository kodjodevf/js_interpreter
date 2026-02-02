import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('ES2022 Top-Level Await', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('Simple module with top-level await', () async {
      final modules = <String, String>{
        'simple.js': '''
          const delay = (ms, value) => new Promise(resolve => setTimeout(() => resolve(value), ms));
          const result = await delay(10, 'done');
          export { result };
        ''',
      };

      interpreter.setModuleLoader((moduleId) async {
        if (modules.containsKey(moduleId)) {
          return modules[moduleId]!;
        }
        throw Exception('Module not found: \$moduleId');
      });

      interpreter.setModuleResolver((moduleId, importer) => moduleId);

      // Load the async module and verify exports
      final module = await interpreter.loadModule('simple.js');

      expect(module.exports['result']?.toString(), equals('done'));
    });

    test('Multiple top-level awaits in module', () async {
      final modules = <String, String>{
        'multiple.js': '''
          const delay = (ms, value) => new Promise(resolve => setTimeout(() => resolve(value), ms));
          
          const a = await delay(5, 'first');
          const b = await delay(5, 'second');
          const c = await delay(5, 'third');
          
          export { a, b, c };
        ''',
      };

      interpreter.setModuleLoader((moduleId) async {
        if (modules.containsKey(moduleId)) {
          return modules[moduleId]!;
        }
        throw Exception('Module not found: \$moduleId');
      });

      interpreter.setModuleResolver((moduleId, importer) => moduleId);

      // Load the async module and verify all exports
      final module = await interpreter.loadModule('multiple.js');

      expect(module.exports['a']?.toString(), equals('first'));
      expect(module.exports['b']?.toString(), equals('second'));
      expect(module.exports['c']?.toString(), equals('third'));
    });

    test('Top-level await with immediate Promise', () async {
      final modules = <String, String>{
        'immediate.js': '''
          const value = await Promise.resolve(42);
          export { value };
        ''',
      };

      interpreter.setModuleLoader((moduleId) async {
        if (modules.containsKey(moduleId)) {
          return modules[moduleId]!;
        }
        throw Exception('Module not found: \$moduleId');
      });

      interpreter.setModuleResolver((moduleId, importer) => moduleId);

      final module = await interpreter.loadModule('immediate.js');
      expect(module.exports['value']?.toNumber(), equals(42.0));
    });

    test('Module importing async module', () async {
      final modules = <String, String>{
        'async-dep.js': '''
          const delay = (ms, value) => new Promise(resolve => setTimeout(() => resolve(value), ms));
          const data = await delay(10, 'loaded');
          export { data };
        ''',
        'importer.js': '''
          import { data } from 'async-dep.js';
          const imported = data;
          export { imported };
        ''',
      };

      interpreter.setModuleLoader((moduleId) async {
        if (modules.containsKey(moduleId)) {
          return modules[moduleId]!;
        }
        throw Exception('Module not found: \$moduleId');
      });

      interpreter.setModuleResolver((moduleId, importer) => moduleId);

      // Preload the async dependency (will be automatic in the full implementation)
      await interpreter.loadModule('async-dep.js');

      // Load the importer module (which depends on async module)
      final module = await interpreter.loadModule('importer.js');
      expect(module.exports['imported']?.toString(), equals('loaded'));
    });

    test('Top-level await with error handling', () async {
      final modules = <String, String>{
        'error.js': '''
          const value = await Promise.reject(new Error('Test error'));
          export { value };
        ''',
      };

      interpreter.setModuleLoader((moduleId) async {
        if (modules.containsKey(moduleId)) {
          return modules[moduleId]!;
        }
        throw Exception('Module not found: \$moduleId');
      });

      interpreter.setModuleResolver((moduleId, importer) => moduleId);

      // Should throw an error
      expect(
        () async => await interpreter.loadModule('error.js'),
        throwsA(anything),
      );
    });

    test('Top-level await in expression', () async {
      final modules = <String, String>{
        'expression.js': '''
          const delay = (ms, value) => new Promise(resolve => setTimeout(() => resolve(value), ms));
          const sum = (await delay(5, 10)) + (await delay(5, 20));
          export { sum };
        ''',
      };

      interpreter.setModuleLoader((moduleId) async {
        if (modules.containsKey(moduleId)) {
          return modules[moduleId]!;
        }
        throw Exception('Module not found: \$moduleId');
      });

      interpreter.setModuleResolver((moduleId, importer) => moduleId);

      final module = await interpreter.loadModule('expression.js');
      expect(module.exports['sum']?.toNumber(), equals(30.0));
    });

    test('Top-level await detection', () async {
      final modules = <String, String>{
        'with-tla.js': '''
          const value = await Promise.resolve(42);
          export { value };
        ''',
        'without-tla.js': '''
          const value = 100;
          export { value };
        ''',
      };

      interpreter.setModuleLoader((moduleId) async {
        if (modules.containsKey(moduleId)) {
          return modules[moduleId]!;
        }
        throw Exception('Module not found: \$moduleId');
      });

      interpreter.setModuleResolver((moduleId, importer) => moduleId);

      // Both modules should load successfully
      final moduleTLA = await interpreter.loadModule('with-tla.js');
      final moduleSync = await interpreter.loadModule('without-tla.js');

      expect(moduleTLA.exports['value']?.toNumber(), equals(42.0));
      expect(moduleSync.exports['value']?.toNumber(), equals(100.0));

      // Verify TLA detection
      expect(moduleTLA.hasTopLevelAwait, isTrue);
      expect(moduleSync.hasTopLevelAwait, isFalse);
    });

    test('Top-level await with variable assignment', () async {
      final modules = <String, String>{
        'assignment.js': '''
          const delay = (ms, value) => new Promise(resolve => setTimeout(() => resolve(value), ms));
          let result = 0;
          result = await delay(5, 100);
          result += await delay(5, 50);
          export { result };
        ''',
      };

      interpreter.setModuleLoader((moduleId) async {
        if (modules.containsKey(moduleId)) {
          return modules[moduleId]!;
        }
        throw Exception('Module not found: \$moduleId');
      });

      interpreter.setModuleResolver((moduleId, importer) => moduleId);

      final module = await interpreter.loadModule('assignment.js');
      expect(module.exports['result']?.toNumber(), equals(150.0));
    });

    test('Top-level await with array operations', () async {
      final modules = <String, String>{
        'array.js': '''
          const delay = (ms, value) => new Promise(resolve => setTimeout(() => resolve(value), ms));
          const arr = [
            await delay(5, 1),
            await delay(5, 2),
            await delay(5, 3)
          ];
          export { arr };
        ''',
      };

      interpreter.setModuleLoader((moduleId) async {
        if (modules.containsKey(moduleId)) {
          return modules[moduleId]!;
        }
        throw Exception('Module not found: \$moduleId');
      });

      interpreter.setModuleResolver((moduleId, importer) => moduleId);

      final module = await interpreter.loadModule('array.js');
      final arr = module.exports['arr'];

      expect(arr?.toObject().getProperty('length').toNumber(), equals(3.0));
      expect(arr?.toObject().getProperty('0').toNumber(), equals(1.0));
      expect(arr?.toObject().getProperty('1').toNumber(), equals(2.0));
      expect(arr?.toObject().getProperty('2').toNumber(), equals(3.0));
    });

    test('Top-level await with object operations', () async {
      final modules = <String, String>{
        'object.js': '''
          const delay = (ms, value) => new Promise(resolve => setTimeout(() => resolve(value), ms));
          const obj = {
            x: await delay(5, 10),
            y: await delay(5, 20),
            z: await delay(5, 30)
          };
          export { obj };
        ''',
      };

      interpreter.setModuleLoader((moduleId) async {
        if (modules.containsKey(moduleId)) {
          return modules[moduleId]!;
        }
        throw Exception('Module not found: \$moduleId');
      });

      interpreter.setModuleResolver((moduleId, importer) => moduleId);

      final module = await interpreter.loadModule('object.js');
      final obj = module.exports['obj'];

      expect(obj?.toObject().getProperty('x').toNumber(), equals(10.0));
      expect(obj?.toObject().getProperty('y').toNumber(), equals(20.0));
      expect(obj?.toObject().getProperty('z').toNumber(), equals(30.0));
    });

    test('Top-level await in for-of loop with pre-resolved values', () async {
      final modules = <String, String>{
        'loop.js': '''
          // Create pre-resolved Promises
          const promises = [
            Promise.resolve(1),
            Promise.resolve(2),
            Promise.resolve(3)
          ];
          const results = [];
          for (const p of promises) {
            results.push(await p);
          }
          export { results };
        ''',
      };

      interpreter.setModuleLoader((moduleId) async {
        if (modules.containsKey(moduleId)) {
          return modules[moduleId]!;
        }
        throw Exception('Module not found: \$moduleId');
      });

      interpreter.setModuleResolver((moduleId, importer) => moduleId);

      final module = await interpreter.loadModule('loop.js');
      final results = module.exports['results'];

      expect(results?.toObject().getProperty('length').toNumber(), equals(3.0));
      expect(results?.toObject().getProperty('0').toNumber(), equals(1.0));
      expect(results?.toObject().getProperty('1').toNumber(), equals(2.0));
      expect(results?.toObject().getProperty('2').toNumber(), equals(3.0));
    });

    test('Top-level await with conditional', () async {
      final modules = <String, String>{
        'conditional.js': '''
          const delay = (ms, value) => new Promise(resolve => setTimeout(() => resolve(value), ms));
          const condition = await delay(5, true);
          const result = condition ? await delay(5, 'yes') : await delay(5, 'no');
          export { result };
        ''',
      };

      interpreter.setModuleLoader((moduleId) async {
        if (modules.containsKey(moduleId)) {
          return modules[moduleId]!;
        }
        throw Exception('Module not found: \$moduleId');
      });

      interpreter.setModuleResolver((moduleId, importer) => moduleId);

      final module = await interpreter.loadModule('conditional.js');
      expect(module.exports['result']?.toString(), equals('yes'));
    });
  });
}
