import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('ES2020 Dynamic Import', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('should return a Promise when module loader is not set', () {
      // Without module loader, import() returns a Promise anyway
      // (which will be rejected when we try to resolve it)
      final result = interpreter.eval('import("./test.js")');
      expect(result, isA<JSPromise>());
      expect(result.toString(), '[object Promise]');
    });

    test('dynamic import() should return a Promise', () {
      // Simuler un module loader basique
      interpreter.setModuleLoader((moduleId) async {
        // Return a simple JS module
        return '''
          export const value = 42;
          export default function greet() { return "Hello"; }
        ''';
      });

      // Maintenant l'import devrait fonctionner
      final result = interpreter.eval('''
        const modulePromise = import("./test.js");
        typeof modulePromise;
      ''');

      expect(result.toString(), 'object');
    });

    test('dynamic import() should resolve with module exports', () async {
      // Module loader qui retourne un module avec exports
      interpreter.setModuleLoader((moduleId) async {
        if (moduleId == './math.js') {
          return '''
            export const PI = 3.14159;
            export function add(a, b) { return a + b; }
            export default function multiply(a, b) { return a * b; }
          ''';
        }
        throw Exception('Module not found: $moduleId');
      });

      // Utiliser evalAsync pour attendre automatiquement la Promise
      final module = await interpreter.evalAsync('import("./math.js")');

      // Check the exports
      final moduleObj = module.toObject();

      // Check PI
      final piValue = moduleObj.getProperty('PI');
      expect(piValue.toNumber(), closeTo(3.14159, 0.00001));

      // Check the add function - call via eval
      final addResult = await interpreter.evalAsync('''
        (async () => {
          const m = await import("./math.js");
          return m.add(2, 3);
        })()
      ''');
      expect(addResult.toNumber(), 5);

      // Check the default function (multiply)
      final multiplyResult = await interpreter.evalAsync('''
        (async () => {
          const m = await import("./math.js");
          return m.default(4, 5);
        })()
      ''');
      expect(multiplyResult.toNumber(), 20);
    });
    test('dynamic import() should support module resolution', () async {
      // Module resolver qui transforme les chemins relatifs
      interpreter.setModuleResolver((moduleId, importer) {
        if (moduleId.startsWith('./')) {
          return 'modules/${moduleId.substring(2)}';
        }
        return moduleId;
      });

      // Module loader
      interpreter.setModuleLoader((moduleId) async {
        if (moduleId == 'modules/utils.js') {
          return 'export const version = "1.0.0";';
        }
        throw Exception('Module not found: $moduleId');
      });

      // Utiliser evalAsync avec await
      final module = await interpreter.evalAsync('''
        import("./utils.js")
      ''');

      final version = module.toObject().getProperty('version');
      expect(version.toString(), '1.0.0');
    });

    test('dynamic import() should handle errors', () async {
      interpreter.setModuleLoader((moduleId) async {
        throw Exception('Network error');
      });

      // evalAsync devrait propager l'erreur comme rejet de Promise
      expect(
        () => interpreter.evalAsync('import("./missing.js")'),
        throwsA(isA<Object>()),
      );
    });

    test('dynamic import() with computed module path', () async {
      interpreter.setModuleLoader((moduleId) async {
        if (moduleId == 'en.js') {
          return 'export const greeting = "Hello";';
        } else if (moduleId == 'fr.js') {
          return 'export const greeting = "Bonjour";';
        }
        throw Exception('Module not found: $moduleId');
      });

      // Use evalAsync with await and computed path
      final module = await interpreter.evalAsync('''
        const lang = "fr";
        import(lang + ".js")
      ''');

      final greeting = module.toObject().getProperty('greeting');
      expect(greeting.toString(), 'Bonjour');
    });

    test('dynamic import() can be awaited in async function', () async {
      interpreter.setModuleLoader((moduleId) async {
        return 'export const data = [1, 2, 3];';
      });

      // Tester simplement que le module s'exporte correctement
      final module = await interpreter.evalAsync('import("./data.js")');

      final data = module.toObject().getProperty('data');
      expect((data as JSArray).length, 3);

      // Test reduce in a separate call
      final sum = await interpreter.evalAsync('''
        (async () => {
          const m = await import("./data.js");
          return m.data.reduce((a, b) => a + b, 0);
        })()
      ''');
      expect(sum.toNumber(), 6);
    });

    test('multiple dynamic imports can run concurrently', () async {
      interpreter.setModuleLoader((moduleId) async {
        // Simulate a variable delay
        await Future.delayed(Duration(milliseconds: 10));
        return 'export const name = "$moduleId";';
      });

      // Utiliser evalAsync avec Promise.all
      final results = await interpreter.evalAsync('''
        Promise.all([
          import("module1.js"),
          import("module2.js"),
          import("module3.js")
        ]).then(modules => {
          return modules.map(m => m.name);
        })
      ''');

      final resultsArray = results as JSArray;
      expect(resultsArray.length, 3);
      expect(resultsArray.get(0).toString(), 'module1.js');
      expect(resultsArray.get(1).toString(), 'module2.js');
      expect(resultsArray.get(2).toString(), 'module3.js');
    });
  });
}
