import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:js_interpreter/js_interpreter.dart';

enum TestMode { defaultNoStrict, defaultStrict, noStrict, strict, all }

class Test262Runner {
  String? testDir;
  String? harnessDir;
  String? reportPath;
  final List<String> excludeList = [];
  final List<String> excludeDirList = [];
  final Set<String> features = {};
  final Set<String> skipFeatures = {};
  final Set<String> harnessExclude = {};

  TestMode testMode = TestMode.defaultNoStrict;
  bool verbose = false;
  bool compact = false;
  bool showTimings = false;
  bool newStyle = true;
  int slowTestThreshold = 100;
  int timeoutMs = 10000;

  int testCount = 0;
  int testFailed = 0;
  int testSkipped = 0;
  int testExcluded = 0;

  final Map<String, int> skipFeatureCounts = {};
  final Map<String, Map<String, dynamic>> results = {};

  Test262Runner();

  void loadConfig(String path) {
    final file = File(path);
    if (!file.existsSync()) return;

    final lines = file.readAsLinesSync();
    String? section;

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1);
        continue;
      }

      if (section == 'config') {
        final parts = line.split('=');
        if (parts.length == 2) {
          final key = parts[0].trim();
          final value = parts[1].trim();
          switch (key) {
            case 'harnessdir':
              harnessDir = value;
              break;
            case 'testdir':
              testDir = value;
              break;
            case 'mode':
              testMode = _parseTestMode(value);
              break;
            case 'style':
              newStyle = value == 'new';
              break;
          }
        }
      } else if (section == 'features') {
        final parts = line.split('=');
        final feature = parts[0].trim();
        if (parts.length == 2 && parts[1].trim() == 'skip') {
          skipFeatures.add(feature);
        } else {
          features.add(feature);
        }
      }
    }
  }

  TestMode _parseTestMode(String mode) {
    switch (mode) {
      case 'default-nostrict':
        return TestMode.defaultNoStrict;
      case 'default-strict':
        return TestMode.defaultStrict;
      case 'strict':
        return TestMode.strict;
      case 'nostrict':
        return TestMode.noStrict;
      case 'all':
      case 'both':
        return TestMode.all;
      default:
        return TestMode.defaultNoStrict;
    }
  }

  int _naturalCompare(String a, String b) {
    var i = 0, j = 0;
    while (i < a.length && j < b.length) {
      if (_isDigit(a[i]) && _isDigit(b[j])) {
        var numA = 0;
        while (i < a.length && _isDigit(a[i])) {
          numA = numA * 10 + (a.codeUnitAt(i) - 48);
          i++;
        }
        var numB = 0;
        while (j < b.length && _isDigit(b[j])) {
          numB = numB * 10 + (b.codeUnitAt(j) - 48);
          j++;
        }
        if (numA != numB) return numA.compareTo(numB);
      } else {
        if (a[i] != b[j]) return a[i].compareTo(b[j]);
        i++;
        j++;
      }
    }
    return a.length.compareTo(b.length);
  }

  bool _isDigit(String s) =>
      s.isNotEmpty && s.codeUnitAt(0) >= 48 && s.codeUnitAt(0) <= 57;

  Future<void> run() async {
    if (testDir == null) {
      print('Test directory not specified');
      return;
    }

    final dir = Directory(testDir!);
    if (!dir.existsSync()) {
      print('Test directory not found: $testDir');
      return;
    }

    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.js'))
        .toList();

    files.sort((a, b) => _naturalCompare(a.path, b.path));

    final stopwatch = Stopwatch()..start();

    for (final file in files) {
      final relPath = _getRelativePath(file.path);
      if (_shouldExclude(relPath)) {
        testExcluded++;
        continue;
      }

      await _runTest(file);
      _showProgress();
    }

    stopwatch.stop();

    if (reportPath != null) {
      final reportFile = File(reportPath!);
      if (reportPath!.endsWith('.md')) {
        _writeMarkdownReport(reportFile);
      } else {
        final encoder = JsonEncoder.withIndent('  ');
        reportFile.writeAsStringSync(encoder.convert(results));
      }
      print('\nReport written to $reportPath');
    }

    print('\n');
    if (skipFeatureCounts.isNotEmpty) {
      print('${"SKIPPED FEATURE".padRight(30)} COUNT');
      final sortedFeatures = skipFeatureCounts.keys.toList()..sort();
      for (final f in sortedFeatures) {
        print('${f.padRight(30)} ${skipFeatureCounts[f]}');
      }
      print('');
    }

    print(
      'Result: $testFailed/$testCount errors, $testExcluded excluded, $testSkipped skipped',
    );
    if (showTimings) {
      print(
        'Total time: ${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(3)}s',
      );
    }
  }

  void _recordResult(
    String filename,
    bool strict,
    String status, [
    String? error,
  ]) {
    final relPath = _getRelativePath(filename);
    results.putIfAbsent(relPath, () => {});
    results[relPath]![strict ? 'strict' : 'non-strict'] = {
      'status': status,
      'error': ?error,
    };
  }

  void _writeMarkdownReport(File file) {
    final buffer = StringBuffer();
    buffer.writeln('# Test262 Compliance Report');
    buffer.writeln();
    buffer.writeln('Generated on: ${DateTime.now()}');
    buffer.writeln();
    buffer.writeln('## Summary');
    buffer.writeln();
    buffer.writeln('- **Total Tests**: $testCount');
    buffer.writeln('- **Failed**: $testFailed');
    buffer.writeln('- **Skipped**: $testSkipped');
    buffer.writeln('- **Excluded**: $testExcluded');
    buffer.writeln();
    buffer.writeln('## Results');
    buffer.writeln();
    buffer.writeln('| Test File | Non-Strict | Strict |');
    buffer.writeln('|-----------|------------|--------|');

    final sortedFiles = results.keys.toList()..sort();
    for (final fileName in sortedFiles) {
      final nonStrict = results[fileName]?['non-strict']?['status'] ?? '-';
      final strict = results[fileName]?['strict']?['status'] ?? '-';

      String formatStatus(String status) {
        if (status == 'pass') return '✅ Pass';
        if (status == 'fail') return '❌ Fail';
        if (status == 'skip') return '⏩ Skip';
        return status;
      }

      buffer.writeln(
        '| $fileName | ${formatStatus(nonStrict)} | ${formatStatus(strict)} |',
      );
    }

    file.writeAsStringSync(buffer.toString());
  }

  String _getRelativePath(String path) {
    if (testDir != null && path.startsWith(testDir!)) {
      return path.substring(testDir!.length).replaceAll(r'\', '/');
    }
    return path;
  }

  bool _shouldExclude(String path) {
    final relPath = _getRelativePath(path);
    for (final exclude in excludeList) {
      if (relPath.contains(exclude)) return true;
    }
    for (final dir in excludeDirList) {
      if (relPath.contains(dir)) return true;
    }
    return false;
  }

  void _showProgress() {
    if (compact) {
      stdout.write('.');
      if (testCount % 60 == 0) {
        stdout.write(' $testFailed/$testCount/$testSkipped\n');
      }
    } else {
      stdout.write('\r$testFailed/$testCount/$testSkipped \x1b[K');
    }
  }

  Future<void> _runTest(File file) async {
    final content = file.readAsStringSync();
    final metadata = _parseMetadata(content);

    for (final f in metadata.features) {
      if (skipFeatures.contains(f)) {
        skipFeatureCounts[f] = (skipFeatureCounts[f] ?? 0) + 1;
        testSkipped++;
        _recordResult(file.path, false, 'skip', 'Feature: $f');
        _recordResult(file.path, true, 'skip', 'Feature: $f');
        return;
      }
    }

    bool skip = false;
    bool onlyStrict = metadata.flags.contains('onlyStrict');
    bool noStrict =
        metadata.flags.contains('noStrict') || metadata.flags.contains('raw');
    bool isModule = metadata.flags.contains('module');

    switch (testMode) {
      case TestMode.strict:
        if (noStrict) skip = true;
        break;
      case TestMode.noStrict:
        if (onlyStrict) skip = true;
        break;
      default:
        break;
    }

    if (skip) {
      testSkipped++;
      _recordResult(file.path, false, 'skip', 'Test mode skip');
      _recordResult(file.path, true, 'skip', 'Test mode skip');
      return;
    }

    testCount++;

    bool useStrict = false;
    bool useNoStrict = false;

    switch (testMode) {
      case TestMode.defaultNoStrict:
        if (onlyStrict) {
          useStrict = true;
        } else {
          useNoStrict = true;
        }
        break;
      case TestMode.defaultStrict:
        if (noStrict) {
          useNoStrict = true;
        } else {
          useStrict = true;
        }
        break;
      case TestMode.noStrict:
        useNoStrict = true;
        break;
      case TestMode.strict:
        useStrict = true;
        break;
      case TestMode.all:
        if (isModule) {
          useNoStrict = true;
        } else {
          if (!noStrict) useStrict = true;
          if (!onlyStrict) useNoStrict = true;
        }
        break;
    }

    final stopwatch = Stopwatch();
    if (useNoStrict) {
      stopwatch.start();
      try {
        await _execute(
          file.path,
          content,
          metadata,
          false,
        ).timeout(Duration(milliseconds: timeoutMs));
      } on TimeoutException {
        _reportFailure(file.path, 'Execution timed out', false);
      } catch (e) {
        // Other errors are already handled in _execute
      }
      stopwatch.stop();
      _reportSlowTest(file.path, stopwatch.elapsedMilliseconds, false);
    }
    if (useStrict) {
      stopwatch.reset();
      stopwatch.start();
      try {
        await _execute(
          file.path,
          content,
          metadata,
          true,
        ).timeout(Duration(milliseconds: timeoutMs));
      } on TimeoutException {
        _reportFailure(file.path, 'Execution timed out', true);
      } catch (e) {
        // Other errors are already handled in _execute
      }
      stopwatch.stop();
      _reportSlowTest(file.path, stopwatch.elapsedMilliseconds, true);
    }
  }

  void _reportSlowTest(String path, int ms, bool strict) {
    if (showTimings && ms >= slowTestThreshold) {
      print('\n$path ${strict ? "(strict)" : ""}: $ms ms');
    }
  }

  Future<void> _execute(
    String filename,
    String content,
    TestMetadata metadata,
    bool strict,
  ) async {
    final interpreter = JSInterpreter();

    // Register test262 helpers
    final helperObj = _createTest262Object(interpreter);
    interpreter.registerGlobal('\$262', helperObj);

    // Some tests use 'global' directly instead of $262.global
    interpreter.eval('var global = this;');
    interpreter.eval('var print = function(msg) { \$262.print(msg); };');

    try {
      _loadHarness(interpreter, 'sta.js');
      _loadHarness(interpreter, 'assert.js');
      for (final include in metadata.includes) {
        if (!harnessExclude.contains(include)) {
          _loadHarness(interpreter, include);
        }
      }
      if (metadata.flags.contains('async')) {
        _loadHarness(interpreter, 'doneprintHandle.js');
      }
    } catch (e) {
      _reportFailure(filename, 'Harness error: $e', strict);
      return;
    }

    String code = content;
    if (strict && !content.contains('use strict')) {
      code = '"use strict";\n$code';
    }

    bool asyncCompleted = false;
    interpreter.onMessage('print', (msg) {
      if (msg == 'Test262:AsyncTestComplete') {
        asyncCompleted = true;
      } else if (verbose) {
        print('JS Output: $msg');
      }
    });

    try {
      // For tests with negative phase:parse, we need to catch parsing errors separately
      if (metadata.negativePhase == 'parse' && metadata.negativeType != null) {
        try {
          // Try to parse the code to detect parse-phase errors
          if (metadata.flags.contains('module')) {
            await interpreter.loadModule(filename);
          } else {
            interpreter.eval(code);
          }
          // If parsing succeeded but error was expected, that's a failure
          _reportFailure(
            filename,
            'Expected parse error ${metadata.negativeType} but none thrown',
            strict,
          );
        } catch (e) {
          // Parse error occurred - check if it matches expected type
          final errorStr = e.toString();
          if (errorStr.contains(metadata.negativeType!)) {
            _recordResult(filename, strict, 'pass');
          } else {
            _reportFailure(
              filename,
              'Expected parse error ${metadata.negativeType} but got: $e',
              strict,
            );
          }
        }
      } else {
        // Normal execution path
        if (metadata.flags.contains('module')) {
          await interpreter.loadModule(filename);
        } else {
          interpreter.eval(code);
        }

        if (metadata.flags.contains('async')) {
          // Process all pending microtasks (Promise callbacks) first
          interpreter.runPendingAsyncTasks();

          // Simple async wait
          int timeout = 0;
          while (!asyncCompleted && timeout < 2000) {
            await Future.delayed(Duration(milliseconds: 10));
            timeout += 10;
            // Continue processing microtasks in each iteration
            interpreter.runPendingAsyncTasks();
          }
          if (!asyncCompleted) {
            throw Exception('\$DONE() not called');
          }
        }

        if (metadata.negativeType != null) {
          _reportFailure(
            filename,
            'Expected error ${metadata.negativeType} but none thrown',
            strict,
          );
        } else {
          _recordResult(filename, strict, 'pass');
        }
      }
    } catch (e) {
      if (metadata.negativePhase != 'parse' && metadata.negativeType != null) {
        final errorStr = e.toString();
        if (errorStr.contains(metadata.negativeType!)) {
          _recordResult(filename, strict, 'pass');
          return;
        } else {
          _reportFailure(
            filename,
            'Expected error ${metadata.negativeType} but got: $e',
            strict,
          );
        }
      } else {
        _reportFailure(filename, 'Unexpected error: $e', strict);
      }
    }
  }

  void _loadHarness(JSInterpreter interpreter, String name) {
    if (harnessDir == null) throw Exception('Harness directory not specified');
    final file = File('$harnessDir/$name');
    if (!file.existsSync()) {
      throw Exception('Harness file not found: $name');
    }
    interpreter.eval(file.readAsStringSync());
  }

  JSValue _createTest262Object(JSInterpreter interpreter) {
    final obj = JSObject();
    obj.setProperty('global', interpreter.eval('this'));
    obj.setProperty('createRealm', interpreter.createRealmFunction());
    obj.setProperty(
      'detachArrayBuffer',
      JSNativeFunction(
        functionName: 'detachArrayBuffer',
        nativeImpl: (args) {
          return JSValueFactory.undefined();
        },
      ),
    );
    obj.setProperty(
      'print',
      JSNativeFunction(
        functionName: 'print',
        nativeImpl: (args) {
          final msg = args.isNotEmpty ? args[0].toString() : '';
          // Directly trigger the onMessage('print') callback via MessageSystem
          MessageSystem(
            interpreter.getInterpreterInstanceId(),
          ).sendMessage('print', msg);
          return JSValueFactory.undefined();
        },
      ),
    );
    return obj;
  }

  void _reportFailure(String filename, String message, bool strict) {
    testFailed++;
    _recordResult(filename, strict, 'fail', message);
    if (verbose) {
      print('\nFAILED: $filename ${strict ? "(strict)" : ""}\n$message\n');
    }
  }

  TestMetadata _parseMetadata(String content) {
    final metadata = TestMetadata();
    final startIdx = content.indexOf('/*---');
    if (startIdx == -1) return metadata;

    final endIdx = content.indexOf('---*/', startIdx);
    if (endIdx == -1) return metadata;

    final yamlContent = content.substring(startIdx + 5, endIdx);
    final lines = yamlContent.split('\n');

    String? currentKey;
    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('includes:')) {
        currentKey = 'includes';
        final val = trimmed.substring(9).trim();
        if (val.startsWith('[') && val.endsWith(']')) {
          metadata.includes.addAll(_parseList(val));
          currentKey = null;
        }
      } else if (trimmed.startsWith('flags:')) {
        currentKey = 'flags';
        final val = trimmed.substring(6).trim();
        if (val.startsWith('[') && val.endsWith(']')) {
          metadata.flags.addAll(_parseList(val));
          currentKey = null;
        }
      } else if (trimmed.startsWith('features:')) {
        currentKey = 'features';
        final val = trimmed.substring(9).trim();
        if (val.startsWith('[') && val.endsWith(']')) {
          metadata.features.addAll(_parseList(val));
          currentKey = null;
        }
      } else if (trimmed.startsWith('negative:')) {
        currentKey = 'negative';
      } else if (trimmed.startsWith('phase:') && currentKey == 'negative') {
        metadata.negativePhase = trimmed.substring(6).trim();
      } else if (trimmed.startsWith('type:') && currentKey == 'negative') {
        metadata.negativeType = trimmed.substring(5).trim();
      } else if (trimmed.startsWith('- ')) {
        final val = trimmed.substring(2).trim();
        if (currentKey == 'includes') metadata.includes.add(val);
        if (currentKey == 'flags') metadata.flags.add(val);
        if (currentKey == 'features') metadata.features.add(val);
      } else if (!line.startsWith(' ') && !line.startsWith('\t')) {
        // If it doesn't start with whitespace and doesn't match a known key,
        // it's a new top-level key we don't care about.
        currentKey = null;
      }
      // If it starts with whitespace, it might be a sub-key like 'phase:' or 'type:'
      // and we should keep the currentKey (especially for 'negative:')
    }

    return metadata;
  }

  List<String> _parseList(String val) {
    return val
        .substring(1, val.length - 1)
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
}

