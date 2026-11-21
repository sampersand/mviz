#include "pattern.h"
#include <stdlib.h>

int
parse_pattern(struct pattern *pat, const char *source)
{
	pat->ccs = malloc(sizeof(struct charclass) * 1);
	pat->nccs = 1;
	pat->ccs[0].negated = true;
	pat->ccs[0].nranges = 1;
	pat->ccs[0].ranges = malloc(sizeof(struct range) * 1);
	pat->ccs[0].ranges[0].lo = 'a';
	pat->ccs[0].ranges[0].hi = 'z';
	return 0;
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

bool
pattern_match(const struct pattern *pat, char_codepoint cp)
{
	// TODO: do we need a pattern struct?
	return class_match(&pat->ccs[0], cp);
}
