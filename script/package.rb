# CRuby development tool; the packaged builder and generated runners are native.
require "fileutils"
require "open3"
require "tmpdir"
require_relative "../lib/hypo/version"

root = File.expand_path("..", __dir__)
unless ARGV.length == 1
  warn "usage: ruby script/package.rb NEW_DIRECTORY"
  exit 2
end
destination = File.expand_path(ARGV[0])
compiler = ENV.fetch("SPINEL", "spinel")
begin
  raise "destination already exists: #{destination}" if File.exist?(destination) || File.symlink?(destination)
  raise "SPINEL must name an executable, not be empty" if compiler.empty?
  artifacts = File.join(root, ".agents.local/package")
  FileUtils.mkdir_p(artifacts)
  stage = Dir.mktmpdir("hypo-", artifacts)
  FileUtils.mkdir_p(File.join(stage, "bin"))
  version, error, status = Open3.capture3(compiler, "--version")
  File.write(File.join(stage, "compiler-version.log"), version + error)
  raise "compiler version failed: #{status.inspect}" unless status.success? && !version.strip.empty?
  output, error, status = Open3.capture3(compiler, File.join(root, "bin/hypo.rb"), "--require-gate", "-o", File.join(stage, "bin/hypo"))
  File.write(File.join(stage, "compiler.log"), output + error)
  raise "compiler failed: #{status.inspect}" unless status.success? && File.executable?(File.join(stage, "bin/hypo"))
  FileUtils.cp_r(File.join(root, "lib"), stage)
  FileUtils.cp(File.join(root, "README.md"), stage)
  FileUtils.cp_r(File.join(root, "docs"), stage)
  FileUtils.cp_r(File.join(root, "spec"), stage)
  FileUtils.cp_r(File.join(root, "examples"), stage)
  File.write(File.join(stage, "BUILD_INFO"), "Hypo #{Hypo::VERSION}\nCompiler: #{version.strip}\nHost: #{RUBY_PLATFORM}\n")
  FileUtils.mkdir_p(File.dirname(destination))
  # Copy exclusively into a new directory. Partial copies are removed on error.
  Dir.mkdir(destination)
  begin
    Dir.children(stage).each { |name| FileUtils.cp_r(File.join(stage, name), destination) }
  rescue StandardError
    FileUtils.remove_entry(destination)
    raise
  end
  puts "packaged #{destination}"
rescue StandardError => error
  warn "hypo package: #{error.message}"
  warn "package artifacts: #{stage}" if stage
  exit 2
end
