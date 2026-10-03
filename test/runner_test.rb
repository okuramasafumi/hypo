require_relative "../lib/hypo"

def check(condition, message)
  raise message unless condition
end

Hypo.configure(["--seed", "42", "--examples", "7"])
seen = []
Hypo.property "passing", Hypo.integers(min: -2, max: 2), at: [__FILE__, __LINE__] do |value|
  seen << value
  Hypo.assert(value >= -2 && value <= 2)
end
check(seen == [-2, 2, 0, -1, 1, 1, 1], "seeded inputs")
check(Hypo.finish == 0, "passing exit")

Hypo.configure([])
seen = []
Hypo.property "failing", Hypo.integers(min: -2, max: 2), at: [__FILE__, __LINE__] do |value|
  seen << value
  Hypo.assert(value < 0, "must be negative")
end
check(seen == [-2, 2], "stops at first failure")
check(Hypo.finish == 1, "failing exit")

Hypo.configure([])
Hypo.property "exception", Hypo.integers, at: [__FILE__, __LINE__] do |value|
  raise ArgumentError, "target error"
end
check(Hypo.finish == 1, "exception exit")

errors = 0
Hypo.configure([])
begin
  Hypo.property "two assertions", Hypo.integers, at: [__FILE__, __LINE__] do |value|
    Hypo.assert(true)
    Hypo.assert(true)
  end
rescue Hypo::Error
  errors += 1
end
Hypo.configure([])
begin
  Hypo.property "framework error", Hypo.integers, at: [__FILE__, __LINE__] do |value|
    raise Hypo::Error, "must escape failure rescue"
  end
rescue Hypo::Error
  errors += 1
end
Hypo.configure([])
begin
  Hypo.property "nonboolean", Hypo.integers, at: [__FILE__, __LINE__] do |value|
    Hypo.assert(1)
  end
rescue Hypo::Error
  errors += 1
end
Hypo.configure([])
begin
  Hypo.property "bad location", Hypo.integers, at: ["file.rb", 0] do |value|
    Hypo.assert(true)
  end
rescue Hypo::Error
  errors += 1
end
Hypo.configure([])
begin
  Hypo.finish
rescue Hypo::Error
  errors += 1
end
check(errors == 5, "configuration errors stay errors")

invalid_options = [["--seed", "-1"], ["--seed", "4294967296"], ["--seed", "1x"], ["--seed"], ["--examples", "0"], ["--examples", "1.5"], ["--unknown"], ["--seed", "1", "--seed", "2"]]
rejected = 0
invalid_options.each do |args|
  begin
    Hypo.configure(args)
  rescue Hypo::Error
    rejected += 1
  end
end
check(rejected == invalid_options.length, "invalid runtime options")
puts "property execution: passed"
