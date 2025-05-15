#!/bin/sh
exec env ruby -S -Ebinary "$0" "$@"
#!ruby
# -*- encoding: UTF-8; frozen-string-literal: true -*-

=begin Notes on the above
The first three lines (the shebang, `exec env`, and `#!ruby`) are there so that we can specify the
`-Ebinary` flag, which specifies that all command-line arguments should be binary-encoded; If we
didn't, they'd default to UTF-8 (unless `RUBYOPT` was set), and `optparse`'s regexes would fail. An
alternative would be to do something like `$*.replace $*.map { (+_1).force_encoding 'binary' }`, but
we need to clone each arg, as ruby makes the arguments frozen, which precludes `force_encoding`.
Since we possibly expect large strings to be passed in, I decided to juse use the `#!/bin/sh` hack.

We also specify this file's encoding as UTF-8 (which overrides what `RUBYOPT` might have), as that
way all the strings default to it. We also specify frozen string literals, as we use a lot of
strings.
=end

####################################################################################################
#                                                                                                  #
#                                             Prelude                                              #
#                                                                                                  #
####################################################################################################

## Import `optparse`, which is a default gem (and thus should always be available). Note that we
# target older versions of Ruby (2.3.0 and above), so we don't use some of the new features of
# optparse.
require 'optparse'

## Enable YJIT, for speed improvements. If there's _any_ problems (including running on a version
# where YJIT doesn't exist), just silently ignore them.
begin
  RubyVM::YJIT.enable
rescue Exception
  # Completely ignore the exception
end

## Redefine `abort` and `warn` to prepend the program name to the message, in the traditional style.
PROGRAM_NAME = File.basename($0, '.*')
def abort(message) super "#{PROGRAM_NAME}: #{message}" end
def warn(message)  super "#{PROGRAM_NAME}: #{message}" end

## Converts a string's bytes to their `\xHH` escaped version
# it's here because `hex_bytes` is frequently used
class String
  def hex_bytes
    each_byte.map { |byte| '\x%02X' % byte }.join
  end
end

####################################################################################################
#                                                                                                  #
#                                             Patterns                                             #
#                                                                                                  #
####################################################################################################

module Patterns
  C_ESCAPES_MAP = {
    "\0" => '\0', "\a" => '\a', "\b" => '\b', "\t" => '\t',
    "\n" => '\n', "\v" => '\v', "\f" => '\f', "\r" => '\r',
    "\e" => '\e', "\\" => '\\\\',
  }
  C_ESCAPES_DEFAULT = C_ESCAPES_MAP.keys.map{_1.inspect[1..-2]}.join.sub('u000','')

  PRINT      = ->char { char }
  DELETE     = ->_char{ $SOMETHING_ESCAPED = true; '' }
  DOT        = ->_char { visualize '.' }
  HEX        = ->char { visualize char.hex_bytes }
  OCTAL      = ->char { visualize char.each_byte.map { |byte| '\%03o' % byte }.join }
  CODEPOINTS = ->char { visualize '\u{%04X}' % char.ord }
  C_ESCAPES  = ->char { visualize C_ESCAPES_MAP.fetch(char) }
  HIGHLIGHT  = ->char { visualize char }
  PICTURES   = ->char{
    case char
    when "\0".."\x1F" then visualize (0x2400 + char.ord).chr(Encoding::UTF_8)
    when "\x7F"       then visualize "\u{2421}"
    when ' '          then visualize "\u{2423}"
    else                   HEX.call(char) # Default to hex if pictures doesn't work
    end
  }

  DEFAULT = ->char{
    case
    when char == '\\'
      $use_color ? '\\' : '\\\\'
    when (ce = C_ESCAPES_MAP[char])
      visualize ce
    when char <= "\x1F", char == "\x7F", ($encoding == Encoding::BINARY && "\x7F" <= char)
      visualize char.hex_bytes
    else
      char
    end
  }

  @patterns = []
  @default_charset = nil
  @default_action  = DEFAULT

  module_function

  def add_charset(charset, block)
    return if charset == '' || charset == '^' # Ignore empty charsets
    @patterns.prepend [charset, block]
  end

  class << self
    attr_writer :default_charset
    attr_writer :default_action
  end

  def create_charset(selector)
    case selector
    when '\A'         then /./m
    when '\E'         then default_charset_computed
    when '\m'         then LAMBDA_FOR_MULTIBYTE
    when '\M'         then LAMBDA_FOR_SINGLEBYTE
    when String       then Regexp.new("[#{selector}]".force_encoding($encoding))
    when Regexp, Proc then selector
    else raise "fail: bad charset '#{selector.inspect}'"
    end
  end

  def default_charset_computed
    @default_charset_computed ||=
      if @default_charset
        create_charset @default_charset
      elsif @default_charset == false
        ->char { false }
      elsif $encoding == Encoding::BINARY
        Regexp.new (+"[\0-\x1F\x7F-\xFF]").force_encoding(Encoding::BINARY)
      else
        /[\0-\x1F\x7F]/
      end
  end

  LAMBDA_FOR_MULTIBYTE = ->char{char.bytesize > 1}
  LAMBDA_FOR_SINGLEBYTE = ->char{char.bytesize == 1}

  def build!
    @built = @patterns.map do |selector, block|
      [create_charset(selector), block]
    rescue RegexpError
      abort $!
    end
  end

  def handle(char)
    @built.each do |condition, escape_method|
      return escape_method.call(char) if condition === char
    end

    if default_charset_computed === char
      @default_action.call(char)
    else
      char
    end
  end
