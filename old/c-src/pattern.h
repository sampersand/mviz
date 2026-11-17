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

bool parse_charclass(struct charclass *cc, const char *source);
bool class_match(const struct charclass *cc, char_codepoint cp);
