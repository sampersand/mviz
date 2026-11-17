#include "color.h"
#include "options.h"
#include "rune.h"
#include "action.h"
#include <stdlib.h>
#include <stdio.h>
#include <locale.h>

struct action *actions;

int main(int argc, char **argv)
{
	color_init();
	actions = malloc(sizeof(struct action) * argc);

	parse_options(argc, argv);

	(void) argc;

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
