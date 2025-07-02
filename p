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

## Redefine `abort` and `warn` to prepend the program name to the message, in traditional unix style
PROGRAM_NAME = File.basename($0, '.*')
def abort(message) super "#{PROGRAM_NAME}: #{message}" end
def warn(message)  super "#{PROGRAM_NAME}: #{message}" end

####################################################################################################
#                                                                                                  #
#                                              Action                                              #
#                                                                                                  #
####################################################################################################

## Actions that can be taken for each character. They're all `Proc`s, but really all they need is to
# have a `.call` method on them.
module Action
  # Used with `C_ESCAPES` for faster access than just calling `.inspect`
  C_ESCAPES_MAP = {
    "\0" => '\0', "\a" => '\a', "\b" => '\b', "\t" => '\t', "\n" => '\n',
    "\v" => '\v', "\f" => '\f', "\r" => '\r', "\e" => '\e', "\\" => '\\\\',
  }

  # Used with `REPLACE`, to be the character we replace things with.
  REPLACEMENT_CHARACTER = '�'
  REPLACEMENT_CHARACTER_REPR = '\uFFFD'

  ## Returns the character unchanged
  PRINT = ->char do
    char
  end

  ## Returns nothing, but sets `$SOMETHING_ESCAPED` to true as this is a way to escape something.
  DELETE = ->_char do
    $SOMETHING_ESCAPED = true
    ''
  end

  ## Returns a single `.`
  DOT = ->_char do
    visualize '.'
  end

  ## Returns the replacement character, `REPLACEMENT_CHARACTER`
  REPLACE = ->_char do
    visualize REPLACEMENT_CHARACTER
  end

  ## Returns the bytes of the character in hexadecimal format, `\xHH`
  HEX = ->char do
    visualize char.each_byte.map { |byte| '\x%02X' % byte }.join
  end

  ## Returns the bytes of the character in octal format, `\OOO`
  OCTAL = ->char do
    visualize char.each_byte.map { |byte| '\%03o' % byte }.join
  end

  ## Returns the unicode codepoint for the character, `\u{HHHH}`.
  CODEPOINTS = ->char do
    visualize '\u{%04X}' % char.ord
  end

  # Simply visualizes the character without changing it
  HIGHLIGHT = ->char do
    visualize char
  end

  ## Returns the C-style escape for the character, if it exists. If it doesn't, a warning is
  # printed, and it falls back on hex escapes
  C_ESCAPES = ->char do
    unless (c_escape = C_ESCAPES_MAP[char])
      warn "character #{char.inspect} does not have a c escape; falling back on hex escapes"
      return HEX.call(char)
    end

    visualize c_escape
  end

  ## Returns Unicode "pictures" for certain characters (0x00 thru 0x20, and 0x7f). Other characters
  # yield a warning with a fallback on hex escapes.
  PICTURE = ->char do
    case char
    when "\0".."\x1F" then visualize (0x2400 + char.ord).chr(Encoding::UTF_8)
    when "\x7F"       then visualize "\u{2421}"
    when ' '          then visualize "\u{2423}"
    else
      warn "character #{char.inspect} does not have a picture; falling back on hex escapes"
      HEX.call(char)
    end
  end

  ## The sensible, default action for characters: Backslash is escaped if not in visual mode,
  # c-escapable characters are escaped, and invisible characters (0x00-0x1F, 0x7F, or 0x7F and above
  # if in binary mode) are printed in hex escapes. All other characters are returned unchanged.
  DEFAULT = ->char do
    if char == '\\'
      $use_color ? '\\' : '\\\\'
    elsif C_ESCAPES_MAP.key?(char)
      C_ESCAPES.call(char)
    elsif char <= "\x1F" || char == "\x7F" || ($encoding == Encoding::BINARY && "\x7F" <= char)
      HEX.call(char)
    else
      char
    end
  end

  VALID_ACTIONS = constants.map { |name|
    a = Action.const_get(name)
    a.is_a?(Proc) ? [name.to_s.downcase.tr('_','-'), a] : nil
  }.compact.to_h

  ## The action to use by default.
  class << self
    attr_accessor :default
    attr_accessor :error
  end
  self.default = DEFAULT
  self.error   = HEX
