#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include "utils.h"

#define COLOR_RESET  "\033[0m"
#define COLOR_INFO   "\033[1;34m"
#define COLOR_ERROR  "\033[1;31m"

void log_info(const char *fmt, ...) {
    if (!fmt) return;
    
    fprintf(stdout, "%s[info]%s ", COLOR_INFO, COLOR_RESET);
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    printf("\n");
    fflush(stdout);
}

void log_error(const char *fmt, ...) {
    if (!fmt) return;
    
    fprintf(stderr, "%s[error]%s ", COLOR_ERROR, COLOR_RESET);
    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);
    fprintf(stderr, "\n");
    fflush(stderr);
}

char *read_file(const char *path) {
    if (!path) return NULL;
    
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return NULL;
    }
    
    long length = ftell(f);
    if (length < 0 || length > 100 * 1024 * 1024) { // 100MB limit
        fclose(f);
        return NULL;
    }
    
    if (fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return NULL;
    }
    
    char *buffer = malloc((size_t)length + 1);
    if (!buffer) {
        fclose(f);
        return NULL;
    }
    
    size_t read_len = fread(buffer, 1, (size_t)length, f);
    fclose(f);
    
    if (read_len != (size_t)length) {
        free(buffer);
        return NULL;
    }
    
    buffer[length] = '\0';
    return buffer;
}

int write_file(const char *path, const char *content) {
    if (!path || !content) return 0;
    
    FILE *f = fopen(path, "w");
    if (!f) {
        log_error("Failed to open '%s' for writing: %s", path, strerror(errno));
        return 0;
    }
    
    size_t len = strlen(content);
    size_t written = fwrite(content, 1, len, f);
    
    if (fclose(f) != 0 || written != len) {
        return 0;
    }
    
    return 1;
}
