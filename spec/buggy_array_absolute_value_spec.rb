require_relative "../examples/absolute_value"

Hypo.property "buggy array absolute values are nonnegative",
              Hypo.arrays(of: Hypo.integers(min: -100, max: 100)),
              at: [__FILE__, __LINE__] do |numbers|
  numbers.map! { |number| buggy_absolute_value(number) }
  Hypo.assert(numbers.all? { |number| number >= 0 })
end
