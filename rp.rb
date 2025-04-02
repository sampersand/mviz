$*.replace %w[tmp2.ignore]
$encoding = Encoding::UTF_16BE

CHARACTERS = {}

CHARACTERS["\n".encode($encoding)] = "\n"
p CHARACTERS["\n".encode($encoding)]
exit

class Exception
  def self.~
    return if self === $!
    raise
  end
end

fail rescue p 1 if true
# $<.set_encoding 'utf-16' rescue ~SyntaxError and retry # ArgumentError
p $<.readpartial 8
