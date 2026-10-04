require_relative "../lib/hypo"

def check(condition, message)
  raise message unless condition
end

runner = Hypo::Runner.new(["--examples", "7"], executable: "test-runner", compiler_version: "test compiler")
runner.property("integer fails", Hypo.integers, at: ["suite_test.rb", 1]) { |n| runner.assert(false, "integer") }
seen = []
runner.property("Boolean passes", Hypo.booleans, at: ["suite_test.rb", 2]) { |b| seen << b; runner.assert(true, "Boolean") }
runner.property("array fails", Hypo.arrays(of: Hypo.integers), at: ["suite_test.rb", 3]) { |a| runner.assert(false, "array") }
check(seen.length == 7, "suite continues after failure with different input types")
check(runner.finish == 1, "failures aggregate")

selected = Hypo::Runner.new(["--property", "chosen", "--seed", "42", "--examples", "7"], executable: "test-runner", compiler_version: "test compiler")
selected.property("skipped", Hypo.booleans, at: ["suite_test.rb", 4]) { |b| raise "must not run" }
sequence = []
selected.property("chosen", Hypo.integers(min: -2, max: 2), at: ["suite_test.rb", 5]) { |n| sequence << n }
check(sequence == [-2, 2, 0, -1, 1, 1, 1], "filtered sequence")
check(selected.finish == 0, "selected suite passes")

errors = 0
begin
  selected.property("skipped", Hypo.booleans, at: ["suite_test.rb", 6]) { |b| }
rescue Hypo::Error
  errors += 1
end
unmatched = Hypo::Runner.new(["--property", "missing"])
unmatched.property("present", Hypo.integers, at: ["suite_test.rb", 7]) { |n| }
begin
  unmatched.finish
rescue Hypo::Error
  errors += 1
end
[["--property"], ["--property", ""], ["--property", "a", "--property", "b"]].each do |args|
  begin
    Hypo::Runner.new(args)
  rescue Hypo::Error
    errors += 1
  end
end
check(errors == 5, "duplicates including unselected declarations and invalid selection rejected")
puts "Suites: passed"
