# CRuby harness; every property executable and the builder run natively.
require "open3"
require "fileutils"
require "shellwords"

ROOT = File.expand_path("../..", __dir__)
WORK = File.join(ROOT, ".agents.local/m2/integration-#{Process.pid}")
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

cli = File.join(WORK, "hypo")
out, err, status = run(COMPILER, File.join(ROOT, "bin/hypo.rb"), "--require-gate", "-o", cli)
check(status == 0, "compile builder: #{err}")
# Shell metacharacters belong to this filename, never to shell syntax.
runner = File.join(WORK, %q{runner's $dollar $(touch INJECTED) ; test})
fixture = File.join(ROOT, "test/fixtures/m2/threshold.rb")
out, err, status = run(cli, "build", fixture, "-o", runner, env: {"SPINEL" => COMPILER})
check(status == 0, "build threshold: #{out} #{err}")
first = run(runner, "--seed", "42", "--examples", "100")
out, err, status = first
check(status == 1 && out.include?("original_input=100\n") && out.include?("reduced_input=10\n"), "shrink to ten: #{out} #{err}")
check(out.include?("threshold.rb:1") && out.include?("confirmation_evaluations=1"), "source and confirmation count")
compiler_version, _, compiler_status = run(COMPILER, "--version")
check(compiler_status == 0 && out.include?(compiler_version.strip), "actual compiler version reported")
check(out.include?("hypo_version="), "Hypo version reported")
replay_line = out.lines.find { |line| line.start_with?("  replay: ") }
check(!replay_line.nil?, "replay command printed")
replay = replay_line.delete_prefix("  replay: ").strip
check(Shellwords.split(replay) == [runner, "--seed", "42", "--examples", "100", "--shrink-limit", "1000", "--property", "threshold"], "complete replay arguments")
check(run("/bin/sh", "-c", replay) == first, "printed shell command exactly reproduces failure")
check(!File.exist?(File.join(WORK, "INJECTED")), "executable path is shell quoted")

limited = run(runner, "--seed", "42", "--examples", "100", "--shrink-limit", "1")
check(limited[2] == 1 && limited[0].include?("reduced_input=100\n") && limited[0].include?("shrink_status=budget_exhausted"), "budget report retains best")
limited_replay = limited[0].lines.find { |line| line.start_with?("  replay: ") }.delete_prefix("  replay: ").strip
check(run("/bin/sh", "-c", limited_replay) == limited, "budget is included in replay")
zero = run(runner, "--shrink-limit", "0")
check(zero[2] == 1 && zero[0].include?("shrink_evaluations=0") && zero[0].include?("confirmation_evaluations=1"), "zero budget still confirms")
invalid = run(runner, "--shrink-limit", "1001")
check(invalid[2] == 2, "budget cannot exceed 1000")

unstable_runner = File.join(WORK, "unstable")
out, err, status = run(cli, "build", File.join(ROOT, "test/fixtures/m2/unstable.rb"), "-o", unstable_runner, env: {"SPINEL" => COMPILER})
check(status == 0, "build unstable: #{err}")
out, err, status = run(unstable_runner)
check(status == 1 && out.include?('UNSTABLE "unstable"') && out.include?("confirmation=passed"), "unstable is a failure: #{out} #{err}")
check(out.include?("original_failure=assertion: first evaluation fails") && out.include?("RESULT unstable"), "unstable reports both observations")

# Reproduction after moving the executable must name its new invocation path.
portable = File.join(WORK, "moved ' executable")
FileUtils.cp(runner, portable)
empty_path = File.join(WORK, "empty-path")
FileUtils.mkdir_p(empty_path)
moved = run(portable, "--examples", "2", env: {"PATH" => empty_path})
moved_replay = moved[0].lines.find { |line| line.start_with?("  replay: ") }.delete_prefix("  replay: ").strip
check(Shellwords.split(moved_replay).first == portable, "moved binary replay path")
check(run("/bin/sh", "-c", moved_replay, env: {"PATH" => empty_path}) == moved, "replay needs neither Ruby nor compiler")
puts "M2 integration: #{$count} checks passed"
