#!/usr/bin/env -S ruby -Ebinary
# -*- encoding: binary; frozen-string-literal: true -*-
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
  op.version = '0.8.5'
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

  op.on '-h', 'Shorter help usage' do
    puts <<~EOS
    #{BOLD_BEGIN}usage: #{op.program_name} [options] [string ...]#{BOLD_END}
      --help          Print a longer help message, with more options
      -f              interpret args as files, not strings
      -c              Exit nonzero if any escapes are printed. ("check")
      -N, -n          Don't add prefixes/prefixes or newlines to output
    #{BOLD_BEGIN}WHAT TO ESCAPE#{BOLD_END}
      -e CHARSET      Escape chars matching /[CHARSET]/
      -E              Escape all characters
      -u CHARSET      Don't escape chars matching /[CHARSET]/
      -U              Don't use the default escapes
      -l, -w          Unescape newlines/whitespace (space, tab, newline)
      -s, -B          Escape spaces/backslashes
      -m              Escape all multibyte characters; implies -8
    #{BOLD_BEGIN}HOW TO ESCAPE#{BOLD_END}
      -v, -V          Enable/disable visual mode
      -d, -., -x, -X  Escape by deleting/with `.`/hex bytes/always hex bytes
      -C              Escape with codepoints (implies -8)
      -P, -S          Have "pictures" for some characters/only spaces
    #{BOLD_BEGIN}ENCODINGS#{BOLD_END}
      -b, -A, -8, -L  Interpret input data as binary/ASCII/UTF-8/locale data
    EOS
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

  op.on '-f', '--[no-]files', 'Interpret trailing options as filenames to read' do |f|
    $files = f
  end

  op.on'--[no-]malformed-error', 'Invalid chars for --encoding a cause nonzero exit. (default)' do |me|
    $malformed_error = me
  end

  op.on '-c', '--[no-]check-escapes', 'Any escapes cause an error status' do |ee|
    $escape_error = ee
  end

  ##################################################################################################
  #                                       Separating Outputs                                       #
  ##################################################################################################
  op.separator 'SEPARATING OUTPUTS'

  op.on '--prefixes', "Add \"prefixes\". (default if stdout's a tty, and args are given)" do
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
  op.separator 'WHAT TO ESCAPE', '(You can specify multiple options; they are additive.)'
  $unescape_regexes = []
  $escape_regexes = []
  $default_escapes = true

  op.on '-e', '--escape=CHARSET', 'Escape characters that match the regex /[CHARSET]/' do |rxp|
    $escape_regexes.push "[#{rxp}]"
  end

  # 'Same as --escape=\'\0-\u{10FFFF}\'', in utf-8
  op.on '-E', '--escape-all', 'Escape all characters. Useful when combined with --unescape.' do
    $escape_regexes.push '.'
  end

  op.on '-u', '--unescape=CHARSET', 'Do not escape characters if they match /[CHARSET]/. If a char',
                                    'matches both an --escape and --unescape, it is unescaped.' do |rxp|
    $unescape_regexes.push "[#{rxp}]"
  end

  op.on '--default-escapes', "Implicitly include --escape='\\0-\\x1F\\x7F'; If not visual mode,",
                             "also --escape='\\\\'. If --binary, also -e'\\x80-\\xFF'. (default)" do
    $default_escapes = true
  end

  op.on '-U', '--no-default-escapes', 'Dont include --default-escapes' do
    $default_escapes = false
  end


  op.on '-l', '--unescape-newline', "Same as --unescape='\\n'. (\"Line-oriented mode\")" do
    $unescape_regexes.push '[\n]'
  end

  op.on '-w', '--unescape-whitespace', "Same as --unescape='\\n\\t '" do
    $unescape_regexes.push '[\n\t ]'
  end

  op.on '-s', '--escape-space', "Same as --escape=' '" do
    $escape_regexes.push ' '
  end

  op.on '-S', '--show-spaces', 'Same as --escape-space --space-picture' do
    $space_picture = true
    $escape_regexes.push ' '
  end

  op.on '-B', '--escape-backslash', "Same as --escape='\\\\' (default if not visual mode)" do |eb|
    $escape_regexes.push '\\\\'
  end

  op.on '-m', '--escape-multibyte', "Same as --multibyte-codepoints --escape='\\u{80}-\\u{10FFFF}'.",
                                    '(Escapes all multibyte codepoints.) Implies --utf-8.' do
    $upper_codepoints = true
    $encoding = Encoding::UTF_8
    $escape_regexes.push '[\u{80}-\u{10FFFF}]'
  end

  op.on '--[no-]escape-surrounding-space', "Escape leading/trailing spaces. Doesn't work with -f (default)" do |ess|
    $escape_surronding_spaces = ess
  end

  ##################################################################################################
  #                                         How to Escape                                          #
  ##################################################################################################
  op.separator 'HOW TO ESCAPE', '(-d, -., -x, -X, and -C are mutually exclusive)'

  op.on '-v', '--visual', 'Enable visual effects. (default only if stdout is tty)' do
    $visual = true
  end

  op.on '-V', '--no-visual', 'Do not enable visual effects' do
    $visual = false
  end

  op.on '-d', '--delete', 'Delete escaped characters instead of printing their escape' do
    $escape_how = :delete
  end

  op.on '-.', '--dot', "Replace escaped characters with a '.'" do
    $escape_how = :dot
  end

  # Note: this applies only to characters without any other values
  op.on '-x', '--hex', 'Escape with hex bytes, \xHH (default)' do
    $escape_how = :hex
  end

  op.on '--[no-]c-escapes', 'Use C-style escapes (\n, \t, etc). (default if -x and not -P)' do |ce|
    $c_escapes = ce
  end

  op.on '-X', '--hex-all', 'Like --hex, but applies to _all_ characters' do
    $escape_how = :hex_all
    $upper_codepoints = false
  end

  op.on '-C', '--codepoints', 'Escape with \u{...}. Sets (and can only be used with) --utf-8.' do
    $escape_how = :codepoints
    $encoding = Encoding::UTF_8
  end

  op.on '--[no-]multibyte-codepoints', 'Like --codepoints, but only for values above 0x80. (default)'  do |uc|
    $upper_codepoints = uc
    $encoding = Encoding::UTF_8
  end

  op.on '-P', '--[no-]pictures', 'Use "pictures" (U+240x-U+242x) for some escapes.' do |cp|
    $pictures = $space_picture = cp
  end

  # The reason this doesn't imply `-s` is because you may want to use it exclusively with `--escape-surrounding-space`
  op.on '--[no-]space-picture', "Like --pictures, but only enable for spaces; Doesn't imply -s." do |sp|
    $space_picture = sp
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

  op.on '-L', '--locale', 'Same as --encoding=locale. (Uses LANG/LC_ALL/LC_CTYPE env vars)' do
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
  EOS

  ##################################################################################################
  #                                         Parse Options                                          #
  ##################################################################################################

  # Parse the options; Note that `op.parse!` handles `POSIXLY_CORRECT` internally to determine if
  # flags should be allowed to come after arguments.
  op.parse! rescue abort
