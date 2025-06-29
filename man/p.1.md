% p(1) | General Commands Manual

NAME
====

p - visualize invisible and invalid bytes in different encodings.

SYNOPSIS
========
<!-- TODO: IS THERE A WAY TO GET this in three separate forms? -->
**p** [**options**] \
**p** [**options**] [_string_ _..._] \
**p** -f [**options**] [_file_ _..._]

DESCRIPTION
===========

**p** is an "escaper," converting bytes from their source representation to a more human-understandable one. There are many options to control which bytes are converted (which, by default, is invisible ASCII bytes, and invalid UTF-8) and also how the bytes are visualized.

**p** is designed with sane defaults, and most users don't need to muck around with the.

**p** normally works on a "default charset," which all the short-forms (eg `-x`) and value-less flags (eg `--hex`) work on by default. This charset can be changed with `--default-charset=CHARSET`, or disabled entirely with `--no-default-charset` (where only explicitly-selected options are used).

In addition to the default charset, options for specific ranges (eg `--delete=a-d`) may be specified; these take priority over the default, and are evaluated in a last-specified-first-evaluated order.

GENERIC OPTIONS
===============

**`-h`**, **`--help`**
:      Show the help message and exit. `-h` Shows a shorter help message.

**`--version`**
:      Print the version and exit.

**`-f`**, **`--files`**, **`--no-files`**
:      Interpret trailing options as filenames to read. Without this option, contrary to UNIX-philosophy, all arguments are interpreted as string literals, and are escaped as-is. (This is because by the most common use-case for `p` is to visualize strings, not files). The `--no-files` option disables an earlier `--files`, causing all arguments to be interpreted as string literals again.

**`--malformed-error`**, **`--no-malformed-error`**
: (Enabled by default.) Causes the program to exit with status code `1` if any invalid characters for the **ENCODING** are encountered. This will not abort the program prematurely, and simply changes the final status.

**`-c`**, **`--check-escapes`**, **`--no-check-escapes`**
: Causes the program to exit with status code `1` if *any* character is escaped. Note that the `--print` **ACTION** is not considered "escaping" a character.

**`-q`**, **`--quiet`**, **`--no-quiet`**
: Do not output anything. Useful with `--check-escapes` and `--malformed-error` to programmatically see if an input is "normal."

**`--color`**, **`--no-color`**, **`--color=`_auto/always/never_**
: Changes the visual effects, including both usage messages and "standouts" added to escaped characters. `--color` (and `--color=always`) enables them, `--no-color` (and `--color=never`) disables them, and `--color=auto` resets them to the default value.
: <br>
: The _auto_ color is done as follows: First, if `FORCE_COLOR` is present in the environment and non-empty, then colors are enabled. Second, if `NO_COLOR` is present in the environment and non-empty, then colors are disabled. Lastly, colors are enabled if stdout is a tty.

**`--prefixes`**
: (Defaults to enable if stdout is a tty, and any arguments are given.) Adds "prefixes" to arguments. For string arguments (ie without `--files`), this is their positional number (after all flags are removed). For files, this is a header containing the name of the file. Mutually exclusive with `--one-per-line` and `--no-prefixes-or-newline`.

