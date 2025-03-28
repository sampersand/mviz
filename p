#!/usr/bin/env -S ruby -Ebinary --disable=all
# -*- encoding: binary; frozen-string-literal: true -*-
defined?(RubyVM::YJIT.enable) and RubyVM::YJIT.enable

require 'optparse'

## Default escape sequences
Encoding.default_internal = Encoding::UTF_8

####################################################################################################
#                                                                                                  #
#                                         Parse Arguments                                          #
#                                                                                                  #
####################################################################################################

OptParse.new do |op|
  op.version = '1.1'
  op.banner = <<~BANNER
    usage: #{op.program_name} [options] [string ...]
           #{op.program_name} -f/--files [options] [file ...]
    When no arguments, and stdin isn't a tty, the second form is assumed.
  BANNER
  op.require_exact = true if defined? op.require_exact = true

  op.separator "\nGeneric Options"
  op.on '-h', '--help', 'Print this and then exit' do op.help_exit end
  op.on       '--version', 'Print the version' do puts op.ver; exit end
  op.on '-f', '--files', 'Interpret arguments as filenames to read, not strings' do $files = true end

  # This has to be cleaned up a bit.
  op.separator "\nHow to Output (todo: clean this section up)"
  op.on '-H', '--[no-]number-lines', '--[no-]heading', 'Number args without -f; add headings with -f. (default: true if output is a tty)' do |x| $number_lines = x end
  op.on       '--trailing-newline', 'Print a final trailing newline; only useful with -f. (default)' do $no_newline = false end
  op.on '-n', '--no-trailing-newline', 'Suppress final trailing newline.' do $no_newline = true end
  # op.on '-N', '--[no-]number-lines', 'Number arguments; defaults to on when output is a TTY' do |nl| $number_lines = nl end

  op.separator "\nWhat to Escape"
  op.on       '--escape-newline', 'Escape newlines. (default)' do |x| $escape_newline = x end
  op.on '-l', '--no-escape-newline', 'Shorthand for --no-escape-newline. ("Line-oriented mode")' do $escape_newline = false end
  op.on       '--escape-tab', 'Escape tabs. (default)' do |x| $escape_tab = x end
  op.on '-t', '--no-escape-tab', 'Shorthand for --no-escape-tabs.' do $escape_tab = false end
  op.on '-s', '--[no-]escape-space', 'Escape spaces; Only useful in visual mode.' do |es| $escape_space = es end
  op.on '--[no-]escape-outer-space', 'Visualize leading and trailing whitespace. (default); not useful with -f' do |ess| $escape_surronding_spaces = ess end
  op.on '-B', '--[no-]escape-backslash', 'Escape backslashes (default: when in visual)' do |eb| $escape_backslash = eb end
  op.on '-U', '--[no-]escape-unicode', 'Escape non-ASCII Unicode characters with "\u{...}"' do |eu| $escape_unicode = eu end

  # op.on '-P', '--[no-]escape-print', 'Escape all non-print characters (including unicode ones) TODO' do |ep| $escape_print = ep end
  # op.on '-a', '--escape-all', 'Escapes all characters' do $escape_space = $escape_backslash = $escape_tab = $escape_newline = $escape_unicode = true end
  # op.on '-w', '--no-escape-whitespace', 'Do not escape whitespace' do $escape_space = $escape_tab = $escape_newline = $escape_surronding_spaces = false end

  op.separator "\nHow to Escape"
  op.on '-d', '--delete', 'Delete escaped characters instead of printing' do $delete = true end
  op.on '-v', '--visualize', 'Enable visual effects. (default: when output\'s a tty)' do $visual = true end
  op.on '-V', '--no-visualize', "Don't enable visual effects" do $visual = false end
  op.on       '--c-escapes', 'Use C-style escapes (\n, \t, etc, and \xHH). (default)' do $c_escapes = true end
  op.on '-x', '--no-c-escapes', 'Alias for --no-c-escapes; only use \xHH for escapes.' do $c_escapes = false end
  op.on '-P', '--control-pictures', 'Use "control pictures" (U+240x..U+242x) for some escapes' do
    $c_escapes = false unless defined? $c_escapes
    $pictures = true
  end

  # Implementation note: Even though these usage messages reference "input encodings," the input is
  # actually always read as binary data, and then attempted to be converted to whatever these
  # encodings are
  op.separator "\nInput Encodings"
  op.on '-E', '--encoding=ENCODING', "Specify the input data's encoding; use 'list' for a list." do |enc|
    if enc == 'list'
      puts "available encodings: #{(Encoding.name_list - %w[external internal]).join(', ')}"
      exit
    end
    $encoding = Encoding.find enc rescue op.abort
  end

  op.on '-b', '--binary', '--bytes', 'Alias for -Ebinary; High-bit bytes are escaped.' do $encoding = Encoding::BINARY end
  op.on '-a', '--ascii', 'Alias for -Eascii. Like -b, but high-bit bytes are invalid.' do $encoding = Encoding::ASCII end
  op.on '-u', '-8', '--utf-8', 'Alias for -Eutf-8. (See also the -U flag to escape UTF-8)' do $encoding = Encoding::UTF_8 end
  op.on '-L', '--locale', 'Alias for -Elocale, i.e. what LC_ALL/LC_CTYPE/LANG specify.' do $encoding = Encoding.find('locale') end
  op.on '--[no-]encoding-failure-status', 'Invalid bytes cause non-zero exit status. (deafult: when a tty)' do |efe| $encoding_failure_error = efe end

  op.on_tail "\nnote: IF any invalid bytes for the output encoding are read, the exit status is based on `--encoding-failure-err`"

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
defined? $escape_surronding_spaces or $escape_surronding_spaces = true
defined? $encoding                 or $encoding = Encoding.find('locale')
defined? $c_escapes                or $c_escapes = true

