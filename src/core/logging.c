#include "logging.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>

static FILE *log_file = NULL;

void aweos_log_set_file(const char *filepath) {
    if (log_file && log_file != stdout && log_file != stderr) {
        fclose(log_file);
        log_file = NULL;
    }
    if (filepath) {
        log_file = fopen(filepath, "a");
    }
}

void aweos_log(aweos_log_level_t level, const char *fmt, ...) {
    const char *level_str = "INFO";
    switch (level) {
        case LOG_LEVEL_DEBUG: level_str = "DEBUG"; break;
        case LOG_LEVEL_INFO:  level_str = "INFO";  break;
        case LOG_LEVEL_WARN:  level_str = "WARN";  break;
        case LOG_LEVEL_ERROR: level_str = "ERROR"; break;
    }

    time_t t = time(NULL);
    struct tm *tm_info = localtime(&t);
    char time_buf[26];
    if (tm_info) {
        strftime(time_buf, sizeof(time_buf), "%Y-%m-%d %H:%M:%S", tm_info);
    } else {
        snprintf(time_buf, sizeof(time_buf), "0000-00-00 00:00:00");
    }

    va_list args;
    va_start(args, fmt);
    fprintf(stderr, "[%s] [%s] ", time_buf, level_str);
    vfprintf(stderr, fmt, args);
    fprintf(stderr, "\n");
    va_end(args);

    if (log_file) {
        va_start(args, fmt);
        fprintf(log_file, "[%s] [%s] ", time_buf, level_str);
        vfprintf(log_file, fmt, args);
        fprintf(log_file, "\n");
        fflush(log_file);
        va_end(args);
    }
}
