# The `p` command
A program to visualize invisible and invalid bytes in different encodings.

`p` is essentially a replacement for interactive use of `echo` or `cat`: Instead of `echo "$variable"` or `cat file.txt`, which (on most terminals) hide invisible characters (like `\x01`), you instead do `p "$variable"` or `p -f file.txt`.

# Examples
`p` is designed with sensible defaults in mind; its default behaviour is what you want most of the time, but it can easily (and sensibly) be changed with options

```sh
$ p "$variable"        # See the contents of a shell variable
$ p -d "$variable"     # Delete weird characters from the variable
$ p -f file.txt        # Print file.txt, escaping "weird" characters
$ p -fw file.txt       # Like the previous line, but newlines and tabs aren't escaped.
$ some_command | p     # Visualize weird characters of `some_command`
$ some_command | p -l  # Like the previous one, but don't escape newlines.
$ some_command | p -b  # Interpret input data as binary, not UTF-8 (the default)
```

It's also quite useful when you're learning how shells work:
```bash
# See what files are expanded by a glob
$ p [A-Z]*
    1: LICENSE
    2: README.md
# See how `$variable` word splits
$ variable='hello    world,   :-)'
$ p $variable
    1: hello
    2: world,
    3: :-)
# See how `$IFS` affects it
$ IFS=o
$ p $variable
    1: hell
    2:     w
    3: rld,   :-)
```

Try `p -h` for short usage, and `p --help` for the longer one.

# Why not use tool X (`xxd`, `hexdmp`, `vis`, `od`, etc)?
The biggest difference between `p` and other tools is that `p` is intended for looking at mostly-normal text by default, and optimizes for that. It doesn't change the output _unless_ weird characters exist. For example:
```bash
% printf 'hello\x04world, how are you? \xC3👍\n' | p
hello\x04world, how are you? \xC3👍\n

% printf 'hello\x04world, how are you? \xC3👍\n' | xxd
00000000: 6865 6c6c 6f04 776f 726c 642c 2068 6f77  hello.world, how
00000010: 2061 7265 2079 6f75 3f20 c3f0 9f91 8d0a   are you? ......

% printf 'hello\x04world, how are you? \xC3👍\n' | hexdump -C
00000000  68 65 6c 6c 6f 04 77 6f  72 6c 64 2c 20 68 6f 77  |hello.world, how|
00000010  20 61 72 65 20 79 6f 75  3f 20 c3 f0 9f 91 8d 0a  | are you? ......|
00000020

% printf 'hello\x04world, how are you? \xC3👍\n' | od -c
0000000    h   e   l   l   o 004   w   o   r   l   d   ,       h   o   w
0000020        a   r   e       y   o   u   ?     303  👍  **  **  **  \n
0000040

% printf 'hello\x04world, how are you? \xC3👍\n' | vis
hello\^Dworld, how are you? \M-C\M-p\M^_\M^Q\M^M

% printf 'hello\x04world, how are you? \xC3👍\n' | cat -v
hello^Dworld, how are you? ??M-^_M-^QM-^M
```

In addition, `p` by default adds a "standout marker" to escaped characters (by default, it inverts the foreground and background colours), so they're more easily distinguished at a glance.

# How it works
The way `p` works at a high-level is pretty easy: Every character in an input is checked against the list of patterns, and the first one that matches is used. If no patterns match, the character is checked against the "default pattern," and if that doesn't match, the character is printed verbatim.

To simplify the most common use-case of `p`, where only the "escaping mechanism" (called an "Action"; see below) is changed, a lot of short-hand flags (such as `-x`, `-d`, etc.) are provided to just change the default action.

`p` is broken into three configurable parts: The encoding of the input data, the "patterns" to match against the input data, and the action to take when a pattern matches. They're described in more details below:

## Encodings
The encoding (which can be specified via `--encoding`, and are case-insensitive) is used to determine which input bytes are valid, and which are invalid.

Valid bytes (which differ between encodings, see below) are then matched against patterns as described in `How it works`. However, "invalid bytes" (for example `\xC3` in UTF-8) are handled specially:

By default, these bytes have their hex values printed out (but this can be changed, e.g. with `--invalid-action=delete`), along with a different "standout" pattern than normal escapes (by default, a red background). If any invalid bytes are encountered during an execution, and `--malformed-error` is set (which it is by default), the program will exit with a non-zero exit code at the end.

You can get a list of all the supported encodings via `--list-encodings`. Non-ASCII-compliant encodings, such as `UTF-16`, aren't supported (as they drastically complicate character matching logic).

The "binary" encoding (which can be specified either with `--encoding=binary` or the `-b` / `--binary` / `--bytes` shorthands) is unique in that it doesn't have any "invalid bytes."

Unless explicitly specified (either via `--encoding`, or one of the shorthands like `-b`), the encoding normally defaults to `UTF-8`. However, if the environment variable `POSIXLY_CORRECT` is set, it defaults to the "locale" encoding, which relies on the environment variables `LC_ALL`, `LC_CTYPE`, and `LANG` (in that order) to specify it.

## Patterns
Patterns are a sets of characters (internally using regular expression character classes—`[a-z]`) that are used to match against input characters. In addition to specifying "normal" escape sequences (eg `\n` for newlines, `\xHH` for hex escapes, and `\u{HHHH}` for Unicode codepoints, `\w` for "word characters", etc), patterns also support the following custom escape sequences:

