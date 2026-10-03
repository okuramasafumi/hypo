# CRuby-only process harness: expected failing children are successful test cases.
require "open3"
require "fileutils"

ROOT = File.expand_path("../..", __dir__)
WORK = File.join(ROOT, ".agents.local/m1/integration-#{Process.pid}")
COMPILER = ENV.fetch("SPINEL", "spinel")
FileUtils.mkdir_p(WORK)

$count = 0
def run(*command, env: {})
  output, error, status = Open3.capture3(env, *command, chdir: WORK)
  File.open(File.join(WORK, "commands.log"), "a") do |file|
    file.puts "COMMAND #{command.inspect}\nSTATUS #{status.exitstatus}\nSTDOUT\n#{output}STDERR\n#{error}"
  end
  [output, error, status.exitstatus]
end

def check(condition, message)
  raise message unless condition
  $count += 1
end

cli = File.join(WORK, "hypo")
out, err, status = run(COMPILER, File.join(ROOT, "bin/hypo.rb"), "--require-gate", "-o", cli)
check(status == 0, "compile CLI: #{err}")

def build(cli, name, output = name)
  destination = File.join(WORK, output)
  out, err, status = run(cli, "build", File.join(ROOT, "test/fixtures/#{name}.rb"), "-o", destination, env: {"SPINEL" => COMPILER})
  check(status == 0, "build #{name}: #{out} #{err}")
  check(File.executable?(destination), "#{name}: native output exists")
  destination
end

passing = build(cli, "passing", "passing runner's binary")
out, err, status = run(passing, "--seed", "42", "--examples", "7")
check(status == 0 && out.include?('PASS "absolute value is nonnegative" (7 examples)'), "passing property: #{out} #{err}")
check(out.include?("seed=42 examples=7") && out.include?("RESULT pass properties=1 examples=7"), "passing counts")
failing = build(cli, "failing")
first = run(failing, "--seed", "42", "--examples", "7")
second = run(failing, "--seed", "42", "--examples", "7")
check(first == second, "same binary/options reproduce failure")
check(first[2] == 1 && first[0].include?("input=10") && first[0].include?("example=2"), "known counterexample")
check(first[0].include?("test/fixtures/failing.rb:1"), "original spec location")
sampled = build(cli, "sampled_failure")
out, err, status = run(sampled, "--seed", "42", "--examples", "10")
# Independent known value: (1664525 * 42 + 1013904223) % 2^32 = 1083814273.
expected = -100 + (1083814273 % 201)
check(status == 1 && out.include?("input=#{expected}") && out.include?("example=6"), "known random counterexample: #{out} #{err}")
check(run(sampled, "--seed", "42", "--examples", "10") == [out, err, status], "random failure repeats")

[ ["--seed", "-1"], ["--examples", "0"], ["--seed"], ["--property", "nope"] ].each do |args|
  out, err, status = run(passing, *args)
  check(status == 2 && !out.include?("PASS"), "invalid options: #{args.inspect}")
end

# A copied runner must work without the compiler, Ruby, or source tree at run time.
portable = File.join(WORK, "portable")
FileUtils.cp(passing, portable)
empty_path = File.join(WORK, "empty-path")
FileUtils.mkdir_p(empty_path)
out, err, status = run(portable, "--examples", "1", env: {"PATH" => empty_path})
check(status == 0 && out.include?("(1 examples)"), "standalone runner")

[["empty", "no properties executed"], ["invalid_domain", "integer bounds"], ["two_assertions", "only one assertion"], ["two_properties", "one property per executable"]].each do |name, message|
  executable = build(cli, name)
  out, err, status = run(executable)
  check(status == 2 && err.include?(message) && !out.include?("RESULT pass"), "configuration error #{name}: #{out} #{err}")
end
executable = build(cli, "target_error")
out, err, status = run(executable)
check(status == 1 && out.include?("exception ArgumentError: target exploded"), "target exception: #{out} #{err}")

# Real compiler errors retain diagnostics and do not replace a previous output.
invalid_spec = File.join(WORK, "invalid.rb")
File.write(invalid_spec, "def broken(\n")
previous = File.binread(passing)
out, err, status = run(cli, "build", invalid_spec, "-o", passing, env: {"SPINEL" => COMPILER})
check(status == 2 && err.include?("compiler exited") && err.include?("build artifacts:"), "compiler error reported: #{err}")
check(File.binread(passing) == previous && !out.include?("built "), "failed build preserves existing output")
logs = Dir.glob(File.join(WORK, "build/hypo/*/compiler.log"))
check(logs.any? { |file| File.read(file).include?("syntax error") || File.read(file).include?("unexpected") }, "compiler diagnostic retained")

out, err, status = run(cli, "build", File.join(ROOT, "test/fixtures/passing.rb"), "-o", passing, env: {"SPINEL" => File.join(WORK, "missing-compiler")})
check(status == 2 && err.include?("missing-compiler") && File.binread(passing) == previous, "missing compiler preserves output")
out, err, status = run(cli, "build", File.join(WORK, "absent.rb"), "-o", passing, env: {"SPINEL" => COMPILER})
check(status == 2 && err.include?("spec file not found"), "missing spec")
out, err, status = run(cli, "build", invalid_spec, "-o", invalid_spec, env: {"SPINEL" => COMPILER})
check(status == 2 && File.read(invalid_spec) == "def broken(\n", "reject source overwrite")

# Exercise spec-relative loading, source locations, and shell-sensitive paths.
source_dir = File.join(WORK, "source with space and ' apostrophe")
FileUtils.mkdir_p(source_dir)
File.write(File.join(source_dir, "subject.rb"), "def local_absolute(value)\n  value.abs\nend\n")
local_spec = File.join(source_dir, "local.rb")
File.write(local_spec, <<~'SPEC')
  require_relative "subject"
  Hypo.property "local function", Hypo.integers, at: [__FILE__, __LINE__] do |value|
    Hypo.assert(local_absolute(value) >= 0)
  end
SPEC
local_runner = File.join(WORK, "local-runner")
out, err, status = run(cli, "build", local_spec, "-o", local_runner, env: {"SPINEL" => COMPILER})
check(status == 0, "local spec build: #{out} #{err}")
FileUtils.mv(source_dir, source_dir + ".hidden")
out, err, status = run(local_runner, "--examples", "3", env: {"PATH" => empty_path})
check(status == 0 && out.include?('PASS "local function" (3 examples)'), "runner survives source removal: #{out} #{err}")

escaped = File.join(WORK, 'source#{literal}.rb')
FileUtils.cp(File.join(ROOT, "test/fixtures/passing.rb"), escaped)
out, err, status = run(cli, "build", escaped, "-o", passing, env: {"SPINEL" => COMPILER})
check(status == 2 && err.include?("unsupported Ruby escapes") && File.binread(passing) == previous, "escaped source reference rejected")

out, err, status = run(cli, "--help")
check(status == 0 && out.include?("usage:"), "CLI help")
out, err, status = run(cli)
check(status == 2 && err.include?("usage:"), "CLI invalid usage")
puts "M1 integration: #{$count} checks passed"
