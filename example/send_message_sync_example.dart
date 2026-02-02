/// SendMessage Synchronous Patterns
///
/// Demonstrates synchronous message passing between Dart and JavaScript
/// using sendMessage (non-async version) for simpler, blocking operations.
library;

import 'dart:convert';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  final interpreter = JSInterpreter();

  print('=== Basic Synchronous Message ===');

  // Simple synchronous callback
  interpreter.onMessage('calculate', (dynamic message) {
    final args = message as List;
    final a = args[0] as num;
    final b = args[1] as num;

    return a + b;
  });

  final result1 = interpreter.eval('''
    const result = sendMessage('calculate', 5, 3);
    result;
  ''');
  print('Sync calculation: 5 + 3 = $result1');

  print('\n=== String Processing ===');

  interpreter.onMessage('process', (dynamic message) {
    final args = message as List;
    final text = args[0] as String;
    final operation = args[1] as String;

    switch (operation) {
      case 'upper':
        return text.toUpperCase();
      case 'lower':
        return text.toLowerCase();
      case 'length':
        return text.length;
      case 'reverse':
        return text.split('').reversed.join('');
      default:
        return text;
    }
  });

  final result2 = interpreter.eval('''
    ({
      uppercase: sendMessage('process', 'hello', 'upper'),
      lowercase: sendMessage('process', 'WORLD', 'lower'),
      length: sendMessage('process', 'test', 'length'),
      reversed: sendMessage('process', 'hello', 'reverse')
    });
  ''');
  print('String operations: $result2');

  print('\n=== Data Validation ===');

  interpreter.onMessage('validate', (dynamic message) {
    final args = message as List;
    final value = args[0];
    final type = args[1] as String;

    switch (type) {
      case 'email':
        final email = value as String;
        return email.contains('@') && email.contains('.');
      case 'number':
        return value is num;
      case 'string':
        return value is String;
      case 'length':
        final minLength = args[2] as num;
        return (value as String).length >= minLength;
      default:
        return false;
    }
  });

  final result3 = interpreter.eval('''
    ({
      validEmail: sendMessage('validate', 'user@example.com', 'email'),
      invalidEmail: sendMessage('validate', 'not-an-email', 'email'),
      isNumber: sendMessage('validate', 42, 'number'),
      minLength: sendMessage('validate', 'password123', 'length', 8)
    });
  ''');
  print('Validation: $result3');

  print('\n=== Lookup & Mapping ===');

  final userDatabase = {
    '1': {'name': 'Alice', 'age': 30, 'role': 'admin'},
    '2': {'name': 'Bob', 'age': 25, 'role': 'user'},
    '3': {'name': 'Charlie', 'age': 35, 'role': 'user'},
  };

  interpreter.onMessage('lookup', (dynamic message) {
    final args = message as List;
    final userId = args[0] as String;

    if (userDatabase.containsKey(userId)) {
      return jsonEncode(userDatabase[userId]);
    }

    return jsonEncode({'error': 'User not found'});
  });

  final result4 = interpreter.eval('''
    const user = JSON.parse(sendMessage('lookup', '2'));
    ({
      name: user.name,
      age: user.age,
      role: user.role
    });
  ''');
  print('Database lookup: $result4');

  print('\n=== Configuration Access ===');

  final config = {
    'apiUrl': 'https://api.example.com',
    'version': '1.0.0',
    'debug': true,
    'timeout': 5000,
    'retries': 3,
  };

  interpreter.onMessage('config', (dynamic message) {
    final args = message as List;
    final key = args[0] as String;

    if (config.containsKey(key)) {
      return config[key];
    }

    return null;
  });

  final result5 = interpreter.eval('''
    ({
      api: sendMessage('config', 'apiUrl'),
      version: sendMessage('config', 'version'),
      debug: sendMessage('config', 'debug'),
      timeout: sendMessage('config', 'timeout')
    });
  ''');
  print('Configuration: $result5');

  print('\n=== Array Operations ===');

  interpreter.onMessage('array', (dynamic message) {
    final args = message as List;
    final operation = args[0] as String;
    final data = args[1] as List;
    final numData = data
        .map((e) => (e is num) ? e : double.parse(e.toString()))
        .toList();

    switch (operation) {
      case 'sum':
        return numData.fold<num>(0, (a, b) => a + b);
      case 'average':
        final sum = numData.fold<num>(0, (a, b) => a + b);
        return sum / numData.length;
      case 'max':
        return numData.reduce((a, b) => a > b ? a : b);
      case 'min':
        return numData.reduce((a, b) => a < b ? a : b);
      case 'count':
        return numData.length;
      default:
        return 0;
    }
  });

  final result6 = interpreter.eval('''
    const numbers = [10, 20, 30, 40, 50];
    ({
      sum: sendMessage('array', 'sum', numbers),
      average: sendMessage('array', 'average', numbers),
      max: sendMessage('array', 'max', numbers),
      min: sendMessage('array', 'min', numbers),
      count: sendMessage('array', 'count', numbers)
    });
  ''');
  print('Array operations: $result6');

  print('\n=== Currency Conversion ===');

  final exchangeRates = {
    'USD': 1.0,
    'EUR': 0.85,
    'GBP': 0.73,
    'JPY': 110.0,
    'CAD': 1.25,
  };

  interpreter.onMessage('convert', (dynamic message) {
    final args = message as List;
    final amount = args[0] as num;
    final from = args[1] as String;
    final to = args[2] as String;

    if (!exchangeRates.containsKey(from) || !exchangeRates.containsKey(to)) {
      return -1;
    }

    final inUsd = amount / exchangeRates[from]!;
    final converted = inUsd * exchangeRates[to]!;
    return (converted * 100).round() / 100; // Round to 2 decimals
  });

  final result7 = interpreter.eval('''
    ({
      usdToEur: sendMessage('convert', 100, 'USD', 'EUR'),
      eurToGbp: sendMessage('convert', 50, 'EUR', 'GBP'),
      gbpToJpy: sendMessage('convert', 10, 'GBP', 'JPY'),
      cadToUsd: sendMessage('convert', 125, 'CAD', 'USD')
    });
  ''');
  print('Currency conversion: $result7');

  print('\n=== Template Generation ===');

  interpreter.onMessage('template', (dynamic message) {
    final args = message as List;
    final name = args[0] as String;
    final format = args[1] as String;

    switch (format) {
      case 'greeting':
        return 'Hello, $name!';
      case 'email':
        return 'Dear $name,\n\nBest regards';
      case 'title':
        return 'Mr./Ms. $name';
      case 'welcome':
        return 'Welcome to our service, $name! We\'re glad to have you.';
      default:
        return 'Name: $name';
    }
  });

  final result8 = interpreter.eval('''
    ({
      greeting: sendMessage('template', 'Alice', 'greeting'),
      title: sendMessage('template', 'Smith', 'title'),
      welcome: sendMessage('template', 'Bob', 'welcome')
    });
  ''');
  print('Templates: $result8');

  print('\n=== Hash & Encoding ===');

  interpreter.onMessage('hash', (dynamic message) {
    final args = message as List;
    final operation = args[0] as String;
    final value = args[1] as String;

    switch (operation) {
      case 'length':
        return value.length;
      case 'charCodes':
        return value.codeUnits.reduce((a, b) => a + b);
      case 'toBase64':
        // Simple encoding simulation
        return 'b64_${value.length}_chars';
      case 'hash':
        // Simple hash simulation
        return value.hashCode.toRadixString(16);
      default:
        return null;
    }
  });

  final result9 = interpreter.eval('''
    ({
      length: sendMessage('hash', 'length', 'hello world'),
      charCodes: sendMessage('hash', 'charCodes', 'hello'),
      base64: sendMessage('hash', 'toBase64', 'secret'),
      hash: sendMessage('hash', 'hash', 'password123')
    });
  ''');
  print('Hash & Encoding: $result9');

  print('\n=== Format Detection ===');

  interpreter.onMessage('detect', (dynamic message) {
    final args = message as List;
    final value = args[0] as String;

    if (RegExp(r'^\d+$').hasMatch(value)) {
      return 'integer';
    } else if (RegExp(r'^\d+\.\d+$').hasMatch(value)) {
      return 'decimal';
    } else if (RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(value)) {
      return 'email';
    } else if (RegExp(r'^\d{3}-\d{3}-\d{4}$').hasMatch(value)) {
      return 'phone';
    } else if (RegExp(r'^https?://').hasMatch(value)) {
      return 'url';
    }

    return 'text';
  });

  final result10 = interpreter.eval('''
    ({
      value1: sendMessage('detect', '12345'),
      value2: sendMessage('detect', '3.14'),
      value3: sendMessage('detect', 'user@example.com'),
      value4: sendMessage('detect', '555-123-4567'),
      value5: sendMessage('detect', 'https://example.com'),
      value6: sendMessage('detect', 'hello world')
    });
  ''');
  print('Format detection: $result10');

  print('\n=== Cache Access (Sync) ===');

  final cache = <String, dynamic>{};

  interpreter.onMessage('cache', (dynamic message) {
    final args = message as List;
    final operation = args[0] as String;

    switch (operation) {
      case 'set':
        final key = args[1] as String;
        final value = args[2];
        cache[key] = value;
        return 'Cached';
      case 'get':
        final key = args[1] as String;
        return cache[key] ?? 'not_found';
      case 'has':
        final key = args[1] as String;
        return cache.containsKey(key);
      case 'delete':
        final key = args[1] as String;
        cache.remove(key);
        return 'Deleted';
      case 'clear':
        cache.clear();
        return 'Cleared';
      case 'size':
        return cache.length;
      default:
        return null;
    }
  });

  final result11 = interpreter.eval('''
    sendMessage('cache', 'set', 'user1', 'Alice');
    sendMessage('cache', 'set', 'user2', 'Bob');
    
    ({
      has1: sendMessage('cache', 'has', 'user1'),
      has3: sendMessage('cache', 'has', 'user3'),
      get1: sendMessage('cache', 'get', 'user1'),
      size: sendMessage('cache', 'size'),
      get3: sendMessage('cache', 'get', 'user3')
    });
  ''');

  print('Cache operations: $result11');

  print('\n=== Cleanup ===');
  interpreter.removeChannel('calculate');
  interpreter.removeChannel('process');
  interpreter.removeChannel('validate');
  interpreter.removeChannel('lookup');
  interpreter.removeChannel('config');
  interpreter.removeChannel('array');
  interpreter.removeChannel('convert');
  interpreter.removeChannel('template');
  interpreter.removeChannel('hash');
  interpreter.removeChannel('detect');
  interpreter.removeChannel('cache');

  print('Done!');
}