end

####################################################################################################
#                                                                                                  #
#                                      Defaults for Arguments                                      #
#                                                                                                  #
####################################################################################################

# Specify defaults
defined? $visual                   or $visual = $stdout.tty?
defined? $prefixes                 or $prefixes = $stdout.tty? && (!$*.empty? || $files)
defined? $files                    or $files = !$stdin.tty? && $*.empty?
defined? $trailing_newline         or $trailing_newline = true
defined? $malformed_error          or $malformed_error = true
defined? $escape_surronding_spaces or $escape_surronding_spaces = true
was_escape_how_defined = defined?($escape_how)
defined? $escape_how               or $escape_how = :hex
defined? $c_escapes                or $c_escapes = $escape_how == :hex && !$pictures
defined? $encoding                 or $encoding = ENV.key?('POSIXLY_CORRECT') ? Encoding.find('locale') : Encoding::UTF_8
defined? $upper_codepoints         or $upper_codepoints = $encoding == Encoding::UTF_8
# ^ Escape things above `\x80` by replacing them with their codepoints if in utf-8 mode, and "make everything hex" wasn't requested

## Union all the regexes we've been given
if $default_escapes
  $escape_regexes.push '[\x00-\x1F\x7F]'
  $escape_regexes.push '[\x80-\xFF]' if $encoding == Encoding::BINARY
end

def make_regexp(regex_array, flag)
  Regexp.union regex_array.map{|re| Regexp.new (+re).force_encoding($encoding), Regexp::FIXEDENCODING }
rescue RegexpError => err
  abort "issue with --#{flag} (encoding: #$encoding): #{err}"
end

$escape_regex   = make_regexp($escape_regexes, 'escape')
$unescape_regex = make_regexp($unescape_regexes, 'unescape')