- `\A` matches all characters
- `\N` matches no characters
- `\m` matches multibyte characters (and is only useful if the input encoding is multibyte, like UTF-8)
- `\M` matches single-byte characters (ie anything `\m` doesn't match)
- `\@` matches the "default pattern" (see below)

Patterns are normally used when specifying actions directly (eg `p --delete=^a-z` will only output lower-case letters).

### Default Pattern
The default pattern is the pattern that is checked _after_ all "user-specified patterns." If it matches, the "default action" takes place (which are controlled by shorthands like `-x`, `-o`, etc.) acts upon.

Normally, the default pattern is just `\x00-\x1F\x7F`—that is, all of the "weird" bytes in ASCII. However, there's a few ways it can be changed:
1. It can be explicitly set via `--default-pattern=PATTERN`, at which point that's exactly what'll be used.
2. If encoding is `BINARY`, the bytes `\x80-\xFF` are also added, as the binary encoding considers all bytes to be valid.
3. If the default action is unchanged, and visual effects aren't be used, then backslash (`\`) is added to the default pattern. This way, it'll be escaped when "standout features" aren't in use.

## Actions
Actions are how characters are escaped. There's a lot of them, and they can be used either as arguments to flags (eg `--invalid-action=octal`) or specified explicitly (eg via `--highlight=a-z`):

| name | value |
|------|-------|
| `print` | Print characters, unchanged, without escaping them. Unlike the other actions, using `print` will not mark values as "escaped" for the purposes of `--check-escapes` |
| `delete` | Delete characters from the output by not printing anything. Deleted characters are considered "escaped" for the purposes of `--check-escape` |
| `dot` | Replaces characters by simply printing a single period (`.`). (Note: Multibyte characters are still represented by a single period.) |
| `replace` | Identical to --dot, except instead of a period, the replacement character (\uFFFD) is printed instead. |
| `hex` | Replaces characters with their hex value (\xHH). Multibyte characters will have each of their bytes printed, in order they were received. |
| `octal` | Like --hex, except octal escapes (\###) are used instead. The output is always padded to three bytes (so NUL is \000, not \0) |
| `control-picture` | Print out "control pictures" (U+240x-U+242x) corresponding to the character. Note that only \x00-\x20 and \x7F have control pictures assigned to them, and any other characters will yield a warning (and fall back to --hex). |
| `codepoint` | Replaces chars with their UTF-8 codepoints (\u{...}). This only works if the encoding is UTF-8. See also --multibyte-codepoints |
| `highlight` | Prints the character unchanged, but considers it "escaped". (Thus, visual effects are added to it like any other escape, and --check-escapes considers it an escaped character.) |
| `c-escape` | Use c-style escapes for the following characters. (Any other characters will yield a warning, and fall back to --hex.): \0\a\b\t\n\v\f\r\e\\ |
| `default` | Use the default patterns for chars in CHARSET |


(Note that it also changes the "default pattern" (see below) to include bytes `0x80-0xFF`, as those are normally considered "invalid".)

<!--     A 'CHARSET' is a regex character without the surrounding brackets (for example, --delete='^a-z' will
    only output lowercase letters.) In addition to normal escapes (eg '\n' for newlines, '\w' for "word"
    characters, etc), some other special sequences are accepted:
      - '\A' matches all chars (so `--print='\A'` would print out every character)
      - '\N' matches no chars  (so `--delete='\N'` would never delete a character)
      - '\m' matches multibyte characters (only useful if input data is multibyte like, UTF-8.)
      - '\M' matches all single-byte characters (i.e. anything \m doesn't match)
      - '\@' matches the charset "ESCAPES" uses (so `--hex='\@'` is equivalent to `--escape-by-hex`)
    If more than pattern matches, the last one supplied on the command line wins.

 -->

# Encodings
The way `p` works at a high-level is pretty easy: Every character in an input is checked against the list of patterns, where the
. If it matches, the first escape that matches is used. Otherwise, the char is printed verbatim. In list form:


# How it works
1. Is the byte/character illegal in the given encoding (eg byte `0xC3` in UTF-8)? If so, print the escape.


# Charsets

<!--

## TODO
- Should I add an `--highlight-means-error` flag (name subject to bikeshed)? I.e. if there's _any_ form of highlights, return an error. (done)
- Should make `-l` not `--unescape='\n'` but instead act like `/\R/` (ie platform-indep line sep)?
- `p -ax` makes everything hex, except for spaces and backslashes. should we do this?
- MAke `escape-options.txt` the actual escape options that are used. E.g., right now, it's not possible to have spaces escaped as `\x20`, but still have utf-8 chars escaped as `\u`

## Character class
- There's a 

Oops:
```sh
print '\xC3👍' | p --escape='\u{1F44D}' --escape='\xC3'
```
This isn't great, cause regexes can't be one or the other. so i have to figure out what to do...

You can also `LC_ALL=en_US-iso8859-1"

# HOW ESCAPES WORK
If a character is to be escaped, it goes through the following steps:
1. If `--delete` is given, nothing is printed
2. If `--dot` is given, a `.` is used


---
allenc=( $(i --list-encodings | awk '{$1=$2=""; print}' | tr ',' '\n' | tr -d ' ') )
 -->

# TODO
- `--no-prefixes-or-newline` and co: fix their names and update associated documentatoin
