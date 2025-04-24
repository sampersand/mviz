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
  @patterns = []
  @default_charset = nil #'[\0-\x1F\x7F]'

  class << self
    attr_writer :default_charset
  end

  def default_charset
    @default_charset ||= if $encoding == Encoding::BINARY
      Regexp.new((+"[\0-\x1F\x7F-\xFF]").force_encoding(Encoding::BINARY))
    else
      /[\0-\x1F\x7F]/
    end
  end

  def reset!
    @patterns.clear
  end

  def print(charset)
    @patterns.prepend [charset, ->char{ char }]
  end

  def delete(charset)
    @patterns.prepend [charset, ->_char{ $SOMETHING_ESCAPED = true; '' }]
  end

  def dot(charset)
    @patterns.prepend [charset, ->_char{ visualize '.' }]
  end

  def hex(charset)
    @patterns.prepend [charset, ->char{ visualize hex_bytes char }]
  end

  def codepoints(charset)
    @patterns.prepend [charset, ->char{ visualize '\u{%04X}' % char.ord }]
  end

  C_ESCAPES = {
    "\0" => '\0', "\a" => '\a', "\b" => '\b', "\t" => '\t',
    "\n" => '\n', "\v" => '\v', "\f" => '\f', "\r" => '\r',
    "\e" => '\e', "\\" => '\\\\',
  }
  C_ESCAPES_DEFAULT = /[#{C_ESCAPES.keys.map{_1.inspect[1..-2]}.join}]/

  def c_escapes(charset)
    @patterns.prepend [charset || C_ESCAPES_DEFAULT, ->char{ visualize C_ESCAPES.fetch(char) }]
  end

  def standout(charset)
    @patterns.prepend [charset, ->char{ visualize char }]
  end

  def pictures(charset)
    @patterns.prepend [charset, ->char{
      case char
      when "\0".."\x1F" then visualize (0x2400 + char.ord).chr(Encoding::UTF_8)
      when "\x7F" then visualize "\u{2421}"
      when ' '    then visualize "\u{2423}"
      else fail
      end
    }]
  end

  DEFAULT_PROC = ->char{
    if char == '\\'
      $visual ? '\\' : '\\\\'
    elsif ce = C_ESCAPES[char]
      visualize ce
    elsif (char == "\x7F" || char <= "\x1F") or ($encoding == Encoding::BINARY && char >= "\x7F")
      visualize hex_bytes char
    else
      char
    end
  }

  def default(charset)
    @patterns.prepend [charset, DEFAULT_PROC]
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

    DEFAULT_PROC.call(char)
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
  op.version = '0.8.7'
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

  ##################################################################################################
  #                                        Generic Options                                         #
  ##################################################################################################
  op.separator 'GENERIC OPTIONS'

  op.accept :CHARSET do |selector|
    case selector
    when '\A'   then /./m
    when '\@'   then :default
    when '\m'   then Patterns::LAMBDA_FOR_MULTIBYTE
    when '\M'   then Patterns::LAMBDA_FOR_SINGLEBYTE
    when ''     then throw :oops # Ie a value was given, but it's empty.
    when nil    then :default
    when String then selector.to_s
    else        fail "bad selector?: #{selector}"
    end
  end

  op.on '-h', 'Print a shorter help message and exit' do
    puts <<~EOS
    #{BOLD_BEGIN}usage: #{op.program_name} [options] [string ...]#{BOLD_END}
      --help          Print a longer help message with more options
      -f              Interpret args as files, not strings
      -c              Exit nonzero if any escapes are printed. ("check")
      -1              Print out arguments once per line, and add a trailing newline
      -n              Print out arguments with nothing separating them
      -v, -V          Enable/disable visual effects
    #{BOLD_BEGIN}INPUT DATA#{BOLD_END}
      -b, -A, -8      Interpret the input bytes as binary/ASCII/UTF-8
    #{BOLD_BEGIN}CHANGE HOW CHARACTERS ARE OUTPUT#{BOLD_END}
      -p [CHARSET]    Print chars in CHARSET unchanged
      -d [CHARSET]    Deletes chars in CHARSET
      -. [CHARSET]    Replace chars in CHARSET with a period
      -x [CHARSET]    Escape chars with their hexadecimal value of their bytes
      -P [CHARSET]    Escape some chars with their "pictures"
    #{BOLD_BEGIN}SHORTHANDS#{BOLD_END}
      -l              Don't escape newlines.
      -w              Don't escape newlines, tabs, or spaces
      -s              Escape spaces
      -B              Escape backslashes
      -m              Escape multibyte characters with their Unicode codepoint.
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

  op.separator 'ESCAPE PATTERNS', '(If something matches multiple, the last one wins.)'

  op.on '--reset-patterns', 'Clear all patterns that have been specified so far' do
    Patterns.reset!
  end

  op.on '--default-charset=CHARSET', :CHARSET, 'Set the default charset for --print, --delete, --dot, and --hex' do |cs|
    Patterns.default_charset = cs
  end

  op.on '-p', '--print[=CHARSET]', :CHARSET, 'Print characters, unchanged, which match CHARSET' do |cs|
    Patterns.print(cs || :default)
  end

  op.on '-d', '--delete[=CHARSET]', :CHARSET, 'Delete characters which match CHARSET from the output.' do |cs|
    Patterns.delete(cs || :default)
  end

  op.on '-.', '--dot[=CHARSET]', :CHARSET, "Replaces CHARSET with a period ('.')" do |cs|
    Patterns.dot(cs || :default)
  end

  op.on '-x', '--hex[=CHARSET]', :CHARSET, 'Replaces characters with their hex value (\xHH)' do |cs|
    Patterns.hex(cs || :default)
  end

  op.on '-P', '--pictures[=CHARSET]', 'Use "pictures" (U+240x-U+242x). CHARSET defaults to \0-\x20\x7F',
                                      'Attempts to generate pictures for other chars is an error.' do |cs|
    Patterns.pictures(charset || /[\0-\x20\x7F]/)
  end

  op.on '--codepoints=CHARSET', 'Replaces chars with their UTF-8 codepoints (ie \u{...}). See -m' do |cs|
    Patterns.codepoints(cs || fail)
  end

  op.on '--c-escapes=CHARSET', 'Replaces chars with their C escapes; Attempts to generate',
                               "c-escapes for non-'#{Patterns::C_ESCAPES_DEFAULT.source[1..-2]
                                  .sub('u0000', '0')}' is an error" do |cs|
    Patterns.c_escapes(cs || fail)
  end

  op.on '--standout=CHARSET', 'Like --print, except the --visualize effects are added' do |cs|
    Patterns.standout(cs || fail)
  end

  op.on '--default=CHARSET', 'Output whatever the default is for chars in CHARSET. (Note: You',
                             "can \"undo\" previous patterns via --default='\\A')" do |cs|
    Patterns.default(cs || fail)
  end

  op.on '--[no-]escape-surrounding-space', "Escape leading/trailing spaces. Doesn't work with -f (default)" do |ess|
    $escape_surronding_spaces = ess
  end

  op.on <<~'EOS'
    CHARSET is a regex character set; the braces can be omitted. For example `--delete=a-z` will
    cause all lower-case latin letters to be removed. Note that sequences like `\w` and `\d` are
    supported. In addition, there are some special cases for a charset of just: `\A` (all chars),
    `\m` (all multibyte chars), and `\M` (all non-multibyte chars)
  EOS

  ## =====
  ## =====
  ## =====

  op.separator 'SHORTHANDS'
  op.on '-l', '--print-newlines', "Same as --print='\\n'" do
    Patterns.print(/\n/)
  end

  op.on '-w', '--print-whitespace', "Same as --print='\\n\\t '" do
    Patterns.print(/[\n\t ]/)
  end

  op.on '-s', '--standout-space', "Same as --standout=' '" do
    Patterns.standout(/ /)
  end

  op.on '-B', '-\\', '--escape-backslashes', "Same as --c-escapes='\\\\' (default if not visual mode)" do |eb|
    Patterns.c_escapes(/\\/)
  end

  op.on '-m', '--multibyte-codepoints', "Same as --codepoints='\\m'" do
    Patterns.codepoints(Patterns::LAMBDA_FOR_MULTIBYTE)
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
defined? $visual                   or $visual = $stdout.tty?
defined? $prefixes                 or $prefixes = $stdout.tty? && (!$*.empty? || (defined?($files) && $files))
defined? $files                    or $files = !$stdin.tty? && $*.empty?
defined? $trailing_newline         or $trailing_newline = true
defined? $escape_surronding_spaces or $escape_surronding_spaces = true
defined? $encoding                 or $encoding = ENV.key?('POSIXLY_CORRECT') ? Encoding.find('locale') : Encoding::UTF_8
# ^ Escape things above `\x80` by replacing them with their codepoints if in utf-8 mode, and "make everything hex" wasn't requested

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
