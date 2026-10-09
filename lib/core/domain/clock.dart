/// Injectable time source so business rules are deterministic in tests.
typedef Clock = DateTime Function();

DateTime systemClock() => DateTime.now();

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
