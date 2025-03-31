#!/usr/bin/env -S ruby -Ebinary --disable=all
# -*- encoding: binary; frozen-string-literal: true -*-
defined?(RubyVM::YJIT.enable) and RubyVM::YJIT.enable

require 'optparse'

## Default escape sequences
# Encoding.default_internal = Encoding::UTF_8

####################################################################################################
#                                                                                                  #
#                                         Parse Arguments                                          #
#                                                                                                  #
####################################################################################################

$stdout_tty = $stdout.tty?
OptParse.new do |op|
  $op = op
  op.version = '1.2'
  op.banner = <<~BANNER
    usage: #{op.program_name} [options] [string ...]
           #{op.program_name} -f/--files [options] [file ...]
    When no arguments, and stdin isn't a tty, the second form is assumed.
  BANNER
  op.require_exact = true if defined? op.require_exact = true

  op.accept :chars do |c|
    c.undump
    # %|"#{c.gsub('"', '\"')}"|.undump
  end

  op.separator "\nGeneric Options"
  op.on '-h', '--help', 'Print this message and exit' do puts op.help; exit end
  op.on       '--version', 'Print the version and exit' do puts op.ver; exit end
  op.on '-f', '--files', 'Interpret arguments as filenames to read, not strings' do $files = true end
  op.on       '--[no-]assume-tty', 'Pretend stdout is tty for defaults' do |tty| $stdout_tty = tty end

  # TODO: make custom separators like space between fields... but figure out a "Trailing sep"?
  op.separator "\nHow to separate fields"
  op.on       '--heading', 'Add headers to the output (default if stdout is a tty)' do $headings = true end
  op.on '-N', '--no-heading', 'Do not add headers to the output' do $headings = false end
  op.on       '--[no-]trailing-newline', 'Print trailing newlines; only used with --no-headers. (default)' do |tnl| $trailing_newline = tnl end
  op.on '-n', '--no-heading-or-newline', 'Disables both headeres and trailing newliens' do $headings = $trailing_newline = false end

  op.separator "\nWhat to Escape"
  $unescape_chars = +""; $escape_chars = +""
  op.on '-u', '--unescape=CHARS', :chars, 'Do not escape CHARS' do |c| $unescape_chars.concat c end
  op.on '--unescape-all', 'Do not escape any characters' do $unescape_all = true end
  op.on '-e', '--escape=CHARS', :chars, 'Explicitly escape CHARS' do |c| $escape_chars.concat c end
  op.on '--escape-all', 'Explicitly escape all (non-ASCII, non-visible) characters' do $escape_all = true end

  op.on '-l', "Same as --unescape='\\n'. (\"Line-oriented mode\")" do $unescape_chars.concat "\n" end
  op.on '-w', "Same as --unescape='\\n\\t ' (newline, tab, space)" do $unescape_chars.concat "\n\t " end
  op.on '-B', "Same as --escape='\\\\' (backslash)" do $unescape_chars.concat '\\' end
  op.on '-s', "Same as --escape=' ' (space)" do $escape_chars.concat "\s" end
  op.on '-U', '--[no-]escape-unicode', 'Escape non-ASCII Unicode characters with "\u{...}"' do |eu| $escape_how = :unicode end
  # space)" do $escape_chars.concat "\s" end

  # op.on       '--escape-tab', 'Escape tabs. (default)' do |x| $escape_tab = x end
  # op.on '-t', '--no-escape-tab', 'Shorthand for --no-escape-tabs.' do $escape_tab = false end
  # op.on '-s', '--[no-]escape-space', 'Escape spaces; Only useful in visual mode.' do |es| $escape_space = es end
  # op.on '-w', '--no-escape-whitespace', 'Do not escape whitespace (space, tab, newline)' do
  #   $escape_tab = $escape_space = $escape_newline = false
  # end
  # op.on       '--[no-]escape-outer-space', 'Visualize leading and trailing spaces. (default)', 'Only useful in visual mode' do |ess| $escape_surronding_spaces = ess end
  # op.on '-B', '--[no-]escape-backslash', 'Escape backslashes (default when in visual)' do |eb| $escape_backslash = eb end

  op.separator "\nHow to Escape"
  op.on '-v', '--visualize', 'Enable visual effects. (default when stdout is a tty)' do $visual = true end
  op.on '-V', '--no-visualize', 'Do not enable visual effects' do $visual = false end

  op.on '--escape-with=WHAT', 'How to escape (valid options: dot, delete, bytes, codepoints)',
    %w[dot delete bytes codepoints] do |how| $escape_how = how.to_sym end
  op.on '-.', 'Alias for --escape-with=dot; Escape with dots, instead of other characters' do $escape_how = :dot end
  op.on '-d', 'Alias for --escape-with=delete; Delete escaped characters instead of printing their escapes' do $escape_how = :delete end
  op.on '-x', 'Alias for --escape-with=bytes; Use \xHH for escapes. (default)' do $escape_how = :bytes end
  op.on '-c', 'Alias for --escape-with=codepoints; Use \u{...} for escapes.' do $escape_how = :codepoints end

  # Options for a specific subset
  op.on '-C', '--C-escapes', 'Use C-style escapes (\n, \t, etc). (default)' do $c_escapes = true end
  op.on '-P', '--control-pictures', 'Use "control pictures" (U+240x..U+242x) for some escapes' do $pictures = true end


  # Implementation note: Even though these usage messages reference "input encodings," the input is
  # actually always read as binary data, and then attempted to be converted to whatever these
  # encodings are
  op.separator "\nInput Encodings"
  op.on '-E', '--encoding=ENCODING', "Specify the input data's encoding. Case insensitive" do |enc|
    $encoding = Encoding.find enc rescue op.abort
  end
  op.on       '--list-encodings', 'List all possible encodings' do
    puts "available encodings: #{(Encoding.name_list - %w[external internal]).join(', ')}"
    exit
  end
  op.on '-b', '--binary', '--bytes', 'Alias for -Ebinary; High-bit bytes are escaped.' do $encoding = Encoding::BINARY end
  op.on '-a', '--ascii', 'Alias for -Eascii. Like -b, but high-bit bytes are invalid.' do $encoding = Encoding::ASCII end
  op.on '-8', '--utf-8', 'Alias for -Eutf-8. (See also the -U flag to escape UTF-8)' do $encoding = Encoding::UTF_8 end
  op.on '-L', '--locale', 'Alias for -Elocale, i.e. what LC_ALL/LC_CTYPE/LANG specify.' do $encoding = Encoding.find('locale') end
  op.on '--[no-]encoding-failure-status', 'Invalid bytes cause non-zero exit status. (deafult: when a tty)' do |efe| $encoding_failure_error = efe end

  op.on_tail "\nnote: IF any invalid bytes for the output encoding are read, the exit status is based on `--encoding-failure-err`"

  op.on 'ENVIRONMENT: P_BEGIN_STANDOUT; P_END_STANDOUT; P_BEGIN_ERR; P_END_ERR'

  op.parse! rescue op.abort # <-- only cares about flag order when POSIXLY_CORRECT is set.
