require_relative "../examples/absolute_value"

Hypo.property "buggy absolute value is nonnegative",
              Hypo.integers(min: -100, max: 100),
              at: [__FILE__, __LINE__] do |number|
  Hypo.assert(buggy_absolute_value(number) >= 0)
end
