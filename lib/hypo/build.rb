require "pathname"
require_relative "errors"
require_relative "version"

module Hypo
  module Build
    def self.mkdir_p(directory)
      return if File.directory?(directory)
      parent = File.dirname(directory)
      mkdir_p(parent) unless parent == directory
      begin
        Dir.mkdir(directory)
      rescue Errno::EEXIST
        raise Error, "not a directory: #{directory}" unless File.directory?(directory)
      end
    end

    def self.artifact_directory
      parent = File.expand_path("build/hypo")
      mkdir_p(parent)
      index = 0
      loop do
        directory = File.join(parent, "#{Process.pid}-#{index}")
        begin
          Dir.mkdir(directory)
          return directory
        rescue Errno::EEXIST
          index += 1
        end
      end
    end

    def self.reference(path, directory)
      relative = Pathname.new(path).relative_path_from(Pathname.new(directory)).to_s
      literal = relative.dump
      if literal.include?("\\")
        raise Error, "source reference requires unsupported Ruby escapes: #{relative.inspect}"
      end
      "require_relative #{literal}\n"
    end

    def self.compiler_version(compiler, directory)
      log_path = File.join(directory, "compiler-version.log")
      log = File.open(log_path, "w")
      begin
        pid = Process.spawn(compiler, "--version", out: log, err: log)
        status = Process.waitpid2(pid)[1]
      ensure
        log.close
      end
      unless status.success?
        warn File.read(log_path)
        if status.signaled?
          raise Error, "compiler version command terminated by signal #{status.termsig}"
        end
        raise Error, "compiler version command exited #{status.exitstatus}"
      end
      version = File.read(log_path).strip
      raise Error, "compiler returned an empty version" if version.empty?
      version
    end

    # A distribution keeps lib/ beside bin/. Resolve PATH invocations and
    # symlinks before looking for that bundle; checkout builds use __dir__.
    def self.runtime_source(executable = $0)
      path = executable
      unless path.include?("/")
        (ENV["PATH"] || "").split(File::PATH_SEPARATOR).each do |directory|
          candidate = File.join(directory, executable)
          if File.file?(candidate) && File.executable?(candidate)
            path = candidate
            break
          end
        end
      end
      if File.file?(path)
        bundled = File.expand_path("../lib/hypo.rb", File.dirname(File.realpath(path)))
        return bundled if File.file?(bundled)
      end
      File.expand_path("../hypo.rb", __dir__)
    end

    def self.call(specs, output, compiler)
      raise Error, "SPINEL must name an executable, not be empty" if compiler.empty?
      raise Error, "at least one spec file is required" if specs.empty?
      specs = specs.map { |spec| File.expand_path(spec) }
      output = File.expand_path(output)
      runtime = runtime_source
      seen = []
      specs.each do |spec|
        raise Error, "spec file not found: #{spec}" unless File.file?(spec)
        raise Error, "duplicate spec file: #{spec}" if seen.include?(spec)
        seen << spec
      end
      raise Error, "Hypo runtime source not found: #{runtime}" unless File.file?(runtime)
      if specs.include?(output) || output.end_with?(".rb")
        raise Error, "output must be a native executable path, not a Ruby source file"
      end
      directory = artifact_directory
      entry = File.join(directory, "runner.rb")
      pending = File.join(directory, "runner")
      log_path = File.join(directory, "compiler.log")
      begin
        info_path = File.join(directory, "build-info.txt")
        info = "hypo_version=#{VERSION}\ncompiler=#{compiler.inspect}\noutput=#{output.inspect}\n"
        specs.each { |spec| info += "spec=#{spec.inspect}\n" }
        File.write(info_path, info)
        version = compiler_version(compiler, directory)
        File.write(info_path, info + "compiler_version=#{version.inspect}\n")
        source = reference(runtime, directory)
        source += "begin\nexit 0 if Hypo.information(ARGV, compiler_version: #{version.dump})\nHypo.configure(ARGV, compiler_version: #{version.dump})\n"
        specs.each { |spec| source += reference(spec, directory) }
        source += "exit Hypo.finish\nrescue StandardError => error\nwarn \"hypo: \" + error.class.to_s + \": \" + error.message\nexit 2\nend\n"
        File.write(entry, source)
        mkdir_p(File.dirname(output))
        log = File.open(log_path, "w")
        begin
          pid = Process.spawn(compiler, entry, "--require-gate", "-o", pending, out: log, err: log)
          result = Process.waitpid2(pid)
          status = result[1]
        ensure
          log.close
        end
        unless status.success?
          warn File.read(log_path)
          if status.signaled?
            raise Error, "compiler terminated by signal #{status.termsig}"
          end
          raise Error, "compiler exited #{status.exitstatus}"
        end
        raise Error, "compiler did not produce an executable" unless File.executable?(pending)
        File.rename(pending, output)
      rescue StandardError
        warn "build artifacts: #{directory}"
        raise
      end
      puts "built #{output}"
    end
  end
end
