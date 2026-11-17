#include "options.h"
#include "shared.h"
#include <stdio.h>

char *program_name;
struct options options;

char **
parse_options(int argc, char **argv)
{
	(void) argc;
	program_name = argv[0];
	argv++;

	while (*argv != NULL) {
		char *arg = *argv;

		// If it's not a flag, then we're done
		if (arg[0] != '-')
			goto done;

		switch (*arg++) {
		// If it's just a `-`, that's also end.
		case '\0':
			goto done;
		case 'h':
			die("todo");

		case 'f':
			die("todo");
		}
		arg++;
		if (arg[0] == '\0')
			break;

		// For `--`, that's end but first reduce argv
		if (arg[0] == '-' && arg[1] == '\0') {
			argv++;
			break;
		}

		if (arg[0] == '-' && arg[1] == '-') goto long_option;


	long_option:
		die("todo");
		argc--;
		argv++;
	}

done:
	options.params = argv;
}

