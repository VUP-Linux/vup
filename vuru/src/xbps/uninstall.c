#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include <errno.h>
#include "uninstall.h"
#include "../utils.h"

int xbps_uninstall(const char *pkg_name, int yes) {
    if (!pkg_name || pkg_name[0] == '\0') {
        log_error("Invalid package name");
        return -1;
    }

    log_info("Removing %s...", pkg_name);
    
    pid_t pid = fork();
    
    if (pid < 0) {
        log_error("fork() failed: %s", strerror(errno));
        return -1;
    }
    
    if (pid == 0) {
        if (yes) {
            execlp("sudo", "sudo", "xbps-remove", "-R", "-y", pkg_name, (char *)NULL);
        } else {
            execlp("sudo", "sudo", "xbps-remove", "-R", pkg_name, (char *)NULL);
        }
        _exit(127);
    }
    
    int status;
    if (waitpid(pid, &status, 0) == -1) {
        log_error("waitpid() failed: %s", strerror(errno));
        return -1;
    }
    
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        log_info("Successfully removed %s", pkg_name);
        return 0;
    }
    
    log_error("xbps-remove failed for %s", pkg_name);
    return -1;
}
