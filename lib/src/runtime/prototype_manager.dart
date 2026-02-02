import 'dart:async';
import 'js_value.dart';

/// Manages prototypes for a single JavaScript interpreter instance.
/// This ensures each interpreter has its own isolated prototype chain.
class PrototypeManager {
  JSObject? _objectPrototype;
  JSObject? _functionPrototype;
  JSArray? _arrayPrototype;
  JSObject? _stringPrototype;
  JSObject? _booleanPrototype;
  JSObject? _numberPrototype;
  JSObject? _promisePrototype;

  JSObject? get objectPrototype => _objectPrototype;
  JSObject? get functionPrototype => _functionPrototype;
  JSArray? get arrayPrototype => _arrayPrototype;
  JSObject? get stringPrototype => _stringPrototype;
  JSObject? get booleanPrototype => _booleanPrototype;
  JSObject? get numberPrototype => _numberPrototype;
  JSObject? get promisePrototype => _promisePrototype;

  void setObjectPrototype(JSObject prototype) {
    _objectPrototype = prototype;
  }

  void setFunctionPrototype(JSObject prototype) {
    _functionPrototype = prototype;
  }

  void setArrayPrototype(JSArray prototype) {
    _arrayPrototype = prototype;
  }

  void setStringPrototype(JSObject prototype) {
    _stringPrototype = prototype;
  }

  void setBooleanPrototype(JSObject prototype) {
    _booleanPrototype = prototype;
  }

  void setNumberPrototype(JSObject prototype) {
    _numberPrototype = prototype;
  }

  void setPromisePrototype(JSObject prototype) {
    _promisePrototype = prototype;
  }

  /// Zone-local key to store the current prototype manager
  static final _zoneKey = Object();

  /// Gets the current prototype manager from the Zone
  static PrototypeManager? get current {
    return Zone.current[_zoneKey] as PrototypeManager?;
  }

  /// Runs code within a Zone that has this prototype manager active
  R runWithin<R>(R Function() body) {
    return runZoned(body, zoneValues: {_zoneKey: this});
  }
}
