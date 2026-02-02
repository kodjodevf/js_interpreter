# js_interpreter

[![Pub package](https://img.shields.io/pub/v/js_interpreter.svg)](https://pub.dev/packages/js_interpreter)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A comprehensive, pure Dart implementation of a JavaScript interpreter supporting **ES6+** features. Perfect for embedding JavaScript execution in Dart/Flutter applications.

## ✨ Features

### 🚀 Core Capabilities

- **Full JavaScript Parsing** - Complete lexer and parser supporting modern JavaScript syntax
- **Async/Await Support** - Native async function execution with Promise integration
- **Module System** - ES6 modules with `import`/`export`
- **Class System** - Full ES6+ class support including private fields and static blocks
- **Generators** - `function*` and `yield`/`yield*` support
- **Iterators** - Full iterator protocol implementation
- **Proxy/Reflect** - Complete metaprogramming support
- **TypedArrays** - All typed array types (`Int8Array`, `Uint8Array`, `Float32Array`, etc.)
- **RegExp** - Full regular expression support with ES2022 features
- **Strict Mode** - Automatic and explicit strict mode handling

> **For detailed feature coverage and use cases**, check the [test suite](test/) for comprehensive examples.

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  js_interpreter: ^0.0.1
```

Or install via command line:

```bash
dart pub add js_interpreter
```

## 🔧 Quick Start

### Basic Usage

```dart
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  final interpreter = JSInterpreter();
  
  // Evaluate JavaScript code
  final result = interpreter.eval('''
    const greeting = "Hello";
    const name = "World";
    greeting + ", " + name + "!";
  ''');
  
  print(result); // Hello, World!
}
```

### Async/Await Support

```dart
import 'package:js_interpreter/js_interpreter.dart';

void main() async {
  final interpreter = JSInterpreter();
  
  final result = await interpreter.evalAsync('''
    async function fetchData() {
      const response = await Promise.resolve({ data: "Hello Async!" });
      return response.data;
    }
    
    await fetchData();
  ''');
  
  print(result); // Hello Async!
}
```

### Convert to Dart Types

```dart
import 'package:js_interpreter/js_interpreter.dart';

void main() async {
  final interpreter = JSInterpreter();
  
  // Returns native Dart types (String, int, double, List, Map, etc.)
  final result = await interpreter.evalAsyncToDart('''
    const data = {
      name: "Alice",
      age: 30,
      hobbies: ["reading", "coding"]
    };
    JSON.stringify(data);
  ''');
  
  print(result); // {"name":"Alice","age":30,"hobbies":["reading","coding"]}
  print(result.runtimeType); // String
}
```

### ES6 Modules

```dart
import 'package:js_interpreter/js_interpreter.dart';

void main() async {
  final interpreter = JSInterpreter();
  
  // Register a module
  interpreter.registerModule('math-utils', '''
    export function add(a, b) { return a + b; }
    export function multiply(a, b) { return a * b; }
    export const PI = 3.14159;
  ''');
  
  // Use the module
  final result = await interpreter.evalModuleAsync('''
    import { add, multiply, PI } from 'math-utils';
    
    const sum = add(5, 3);
    const product = multiply(4, PI);
    
    export default { sum, product };
  ''');
  
  print(result); // {sum: 8, product: 12.56636}
}
```

### Dart-JS Interop

```dart
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  final interpreter = JSInterpreter();
  
  // Inject Dart function into JavaScript
  interpreter.setGlobal('dartPrint', (List<JSValue> args) {
    print('From Dart: ${args.first}');
    return JSValueFactory.undefined();
  });
  
  interpreter.eval('''
    dartPrint("Hello from JavaScript!");
  ''');
  // Output: From Dart: Hello from JavaScript!
}
```

### Messaging System: sendMessage & sendMessageAsync

The interpreter provides a powerful bidirectional messaging system for complex Dart-JavaScript interactions.

#### sendMessage (Synchronous)

```dart
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  final interpreter = JSInterpreter();
  
  // Register a message handler
  interpreter.onMessage('greet', (dynamic message) {
    final name = message as String;
    return 'Hello, $name!';
  });
  
  // Call from JavaScript (synchronous)
  final result = interpreter.eval('''
    const greeting = sendMessage('greet', 'Alice');
    greeting; // "Hello, Alice!"
  ''');
  
  print(result);
}
```

#### sendMessageAsync (Asynchronous)

For async operations that require waiting for results:

```dart
import 'package:js_interpreter/js_interpreter.dart';

