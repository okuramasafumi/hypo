require_relative "../lib/hypo"

def check(condition, message)
  raise message unless condition
end

# Use fixed metadata here; native integration tests check spec __FILE__/__LINE__.
runner = Hypo::Runner.new([], executable: "hypo-test-runner", compiler_version: "test compiler")
runner.property "threshold", Hypo.integers(min: 0, max: 100), at: ["shrinking_test.rb", 1] do |value|
  runner.assert(value < 10, "threshold")
end
check(runner.reduced_input == 10, "threshold must reduce to 10")
check(runner.original_input == 100, "original preserved")
check(runner.confirmation_evaluations == 1 && !runner.unstable, "confirmed once")
check(runner.finish == 1, "shrunk failure still fails")

positive = Hypo::Runner.new([], executable: "hypo-test-runner", compiler_version: "test compiler")
positive.property "positive domain", Hypo.integers(min: 5, max: 100), at: ["shrinking_test.rb", 1] do |value|
  raise Hypo::Error, "out of domain" unless value >= 5 && value <= 100
  positive.assert(value < 10, "positive threshold")
end
check(positive.reduced_input == 10, "positive domain shrink")
negative = Hypo::Runner.new([], executable: "hypo-test-runner", compiler_version: "test compiler")
negative.property "negative domain", Hypo.integers(min: -100, max: -5), at: ["shrinking_test.rb", 1] do |value|
  raise Hypo::Error, "out of domain" unless value >= -100 && value <= -5
  negative.assert(value > -10, "negative threshold")
end
check(negative.reduced_input == -10, "negative domain shrink")

assertion = Hypo::Runner.new([], executable: "hypo-test-runner", compiler_version: "test compiler")
assertion.property "preserve assertion", Hypo.integers(min: -100, max: 100), at: ["shrinking_test.rb", 1] do |value|
  raise ArgumentError, "different failure" if value == 0
  assertion.assert(value >= -10, "assertion identity")
end
check(assertion.reduced_input == -11, "exception must not replace assertion")
exception = Hypo::Runner.new([], executable: "hypo-test-runner", compiler_version: "test compiler")
exception.property "preserve exception", Hypo.integers(min: -100, max: 100), at: ["shrinking_test.rb", 1] do |value|
  raise TypeError, "different exception class" if value == 0
  raise ArgumentError, "bad input #{value}" if value < -10
end
check(exception.reduced_input == -11, "exception class preserved while message changes")

limited = Hypo::Runner.new(["--shrink-limit", "1"], executable: "hypo-test-runner", compiler_version: "test compiler")
limited.property "budget", Hypo.integers(min: 0, max: 100), at: ["shrinking_test.rb", 1] do |value|
  limited.assert(value < 10, "threshold")
end
check(limited.shrink_evaluations == 1 && limited.shrink_exhausted, "budget exhausted honestly")
check(limited.reduced_input == 100 && limited.confirmation_evaluations == 1, "budget retains and confirms best")
terminal = Hypo::Runner.new(["--shrink-limit", "0"], executable: "hypo-test-runner", compiler_version: "test compiler")
terminal.property "singleton", Hypo.integers(min: 7, max: 7), at: ["shrinking_test.rb", 1] do |value|
  terminal.assert(false, "always fails")
end
check(terminal.shrink_evaluations == 0 && !terminal.shrink_exhausted, "terminal is not budget exhaustion")
check(terminal.reduced_input == 7 && terminal.confirmation_evaluations == 1, "singleton confirmed")

class ChangingTarget
  attr_reader :calls

  def initialize
    @calls = 0
  end

  def passes?
    @calls += 1
    @calls > 1
  end

  def raise_changing
    @calls += 1
    raise ArgumentError, "original" if @calls == 1
    raise TypeError, "confirmation changed"
  end
end

unstable = Hypo::Runner.new([], executable: "hypo-test-runner", compiler_version: "test compiler")
target = ChangingTarget.new
unstable.property "unstable", Hypo.integers(min: 10, max: 10), at: ["shrinking_test.rb", 1] do |value|
  unstable.assert(target.passes?, "only first call fails")
end
check(unstable.unstable && target.calls == 2 && unstable.finish == 1, "unstable failure is not a pass")
changed = Hypo::Runner.new([], executable: "hypo-test-runner", compiler_version: "test compiler")
target = ChangingTarget.new
changed.property "changed exception", Hypo.integers(min: 10, max: 10), at: ["shrinking_test.rb", 1] do |value|
  target.raise_changing
end
check(changed.unstable && changed.finish == 1, "changed confirmation identity is unstable")

errors = 0
internal = Hypo::Runner.new([], executable: "hypo-test-runner", compiler_version: "test compiler")
begin
  internal.property "shrink configuration error", Hypo.integers(min: -100, max: 100), at: ["shrinking_test.rb", 1] do |value|
    raise Hypo::Error, "not a counterexample" if value == 0
    internal.assert(false, "trigger shrinking")
  end
rescue Hypo::Error
  errors += 1
end
["-1", "1001", "1x"].each do |limit|
  begin
    Hypo::Runner.new(["--shrink-limit", limit], executable: "hypo-test-runner", compiler_version: "test compiler")
  rescue Hypo::Error
    errors += 1
  end
end
check(errors == 4, "configuration errors propagate and limits are bounded")
puts "bounded shrinking and confirmation: passed"
