#include "rune.h"
#include <locale.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

#if 0
bool
decrypt_locale_rune(struct rune *r, const unsigned char *src)
{
    mbstate_t st = {0};
    wchar_t c;
    const char *p = s;
    size_t left = strlen(s);

    while (*p) {
        size_t r = mbrtoc32(&c, p, left, &st);
        if (r == (size_t)-1 || r == (size_t)-2)  /* invalid or incomplete sequence */
            break;
        printf("U+%04lX\n", (unsigned long)c);
        p += r;
        left -= r;
    }
    return 0;
    // TODO
}
#endif

bool
decrypt_utf8_rune(struct rune *r, const unsigned char *src)
{
	const unsigned char lead = src[0];
	uint32_t value;
	uint32_t min;
	unsigned char total;
	int extra;

	r->src = src;
	r->valid = false;
	r->codepoint = 0;
	r->len = 1;          /* invalid input consumes one byte, so the caller can resync */

	if (lead == '\0') {
		r->len = 0;      /* end of string; no rune to advance over */
		return false;
	}

	if (lead < 0x80) {                       /* 0xxxxxxx: ASCII */
		r->valid = true;
		r->codepoint = lead;
		return true;
	} else if ((lead & 0xE0) == 0xC0) {      /* 110xxxxx: 2 bytes */
		value = lead & 0x1F; extra = 1; min = 0x80;
	} else if ((lead & 0xF0) == 0xE0) {      /* 1110xxxx: 3 bytes */
		value = lead & 0x0F; extra = 2; min = 0x800;
	} else if ((lead & 0xF8) == 0xF0) {      /* 11110xxx: 4 bytes */
		value = lead & 0x07; extra = 3; min = 0x10000;
	} else {
		return true;                         /* cannot start a sequence */
	}

	for (int k = 1; k <= extra; k++) {
		const unsigned char c = src[k];
		if ((c & 0xC0) != 0x80)              /* also catches a NUL mid-sequence */
			return true;                     /* truncated: len stays 1 */
		value = (value << 6) | (c & 0x3F);
	}

	total = (unsigned char)(extra + 1);
	r->len = total;                          /* consumed bytes, even if rejected below */

	if (value < min)                         /* overlong encoding */
		return true;
	if (value >= 0xD800 && value <= 0xDFFF)  /* UTF-16 surrogate */
		return true;
	if (value > 0x10FFFF)                    /* beyond Unicode */
		return true;

	r->valid = true;
	r->codepoint = value;
	return true;
}

