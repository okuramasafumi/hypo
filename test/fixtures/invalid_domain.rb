Hypo.property "bad bounds", Hypo.integers(min: 3, max: 2), at: [__FILE__, __LINE__] do |value|
  Hypo.assert(true)
end
