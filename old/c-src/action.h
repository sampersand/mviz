#pragma once
#include "rune.h"

enum action_type
{
	ACTION_DEFAULT,
	ACTION_PRINT,
	ACTION_DELETE,
	ACTION_DOT,
	ACTION_REPLACE,
	ACTION_HEX,
	ACTION_OCTAL,
	ACTION_CODEPOINTS,
	ACTION_HIGHLIGHT,
	ACTION_C_ESCAPES,
	ACTION_PICTURE,
};

struct action
{
	enum action_type type;

	union {
		char *replacement;
	};
};

void action_fn_default(const struct action *, struct rune);
void action_fn_print(const struct action *, struct rune);
void action_fn_delete(const struct action *, struct rune);
void action_fn_dot(const struct action *, struct rune);
void action_fn_replace(const struct action *, struct rune);
void action_fn_hex(const struct action *, struct rune);
void action_fn_octal(const struct action *, struct rune);
void action_fn_codepoints(const struct action *, struct rune);
void action_fn_highlight(const struct action *, struct rune);
void action_fn_c_escapes(const struct action *, struct rune);
void action_fn_picture(const struct action *, struct rune);

