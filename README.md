# The `p` command
A program to print out invisible characters in strings or files.

# "Impetus" example usages:
(i.e. the usages that inspired this command)
```shell
$ p "$variable"      # See the contents of `$variable`
$ p $variable        # See how `$variable` word splits
$ p *                # See what files are expanded by a glob
$ some_command | p   # escape characters that `some_command` outputs
$ p -f some-file.txt # print out `some-file.txt`
```

Try `p --help` for usage

## Why not use tool X (`xxd`, `hexdmp`, `vis`, `od`, etc)?
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

% printf 'hello\x04world, how are you? \xC3👍\n' | vis
hello\^Dworld, how are you? \M-C\M-p\M^_\M^Q\M^M

% printf 'hello\x04world, how are you? \xC3👍\n' | od
0000000    062550  066154  002157  067567  066162  026144  064040  073557
0000020    060440  062562  074440  072557  020077  170303  110637  005215
0000040
```