end

# Fetch standout constants (regardless of whether we're using them, as they're used as defaults)
BEGIN_STANDOUT = ENV.fetch('P_BEGIN_STANDOUT', "\e[7m")
END_STANDOUT   = ENV.fetch('P_END_STANDOUT',   "\e[27m")
BEGIN_ERR      = ENV.fetch('P_BEGIN_ERR',      "\e[37m\e[41m")
END_ERR        = ENV.fetch('P_END_ERR',        "\e[49m\e[39m")

# Specify defaults
defined? $files                    or $files = !$stdin.tty? && $*.empty?
defined? $visual                   or $visual = $stdout_tty
defined? $encoding_failure_error   or $encoding_failure_error = !$stdout_tty
defined? $escape_spaces            or $escape_spaces = !$files
defined? $escape_tab               or $escape_tab = true
defined? $escape_newline           or $escape_newline = true
defined? $headings                 or $headings = $stdout_tty
defined? $escape_backslash         or $escape_backslash = !$visual
defined? $escape_surronding_spaces or $escape_surronding_spaces = true
defined? $c_escapes                or $c_escapes = $escape_how == :bytes
defined? $trailing_newline         or $trailing_newline = true
defined? $encoding                 or $encoding = ENV.key?('POSIXLY_CORRECT') ? Encoding.find('locale') : Encoding::UTF_8

