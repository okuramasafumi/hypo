require_relative "../lib/hypo/generators"

def check(condition, message)
  raise message unless condition
end

random = Hypo::Random.new(0)
expected = [1013904223, 1196435762, 3519870697, 2868466484, 1649599747]
expected.each { |value| check(random.next_u32 == value, "random known answer") }
check(Hypo::Random.new(4294967295).next_u32 == 1012239698, "maximum seed")
# Rejection must consume draws above the largest complete domain multiple.
random = Hypo::Random.new(0)
random.next_u32
random.next_u32
check(random.below(2147483649) == 1649599747, "rejection sampling")
check(random.next_u32 == 2670642822, "rejection consumed two extra draws")

random = Hypo::Random.new(42)
generator = Hypo.integers(min: -2, max: 2)
check((0...5).map { |index| generator.example(random, index) } == [-2, 2, 0, -1, 1], "boundary order")
check(random.next_u32 == 1083814273, "boundaries do not consume random state")
check(Hypo.integers(min: 7, max: 7).example(random, 100) == 7, "singleton")
positive = Hypo.integers(min: 2, max: 5)
negative = Hypo.integers(min: -5, max: -2)
wide = Hypo.integers(min: -2147483648, max: 2147483647)
1000.times do |index|
  pvalue = positive.example(random, index)
  nvalue = negative.example(random, index)
  wvalue = wide.example(random, index)
  check(pvalue >= 2 && pvalue <= 5, "positive domain")
  check(nvalue >= -5 && nvalue <= -2, "negative domain")
  check(wvalue >= -2147483648 && wvalue <= 2147483647, "full signed domain")
end
check(wide.example(Hypo::Random.new(0), 5) == -1133579425, "full width mapping")

invalid = 0
begin
  Hypo.integers(min: 3, max: 2)
rescue Hypo::Error
  invalid += 1
end
begin
  Hypo.integers(min: -2147483649, max: 0)
rescue Hypo::Error
  invalid += 1
end
begin
  Hypo.integers(min: 0, max: 2147483648)
rescue Hypo::Error
  invalid += 1
end
begin
  Hypo.integers(min: 0.5, max: 2)
rescue Hypo::Error
  invalid += 1
end
begin
  Hypo::Random.new(-1)
rescue Hypo::Error
  invalid += 1
end
begin
  Hypo::Random.new(4294967296)
rescue Hypo::Error
  invalid += 1
end
check(invalid == 6, "invalid domains and seeds")
puts "integer generation: passed"
