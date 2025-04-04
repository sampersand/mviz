#!/bin/sh
exec env ruby -S -Ebinary --disable=all $0 "$@"
#!ruby
# -*- encoding: binary; frozen-string-literal: true -*-
defined?(RubyVM::YJIT.enable) and RubyVM::YJIT.enable

####################################################################################################
#                                                                                                  #
#                                         Parse Arguments                                          #
#                                                                                                  #
####################################################################################################
require 'optparse'

OptParse.new nil, 28 do |op|
  $op = op # for `$op.abort` and `$op.warn`

  op.version = '0.7.3'
  op.banner = <<~BANNER
    usage: #{op.program_name} [options] [string ...]
           #{op.program_name} -f/--files [options] [file ...]
    When no arguments, and stdin isn't a tty, the second form is assumed.
  BANNER

  op.on_head 'A program to escape "weird" characters'
  # TODO: why youno work sometimes, eg `p --escape-ties`
  # op.require_exact = true if defined? op.require_exact = true


  ##################################################################################################
  #                                        Generic Options                                         #
  ##################################################################################################
  op.separator "\nGeneric Options"

  op.on '-h', '--help', 'Print this message and exit' do
    puts op.help # Newer versions of OptParse have `op.help_exit`, but we are targeting older ones.
    exit
  end

  op.on '--version', 'Print the version and exit' do
    puts op.ver
    exit
  end

  op.on '--debug', 'Enable debug mode' do
    $DEBUG = $VERBOSE = true
  end

  op.on '-f', '--files', 'Interpret trailing options as filenames to read' do
    # Note there's no `-[no-]` prefix, because we expect this to be an explicit toggle on each time
    # it's used (i.e. you shouldn't `alias p='p -f'`.)
    $files = true
  end

  # This maybe removed in a future release, as it doesn't control a whole lot.
  op.on '--[no-]assume-tty', 'Assume stdout is tty for defaults' do |tty|
    $stdout_tty = tty
  end

  ##################################################################################################
  #                                       Separating Outputs                                       #
  ##################################################################################################
  op.separator "\nSeparating Outputs"

  op.on '-p', '--prefixes', 'Add prefixes to outputs. (default if tty)' do
    $prefixes = true
  end

  op.on '-N', '--no-prefixes', 'Do not add prefixes to the output' do
    $prefixes = false
  end

  # No need to have an option to set `$trailing_newline` on its own to false, as it's useless
  # when `$prefixes` is truthy.
  op.on '-n', '--no-prefixes-or-newline', 'Disables both prefixes and trailing newlines' do
    $prefixes = $trailing_newline = false
  end

  ##################################################################################################
  #                                         What To Escape                                         #
  ##################################################################################################
  op.separator "\nWhat to Escape. (You can specify multiple options; they are additive.)"
  $unescape_regex = []
  $escape_regex = []

  op.on '-t', '--[no-]escape-ties', 'Break ties that match both -e and -u by',
                                    'escaping. (the default is to not escape ties.)' do |et|
    $escape_ties = et
  end

  op.on '-e', '--escape=REGEX', Regexp, 'Also escape characters which match REGEX' do |rxp|
    $escape_regex.push rxp
  end

  op.on '--escape-chars=CHARS', 'Also escape any characters in CHARS' do |chars|
    $escape_regex.concat chars.split('')
  end

  op.on '-u', '--unescape=REGEX', Regexp, 'Do not escape characters which match REGEX' do |rxp|
    $unescape_regex.push rxp
  end

  op.on '--unescape-chars=CHARS', 'Do not escape any characters in CHARS' do |chars|
    $unescape_regex.concat chars.split('')
  end

  # The `-l` is because of "lien-oriented mode" as found in things like perl and ruby.
  op.on '-l', "Same as --unescape='\\n'" do
    $unescape_regex.push "\n"
  end

  op.on '-w', "Same as --unescape='[\\n\\t ]'" do
    $unescape_regex.push "\n", "\t", " "
  end

  op.on '-s', "Same as --escape=' '" do
    $escape_regex.push ' '
  end

  op.on '-B', "Same as --escape='\\\\' (default if not visual mode)" do |eb|
    $escape_regex.push '\\'
  end

  op.on '-U', "Same as --upper-codepoints --escape='[\\u{80}-\\u{10FFFF}]'", '(i.e. escape all non-ascii codepoints)' do
    $escape_unicode = true
    $escape_regex.push /[\u{80}-\u{10FFFF}]/
  end

  op.on '--[no-]escape-surrounding-space', 'Escape leading and trailing spaces. (default)',
                                           'Does not work with --files' do |ess|
    $escape_surronding_spaces = ess
  end

  ##################################################################################################
  #                                         How to Escape                                          #
  ##################################################################################################
  op.separator "\nHow to Escape (-d, -., -x, and -C are mutually exclusive)"

  op.on '-v', '--visual', 'Enable visual effects. (default if tty)' do
    $visual = true
  end

  op.on '-V', '--no-visual', 'Do not enable visual effects' do
    $visual = false
  end

  op.on '-d', '--delete', 'Delete escaped characters' do
    $escape_how = :delete
  end

  op.on '-.', '--dot', "Use a '.' instead of escapes" do
    $escape_how = :dot
  end

  op.on '-x', '--hex', 'Escape with hex bytes, \xHH (default)' do
    $escape_how = :bytes
  end

  op.on '-C', '--codepoints', 'Escape with codepoints, \u{...}. Sets --utf-8,',
                              "and can't be used with other encodings." do
    $escape_how = :codepoints
    $encoding = Encoding::UTF_8
  end

  op.on '--[no-]upper-codepoints', 'Like -C, but only for values above 0x7F; See -U'  do |uc|
    $escape_unicode = uc
    $encoding = Encoding::UTF_8
  end

  op.on '-c', '--[no-]c-escapes', 'Escape with C-style escapes (\n, \t, etc). (default if no -d.xC given)' do |ce|
    $c_escapes = ce
  end

  op.on '-P', '--[no-]pictures', 'Use "pictures" (U+240x-U+242x) for some escapes' do |cp|
    $pictures = $space_picture = cp
    $c_escapes = false unless defined? $c_escapes
  end

  op.on '--[no-]space-picture', 'Like -P, but just for space (\' \'); Requires -s' do |sp|
    $space_picture = sp
  end

  ##################################################################################################
  #                                        Input Encodings                                         #
  ##################################################################################################

  # Implementation note: Even though these usage messages reference "input encodings," the input is
  # actually always read as binary data, and then attempted to be converted to whatever these
  # encodings are
  op.separator "\nEncodings (default based on POSIXLY_CORRECT: --utf-8 if unset, --locale if set)"

  op.on '-E', '--encoding=ENCODING', "Specify the input's encoding. Case insensitive" do |enc|
    $encoding = Encoding.find enc rescue op.abort
  end

  op.on '--list-encodings', 'List all possible encodings and exit' do
    # Don't list external/internal encodings, as they're not really relevant.
    puts "available encodings: #{(Encoding.name_list - %w[external internal]).join(', ')}"
    exit
  end

  op.on '-b', '--binary', '--bytes', 'Same as --encoding=binary' do
    $encoding = Encoding::BINARY
  end

  op.on '-a', '--ascii', 'Same as --encoding=ascii' do
    $encoding = Encoding::ASCII
  end

  op.on '-8', '--utf-8', 'Same as --encoding=UTF-8 (See the -U flag)' do
    $encoding = Encoding::UTF_8
  end

  op.on '-L', '--locale', 'Same as --encoding=locale' do
    $encoding = Encoding.find('locale')
  end

  op.on '--[no-]malformed-error', 'Invalid chars cause nonzero exit. (default)' do |ibf|
    $invalid_bytes_failure = ibf
  end
  op.on <<~EOS
  The only difference between --ascii and --binary is the former considers 0x80
  and above to be invalid (and thus highlights them differently). The "locale"
  encoding (--locale) uses whatever the environment specifies. Other encodings
  are possible, but haven't been tested extensively.
  EOS

  op.on_tail "\nnote: IF any invalid bytes for the output encoding are read, the exit status is"
  op.on_tail "based on `--encoding-failure-err`"

  ##################################################################################################
  #                                        Environment Vars                                        #
  ##################################################################################################
  op.separator "\nEnvironment Variables"
  op.on <<-EOS # Note: `-EOS` not `~EOS` to keep leading spaces
    P_BEGIN_VISUAL     Beginning escape sequence for --visual
    P_END_VISUAL       Ending escape sequence for --visual
    P_BEGIN_ERR        Beginning escape sequence for invalid bytes with --visual
    P_END_ERR          Ending escape sequence for invalid bytes with --visual
    POSIXLY_CORRECT    If present, changes default encoding to the locale's (cf
                       locale(1).), and also disables parsing switches after ar-
                       guments (e.g. `p foo -x` will print out `foo` and `-x`,
                       and won't interpret `-x` as a switch.)
  EOS

  ##################################################################################################
  #                                         Parse Options                                          #
  ##################################################################################################

  # Parse the options; Note that `op.parse!` handles `POSIXLY_CORRECT` internally to determine if
  # flags should be allowed to come after arguments.
  op.parse! rescue op.abort
end

####################################################################################################
#                                                                                                  #
#                                      Defaults for Arguments                                      #
#                                                                                                  #
####################################################################################################

# Fetch standout constants (regardless of whether we're using them, as they're used as defaults)
BEGIN_VISUAL = ENV.fetch('P_BEGIN_VISUAL', "\e[7m")
END_VISUAL   = ENV.fetch('P_END_VISUAL',   "\e[27m")
BEGIN_ERR    = ENV.fetch('P_BEGIN_ERR',    "\e[37m\e[41m")
END_ERR      = ENV.fetch('P_END_ERR',      "\e[49m\e[39m")

# Specify defaults
defined? $stdout_tty               or $stdout_tty = $stdout.tty?
defined? $files                    or $files = !$stdin.tty? && $*.empty?
defined? $visual                   or $visual = $stdout_tty
defined? $invalid_bytes_failure    or $invalid_bytes_failure = true
defined? $prefixes                 or $prefixes = $stdout_tty && (!$*.empty? || $files)
defined? $escape_surronding_spaces or $escape_surronding_spaces = true
defined? $c_escapes                or $c_escapes = !defined?($escape_how) # Make sure to put this before `escape_how`'s default'
defined? $escape_how               or $escape_how = :bytes
defined? $escape_ties              or $escape_ties = false
defined? $encoding                 or $encoding = ENV.key?('POSIXLY_CORRECT') ? Encoding.find('locale') : Encoding::UTF_8

if !Regexp.union($escape_regex).match?('\\') && !Regexp.union($unescape_regex).match?('\\') && !$visual
  $escape_regex.push '\\'
end

## Union all the regexes we've been given
# $unescape_regex = Regexp.union($unescape_regex.map { |x| x.encode $encoding })
# $escape_regex   = Regexp.union($escape_regex.map { |x| x.encode $encoding })
$unescape_regex = Regexp.union($unescape_regex)
$escape_regex   = Regexp.union($escape_regex)

## Force `$trailing_newline` to be set if `$prefixes` are set, as otherwise there wouldn't be a
# newline between each header, which is weird.
$trailing_newline ||= $prefixes

## Validate options
unless $encoding == Encoding::UTF_8
  if $escape_how == :codepoints
    $op.abort "cannot use --codepoints with non-UTF-8 encodings (encoding is #$encoding)"
  elsif $escape_unicode
    $op.abort "cannot use --upper-codepoints with non-UTF-8 encodings (encoding is #$encoding)"
  end
end

## Add the functionality in for `--malformed-error`: If the program is normally exiting (i.e.
# it's not exiting due to an exception), and there was an encoding failure, then exit with status 1.
$invalid_bytes_failure and at_exit do
  exit 1 if !$! && $ENCODING_FAILED
end

####################################################################################################
#                                                                                                  #
#                                       Visualizing Escapes                                        #
#                                                                                                  #
####################################################################################################

def should_escape?(char)
  $escape_regex.match?(char) and ($escape_ties ? true : !$unescape_regex.match?(char))
end

# Converts a string's bytes to their `\xHH` escaped version, and joins them
def hex_bytes(string) string.each_byte.map { |byte| '\x%02X' % byte }.join end
def codepoints(string) '\u{%04X}' % string.ord end


if $escape_how == :codepoints
  alias escape_bytes codepoints
elsif $escape_unicode
  def escape_bytes(string) string.codepoints.sum >= 0x80 ? codepoints(string) : hex_bytes(string) end
else
  alias escape_bytes hex_bytes
end

# Add "visualize" escape sequences to a string; all escaped characters should be passed to this, as
# visual effects are the whole purpose of the `p` program.
# - if `$delete` is specified, then an empty string is returned---escaped characters are deleted.
# - if `$visual` is specified, then `start` and `stop` surround `string`
# - else, `string` is returned.
def visualize(string, start=BEGIN_VISUAL, stop=END_VISUAL)
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
  CHARACTERS[char] = visualize escape_bytes(char)
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
    CHARACTERS[char] = visualize escape_bytes(char)
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

################################################################################
#                               Escapes and unescapes            #
################################################################################
CHARACTERS.reject! do |key, value|
  # should_escape?(key) == (key == value)

  ## TODO: use `-t`
  key.match?(if key == value then $escape_regex else $unescape_regex end)
end

CHARACTERS['\\'] = visualize('\\\\') if should_escape? '\\' # special case?? i need to fix the thing before this
CHARACTERS[" "] = visualize ($space_picture ? "\u{2423}" : ' ') if should_escape?(' ')

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
      $ENCODING_FAILED = true # for the exit status with `$invalid_bytes_failure`.
      visualize hex_bytes(char), BEGIN_ERR, END_ERR
    elsif should_escape?(char)
      visualize escape_bytes(char)
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
  tmp = CHARACTERS.to_h { [_1.encode($encoding), _2.encode($encoding)] } # Can't use `encode!` because keys of hashes are frozen
  CHARACTERS.clear
  CHARACTERS.merge! tmp
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
  suffix and print visualize suffix

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
      leading_spaces  = string.slice!(/\A +/) and $stdout.write visualize leading_spaces.gsub(' ', $space_picture ? '␣' : ' ')
      trailing_spaces = string.slice!(/ +\z/)&.gsub(' ', $space_picture ? '␣' : ' ')
    end

    # handle the input string
    print_escapes string.force_encoding($encoding), trailing_spaces
  end

  exit
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
      $stdin.binmode.set_encoding $encoding
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
  $op.warn err  # Warn of the problem
  @file_error = true # For use when we're exiting
ensure
  ## Regardless of whether an exception occurred, attempt to close the file after each execution.
  # However,# do not close `$stdin` (which occurs when `-` is passed in as a filename), as we might
  # be reading from it later on. Additionally any problems closing the file are silently swallowed,
  # as we only care about problems opening/reading files, not closing them.
  unless file.nil? || file.equal?($stdin) # file can be `nil` if opening it failed
    file.close rescue nil
  end
end

## If there was a problem reading a file, exit with a non-zero exit status. Note that we do this
# instead of `exit !@file_error`, as the `--invalid-bytes-failure` flag sets an `at_exit` earlier in
# this file which checks for the exiting exception, which `exit false` would still raise.
exit 1 if @file_error
