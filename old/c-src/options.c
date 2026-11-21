#include "options.h"
#include "color.h"
#include "shared.h"
#include <stdio.h>
#include <string.h>

const char *program_name;
struct options options;

void
parse_options(int argc, char **argv)
{
	const char **orig_argv = (const char **)argv;
	if (argc == 0) {
		program_name = "p";
		return;
	}

	program_name = argv[0];
	argv++;

	// Parse each option out
	for (; *argv != NULL; ++argv) {
		const char *arg = *argv;

		// If it's not a flag, then we're done parsing options.
		if (arg[0] != '-')
			break;

		arg++; // go past the `-` to figure out what's next
		char opt = *arg;

		if (opt == '\0') break; // just a `-`, that's a normal arg
		if (opt == '-' && arg[1] == '\0') { // that's `--`, incr arg and stop
			argv++;
			break;
		}

	reparse:
		// otherwise, let's see what short option we just got
		switch (opt) {
		case 'h':
			die("todo1");
		case 'f':
			die("todo2");
		default:
			die("todo arg");
		case '-':
			arg++;
			if (!strcmp(arg, "color")) {
				color_enabled = true;
				continue;
			} else if (!strcmp(arg, "no-color")) {
				color_enabled = false;
				continue;
			}
			;
		}
	}

done:
	options.args = (const char **) argv;
	options.nargs = options.args - orig_argv;
}

