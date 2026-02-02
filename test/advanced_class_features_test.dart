import 'package:js_interpreter/js_interpreter.dart';
import 'package:test/test.dart';

void main() {
  test('Complex Class and Inheritance Test', () {
    final code = """
      class Vehicle {
        constructor(name) {
          this.name = name;
          this.repairs = [];
        }

        drive() {
          return this.name + ' is driving.';
        }

        addRepair(part) {
          this.repairs.push(part);
        }

        static getCompanyName() {
          return 'Generic Motors';
        }
      }

      class Car extends Vehicle {
        constructor(name, brand) {
          super(name);
          this.brand = brand;
        }

        // Override
        drive() {
          return this.brand + ' ' + this.name + ' is cruising.';
        }

        // Use super.method()
        breakDown(part) {
          super.addRepair(part);
          return this.name + ' broke down. Needs ' + part + ' fixed.';
        }

        static getCompanyName() {
          return 'Specific Motors';
        }

        static getParentCompanyName() {
          return super.getCompanyName();
        }
      }

      const myCar = new Car('Civic', 'Honda');
      const carDrive = myCar.drive();
      myCar.breakDown('alternator');
      const carRepairs = myCar.repairs;
      const company = Car.getCompanyName();
      const parentCompany = Car.getParentCompanyName();

      // Test returning object from constructor
      class TestReturn {
        constructor() {
          return { a: 1, b: 2 };
        }
      }
      const testReturnObj = new TestReturn();

      [carDrive, carRepairs[0], company, parentCompany, testReturnObj.a, testReturnObj.b];
    """;
    final result = JSInterpreter().eval(code).toObject();
    expect((result as JSArray).toList(), [
      'Honda Civic is cruising.',
      'alternator',
      'Specific Motors',
      'Generic Motors',
      1,
      2,
    ]);
  });
}