void main() async {
  final interpreter = JSInterpreter();
  
  // Register an async message handler
  interpreter.onMessage('fetchUser', (dynamic message) async {
    final userId = message as int;
    // Simulate async operation
    await Future.delayed(Duration(milliseconds: 100));
    return {
      'id': userId,
      'name': 'Alice',
      'email': 'alice@example.com'
    };
  });
  
  // Call from JavaScript (asynchronous)
  final result = await interpreter.evalAsync('''
    async function loadUser() {
      const user = await sendMessageAsync('fetchUser', 1);
      return user.email;
    }
    
    await loadUser();
  ''');
  
  print(result); // "alice@example.com"
}
```

#### Advanced Patterns

**Message Handlers with Multiple Arguments:**

```dart
interpreter.onMessage('calculate', (dynamic message) {
  final args = message as List;
  final operation = args[0] as String;
  final a = args[1] as num;
  final b = args[2] as num;
  
  switch (operation) {
    case 'add': return a + b;
    case 'multiply': return a * b;
    default: return null;
  }
});

// In JavaScript:
final result = interpreter.eval('''
  sendMessage('calculate', 'add', 5, 3); // 8
  sendMessage('calculate', 'multiply', 4, 7); // 28
''');
```

**Async Pipeline with Promise.all:**

```dart
interpreter.onMessage('fetchData', (dynamic message) async {
  final source = message as String;
  await Future.delayed(Duration(milliseconds: 50));
  return {'source': source, 'data': [1, 2, 3]};
});

final result = await interpreter.evalAsync('''
  const results = await Promise.all([
    sendMessageAsync('fetchData', 'database'),
    sendMessageAsync('fetchData', 'api'),
    sendMessageAsync('fetchData', 'cache')
  ]);
  
  results.map(r => r.source);
''');
// ['database', 'api', 'cache']
```

**Error Handling:**

```dart
interpreter.onMessage('riskyOperation', (dynamic message) {
  if (message == 'fail') {
    throw Exception('Operation failed');
  }
  return 'Success';
});

// In JavaScript:
final result = await interpreter.evalAsync('''
  try {
    const result1 = await sendMessageAsync('riskyOperation', 'ok');
    const result2 = await sendMessageAsync('riskyOperation', 'fail');
  } catch (error) {
    console.log('Caught:', error.message);
  }
''');
```

## 📚 API Reference

### JSInterpreter

The main class for JavaScript interpretation.

| Method | Description |
|--------|-------------|
| `eval(String code)` | Synchronously evaluate JavaScript code |
| `evalAsync(String code)` | Asynchronously evaluate JavaScript code (returns `Future<JSValue>`) |
| `evalAsyncToDart(String code)` | Asynchronously evaluate and convert result to Dart types |
| `evalModule(String code)` | Evaluate as ES6 module |
| `evalModuleAsync(String code)` | Asynchronously evaluate as ES6 module |
| `registerModule(String name, String code)` | Register a module for import |
| `setGlobal(String name, dynamic value)` | Set a global variable |
| `getGlobal(String name)` | Get a global variable |
| `onMessage(String channel, dynamic callback)` | Register a message handler for a specific channel |

### Global Functions (JavaScript Context)

| Function | Description |
|----------|-------------|
| `sendMessage(String channel, [arg1, arg2, ...])` | Send a synchronous message to Dart and get a result |
| `sendMessageAsync(String channel, [arg1, arg2, ...])` | Send an asynchronous message to Dart (returns Promise) |

### JSValue Types

| Type | Description |
|------|-------------|
| `JSUndefined` | JavaScript undefined |
| `JSNull` | JavaScript null |
| `JSBoolean` | JavaScript boolean |
| `JSNumber` | JavaScript number (int or double) |
| `JSString` | JavaScript string |
| `JSBigInt` | JavaScript BigInt |
| `JSSymbol` | JavaScript Symbol |
| `JSObject` | JavaScript object |
| `JSArray` | JavaScript array |
| `JSFunction` | JavaScript function |
| `JSClass` | JavaScript class |
| `JSGenerator` | JavaScript generator |
| `JSAsyncGenerator` | JavaScript async generator |
| `JSPromise` | JavaScript Promise |
| `JSRegExp` | JavaScript RegExp |
| `JSDate` | JavaScript Date |
| `JSError` | JavaScript Error (and all error types) |

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

Made with ❤️ in Dart
