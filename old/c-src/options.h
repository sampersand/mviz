#pragma once
#include "action.h"
#include "pattern.h"
#include <stdbool.h>

enum auto_option { AUTO_AUTO, AUTO_TRUE, AUTO_FALSE };

struct action_and_pattern {
	struct action action;
	struct charclass charclass;
}

struct options {
	enum { SOURCE_AUTO, SOURCE_FILES, SOURCE_STDIN, SOURCE_STRINGS } source;
	bool quiet;
	bool check_escapes;
	bool malformed_error;
	auto_option color;
	auto_option prefixes;
	auto_option trailing_newline;
	auto_option escape_surronding_spaces;

	struct action default_action;
	struct action invalid_action;

	struct action_and_pattern *actions;
	unsigned int nactions;
};

extern char *program_name;
extern struct options options;

// Parses options out, then returns the remaining non-options (if any)
char **parse_options(int argc, char **argv);
