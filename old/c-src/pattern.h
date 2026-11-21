#pragma once
#include "rune.h"

struct range {
	char_codepoint lo, hi;
};

struct charclass {
	bool negated;
	size_t nranges;
	struct range *ranges;
};

struct pattern {
	struct charclass *ccs;
	int nccs;
};

// parses a pattern, returns non-zero if there's an error
int parse_pattern(struct pattern *pat, const char *source);

// returns true if the pattern matches
bool pattern_match(const struct pattern *pat, char_codepoint cp);