end

####################################################################################################
#                                                                                                  #
#                                             Pattern                                              #
#                                                                                                  #
####################################################################################################

## Like a `Regexp`, except the `===` method calls `.match?`, instead of `=~` (which sets global
# variables, and is less efficient).
class RegexpFasterEqq < Regexp
  alias === match?
end

## Helpers for matching against characters. All that a "Character Set" needs to have is the `===`
# method defined on it, which is used to determine if the character set matches or not.
module Pattern
  ## A character set which matches _all_ characters.
  ALL = ->char { true }

  ## A character set which matches _no_ characters.
  NONE = ->char { false }

  ## A character set which matches characters composed of more than one byte.
  MULTIBYTE = ->char { char.bytesize > 1 }

  ## A character set which matches characters composed of exactly one byte.
  SINGLEBYTE = ->char { char.bytesize == 1 }

  # INVISIBLE = /[\u0009-\u000D \xA0\x]/

  module_function

  ## Creates a character set (ie something which has `===` defined) based on `selector`.
  def build(selector)
    case selector
    when '\A'         then ALL
    when '\N'         then NONE
    when '\@'         then default # if this changes, change `default_pattern=`
    when '\m'         then MULTIBYTE
    when '\M'         then SINGLEBYTE
    when String       then RegexpFasterEqq.new((+"[#{selector}]").force_encoding($encoding)) # TODO: WHY is this frozen in ruby 2.6.10
    when Regexp, Proc then selector
    else raise "fail: bad pattern '#{selector.inspect}'"
    end
  end

  @raw_default = nil

  ## Set the default pattern; This can only be called before `build_default_pattern!` is run. If
  def raw_default=(pattern)
    fail if @default

    @raw_default =
      case pattern
      when '\@'    then nil # Handle `\@` here to mean "whatever the default is"
      when '', '^' then false
      else              pattern
      end
  end

  ## Constructs the default pattern; This should only ever be called once, after any calls to the
  # `default_pattern=` method have been performed.
  def build_default_pattern!
    fail if @default

    @default =
      if @raw_default
        build @raw_default
      elsif @raw_default == false
        NONE
      else
        # Universal default character class; encode it in whatever the encoding we're using is.
        regex = (+'[\0-\x1F\x7F').force_encoding $encoding

        # Add the upper range if in binary
        regex.concat '-\xFF' if $encoding == Encoding::BINARY

        # If we're using the default action, and we're using colours, then also add backslash to the
        # list of escapes. We need to use a double backslash so it interpolates correctly.
        regex.concat '\\\\' if Action.default == Action::DEFAULT && !$use_color

        # Finish the character class
        regex.concat ']'
        RegexpFasterEqq.new regex
      end
  end

  ## Get the default pattern; This should only be called after `build_default_pattern!` is called,
  # as the encoding for the pattern isn't known until all command-line options are parsed.
  def default
    @default or fail
  end
end

####################################################################################################
#                                                                                                  #
#                                             PatternAndAction                                             #
#                                                                                                  #
####################################################################################################

