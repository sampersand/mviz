#pragma once
#include "action.h"
#include "pattern.h"
#include <stdbool.h>


enum auto_option { AUTO_AUTO, AUTO_TRUE, AUTO_FALSE };

static inline bool
resolve_auto_option(enum auto_option aopt, bool default_value)
{
	return aopt == AUTO_TRUE || (aopt == AUTO_AUTO && default_value);
}

struct action_and_pattern {
	struct action action;
	struct pattern pattern;
};

struct options {
	enum { SOURCE_AUTO, SOURCE_FILES, SOURCE_STDIN, SOURCE_STRINGS } source;
	bool quiet;
	bool check_escapes;
	bool malformed_error;
	enum auto_option color;
	enum auto_option prefixes;
	enum auto_option trailing_newline;
	enum auto_option escape_surronding_spaces;

	struct action default_action;
	struct action invalid_action;

	struct action_and_pattern *ap;
	unsigned int nap;

	const char **args;
	unsigned nargs;
};

extern const char *program_name;
extern struct options options;

// Parses options out, then returns the remaining non-options (if any)
void parse_options(int argc, char **argv);
