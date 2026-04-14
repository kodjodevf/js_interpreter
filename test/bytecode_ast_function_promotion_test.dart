import 'package:js_interpreter/src/bytecode/vm.dart';
import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  group('Bytecode AST Function Promotion', () {
    test('interpreter hoists function declarations before execution', () {
      final interpreter = JSInterpreter();

      final result = interpreter.eval('''
        var value = twice(21);
        function twice(x) { return x * 2; }
        value;
      ''');

      expect(result.toNumber(), equals(42));
    });

    test('interpreter hoists sibling functions before compiling closures', () {
      final interpreter = JSInterpreter();

      final result = interpreter.eval('''
        var l = {};
        function outer() {
          function i(value) { return l(value); }
          function l(value) { return value + 1; }
          return i(41);
        }
        outer();
      ''');

      expect(result.toNumber(), equals(42));
    });

    test('interpreter can trace not-a-function errors', () {
      final interpreter = JSInterpreter();
      interpreter.enableNotAFunctionTracing();

      expect(
        () => interpreter.eval('''
          var value = {};
          value();
        '''),
        throwsA(
          predicate((error) => error.toString().contains('is not a function')),
        ),
      );

      final trace = interpreter.consoleOutput.join('\n');
      expect(trace, contains('[trace:not-a-function]'));
      expect(trace, contains('callee=[object Object]'));
      expect(trace, contains('jsType=object'));
      expect(trace, contains('function=<script>'));
      expect(trace, contains('opcode='));
      expect(trace, contains('location=<script>@'));
      expect(trace, contains('stackTop='));
      expect(trace, contains('locals='));
      expect(trace, contains('closureVars='));
    });

    test('interpreter resolves globals defined via globalThis properties', () {
      final interpreter = JSInterpreter();

      final initial = interpreter.eval('''
        Object.defineProperty(globalThis, 'fromDefineProperty', {
          value: 42,
          writable: true,
          configurable: true,
        });
        fromDefineProperty;
      ''');

      expect(initial.toNumber(), equals(42));

      final updated = interpreter.eval('''
        fromDefineProperty = 7;
        globalThis.fromDefineProperty;
      ''');

      expect(updated.toNumber(), equals(7));
      expect(
        interpreter.eval('typeof fromDefineProperty').toString(),
        'number',
      );
    });

    test('VM can execute a global AST function directly in bytecode', () {
      final declaration = JSParser.parseExpression(
        'function add(a, b) { return a + b; }',
      );
      final function = JSFunction(
        declaration,
        Environment.global(),
        sourceText: 'function add(a, b) { return a + b; }',
      );

      expect(function, isA<JSFunction>());

      final vm = BytecodeVM();
      vm.globals['globalThis'] = JSObject();

      final result = vm.callFunction(function as JSValue, [
        JSValueFactory.number(2),
        JSValueFactory.number(3),
      ]);

      expect(result.toNumber(), equals(5));
    });

    test('VM can execute through empty intermediate environments', () {
      final declaration = JSParser.parseExpression(
        'function mul(a, b) { return a * b; }',
      );
      final function = JSFunction(
        declaration,
        Environment.block(Environment.global()),
        sourceText: 'function mul(a, b) { return a * b; }',
      );

      final vm = BytecodeVM();
      vm.globals['globalThis'] = JSObject();

      final result = vm.callFunction(function, [
        JSValueFactory.number(6),
        JSValueFactory.number(7),
      ]);

      expect(result.toNumber(), equals(42));
    });

    test(
      'VM can execute when intermediate environments exist but are unused',
      () {
        final declaration = JSParser.parseExpression(
          'function inc(a) { return a + 1; }',
        );
        final env = Environment.block(Environment.global());
        env.define(
          'shadowedButUnused',
          JSValueFactory.number(99),
          BindingType.let_,
        );
        final function = JSFunction(
          declaration,
          env,
          sourceText: 'function inc(a) { return a + 1; }',
        );

        final vm = BytecodeVM();
        vm.globals['globalThis'] = JSObject();

        final result = vm.callFunction(function, [JSValueFactory.number(8)]);
        expect(result.toNumber(), equals(9));
      },
    );

    test('VM can execute with captured immutable bindings', () {
      final declaration = JSParser.parseExpression(
        'function addCapturedConst(a) { return a + capturedConst; }',
      );
      final env = Environment.block(Environment.global());
      env.define(
        'capturedConst',
        JSValueFactory.number(10),
        BindingType.const_,
      );
      final function = JSFunction(
        declaration,
        env,
        sourceText:
            'function addCapturedConst(a) { return a + capturedConst; }',
      );

      final vm = BytecodeVM();
      vm.globals['globalThis'] = JSObject();

      final result = vm.callFunction(function, [JSValueFactory.number(5)]);
      expect(result.toNumber(), equals(15));
    });

    test('VM can execute with captured mutable bindings', () {
      final declaration = JSParser.parseExpression(
        'function addCaptured(a) { captured += a; return captured; }',
      );
      final env = Environment.block(Environment.global());
      env.define('captured', JSValueFactory.number(10), BindingType.let_);
      final function = JSFunction(
        declaration,
        env,
        sourceText:
            'function addCaptured(a) { captured += a; return captured; }',
      );

      final vm = BytecodeVM();
      vm.globals['globalThis'] = JSObject();

      final first = vm.callFunction(function, [JSValueFactory.number(5)]);
      final second = vm.callFunction(function, [JSValueFactory.number(3)]);

      expect(first.toNumber(), equals(15));
      expect(second.toNumber(), equals(18));
      expect(env.get('captured').toNumber(), equals(18));
    });

    test('VM can execute a legacy MethodDefinition without fallback', () {
      final classExpr =
          JSParser.parseExpression(
                'class Example { method(delta) { return this.base + delta; } }',
              )
              as ClassExpression;
      final method = classExpr.body.members.first as MethodDefinition;
      final function = JSFunction(
        method,
        Environment.global(),
        sourceText: 'method(delta) { return this.base + delta; }',
        isMethodDefinition: true,
      );
      function.setFunctionName('method');

      final vm = BytecodeVM();
      final receiver = JSObject()
        ..setProperty('base', JSValueFactory.number(5));
      vm.globals['globalThis'] = JSObject();

      final result = vm.callFunction(function, [
        JSValueFactory.number(2),
      ], receiver);

      expect(result.toNumber(), equals(7));
    });

    test('promoted closures share the same mutable captured binding', () {
      final incrementDecl = JSParser.parseExpression(
        'function increment() { counter += 1; return counter; }',
      );
      final readDecl = JSParser.parseExpression(
        'function read() { return counter; }',
      );

      final env = Environment.block(Environment.global());
      env.define('counter', JSValueFactory.number(0), BindingType.let_);

      final increment = JSFunction(
        incrementDecl,
        env,
        sourceText: 'function increment() { counter += 1; return counter; }',
      );
      final read = JSFunction(
        readDecl,
        env,
        sourceText: 'function read() { return counter; }',
      );

      final vm = BytecodeVM();
      vm.globals['globalThis'] = JSObject();

      expect(vm.callFunction(read, []).toNumber(), equals(0));
      expect(vm.callFunction(increment, []).toNumber(), equals(1));
      expect(vm.callFunction(read, []).toNumber(), equals(1));
      expect(vm.callFunction(increment, []).toNumber(), equals(2));
      expect(env.get('counter').toNumber(), equals(2));
    });

    test('VM preserves TDZ behavior for captured uninitialized bindings', () {
      final declaration = JSParser.parseExpression(
        'function readCaptured() { return captured; }',
      );
      final env = Environment.block(Environment.global());
      env.createHoistedBinding('captured', BindingType.let_);
      final function = JSFunction(
        declaration,
        env,
        sourceText: 'function readCaptured() { return captured; }',
      );

      final vm = BytecodeVM();
      vm.globals['globalThis'] = JSObject();

      expect(
        () => vm.callFunction(function, []),
        throwsA(isA<JSReferenceError>()),
      );

      env.initializeHoistedBinding('captured', JSValueFactory.number(21));

      final result = vm.callFunction(function, []);
      expect(result.toNumber(), equals(21));
    });

    test('functionExprName assignment is ignored in non-strict mode', () {
      final declaration = JSParser.parseExpression(
        'function writeSelf() { selfRef = 9; return selfRef; }',
      );
      final env = Environment.block(Environment.global());
      env.define(
        'selfRef',
        JSValueFactory.number(7),
        BindingType.functionExprName,
      );
      final function = JSFunction(
        declaration,
        env,
        sourceText: 'function writeSelf() { selfRef = 9; return selfRef; }',
        strictMode: false,
      );

      final vm = BytecodeVM();
      vm.globals['globalThis'] = JSObject();

      final result = vm.callFunction(function, []);
      expect(result.toNumber(), equals(7));
      expect(env.get('selfRef').toNumber(), equals(7));
    });

    test('functionExprName assignment throws in strict mode', () {
      final declaration = JSParser.parseExpression(
        'function writeSelfStrict() { selfRef = 9; return selfRef; }',
      );
      final env = Environment.block(Environment.global());
      env.define(
        'selfRef',
        JSValueFactory.number(7),
        BindingType.functionExprName,
      );
      final function = JSFunction(
        declaration,
        env,
        sourceText:
            'function writeSelfStrict() { selfRef = 9; return selfRef; }',
        strictMode: true,
      );

      final vm = BytecodeVM();
      vm.globals['globalThis'] = JSObject();

      expect(() => vm.callFunction(function, []), throwsA(isA<JSTypeError>()));
      expect(env.get('selfRef').toNumber(), equals(7));
    });

    test('bytecode interpreter can construct via promoted AST function', () {
      final interpreter = JSInterpreter();
      final result = interpreter.eval('''
        function Point(x, y) { this.x = x; this.y = y; }
        const p = new Point(4, 6);
        p.x + p.y;
      ''');

      expect(result.toNumber(), equals(10));
    });

    test('Function constructor works without evaluator bootstrap', () {
      final interpreter = JSInterpreter();
      final result = interpreter.eval('''
        const add = Function('a', 'b', 'return a + b;');
        add(4, 5);
      ''');

      expect(result.toNumber(), equals(9));
    });

    test('bytecode closures can capture later lexical declarations', () {
      final interpreter = JSInterpreter();
      final result = interpreter.eval('''
        let readLater;
        {
          readLater = function() { return laterValue; };
          let laterValue = 21;
          readLater();
        }
      ''');

      expect(result.toNumber(), equals(21));
    });

    test('VM rejects non-promotable legacy functions', () {
      final declaration = JSParser.parseExpression(
        'function add(a, b) { return a + b; }',
      );
      final function = JSFunction(
        declaration,
        Object(),
        sourceText: 'function add(a, b) { return a + b; }',
      );

      final vm = BytecodeVM();
      vm.globals['globalThis'] = JSObject();

      expect(
        () => vm.callFunction(function, [
          JSValueFactory.number(2),
          JSValueFactory.number(3),
        ]),
        throwsA(isA<JSTypeError>()),
      );
    });
  });
}
