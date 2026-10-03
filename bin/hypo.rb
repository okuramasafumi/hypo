require_relative "../lib/hypo/build"

usage = "usage: hypo build SPEC.rb -o EXECUTABLE"
if ARGV == ["--help"]
  puts usage
  exit 0
end
unless ARGV.length == 4 && ARGV[0] == "build" && ARGV[2] == "-o"
  warn usage
  exit 2
end
begin
  Hypo::Build.call(ARGV[1], ARGV[3], ENV["SPINEL"] || "spinel")
rescue StandardError => error
  warn "hypo: #{error.class}: #{error.message}"
  exit 2
end
