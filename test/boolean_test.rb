require_relative "../lib/hypo"

def check(condition, message)
  raise message unless condition
end

generator = Hypo.booleans
random = Hypo::Random.new(42)
values = []
6.times { |index| values << generator.example(random, index) }
check(values == [false, true, true, false, true, false], "Boolean boundaries and seeded values")
check(generator.shrink_candidates(true) == [false], "true shrinks to false")
check(generator.shrink_candidates(false) == [], "false is minimal")
runner = Hypo::Runner.new([], executable: "test-runner", compiler_version: "test compiler")
seen = []
runner.property("Boolean failure", generator, at: ["boolean_test.rb", 1]) do |value|
  seen << value
  runner.assert(value, "must be true")
end
check(seen == [false, false], "minimal Boolean is confirmed")
check(runner.original_input == false && runner.reduced_input == false, "Boolean inputs retained")
check(runner.finish == 1, "Boolean failure exit")
puts "Boolean properties: passed"
