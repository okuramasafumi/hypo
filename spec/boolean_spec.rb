Hypo.property "double negation preserves a Boolean", Hypo.booleans, at: [__FILE__, __LINE__] do |value|
  Hypo.assert(!!value == value)
end
