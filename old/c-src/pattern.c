#include "pattern.h"

bool
parse_charclass(struct charclass *cc, const char *source)
{
	// TODO
	return true;
}

bool
class_match(const struct charclass *cc, char_codepoint cp)
{
	bool in = false;
	for (size_t i = 0; i < cc->nranges && !in; ++i) {
		in = cp >= cc->ranges[i].lo && cp <= cc->ranges[i].hi;
	}
	return in != cc->negated;
}
