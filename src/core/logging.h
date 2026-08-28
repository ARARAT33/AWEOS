#ifndef AWEOS_LOGGING_H
#define AWEOS_LOGGING_H

#include <stdio.h>
#include <stdarg.h>

typedef enum {
    LOG_LEVEL_DEBUG = 0,
    LOG_LEVEL_INFO,
    LOG_LEVEL_WARN,
    LOG_LEVEL_ERROR
} aweos_log_level_t;

void aweos_log_set_file(const char *filepath);
void aweos_log(aweos_log_level_t level, const char *fmt, ...);

#define LOGD(fmt, ...) aweos_log(LOG_LEVEL_DEBUG, fmt, ##__VA_ARGS__)
#define LOGI(fmt, ...) aweos_log(LOG_LEVEL_INFO, fmt, ##__VA_ARGS__)
#define LOGW(fmt, ...) aweos_log(LOG_LEVEL_WARN, fmt, ##__VA_ARGS__)
#define LOGE(fmt, ...) aweos_log(LOG_LEVEL_ERROR, fmt, ##__VA_ARGS__)

#endif /* AWEOS_LOGGING_H */
