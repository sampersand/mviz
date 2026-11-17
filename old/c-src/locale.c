#include "locale.h"

#include <stdio.h>
#include <stdint.h>

/* Decodes one code point starting at s[*i].
   On success, stores it in *cp, advances *i, and returns 1.
   On failure, leaves *i unchanged and returns 0. */
