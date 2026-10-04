require_relative "../lib/sorted_ints"

Hypo.property "lower_bound partitions at zero",
              Hypo.arrays(of: Hypo.integers(min: -20, max: 20), max_size: 40),
              at: [__FILE__, __LINE__] do |numbers|
  sorted = numbers.sort
  index = SortedInts.lower_bound(sorted, 0)
  expected = sorted.count { |number| number < 0 }
  Hypo.assert(index == expected, "lower_bound must follow all negative elements")
end

Hypo.property "lower_bound handles arbitrary keys",
              Hypo.integers(min: -10, max: 10),
              at: [__FILE__, __LINE__] do |key|
  sorted = [-3, -1, 0, 0, 2, 7]
  expected = sorted.count { |number| number < key }
  Hypo.assert(SortedInts.lower_bound(sorted, key) == expected)
end
