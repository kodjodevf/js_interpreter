import 'js_value.dart';

/// Implementation of JavaScript Symbol
/// NOTE: JSSymbol extends JSValue (not JSObject) because symbols are primitives
class JSSymbol extends JSValue {
  /// Symbol description (optional)
  final String? description;

  /// If it's a global symbol (Symbol.for)
  final bool isGlobal;

  /// Key for global symbols
  final String? globalKey;

  /// Unique ID for symbol identity
  final int _id;

  /// Global counter to generate unique IDs
  static int _nextId = 0;

  /// Registry of global symbols (Symbol.for)
  static final Map<String, JSSymbol> _globalSymbols = {};

  /// Flag to avoid multiple initialization of well-known symbols
  static bool _wellKnownSymbolsInitialized = false;

  /// Predefined well-known symbols
  static late final JSSymbol iterator;
  static late final JSSymbol asyncIterator;
  static late final JSSymbol toStringTag;
  static late final JSSymbol hasInstance;
  static late final JSSymbol species;
  static late final JSSymbol symbolToPrimitive; // Renamed to avoid conflict
  static late final JSSymbol match;
  static late final JSSymbol replace;
  static late final JSSymbol search;
  static late final JSSymbol split;
  static late final JSSymbol isConcatSpreadable;
  static late final JSSymbol unscopables;

  JSSymbol._(this.description, this.isGlobal, this.globalKey) : _id = _nextId++;

  /// Create a new symbol with an optional description
  factory JSSymbol([String? description]) {
    return JSSymbol._(description, false, null);
  }

  /// Create or retrieve a global symbol (Symbol.for)
  factory JSSymbol.symbolFor(String key) {
    if (_globalSymbols.containsKey(key)) {
      return _globalSymbols[key]!;
    }
    final symbol = JSSymbol._(key, true, key);
    _globalSymbols[key] = symbol;
    return symbol;
  }

  /// Initialize well-known symbols
  static void initializeWellKnownSymbols() {
    if (_wellKnownSymbolsInitialized) return;
    _wellKnownSymbolsInitialized = true;

    iterator = JSSymbol._('Symbol.iterator', false, null);
    asyncIterator = JSSymbol._('Symbol.asyncIterator', false, null);
    toStringTag = JSSymbol._('Symbol.toStringTag', false, null);
    hasInstance = JSSymbol._('Symbol.hasInstance', false, null);
    species = JSSymbol._('Symbol.species', false, null);
    symbolToPrimitive = JSSymbol._('Symbol.toPrimitive', false, null);
    match = JSSymbol._('Symbol.match', false, null);
    replace = JSSymbol._('Symbol.replace', false, null);
    search = JSSymbol._('Symbol.search', false, null);
    split = JSSymbol._('Symbol.split', false, null);
    isConcatSpreadable = JSSymbol._('Symbol.isConcatSpreadable', false, null);
    unscopables = JSSymbol._('Symbol.unscopables', false, null);
  }

  /// Returns the key of a global symbol or null
  static String? keyFor(JSSymbol symbol) {
    return symbol.globalKey;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other);
  }

  @override
  int get hashCode => _id.hashCode;

  @override
  String toString() {
    if (description != null) {
      return 'Symbol($description)';
    } else {
      return 'Symbol()';
    }
  }

  @override
  JSValueType get type => JSValueType.symbol;

  @override
  dynamic get primitiveValue => this;

  @override
  bool toBoolean() => true;

  @override
  double toNumber() {
    throw JSTypeError('Cannot convert a Symbol value to a number');
  }

  @override
  JSObject toObject() => JSSymbolObject(this);

  @override
  bool equals(JSValue other) => identical(this, other);

  @override
  bool strictEquals(JSValue other) => identical(this, other);
}

/// Symbol constructor for JavaScript
class JSSymbolConstructor extends JSFunction {
  JSSymbolConstructor()
    : super('Symbol', (context, thisBinding, arguments) {
        // Symbol() sans new
        if (arguments.isEmpty) {
          return JSSymbol();
        } else {
          final description = arguments[0].toString();
          return JSSymbol(description);
        }
      });

  /// Symbol.for(key)
  JSValue symbolForMethod(List<JSValue> args) {
    if (args.isEmpty) {
      throw JSException(JSValueFactory.string('Symbol.for requires a key'));
    }
    final key = args[0].toString();
    return JSSymbol.symbolFor(key);
  }

  /// Symbol.keyFor(symbol)
  JSValue keyForMethod(List<JSValue> args) {
    if (args.isEmpty || !args[0].isSymbol) {
      throw JSException(
        JSValueFactory.string('Symbol.keyFor requires a symbol'),
      );
    }
    final symbol = args[0] as JSSymbol;
    final key = JSSymbol.keyFor(symbol);
    return key != null
        ? JSValueFactory.string(key)
        : JSValueFactory.undefined();
  }

  /// Initialize Symbol constructor properties and methods
  void initialize() {
    // Static methods
    setProperty(
      'for',
      JSValueFactory.function('for', (context, thisBinding, arguments) {
        return symbolForMethod(arguments);
      }),
    );

    setProperty(
      'keyFor',
      JSValueFactory.function('keyFor', (context, thisBinding, arguments) {
        return keyForMethod(arguments);
      }),
    );

    // Well-known symbols
    setProperty('iterator', JSSymbol.iterator);
    setProperty('asyncIterator', JSSymbol.asyncIterator);
    setProperty('toStringTag', JSSymbol.toStringTag);
    setProperty('hasInstance', JSSymbol.hasInstance);
    setProperty('species', JSSymbol.species);
    setProperty('toPrimitive', JSSymbol.symbolToPrimitive);
    setProperty('match', JSSymbol.match);
    setProperty('replace', JSSymbol.replace);
    setProperty('search', JSSymbol.search);
    setProperty('split', JSSymbol.split);
    setProperty('isConcatSpreadable', JSSymbol.isConcatSpreadable);
    setProperty('unscopables', JSSymbol.unscopables);
  }
}

/// Symbol object wrapper - Object wrapper for symbol primitives
class JSSymbolObject extends JSObject {
  @override
  final JSSymbol primitiveValue;

  // Static prototype for all Symbol objects
  static JSObject? _symbolPrototype;

  static void setSymbolPrototype(JSObject prototype) {
    _symbolPrototype = prototype;
  }

  static JSObject? get symbolPrototype => _symbolPrototype;

  JSSymbolObject(this.primitiveValue) {
    // Set the prototype to Symbol.prototype if available
    final proto = symbolPrototype;
    if (proto != null) {
      setPrototype(proto);
    }
  }

  @override
  String toString() => primitiveValue.toString();

  @override
  bool toBoolean() => true; // Objects are always truthy

  @override
  double toNumber() {
    throw JSTypeError('Cannot convert a Symbol value to a number');
  }

  @override
  bool equals(JSValue other) {
    if (other is JSSymbol) {
      return primitiveValue == other;
    } else if (other is JSSymbolObject) {
      return primitiveValue == other.primitiveValue;
    }
    return false;
  }
}