# If `--encoding-failure-err` was specified, then exit depending on whether an
# encoding failure occurred
$encoding_failure_error and at_exit { exit !$ENCODING_FAILED }

####################################################################################################
#                                                                                                  #
#                                       Visualizing Escapes                                        #
#                                                                                                  #
####################################################################################################

# Converts a string's bytes to their `\xHH` escaped version, and joins them
def hex_bytes(string)
  if $escape_how == :codepoints
    (return '\u{%04X}' % string.codepoints.sum) rescue nil
  end

  string.each_byte.map { |byte| '\x%02X' % byte }.join
end

# Add "visualize" escape sequences to a string; all escaped characters should be passed to this, as
# visual effects are the whole purpose of the `p` program.
# - if `$delete` is specified, then an empty string is returned---escaped characters are deleted.
# - if `$visual` is specified, then `start` and `stop` surround `string`
# - else, `string` is returned.
def visualize(string, start=BEGIN_STANDOUT, stop=END_STANDOUT)
  string = '.' if $escape_how == :dot
  case
  when $escape_how == :delete then ''
  when $visual then "#{start}#{string}#{stop}"
  else              string
  end
end

####################################################################################################
#                                                                                                  #
#                                        Create Escape Hash                                        #
#                                                                                                  #
####################################################################################################

## Construct the `CHARACTERS` hash, whose keys are characters, and values are the corresponding
# sequences to be printed.
CHARACTERS = {}

################################################################################
#                               Set the Defaults                               #
################################################################################

## Escape the lower control characters (i.e. \x00..\x1F and \x7F) with their hex escapes. Note that
# some of these escapes escapes may be overwritten below by user options (like `--c-escapes`).
[*"\0".."\x1F", "\x7F"].each do |char|
  CHARACTERS[char] = visualize hex_bytes(char)
end

## Add in normal ASCII printable characters (i.e. \x20..\x7E).
(' '..'~').each do |char|
  CHARACTERS[char] = char
end

## Escape the high-bit characters (i.e. \x80..\xFF) when we're outputting binary data, because the
# high-bit characters are technically valid (ie `"\x80".force_encoding("binary").valid_encoding?` is
# true), so our logic later on would print them out verbatim.
if $encoding == Encoding::BINARY
  ("\x80".."\xFF").each do |char|
    CHARACTERS[char] = visualize hex_bytes(char)
  end
end

################################################################################
#                                 Apply Flags                                  #
################################################################################

## If the control pictures were requested, then print out visualizations of the control characters
# instead of whatever else.
if $pictures
  (0x00...0x20).each do |byte|
    CHARACTERS[byte.chr] = visualize((0x2400 + byte).chr(Encoding::UTF_8))
  end

  CHARACTERS["\x7F"] = visualize "\u{2421}"
  CHARACTERS[" "] = visualize "\u{2420}"
end

## If C-Style escapes were specified, then change a subset of the control characters to use the
# alternative syntax instead of their hex escapes.
if $c_escapes
  CHARACTERS["\0"] = visualize '\0'
  CHARACTERS["\a"] = visualize '\a'
  CHARACTERS["\b"] = visualize '\b'
  CHARACTERS["\t"] = visualize '\t'
  CHARACTERS["\n"] = visualize '\n'
  CHARACTERS["\v"] = visualize '\v'
  CHARACTERS["\f"] = visualize '\f'
  CHARACTERS["\r"] = visualize '\r'
  CHARACTERS["\e"] = visualize '\e'
