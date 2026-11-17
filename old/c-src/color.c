#include "color.h"
#include <stdio.h>
#include <stdlib.h>

#ifdef _WIN32
# include <io.h>
# define IS_STDOUT_A_TTY() _isatty(_fileno(stdout))
#else
# include <unistd.h>
# define IS_STDOUT_A_TTY() isatty(STDOUT_FILENO)
#endif

#define ENV_PREFIX "P_"

const char *standout_begin;
const char *standout_end;
const char *standout_err_begin;
const char *standout_err_end;
const char *bold_begin;
const char *bold_end;

bool color_enabled;

void
visualize_start(void)
{
	if (color_enabled) fputs(standout_begin, stdout);
}

void
visualize_end(void)
{
	if (color_enabled) fputs(standout_end, stdout);
}

static const char *
getenv_or(const char *name, const char *fallback)
{
	char *tmp = getenv(name);
	return tmp ? tmp : fallback;
}

void
color_init(void)
{
	standout_begin     = getenv_or(ENV_PREFIX "STANDOUT_BEGIN", "\e[7m");
	standout_end       = getenv_or(ENV_PREFIX "STANDOUT_END",   "\e[27m");
	standout_err_begin = getenv_or(ENV_PREFIX "STANDOUT_ERR_BEGIN", "\e[37m\e[41m");
	standout_err_end   = getenv_or(ENV_PREFIX "STANDOUT_ERR_END",   "\e[49m\e[39m");
	bold_begin         = getenv_or(ENV_PREFIX "BOLD_BEGIN", "\e[1m");
	bold_end           = getenv_or(ENV_PREFIX "BOLD_END",   "\e[0m");

	const char *tmp;
	if (*(tmp = getenv_or("FORCE_COLOR", "")) != '\0') {
		color_enabled = true;
	} else if (*(tmp = getenv_or("NO_COLOR", "")) != '\0') {
		color_enabled = false;
	} else {
		color_enabled = IS_STDOUT_A_TTY();
	}
}
