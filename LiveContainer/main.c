#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

void* lcShared = 0;

int LiveContainerMainC(int argc, char *argv[], char *envp[]) {
    const char *home = getenv("HOME");

    int (*lcMain)(int argc, char *argv[], char *envp[]) = 0;
    
    if (!home) {
        abort();
    }
    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/Library/preloadLibraries.txt", home);
    FILE *file = fopen(path, "r");
    if (!file) {
        goto loadlc;
    }
    char line[PATH_MAX];
    // Only allow tweaks from the app's own Tweaks dir or app-group container
    char tweaksDir[PATH_MAX], groupDir[PATH_MAX];
    snprintf(tweaksDir, sizeof(tweaksDir), "%s/Tweaks/", home);
    snprintf(groupDir, sizeof(groupDir), "%s/Library/Group Containers/", home);
    while (fgets(line, sizeof(line), file)) {
        // Remove trailing newline if present
        size_t len = strlen(line);
        if (len > 0 && line[len - 1] == '\n') {
            line[len - 1] = '\0';
        }
        char resolved[PATH_MAX];
        if (!realpath(line, resolved)) continue;
        if (strncmp(resolved, tweaksDir, strlen(tweaksDir)) != 0 &&
            strncmp(resolved, groupDir, strlen(groupDir)) != 0) continue;
        if (strstr(resolved, "..") != NULL) continue;
        dlopen(resolved, RTLD_LAZY|RTLD_GLOBAL);
    }
    
    fclose(file);
    remove(path);
    
loadlc:
    lcShared = dlopen("@executable_path/Frameworks/LiveContainerShared.framework/LiveContainerShared", RTLD_LAZY|RTLD_GLOBAL);
    lcMain = dlsym(lcShared, "LiveContainerMain");
    __attribute__((musttail)) return lcMain(argc, argv, envp);
}

#ifdef DEBUG
int main(int argc, char *argv[], char *envp[]) {

    if(lcShared == NULL) {
        __attribute__((musttail)) return LiveContainerMainC(argc, argv, envp);
    }
    int (*callAppMain)(int argc, char *argv[], char *envp[]) = dlsym(lcShared, "callAppMain");
    __attribute__((musttail)) return callAppMain(argc, argv, envp);

}
#endif
