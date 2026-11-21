#pragma once

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
# define NORETURN _Noreturn
#else
# define NORETURN
#endif

void warn(const char *fmt, ...);

NORETURN void die2(int status, const char *fmt, ...);
#define die(...) die2(1, __VA_ARGS__)

#define todo(msg) die("%s:%s:%d: %s", __FILE__, __FUNCTION__, __LINE__, msg)
