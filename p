#!/usr/bin/env -S ruby -Ebinary --disable=all
# frozen-string-literal: true
defined?(RubyVM::YJIT.enable) and RubyVM::YJIT.enable

require 'optparse'

####################################################################################################
#                                                                                                  #
#                                         Parse Arguments                                          #
#                                                                                                  #
####################################################################################################

$isatty = $stdout.tty?
OptParse.new do |op|
  op.version = '1.0'
  op.banner = <<~BANNER
    usage: #{op.program_name} [options] [string ...]
           #{op.program_name} -f/--files [options] [file ...]
    With no arguments, second form is assumed if stdin isnt a tty.
  BANNER

  op.separator "\nGeneric Options"

  op.on '-h', '--help', 'Print this and then exit' do puts op.help; exit end
  op.on       '--version', 'Print the version' do puts op.ver; exit end
  op.on '-f', '--files', 'Interpret arguments as filenames to be read instead of strings' do $files = true end

  op.separator "\nHow to Output (todo: clean this section up)"
  # This has to be cleaned up a bit.
  op.on '--[no-]number-lines', '--[no-]heading', 'Number args without -f; add headings with -f. (default: true if output is a tty)' do |x| $number_lines = x end
  op.on       '--trailing-newline', 'Print a final trailing newline; only useful with -f. (default)' do $no_newline = false end
  op.on '-n', '--no-trailing-newline', 'Suppress final trailing newline.' do $no_newline = true end
  # op.on '-N', '--[no-]number-lines', 'Number arguments; defaults to on when output is a TTY' do |nl| $number_lines = nl end

  op.separator "\nWhat to Escape."

  op.on       '--[no-]escape-newline', 'Escape newlines. (default)' do |x| $escape_newline = x end
  op.on '-l', 'Shorthand for --no-escape-newline. ("Line-oriented mode")' do $escape_newline = false end
  op.on       '--[no-]escape-tab', 'Escape tabs. (default)' do |x| $escape_tab = x end
  op.on '-t', 'Shorthand for --no-escape-tabs.' do $escape_tab = false end

  op.on '-s', '--[no-]escape-space', 'Escape spaces by visualizing them. Only useful in visual mode.' do |es| $escape_space = es end

  op.on '--[no-]escape-outer-space', 'Visualize leading and trailing whitespace. (default); not useful with -f' do |ess|
    $escape_surronding_spaces = ess
  end

  op.on '-B', '--[no-]escape-backslash', 'Escape backslashes (default when in visual)' do |eb|
    $escape_backslash = eb
  end

  op.on '-U', '--[no-]escape-unicode', 'Escape non-ASCII Unicode characters via `\u{...}`' do |eu|
    $escape_unicode = eu
  end

  op.on '-P', '--[no-]escape-print', 'Escape all non-print characters (including unicode ones) TODO' do |ep| $escape_print = ep end
  # op.on '-a', '--escape-all', 'Escapes all characters' do $escape_space = $escape_backslash = $escape_tab = $escape_newline = $escape_unicode = true end
  # op.on '-w', '--no-escape-whitespace', 'Do not escape whitespace' do $escape_space = $escape_tab = $escape_newline = $escape_surronding_spaces = false end

  op.separator "\nHow to Escape"
  op.on '-d', '--delete', 'Delete invalid characters instead of printing them' do
    $delete = true
  end

  op.on '-v', '--visualize', 'Enable visual effects. (default: when output is a tty)' do $visual = true end
  op.on '-V', '--no-visualize', "Don't enable visual effects" do $visual = false end
  op.on       '--[no-]visualize-invalid', 'Enable a separator colour for invalid bytes when in visual mode',
                                          'Not all output encodings have invalid bytes, eg -b. (default)' do |iv| $invalid_visual = iv end
  op.on       '--c-escapes', 'Use C-style escapes (\n, \t, etc, and \xHH). (default)' do $c_escapes = true end
  op.on '-x', '--hex-escapes', "Escape in \\xHH format. (doesn't affect backslashes or unicode)" do $c_escapes = false end

  op.on "\nOutput Encodings (all inputs are assumed binary)"
  op.on '-E', '--encoding=ENCODING', 'The output encoding; Specify `list` for the list.' do |enc|
    if enc == 'list'
      puts "available encodings: #{(Encoding.name_list - %w[external internal]).join(', ')}"
      exit
    end

    $encoding = Encoding.find enc rescue op.abort
  end
  alias $output_encoding $encoding

  op.on '-u', '-8', '--utf-8', 'Equivalent to --encoding=UTF-8. (default)' do $encoding = Encoding::UTF_8 end
  op.on '-b', '--binary', '--bytes', 'Equivalent to --encoding=binary. (All bytes are valid.)' do $encoding = Encoding::BINARY end
  op.on '-a', '--ascii', 'Equivalent to --encoding=ascii. (8th bit bytes are invalid.)' do $encoding = Encoding::ASCII end
  op.on '-L', '--locale', 'Equivalent to --encoding=locale, i.e. what LC_ALL/LC_CTYPE/LANG specify.' do $encoding = Encoding.find('locale') end

  op.on '--[no-]encoding-failure-err', 'Invalid bytes cause non-zero exit. (default: output isnt a tty)' do |efe| $encoding_failure_error = efe end

  op.on_tail "\nnote: IF any invalid bytes for the output encoding are read, the exit status is based on `--encoding-failure-err`"



  op.require_exact = true if defined? op.require_exact = true
  op.on 'ENVIRONMENT: P_BEGIN_STANDOUT; P_END_STANDOUT; P_BEGIN_ERR; P_END_ERR'

  op.parse! rescue op.abort # <-- only cares about flags when POSIXLY_CORRECT is set.
  # op.order! rescue op.abort <-- does care about order of flags
