# Use the distributed native CLI from an independent consumer project.
require "open3"
require "fileutils"
require "shellwords"

ROOT = File.expand_path("../..", __dir__)
WORK = File.join(ROOT, ".agents.local/m5/integration-#{Process.pid}")
COMPILER = ENV.fetch("SPINEL", "spinel")
FileUtils.mkdir_p(WORK)
$count = 0

def run(*command, chdir: WORK)
  out, err, status = Open3.capture3({"SPINEL" => COMPILER}, *command, chdir: chdir)
  File.open(File.join(WORK, "commands.log"), "a") do |log|
    log.puts "COMMAND #{command.inspect}\nCWD #{chdir}\nSTATUS #{status.exitstatus}\nSTDOUT\n#{out}STDERR\n#{err}"
  end
  [out, err, status.exitstatus]
end

def check(condition, message)
  raise message unless condition
  $count += 1
end

package = File.join(WORK, "Hypo's bundle")
out, err, status = run(RbConfig.ruby, File.join(ROOT, "script/package.rb"), package)
check(status == 0, "package builder: #{out} #{err}")
project = File.join(WORK, "consumer project")
FileUtils.cp_r(File.join(package, "examples/sorted_ints"), project)
cli = File.join(package, "bin/hypo")
command = [cli, "build", "spec/partition_spec.rb", "spec/insertion_spec.rb", "-o", "build/properties"]
out, err, status = run(*command, chdir: project)
check(status == 0, "consumer project build: #{out} #{err}")
runner = File.join(project, "build/properties")
out, err, status = run(runner, "--seed", "42", "--examples", "100", chdir: project)
check(status == 0 && out.include?("RESULT pass properties=3 examples=300"), "three real library contracts: #{out} #{err}")

# The consumer requires only its own library; generated source supplies Hypo.
check(!File.read(File.join(project, "spec/partition_spec.rb")).include?("lib/hypo"), "no consumer import of framework source")
entry = Dir.glob(File.join(project, "build/hypo/*/runner.rb")).fetch(0)
reference = File.read(entry).lines.first[/require_relative "([^"]+)"/, 1]
check(reference && File.expand_path(reference, File.dirname(entry)) == File.join(package, "lib/hypo.rb"), "builder uses packaged runtime")

# Plant a plausible exclusive-upper-bound mistake only in the copied project.
source = File.join(project, "lib/sorted_ints.rb")
correct = File.read(source)
check(correct.scan("high = numbers.length\n").length == 1, "one intended mutation site")
buggy = correct.sub("high = numbers.length\n", "high = numbers.length - 1\n")
File.write(File.join(WORK, "correct-library.rb"), correct)
File.write(File.join(WORK, "buggy-library.rb"), buggy)
File.write(source, buggy)
out, err, status = run(*command, chdir: project)
check(status == 0, "buggy target still compiles: #{out} #{err}")
out, err, status = run(runner, "--seed", "42", "--examples", "100", chdir: project)
check(status == 1 && out.include?("passed=0 failed=3"), "contracts detect the off-by-one bug: #{out} #{err}")
check(out.include?("original_input=[-20]\n") && out.include?("reduced_input=[-1]\n"), "array counterexample reduces to one negative element")
check(out.include?("spec/partition_spec.rb:5"), "consumer spec location preserved")
File.write(File.join(WORK, "failure.txt"), out)
replay = out.lines.find { |line| line.start_with?("  replay: ") }.delete_prefix("  replay: ").strip
check(Shellwords.split(replay).last(2) == ["--property", "lower_bound partitions at zero"], "failure selects exact contract")
selected = run(runner, "--seed", "42", "--examples", "100", "--property", "lower_bound partitions at zero", chdir: project)
check(run("/bin/sh", "-c", replay, chdir: project) == selected, "printed command reproduces selected failure exactly")

# A reduced example becomes a conventional regression assertion in the consumer.
regression = File.join(project, "regression.rb")
File.write(regression, <<~'REGRESSION')
  require_relative "lib/sorted_ints"
  raise "wrong insertion position for [-1]" unless SortedInts.lower_bound([-1], 0) == 1
  puts "regression passed"
REGRESSION
check(run(RbConfig.ruby, regression, chdir: project)[2] != 0, "reduced regression fails against buggy source")
File.write(source, correct)
check(run(RbConfig.ruby, regression, chdir: project)[2] == 0, "reduced regression passes after source fix")
check(run("/bin/sh", "-c", replay, chdir: project) == selected, "source edits do not silently replace a compiled executable")
out, err, status = run(*command, chdir: project)
check(status == 0, "rebuild fixed target: #{out} #{err}")
[0, 42, 4294967295].each do |seed|
  out, err, status = run(runner, "--seed", seed.to_s, "--examples", "100", chdir: project)
  check(status == 0 && out.include?("RESULT pass properties=3 examples=300"), "fixed library passes seed #{seed}: #{out} #{err}")
end
puts "M5 integration: #{$count} checks passed"
