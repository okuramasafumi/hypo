require_relative "version"

module Hypo
  module Help
    def self.runner
      <<~TEXT
        usage: EXECUTABLE [--seed N] [--examples N] [--shrink-limit N] [--property DESCRIPTION]
               EXECUTABLE --help | --version

        --seed N                Seed in 0..4294967295 (default: 0)
        --examples N            Cases per property in 1..2147483647 (default: 100)
        --shrink-limit N        Candidate evaluations in 0..1000 (default: 1000)
        --property DESCRIPTION  Select one exact, case-sensitive property description
        --help                  Show help without loading specifications
        --version               Show Hypo and build-compiler versions

        Numeric values are unsigned decimal integers. Options cannot be repeated.
        Exit codes: 0 all selected properties passed; 1 failure/unstable; 2 error.
        Replay commands require the same executable and deterministic target behavior.
      TEXT
    end

    def self.builder
      <<~TEXT
        Hypo #{VERSION}
        usage: hypo build SPEC.rb [SPEC.rb ...] -o EXECUTABLE
               hypo --help | --version

        Build explicit spec files in the given order using Spinel and its C toolchain.
        -o EXECUTABLE must follow the spec paths. The shell may expand globs.
        SPINEL selects a compiler path; otherwise "spinel" is resolved on PATH.
        Tested Spinel revision: #{SPINEL_REVISION}
        Build sources and compiler logs are retained under build/hypo/<id>/.
        Exit codes: 0 build succeeded; 2 usage, configuration, or compiler error.

        Produced executable options:
        #{runner}
      TEXT
    end
  end

  def self.information(args, compiler_version:)
    if args == ["--help"]
      puts Help.runner
      true
    elsif args == ["--version"]
      puts "Hypo #{VERSION}"
      puts "Compiler: #{compiler_version}"
      true
    else
      false
    end
  end
end
