require_relative "../lib/hypo"

def check(condition, message)
  raise message unless condition
end

generator = Hypo.arrays(of: Hypo.integers(min: -10, max: 10), max_size: 4)
random = Hypo::Random.new(42)
values = []
20.times { |index| values << generator.example(random, index) }
check(values[0] == [] && values[1] == [-10] && values[2] == [10, 10, 10, 10], "array boundary examples")
check(values.all? { |a| a.length <= 4 && a.all? { |n| n >= -10 && n <= 10 } }, "generation bounds")
check(generator.shrink_candidates([10, 10], 3) == [[], [10], [10]], "chunk removal precedes elements with bounded allocation")
check(generator.shrink_candidates([10]).include?([0]), "elements shrink after size")
bounded = Hypo.arrays(of: Hypo.integers(min: 2, max: 9), min_size: 2, max_size: 3)
check(bounded.shrink_candidates([9, 9, 9]).all? { |a| a.length >= 2 && a.all? { |n| n >= 2 && n <= 9 } }, "shrinks stay in domain")
check(Hypo.arrays(of: Hypo.integers, max_size: 0).shrink_candidates([]) == [], "empty array minimal")

runner = Hypo::Runner.new([], executable: "test-runner", compiler_version: "test compiler")
seen = []
runner.property("mutating array bug", generator, at: ["arrays_test.rb", 1]) do |array|
  seen << array.dup
  failure = array.any? { |n| n >= 3 }
  array.clear
  runner.assert(!failure, "values below three")
end
check(runner.original_input == [10, 10, 10, 10], "original survives target mutation")
check(runner.reduced_input == [3], "array reduces to singleton threshold")
check(seen[-1] == [3] && seen[-2] != [], "confirmation uses fresh input")
check(!runner.unstable && runner.finish == 1, "mutation does not make failure unstable")

errors = 0
[[-1, 2], [2, 1], [0, 1001]].each do |bounds|
  begin
    Hypo.arrays(of: Hypo.integers, min_size: bounds[0], max_size: bounds[1])
  rescue Hypo::Error
    errors += 1
  end
end
begin
  Hypo.arrays(of: Hypo.booleans)
rescue Hypo::Error
  errors += 1
end
check(errors == 4, "invalid array domains rejected")
puts "Array properties: passed"

# Length, then total distance from the integer pivot strictly decreases.
[0, 1, 2].each do |minimum|
  [-2, 2].each do |lower|
    domain = Hypo.arrays(of: Hypo.integers(min: lower, max: 3), min_size: minimum, max_size: 3)
    pivot = lower > 0 ? lower : 0
    random = Hypo::Random.new(123)
    10.times do |index|
      original = domain.example(random, index)
      distance = original.map { |n| (n - pivot).abs }.sum
      domain.shrink_candidates(original).each do |candidate|
        check(candidate.length >= minimum && candidate.length <= original.length, "candidate size in bounds")
        check(candidate.all? { |n| n >= lower && n <= 3 }, "candidate elements in bounds")
        check(candidate.length < original.length || candidate.map { |n| (n - pivot).abs }.sum < distance, "strict array reduction")
      end
    end
  end
end
large = Hypo.arrays(of: Hypo.integers(min: 0, max: 2147483647), min_size: 1000, max_size: 1000)
check(large.shrink_candidates(Array.new(1000, 2147483647), 2).length == 2, "large candidate lists bounded by budget")

# Boundary arrays must not consume random draws, even for constant elements.
constant = Hypo.arrays(of: Hypo.integers(min: 7, max: 7), max_size: 3)
random = Hypo::Random.new(42)
3.times { |index| constant.example(random, index) }
check(random.next_u32 == 1083814273, "constant-element boundary arrays do not advance PRNG")