end

# Fetch standouts (regardless of whether they're being used)
BEGIN_STANDOUT = ENV.fetch('P_BEGIN_STANDOUT', "\e[7m")
END_STANDOUT   = ENV.fetch('P_END_STANDOUT',   "\e[27m")
BEGIN_ERR      = ENV.fetch('P_BEGIN_ERR',      "\e[37m\e[41m")
END_ERR        = ENV.fetch('P_END_ERR',        "\e[49m\e[39m")

# Specify defaults
defined? $files                    or $files = !$stdin.tty? && $*.empty?
defined? $visual                   or $visual = $stdout.tty?
defined? $encoding_failure_error   or $encoding_failure_error = !$stdout.tty?
defined? $escape_spaces            or $escape_spaces = !$files
defined? $escape_tab               or $escape_tab = true
defined? $escape_newline           or $escape_newline = true
defined? $number_lines             or $number_lines = $stdout.tty?
defined? $escape_backslash         or $escape_backslash = !$visual
defined? $invalid_visual           or $invalid_visual = true
defined? $escape_surronding_spaces or $escape_surronding_spaces = true
defined? $encoding                 or $encoding = Encoding.find('locale')
defined? $c_escapes                or $c_escapes = true


####################################################################################################
#                                                                                                  #
#                                        Create Escape Hash                                        #
#                                                                                                  #
####################################################################################################

# Visualize a character in hex format
def visualize_hex(char, **b)
  visualize(char.each_byte.map { |byte| '\x%02X' % byte }.join, **b)
end

# Add "visualize" escape sequences to a string; all escaped characters should be passed to this, as
# visual effects are the whole purpose of the `p` program.
# - if `$delete` is specified, then an empty string is returned---escaped characters are deleted.
# - if `$visual` is specified, then `start` and `stop` surround `string`
# - else, `string` is returned.
def visualize(string, start: BEGIN_STANDOUT, stop: END_STANDOUT)
  return '' if $delete

  if $visual
    "#{start}#{string}#{stop}"
  else
    string
  end
end

## Construct the `ESCAPES` hash, whose keys are characters, and values are the desired escape
# sequences.
ESCAPES = Hash.new

## Default escape sequences

# Set the default escapes for all "C0" control characters, as well as `DEL`.
[*0x00...0x20, 0x7F].map { |c| c.chr $output_encoding }.each do |char|
  ESCAPES[char] = visualize_hex(char)
