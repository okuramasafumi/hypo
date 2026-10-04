# CRuby harness for native release and distribution behavior.
require "open3"
require "fileutils"
require "shellwords"
require "json"

ROOT = File.expand_path("../..", __dir__)
WORK = File.join(ROOT, ".agents.local/m4/integration-#{Process.pid}")
COMPILER = ENV.fetch("SPINEL", "spinel")
FileUtils.mkdir_p(WORK)
$count = 0

def run(*command, env: {}, chdir: WORK)
  out, err, status = Open3.capture3(env, *command, chdir: chdir)
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
check(status == 0, "compile builder: #{out} #{err}")
out, err, status = run(cli, "--version")
check(status == 0 && out.start_with?("Hypo 0.4.0\n"), "builder version: #{out} #{err}")
[["--help"], ["build", "--help"]].each do |args|
  out, err, status = run(cli, *args)
  check(status == 0 && out.include?("SPINEL") && out.include?("--property") && out.include?("--shrink-limit"), "complete builder help")
end
# Information requests must not load or execute even an invalid spec.
explosive = File.join(WORK, "explosive.rb")
File.write(explosive, 'raise "spec was executed"' + "\n")
runner = File.join(WORK, "explosive")
out, err, status = run(cli, "build", explosive, "-o", runner, env: {"SPINEL" => COMPILER})
check(status == 0, "build information-only fixture: #{out} #{err}")
out, err, status = run(runner, "--help")
check(status == 0 && out.include?("--seed") && out.include?("0..4294967295") && !out.include?("RESULT"), "runner help skips specs: #{out} #{err}")
out, err, status = run(runner, "--version")
compiler_version = run(COMPILER, "--version")[0].strip
check(status == 0 && out.include?("Hypo 0.4.0") && out.include?(compiler_version), "runner version includes build compiler")
check(run(runner)[2] == 2, "fixture really fails when loaded")
check(run(runner, "--help", "--examples", "1")[2] == 2, "help must be a standalone option")
# Every failed build retains its diagnostics and preserves an existing binary.
passing_spec = File.join(ROOT, "test/fixtures/passing.rb")
empty_compiler = run(cli, "build", passing_spec, "-o", runner, env: {"SPINEL" => ""})
check(empty_compiler[2] == 2 && empty_compiler[1].include?("SPINEL must name"), "empty compiler override rejected")
previous = File.binread(runner)
fake = File.join(WORK, "compiler's test tool")
File.write(fake, <<~'SH')
  #!/bin/sh
  if [ "$1" = "--version" ]; then echo 'fake compiler 1.0'; exit 0; fi
  echo 'deliberate compiler diagnostic' >&2
  exit 17
SH
FileUtils.chmod(0755, fake)
out, err, status = run(cli, "build", passing_spec, "-o", runner, env: {"SPINEL" => fake})
check(status == 2 && err.include?("compiler exited 17") && err.include?("deliberate compiler diagnostic"), "compiler status and diagnostics retained")
artifacts = err.lines.find { |line| line.start_with?("build artifacts: ") }.delete_prefix("build artifacts: ").strip
check(File.read(File.join(artifacts, "runner.rb")).include?("require_relative"), "generated entry retained")
info = File.read(File.join(artifacts, "build-info.txt"))
check(info.include?("hypo_version=0.4.0") && info.include?("fake compiler 1.0") && info.include?(passing_spec), "artifact build provenance")
check(File.read(File.join(artifacts, "compiler.log")).include?("deliberate compiler diagnostic"), "compiler log retained")
check(File.binread(runner) == previous, "failed compiler preserves output")

File.write(fake, "#!/bin/sh\nexit 23\n")
out, err, status = run(cli, "build", passing_spec, "-o", runner, env: {"SPINEL" => fake})
check(status == 2 && err.include?("compiler version command exited 23") && err.include?("build artifacts:"), "version command status retained")
check(File.binread(runner) == previous, "version failure preserves output")

