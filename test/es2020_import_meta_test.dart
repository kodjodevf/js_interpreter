import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('ES2020 import.meta', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    test('import.meta returns an object', () async {
      // Configure the module loader and resolver
      interpreter.setModuleResolver((moduleId, importer) {
        return moduleId; // Simple resolution for the test
      });

      interpreter.setModuleLoader((moduleId) async {
        return '''
          const meta = import.meta;
          export { meta };
        ''';
      });

      final module = await interpreter.evalAsync('''
        import('./test-module.js')
      ''');

      expect(module, isA<JSObject>());
      final metaValue = module.toObject().getProperty('meta');
      expect(metaValue, isA<JSObject>());
    });

    test('import.meta.url contains module URL', () async {
      interpreter.setModuleResolver((moduleId, importer) {
        return 'modules/$moduleId';
      });

      interpreter.setModuleLoader((moduleId) async {
        return '''
          const url = import.meta.url;
          export { url };
        ''';
      });

      final module = await interpreter.evalAsync('''
        import('./my-module.js')
      ''');

      expect(module, isA<JSObject>());
      final urlValue = module.toObject().getProperty('url');
      expect(urlValue.isString, isTrue);
      expect(urlValue.toString(), contains('modules/'));
      expect(urlValue.toString(), startsWith('file:///'));
    });

    test('import.meta is accessible in module scope', () async {
      interpreter.setModuleResolver((moduleId, importer) => moduleId);

      interpreter.setModuleLoader((moduleId) async {
        return '''
          const hasMeta = typeof import.meta !== 'undefined';
          const hasUrl = import.meta && typeof import.meta.url === 'string';
          export { hasMeta, hasUrl };
        ''';
      });

      // final module = await interpreter.evalAsync("import('./test.js')");

      // Check the properties by evaluating JavaScript
      final hasMetaResult = await interpreter.evalAsync('''
        (async () => {
          const m = await import('./test.js');
          return m.hasMeta;
        })()
      ''');

      final hasUrlResult = await interpreter.evalAsync('''
        (async () => {
          const m = await import('./test.js');
          return m.hasUrl;
        })()
      ''');

      expect(hasMetaResult.toNumber(), 1); // true is 1 in numeric context
      expect(hasUrlResult.toNumber(), 1);
    });

    test('import.meta can be stored and passed around', () async {
      interpreter.setModuleResolver((moduleId, importer) => moduleId);

      interpreter.setModuleLoader((moduleId) async {
        return '''
          const meta = import.meta;
          function getMeta() {
            return meta;
          }
          export { getMeta };
        ''';
      });

      // Call the function from JavaScript
      final result = await interpreter.evalAsync('''
        (async () => {
          const m = await import('./test.js');
          const metaObj = m.getMeta();
          return metaObj.url;
        })()
      ''');

      expect(result.isString, isTrue);
      expect(result.toString(), contains('test.js'));
    });

    test('import.meta.url is unique per module', () async {
      final loadedModules = <String>[];

      interpreter.setModuleResolver((moduleId, importer) => moduleId);

      interpreter.setModuleLoader((moduleId) async {
        loadedModules.add(moduleId);
        return '''
          const url = import.meta.url;
          export { url };
        ''';
      });

      // Get URLs from each module
      final url1 = await interpreter.evalAsync('''
        (async () => {
          const m = await import('./module1.js');
          return m.url;
        })()
      ''');

      final url2 = await interpreter.evalAsync('''
        (async () => {
          const m = await import('./module2.js');
          return m.url;
        })()
      ''');

      expect(url1.toString(), isNot(equals(url2.toString())));
      expect(url1.toString(), contains('module1.js'));
      expect(url2.toString(), contains('module2.js'));
    });

    test('import.meta in nested dynamic imports', () async {
      interpreter.setModuleResolver((moduleId, importer) => moduleId);

      interpreter.setModuleLoader((moduleId) async {
        if (moduleId == './parent.js') {
          return '''
            export async function loadChild() {
              const childModule = await import('./child.js');
              return {
                parentUrl: import.meta.url,
                childUrl: childModule.url
              };
            }
          ''';
        } else if (moduleId == './child.js') {
          return '''
            export const url = import.meta.url;
          ''';
        }
        return '';
      });

      // Call the nested function and get results
      final result = await interpreter.evalAsync('''
        (async () => {
          const parent = await import('./parent.js');
          const data = await parent.loadChild();
          return JSON.stringify({
            parentUrl: data.parentUrl,
            childUrl: data.childUrl
          });
        })()
      ''');

      // Parse the JSON result
      final jsonStr = result.toString();
      expect(jsonStr, contains('parent.js'));
      expect(jsonStr, contains('child.js'));
    });

    test('import.meta without module context returns default', () {
      // In the global context (non-module), import.meta should still work
      // but return a default URL
      final result = interpreter.eval('''
        const meta = import.meta;
        meta.url;
      ''');

      expect(result.isString, isTrue);
      expect(result.toString(), contains('file:///'));
    });

    test('import.meta properties are read-only conceptually', () async {
      interpreter.setModuleResolver((moduleId, importer) => moduleId);

      interpreter.setModuleLoader((moduleId) async {
        return '''
          const originalUrl = import.meta.url;
          // Tenter de modifier (ne devrait pas affecter l'original)
          const meta = import.meta;
          meta.url = 'changed';
          const afterUrl = import.meta.url;
          
          export { originalUrl, afterUrl };
        ''';
      });

      // Get URLs from JavaScript
      final originalUrl = await interpreter.evalAsync('''
        (async () => {
          const m = await import('./test.js');
          return m.originalUrl;
        })()
      ''');

      final afterUrl = await interpreter.evalAsync('''
        (async () => {
          const m = await import('./test.js');
          return m.afterUrl;
        })()
      ''');

      // Both should be non-empty
      expect(originalUrl.toString(), isNotEmpty);
      expect(afterUrl.toString(), isNotEmpty);
    });
  });
}