end

## Individual character escapes
CHARACTERS["\n"] = "\n" unless $escape_newline
CHARACTERS["\t"] = "\t" unless $escape_tab
CHARACTERS['\\'] = visualize('\\\\') if $escape_backslash
CHARACTERS[' ']  = visualize(' ') if $escape_space

################################################################################
#                             Any Other Characters                             #
################################################################################

## Handle characters without entries in CHARACTERS by adding their value to `CHARACTERS`:
#
# 1. If the character's not valid for $encoding (eg an invalid UTF-8 byte), then `$ENCODING_FAILED`
#    is set (for later use for the exit status of `p`) and an "error" visualization is used (unless
#    `--no-visualize-invalid` was given).
# 2. If the character is valid, but `--escape-unicode` was passed in, then the character is escaped
#    with the `\u{...}` syntax (`...` being the unicode codepoint for the character). This might be
#    separated further in the future to allow for more precise handling over _what_ becomes escaped.
# 3. Otherwise, the character (and all its bytes) are used directly.
#
# Note that the escapes are cached for further re-use. While theoretically over time memory
# consumption may grow, in reality there's not enough unique characters for this to be a problem.
CHARACTERS.default_proc = proc do |hash, char|
  hash[char] =
    if !char.valid_encoding?
      $ENCODING_FAILED = true # for the exit status with `$encoding_failure_error`.
      visualize hex_bytes(char), BEGIN_ERR, END_ERR
    elsif $escape_unicode
      visualize '\u{%04X}' % char.codepoints.sum
    else
      char
    end
end

################################################################################
#                               Other Characters                               #
################################################################################
$unescape_all and CHARACTERS.replace(Hash.new{|x,y| x[y] = y})

$escape_chars.each_char do |char|
  CHARACTERS[char] = visualize hex_bytes char
end

$unescape_chars.each_char do |char|
  CHARACTERS[char] = char
end

################################################################################
#                    Handle Non-ASCII Compatible Characters                    #
################################################################################

## If not using ASCII-compatible encodings (like UTF-16), then encode all the keys to the encoding.
# This is required because hash lookups in ruby are based on "compatible" encodings, and all of the
# values added to CHARACTERS previously are all ASCII-based. (This section is de-optimized, i.e. we
# do it at the end here instead of converting every string in-place, because conversions to/from
# UTF-16 aren't a terribly common use-case; Users have to explicitly supply `--encoding=UTF-16`.)
unless $encoding.ascii_compatible?
  CHARACTERS.merge! CHARACTERS.to_h { [_1.encode($encoding), _2.encode($encoding)] } # Can't use `encode!` because keys of hashes are frozen
end

####################################################################################################
#                                                                                                  #
#                                         Handle Arguments                                         #
#                                                                                                  #
####################################################################################################

CAPACITY = ENV['P_CAP'].to_i.nonzero? || 4096 * 3
OUTPUT = String.new(capacity: CAPACITY * 8, encoding: Encoding::BINARY)

$stdout.binmode
# TODO: optimize this later
def handle(string)
  OUTPUT.clear

  string.force_encoding $encoding
  string.each_char do |char|
    # warn [char.encoding, CHARACTERS[char].encoding, char, char.bytes].inspect
    OUTPUT .concat CHARACTERS[char]
  end

  $stdout.write OUTPUT
end

