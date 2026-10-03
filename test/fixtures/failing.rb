Hypo.property "must be negative", Hypo.integers(min: -10, max: 10), at: [__FILE__, __LINE__] do |value|
  Hypo.assert(value < 0, "positive input found")
end
