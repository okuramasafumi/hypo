require "pathname"
require_relative "errors"

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

    def self.call(spec, output, compiler)
      spec = File.expand_path(spec)
      output = File.expand_path(output)
      runtime = File.expand_path("../hypo.rb", __dir__)
      raise Error, "spec file not found: #{spec}" unless File.file?(spec)
      raise Error, "Hypo runtime source not found: #{runtime}" unless File.file?(runtime)
      if output == spec || output.end_with?(".rb")
        raise Error, "output must be a native executable path, not a Ruby source file"
      end
      directory = artifact_directory
      entry = File.join(directory, "runner.rb")
      pending = File.join(directory, "runner")
      log_path = File.join(directory, "compiler.log")
      source = reference(runtime, directory)
      source += "begin\nHypo.configure(ARGV)\n"
      source += reference(spec, directory)
      source += "exit Hypo.finish\nrescue StandardError => error\nwarn \"hypo: \" + error.class.to_s + \": \" + error.message\nexit 2\nend\n"
      File.write(entry, source)
      mkdir_p(File.dirname(output))
      begin
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
