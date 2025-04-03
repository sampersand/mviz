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
