#include "shared.h"
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>

extern char *program_name;

/**
 * Print an error message to stderr and exit, prefixing it with the program name
 **/
void
warn(const char *fmt, ...)
{

	fprintf(stderr, "%s: ", program_name);

	va_list vl;
	va_start(vl, fmt);
	vfprintf(stderr, fmt, vl);
	va_end(vl);

	fputc('\n', stderr);
}

/**
 * Print an error message to stderr and exit, prefixing it with the program name
 **/
NORETURN void
die2(int status, const char *fmt, ...)
{

	fprintf(stderr, "%s: ", program_name);

	va_list vl;
	va_start(vl, fmt);
	vfprintf(stderr, fmt, vl);
	va_end(vl);

	fputc('\n', stderr);
	fflush(stderr);

	exit(status);
}
