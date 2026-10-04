Hypo.property "integer threshold", Hypo.integers(min: 0, max: 100), at: [__FILE__, __LINE__] do |n|
  Hypo.assert(n < 10)
end
Hypo.property "Boolean passes", Hypo.booleans, at: [__FILE__, __LINE__] do |b|
  Hypo.assert(!!b == b)
end
Hypo.property "Boolean fails", Hypo.booleans, at: [__FILE__, __LINE__] do |b|
  Hypo.assert(!b)
end