escaped = File.join(WORK, 'source#{literal}.rb')
FileUtils.cp(passing_spec, escaped)
out, err, status = run(cli, "build", escaped, "-o", runner, env: {"SPINEL" => COMPILER})
check(status == 2 && err.include?("unsupported Ruby escapes") && err.include?("build artifacts:"), "source-emission failure reports artifacts")
# Package from a clean source copy, then remove that copy before using the CLI.
fresh = File.join(WORK, "fresh-checkout")
FileUtils.mkdir_p(fresh)
%w[bin lib script docs spec examples spin.toml README.md].each do |path|
  FileUtils.cp_r(File.join(ROOT, path), File.join(fresh, path)) if File.exist?(File.join(ROOT, path))
end
package = File.join(WORK, "package")
out, err, status = run(RbConfig.ruby, File.join(fresh, "script/package.rb"), package, env: {"SPINEL" => COMPILER})
check(status == 0, "package from clean source: #{out} #{err}")
check(File.executable?(File.join(package, "bin/hypo")) && File.file?(File.join(package, "lib/hypo.rb")), "package contains builder and runtime")
check(File.read(File.join(package, "BUILD_INFO")).include?(compiler_version), "package records compiler version")
check(run(RbConfig.ruby, File.join(fresh, "script/package.rb"), package, env: {"SPINEL" => COMPILER})[2] != 0, "package refuses existing destination")
FileUtils.mv(fresh, fresh + ".hidden")
moved = File.join(WORK, "moved package's directory")
FileUtils.mv(package, moved)
package_cli = File.join(moved, "bin/hypo")
links = File.join(WORK, "compiler tools")
FileUtils.mkdir_p(links)
FileUtils.ln_s(package_cli, File.join(links, "hypo"))
source_dir = File.join(WORK, "user sources")
FileUtils.mkdir_p(source_dir)
File.write(File.join(source_dir, "subject.rb"), "def acceptable(numbers)\n  numbers.all? { |n| n < 3 }\nend\n")
source = File.join(source_dir, "property.rb")
File.write(source, <<~'SPEC')
  require_relative "subject"
  Hypo.property "portable array", Hypo.arrays(of: Hypo.integers(min: 0, max: 10), max_size: 4), at: [__FILE__, __LINE__] do |numbers|
    result = acceptable(numbers)
    numbers.clear
    Hypo.assert(result)
  end
SPEC
portable = File.join(WORK, "portable runner")
out, err, status = run("hypo", "build", source, "-o", portable, env: {"SPINEL" => COMPILER, "PATH" => links + File::PATH_SEPARATOR + ENV.fetch("PATH")})
check(status == 0, "moved package builds through PATH symlink: #{out} #{err}")
# An unset SPINEL uses PATH, including a compiler path containing spaces.
compiler_path = COMPILER.include?("/") ? File.expand_path(COMPILER) : ENV.fetch("PATH").split(File::PATH_SEPARATOR).map { |part| File.join(part, COMPILER) }.find { |path| File.executable?(path) && File.file?(path) }
raise "compiler not found on PATH" unless compiler_path
FileUtils.ln_s(compiler_path, File.join(links, "spinel"))
out, err, status = run("hypo", "build", source, "-o", portable, env: {"SPINEL" => nil, "PATH" => links + File::PATH_SEPARATOR + ENV.fetch("PATH")})
check(status == 0, "compiler PATH fallback: #{out} #{err}")
FileUtils.mv(moved, moved + ".hidden")
FileUtils.mv(source_dir, source_dir + ".hidden")
empty_path = File.join(WORK, "empty-path")
FileUtils.mkdir_p(empty_path)
result = run(portable, "--seed", "42", env: {"PATH" => empty_path})
check(result[2] == 1 && result[0].include?("reduced_input=[3]"), "runner survives removal of builder/runtime/spec sources and tools")
replay = result[0].lines.find { |line| line.start_with?("  replay: ") }.delete_prefix("  replay: ").strip
check(run("/bin/sh", "-c", replay, env: {"PATH" => empty_path}) == result, "standalone packaged replay")
puts "M4 integration: #{$count} checks passed"
