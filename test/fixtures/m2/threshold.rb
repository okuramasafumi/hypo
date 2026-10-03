Hypo.property "threshold", Hypo.integers(min: 0, max: 100), at: [__FILE__, __LINE__] do |value|
  Hypo.assert(value < 10, "must be below ten")
end