## The list of patterns the user has supplied in command-line flags
module PatternAndAction
  @raw_patterns = []

  module_function

  ## Adds a pattern (comprise of a `Pattern` and its `Action`) to the start of the list of patterns.
  # This means that later patterns take priority over earlier ones. Should not be called after
  # `.build!` is called.
  def add_pattern_and_action(pattern, action)
    if pattern.nil?
      Action.default = action
      return
    end

    fail if @patterns # Ensure that we're called only before `.build!`

    # Ignore patterns which are empty. This isn't just an optimization: Without this check, the
    # eventual call to `Pattern.build` will fail because `[]` and `[^]` aren't valid regex character
    # classes.
    return if pattern == '' || pattern == '^'

    # Add the pattern and its action to the list of raw patterns
    @raw_patterns.prepend [pattern, action]
  end

  ## Finalizes all the patterns, constructing the patterns with the current encoding. Should only
  # ever be called once, after all user-supplied patterns are added via `add_pattern_and_action`.
  def build!
    fail if @patterns # Ensure that we're only called once.

    # Construct the default pattern, so that any user-supplied patterns can reference it.
    Pattern.build_default_pattern!

    # Build the patterns via `Pattern.build`.
    @patterns = @raw_patterns.map { |pattern, action| [Pattern.build(pattern), action] }
  end

  ## Returns the representation of a character; Should only be called after `.build!`.
  def handle(char)
    # No need for a `fail unless @patterns`, as `@patterns.each` will fail if `.build!` wasn't
    # called first (as `@patterns` will be nil.)

    # Check user-supplied patterns to see if any match
    @patterns.each do |condition, action|
      return action.call(char) if condition === char
    end

    # No user-supplied actions match, so check the default one
    return Action.default.call(char) if Pattern.default === char

    # The default one didn't match either, so just return the character unchanged.
    char
  end
end

####################################################################################################
#                                                                                                  #
#                                  Constants and Global Defaults                                   #
#                                                                                                  #
####################################################################################################

## Whether visual effects should be enabled by default
USE_COLOR = $use_color =
  if ENV.fetch('FORCE_COLOR', '') != ''
    true
  elsif ENV.fetch('NO_COLOR', '') != ''
    false
  else
    $stdout.tty?
  end

## Whether POSIX-ly correct defaults should be used.
IS_POSIXLY_CORRECT = ENV.key?('POSIXLY_CORRECT')

## Strings to surround all escaped characters with; Defaults to "invert colour"
STANDOUT_BEGIN = $standout_begin = ENV.fetch('P_STANDOUT_BEGIN', "\e[7m")
STANDOUT_END   = $standout_end   = ENV.fetch('P_STANDOUT_END',   "\e[27m")

## Like `STANDOUT_XXX`, but only for encoding errors. Defaults to "red background, light grey
# foreground"
STANDOUT_ERR_BEGIN = ENV.fetch('P_STANDOUT_ERR_BEGIN', "\e[37m\e[41m")
STANDOUT_ERR_END   = ENV.fetch('P_STANDOUT_ERR_END',   "\e[49m\e[39m")

## Bold escape sequences; Bold is only used in help message and headers when files are given.
BOLD_BEGIN = (ENV.fetch('P_BOLD_BEGIN', "\e[1m") if $use_color)
BOLD_END   = (ENV.fetch('P_BOLD_END',   "\e[0m") if $use_color)

## Set defaults for globals; user-supplied options can change these.
$encoding = IS_POSIXLY_CORRECT ? Encoding.find('locale') : Encoding::UTF_8
$malformed_error = true
$escape_error = false
$quiet = false
$trailing_newline = true
$escape_surronding_spaces = true

####################################################################################################
#                                                                                                  #
#                                         Parse Arguments                                          #
#                                                                                                  #
####################################################################################################

