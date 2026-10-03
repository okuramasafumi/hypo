require_relative "hypo/runner"

module Hypo
  @runner = Runner.new([])

  def self.configure(args, executable: $0, compiler_version: "unrecorded")
    @runner = Runner.new(args, executable: executable, compiler_version: compiler_version)
  end

  def self.property(name, generator, at:)
    @runner.property(name, generator, at: at) { |value| yield value }
  end

  def self.assert(condition, message = "assertion failed")
    @runner.assert(condition, message)
  end

  def self.finish
    @runner.finish
  end
end