end


####################################################################################################
#                                                                                                  #
#                                         Parse Arguments                                          #
#                                                                                                  #
####################################################################################################

# Whether visual effects should be enabled by default
USE_COLOR_DEFAULT = $use_color =
  if ENV.fetch('FORCE_COLOR', '') != ''
    true
  elsif ENV.fetch('NO_COLOR', '') != ''
    false
  else
    $stdout.tty?
  end

# Fetch standout constants (regardless of whether we're using them, as they're used as defaults)
VISUAL_BEGIN     = ENV.fetch('P_VISUAL_BEGIN', "\e[7m")
VISUAL_END       = ENV.fetch('P_VISUAL_END',   "\e[27m")
VISUAL_ERR_BEGIN = ENV.fetch('P_VISUAL_ERR_BEGIN', "\e[37m\e[41m")
VISUAL_ERR_END   = ENV.fetch('P_VISUAL_ERR_END',   "\e[49m\e[39m")
BOLD_BEGIN       = (ENV.fetch('P_BOLD_BEGIN', "\e[1m") if $use_color)
BOLD_END         = (ENV.fetch('P_BOLD_END',   "\e[0m") if $use_color)

OptParse.new do |op|
  op.program_name = PROGRAM_NAME
  op.version = '0.10.1'
  op.banner = <<~BANNER
  #{VISUAL_BEGIN if $use_color}usage#{VISUAL_END if $use_color}: #{BOLD_BEGIN}#{op.program_name} [options]#{BOLD_END}                # Read from stdin
         #{BOLD_BEGIN}#{op.program_name} [options] [string ...]#{BOLD_END}   # Print strings
         #{BOLD_BEGIN}#{op.program_name} -f [options] [file ...]#{BOLD_END}  # Read from files
  When no args are given, first form is assumed if stdin is not a tty.
  BANNER

  op.on_head 'A program to escape "weird" characters'

  # Define a custom `separator` function to add bold to each section
  def op.separator(title, additional = nil)
    super "\n#{BOLD_BEGIN}#{title}#{BOLD_END}#{additional && ' '}#{additional}"
  end

  # We can't use an `op.accept :CHARSET` here to create regex patterns because we only know the
  # encoding after parsing all options, at which point we'd have already created all the regexes.

  ##################################################################################################
  #                                        Generic Options                                         #
  ##################################################################################################
  op.separator 'GENERIC OPTIONS'

  op.on '-h', 'Print a shorter help message and exit' do
    puts <<~EOS
    #{BOLD_BEGIN}usage: #{op.program_name} [options] [string ...]#{BOLD_END}
      --help          Print a longer help message with more options
      -f              Interpret all arguments as filenames, not strings
      -c              Check if any escapes are printed, and exit nonzero if so.
      -q              Don't output anything. (Useful with -c)
      -1              Print one argument per line, but don't add "prefixes"
      -n              Print spaces between arguments, and omit the trailing newline.
    #{BOLD_BEGIN}ESCAPES#{BOLD_END} (All are mutually exclusive)
      -x, -o          Print escaped chars in hex/octal notation
      -d              Delete escaped chars from the output
      -p              Print escaped chars unchanged
      -.              Replace escaped chars with a period ('.')
      -P              Replace escaped chars with their "pictures"
    #{BOLD_BEGIN}SPECIFIC ESCAPES#{BOLD_END}
      -l              Don't escape newlines.
      -w              Don't escape newlines, tabs, or spaces
      -s, -S          Escape spaces by highlighting it/with "pictures"
      -B              Escape backslashes. (defaults when colour is off)
      -m              Escape multibyte characters with their Unicode codepoint.
      -a              Escape _every_ character. (Must be used with an "ESCAPES")
    #{BOLD_BEGIN}INPUT DATA#{BOLD_END}
      -b              Interpret inputs as binary text
      -A              Interpret inputs as ASCII; like -b, except has invalid bytes
      -8              Interpret inputs as UTF-8
    EOS
    exit
  end

  op.on '--help', 'Print a longer usage message and exit' do
    # Newer versions of OptParse have `op.help_exit`, but we also support older ones
    if defined? op.help_exit
      op.help_exit
    else
      puts op.help
      exit
    end
  end

  op.on '--version', 'Print the version and exit' do
    puts op.ver
    exit
  end

  op.on '--debug', 'Enable internal debugging code.' do
    $DEBUG = $VERBOSE = true
  end

  op.on '-f', '--[no-]files', 'Interpret trailing options as filenames to read' do |f|
    $files = f
  end

  $malformed_error = true
  op.on '--[no-]malformed-error', 'Invalid chars in the --encoding cause exit status 2. (default)' do |me|
    $malformed_error = me
  end

  $escape_error = false
  op.on '-c', '--[no-]check-escapes', 'Exits with status 1 if any character is escaped. Useful to',
                                      'check inputs programmatically to ensure they are "normal".' do |ee|
    $escape_error = ee
  end

  ##################################################################################################
  #                                            Outputs                                             #
  ##################################################################################################
  op.separator 'OUTPUTS'

  $quiet = false
  op.on '-q', '--[no-]quiet', 'Do not output anything. (Useful with -c or --malformed-error)' do |q|
    $quiet = q
  end

  # (Support `--color`, `--no-color`, and `--color=...`)
  op.on '--[no-]color[=WHEN]', %w[always never auto], 'When to enable visual effects. (WHEN is always, never, auto)',
                                                      'auto (default) uses on NO_COLOR/FORCE_COLOR; See ENV VARS below' do |w|
    $use_color =
      case w
      when 'always', nil  then true
      when 'never', false then false
      when 'auto'         then USE_COLOR_DEFAULT
      else fail # Should never happen, as a list of valid options is given via `%w[...]`.
      end
  end

  # TODO: Should `--prefixes`, `--one-per-line`, and `--no-prefixes-or-newline` be collapsed?
  $trailing_newline = true
  op.on '--prefixes', "Add \"prefixes\". (default if stdout's a tty, and args are given)" do
    $prefixes = true
    $trailing_newline = true
  end

  op.on '-1', '--one-per-line', "Print each arg on its own line. (default when --prefixes isn't)" do
    $prefixes = false
    $trailing_newline = true
  end

  op.on '-n', '--no-prefixes-or-newline', 'Disables both prefixes and trailing newlines', 'Spaces are printed between args unless -f is given' do
    # No need to have an option to set `$trailing_newline` on its own to false, as it's useless
    # when `$prefixes` is truthy.
    $prefixes = false
    $trailing_newline = false
  end

  ##################################################################################################
  #                                            Escapes                                             #
  ##################################################################################################

  op.separator 'ESCAPES', '(Change the default output behaviour. -p, -d, -., -x, -o, and -P are mutually exclusive)'

  op.on '-p', '--escape-by-print', 'Print escaped chars verbatim' do
    Patterns.default_action = Patterns::PRINT
  end

  op.on '-d', '--escape-by-delete', 'Delete escaped chars' do
    Patterns.default_action = Patterns::DELETE
  end

  op.on '-.', '--escape-by-dot', "Replace escaped chars with '.'" do
    Patterns.default_action = Patterns::DOT
  end

  op.on '-x', '--escape-by-hex', 'Output hex escape (\xHH) for escaped chars' do
    Patterns.default_action = Patterns::HEX
  end

  op.on '-o', '--escape-by-octal', 'Output octal escapes (\###) for escaped chars' do
    Patterns.default_action = Patterns::OCTAL
  end

  op.on '-P', '--escape-by-pictures', 'Print out pictures for some chars; others use hex' do
    Patterns.default_action = Patterns::PICTURES
  end

  op.on '--escape-charset CHARSET', 'Explicitly set the charset that -p, -d, -., and -x use' do |cs|
    Patterns.default_charset = cs
  end

  $escape_surronding_spaces = true
  op.on '--[no-]escape-surrounding-space', "Escape leading/trailing spaces. Doesn't work with -f (default)" do |ess|
    $escape_surronding_spaces = ess
  end

  ##################################################################################################
  #                                           Shorthands                                           #
  ##################################################################################################

  op.separator 'SHORTHANDS'
  op.on '-l', '--print-newlines', "Don't escape newline. (Same as --print='\\n')" do
    Patterns.add_charset(/\n/, Patterns::PRINT)
  end

  op.on '-w', '--print-whitespace', "Don't escape newline, tab, or space. (Same as --print='\\n\\t ')" do
    Patterns.add_charset(/[\n\t ]/, Patterns::PRINT)
  end

  op.on '-s', '--highlight-space', "Escape all spaces with highlights. (Same as --highlight=' ')" do
    Patterns.add_charset(/ /, Patterns::HIGHLIGHT)
  end

  op.on '-S', '--picture-space', "Escape all spaces with a \"picture\". (Same as --picture=' ')" do
    Patterns.add_charset(/ /, Patterns::PICTURES)
  end

  op.on '-B', '--escape-backslashes', "Escape backslashes as '\\\\'. (Same as --c-escape='\\\\')",
                                      '(default if not visual mode)' do |eb|
    Patterns.add_charset(/\\/, Patterns::C_ESCAPES)
  end

  op.on '-m', '--multibyte-codepoints', "Use codepoints for multibyte chars. (Same as --codepoint='\\m')",
                                        '(Not useful in single-byte-only encodings)' do
    Patterns.add_charset(Patterns::LAMBDA_FOR_MULTIBYTE, Patterns::CODEPOINTS)
  end

  op.on '-a', '--escape-all', "Mark all characters as escaped. (Same as --escape-charset='\\A')",
                              'Does nothing alone; it needs to be used with an "ESCAPES" flag' do
    Patterns.default_charset = /./m
  end

  ##################################################################################################
  #                                        Specific Escapes                                        #
  ##################################################################################################

  op.separator 'SPECIFIC ESCAPES', '(Takes precedence over "ESCAPES"; Ties go to the last one specified)'

  op.on '--print CHARSET', 'Print characters, unchanged, which match CHARSET' do |cs|
    Patterns.add_charset(cs, Patterns::PRINT)
  end

  op.on '--delete CHARSET', 'Delete characters which match CHARSET from the output.' do |cs|
    Patterns.add_charset(cs, Patterns::DELETE)
  end

  op.on '--dot CHARSET', "Replaces CHARSET with a period ('.')" do |cs|
    Patterns.add_charset(cs, Patterns::DOT)
  end

  op.on '--hex CHARSET', 'Replaces characters with their hex value (\xHH)' do |cs|
    Patterns.add_charset(cs, Patterns::HEX)
  end

  op.on '--octal CHARSET', 'Replaces characters with their octal escapes (\###)' do |cs|
    Patterns.add_charset(cs, Patterns::OCTAL)
  end

  op.on '--codepoint CHARSET', 'Replaces chars with their UTF-8 codepoints (ie \u{...}). See -m' do |cs|
    Patterns.add_charset(cs, Patterns::CODEPOINTS)
  end

  op.on '--highlight CHARSET', 'Prints the char unchanged, but visual effects are added to it.' do |cs|
    Patterns.add_charset(cs, Patterns::HIGHLIGHT)
  end

  op.on '--picture CHARSET', 'Use "pictures" (U+240x-U+242x). Attempts to generate pictures',
                                       "for chars outside of '\\0-\\x20\\x7F' is an error." do |cs|
    Patterns.add_charset(cs, Patterns::PICTURES)
  end

  op.on '--c-escape CHARSET', 'Like --hex, except c-style escapes (eg \n) are used for the',
                              "following chars: #{Patterns::C_ESCAPES_DEFAULT}" do |cs|
    Patterns.add_charset(cs, Patterns::C_ESCAPES)
  end

  op.on '--default CHARSET', 'Use the default patterns for chars in CHARSET' do |cs|
    Patterns.add_charset(cs, Patterns::DEFAULT)
  end

  ##################################################################################################
  #                                        Specific Escapes                                        #
  ##################################################################################################
  op.separator 'ENCODINGS', '(default is normally --utf-8. If POSIXLY_CORRECT is set, --locale is the default)'

  op.on '--encoding ENCODING', "Specify the input's encoding. Case-insensitive. Encodings that",
                               "aren't ASCII-compatible encodings (eg UTF-16) are illegal." do |enc|
    $encoding = Encoding.find enc rescue abort $!
    abort "Encoding #$encoding is not ASCII-compatible!" unless $encoding.ascii_compatible?
  end

  op.on '--list-encodings', 'List all possible encodings, and exit' do
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
  op.on <<-'EOS' # Note: `-EOS` not `~EOS` to keep leading spaces
    FORCE_COLOR, NO_COLOR
      Controls `--color=auto`. If FORCE_COLOR is set and nonempty, acts like `--color=always`. Else,
      if NO_COLOR is set and nonempty, acts like `--color=never`. If neither is set to a non-empty
      value, `--color=auto` defaults to `--color=always` when stdout is a tty.

    POSIXLY_CORRECT
      If present, changes the default `--encoding` to be `locale` (cf locale(1).), and also
      disables parsing switches after arguments (e.g. passing in `foo -x` as arguments will not
      interpret `-x` as a switch).

    P_VISUAL_BEGIN, P_VISUAL_END
      Beginning and ending escape sequences for --visual; Usually don't need to be set, as they have
      sane defaults.

    P_VISUAL_ERR_BEGIN, P_VISUAL_ERR_END
      Like P_VISUAL_BEGIN/P_VISUAL_END, except for invalid bytes (eg 0xC3 in --utf-8)

    LC_ALL, LC_CTYPE, LANG
       Checked (in that order) for the encoding when --encoding=locale is used.
  EOS

  ##################################################################################################
  #                                      CHARSET Description                                       #
  ##################################################################################################

  op.separator 'CHARSETS'
  op.on <<~'EOS'
    A 'CHARSET' is a regex character without the surrounding brackets (for example, --delete='^a-z' will
    only output lowercase letters.) In addition to normal escapes (eg '\n' for newlines, '\w' for "word"
    characters, etc), some other special sequences are accepted:
      - '\A' matches all chars (so `--print='\A'` would print out every character)
      - '\m' matches multibyte characters (only useful if input data is multibyte like, UTF-8.)
      - '\M' matches all single-byte characters (i.e. anything \m doesn't match)
      - '\E' matches the charset "ESCAPES" uses (so `--hex='\E'` is equivalent to `--escape-by-hex`)
    If more than pattern matches, the last one supplied on the command line wins.
  EOS

  op.separator 'EXIT CODES'
  op.on <<~'EOS'
    Specific exit codes are used:
      - 0    No problems encountered
      - 1    A problem opening a file given with `-f`
      - 2    Command-line usage error
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
defined? $prefixes or $prefixes = $stdout.tty? && (!$*.empty? || (defined?($files) && $files))
defined? $files    or $files = !$stdin.tty? && $*.empty?
defined? $encoding or $encoding = ENV.key?('POSIXLY_CORRECT') ? Encoding.find('locale') : Encoding::UTF_8
$quiet and $stdout = File.open(File::NULL, 'w')

PATTERNS = Patterns.build!

## Force `$trailing_newline` to be set if `$prefixes` are set, as otherwise there wouldn't be a
# newline between each header, which is weird.
$trailing_newline ||= $prefixes

####################################################################################################
#                                                                                                  #
#                                          Exit Statuses                                           #
#                                                                                                  #
####################################################################################################

# Set the defaults for the options
$ENCODING_FAILED = $SOMETHING_ESCAPED = false

# Change the exit status to reflect `--malformed-error` / `--no-check-escapes`
at_exit do
  # `at_exit` runs even when exiting via an exception, but we only change the exit status upon a
  # normal return.
  next if $!

  # We have specific exit codes for the different conditions, but they're documented as just
  # "non-zero exit statuses."
  if $malformed_error && $ENCODING_FAILED
    exit 1
  elsif $escape_error && $SOMETHING_ESCAPED
    exit 1
  end
end

####################################################################################################
#                                                                                                  #
#                                       Visualizing Escapes                                        #
#                                                                                                  #
####################################################################################################

# Visualizes `string` by surrounding it with the visual escape sequences if visual mode is enabled.
# Also, sets the variable `$SOMETHING_ESCAPED` regardless of visual mode for `--check-escapes`.
if $use_color
  def visualize(string, start=VISUAL_BEGIN, stop=VISUAL_END)
    $SOMETHING_ESCAPED = true
    "#{start}#{string}#{stop}"
  end
else
  def visualize(string, start=nil, stop=nil)
    $SOMETHING_ESCAPED = true
    string
  end
end

####################################################################################################
#                                                                                                  #
#                                        Create Escape Hash                                        #
#                                                                                                  #
####################################################################################################

## Construct the `ESCAPES_CACHE` hash, whose keys are characters, and values are the corresponding
# sequences to be printed.
ESCAPES_CACHE = Hash.new do |hash, key|
  hash[key] =
    if !key.valid_encoding?
      $ENCODING_FAILED = true # for the exit status with `$malformed_error`.
      visualize(key.hex_bytes, VISUAL_ERR_BEGIN, VISUAL_ERR_END)
    else
      Patterns.handle(key)
    end
end

####################################################################################################
#                                                                                                  #
#                                         Handle Arguments                                         #
#                                                                                                  #
####################################################################################################

## Put both stdin and stdout in bin(ary)mode: Disable newline conversion (which is used by Windows),
# no encoding conversion done, and defaults the encoding to Encoding::BINARY (ie ascii-8bit). We
# need this to ensure that we're handling exactly what we're given, and ruby's not trying to be
# smart. Note that we set the encoding of `$stdin` (which doesn't undo the other binmode things),
# as we might be iterating over `$encoding`'s characters from `$stdin` (if `-` was given).
$stdout.binmode
$stdin.binmode.set_encoding $encoding

def print_escapes(has_each_char, suffix = nil)
  ## Print out each character in the file, or their escapes. We capture the last printed character,
  # so that we can match it in the following block. (We don't want to print newlines if the last
  # character in a file was a newline.)
  last = nil
  has_each_char.each_char do |char|
    print last = ESCAPES_CACHE[char]
  end

  ## If a suffix is given (eg trailing spaces with `--escape-surrounding-space)`, then print it out
  # before printing a (possible) trailing newline.
  print suffix if suffix

  ## Print a newline if the following are satisfied:
  # 1. It was requested. (This is the default, but can be suppressed by `--no-prefixes-or-newline`.)
  # 2. At least one character was printed, or prefixes were enabled; If no characters are printed,
  #    we normally don't want to add a newline, when prefixes are being output we want each filename
  #    to be on their own lines.
  # 3. The last character to be printed was not a newline; This is normally the case, but if the
  #    newline was unescaped (eg `-l`), then the last character may be a newline. This condition is
  #    to prevent a blank line in the output. (Kinda like how `puts "a\n"` only prints one newline.)
  puts if $trailing_newline && last != "\n" && (last != nil || $prefixes)
end

####################################################################################################
#                                                                                                  #
#                                Handle when arguments are strings                                 #
#                                                                                                  #
####################################################################################################

## Interpret arguments as strings
unless $files
  ARGV.each_with_index do |string, idx|
    # Print out the prefix if a header was requested
    if $prefixes
      printf '%5d: ', idx + 1
    elsif !$trailing_newline && idx.nonzero?
      print ' '
    end

    # Unfortunately, `ARGV` strings are frozen, and we need to forcibly change the string's encoding
    # within `handle` so can iterate over the contents of the string in the new encoding. As such,
    # we need to duplicate the string here.
    string = +string

    # If we're escaping surrounding spaces, check for them.
    if $escape_surronding_spaces
      # TODO: If we ever end up not needing to modify `string` via `.force_encoding` down below (ie
      # if there's a way to iterate over chars without changing encodings/duplicating the string
      # beforehand), this should be changed to use `byteslice`. The method used here is more
      # convenient, but is destructive. ALSO. It doesn't work wtih non-utf8 characters
      string.force_encoding Encoding::BINARY
      leading_spaces  = string.slice!(/\A +/) and print visualize(ESCAPES_CACHE[' '] * $&.length)
      trailing_spaces = string.slice!(/ +\z/) && visualize(ESCAPES_CACHE[' '] * $&.length)
    end

    # handle the input string
    print_escapes string.force_encoding($encoding), trailing_spaces
  end

  # Exit early so we don't deal with the chunk below. Note however, the `at_exit` earlier in this
  # file for dealing with the `--malformed-error` flag.
  return
end

####################################################################################################
#                                                                                                  #
#                                          Handle --files                                          #
#                                                                                                  #
####################################################################################################

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
  warn err           # Warn of the problem
  @FILE_ERROR = true # For use when we're exiting
ensure
  ## Regardless of whether an exception occurred, attempt to close the file after each execution.
  # However, do not close `$stdin` (which occurs when `-` is passed in as a filename), as we might
  # be reading from it later on. Additionally any problems closing the file are silently swallowed,
  # as we only care about problems opening/reading files, not closing them.
  unless file.nil? || file.equal?($stdin) # file can be `nil` if opening it failed
    file.close rescue nil # We don't care about problems closing it
  end
end

## If there was a problem reading a file, exit with a non-zero exit status. Note that we do this
# instead of `exit !@FILE_ERROR`, as the `--invalid-bytes-failure` flag sets an `at_exit` earlier in
# this file which checks for the exiting exception, which `exit false` would still raise.
exit 1 if @FILE_ERROR
