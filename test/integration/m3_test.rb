# CRuby orchestrates native builder and suite executables.
require "open3"
require "fileutils"
require "shellwords"

ROOT = File.expand_path("../..", __dir__)
WORK = File.join(ROOT, ".agents.local/m3/integration-#{Process.pid}")
COMPILER = ENV.fetch("SPINEL", "spinel")
FileUtils.mkdir_p(WORK)
$count = 0

def run(*command, env: {})
  out, err, status = Open3.capture3(env, *command, chdir: WORK)
  File.open(File.join(WORK, "commands.log"), "a") do |log|
    log.puts "COMMAND #{command.inspect}\nSTATUS #{status.exitstatus}\nSTDOUT\n#{out}STDERR\n#{err}"
  end
  [out, err, status.exitstatus]
end

def check(condition, message)
  raise message unless condition
  $count += 1
end

def fixture(name)
  File.join(ROOT, "test/fixtures/m3/#{name}.rb")
end

def build(cli, name, *specs)
  destination = File.join(WORK, name)
  out, err, status = run(cli, "build", *specs, "-o", destination, env: {"SPINEL" => COMPILER})
  check(status == 0, "build #{name}: #{out} #{err}")
  destination
end

cli = File.join(WORK, "hypo")
out, err, status = run(COMPILER, File.join(ROOT, "bin/hypo.rb"), "--require-gate", "-o", cli)
check(status == 0, "compile builder: #{err}")
suite = build(cli, "suite", fixture("core"), fixture("arrays"))
out, err, status = run(suite, "--seed", "42", "--examples", "7")
check(status == 1, "mixed suite fails: #{out} #{err}")
check(out.include?("RESULT fail properties=5 examples=21 passed=2 failed=3 unstable=0 declared=5"), "aggregate results: #{out}")
check(out.include?("original_input=true\n") && out.include?("reduced_input=true\n"), "Boolean failure retains true when false passes")
check(out.include?("original_input=[10, 10, 10, 10]\n") && out.include?("reduced_input=[3]\n"), "mutation-safe array shrink")
check(out.include?("m3/arrays.rb:3") && out.include?("m3/core.rb:7"), "native source locations")
name = %q{array's $value ; $(touch INJECTED)}
replay = out.lines.find { |line| line.start_with?("  replay:") && line.include?("array") }.delete_prefix("  replay: ").strip
check(Shellwords.split(replay).last(2) == ["--property", name], "quoted exact selector")
selected = run(suite, "--seed", "42", "--examples", "7", "--property", name)
check(run("/bin/sh", "-c", replay) == selected, "printed array replay reproduces selected result")
check(selected[2] == 1 && selected[0].include?("properties=1 examples=3 passed=0 failed=1 unstable=0 declared=5"), "filtered aggregate counts")
check(!File.exist?(File.join(WORK, "INJECTED")), "property name cannot inject shell commands")
limited = run(suite, "--examples", "7", "--shrink-limit", "1")
check(limited[2] == 1 && limited[0].scan("shrink_evaluations=1 ").length == 3, "each failed property gets independent shrink budget")
zero = run(suite, "--property", name, "--shrink-limit", "0")
check(zero[2] == 1 && zero[0].include?("reduced_input=[10, 10, 10, 10]") && zero[0].include?("confirmation_evaluations=1"), "zero array budget still confirms a fresh original")

sequence = build(cli, "sequence", fixture("sequence"))
forward = build(cli, "forward", fixture("unrelated"), fixture("sequence"))
reverse = build(cli, "reverse", fixture("sequence"), fixture("unrelated"))
expected = run(sequence, "--seed", "42", "--examples", "12")
check(expected[2] == 0, "standalone sequence")
[forward, reverse].each do |binary|
  [[], ["--property", "sequence"]].each do |selection|
    observed = run(binary, "--seed", "42", "--examples", "12", *selection)
    check(observed[2] == 0 && observed[0].lines.grep(/^TRACE/) == expected[0].lines.grep(/^TRACE/), "sequence isolated across ordering and filtering")
  end
end
check(run(sequence, "--seed", "43", "--examples", "12")[0].lines.grep(/^TRACE/) != expected[0].lines.grep(/^TRACE/), "array random sequence uses seed")

[["--property", "absent"], ["--property", "Sequence"], ["--property", ""], ["--property"], ["--property", "sequence", "--property", "sequence"]].each do |args|
  out, err, status = run(forward, *args)
  check(status == 2 && !out.include?("RESULT pass"), "invalid selection: #{args.inspect}")
end
duplicate = build(cli, "duplicate", fixture("sequence"), fixture("duplicate"), fixture("unrelated"))
[[], ["--property", "unrelated"]].each do |selection|
  out, err, status = run(duplicate, *selection)
  check(status == 2 && err.include?("duplicate property description"), "duplicate unselected names rejected")
end
unstable = build(cli, "unstable", File.join(ROOT, "test/fixtures/m2/unstable.rb"), fixture("unrelated"))
out, err, status = run(unstable, "--examples", "7")
check(status == 1 && out.include?("RESULT unstable properties=2 examples=8 passed=1 failed=1 unstable=1"), "unstable result survives subsequent pass")

["Hypo.arrays(of: Hypo.booleans)", "Hypo.arrays(of: Hypo.integers, min_size: -1)", "Hypo.arrays(of: Hypo.integers, min_size: 3, max_size: 2)", "Hypo.arrays(of: Hypo.integers, max_size: 1001)", "Hypo.arrays(of: Hypo.integers, min_size: 1.5)", 'Hypo.property " ", Hypo.booleans, at: [__FILE__, __LINE__] do |b|; end'].each_with_index do |source, index|
  path = File.join(WORK, "invalid-#{index}.rb")
  File.write(path, source + "\n")
  binary = build(cli, "invalid-#{index}", path)
  out, err, status = run(binary)
  check(status == 2 && err.include?("Hypo::Error"), "invalid array domain or declaration: #{source}: #{out} #{err}")
end

previous = File.binread(suite)
[[fixture("core"), fixture("core")], [fixture("core"), File.join(WORK, "missing.rb")]].each do |specs|
  out, err, status = run(cli, "build", *specs, "-o", suite, env: {"SPINEL" => COMPILER})
  check(status == 2 && File.binread(suite) == previous, "invalid input list preserves executable")
end
out, err, status = run(cli, "build", "-o", suite)
check(status == 2, "empty input list rejected")
puts "M3 integration: #{$count} checks passed"
