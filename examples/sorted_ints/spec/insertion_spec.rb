require_relative "../lib/sorted_ints"

Hypo.property "inserting zero preserves order and duplicates",
              Hypo.arrays(of: Hypo.integers(min: -20, max: 20), max_size: 40),
              at: [__FILE__, __LINE__] do |numbers|
  sorted = numbers.sort
  before = sorted.dup
  result = SortedInts.insert(sorted, 0)
  Hypo.assert(result == (before + [0]).sort && sorted == before,
              "insertion must preserve every element and leave its input unchanged")
end
