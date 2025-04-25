#!ruby -s
$w = ($w || 100).to_i
r, w = IO.popen './p --help', 'r'
while line = r.gets(chomp: true)
  line = line.ljust($w)
  line.insert($w, "\e[7m|")
  print line, "\e[27m\n"
end