# If `--encoding-failure-err` was specified, then exit depending on whether an
# encoding failure occurred
$encoding_failure_error and at_exit { exit !$ENCODING_FAILED }

####################################################################################################
#                                                                                                  #
#                                       Visualizing Escapes                                        #
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
  case
  when $delete then ''
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
  CHARACTERS[char] = visualize_hex(char)
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
    CHARACTERS[char] = visualize_hex(char)
  end
end

################################################################################
#                                 Apply Flags                                  #
################################################################################

## If the control pictures were requested, then print out visualizations of the control characters
# instead of whatever else.
if $pictures
  (0x00...0x20).each do |char|
    CHARACTERS[char.chr] = visualize (0x2400 + char).chr(Encoding::UTF_8)
  end

  CHARACTERS["\x7F"] = visualize "\u{2421}"
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
      visualize_hex(char, start: BEGIN_ERR, stop: END_ERR)
    elsif $escape_unicode
      visualize '\u{%04X}' % char.codepoints.sum
    else
      char
    end
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
  CHARACTERS.transform_keys!(&:encode) # Can't use `encode!` because keys of hashes are frozen
end

####################################################################################################
#                                                                                                  #
#                                         Handle Arguments                                         #
#                                                                                                  #
####################################################################################################

CAPACITY = 4096
OUTPUT = String.new(capacity: CAPACITY * 8, encoding: Encoding::BINARY)

# TODO: optimize this later
def handle(string)
  OUTPUT.clear

  string.force_encoding($encoding).each_char do |char|
    OUTPUT << CHARACTERS[char]
  end

  $stdout.write OUTPUT
end

def handle_argv_string(string)
  # Unfortunately, `ARGV` strings are frozen, and we need to forcibly change the string's encoding
  # within `handle` so can iterate over the contents of the string in the new encoding. As such,
  # we need to duplicate the string here.
  string = +string

  # If we're escaping surrounding spaces, check for them.
  if $escape_surronding_spaces
    # TODO: If we ever end up not needing to modify `string` via `.force_encoding` down below (i.e.
    # if there's a way to iterate over chars without changing encodings/duplicating the string
    # beforehand), this should be changed to use `byteslice`.The method used here is more convenient,
    # but is destructive.
    string.force_encoding Encoding::BINARY
    leading_spaces  = string.slice!(/\A */) and $stdout.write visualize leading_spaces
    trailing_spaces = string.slice!(/ *\z/)
  end

  handle string

  trailing_spaces and $stdout.write trailing_spaces
end


## Interpret arguments as strings
unless $files
  $*.each_with_index do |arg, idx|
    $number_lines and printf "%5d: ", idx + 1
    handle_argv_string arg
    $number_lines and puts
  end
  exit
end

# Print the prefix line out before we do binmode on ARGF
$number_lines and not $*.empty? and print "#{ARGF.filename}:" # TODO: clean this up

## Interpret arguments as files
# TODO: This can be made a bit faster using `syswrite`, but at the cost of
# making this so much uglier
ARGF.binmode
INPUT = String.new(capacity: CAPACITY, encoding: $encoding)

# Note that `ARGF.each_char` would do what we want, except it's (a) a bit slower than using
# `readpartial` and (b) wouldn't allow us to easily know when files changed (for filename outputs).
def not_done_reading_all_files?
  ARGF.readpartial(CAPACITY, INPUT)
rescue EOFError
  false
rescue
  abort $!.to_s
end

while not_done_reading_all_files?
  if INPUT.empty?
    $tmp and (handle $tmp; $tmp = nil)
    $number_lines and print "\n#{ARGF.filename}:" # TODO: clean this up
    next
  end

  if false # TODO: clean this up to make sure that it works for all encodings
  (INPUT.prepend $tmp; $tmp = nil) if $tmp
  if INPUT.bytesize >= 1 and !(q=INPUT.byteslice(-1..)).valid_encoding?
    if INPUT.bytesize >= 2 and !(q=INPUT.byteslice(-2..)).valid_encoding?
      if INPUT.bytesize >= 3 and !(q=INPUT.byteslice(-3..)).valid_encoding?
        # Need to support versions without `.bytesplice`
        $tmp = q; INPUT.force_encoding('binary').slice!(-3..)
      else
        $tmp = q; INPUT.force_encoding('binary').slice!(-2..)
      end
    else
      $tmp = q; INPUT.force_encoding('binary').slice!(-1..)
    end
  end
  end

  handle INPUT
end
$tmp and handle $tmp

$no_newline or $stdout.write "\n"

