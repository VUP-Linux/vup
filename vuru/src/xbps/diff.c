#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <errno.h>
#include <ctype.h>
#include "diff.h"
#include "common.h"

#define TEMPLATE_URL_BASE "https://raw.githubusercontent.com/VUP-Linux/vup/main/vup/srcpkgs"

/**
 * Validate identifier (package name, category) for safe path construction.
 */
static int is_valid_identifier(const char *s) {
    if (!s || s[0] == '\0' || s[0] == '.') return 0;
    
    for (const char *p = s; *p; p++) {
        char c = *p;
        if (!((c >= 'a' && c <= 'z') ||
              (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') ||
              c == '-' || c == '_' || c == '.')) {
            return 0;
        }
    }
    
    if (strstr(s, "..") != NULL) return 0;
    
    return 1;
}

/**
 * Run a command using fork/exec.
 * Returns exit status, or -1 on error.
 */
static int run_command(char *const argv[]) {
    pid_t pid = fork();
    
    if (pid < 0) {
        log_error("fork() failed: %s", strerror(errno));
        return -1;
    }
    
    if (pid == 0) {
        execvp(argv[0], argv);
        _exit(127);
    }
    
    int status;
    if (waitpid(pid, &status, 0) == -1) {
        return -1;
    }
    
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    
    return -1;
}

/**
 * Get tmpdir path.
 */
static const char *get_tmpdir(void) {
    const char *tmpdir = getenv("TMPDIR");
    if (!tmpdir || tmpdir[0] != '/') {
        tmpdir = "/tmp";
    }
    return tmpdir;
}

int diff_create_temp_file(const char *prefix, char *out_path, size_t path_size) {
    const char *tmpdir = get_tmpdir();
    
    int ret = snprintf(out_path, path_size, "%s/%s_XXXXXX", tmpdir, prefix);
    if (ret < 0 || (size_t)ret >= path_size) {
        return -1;
    }
    
    return mkstemp(out_path);
}

int diff_write_temp_file(const char *content, char *path_out, size_t path_size) {
    const char *tmpdir = get_tmpdir();
    
    int ret = snprintf(path_out, path_size, "%s/vuru_diff_XXXXXX", tmpdir);
    if (ret < 0 || (size_t)ret >= path_size) {
        return -1;
    }
    
    int fd = mkstemp(path_out);
    if (fd < 0) return -1;
    
    size_t len = strlen(content);
    ssize_t written = write(fd, content, len);
    close(fd);
    
    return (written == (ssize_t)len) ? 0 : -1;
}

char *diff_generate(const char *old_content, const char *new_content) {
    if (!new_content) return NULL;
    
    char old_path[256] = {0};
    char new_path[256] = {0};
    
    if (old_content) {
        if (diff_write_temp_file(old_content, old_path, sizeof(old_path)) != 0) {
            return NULL;
        }
    }
    
    if (diff_write_temp_file(new_content, new_path, sizeof(new_path)) != 0) {
        if (old_path[0]) unlink(old_path);
        return NULL;
    }
    
    // Build command - use colored diff
    char cmd[512];
    if (old_content) {
        snprintf(cmd, sizeof(cmd), "diff -u --color=always '%s' '%s' 2>/dev/null", 
                 old_path, new_path);
    } else {
        // No old content, just show the new file
        snprintf(cmd, sizeof(cmd), "cat '%s'", new_path);
    }
    
    FILE *fp = popen(cmd, "r");
    if (!fp) {
        if (old_path[0]) unlink(old_path);
        unlink(new_path);
        return NULL;
    }
    
    // Read diff output
    size_t cap = 4096;
    size_t len = 0;
    char *output = malloc(cap);
    if (!output) {
        pclose(fp);
        if (old_path[0]) unlink(old_path);
        unlink(new_path);
        return NULL;
    }
    
    char buf[1024];
    while (fgets(buf, sizeof(buf), fp)) {
        size_t blen = strlen(buf);
        if (len + blen + 1 > cap) {
            cap *= 2;
            char *tmp = realloc(output, cap);
            if (!tmp) {
                free(output);
                pclose(fp);
                if (old_path[0]) unlink(old_path);
                unlink(new_path);
                return NULL;
            }
            output = tmp;
        }
        memcpy(output + len, buf, blen);
        len += blen;
    }
    output[len] = '\0';
    
    pclose(fp);
    if (old_path[0]) unlink(old_path);
    unlink(new_path);
    
    return output;
}

void diff_show_pager(const char *path) {
    char *less_args[] = { "less", "-R", (char *)path, NULL };
    run_command(less_args);
}

char *fetch_template(const char *category, const char *pkg_name) {
    if (!is_valid_identifier(category) || !is_valid_identifier(pkg_name)) {
        log_error("Invalid category or package name");
        return NULL;
    }

    char url[1024];
    int ret = snprintf(url, sizeof(url), 
             "%s/%s/%s/template",
             TEMPLATE_URL_BASE, category, pkg_name);
    if (ret < 0 || (size_t)ret >= sizeof(url)) {
        log_error("URL too long");
        return NULL;
    }

    char tmp_path[512];
    char prefix[128];
    snprintf(prefix, sizeof(prefix), "vuru_tmpl_%s", pkg_name);
    
    int fd = diff_create_temp_file(prefix, tmp_path, sizeof(tmp_path));
    if (fd == -1) {
        log_error("Failed to create temp file: %s", strerror(errno));
        return NULL;
    }
    close(fd);

    char *curl_args[] = {
        "curl", "-s", "-f", "-L", "-o", tmp_path, url, NULL
    };
    
    int status = run_command(curl_args);
    if (status != 0) {
        log_error("Failed to fetch template from %s", url);
        unlink(tmp_path);
        return NULL;
    }

    char *content = read_file(tmp_path);
    unlink(tmp_path);
    return content;
}

int review_changes(const char *pkg_name, const char *current, const char *previous) {
    if (!pkg_name || !current) {
        return 0;
    }
    
    if (!is_valid_identifier(pkg_name)) {
        log_error("Invalid package name");
        return 0;
    }

    if (previous && strcmp(current, previous) == 0) {
        log_info("Template for %s unchanged since last install.", pkg_name);
    } else {
        char review_path[256];
        
        if (previous) {
            // Generate colored diff and show in pager
            char *diff_output = diff_generate(previous, current);
            if (diff_output) {
                if (diff_write_temp_file(diff_output, review_path, sizeof(review_path)) == 0) {
                    printf("\nTemplate for %s has changed:\n", pkg_name);
                    diff_show_pager(review_path);
                    unlink(review_path);
                }
                free(diff_output);
            }
        } else {
            // New package - show full template in pager
            printf("\nNew package %s. Review template:\n", pkg_name);
            if (diff_write_temp_file(current, review_path, sizeof(review_path)) == 0) {
                diff_show_pager(review_path);
                unlink(review_path);
            }
        }
    }

    printf("Proceed with installation? [Y/n] ");
    fflush(stdout);
    
    char input[100];
    if (fgets(input, sizeof(input), stdin)) {
        input[strcspn(input, "\n")] = '\0';
        
        if (input[0] == '\0' || 
            strcasecmp(input, "y") == 0 || 
            strcasecmp(input, "yes") == 0) {
            return 1;
        }
    }
    
    return 0;
}
