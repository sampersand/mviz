$*.replace %w[tmp2.ignore]

class Exception
  def self.~
    return if self === $!
    raise
  end
end

fail rescue p 1 if true
# $<.set_encoding 'utf-16' rescue ~SyntaxError and retry # ArgumentError
p $<.readpartial 8
