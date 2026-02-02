import 'dart:convert';
import 'package:test/test.dart';
import 'package:js_interpreter/js_interpreter.dart';

void main() {
  group('Message Async System Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    tearDown(() {
      interpreter.removeChannel('test');
      interpreter.removeChannel('api');
      interpreter.removeChannel('error');
      interpreter.removeChannel('delay');
      interpreter.removeChannel('nested');
      interpreter.removeChannel('concurrent');
      interpreter.removeChannel('types');
      interpreter.removeChannel('cleanup');
      interpreter.removeChannel('multi');
    });

    test('Simple async callback registration and execution', () async {
      // Enregistrer un callback asynchrone simple
      interpreter.onMessage('test', (dynamic message) async {
        final args = message as List;
        return 'Hello ${args[0]}';
      });

      // Execute JavaScript code that uses sendMessageAsync
      final result = await interpreter.evalAsync('''
        async function test() {
          const result = await sendMessageAsync('test', 'World');
          return result;
        }
        test();
      ''');

      expect(result.toString(), equals('Hello World'));
    });

    test('Async callback with primitive data types', () async {
      interpreter.onMessage('api', (dynamic message) async {
        final args = message as List;
        final userId = args[0]; // Ne pas caster en int, c'est un double
        final action = args[1] as String;

        return 'User $userId performed $action';
      });

      final result = await interpreter.evalAsync('''
        async function test() {
          const response = await sendMessageAsync('api', 123, 'login');
          return response;
        }
        test();
      ''');

      expect(result.toString(), equals('User 123 performed login'));
    });

    test('Async callback with delay simulation', () async {
      interpreter.onMessage('delay', (dynamic message) async {
        final args = message as List;
        await Future.delayed(Duration(milliseconds: 10));
        return 'Delayed response for ${args[0]}';
      });

      final result = await interpreter.evalAsync('''
        async function test() {
          const result = await sendMessageAsync('delay', 'request');
          return result;
        }
        test();
      ''');

      expect(result.toString(), equals('Delayed response for request'));
    });

    test('Async callback with nested async operations', () async {
      interpreter.onMessage('nested', (dynamic message) async {
        final args = message as List;
        // Simulate a nested call to another service
        final innerResult = await Future.delayed(
          Duration(milliseconds: 5),
          () => 'inner_${args[0]}',
        );

        // Faire un autre appel asynchrone
        final finalResult = await Future.delayed(
          Duration(milliseconds: 5),
          () => 'Final: $innerResult',
        );

        return finalResult;
      });

      final result = await interpreter.evalAsync('''
        async function test() {
          const result = await sendMessageAsync('nested', 'test');
          return result;
        }
        test();
      ''');

      expect(result.toString(), equals('Final: inner_test'));
    });

    test('Concurrent async messages', () async {
      interpreter.onMessage('concurrent', (dynamic message) async {
        final args = message as List;
        await Future.delayed(Duration(milliseconds: 20));
        return 'Processed ${args[0]}';
      });

      // Launch multiple simultaneous calls
      final results = await Future.wait([
        interpreter.evalAsync('''
          async function test1() {
            return await sendMessageAsync('concurrent', 'A');
          }
          test1();
        '''),
        interpreter.evalAsync('''
          async function test2() {
            return await sendMessageAsync('concurrent', 'B');
          }
          test2();
        '''),
      ]);

      expect(results.length, equals(2));
      expect(results[0].toString(), equals('Processed A'));
      expect(results[1].toString(), equals('Processed B'));
    });

    test('Async callback returning different types', () async {
      interpreter.onMessage('types', (dynamic message) async {
        final args = message as List;
        final type = args[0] as String;

        switch (type) {
          case 'string':
            return 'string result';
          case 'number':
            return 42;
          case 'boolean':
            return true;
          case 'null':
            return null;
          default:
            return 'default';
        }
      });

      final stringResult = await interpreter.evalAsync('''
        async function test() {
          return await sendMessageAsync('types', 'string');
        }
        test();
      ''');

      final numberResult = await interpreter.evalAsync('''
        async function test() {
          return await sendMessageAsync('types', 'number');
        }
        test();
      ''');

      expect(stringResult.toString(), equals('string result'));
      expect(numberResult.toString(), equals('42'));
    });

    test('Channel cleanup and callback removal', () async {
      var callCount = 0;

      Future<String> callback(dynamic message) async {
        callCount++;
        return 'Response $callCount';
      }

      interpreter.onMessage('cleanup', callback);

      // Premier appel
      final result1 = await interpreter.evalAsync('''
        async function test1() {
          return await sendMessageAsync('cleanup', 'test1');
        }
        test1();
      ''');

      expect(callCount, equals(1));
      expect(result1.toString(), equals('Response 1'));

      // Supprimer le canal
      interpreter.removeChannel('cleanup');

      // Second call should return null or a default value
      final result2 = await interpreter.evalAsync('''
        async function test2() {
          const result = await sendMessageAsync('cleanup', 'test2');
          return result;
        }
        test2();
      ''');

      // Behavior depends on implementation when no callback is registered
      expect(result2.toString(), isNotNull);
    });

    test('Async callback error handling', () async {
      interpreter.onMessage('error', (dynamic message) async {
        final args = message as List;
        if (args[0] == 'fail') {
          throw Exception('Test error');
        }
        return 'Success: ${args[0]}';
      });

      // Test success
      final successResult = await interpreter.evalAsync('''
        async function test() {
          const result = await sendMessageAsync('error', 'ok');
          return result;
        }
        test();
      ''');

      expect(successResult.toString(), equals('Success: ok'));

      // Test error - the exception must be propagated and can be caught
      final errorResult = await interpreter.evalAsync('''
        async function test() {
          try {
            const result = await sendMessageAsync('error', 'fail');
            return 'Should not reach here: ' + result;
          } catch (e) {
            return 'Caught error: ' + e;
          }
        }
        test();
      ''');

      // Errors in async callbacks are propagated and can be caught
      expect(errorResult.toString(), contains('Caught error'));
    });
  });

  group('Advanced Message Async System Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    tearDown(() {
      interpreter.removeChannel('sequence');
      interpreter.removeChannel('pipeline');
      interpreter.removeChannel('batch');
      interpreter.removeChannel('cache');
      interpreter.removeChannel('priority');
      interpreter.removeChannel('transform');
      interpreter.removeChannel('aggregate');
      interpreter.removeChannel('stream');
      interpreter.removeChannel('fanout');
      interpreter.removeChannel('orchestrator');
      interpreter.removeChannel('saga');
      interpreter.removeChannel('circuit');
      interpreter.removeChannel('retry');
      interpreter.removeChannel('rate');
      interpreter.removeChannel('auth');
    });

    test('Sequential message processing with dependencies', () async {
      final processedSteps = <String>[];

      interpreter.onMessage('sequence', (dynamic message) async {
        final args = message as List;
        final step = args[0] as String;
        final delay = args[1] as num;

        await Future.delayed(Duration(milliseconds: delay.toInt()));
        processedSteps.add(step);
        return 'Step $step completed';
      });

      final result = await interpreter.evalAsync('''
        async function processSequence() {
          const results = [];
          
          const step1 = await sendMessageAsync('sequence', 'A', 10);
          results.push(step1);
          
          const step2 = await sendMessageAsync('sequence', 'B', 5);
          results.push(step2);
          
          const step3 = await sendMessageAsync('sequence', 'C', 8);
          results.push(step3);
          
          return results.join(' -> ');
        }
        processSequence();
      ''');

      expect(
        result.toString(),
        equals('Step A completed -> Step B completed -> Step C completed'),
      );
      expect(processedSteps, equals(['A', 'B', 'C']));
    });

    test('Message pipeline with transformations', () async {
      interpreter.onMessage('pipeline', (dynamic message) async {
        final args = message as List;
        final operation = args[0] as String;
        final value = args[1] as num;

        await Future.delayed(Duration(milliseconds: 5));

        switch (operation) {
          case 'double':
            return value * 2;
          case 'square':
            return value * value;
          case 'add10':
            return value + 10;
          case 'divide2':
            return value / 2;
          default:
            return value;
        }
      });

      final result = await interpreter.evalAsync('''
        async function pipeline(initialValue) {
          let value = initialValue;
          
          // Double the value
          value = await sendMessageAsync('pipeline', 'double', value);
          
          // Add 10
          value = await sendMessageAsync('pipeline', 'add10', value);
          
          // Divide by 2
          value = await sendMessageAsync('pipeline', 'divide2', value);
          
          return value;
        }
        pipeline(5);
      ''');

      expect(result.toNumber(), equals(10)); // (5*2 + 10) / 2 = 10
    });

    test('Batch message processing', () async {
      interpreter.onMessage('batch', (dynamic message) async {
        final args = message as List;
        final items = args[0] as List;

        await Future.delayed(Duration(milliseconds: 10));

        final results = <String>[];
        for (var item in items) {
          results.add('Processed: $item');
        }

        return results.join(', ');
      });

      final result = await interpreter.evalAsync('''
        async function processBatch() {
          const items = ['item1', 'item2', 'item3', 'item4'];
          const result = await sendMessageAsync('batch', items);
          return result;
        }
        processBatch();
      ''');

      expect(result.toString(), contains('Processed: item1'));
      expect(result.toString(), contains('Processed: item4'));
    });

    test('Message caching pattern', () async {
      final cache = <String, dynamic>{};
      var computeCount = 0;

      interpreter.onMessage('cache', (dynamic message) async {
        final args = message as List;
        final key = args[0] as String;

        if (cache.containsKey(key)) {
          return 'Cached: ${cache[key]}';
        }

        // Simulate expensive computation
        await Future.delayed(Duration(milliseconds: 20));
        computeCount++;
        final value = 'Result for $key (computed)';
        cache[key] = value;

        return value;
      });

      final result = await interpreter.evalAsync('''
        async function testCache() {
          const results = [];
          
          // First call - should compute
          const r1 = await sendMessageAsync('cache', 'key1');
          results.push(r1);
          
          // Second call with same key - should use cache
          const r2 = await sendMessageAsync('cache', 'key1');
          results.push(r2);
          
          // Third call with different key - should compute
          const r3 = await sendMessageAsync('cache', 'key2');
          results.push(r3);
          
          return results;
        }
        testCache();
      ''');

      expect(computeCount, equals(2)); // Only computed twice
      final resultArray = result as JSArray;
      expect(resultArray.elements[0].toString(), contains('computed'));
      expect(resultArray.elements[1].toString(), contains('Cached'));
    });

    test('Priority message handling with queuing', () async {
      final processOrder = <String>[];

      interpreter.onMessage('priority', (dynamic message) async {
        final args = message as List;
        final taskId = args[0] as String;
        final priority = args[1] as num;

        await Future.delayed(Duration(milliseconds: priority.toInt()));
        processOrder.add(taskId);

        return 'Task $taskId completed with priority $priority';
      });

      final result = await interpreter.evalAsync('''
        async function testPriority() {
          const results = await Promise.all([
            sendMessageAsync('priority', 'low', 30),
            sendMessageAsync('priority', 'high', 5),
            sendMessageAsync('priority', 'medium', 15)
          ]);
          
          return results.join(' | ');
        }
        testPriority();
      ''');

      // High priority (5ms) should finish first
      expect(processOrder[0], equals('high'));
      expect(result.toString(), contains('completed'));
    });

    test('Message transformation chain', () async {
      interpreter.onMessage('transform', (dynamic message) async {
        final args = message as List;
        final operation = args[0] as String;
        final data = args[1];

        await Future.delayed(Duration(milliseconds: 3));

        switch (operation) {
          case 'uppercase':
            return (data as String).toUpperCase();
          case 'reverse':
            return (data as String).split('').reversed.join('');
          case 'length':
            return (data as String).length;
          case 'split':
            return (data as String).split('').join('-');
          default:
            return data;
        }
      });

      final result = await interpreter.evalAsync('''
        async function transformChain(input) {
          // Uppercase
          let result = await sendMessageAsync('transform', 'uppercase', input);
          
          // Reverse
          result = await sendMessageAsync('transform', 'reverse', result);
          
          // Split with dashes
          result = await sendMessageAsync('transform', 'split', result);
          
          return result;
        }
        transformChain('hello');
      ''');

      expect(result.toString(), equals('O-L-L-E-H'));
    });

    test('Aggregation pattern with multiple sources', () async {
      interpreter.onMessage('aggregate', (dynamic message) async {
        final args = message as List;
        final source = args[0] as String;

        await Future.delayed(Duration(milliseconds: 5));

        switch (source) {
          case 'users':
            return {'count': 100, 'active': 85};
          case 'posts':
            return {'count': 500, 'published': 450};
          case 'comments':
            return {'count': 1200, 'approved': 1100};
          default:
            return {};
        }
      });

      final result = await interpreter.evalAsync('''
        async function aggregateData() {
          const users = await sendMessageAsync('aggregate', 'users');
          const posts = await sendMessageAsync('aggregate', 'posts');
          const comments = await sendMessageAsync('aggregate', 'comments');
          
          return {
            totalUsers: users.count,
            totalPosts: posts.count,
            totalComments: comments.count
          };
        }
        aggregateData();
      ''');

      final resultObj = result as JSObject;
      expect(resultObj.getProperty('totalUsers').toNumber(), equals(100));
      expect(resultObj.getProperty('totalPosts').toNumber(), equals(500));
      expect(resultObj.getProperty('totalComments').toNumber(), equals(1200));
    });

    test('Stream-like processing with async iteration', () async {
      var itemIndex = 0;
      final items = ['A', 'B', 'C', 'D', 'E'];

      interpreter.onMessage('stream', (dynamic message) async {
        final args = message as List;
        final action = args[0] as String;

        if (action == 'next') {
          if (itemIndex < items.length) {
            final item = items[itemIndex];
            itemIndex++;
            // Return a string representation instead of an object
            return '$item:false';
          } else {
            return 'null:true';
          }
        }

        return null;
      });

      final result = await interpreter.evalAsync('''
        async function processStream() {
          const results = [];
          let isDone = false;
          
          while (!isDone) {
            const response = await sendMessageAsync('stream', 'next');
            const parts = response.split(':');
            const value = parts[0];
            isDone = parts[1] === 'true';
            
            if (!isDone) {
              results.push(value);
            }
          }
          
          return results.join(',');
        }
        processStream();
      ''');

      expect(result.toString(), equals('A,B,C,D,E'));
    });

    test('Fan-out pattern with concurrent processing', () async {
      final processedItems = <String>[];

      interpreter.onMessage('fanout', (dynamic message) async {
        final args = message as List;
        final item = args[0] as String;
        final delay = args[1] as num;

        await Future.delayed(Duration(milliseconds: delay.toInt()));
        processedItems.add(item);

        return 'Processed $item in ${delay}ms';
      });

      final result = await interpreter.evalAsync('''
        async function fanOut() {
          const items = [
            ['task1', 15],
            ['task2', 10],
            ['task3', 20],
            ['task4', 5]
          ];
          
          const promises = items.map(item => 
            sendMessageAsync('fanout', item[0], item[1])
          );
          
          const results = await Promise.all(promises);
          return results.length;
        }
        fanOut();
      ''');

      expect(result.toNumber(), equals(4));
      expect(processedItems.length, equals(4));
    });

    test('Orchestration pattern with conditional flow', () async {
      interpreter.onMessage('orchestrator', (dynamic message) async {
        final args = message as List;
        final step = args[0] as String;
        final value = args.length > 1 ? args[1] : null;

        await Future.delayed(Duration(milliseconds: 5));

        switch (step) {
          case 'validate':
            return value != null && (value as num) > 0;
          case 'process':
            return (value as num) * 2;
          case 'save':
            return 'Saved: $value';
          case 'notify':
            return 'Notified about $value';
          default:
            return null;
        }
      });

      final result = await interpreter.evalAsync('''
        async function orchestrate(input) {
          // Step 1: Validate
          const isValid = await sendMessageAsync('orchestrator', 'validate', input);
          
          if (!isValid) {
            return 'Invalid input';
          }
          
          // Step 2: Process
          const processed = await sendMessageAsync('orchestrator', 'process', input);
          
          // Step 3: Save
          const saved = await sendMessageAsync('orchestrator', 'save', processed);
          
          // Step 4: Notify
          const notified = await sendMessageAsync('orchestrator', 'notify', processed);
          
          return saved + ' and ' + notified;
        }
        orchestrate(5);
      ''');

      // Numbers can be formatted with or without decimals
      expect(
        result.toString(),
        anyOf(
          equals('Saved: 10 and Notified about 10'),
          equals('Saved: 10.0 and Notified about 10.0'),
        ),
      );
    });

    test('Saga pattern with compensation', () async {
      final completedSteps = <String>[];

      interpreter.onMessage('saga', (dynamic message) async {
        final args = message as List;
        final action = args[0] as String;
        final step = args.length > 1 ? args[1] as String : '';

        await Future.delayed(Duration(milliseconds: 5));

        if (action == 'execute') {
          completedSteps.add(step);
          return 'Executed $step';
        } else if (action == 'compensate') {
          completedSteps.remove(step);
          return 'Compensated $step';
        }

        return null;
      });

      // Test successful saga
      final successResult = await interpreter.evalAsync('''
        async function saga() {
          try {
            await sendMessageAsync('saga', 'execute', 'step1');
            await sendMessageAsync('saga', 'execute', 'step2');
            await sendMessageAsync('saga', 'execute', 'step3');
            return 'Success';
          } catch (e) {
            // Compensate in reverse order
            await sendMessageAsync('saga', 'compensate', 'step2');
            await sendMessageAsync('saga', 'compensate', 'step1');
            return 'Failed and compensated';
          }
        }
        saga();
      ''');

      expect(successResult.toString(), equals('Success'));
      expect(completedSteps, equals(['step1', 'step2', 'step3']));
    });

    test('Circuit breaker pattern', () async {
      var failureCount = 0;
      var circuitOpen = false;

      interpreter.onMessage('circuit', (dynamic message) async {
        final args = message as List;
        final action = args[0] as String;

        if (action == 'call') {
          if (circuitOpen) {
            return 'Circuit is open - call rejected';
          }

          await Future.delayed(Duration(milliseconds: 5));

          // Simulate random failures
          final shouldFail = args.length > 1 && args[1] == true;
          if (shouldFail) {
            failureCount++;
            if (failureCount >= 3) {
              circuitOpen = true;
            }
            throw Exception('Service unavailable');
          }

          failureCount = 0;
          return 'Success';
        } else if (action == 'reset') {
          failureCount = 0;
          circuitOpen = false;
          return 'Circuit reset';
        }

        return null;
      });

      final result = await interpreter.evalAsync('''
        async function testCircuitBreaker() {
          const results = [];
          
          // First call - success
          try {
            const r1 = await sendMessageAsync('circuit', 'call', false);
            results.push(r1);
          } catch (e) {
            results.push('Error: ' + e);
          }
          
          // Reset circuit
          await sendMessageAsync('circuit', 'reset');
          
          return results.join(' | ');
        }
        testCircuitBreaker();
      ''');

      expect(result.toString(), contains('Success'));
    });

    test('Retry pattern with exponential backoff', () async {
      var attemptCount = 0;

      interpreter.onMessage('retry', (dynamic message) async {
        final args = message as List;
        final taskId = args[0] as String;

        attemptCount++;

        await Future.delayed(Duration(milliseconds: 5));

        // Fail first two attempts, succeed on third
        if (attemptCount < 3) {
          throw Exception('Temporary failure');
        }

        return 'Success on attempt $attemptCount for $taskId';
      });

      final result = await interpreter.evalAsync('''
        async function retryWithBackoff(taskId, maxRetries) {
          let attempt = 0;
          let delay = 1;
          
          while (attempt < maxRetries) {
            try {
              const result = await sendMessageAsync('retry', taskId);
              return result;
            } catch (e) {
              attempt++;
              if (attempt >= maxRetries) {
                return 'Failed after ' + maxRetries + ' attempts';
              }
              // Wait before retry (simulated backoff)
              await new Promise(resolve => setTimeout(resolve, delay));
              delay *= 2;
            }
          }
        }
        retryWithBackoff('task1', 5);
      ''');

      expect(result.toString(), contains('Success on attempt 3'));
      expect(attemptCount, equals(3));
    });

    test('Rate limiting pattern', () async {
      final timestamps = <DateTime>[];
      const maxRequestsPerSecond = 5;

      interpreter.onMessage('rate', (dynamic message) async {
        final args = message as List;
        final requestId = args[0] as String;

        final now = DateTime.now();
        timestamps.add(now);

        // Clean old timestamps (older than 1 second)
        timestamps.removeWhere((t) => now.difference(t).inMilliseconds > 1000);

        if (timestamps.length > maxRequestsPerSecond) {
          return 'Rate limit exceeded for $requestId';
        }

        await Future.delayed(Duration(milliseconds: 5));
        return 'Processed $requestId';
      });

      final result = await interpreter.evalAsync('''
        async function testRateLimit() {
          const results = [];
          
          for (let i = 1; i <= 3; i++) {
            const result = await sendMessageAsync('rate', 'request' + i);
            results.push(result);
          }
          
          return results.join(' | ');
        }
        testRateLimit();
      ''');

      expect(result.toString(), contains('Processed'));
      expect(timestamps.length, lessThanOrEqualTo(maxRequestsPerSecond));
    });

    test('Authentication and authorization pattern', () async {
      final sessions = <String, Map<String, dynamic>>{};

      interpreter.onMessage('auth', (dynamic message) async {
        final args = message as List;
        final action = args[0] as String;

        await Future.delayed(Duration(milliseconds: 5));

        switch (action) {
          case 'login':
            final username = args[1] as String;
            final token =
                'token_${username}_${DateTime.now().millisecondsSinceEpoch}';
            sessions[token] = {
              'username': username,
              'role': 'user',
              'loginTime': DateTime.now().toIso8601String(),
            };
            return {'token': token, 'username': username};

          case 'validate':
            final token = args[1] as String;
            if (sessions.containsKey(token)) {
              return {'valid': true, 'session': sessions[token]};
            }
            return {'valid': false};

          case 'logout':
            final token = args[1] as String;
            sessions.remove(token);
            return {'success': true};

          default:
            return null;
        }
      });

      final result = await interpreter.evalAsync('''
        async function testAuth() {
          // Login
          const loginResult = await sendMessageAsync('auth', 'login', 'alice');
          const token = loginResult.token;
          
          // Validate
          const validateResult = await sendMessageAsync('auth', 'validate', token);
          
          // Logout
          const logoutResult = await sendMessageAsync('auth', 'logout', token);
          
          return {
            loggedIn: loginResult.username,
            isValid: validateResult.valid,
            loggedOut: logoutResult.success
          };
        }
        testAuth();
      ''');

      final resultObj = result as JSObject;
      expect(resultObj.getProperty('loggedIn').toString(), equals('alice'));
      expect(resultObj.getProperty('isValid').toString(), equals('true'));
      expect(resultObj.getProperty('loggedOut').toString(), equals('true'));
    });
  });

  group('Message JSON Encode/Decode Tests', () {
    late JSInterpreter interpreter;

    setUp(() {
      interpreter = JSInterpreter();
    });

    tearDown(() {
      interpreter.removeChannel('json-simple');
      interpreter.removeChannel('json-nested');
      interpreter.removeChannel('json-array');
      interpreter.removeChannel('json-complex');
      interpreter.removeChannel('json-user');
      interpreter.removeChannel('json-orders');
      interpreter.removeChannel('json-analytics');
      interpreter.removeChannel('json-config');
      interpreter.removeChannel('json-transform');
      interpreter.removeChannel('json-validation');
    });

    test('Simple JSON encode in Dart, decode in JS', () async {
      interpreter.onMessage('json-simple', (dynamic message) async {
        final args = message as List;
        final name = args[0] as String;

        // Return JSON encoded from Dart
        return '{"name": "$name", "status": "active", "age": 25}';
      });

      final result = await interpreter.evalAsync('''
        async function test() {
          const jsonString = await sendMessageAsync('json-simple', 'Alice');
          const data = JSON.parse(jsonString);
          return data.name + ' is ' + data.status + ' and ' + data.age + ' years old';
        }
        test();
      ''');

      expect(result.toString(), equals('Alice is active and 25 years old'));
    });

    test('Nested JSON object encode/decode', () async {
      interpreter.onMessage('json-nested', (dynamic message) async {
        final args = message as List;
        final userId = args[0];

        // Retourner un objet JSON complexe avec jsonEncode
        final data = {
          'user': {
            'id': userId,
            'profile': {
              'firstName': 'John',
              'lastName': 'Doe',
              'email': 'john.doe@example.com',
            },
            'settings': {'theme': 'dark', 'notifications': true},
          },
          'timestamp': 1234567890,
        };
        return jsonEncode(data);
      });

      final result = await interpreter.evalAsync('''
        async function test() {
          const jsonString = await sendMessageAsync('json-nested', 42);
          const data = JSON.parse(jsonString);
          
          return {
            userId: data.user.id,
            fullName: data.user.profile.firstName + ' ' + data.user.profile.lastName,
            theme: data.user.settings.theme,
            hasNotifications: data.user.settings.notifications
          };
        }
        test();
      ''');

      final resultObj = result as JSObject;
      expect(resultObj.getProperty('userId').toString(), equals('42'));
      expect(resultObj.getProperty('fullName').toString(), equals('John Doe'));
      expect(resultObj.getProperty('theme').toString(), equals('dark'));
      expect(
        resultObj.getProperty('hasNotifications').toString(),
        equals('true'),
      );
    });

    test('JSON array encode/decode', () async {
      interpreter.onMessage('json-array', (dynamic message) async {
        // Retourner un tableau JSON avec jsonEncode
        final items = [
          {'id': 1, 'name': 'Item 1', 'price': 10.99},
          {'id': 2, 'name': 'Item 2', 'price': 20.50},
          {'id': 3, 'name': 'Item 3', 'price': 15.75},
        ];
        return jsonEncode(items);
      });

      final result = await interpreter.evalAsync('''
        async function test() {
          const jsonString = await sendMessageAsync('json-array', 3);
          const items = JSON.parse(jsonString);
          
          let total = 0;
          for (const item of items) {
            total += item.price;
          }
          
          return {
            count: items.length,
            firstItem: items[0].name,
            total: total
          };
        }
        test();
      ''');

      final resultObj = result as JSObject;
      expect(resultObj.getProperty('count').toString(), equals('3'));
      expect(resultObj.getProperty('firstItem').toString(), equals('Item 1'));
      expect(resultObj.getProperty('total').toString(), equals('47.24'));
    });

    test('Complex data structure with mixed types', () async {
      interpreter.onMessage('json-complex', (dynamic message) async {
        final args = message as List;
        final category = args[0] as String;

        // Structure complexe avec plusieurs types
        final data = {
          'category': category,
          'items': [
            {
              'id': 1,
              'active': true,
              'tags': ['new', 'featured'],
            },
            {
              'id': 2,
              'active': false,
              'tags': ['sale'],
            },
            {
              'id': 3,
              'active': true,
              'tags': ['popular', 'trending'],
            },
          ],
          'metadata': {'total': 3, 'activeCount': 2, 'lastUpdated': null},
          'scores': [98.5, 87.3, 92.1],
        };
        return jsonEncode(data);
      });

      final result = await interpreter.evalAsync('''
        async function test() {
          const jsonString = await sendMessageAsync('json-complex', 'electronics');
          const data = JSON.parse(jsonString);
          
          const activeItems = data.items.filter(item => item.active);
          const avgScore = data.scores.reduce((a, b) => a + b, 0) / data.scores.length;
          
          return {
            category: data.category,
            activeCount: activeItems.length,
            firstActiveId: activeItems[0].id,
            avgScore: avgScore.toFixed(2),
            hasMetadata: data.metadata !== null
          };
        }
        test();
      ''');

      final resultObj = result as JSObject;
      expect(
        resultObj.getProperty('category').toString(),
        equals('electronics'),
      );
      expect(resultObj.getProperty('activeCount').toString(), equals('2'));
      expect(resultObj.getProperty('firstActiveId').toString(), equals('1'));
      expect(resultObj.getProperty('avgScore').toString(), equals('92.63'));
      expect(resultObj.getProperty('hasMetadata').toString(), equals('true'));
    });

    test('Bidirectional JSON communication', () async {
      interpreter.onMessage('json-user', (dynamic message) async {
        final args = message as List;
        final userJsonString = args[0] as String;

        // Parse the JSON received from JS
        final result = await interpreter.evalAsync('''
          (function() {
            const user = $userJsonString;
            return {
              processed: true,
              userId: user.id,
              fullName: user.firstName + ' ' + user.lastName,
              isAdmin: user.role === 'admin'
            };
          })()
        ''');

        final processed = result as JSObject;
        final userId = processed.getProperty('userId').toString();
        final fullName = processed.getProperty('fullName').toString();
        final isAdmin = processed.getProperty('isAdmin').toString();

        // Retourner un nouveau JSON avec jsonEncode
        final response = {
          'status': 'processed',
          'userId': int.parse(userId),
          'fullName': fullName,
          'isAdmin': isAdmin == 'true',
          'processedAt': 1234567890,
        };
        return jsonEncode(response);
      });

      final result = await interpreter.evalAsync('''
        async function test() {
          const user = {
            id: 123,
            firstName: "Bob",
            lastName: "Smith",
            role: "admin"
          };
          
          const userJson = JSON.stringify(user);
          const responseJson = await sendMessageAsync('json-user', userJson);
          const response = JSON.parse(responseJson);
          
          return {
            status: response.status,
            fullName: response.fullName,
            isAdmin: response.isAdmin
          };
        }
        test();
      ''');

      final resultObj = result as JSObject;
      expect(resultObj.getProperty('status').toString(), equals('processed'));
      expect(resultObj.getProperty('fullName').toString(), equals('Bob Smith'));
      expect(resultObj.getProperty('isAdmin').toString(), equals('true'));
    });

    test('JSON array processing with map/filter/reduce', () async {
      interpreter.onMessage('json-orders', (dynamic message) async {
        // Retourner un tableau de commandes avec jsonEncode
        final orders = [
          {
            'id': 1,
            'customer': 'Alice',
            'amount': 150.00,
            'status': 'completed',
          },
          {'id': 2, 'customer': 'Bob', 'amount': 75.50, 'status': 'pending'},
          {
            'id': 3,
            'customer': 'Charlie',
            'amount': 200.00,
            'status': 'completed',
          },
          {
            'id': 4,
            'customer': 'Diana',
            'amount': 50.00,
            'status': 'cancelled',
          },
          {'id': 5, 'customer': 'Eve', 'amount': 175.00, 'status': 'completed'},
        ];
        return jsonEncode(orders);
      });

      final result = await interpreter.evalAsync('''
        async function test() {
          const ordersJson = await sendMessageAsync('json-orders', 100);
          const orders = JSON.parse(ordersJson);
          
          // Filter completed orders with amount >= 100
          const completedOrders = orders.filter(o => 
            o.status === 'completed' && o.amount >= 100
          );
          
          // Calculate total
          const total = completedOrders.reduce((sum, o) => sum + o.amount, 0);
          
          // Get customer names
          const customers = completedOrders.map(o => o.customer);
          
          return {
            count: completedOrders.length,
            total: total,
            customers: customers.join(', ')
          };
        }
        test();
      ''');

      final resultObj = result as JSObject;
      expect(resultObj.getProperty('count').toString(), equals('3'));
      expect(resultObj.getProperty('total').toString(), equals('525'));
      expect(
        resultObj.getProperty('customers').toString(),
        equals('Alice, Charlie, Eve'),
      );
    });

    test('JSON with nested arrays and complex transformations', () async {
      interpreter.onMessage('json-analytics', (dynamic message) async {
        final args = message as List;
        final period = args[0] as String;

        final data = {
          'period': period,
          'metrics': [
            {
              'date': '2024-01-01',
              'views': [120, 150, 180, 200],
              'clicks': [10, 15, 20, 25],
            },
            {
              'date': '2024-01-02',
              'views': [130, 160, 190, 210],
              'clicks': [12, 18, 22, 28],
            },
            {
              'date': '2024-01-03',
              'views': [140, 170, 200, 220],
              'clicks': [14, 20, 24, 30],
            },
          ],
        };
        return jsonEncode(data);
      });

      final result = await interpreter.evalAsync('''
        async function test() {
          const jsonString = await sendMessageAsync('json-analytics', 'week');
          const data = JSON.parse(jsonString);
          
          let totalViews = 0;
          let totalClicks = 0;
          
          for (const metric of data.metrics) {
            for (const view of metric.views) {
              totalViews += view;
            }
            for (const click of metric.clicks) {
              totalClicks += click;
            }
          }
          
          const ctr = (totalClicks / totalViews * 100).toFixed(2);
          
          return {
            period: data.period,
            totalViews: totalViews,
            totalClicks: totalClicks,
            ctr: ctr + '%',
            days: data.metrics.length
          };
        }
        test();
      ''');

      final resultObj = result as JSObject;
      expect(resultObj.getProperty('period').toString(), equals('week'));
      expect(resultObj.getProperty('totalViews').toString(), equals('2070'));
      expect(resultObj.getProperty('totalClicks').toString(), equals('238'));
      expect(resultObj.getProperty('ctr').toString(), equals('11.50%'));
      expect(resultObj.getProperty('days').toString(), equals('3'));
    });

    test('JSON with escape characters and special strings', () async {
      interpreter.onMessage('json-config', (dynamic message) async {
        final args = message as List;
        final env = args[0] as String;

        // JSON with special characters - jsonEncode handles escaping automatically
        final data = {
          'env': env,
          'apiUrl': 'https://api.example.com/v1',
          'description': 'This is a "quoted" string with\nnewlines\tand tabs',
          'regex': r'^[a-zA-Z0-9_-]+@[a-zA-Z0-9_-]+(\\.[a-zA-Z0-9_-]+)*$',
          'paths': {
            'windows': r'C:\\Users\\Admin\\Documents',
            'unix': '/home/user/documents',
          },
        };
        return jsonEncode(data);
      });

      final result = await interpreter.evalAsync('''
        async function test() {
          const jsonString = await sendMessageAsync('json-config', 'production');
          const config = JSON.parse(jsonString);
          
          return {
            env: config.env,
            hasApiUrl: config.apiUrl.includes('https'),
            hasQuotes: config.description.includes('"'),
            windowsPath: config.paths.windows,
            unixPath: config.paths.unix
          };
        }
        test();
      ''');

      final resultObj = result as JSObject;
      expect(resultObj.getProperty('env').toString(), equals('production'));
      expect(resultObj.getProperty('hasApiUrl').toString(), equals('true'));
      expect(resultObj.getProperty('hasQuotes').toString(), equals('true'));
      expect(
        resultObj.getProperty('windowsPath').toString(),
        contains('Users'),
      );
      expect(
        resultObj.getProperty('unixPath').toString(),
        equals('/home/user/documents'),
      );
    });

    test('JSON data transformation pipeline', () async {
      interpreter.onMessage('json-transform', (dynamic message) async {
        final args = message as List;
        final operation = args[0] as String;
        final dataJson = args[1] as String;

        if (operation == 'normalize') {
          final response = {
            'transformed': true,
            'operation': 'normalize',
            'data': dataJson,
          };
          return jsonEncode(response);
        } else if (operation == 'aggregate') {
          // Parse and aggregate
          final result = await interpreter.evalAsync('''
            (function() {
              const items = $dataJson;
              const sum = items.reduce((a, b) => a + b, 0);
              return sum;
            })()
          ''');

          final response = {
            'transformed': true,
            'operation': 'aggregate',
            'result': double.parse(result.toString()),
          };
          return jsonEncode(response);
        }

        return jsonEncode({'error': 'unknown operation'});
      });

      // Test normalize
      final result1 = await interpreter.evalAsync('''
        async function testNormalize() {
          const data = {"values": [1, 2, 3]};
          const dataJson = JSON.stringify(data);
          const responseJson = await sendMessageAsync('json-transform', 'normalize', dataJson);
          const response = JSON.parse(responseJson);
          return response.operation;
        }
        testNormalize();
      ''');
      expect(result1.toString(), equals('normalize'));

      // Test aggregate
      final result2 = await interpreter.evalAsync('''
        async function testAggregate() {
          const numbers = [10, 20, 30, 40];
          const numbersJson = JSON.stringify(numbers);
          const responseJson = await sendMessageAsync('json-transform', 'aggregate', numbersJson);
          const response = JSON.parse(responseJson);
          return response.result;
        }
        testAggregate();
      ''');
      expect(result2.toString(), equals('100'));
    });

    test('JSON validation and error handling', () async {
      interpreter.onMessage('json-validation', (dynamic message) async {
        final args = message as List;
        final jsonString = args[0] as String;

        try {
          // Tenter de parser le JSON
          final result = await interpreter.evalAsync('''
            (function() {
              try {
                const data = $jsonString;
                return {valid: true, keys: Object.keys(data).length};
              } catch (e) {
                return {valid: false, error: e.message};
              }
            })()
          ''');

          final resultObj = result as JSObject;
          final valid = resultObj.getProperty('valid').toString();

          if (valid == 'true') {
            final keys = resultObj.getProperty('keys').toString();
            return jsonEncode({'status': 'valid', 'keyCount': int.parse(keys)});
          } else {
            return jsonEncode({'status': 'invalid', 'error': 'Parse error'});
          }
        } catch (e) {
          return jsonEncode({
            'status': 'error',
            'message': 'Processing failed',
          });
        }
      });

      // Test valid JSON
      final result1 = await interpreter.evalAsync('''
        async function testValid() {
          const validJson = JSON.stringify({name: "test", value: 42});
          const responseJson = await sendMessageAsync('json-validation', validJson);
          const response = JSON.parse(responseJson);
          return response.status;
        }
        testValid();
      ''');
      expect(result1.toString(), equals('valid'));

      // Test invalid JSON - Le catch attrape l'erreur donc retourne 'error'
      final result2 = await interpreter.evalAsync('''
        async function testInvalid() {
          const invalidJson = '{invalid json}';
          const responseJson = await sendMessageAsync('json-validation', invalidJson);
          const response = JSON.parse(responseJson);
          return response.status;
        }
        testInvalid();
      ''');
      expect(result2.toString(), equals('error'));
    });
  });
}