# Default for backslashes: If visual is disabled, and was given to neither `-e` or `-u`, then
# escape backslashes too.
if $default_escapes && !$visual && !$unescape_regex.match?('\\') && !$escape_regex.match?('\\')
  $escape_regex = Regexp.union '\\'.encode($encoding), $escape_regex
end

## Force `$trailing_newline` to be set if `$prefixes` are set, as otherwise there wouldn't be a
# newline between each header, which is weird.
$trailing_newline ||= $prefixes

## Validate options
unless $encoding == Encoding::UTF_8
  if $escape_how == :codepoints
    abort "cannot use --codepoints with non-UTF-8 encodings (encoding is #$encoding)"
  elsif $upper_codepoints
    abort "cannot use --multibyte-codepoints with non-UTF-8 encodings (encoding is #$encoding)"
  end
end

at_exit do
  next if $! # If there's an exception, then just yield that

  if $malformed_error && $ENCODING_FAILED
    exit 1
  elsif $escape_error && $SOMETHING_ESCAPED
    exit 1
  end
end

# ## Add the functionality in for `--malformed-error`: If the program is normally exiting (i.e.
# # it's not exiting due to an exception), then exit based on whether an encoding failed.
# $malformed_error and at_exit do
#   exit !$ENCODING_FAILED unless $!
# end

####################################################################################################
#                                                                                                  #
#                                       Visualizing Escapes                                        #
#                                                                                                  #
####################################################################################################

def should_escape?(char)
  $escape_regex.match?(char) && !$unescape_regex.match?(char)
end

# Converts a string's bytes to their `\xHH` escaped version, and joins them
def hex_bytes(string) string.each_byte.map { |byte| '\x%02X' % byte }.join end
def codepoints(string) '\u{%04X}' % string.ord end

# Add "visualize" escape sequences to a string; all escaped characters should be passed to this, as
# visual effects are the whole purpose of the `p` program.
# - if `$delete` is specified, then an empty string is returned---escaped characters are deleted.
# - if `$visual` is specified, then `start` and `stop` surround `string`
# - else, `string` is returned.
def visualize(string, start=VISUAL_BEGIN, stop=VISUAL_END)
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

C_ESCAPES = {
  "\0" => '\0',
  "\a" => '\a',
  "\b" => '\b',
  "\t" => '\t',
  "\n" => '\n',
  "\v" => '\v',
  "\f" => '\f',
  "\r" => '\r',
  "\e" => '\e',
}

# Returns the escape sequence for a character, depending on the flags given to the program. It does
# not actually add any visualizations, however; that's `escape`'s job
def escape_sequence(character)
  $SOMETHING_ESCAPED = true

  case
  when $c_escapes && (esc = C_ESCAPES[character])   then esc
  when $pictures && character.match?(/[\x00-\x1F]/)
    (0x2400 + character.ord).chr(Encoding::UTF_8)
  when $pictures && character.match?(/[\x7F]/)      then "\u{2421}"
  when character == '\\' && $escape_how != :hex_all && $escape_how != :codepoints then '\\\\'
  when character == ' '  && $space_picture          then "\u{2423}"
  when character == ' '  && $escape_how != :hex_all && $escape_how != :codepoints then ' '
  when $escape_how == :codepoints || ($upper_codepoints && character.codepoints.sum >= 0x80)
    codepoints character
  else
    hex_bytes character
  end
end

# Return the escape sequence associated with `character`, and visual effects (if there are any). It
# does not actually verify if a character _should_ be escaped; `should_escape?` is used for that.
def escape(character)
  case $escape_how
  when :dot    then visualize '.'
  when :delete then ''
  else              visualize escape_sequence character
  end
end

## Construct the `CHARACTERS` hash, whose keys are characters, and values are the corresponding
# sequences to be printed.
CHARACTERS = Hash.new do |hash, key|
  hash[key] =
    if !key.valid_encoding?
      $ENCODING_FAILED = true # for the exit status with `$malformed_error`.
      visualize hex_bytes(key), VISUAL_ERR_BEGIN, VISUAL_ERR_END
    else
      should_escape?(key) ? escape(key) : key
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
      leading_spaces  = string.slice!(/\A +/) and print visualize escape_sequence(' ') * $&.length
      trailing_spaces = string.slice!(/ +\z/) && visualize(escape_sequence(' ') * $&.length)
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
  $FILE_ERROR = true # For use when we're exiting
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
# instead of `exit !$FILE_ERROR`, as the `--invalid-bytes-failure` flag sets an `at_exit` earlier in
# this file which checks for the exiting exception, which `exit false` would still raise.
exit 1 if $FILE_ERROR
