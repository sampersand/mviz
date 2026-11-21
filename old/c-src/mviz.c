#include "color.h"
#include "options.h"
#include "pattern.h"
#include "rune.h"
#include "action.h"
#include <stdlib.h>
#include <stdio.h>
#include <locale.h>
#include "shared.h"

void
perform_on_strings(size_t nstrings, const unsigned char **strings)
{
	bool print_prefixes = resolve_auto_option(options.prefixes, nstrings != 0);

	if (print_prefixes)
		printf("%zu argument%s:\n", nstrings, nstrings == 1 ? "" : "s");

	for (size_t i = 0; i < nstrings; ++i) {
		struct rune r;
		const unsigned char *str = strings[i];

		while (decrypt_utf8_rune(&r, str)) {
			str += r.len;
			for (unsigned i = 0; i < options.nap; i++) {
				if (pattern_match(&options.ap[i].pattern, r.codepoint)) {
					perform_action(&options.ap[i].action, r);
					goto next;
				}
			}

			perform_action(&options.default_action, r);
		next:
		}
	}

}

int main(int argc, char **argv)
{
	color_init();
	options.default_action.fn = action_fn_print;
	parse_options(argc, argv);

	options.ap = malloc(sizeof(struct action_and_pattern) * 1);
	options.nap = 1;
	options.ap[0] = (struct action_and_pattern) {
		.action = (struct action) {
			.fn = action_fn_hex,
		}
	};
	parse_pattern(&options.ap[0].pattern, "^a-z");

	(void) argc;

	if (!options.args || !*options.args)  todo("no-args");
	if (options.source != SOURCE_AUTO)  todo("non-auto src");

	perform_on_strings(size_t nstrings, const unsigned char **strings)

	for (const char **ptr = options.args; *ptr; ++ptr) {
		struct rune r;
		const unsigned char *str = (const unsigned char *) *ptr;

		while (decrypt_utf8_rune(&r, str)) {
			str += r.len;
			for (unsigned i = 0; i < options.nap; i++) {
				if (pattern_match(&options.ap[i].pattern, r.codepoint)) {
					perform_action(&options.ap[i].action, r);
					goto next;
				}
			}

			perform_action(&options.default_action, r);
		next:
		}
	}
	puts("");

#if 0
    setlocale(LC_ALL, "C.UTF-8");
    setlocale(LC_ALL, "C");
	// const char *s = "A é € \xFE 𝄞";        /* 1, 2, 3, and 4-byte characters */
	const char *s = "\n\r\x7F\0";        /* 1, 2, 3, and 4-byte characters */
	size_t offset = 0;
	if (argc == 2) s = argv[1];
	struct rune r;

	while (decrypt_utf8_rune(&r, (const unsigned char *)s)) {
		// printf("src[%zu] = %.*s %d (U+%04X): '", offset, r.len, r.src, r.valid, r.codepoint);
		s += r.len;
		offset += r.len;
		struct action a = {.type = ACTION_HEX};
		action_fn_hex(&a, r);
		// puts("'");
	}
#endif

	return 0;
}
