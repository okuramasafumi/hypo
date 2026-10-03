Hypo.property "raises", Hypo.integers, at: [__FILE__, __LINE__] do |value|
  raise ArgumentError, "target exploded"
end
