#pragma once
#include <stdbool.h>

extern bool color_enabled;

void color_init(void);
void visualize(const char *seq);

void visualize_start(void);
void visualize_end(void);

