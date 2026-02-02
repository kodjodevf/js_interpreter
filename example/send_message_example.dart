///
/// Demonstrates advanced messaging patterns using sendMessageAsync:
/// - Retry with backoff
/// - Circuit breaker
/// - Rate limiting
/// - Authentication
/// - Orchestration flows
library;

import 'dart:convert';
import 'package:js_interpreter/js_interpreter.dart';

void main() async {
  final interpreter = JSInterpreter();

  print('=== Retry Pattern with Exponential Backoff ===');

  var attemptCount = 0;

  interpreter.onMessage('retry', (dynamic message) async {
    final args = message as List;
    final taskId = args[0] as String;

    attemptCount++;

    await Future.delayed(Duration(milliseconds: 5));

    // Fail first two attempts, succeed on third
    if (attemptCount < 3) {
      throw Exception('Attempt $attemptCount failed');
    }

    return 'Success on attempt $attemptCount for $taskId';
  });

  final result1 = await interpreter.evalAsync('''
    async function retryWithBackoff(taskId, maxRetries) {
      let attempt = 0;
      let delay = 1;
      let lastError = null;
      
      while (attempt < maxRetries) {
        try {
          const result = await sendMessageAsync('retry', taskId);
          return result;
        } catch (e) {
          lastError = e;
          attempt++;
          
          if (attempt >= maxRetries) {
            return 'Failed after ' + maxRetries + ' attempts: ' + lastError;
          }
          
          // Exponential backoff (simulated)
          await new Promise(resolve => setTimeout(resolve, delay));
          delay *= 2;
        }
      }
    }
    retryWithBackoff('task1', 5);
  ''');

  print('Retry Pattern: $result1');
  print('Total attempts: $attemptCount');

  print('\n=== Circuit Breaker Pattern ===');

  var failureCount = 0;
  var circuitOpen = false;

  interpreter.onMessage('circuit', (dynamic message) async {
    final args = message as List;
    final action = args[0] as String;

    if (action == 'call') {
      if (circuitOpen) {
        return 'Circuit OPEN - call rejected';
      }

      await Future.delayed(Duration(milliseconds: 10));

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
      return 'Success - service available';
    } else if (action == 'reset') {
      failureCount = 0;
      circuitOpen = false;
      return 'Circuit reset';
    }

    return null;
  });

  final result2 = await interpreter.evalAsync('''
    async function testCircuitBreaker() {
      const results = [];
      
      try {
        const r1 = await sendMessageAsync('circuit', 'call', false);
        results.push(r1);
      } catch (e) {
        results.push('Error: ' + e);
      }
      
      await sendMessageAsync('circuit', 'reset');
      
      return results.join(' | ');
    }
    testCircuitBreaker();
  ''');

  print('Circuit Breaker: $result2');

  print('\n=== Rate Limiting Pattern ===');

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
      return jsonEncode({'status': 'rate_limited', 'requestId': requestId});
    }

    await Future.delayed(Duration(milliseconds: 5));
    return jsonEncode({
      'status': 'ok',
      'requestId': requestId,
      'timestamp': now.millisecondsSinceEpoch,
    });
  });

  final result3 = await interpreter.evalAsync('''
    async function testRateLimiting() {
      const results = [];
      
      for (let i = 1; i <= 3; i++) {
        const resultJson = await sendMessageAsync('rate', 'request' + i);
        const result = JSON.parse(resultJson);
        results.push(result.status);
      }
      
      return results.join(', ');
    }
    testRateLimiting();
  ''');

  print('Rate Limiting: $result3');

  print('\n=== Authentication & Authorization ===');

  final sessions = <String, Map<String, dynamic>>{};

  interpreter.onMessage('auth', (dynamic message) async {
    final args = message as List;
    final action = args[0] as String;

    await Future.delayed(Duration(milliseconds: 10));

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
        return jsonEncode({
          'token': token,
          'username': username,
          'role': 'user',
        });

      case 'validate':
        final token = args[1] as String;
        if (sessions.containsKey(token)) {
          return jsonEncode({
            'valid': true,
            'username': sessions[token]!['username'],
          });
        }
        return jsonEncode({'valid': false});

      case 'logout':
        final token = args[1] as String;
        sessions.remove(token);
        return jsonEncode({'success': true});

      default:
        return jsonEncode({'error': 'Unknown action'});
    }
  });

  final result4 = await interpreter.evalAsync('''
    async function authFlow() {
      // Login
      const loginJson = await sendMessageAsync('auth', 'login', 'alice');
      const login = JSON.parse(loginJson);
      const token = login.token;
      
      // Validate
      const validateJson = await sendMessageAsync('auth', 'validate', token);
      const validation = JSON.parse(validateJson);
      
      // Logout
      const logoutJson = await sendMessageAsync('auth', 'logout', token);
      const logout = JSON.parse(logoutJson);
      
      return {
        loggedIn: login.username,
        isValid: validation.valid,
        loggedOut: logout.success
      };
    }
    authFlow();
  ''');

  print('Auth Flow: $result4');

  print('\n=== Orchestration with Conditional Flow ===');

  interpreter.onMessage('orchestrator', (dynamic message) async {
    final args = message as List;
    final step = args[0] as String;
    final value = args.length > 1 ? args[1] : null;

    await Future.delayed(Duration(milliseconds: 8));

    switch (step) {
      case 'validate':
        return value != null && (value as num) > 0;
      case 'process':
        return (value as num) * 2;
      case 'save':
        return 'Saved: $value';
      case 'notify':
        return 'Notified about: $value';
      default:
        return null;
    }
  });

  final result5 = await interpreter.evalAsync('''
    async function orchestrateWorkflow(input) {
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
    orchestrateWorkflow(5);
  ''');

  print('Orchestration: $result5');

  print('\n=== Fan-out Pattern (Concurrent Processing) ===');

  final processedItems = <String>[];

  interpreter.onMessage('fanout', (dynamic message) async {
    final args = message as List;
    final item = args[0] as String;
    final delay = args[1] as num;

    await Future.delayed(Duration(milliseconds: delay.toInt()));
    processedItems.add(item);

    return 'Processed $item in ${delay}ms';
  });

  final result6 = await interpreter.evalAsync('''
    async function fanOutProcessing() {
      const items = [
        ['task1', 10],
        ['task2', 8],
        ['task3', 12],
        ['task4', 6]
      ];
      
      const promises = items.map(item => 
        sendMessageAsync('fanout', item[0], item[1])
      );
      
      const results = await Promise.all(promises);
      return {
        totalTasks: results.length,
        results: results
      };
    }
    fanOutProcessing();
  ''');

  print('Fan-out: $result6');
  print('Processed items: ${processedItems.join(", ")}');

  print('\n=== Cleanup ===');
  interpreter.removeChannel('retry');
  interpreter.removeChannel('circuit');
  interpreter.removeChannel('rate');
  interpreter.removeChannel('auth');
  interpreter.removeChannel('orchestrator');
  interpreter.removeChannel('fanout');

  print('Done!');
}
