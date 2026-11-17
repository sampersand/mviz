#pragma once

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
# define NORETURN _Noreturn
#else
# define NORETURN
#endif

void warn(const char *fmt, ...);

NORETURN void die2(int status, const char *fmt, ...);
#define die(...) die2(1, __VA_ARGS__)
