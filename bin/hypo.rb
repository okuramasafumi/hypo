require_relative "../lib/hypo/build"

usage = "usage: hypo build SPEC.rb [SPEC.rb ...] -o EXECUTABLE"
if ARGV == ["--help"]
  puts usage
  exit 0
end
unless ARGV.length >= 4 && ARGV[0] == "build" && ARGV[-2] == "-o"
  warn usage
  exit 2
end
begin
  specs = []
  index = 1
  while index < ARGV.length - 2
    specs << ARGV[index]
    index += 1
  end
  Hypo::Build.call(specs, ARGV[-1], ENV["SPINEL"] || "spinel")
rescue StandardError => error
  warn "hypo: #{error.class}: #{error.message}"
  exit 2
end
