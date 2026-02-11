## 0.0.2

### Features
- **ES2024 Support**: Implemented Explicit Resource Management (`using` and `await using` declarations).
- **ES2015 Support**: Added Tail Call Optimization (TCO).
- **Core Improvements**:
  - Implemented proper `with` statement environment handling and `Symbol.unscopables` support.
  - Enhanced `Promise` microtask queue and async function execution logic.
  - Added support for dynamic imports.
  - Improved `Function` constructor to support `return` statements in dynamically created functions.

### Compliance & Bug Fixes
- **Parser & Syntax**:
  - Added comprehensive "Early Errors" validation for functions, classes, and loops.
  - Fixed Automatic Semicolon Insertion (ASI) to correctly handle all Unicode line terminators (LF, CR, LS, PS).
  - Improved validation for `break` and `continue` labels.
  - Fixed strict mode inheritance in `eval()` and strict mode-specific validations.
- **Data Models**:
  - Improved `JSValue` to Dart `Map`/`List` conversion with support for enumerable properties and recursive conversion.
  - Refined error object detection logic.
- **Execution**:
  - Fixed completion values for control structures (blocks, loops, switch).
  - Improved lexical scoping for `let` and `const` in `for` loops and `switch` statements.
  - Fixed `this` binding in async functions and arrow functions.

### Testing
- Significantly improved `test262` test runner compatibility.
- Fixed numerous bugs discovered through `test262` compliance testing.

## 0.0.1

- Initial version.
