/// Bytecode interpreter: parse → compile → execute pipeline.
///
/// Provides a simple API for executing JavaScript source code
/// through the bytecode compilation and VM execution pipeline.
library;

import '../parser/parser.dart';
import '../runtime/runtime_bootstrap.dart';
import '../runtime/js_value.dart';
import 'bytecode.dart';
import 'compiler.dart';
import 'vm.dart';

/// High-level bytecode-based JavaScript interpreter.
///
/// When [useFullRuntime] is true (default), initializes the VM with
/// the currently configured runtime globals.
class BytecodeInterpreter {
  final BytecodeVM _vm = BytecodeVM();

  BytecodeInterpreter({bool useFullRuntime = true}) {
    if (useFullRuntime) {
      _initFullRuntime();
    }
  }

  void _initFullRuntime() {
    RuntimeBootstrap.populateGlobals(_vm.globals);
  }

  /// Evaluate a JavaScript source string and return the result.
  JSValue eval(String source) {
    final program = JSParser.parseString(source);
    final compiler = BytecodeCompiler();
    final bytecode = compiler.compile(program);
    return _vm.execute(bytecode);
  }

  /// Compile source to bytecode without executing.
  FunctionBytecode compile(String source) {
    final program = JSParser.parseString(source);
    final compiler = BytecodeCompiler();
    return compiler.compile(program);
  }

  /// Execute pre-compiled bytecode.
  JSValue execute(FunctionBytecode bytecode) {
    return _vm.execute(bytecode);
  }

  /// Get console output (for testing).
  List<String> takeConsoleOutput() => _vm.takeConsoleOutput();

  /// Access the underlying VM (for advanced usage).
  BytecodeVM get vm => _vm;
}
