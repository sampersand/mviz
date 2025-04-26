#!/usr/bin/env -S ruby -Ebinary
# -*- encoding: UTF-8; frozen-string-literal: true -*-
# ^ Force all strings in this file to be utf-8, regardless of what the environment says
# NOTE: we needthe `-Ebinary` up top to force `$*` arguments to be binary. otherwise, optparse's
# regexes will die. We could fix it by `$*.replace $*.map { (+_1).force_encoding 'binary' }` but ew.
require 'optparse'

# Enable YJIT, but if there's any problems just ignore them
begin
  RubyVM::YJIT.enable
rescue Exception
  # Ignore
end

## Define custom `abort` and `warn`s to use the program name when writing messages.
PROGRAM_NAME = File.basename($0, '.*')
def abort(msg = $!) super "#{PROGRAM_NAME}: #{msg}" end
def warn(msg = $!)  super "#{PROGRAM_NAME}: #{msg}" end

module Patterns
  module_function

  def add_charset(charset, block, default: :default)
    return if charset == '' || charset == '^' # Ignore empty charsets
    @patterns.prepend [charset || default, block]
  end

  C_ESCAPES_MAP = {
    "\0" => '\0', "\a" => '\a', "\b" => '\b', "\t" => '\t',
    "\n" => '\n', "\v" => '\v', "\f" => '\f', "\r" => '\r',
    "\e" => '\e', "\\" => '\\\\',
  }
  C_ESCAPES_DEFAULT = /[#{C_ESCAPES_MAP.keys.map{_1.inspect[1..-2]}.join}]/

  PRINT = ->char { char }
  DELETE = ->_char{ $SOMETHING_ESCAPED = true; '' }
  DOT = ->_char { visualize '.' }
  HEX = ->char { visualize hex_bytes char }
  CODEPOINTS = ->char { visualize '\u{%04X}' % char.ord }
  C_ESCAPES = ->char { visualize C_ESCAPES_MAP.fetch(char) }
  HIGHLIGHT = ->char { visualize char }
  PICTURES = ->char{
    case char
    when "\0".."\x1F" then visualize (0x2400 + char.ord).chr(Encoding::UTF_8)
    when "\x7F" then visualize "\u{2421}"
    when ' '    then visualize "\u{2423}"
    else fail "ops"
    end
  }

  DEFAULT = ->char{
    if char == '\\'
      $visual ? '\\' : '\\\\'
    elsif ce = C_ESCAPES_MAP[char]
      visualize ce
    elsif (char == "\x7F" || char <= "\x1F") or ($encoding == Encoding::BINARY && char >= "\x7F")
      visualize hex_bytes char
    else
      char
    end
  }

  @patterns = []
  @default_charset = nil #'[\0-\x1F\x7F]'
  @default_action  = DEFAULT

  class << self
    attr_writer :default_charset
    attr_accessor :default_pictures
  end

  def default_charset
    @default_charset ||= if $encoding == Encoding::BINARY
      Regexp.new((+"[\0-\x1F\x7F-\xFF]").force_encoding(Encoding::BINARY))
    else
      /[\0-\x1F\x7F]/
    end
  end

  def default_action(what)
    @default_action = what
  end


  LAMBDA_FOR_MULTIBYTE = ->char{char.bytesize > 1}
  LAMBDA_FOR_SINGLEBYTE = ->char{char.bytesize == 1}

  def build!
    @built = @patterns.map do |selector, block|
      selector = case selector
                 when '\A' then /./m
                 when '\@' then default_charset
                 when '\m' then LAMBDA_FOR_MULTIBYTE
                 when '\M' then LAMBDA_FOR_SINGLEBYTE
                 when ''   then next # If it's empty, don't register it
                 when String then Regexp.new("[#{selector}]".force_encoding($encoding))
                 when :default then default_charset
                 when Regexp, Proc then selector
                 else raise "fail: bad charset '#{selector.inspect}'"
                 end
      [selector, block]
    end.compact
  end

  def handle(char)
    @built.each do |condition, escape_method|
      return escape_method.call(char) if condition === char
    end

    return char unless default_charset === char

    if default_pictures && ( ("\0".."\x20") === char || "\x7F" === char )
      PICTURES.call(char)
    else
      @default_action.call(char)
    end
  end
end


####################################################################################################
#                                                                                                  #
#                                         Parse Arguments                                          #
#                                                                                                  #
####################################################################################################

# Fetch standout constants (regardless of whether we're using them, as they're used as defaults)
VISUAL_BEGIN     = ENV.fetch('P_VISUAL_BEGIN', "\e[7m")
VISUAL_END       = ENV.fetch('P_VISUAL_END',   "\e[27m")
VISUAL_ERR_BEGIN = ENV.fetch('P_VISUAL_ERR_BEGIN', "\e[37m\e[41m")
VISUAL_ERR_END   = ENV.fetch('P_VISUAL_ERR_END',   "\e[49m\e[39m")
BOLD_BEGIN       = (ENV.fetch('P_BOLD_BEGIN', "\e[1m") if $__SHOULD_USE_COLOR = $stdout.tty? || ENV['P_COLOR'])
BOLD_END         = (ENV.fetch('P_BOLD_END',   "\e[0m") if $__SHOULD_USE_COLOR)

OptParse.new do |op|
  op.program_name = PROGRAM_NAME
  op.version = '0.9.0'
  op.banner = <<~BANNER
  #{VISUAL_BEGIN if $__SHOULD_USE_COLOR}usage#{VISUAL_END if $__SHOULD_USE_COLOR}: #{BOLD_BEGIN}#{op.program_name} [options]#{BOLD_END}                # Read from stdin
         #{BOLD_BEGIN}#{op.program_name} [options] [string ...]#{BOLD_END}   # Print strings
         #{BOLD_BEGIN}#{op.program_name} -f [options] [file ...]#{BOLD_END}  # Read from files
  When no args are given, first form is assumed if stdin is not a tty.
  BANNER

  op.on_head 'A program to escape "weird" characters'

  # Define a custom `separator` function to add bold to each section
  def op.separator(title, additional = nil)
    super "\n#{BOLD_BEGIN}#{title}#{BOLD_END}#{additional && ' '}#{additional}"
  end

  op.accept :charset do |selector|
    case selector
    when '\A'    then /./m
    when '\m'    then Patterns::LAMBDA_FOR_MULTIBYTE
    when '\M'    then Patterns::LAMBDA_FOR_SINGLEBYTE
    when '\@'    then :default
    when '', '^' then :empty
    when String  then selector
    else
      fail "bad selector?: #{selector}"
    end
  end

  ##################################################################################################
  #                                        Generic Options                                         #
  ##################################################################################################
  op.separator 'GENERIC OPTIONS'

  op.on '-h', 'Print a shorter help message and exit' do
    puts <<~EOS
    #{BOLD_BEGIN}usage: #{op.program_name} [options] [string ...]#{BOLD_END}
      --help          Print a longer help message with more options
      -f              Interpret all arguments as filenames, not strings
      -c              Exit nonzero if any escapes are printed. ("check")
      -q              Don't output anything. (Useful with -c)
      -1              Don't print a "prefix" to arguments, but do print newlines
      -n              Don't print either "prefixes" nor newlines for arguments
      -v, -V          Enable/disable visual effects for escaped characters
    #{BOLD_BEGIN}ESCAPE FORMATTING#{BOLD_END} (-x, -d, -p, -. are mutually exclusive)
      -x              Print escaped chars in hex-notation (\\xHH)
      -d              Delete escaped chars from the output
      -p              Print escaped chars unchanged
      -.              Replace escaped chars with periods
      -P              Escape some chars with their "pictures".
    #{BOLD_BEGIN}SHORTHANDS FOR COMMON ESCAPES#{BOLD_END}
      -l              Don't escape newlines.
      -w              Don't escape newlines, tabs, or spaces
      -s              Escape spaces
      -B              Escape backslashes
      -m, -u          Escape multibyte characters with their Unicode codepoint.
    #{BOLD_BEGIN}INPUT DATA#{BOLD_END}
      -b              Interpret input data as binary text
      -A              Interpret input data as ASCII; like -b, except invalid bytes
      -8              Interpret input data as UTF-8 (default unless POSIXLY_CORRECT set)
    EOS
    exit
  end

  op.on '--help', 'Print a longer usage message and exit' do
    puts op.help # Newer versions of OptParse have `op.help_exit`, but we are targeting older ones.
    exit
  end

  op.on '--version', 'Print the version and exit' do
    puts op.ver
    exit
  end

  op.on '--debug', 'Enable internal debugging code' do
    $DEBUG = $VERBOSE = true
  end

  op.on '-f', '--files', 'Interpret trailing options as filenames to read' do |f|
    $files = f
  end

  $malformed_error = true
  op.on'--[no-]malformed-error', 'Invalid chars in the --encoding a cause nonzero exit. (default)' do |me|
    $malformed_error = me
  end

  $escape_error = false
  op.on '-c', '--[no-]check-escapes', 'Return nonzero if _any_ character is escaped' do |ee|
    $escape_error = ee
  end

  $quiet = false
  op.on '-q', '--[no-]quiet', 'Do not output anything. (Useful with -c or --malformed-error)' do |q|
    $quiet = q
  end

  op.on '-v', '--visual', 'Enable visual effects. (default only if stdout is tty)' do
    $visual = true
  end

  op.on '-V', '--no-visual', 'Do not enable visual effects' do
    $visual = false
  end

  ##################################################################################################
  #                                       Separating Outputs                                       #
  ##################################################################################################
  op.separator 'OUTPUT FORMAT', "(They're all mutually exclusive; last one wins.)"

  op.on '--prefixes', "Add \"prefixes\". (default if stdout's a tty, and args are given)" do
    $prefixes = true
  end

  op.on '-1', '--one-per-line', "Print each arg on its own line. (default when --prefixes isn't)" do
    $prefixes = false
  end

  # No need to have an option to set `$trailing_newline` on its own to false, as it's useless
  # when `$prefixes` is truthy.
  op.on '-n', '--no-prefixes-or-newline', 'Disables both prefixes and trailing newlines' do
    $prefixes = $trailing_newline = false
  end

  ##################################################################################################
  #                                            Escaping                                            #
  ##################################################################################################

  op.separator 'ESCAPING THE DEFAULT CHARSET'

  op.on '--default-charset=CHARSET', :charset, 'Set the "default" charset. Characters that do not match this',
                                               'charset are printed verbatim.' do |cs|
    cs = '' if cs == :empty # an empty charset is allowed for `default-charset`
    Patterns.default_charset = cs ? /[#{cs}]/ : ''
  end

  op.on '--default-format=WHAT', 'Specify the default escaping behaviour. WHAT must be one of:',
                                 'print, delete, dot, hex, codepoints, highlight, or default.' do |what|
    Patterns.default_action(
      case what
      when 'print' then Patterns::PRINT
      when 'delete' then Patterns::DELETE
      when 'hex' then Patterns::HEX
      when 'default' then Patterns::DEFAULT
      when 'codepoints' then Patterns::CODEPOINTS
      when 'highlight' then Patterns::HIGHLIGHT
      else abort "invalid --default-format option: #{what}"
      end
    )
  end

  op.on '-p', "Alias for '--default-format=print'; Print escaped chars verbatim"  do
    Patterns.default_action(Patterns::PRINT)
  end

  op.on '-d', "Alias for '--default-format=delete'; Delete escaped chars"  do
    Patterns.default_action(Patterns::DELETE)
  end

  op.on '-.', "Alias for '--default-format=dot'; Replace escaped chars with '.'"  do
    Patterns.default_action(Patterns::DOT)
  end

  op.on '-x', "Alias for '--default-format=hex'; Output hex value (\\xHH) for escaped chars"  do
    Patterns.default_action(Patterns::HEX)
  end

  op.on '-P', '--[no-]default-pictures', 'Print out "pictures" if possible; non-pictures will use whatever other default is set' do |cs|
    Patterns.default_pictures = cs
  end

  puts op.help; exit

  ########
  ########
  ########

  op.separator 'SPECIFIC ESCAPES', '(If something matches multiple, the last one wins.)'

  op.on '--print CHARSET', :charset, 'Print characters, unchanged, which match CHARSET' do |cs|
    Patterns.add_charset(cs, Patterns::PRINT)
  end

  op.on '--delete CHARSET', :charset, 'Delete characters which match CHARSET from the output.' do |cs|
    Patterns.add_charset(cs, Patterns::DELETE)
  end

  op.on '--dot CHARSET', :charset, "Replaces CHARSET with a period ('.')" do |cs|
    Patterns.add_charset(cs, Patterns::DOT)
  end

  op.on '--hex CHARSET', :charset, 'Replaces characters with their hex value (\xHH)' do |cs|
    Patterns.add_charset(cs, Patterns::HEX)
  end

  op.on '--codepoints CHARSET', :charset, 'Replaces chars with their UTF-8 codepoints (ie \u{...}). See -m' do |cs|
    Patterns.add_charset(cs, Patterns::CODEPOINTS)
  end

  op.on '--highlight CHARSET', :charset, 'Prints the char unchanged, but visual effects are added to it.' do |cs|
    Patterns.add_charset(cs, Patterns::HIGHLIGHT)
  end

  # (Note: You'"can \"undo\" all previous patterns via --default='\\A')
  op.on '--defaultcharset CHARSET', :charset, 'Use the default patterns for chars in CHARSET' do |cs|
    Patterns.add_charset(cs, Patterns::DEFAULT)
  end

  op.on '--pictures CHARSET', :charset, 'Use "pictures" (U+240x-U+242x). CHARSET defaults to \0-\x20\x7F',
                                      'Attempts to generate pictures for other chars is an error.' do |cs|
    Patterns.add_charset(cs, Patterns::PICTURES, default: /[\0-\x20\x7F]/)
  end

  op.on '--c-escapes CHARSET', 'Replaces chars with their C escapes; Attempts to generate',
                               "c-escapes for non-'#{Patterns::C_ESCAPES_DEFAULT.source[1..-2]
                                                      .sub('u0000', '0')}' is an error", 'Does not use default charset' do |cs|
    Patterns.add_charset(cs, Patterns::C_ESCAPES, default: Patterns::C_ESCAPES_DEFAULT)
  end

  $escape_surronding_spaces = true
  op.on '--[no-]escape-surrounding-space', "Escape leading/trailing spaces. Doesn't work with -f (default)" do |ess|
    $escape_surronding_spaces = ess
  end

  op.on <<~'EOS'
    A 'CHARSET' is a regex character without the surrounding brackets (for example, --delete='^a-z' will
    only output lower-case letters.) In addition to normal escapes like '\n' for newlines, '\w' for
    "word" characters, etc, some other special sequences are accepted:
      * '\A' matches all chars (--print='\A' would print out every character)
      * '\m' matches multibyte characters (only useful if input data is utf-8, the default.)
      * '\M' matches all single-byte characters
      * '\@' matches the default charset. (i.e. --print is equiv to --print='\@')
    If more than pattern matches, the last-most one wins.
  EOS

  ## =====
  ## =====
  ## ===== 

  op.separator 'SHORTHANDS'
  op.on '-l', '--print-newlines', "Same as --print='\\n'" do
    Patterns.add_charset(/\n/, Patterns::PRINT)
  end

  op.on '-w', '--print-whitespace', "Same as --print='\\n\\t '" do
    Patterns.add_charset(/[\n\t ]/, Patterns::PRINT)
  end

  op.on '-s', '--highlight-space', "Same as --highlight=' '" do
    Patterns.add_charset(/ /, Patterns::HIGHLIGHT)
  end

  op.on '-B', '-\\', '--escape-backslashes', "Same as --c-escapes='\\\\' (default if not visual mode)" do |eb|
    Patterns.add_charset(/\\/, Patterns::C_ESCAPES)
  end

  op.on '-m', '-u', '--multibyte-codepoints', "Same as --codepoints='\\m'" do
    Patterns.add_charset(Patterns::LAMBDA_FOR_MULTIBYTE, Patterns::CODEPOINTS)
  end

  ##################################################################################################
  #                                        Input Encodings                                         #
  ##################################################################################################
  op.separator 'ENCODINGS', '(default based on POSIXLY_CORRECT; --utf-8 if unset, --locale if set)'

  op.on '--encoding=ENCODING', "Specify the input's encoding. Case-insensitive. Encodings that",
                               "aren't ASCII-compatible encodings (eg UTF-16) aren't accepted." do |enc|
    $encoding = Encoding.find enc rescue abort
    $encoding.ascii_compatible? or abort "Encoding #$encoding is not ASCII-compatible!"
  end

  op.on '--list-encodings', 'List all possible encodings, and exit.' do
    # Don't list external or internal encodings, as they're not really options
    possible_encodings = (Encoding.name_list - %w[external internal])
      .select { |name| Encoding.find(name).ascii_compatible? }
      .join(', ')

    puts "available encodings: #{possible_encodings}"
    exit
  end

  op.on '-b', '--binary', '--bytes', 'Same as --encoding=binary. (Escapes high-bit bytes)' do
    $encoding = Encoding::BINARY
  end

  op.on '-A', '--ascii', 'Same as --encoding=ASCII. Like -b, but high-bits are "invalid".' do
    $encoding = Encoding::ASCII
  end

  op.on '-8', '--utf-8', 'Same as --encoding=UTF-8. (default unless POSIXLY_CORRECT set)' do
    $encoding = Encoding::UTF_8
  end

  op.on '--locale', 'Same as --encoding=locale. (Chooses encoding based on env vars)' do
    $encoding = Encoding.find('locale')
  end

  ##################################################################################################
  #                                        Environment Vars                                        #
  ##################################################################################################
  op.separator 'ENVIRONMENT VARIABLES'
  op.on <<-EOS # Note: `-EOS` not `~EOS` to keep leading spaces
    P_VISUAL_BEGIN        Beginning escape sequence for --visual
    P_VISUAL_END          Ending escape sequence for --visual
    P_VISUAL_ERR_BEGIN    Beginning escape sequence for invalid bytes with --visual
    P_VISUAL_ERR_END      Ending escape sequence for invalid bytes with --visual
    POSIXLY_CORRECT       If present, changes default encoding to the locale's (cf locale(1).), and
                          also disables parsing switches after arguments (e.g. `p foo -x` will print
                          out `foo` and `-x`, and won't interpret `-x` as a switch.)
    LC_ALL/LC_CTYPE/LANG  Checked (in that order) for encoding when --locale is used.
  EOS

  ##################################################################################################
  #                                         Parse Options                                          #
  ##################################################################################################

  # Parse the options; Note that `op.parse!` handles `POSIXLY_CORRECT` internally to determine if
  # flags should be allowed to come after arguments.
  begin
    op.parse!
  rescue OptionParser::ParseError => err # Only gracefully exit with optparse errors.
    abort err
  end
end

####################################################################################################
#                                                                                                  #
#                                      Defaults for Arguments                                      #
#                                                                                                  #
####################################################################################################

# Specify defaults
defined? $visual           or $visual = $stdout.tty?
defined? $prefixes         or $prefixes = $stdout.tty? && (!$*.empty? || (defined?($files) && $files))
defined? $files            or $files = !$stdin.tty? && $*.empty?
defined? $trailing_newline or $trailing_newline = true
defined? $encoding         or $encoding = ENV.key?('POSIXLY_CORRECT') ? Encoding.find('locale') : Encoding::UTF_8
# ^ Escape things above `\x80` by replacing them with their codepoints if in utf-8 mode, and "make everything hex" wasn't requested
$quiet and $stdout = File.open(File::NULL, 'w')

PATTERNS = Patterns.build!

## Force `$trailing_newline` to be set if `$prefixes` are set, as otherwise there wouldn't be a
# newline between each header, which is weird.
$trailing_newline ||= $prefixes

at_exit do
  next if $! # If there's an exception, then just yield that

  if $malformed_error && ($ENCODING_FAILED ||= false)
    exit 1
  elsif $escape_error && ($SOMETHING_ESCAPED ||= false)
    exit 1
  end
end

####################################################################################################
#                                                                                                  #
#                                       Visualizing Escapes                                        #
#                                                                                                  #
####################################################################################################

# Converts a string's bytes to their `\xHH` escaped version, and joins them
def hex_bytes(string) string.each_byte.map { |byte| '\x%02X' % byte }.join end

# Add "visualize" escape sequences to a string; all escaped characters should be passed to this, as
# visual effects are the whole purpose of the `p` program.
# - if `$delete` is specified, then an empty string is returned---escaped characters are deleted.
# - if `$visual` is specified, then `start` and `stop` surround `string`
# - else, `string` is returned.
def visualize(string, start=VISUAL_BEGIN, stop=VISUAL_END)
  $SOMETHING_ESCAPED = true

  if $visual
    "#{start}#{string}#{stop}"
  else
    string
  end
end

####################################################################################################
#                                                                                                  #
#                                        Create Escape Hash                                        #
#                                                                                                  #
####################################################################################################


## Construct the `CHARACTERS` hash, whose keys are characters, and values are the corresponding
# sequences to be printed.
CHARACTERS = Hash.new do |hash, key|
  hash[key] =
    if !key.valid_encoding?
      $ENCODING_FAILED = true # for the exit status with `$malformed_error`.
      visualize(hex_bytes(key), VISUAL_ERR_BEGIN, VISUAL_ERR_END)
    else
      Patterns.handle(key)
    end
end

####################################################################################################
#                                                                                                  #
#                                         Handle Arguments                                         #
#                                                                                                  #
####################################################################################################

# CAPACITY = ENV['P_CAP'].to_i.nonzero? || 4096 * 3
# OUTPUT = String.new(capacity: CAPACITY * 8, encoding: Encoding::BINARY)

## Put both stdin and stdout in bin(ary)mode: Disable newline conversion (which is used by Windows),
# no encoding conversion done, and defaults the encoding to Encoding::BINARY (ie ascii-8bit). We
# need this to ensure that we're handling exactly what we're given, and ruby's not trying to be
# smart. Note that we set the encoding of `$stdin` (which doesn't undo the other binmode things),
# as we might be iterating over `$encoding`'s characters from `$stdin` (if `-` was given).
$stdout.binmode
$stdin.binmode.set_encoding $encoding

# TODO: optimize this later
def print_escapes(has_each_char, suffix = nil)
  ## Print out each character in the file, or their escapes. We capture the last printed character,
  # so that we can match it in the following block. (We don't want to print newlines if the last
  # character in a file was a newline.)
  last = nil
  has_each_char.each_char do |char|
    print last = CHARACTERS[char]
  end

  ## If a suffix is given (eg trailing spaces with `--escape-surrounding-space)`, then print it out
  # before printing a (possible) trailing newline.
  print suffix if suffix

  ## Print a newline if the following are satisfied:
  # 1. It was requested. (This is the default, but can be suppressed by `--no-trailing-newline`, or
  #    `-n`. Note that if prefixes are enabled, trailing newlines are always enabled regardless.)
  # 2. At least one character was printed, or prefixes were enabled; If no characters are printed,
  #    we normally don't want to add a newline, when prefixes are being output we want each filename
  #    to be on their own lines.
  # 3. The last character to be printed was not a newline; This is normally the case, but if the
  #    newline was unescaped (eg `-l`), then the last character may be a newline. This condition is
  #    to prevent a blank line in the output. (Kinda like how `puts "a\n"` only prints one newline.)
  puts if $trailing_newline && last != "\n" && (last != nil || $prefixes)
end

## Interpret arguments as strings
unless $files
  ARGV.each_with_index do |string, idx|
    # Print out the prefix if a header was requested
    printf '%5d: ', idx + 1 if $prefixes

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
      leading_spaces  = string.slice!(/\A +/) and print visualize(CHARACTERS[' '] * $&.length)
      trailing_spaces = string.slice!(/ +\z/) && visualize(CHARACTERS[' '] * $&.length)
    end

    # handle the input string
    print_escapes string.force_encoding($encoding), trailing_spaces
  end

  # Exit early so we don't deal with the chunk below. note however, the `at_exit` above for the
  # `--malformed-error` flag.
  return
end

# Sadly, we can't use `ARGF` for numerous reasons:
# 1. `ARGF#each_char` will completely skip empty files, and won't call its block. So there's no easy
#    way for us to print prefixes for empty files. (We _could_ keep our own `ARGV` list, but that
#    would be incredibly hacky.) And, we have to check file names _each time_ we get a new char.
# 2. `ARGF#readpartial` gives empty strings when a new file is read, which lets us more easily print
#    out prefixes. However, it doesn't give an empty string for the first line (which is solvable,
#    but annoying). However, the main problem is that you might read the first half of a multibyte
#    sequence, which then wouldn't be escaped. Since we support utf-8, utf-16, and utf-32, it's not
#    terribly easy (from my experiments with) to make a generalized way to detect half-finished seq-
#    uence.
# 3. `ARGF` in general prints out very ugly error messages for missing/unopenable files, and it's a
#    pain to easily capture them, especially since we want to dump all files, even if there's a
#    problem with one of them.
# 4. `ARGF#filename` is not a usable way to see if new files are given: Using `old == ARGF.filename`
#    in a loop doesn't work in the case of two identical files being dumped (eg `p ab.txt ab.txt`).
#    But, `old.equal? ARGF.filename` also doesn't work because a brand new `"-"` is returned for
#    each `.filename` call when `ARGV` started out empty (i.e. `p` with no arguments).
#
# Unfortunately, manually iterating over `ARGV` also has its issues:
# 1. You need to manually check for `ARGV.empty?` and then default it to `/dev/stdin` if no files
#    were given. However, neither `/dev/stdin` nor `/dev/fd/1` are technically portable, and
#    what I can tell Ruby does not automatically recognize them and use the appropriate filenos.
# 2. We have to manually check for `-` ourselves and redirect it to `/dev/stdin`, which is janky.
# 3. It's much more verbose

## If no arguments are given, default to `-`
ARGV.replace %w[-] if ARGV.empty?

## Iterate over each file in `ARGV`, and print their contents.
ARGV.each do |filename|
  ## Open the file that was requested. As a special case, if the value `-` is given, it reads from
  # stdin. (We can't use `/dev/stdin` because it's not portable to Windows, so we have to use
  # `$stdin` directly.)
  file =
    if filename == '-'
      $stdin
    else
      File.open(filename, 'rb', encoding: $encoding)
    end

  ## Print out the filename, a colon, and a space if prefixes were requested.
  print filename, ': ' if $prefixes

  ## Print the escapes for the file
  print_escapes file
rescue => err
  ## Whenever an error occurs, we want to handle it, but not bail out: We want to print every file
  # we're given (like `cat`), reporting errors along the way, and then exiting with a non-zero exit
  # status if there's a problem.
  warn err       # Warn of the problem
  @FILE_ERROR = true # For use when we're exiting
ensure
  ## Regardless of whether an exception occurred, attempt to close the file after each execution.
  # However, do not close `$stdin` (which occurs when `-` is passed in as a filename), as we might
  # be reading from it later on. Additionally any problems closing the file are silently swallowed,
  # as we only care about problems opening/reading files, not closing them.
  unless file.nil? || file.equal?($stdin) # file can be `nil` if opening it failed
    file.close rescue nil
  end
end

## If there was a problem reading a file, exit with a non-zero exit status. Note that we do this
# instead of `exit !@FILE_ERROR`, as the `--invalid-bytes-failure` flag sets an `at_exit` earlier in
# this file which checks for the exiting exception, which `exit false` would still raise.
exit 1 if @FILE_ERROR
