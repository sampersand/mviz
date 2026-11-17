#include "action.h"
#include "color.h"
#include <stdio.h>
#include "shared.h"

// void action_fn_default(const struct action *a, struct rune r) {
// 	// todo
// }

void
action_fn_print(const struct action *a, struct rune r)
{
	(void) a;
	fwrite(r.src, sizeof(unsigned char), r.len, stdout);
}

void
action_fn_delete(const struct action *a, struct rune r)
{
	(void) a;
	(void) r;
	// Do nothing
}

void
action_fn_replace(const struct action *a, struct rune r)
{
	(void) r;

	visualize_start();
	fputs(a->replacement, stdout);
	visualize_end();
}

void
action_fn_hex(const struct action *a, struct rune r)
{
	(void) a;

	visualize_start();
	for (unsigned char c = 0; c < r.len; ++c)
		printf("\\x%02X", r.src[c]);
	visualize_end();
}

void
action_fn_octal(const struct action *a, struct rune r)
{
	(void) a;

	visualize_start();
	for (unsigned char c = 0; c < r.len; ++c)
		printf("\\%03o", r.src[c]);
	visualize_end();
}

void
action_fn_codepoints(const struct action *a, struct rune r)
{
	(void) a;

	visualize_start();
	printf("\\u{%04X}", r.codepoint);
	visualize_end();
}

void
action_fn_highlight(const struct action *a, struct rune r)
{
	visualize_start();
	action_fn_print(a, r);
	visualize_end();
}

void
action_fn_c_escapes(const struct action *a, struct rune r)
{
	static const char codepoints[256] = {
	    ['\0'] = '0',
		['\a'] = 'a',
		['\b'] = 'b',
		['\t'] = 't',
		['\n'] = 'n',
	    ['\v'] = 'v',
		['\f'] = 'f',
		['\r'] = 'r',
		['\e'] = 'e',
		['\\'] = '\\'
	};

	if (r.len != 1) {
		die("oops"); // this is a bug, `c escapes` should only be used with length 1
	}

	char escaped = codepoints[r.src[0]];
	if (escaped == 0) {
		return action_fn_hex(a, r);
	}

	visualize_start();
	putchar('\\');
	putchar(escaped);
	visualize_end();
}

void
action_fn_picture(const struct action *a, struct rune r)
{
	if (r.len != 1) {
		warn("character doesnt have a picture, falling back on hex.");
		return action_fn_hex(a, r);
	}

	char c = r.src[0];

	if (c <= '\x1F') {
		visualize_start();
        putchar(0xE2);
        putchar(0x90);
        putchar(0x80 + c);
		visualize_end();
	} else if (c == '\x7F') {
		visualize_start();
        putchar(0xE2);
        putchar(0x90);
        putchar(0xA1);
		visualize_end();
	} else if (c == ' ') {
		visualize_start();
        putchar(0xE2);
        putchar(0x90);
        putchar(0xA3);
		visualize_end();
	} else {
		warn("character does not have a picture, falling back on hex.");
		return action_fn_hex(a, r);
	}
}

