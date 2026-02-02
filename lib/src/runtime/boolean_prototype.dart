/// Boolean prototype and native methods
///
/// Implements Boolean.prototype methods
library;

import 'js_value.dart';
import 'native_functions.dart';

/// Boolean prototype avec methodes
class BooleanPrototype {
  /// Boolean.prototype.toString()
  static JSValue toStringMethod(List<JSValue> args, bool value) {
    return JSValueFactory.string(value.toString());
  }

  /// Boolean.prototype.valueOf()
  static JSValue valueOf(List<JSValue> args, bool value) {
    return JSValueFactory.boolean(value);
  }

  /// Retrieve a property of a Boolean (auto-boxing)
  static JSValue getBooleanProperty(bool value, String name) {
    switch (name) {
      case 'toString':
        return JSNativeFunction(
          functionName: 'toString',
          nativeImpl: (args) => toStringMethod(args, value),
        );
      case 'valueOf':
        return JSNativeFunction(
          functionName: 'valueOf',
          nativeImpl: (args) => valueOf(args, value),
        );
      default:
        // Search in Object.prototype
        final objectPrototype = JSObject.objectPrototype;
        return objectPrototype.getProperty(name);
    }
  }
}
