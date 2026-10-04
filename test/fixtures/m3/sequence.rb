Hypo.property "sequence", Hypo.arrays(of: Hypo.integers(min: -20, max: 20), max_size: 4), at: [__FILE__, __LINE__] do |a|
  puts "TRACE #{a.inspect}"
  Hypo.assert(true)
end
