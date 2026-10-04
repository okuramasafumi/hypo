# Run the same release gate locally and in CI. Requires CRuby, Spinel, and cc.
require "open3"
require "fileutils"
require "json"
require_relative "../lib/hypo/version"

ROOT = File.expand_path("..", __dir__)
LOGS = File.join(ROOT, ".agents.local/ci/#{Process.pid}")
FileUtils.mkdir_p(LOGS)
$stdout.sync = true
$step = 0

def run(*command, expected: 0, contains: nil)
  $step += 1
  puts "$ #{command.join(' ')}"
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  out, err, status = Open3.capture3(*command, chdir: ROOT)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  File.write(File.join(LOGS, "%02d.log" % $step), "#{command.inspect}\nstatus=#{status.exitstatus}\n#{out}#{err}")
  print out
  warn err unless err.empty?
  raise "unexpected status #{status.inspect}" unless status.exitstatus == expected
  raise "missing expected output #{contains.inspect}" if contains && !out.include?(contains)
  [out, elapsed]
end

compiler = ENV.fetch("SPINEL", "spinel")
spin = ENV.fetch("SPIN", "spin")
version = run(compiler, "--version")[0].strip
revision = version[/\(([0-9a-f]{7,40})\)/, 1]
raise "release checks require Spinel #{Hypo::SPINEL_REVISION}; got #{version}" unless revision && Hypo::SPINEL_REVISION.start_with?(revision)
raise "no unit programs found" if Dir.glob(File.join(ROOT, "test/*_test.rb")).empty?
run(spin, "test")
run(spin, "build")
%w[m1 m2 m3 m4 m5].each { |milestone| run(RbConfig.ruby, "test/integration/#{milestone}_test.rb") }

cli = File.join(ROOT, "build/bin/hypo")
passing = File.join(ROOT, "build/absolute_value_spec")
run(cli, "build", "spec/absolute_value_spec.rb", "-o", passing)
run(passing, "--seed", "42", "--examples", "100", contains: "RESULT pass properties=1 examples=100")
suite = File.join(ROOT, "build/suite")
build_seconds = run(cli, "build", "spec/boolean_spec.rb", "spec/array_absolute_value_spec.rb", "-o", suite)[1]
execution_seconds = run(suite, "--seed", "42", "--examples", "100", contains: "RESULT pass properties=2 examples=200")[1]
run(suite, "--property", "array absolute values are nonnegative", "--seed", "42", "--examples", "100", contains: "properties=1 examples=100")
run(suite, "--seed", "invalid", expected: 2)
%w[buggy_absolute_value buggy_array_absolute_value].each do |example|
  binary = File.join(ROOT, "build/#{example}")
  run(cli, "build", "spec/#{example}_spec.rb", "-o", binary)
  input = example == "buggy_absolute_value" ? "10" : "[10]"
  run(binary, "--seed", "42", "--examples", "100", expected: 1, contains: "reduced_input=#{input}\n")
end
measurement = {hypo_version: Hypo::VERSION, compiler: version, host: RUBY_PLATFORM,
               specs: ["spec/boolean_spec.rb", "spec/array_absolute_value_spec.rb"], seed: 42,
               examples_per_property: 100, build_seconds: build_seconds,
               binary_bytes: File.size(suite), execution_seconds: execution_seconds}
File.write(File.join(LOGS, "measurement.json"), JSON.pretty_generate(measurement) + "\n")
puts "Release checks passed. Logs and workload measurement: #{LOGS}"
