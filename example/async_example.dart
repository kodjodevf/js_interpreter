/// Asynchronous JavaScript evaluation with sendMessageAsync
///
/// This example demonstrates async/await with sendMessageAsync patterns,
/// showing how to integrate Dart callbacks with JavaScript async code.
library;

import 'dart:convert';
import 'package:js_interpreter/js_interpreter.dart';

void main() async {
  final interpreter = JSInterpreter();

  print('=== Basic SendMessageAsync Pattern ===');

  // Register a simple Dart callback
  interpreter.onMessage('greet', (dynamic message) async {
    final args = message as List;
    final name = args[0] as String;
    await Future.delayed(Duration(milliseconds: 10));
    return 'Hello, $name!';
  });

  final result1 = await interpreter.evalAsync('''
    async function sayHello() {
      const greeting = await sendMessageAsync('greet', 'Alice');
      return greeting;
    }
    sayHello();
  ''');
  print('Greeting: $result1');

  print('\n=== Database-like Operations ===');

  // Simulate database operations
  interpreter.onMessage('database', (dynamic message) async {
    final args = message as List;
    final operation = args[0] as String;

    await Future.delayed(Duration(milliseconds: 20));

    switch (operation) {
      case 'getUser':
        return jsonEncode({
          'id': 1,
          'name': 'Alice',
          'email': 'alice@example.com',
        });
      case 'getUserPosts':
        return jsonEncode([
          {'id': 1, 'title': 'First Post', 'likes': 42},
          {'id': 2, 'title': 'Second Post', 'likes': 35},
        ]);
      default:
        return jsonEncode({'error': 'Unknown operation'});
    }
  });

  final result2 = await interpreter.evalAsync('''
    async function fetchUserData() {
      const userJson = await sendMessageAsync('database', 'getUser');
      const user = JSON.parse(userJson);
      
      const postsJson = await sendMessageAsync('database', 'getUserPosts');
      const posts = JSON.parse(postsJson);
      
      return {
        user: user.name,
        email: user.email,
        postCount: posts.length,
        totalLikes: posts.reduce((sum, p) => sum + p.likes, 0)
      };
    }
    fetchUserData();
  ''');
  print('User Data: $result2');

  print('\n=== Sequential Pipeline Processing ===');

  var pipelineStep = 0;

  interpreter.onMessage('process', (dynamic message) async {
    final args = message as List;
    final step = args[0] as String;
    final value = args[1] as num;

    pipelineStep++;
    await Future.delayed(Duration(milliseconds: 15));

    switch (step) {
      case 'multiply':
        return value * 2;
      case 'add':
        return value + 10;
      case 'divide':
        return value / 2;
      default:
        return value;
    }
  });

  final result3 = await interpreter.evalAsync('''
    async function pipeline(initialValue) {
      // Process: (5 * 2) + 10 / 2 = 10
      let value = initialValue;
      
      value = await sendMessageAsync('process', 'multiply', value);
      console.log('After multiply:', value);
      
      value = await sendMessageAsync('process', 'add', value);
      console.log('After add:', value);
      
      value = await sendMessageAsync('process', 'divide', value);
      console.log('After divide:', value);
      
      return value;
    }
    pipeline(5);
  ''');
  print('Pipeline result: $result3 (steps executed: $pipelineStep)');

  print('\n=== Concurrent Batch Processing ===');

  interpreter.onMessage('batch', (dynamic message) async {
    final args = message as List;
    final items = args[0] as List;

    await Future.delayed(Duration(milliseconds: 30));

    final processed = items.map((item) => 'Processed: $item').toList();
    return jsonEncode(processed);
  });

  final result4 = await interpreter.evalAsync('''
    async function processBatch() {
      const items = ['item1', 'item2', 'item3'];
      const resultJson = await sendMessageAsync('batch', items);
      const results = JSON.parse(resultJson);
      return results.length;
    }
    processBatch();
  ''');
  print('Batch processed: $result4 items');

  print('\n=== Error Handling in Callbacks ===');

  interpreter.onMessage('validate', (dynamic message) async {
    final args = message as List;
    final value = args[0] as String;

    await Future.delayed(Duration(milliseconds: 10));

    if (value.isEmpty) {
      throw Exception('Value cannot be empty');
    }

    return 'Valid: $value';
  });

  final result5 = await interpreter.evalAsync('''
    async function validateInput() {
      try {
        const result = await sendMessageAsync('validate', '');
        return result;
      } catch (error) {
        return 'Error caught: ' + error;
      }
    }
    validateInput();
  ''');
  print('Validation: $result5');

  print('\n=== Promise.all with Multiple Async Calls ===');

  interpreter.onMessage('fetch', (dynamic message) async {
    final args = message as List;
    final resource = args[0] as String;

    await Future.delayed(Duration(milliseconds: 20));

    return jsonEncode({
      'resource': resource,
      'data': 'Data from $resource',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  });

  final result6 = await interpreter.evalAsync('''
    async function fetchMultiple() {
      const [usersJson, postsJson, commentsJson] = await Promise.all([
        sendMessageAsync('fetch', 'users'),
        sendMessageAsync('fetch', 'posts'),
        sendMessageAsync('fetch', 'comments')
      ]);
      
      const users = JSON.parse(usersJson);
      const posts = JSON.parse(postsJson);
      const comments = JSON.parse(commentsJson);
      
      return {
        fetchedResources: 3,
        resources: [users.resource, posts.resource, comments.resource]
      };
    }
    fetchMultiple();
  ''');
  print('Parallel fetches: $result6');

  print('\n=== Cleanup ===');
  interpreter.removeChannel('greet');
  interpreter.removeChannel('database');
  interpreter.removeChannel('process');
  interpreter.removeChannel('batch');
  interpreter.removeChannel('validate');
  interpreter.removeChannel('fetch');

  print('Done!');
}