end

## Normal print characters
(0x20...0x7F).map{ |c| c.chr $encoding }.each do |char|
  ESCAPES[char] = char
end

# If the user specified "c-style escapes" (the default), then replace the escapes for a specific
# subset of characters with their C-style escape equivalents.
if $c_escapes
  ESCAPES["\0"] = visualize '\0'
  ESCAPES["\a"] = visualize '\a'
  ESCAPES["\b"] = visualize '\b'
  ESCAPES["\t"] = visualize '\t'
  ESCAPES["\n"] = visualize '\n'
  ESCAPES["\v"] = visualize '\v'
  ESCAPES["\f"] = visualize '\f'
  ESCAPES["\r"] = visualize '\r'
  ESCAPES["\e"] = visualize '\e'
end

# If the user disabled escaping of newlines or tabs, then reset them to their "unescaped" state.
ESCAPES["\n"] = "\n" unless $escape_newline
ESCAPES["\t"] = "\t" unless $escape_tab
ESCAPES['\\'] = visualize('\\\\') if $escape_backslash
ESCAPES[' ']  = visualize(' ') if $escape_space

# Upper bits, for binary encodings
if $encoding == Encoding::BINARY
  (0x80..0xFF).map{ |c| c.chr $encoding }.each do |char|
    ESCAPES[char] = visualize_hex(char)
  end
end

ESCAPES.default_proc = proc do |hash, char|
  hash[char] = if !char.valid_encoding?
    $ENCODING_FAILED = true
    $invalid_visual ? visualize_hex(char, start: BEGIN_ERR, stop: END_ERR) : visualize_hex(char)
  elsif $escape_unicode || ($escape_print && char =~ /\p{Graph}/)
    visualize('\u{%04X}' % char.codepoints.sum)
  else
    char
  end
end

####################################################################################################
#                                                                                                  #
#                                         Handle Arguments                                         #
#                                                                                                  #
####################################################################################################

CAPACITY = 4096
OUTPUT = String.new(capacity: CAPACITY * 8, encoding: Encoding::BINARY)

def handle(string)
  OUTPUT.clear

  string.each_char do |char|
    OUTPUT << ESCAPES[char]
  end

  $stdout.write OUTPUT
end


# TODO: allow for `p filename`
if !$files
  $*.each_with_index do |arg, idx|
    $number_lines and printf "%5d: ", idx + 1
    arg = (+arg)

    if $escape_surronding_spaces
      arg.force_encoding Encoding::BINARY
      x = arg.slice!(/\A */) and $stdout.write visualize x
      rest = arg.slice!(/ *\z/)
    end

    handle arg.force_encoding $encoding
    rest and $stdout.write visualize rest
    puts
  end
else
  INPUT = String.new(capacity: CAPACITY, encoding: $encoding)
  $*.unshift '/dev/stdin' if $*.empty?
  while (arg = $*.shift)
    open arg, 'rb', encoding: 'binary' do |file|
      $number_lines and print "\n==[#{arg}]==\n" # TODO: clean this up
      loop do
        begin
          file.sysread(CAPACITY, INPUT)
        rescue EOFError
          break
        end

        (INPUT.prepend $tmp; $tmp = nil) if $tmp
        if !(q=INPUT.byteslice(-1..)).valid_encoding?
          if !(q=INPUT.byteslice(-2..)).valid_encoding?
            if !(q=INPUT.byteslice(-3..)).valid_encoding?
              # Need to support versions without `.bytesplice`
              $tmp = q; INPUT.force_encoding('binary').slice!(-3..); INPUT.force_encoding $encoding
            else
              $tmp = q; INPUT.force_encoding('binary').slice!(-2..); INPUT.force_encoding $encoding
            end
          else
            $tmp = q; INPUT.force_encoding('binary').slice!(-1..); INPUT.force_encoding $encoding
          end
        end

        handle INPUT
      end

      $tmp and handle $tmp
    end
  end

  $no_newline and $stdout.syswrite "\n"
end

$encoding_failure_error and exit $ENCODING_FAILED