**`-1`**, **`--one-per-line`**
: (Defaults when `--prefixes` isn't.) Print each argument on its own line.  Mutually exclusive with `--prefixes` and `--no-prefixes-or-newline`

**`-n`**, **`--no-prefixes-or-newline`**
: Disables prefixes, and separates arguments with spaces.

ESCAPES
====
Specify how characters should be escaped. Flags which optionally take a **CHARSET** set the default action if no charset is supplied. Actions with explicit charsets are checked first, and ties go to the last one specified. If no charset matches, the default one is used. Shorthand options are like the their corresponding long-form one, except they don't take an argument, and only work on the default charset.

If more than pattern matches, the last one supplied on the command line wins.

**`--default-charset`=_CHARSET_**
: Explicitly set the default charset that flags without **_CHARSET_** values use. The default value is `\x00-\x1F\x7F`, with an additional `\x80-\xFF` if the binary **ENCODING** is used. Additionally, if not using colors and using the default action, backslash (`\\`) is added to this charset list.

**`--no-default-charset`**
: Disables the default charset so that only **ESCAPES** woth explicit charsets are used.

**`--escape-surrounding-space`**, **`--no-escape-surrounding-space`**
: (Defaults to enabled) A convenience flag that doesn't really fit anywhere else: Unlike all the other escapes, this explicitly only works on leading and trailing spaces in strings, and only when the `--file` option is not given. This lets you visualize leading/trailing spaces in shell variables (eg `p "$foo"`)

**`-p`**, **`--print`**, **`--print=`_CHARSET_**
: Print characters, unchanged, without escaping them. Unlike the other actions, using `--print` will not mark values as "escaped" for the purposes of `--check-escapes`.

**`-d`**, **`--delete`**, **`--delete=`_CHARSET_**
: Delete characters from the output by not printing anything. Deleted characters are considered "escaped" for the purposes of `--check-escape`.

**`-.`**, **`--dot`**, **`--dot=`_CHARSET_**
: Replaces characters by simply printing a single period (`.`). (Note: Multibyte characters are still represented by a single period.)

**`-r`**, **`--replace`**, **`--replace=`_CHARSET_**
: Identical to `--dot`, except instead of a period, the replacement character (`\uFFFD`) is printed instead.

**`-x`**, **`--hex`**, **`--hex=`_CHARSET_**
: Replaces characters with their hex value (`\xHH`). Multibyte characters will have each of their bytes printed, in order they were received.

**`-o`**, **`--octal`**, **`--octal=`_CHARSET_**
: Like `--hex`, except octal escapes (`\###`) are used instead. The output is always padded to three bytes (so NUL is `\000`, not `\0`).

**`-C`**, **`--control-picture`**, **`--control-picture=`_CHARSET_**
: Print out "control pictures" (`U+240x`-`U+242x`) corresponding to the character. Note that only `\x00-\x20` and `\x7F` have control pictures assigned to them, and any other characters will yield a warning (and fall back to `--hex`).

**`--codepoint`**, **`--codepoint=`_CHARSET_**
: Replaces chars with their UTF-8 codepoints (`\u{...}`). This only works if the encoding is UTF-8. See also `--multibyte-codepoints`

**`--highlight`**, **`--highlight=`_CHARSET_**
: Prints the character unchanged, but considers it "escaped". (Thus, visual effects are added to it like any other escape, and `--check-escapes` considers it an escaped character.)

**`--c-escape`**, **`--c-escape=`_CHARSET_**
: Use c-style escapes for the following characters. (Any other characters will yield a warning, and fall back to `--hex`.): `\0\a\b\t\n\v\f\r\e\\`

**`--default`**, **`--default=`_CHARSET_**
: Use the default patterns for chars in **CHARSET**


MALFORMED ESCAPES
=====
Escapes for malformed bytes in the encoding. Like the "ESCAPES" section, except these apply to malformed bytes for the given encoding. Not all escape actions are possible, as some (eg codepoints) dont make sense. The shorthand flags are just upper cases of their equivalent normal-escape forms.

**`-X`**, **`--invalid-hex`**
: Like `-x`, but only for illegal bytes in the encoding.

**`-O`**, **`--invalid-octal`**
: Like `-o`, but only for illegal bytes in the encoding.

**`-D`**, **`--invalid-delete`**
: Like `-d`, but only for illegal bytes in the encoding.

**`-P`**, **`--invalid-print`**
: Like `-p`, but only for illegal bytes in the encoding.

**`-@`**, **`--invalid-dot`**
: Like `-.`, but only for illegal bytes in the encoding.

**`-R`**, **`--invalid-replace`**
: Like `-r`, but only for illegal bytes in the encoding.

SHORTHANDS
==========

**`-l`**, **`--print-newlines`**
: Don't escape newlines. (Same as \--print='\n')

**`-w`**, **`--print-whitespace`**
: Don't escape newline, tab, or space. (Same as \--print='\n\t ')

**`-s`**, **`--highlight-space`**
: Escape spaces with highlights. (Same as \--highlight=' ')

**`-S`**, **`--control-picture-space`**
: Escape spaces with a "picture". (Same as \--control-picture=' ')

**`-B`**, **`--escape-backslashes`**
: Escape backslashes as '\\'. (Same as \--c-escape='\\') (Default if not in colour mode, and no \--escape-by was given)

**`-m`**, **`--multibyte-codepoints`**
: Use codepoints for multibyte chars. (Same as \--codepoint='\m'). (Not useful in single-byte-only encodings)

**`-a`**, **`--escape-all`**
: Mark all characters as escaped. (Same as \--escape-charset='\A') Does nothing alone; it needs to be used with an "ESCAPES" flag


ENCODINGS
=========
(default is normally `--utf-8`. If POSIXLY_CORRECT is set, `--locale` is the default)


**`-E` _ENCODING_**, **`--encoding=`_ENCODING_**
: Specify the input's encoding, which is case-insensitive. The encoding must be ASCII-compatible; encodings which aren't (eg UTF-16) yield a fatal error. See `--list-encodings` for a list of encodings that can be specified.

**`--list-encodings`**
: List all possible encodings, and exit with status 0.

**`-b`**, **`--binary`**, **`--bytes`**
: Same as `--encoding=binary`. This encoding considers all bytes "valid," and specifying it changes the `--default-charset` to also escape all high-bit bytes (ie `\x80-\xFF`).

**`-A`**, **`--ascii`**
: Same as `--encoding=ASCII`. Like `--binary`/`--bytes`, but but high-bits are considered "invalid".

**`-8`**, **`--utf-8`**
: Same as `--encoding=UTF-8`. The default, unless the environment variable variable _POSIXLY_CORRECT_ is set.

**`--locale`**
: Same as `--encoding=locale`. This chooses the encoding based on the environment variables _LC_ALL_, _LC_CTYPE_, and _LANG_ (in that order). If the encoding is not valid, or none of the variables are present, `US-ASCII` is used as a default.

ENVIRONMENT
======
The following environment variables affect the execution of `p`:

`FORCE_COLOR, NO_COLOR`
: Controls `--color=auto`. If FORCE_COLOR is set and nonempty, acts like `--color=always`. Else, if NO_COLOR is set and nonempty, acts like `--color=never`. If neither is set to a non-empty value, `--color=auto` defaults to `--color=always` when stdout is a tty.

`POSIXLY_CORRECT`
: If present, changes the default `--encoding` to be `locale` (cf locale(1).), and also disables parsing switches after arguments (e.g. passing in `foo -x` as arguments will not interpret `-x` as a switch).

`P_STANDOUT_BEGIN`, `P_STANDOUT_END`
: Beginning and ending escape sequences for \--color; Usually don't need to be set, as they have sane defaults.

`P_STANDOUT_ERR_BEGIN`, `P_STANDOUT_ERR_END`
: Like P_STANDOUT_BEGIN/P_STANDOUT_END, except for invalid bytes (eg 0xC3 in \--utf-8)

`LC_ALL, LC_CTYPE, LANG`
: Checked (in that order) for the encoding when \--encoding=locale is used.

CHARSETS
========
A "_CHARSET_" is a way to specify a range of characters. They're based off Regular Expression character classes, with a few additional options escapes available in addition to the regular escapes (eg `\n` to escape a newline, or `\w` for "word" characters). To use these escapes they must be the _entire_ regex (so eg `^\E` doesn't work):

  - `\A` matches all chars (so `--print='\A'` would print out every character)
  - `\N` matches no chars  (so `--delete='\N'` would never delete a character)
  - `\m` matches multibyte characters (only useful if input data is multibyte like, UTF-8.)
  - `\M` matches all single-byte characters (i.e. anything \m doesn't match)
  - `\E` matches the "default charset" (see `--default-charset`) (so `--hex='\E'` is equivalent to `--hex`.)

(Under the hood, the character classes use ruby's regular expression engine, and so anything that's valid)


EXIT STATUS
===========
Specific exit codes are used:

  - 0    No problems encountered
  - 1    A problem opening a file given with `-f`
  - 2    Command-line usage error


BUGS
====

Bugs can be reported and filed at https://github.com/sampersand/p/

If you are not using the flatpak version of p, or if you are using an otherwise out of date or downstream version of it, please make sure that the bug you want to report hasn't been already fixed or otherwise caused by a downstream patch.
