# The `p` command
A program to escape "weird" characters in strings or files.

`p` is essentially a replacement for interactive use of `echo` or `cat`: Instead of `echo "$variable"` or `cat file.txt`, which would be hiding invisible characters (like `\x01`), instead do `p "$variable"` or `p -f file.txt`.

# Examples
`p` is designed with defaults in mind; its default behaviour is what you want most of the time, but can easily (and sensibly) be changed with options

```shell
$ p "$variable"        # See the contents of a shell variable
$ p -d "$variable"     # Delete weird characters from the variable
$ p -f some-file.txt   # Print some-file, escaping all characters
$ p -fw some-file.txt  # Like the previous line, but newlines and tabs aren't escaped.
$ some_command | p     # Visualize weird chars of `some_command`
$ some_command | p -l  # Like the previous one, but don't escape newlines.
$ some_command | p -b  # Interpret input data as binary, not utf-8 (the default)
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
The biggest difference between `p` and other tools is that `p` is intended for looking at text (not binary data) by default, and optimizes for that. (It doesn't change the output _unless_ weird characters exist.) For example:
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

# Details

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