## Interpret arguments as strings
unless $files
  ARGV.each_with_index do |string, idx|
    # Print out the prefix if a heading was requested
    if $headings
      printf "%5d: ", idx + 1
    end

    # Unfortunately, `ARGV` strings are frozen, and we need to forcibly change the string's encoding
    # within `handle` so can iterate over the contents of the string in the new encoding. As such,
    # we need to duplicate the string here.
    string = +string

    # If we're escaping surrounding spaces, check for them.
    if $escape_surronding_spaces
      # TODO: If we ever end up not needing to modify `string` via `.force_encoding` down below (i.e.
      # if there's a way to iterate over chars without changing encodings/duplicating the string
      # beforehand), this should be changed to use `byteslice`.The method used here is more convenient,
      # but is destructive. ALSO. It doesn't work wtih non-utf8 characters
      string.force_encoding Encoding::BINARY
      leading_spaces  = string.slice!(/\A */) and $stdout.write visualize leading_spaces
      trailing_spaces = string.slice!(/ *\z/)
    end

    # handle the input string
    handle string

    # If any trailing spaces were made, print them out
    trailing_spaces and $stdout.write visualize trailing_spaces

    $trailing_newline or $headings and puts
  end
  # $trailing_newline && !$headings and $stdout.write "\n".encode $encoding
  exit
end

at_exit do
  if $!.is_a?(Errno::ENOENT)
    $op.warn $!.to_s.sub(/ @ rb\w+/, '')
    # exit! 2
  end
end

ARGF.set_encoding $encoding
ARGF.each_char do |char|
  #  if ARGF.file.tell == 1
  #    $trailing_newline || $headings and $not_first ? print("\n") : $not_first = true
  #    $headings and print ARGF.filename, ":"
  #  end
  $stdout.write CHARACTERS[char]
end
# TODO: check `char` after to see if we need to print a newline
$trailing_newline and $stdout.write "\n".encode $encoding


__END__
def ARGF.filename
  super || exit
rescue
  warn $!.to_s
  retry
end

# Print the prefix line out before we do binmode on ARGF
if $headings and not $*.empty?
  print "#{ARGF.filename}:" # TODO: clean this up
end

## Interpret arguments as files
# TODO: This can be made a bit faster using `syswrite`, but at the cost of
# making this so much uglier
ARGF.binmode
INPUT = String.new(capacity: CAPACITY, encoding: $encoding)

# Note that `ARGF.each_char` would do what we want, except it's (a) a bit slower than using
# `readpartial` and (b) wouldn't allow us to easily know when files changed (for filename outputs).
def not_done_reading_all_files?
  # INPUT.replace (ARGF.gets || (return false))
  ARGF.readpartial(CAPACITY, INPUT)
rescue EOFError
  false
rescue
  abort $!.to_s
end

while not_done_reading_all_files?
  # $stdout.write INPUT
  # next

  if INPUT.empty?
    $tmp and (handle $tmp; $tmp = nil)

    # TODO: clean this up
    print "\n".encode $encoding if $headings || $trailing_newline
    print "#{ARGF.filename}:".encode $encoding if $headings
    $stdout.flush
    next
  end

  # if false # TODO: clean this up to make sure that it works for all encodings
  if true
     if $tmp
      warn ["before", INPUT.bytes, $tmp.bytes].inspect
      INPUT.prepend $tmp
      $tmp = nil
      warn ["after", INPUT.bytes].inspect
    end

    if INPUT.bytesize >= 1 and !(q=INPUT.byteslice(-1..)).valid_encoding?
      if INPUT.bytesize >= 2 and !(q=INPUT.byteslice(-2..)).valid_encoding?
        if INPUT.bytesize >= 3 and !(q=INPUT.byteslice(-3..)).valid_encoding?
          # Need to support versions without `.bytesplice`
          $tmp = q; INPUT.force_encoding('binary').slice!(-3..)
          warn 1
        else
          $tmp = q; INPUT.force_encoding('binary').slice!(-2..)
          warn 2
        end
      else
        $tmp = q; INPUT.force_encoding('binary').slice!(-1..)
          warn 3
      end
    end
  end

  # warn ["sliced", INPUT.bytes, $tmp&.bytes].inspect

  handle INPUT
end
$tmp and handle $tmp

$trailing_newline and $stdout.write "\n".encode $encoding

