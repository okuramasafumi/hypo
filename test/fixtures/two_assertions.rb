Hypo.property "too many assertions", Hypo.integers, at: [__FILE__, __LINE__] do |value|
  Hypo.assert(true)
  Hypo.assert(true)
end
