Hypo.property "absolute value is nonnegative", Hypo.integers(min: -10, max: 10), at: [__FILE__, __LINE__] do |value|
  Hypo.assert(value.abs >= 0)
end
