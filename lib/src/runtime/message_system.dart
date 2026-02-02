/// Message system for dynamic function calls between Dart and JavaScript
library;

import 'package:js_interpreter/js_interpreter.dart';

/// Message system for pub/sub communication between Dart and JavaScript
class MessageSystem {
  final String? getInterpreterInstanceId;

  MessageSystem(this.getInterpreterInstanceId) {
    _channels =
        JSInterpreter.channelFunctionsRegistered[getInterpreterInstanceId] ??
        {};
  }

  /// Map of channel names to synchronous callbacks
  Map<String, dynamic Function(dynamic)> _channels = {};

  /// Register a synchronous callback for a channel
  void onMessage(String channelName, dynamic Function(dynamic) callback) {
    _channels[channelName] = callback;
  }

  /// Send a message to a channel, triggering the registered synchronous callback
  /// Returns the return value from the callback
  /// Auto-converts JSValue to Dart native types
  /// Throws JSError if the callback throws an exception
  dynamic sendMessage(String channelName, dynamic message) {
    final callback = _channels[channelName];

    if (callback == null) return null;

    // Convert JSValue to native Dart types
    final dartMessage = _convertMessage(message);

    try {
      return callback.call(dartMessage);
    } catch (error, stackTrace) {
      // Convert Dart exceptions to JSError for JavaScript propagation
      if (error is JSError) {
        rethrow;
      }
      // Create JSError with message and stack trace
      throw JSError(
        'Error in onMessage callback for channel "$channelName": $error\n$stackTrace',
      );
    }
  }

  /// Send an async message to a channel, triggering the registered asynchronous callback
  /// Returns a Future that completes with the return value
  /// Auto-converts JSValue to Dart native types
  /// Rejects the promise if the callback throws an exception
  Future<dynamic> sendMessageAsync(String channelName, dynamic message) async {
    final callback = _channels[channelName];

    if (callback == null) return null;

    // Convert JSValue to native Dart types
    final dartMessage = _convertMessage(message);

    try {
      return await callback.call(dartMessage);
    } catch (error, stackTrace) {
      // Convert Dart exceptions to JSError for JavaScript propagation
      if (error is JSError) {
        rethrow;
      }
      // Create JSError with message and stack trace
      throw JSError(
        'Error in onMessage callback for channel "$channelName": $error\n$stackTrace',
      );
    }
  }

  /// Convert JSValue or list of JSValues message to native Dart types
  dynamic _convertMessage(dynamic message) {
    if (message is JSValue) {
      return DartValueConverter.toDartValue(message);
    }
    if (message is List) {
      return message.map((item) => _convertMessage(item)).toList();
    }
    if (message is Map) {
      return message.map((key, value) => MapEntry(key, _convertMessage(value)));
    }
    return message;
  }

  /// Remove all callbacks for a channel
  void removeChannel(String channelName) {
    _channels.remove(channelName);
  }

  /// Remove a specific callback from a channel
  void removeCallback(String channelName, dynamic Function(dynamic) callback) {
    final callback = _channels[channelName];
    if (callback != null) {
      if (callback == callback) {
        _channels.remove(channelName);
      }
    }
  }

  /// Get all registered channel names (both sync and async)
  List<String> getChannels() {
    final allChannels = <String>{};
    allChannels.addAll(_channels.keys);
    return allChannels.toList();
  }

  /// Clear all channels and callbacks
  void clear() {
    _channels.clear();
  }
}
