# q06_unit_classes

Every unit class is an anonymous `Class.new(Quantity)` built in a loop while `lib/units.rb` loads, given
class-level ivars (`@factor`, `@dimension`, `@symbol`) and named with `const_set`; the factor arithmetic
(`INCH_MM * 12 * 5_280`, `POUND_G / 16`) and the frozen `BY_SYMBOL` index only run at load. Re-running the
loop makes new classes that the existing constants and index do not point to.
