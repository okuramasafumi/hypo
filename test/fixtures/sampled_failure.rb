Hypo.property "interior input", Hypo.integers(min: -100, max: 100), at: [__FILE__, __LINE__] do |value|
  Hypo.assert(value == -100 || value == 100 || value == 0 || value == -1 || value == 1)
end