class TestMetadata {
  final List<String> includes = [];
  final List<String> flags = [];
  final List<String> features = [];
  String? negativeType;
  String? negativePhase; // 'parse' or 'execution'
}

void main(List<String> args) async {
  final runner = Test262Runner();

  int i = 0;
  while (i < args.length) {
    final arg = args[i++];
    if (arg == '-h' || arg == '--help') {
      _showHelp();
      return;
    } else if (arg == '-m') {
      if (i < args.length) {
        final modeStr = args[i++];
        runner.testMode = TestMode.values.firstWhere(
          (m) => m.toString().split('.').last == modeStr,
          orElse: () => TestMode.all,
        );
      }
    } else if (arg == '-v') {
      runner.verbose = true;
    } else if (arg == '-c') {
      if (i < args.length) {
        runner.loadConfig(args[i++]);
      }
    } else if (arg == '-a') {
      runner.testMode = TestMode.all;
    } else if (arg == '-all') {
      runner.testDir = 'test262/test';
      runner.harnessDir = 'test262/harness';
    } else if (arg == '-r') {
      if (i < args.length) {
        runner.reportPath = args[i++];
      }
    } else if (arg == '-compact') {
      runner.compact = true;
    } else if (arg == '-T') {
      runner.showTimings = true;
    } else if (arg == '-timeout') {
      if (i < args.length) {
        runner.timeoutMs = int.tryParse(args[i++]) ?? 10000;
      }
    } else if (arg.startsWith('--testdir=')) {
      runner.testDir = arg.substring(10);
    } else if (arg.startsWith('--harnessdir=')) {
      runner.harnessDir = arg.substring(13);
    } else if (!arg.startsWith('-')) {
      if (runner.testDir == null) {
        runner.testDir = arg;
      } else {
        runner.harnessDir ??= arg;
      }
    }
  }

  if (runner.testDir == null || runner.harnessDir == null) {
    print('Error: test directory and harness directory must be specified.');
    _showHelp();
    exit(1);
  }

  await runner.run();
}

// example: dart tool/run_test262.dart -v test262/test/language/statements/if/ test262/harness/
void _showHelp() {
  print('Usage: dart tool/run_test262.dart [options] <testDir> <harnessDir>');
  print('\nOptions:');
  print('  -h, --help       Show this help');
  print('  -v              Verbose: show failures and print output');
  print(
    '  -m <mode>        Test mode: defaultNoStrict, defaultStrict, noStrict, strict, all',
  );
  print('  -a               Run all modes (strict and non-strict)');
  print(
    '  -all             Test everything (uses test262/test and test262/harness)',
  );
  print('  -r <file>        Save results to a JSON report file');
  print('  -c <file>        Load exclude configuration from file');
  print('  -compact         Compact progress display');
  print('  -T               Show timings and slow tests');
  print('  -timeout <ms>    Set test timeout in milliseconds (default: 10000)');
  print('  --testdir=PATH   Set test directory');
  print('  --harnessdir=PATH Set harness directory');
}
