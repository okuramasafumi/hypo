require_relative "../examples/sorted_ints/lib/sorted_ints"

def check(condition, message)
  raise message unless condition
end

[[], [-2], [0], [2], [-2, 0, 0, 2], [1, 1, 1]].each do |numbers|
  (-3..3).each do |key|
    before = numbers.dup
    index = SortedInts.lower_bound(numbers, key)
    check(index == numbers.count { |n| n < key }, "first insertion index")
    inserted = SortedInts.insert(numbers, key)
    check(inserted == (numbers + [key]).sort, "sorted insertion preserves multiplicity")
    check(numbers == before, "library does not mutate its input")
    inserted.clear
    check(numbers == before, "result does not alias input")
  end
end
puts "sorted integer library: passed"
