Hypo.property %q{array's $value ; $(touch INJECTED)},
              Hypo.arrays(of: Hypo.integers(min: -10, max: 10), max_size: 4),
              at: [__FILE__, __LINE__] do |array|
  failure = array.any? { |n| n >= 3 }
  array.clear
  Hypo.assert(!failure, "values below three")
end
Hypo.property "array passes", Hypo.arrays(of: Hypo.integers(min: 2, max: 9), min_size: 1, max_size: 3), at: [__FILE__, __LINE__] do |a|
  Hypo.assert(a.length >= 1 && a.length <= 3 && a.all? { |n| n >= 2 && n <= 9 })
end
