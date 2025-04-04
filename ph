#!ruby -s
$w = ($w || 80).to_i
r, w = IO.popen './p -h', 'r'
while line = r.gets(chomp: true)
  line = line.ljust($w)
  line.insert($w, "\e[7m|")
  print line, "\e[27m\n"
end
