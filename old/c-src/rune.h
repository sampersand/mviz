#pragma once

#include <stddef.h> // size_t
#include <stdint.h> // uint32_t
#include <stdbool.h>

typedef uint32_t char_codepoint;

struct rune
{
	const unsigned char *src; // pointer into the source of the rune; not owned.
	unsigned char len;        // the length of the rune, 1..4
	bool valid;               // whether it's a valid codepoint.
	char_codepoint codepoint;       // codepoint, only if it's valid
};

/**
 * Decrypts the next rune stored in `src`, and returns it.
 * Returns whether there's anything left.
 * Increment `src` by `r->len` to get the next value.
 */
bool decrypt_locale_rune(struct rune *r, const unsigned char *src);

/**
 * Decrypts the next rune stored in `src`, and returns it.
 * Returns whether there's anything left.
 * Increment `src` by `r->len` to get the next value.
 */
bool decrypt_utf8_rune(struct rune *r, const unsigned char *src);