OptParse.new do |op|
  op.program_name = PROGRAM_NAME
  op.version = '0.13.0'
  op.banner = <<~BANNER
  #{$standout_begin if $use_color}usage#{$standout_end if $use_color}: #{BOLD_BEGIN}#{op.program_name} [options]#{BOLD_END}                # Read from stdin
         #{BOLD_BEGIN}#{op.program_name} [options] [string ...]#{BOLD_END}   # Print strings
         #{BOLD_BEGIN}#{op.program_name} -f [options] [file ...]#{BOLD_END}  # Read from files
  When no args are given, first form is assumed if stdin is not a tty.
  BANNER

  op.on_head 'A program to escape "weird" characters'

  op.accept :ACTION do |foo|
    Action::VALID_ACTIONS[foo.downcase] or raise OptionParser::InvalidArgument
  end

  # Define a custom `separator` function to add bold to each section
  def op.section(title, additional = nil)
    separator "#{BOLD_BEGIN}#{title}#{BOLD_END}#{additional && ' '}#{additional}"
  end

  # We can't use an `op.accept :PATTERN` here to create regex patterns because we only know the
  # encoding after parsing all options, at which point we'd have already created all the regexes.

  ##################################################################################################
  #                                        Generic Options                                         #
  ##################################################################################################
  op.section 'GENERIC OPTIONS'

  op.on '-h', 'Print a shorter help message and exit' do
    puts <<~EOS
    #{BOLD_BEGIN}usage: #{op.program_name} [options] [string ...]#{BOLD_END}
      --help          Print a longer help message with more options
      -f              Interpret all arguments as filenames, not strings
      -c              Check if any escapes are printed, and exit nonzero if so.
      -q              Don't output anything. (Useful with -c)
      -1 / -n         Disable prefixes; Separate arguments with newlines / spaces.
    #{BOLD_BEGIN}ESCAPES#{BOLD_END} (Mutually exclusive; Uppercase escapes control illegal bytes)
      -x (-X)         Print in hex notation
      -o (-O)         Print in octal notation
      -d (-D)         Delete from the output
      -p (-P)         Print unchanged
      -. (-@)         Replace with a period ('.')
      -r (-R)         Replace with the replacement character (#{Action::REPLACEMENT_CHARACTER_REPR})
      -C              Replace escaped chars with their "control pictures"
    #{BOLD_BEGIN}ESCAPE SHORTHANDS#{BOLD_END}
      -l / -w         Don't escape newlines / newlines, tabs, or spaces.
      -s / -S         Escape spaces by highlighting it / with "pictures".
      -B              Escape backslashes. (default unless colour or "ESCAPES" given)
      -m              Escape multibyte characters with their Unicode codepoint.
      -a              Escape _every_ character. (Must be used with an "ESCAPES")
    #{BOLD_BEGIN}INPUT DATA#{BOLD_END} (UTF-8 is default unless POSIXLY_CORRECT is set)
      -E encoding     Specify the (ASCII-compatible) encoding.
      -b / -A / -8    Shorthands for specifying encoding as BINARY / ASCII / UTF-8
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

  op.on '-f', '--[no-]files', 'Interpret trailing options as filenames to read, instead of as',
                              'literal strings.'  do |f|
    $files = f
  end

  ##################################################################################################
  #                                            Outputs                                             #
  ##################################################################################################
  op.section 'OUTPUTS & ERROR CHECKING'

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
      when 'auto'         then USE_COLOR
      else fail # Should never happen, as a list of valid options is given via `%w[...]`.
      end
  end

  # TODO: Should `--prefixes`, `--one-per-line`, and `--no-prefixes-or-newline` be collapsed?
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

  op.on '--[no-]malformed-error', 'Invalid chars in the --encoding cause exit status 2. (default)' do |me|
    $malformed_error = me
  end

  op.on '-c', '--[no-]check-escapes', 'Exits with status 1 if any character is escaped. Useful to',
                                      'check inputs programmatically to ensure they are "normal".' do |ee|
    $escape_error = ee
  end

  ##################################################################################################
  #                                        Specific Escapes                                        #
  ##################################################################################################

  op.section 'ESCAPES', '(Multiple may be specified; ties go to the last one specified)'

  op.on '--print=PATTERN', 'Print characters, verbatim, without escaping them' do |pattern|
    PatternAndAction.add_pattern_and_action(pattern, Action::PRINT)
  end

  op.on '--delete=PATTERN', 'Delete characters from the output' do |pattern|
    PatternAndAction.add_pattern_and_action(pattern, Action::DELETE)
  end

  op.on '--dot=PATTERN', 'Replaces characters by with a single period (`.`)' do |pattern|
    PatternAndAction.add_pattern_and_action(pattern, Action::DOT)
  end

  op.on '--replace=PATTERN', "Replaces characters with the replacement character (#{Action::REPLACEMENT_CHARACTER_REPR})" do |pattern|
    PatternAndAction.add_pattern_and_action(pattern, Action::REPLACE)
  end

  op.on '--hex=PATTERN', "Prints out a char's hex value (\\xHH)" do |pattern|
    PatternAndAction.add_pattern_and_action(pattern, Action::HEX)
  end

  op.on '--octal=PATTERN', "Prints out a char's octal value (\\###)" do |pattern|
    PatternAndAction.add_pattern_and_action(pattern, Action::OCTAL)
  end

  op.on '--picture=PATTERN', 'Print out "pictures" (U+240x-U+242x) for the character. Only',
                             'works for \x00-\x20 and \x7F; other chars yield a warning' do |pattern|
    PatternAndAction.add_pattern_and_action(pattern, Action::PICTURE)
  end

  op.on '--codepoint=PATTERN', 'Prints out UTF-8 codepoints (\u{...}). Only works with UTF-8'  do |pattern|
    # TODO: check if encoding is utf-8, and warn if it isn't
    PatternAndAction.add_pattern_and_action(pattern, Action::CODEPOINTS)
  end

  op.on '--highlight=PATTERN', 'Prints the character unchanged, but considers it "escaped"' do |pattern|
    PatternAndAction.add_pattern_and_action(pattern, Action::HIGHLIGHT)
  end

  op.on '--c-escape=PATTERN', "Use c-style escapes for #{Action::C_ESCAPES_MAP.map{ |key, _| key.inspect[1..-2].sub('u000', '') }.join}; others chars",
                              'will yield a warning.' do |pattern|
    PatternAndAction.add_pattern_and_action(pattern, Action::C_ESCAPES)
  end

  op.on '--default=PATTERN', 'Use the default patterns for chars in PATTERN' do |pattern|
    PatternAndAction.add_pattern_and_action(pattern, Action::DEFAULT)
  end

  op.on '--[no-]escape-surrounding-space', "Escape leading/trailing spaces in strings. Doesn't work with",
                                           "the --file option. [default]" do |ess|
    $escape_surronding_spaces = ess
  end

  op.on '-l', "Don't escape newlines. (Same as --print='\\n')" do
    PatternAndAction.add_pattern_and_action(/\n/, Action::PRINT)
  end

  op.on '-w', "Don't escape newline, tab, or space. (Same as --print='\\n\\t ')" do
    PatternAndAction.add_pattern_and_action(/[\n\t ]/, Action::PRINT)
  end

  op.on '-s', "Escape spaces with highlights. (Same as --highlight=' ')" do
    PatternAndAction.add_pattern_and_action(/ /, Action::HIGHLIGHT)
  end

  op.on '-S', "Escape spaces with a \"picture\". (Same as --picture=' ')" do
    PatternAndAction.add_pattern_and_action(/ /, Action::PICTURE)
  end

  op.on '-B', "Escape backslashes as '\\\\'. (Same as --c-escape='\\\\')",
              '[default when no --no-color, and no --default-action is given]' do |eb|
    PatternAndAction.add_pattern_and_action(/\\/, Action::C_ESCAPES)
  end

  op.on '-m', "Use codepoints for multibyte chars. (Same as --codepoint='\\m')",
                                        '(Not useful in single-byte-only encodings)' do
    PatternAndAction.add_pattern_and_action(Pattern::MULTIBYTE, Action::CODEPOINTS)
  end


  ##################################################################################################
  ##################################################################################################

  op.section 'DEFAULT ESCAPES', '(Performed if no ESCAPES match)'

  op.on '--default-pattern=PATTERN', 'Explicitly set the default pattern. [default: \x00-\x1F\x7F]' do |cs|
    Pattern.default_pattern = cs
  end


  op.on '--default-action=ACTION', :ACTION, "Set the default action that's used when no ESCAPES match.",
                                            '[default: default]' do |action|
    Action.default = action
  end

  op.on '--no-default-pattern', '--no-default-action', 'Specify either of these to disable the default functionality,',
                                                       'and to print verbatim any characters that dont match ESCAPES.' do
    # Technically we could also set `Action.default = Action::PRINT`; it doesn't really matter, as
    # "pattern that never matches" and "action that always prints" do the same thing.
    Pattern.default_pattern = nil
  end

  op.on '-p', 'Same as --default-action=print' do
    Action.default = Action::PRINT
  end

  op.on '-d', 'Same as --default-action=delete' do
    Action.default = Action::DELETE
  end

  op.on '-.', 'Same as --default-action=dot' do
    Action.default = Action::DOT
  end

  op.on '-r', 'Same as --default-action=replace' do
    Action.default = Action::REPLACE
  end

  op.on '-x', 'Same as --default-action=hex' do
    Action.default = Action::HEX
  end

  op.on '-o', 'Same as --default-action=octal' do
    Action.default = Action::OCTAL
  end

  op.on '-C', 'Same as --default-action=picture (`-C` b/c "control pic")' do
    Action.default = Action::PICTURE
  end

  op.on '-a', '--escape-all', "Same as --default-pattern='\\A'. (Does nothing on its own,",
                              'and should be combined with a --default-action=XXX flag.)' do
    Pattern.raw_default = Pattern::ALL
  end

  ##################################################################################################
  #                                            Escapes                                             #
  ##################################################################################################

  op.section 'INVALID BYTE ESCAPES', '(Performed on invalid bytes for the --encoding)'

  op.on '--invalid-action=ACTION', :ACTION, 'Specify the action to be used for invalid bytes. (Cannot',
                                            'specify `codepoints`, as it doesnt make sense) [default: hex]' do |action|
    raise OptionParser::InvalidArgument if action == Action::CODEPOINTS
    Action.error = action
  end

  op.on '-X', 'Same as --invalid-action=hex' do
    Action.error = Action::HEX
  end

  op.on '-O', 'Same as --invalid-action=octal' do
    Action.error = Action::OCTAL
  end

  op.on '-D', 'Same as --invalid-action=delete' do
    Action.error = Action::DELETE
  end

  op.on '-P', 'Same as --invalid-action=print' do
    Action.error = Action::PRINT
  end

  op.on '-@', 'Same as --invalid-action=dot' do
    Action.error = Action::DOT
  end

  op.on '-R', 'Same as --invalid-action=replace' do
    Action.error = Action::REPLACE
  end

  ##################################################################################################
  #                                        Specific Escapes                                        #
  ##################################################################################################
  op.section 'ENCODINGS'

  op.on '-E', '--encoding ENCODING', "Specify the input's encoding. Case-insensitive. Encodings that",
                                     "aren't ASCII-compatible encodings (eg UTF-16) are invalid." do |enc|
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

  op.on '-b', '--binary', '--bytes', 'Escapes high-bit bytes. (Same as --encoding=BINARY)' do
    $encoding = Encoding::BINARY
  end

  op.on '-A', '--ascii', 'Like -b, but high-bits are invalid. (Same as --encoding=ASCII)' do
    $encoding = Encoding::ASCII
  end

  op.on '-8', '--utf-8', 'Sets encoding to utf-8. (Same as --encoding=UTF-8). [default',
                         'when POSIXLY_CORRECT is not set]' do
    $encoding = Encoding::UTF_8
  end

  op.on '--locale', 'Chooses the encoding based on environment variables. (Same',
                    'as --encoding=locale.) [default when POSIXLY_CORRECT is set]' do
    $encoding = Encoding.find('locale') # Chooses based on `LC_ALL`, `LC_CTYPE`, and `LANG`, in that order
  end

=begin
  puts op.help; exit

  ##################################################################################################
  #                                        Environment Vars                                        #
  ##################################################################################################
  op.section 'ENVIRONMENT VARIABLES'
  op.on <<-'EOS' # Note: `-EOS` not `~EOS` to keep leading spaces
    FORCE_COLOR, NO_COLOR
      Controls `--color=auto`. If FORCE_COLOR is set and nonempty, acts like `--color=always`. Else,
      if NO_COLOR is set and nonempty, acts like `--color=never`. If neither is set to a non-empty
      value, `--color=auto` defaults to `--color=always` when stdout is a tty.

    POSIXLY_CORRECT
      If present, changes the default `--encoding` to be `locale` (cf locale(1).), and also
      disables parsing switches after arguments (e.g. passing in `foo -x` as arguments will not
      interpret `-x` as a switch).

    P_STANDOUT_BEGIN, P_STANDOUT_END
      Beginning and ending escape sequences for --colour; Usually don't need to be set, as they have
      sane defaults.

    P_STANDOUT_ERR_BEGIN, P_STANDOUT_ERR_END
      Like P_STANDOUT_BEGIN/P_STANDOUT_END, except for invalid bytes (eg 0xC3 in --utf-8)

    LC_ALL, LC_CTYPE, LANG
       Checked (in that order) for the encoding when --encoding=locale is used.
  EOS

  ##################################################################################################
  #                                      PATTERN Description                                       #
  ##################################################################################################

  op.section 'PATTERNS'
  op.on <<~'EOS'
    A 'PATTERN' is a regex character without the surrounding brackets (for example, --delete='^a-z' will
    only output lowercase letters.) In addition to normal escapes (eg '\n' for newlines, '\w' for "word"
    characters, etc), some other special sequences are accepted:
      - '\A' matches all chars (so `--print='\A'` would print out every character)
      - '\N' matches no chars  (so `--delete='\N'` would never delete a character)
      - '\m' matches multibyte characters (only useful if input data is multibyte like, UTF-8.)
      - '\M' matches all single-byte characters (i.e. anything \m doesn't match)
      - '\@' matches the pattern "ESCAPES" uses (so `--hex='\@'` is equivalent to `--escape-by-hex`)
    If more than pattern matches, the last one supplied on the command line wins.
  EOS

  op.section 'EXIT CODES'
  op.on <<~'EOS'
    Specific exit codes are used:
      - 0    No problems encountered
      - 1    A problem opening a file given with `-f`
      - 2    Command-line usage error
  EOS
=end


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
$quiet and $stdout = File.open(File::NULL, 'w')

PatternAndAction.build!

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

# Optimization: Early exit for `--malformed-error` and `--check-escapes` if we're in quiet mode.
if $quiet
  $malformed_error and trace_var :$ENCODING_FAILED do exit 1 end
  $escape_error    and trace_var :$SOMETHING_ESCAPED do exit 1 end
end

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

# Visualizes `string` by surrounding it with the colour escape sequences if colour mode is enabled.
# Also, sets the variable `$SOMETHING_ESCAPED` regardless of colour mode for `--check-escapes`.
if $use_color
  def visualize(string)
    $SOMETHING_ESCAPED = true
    "#$standout_begin#{string}#$standout_end"
  end
else
  def visualize(string)
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

      # Replace the global variables for just this invocation.
      begin
        $standout_begin = STANDOUT_ERR_BEGIN
        $standout_end   = STANDOUT_ERR_END
        Action.error.call key
      ensure
        $standout_begin = STANDOUT_BEGIN
        $standout_end = STANDOUT_END
      end
    else
      PatternAndAction.handle(key)
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
  puts if $prefixes && $files
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
  print BOLD_BEGIN, "==[#{filename}]==", BOLD_END, "\n" if $prefixes

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
