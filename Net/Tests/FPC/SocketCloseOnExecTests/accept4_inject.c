/* 仅用于 x86_64 glibc Linux 回归，不进入生产构建。 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <unistd.h>

static _Atomic int calls;

int socket_test_accept4_calls(void) { return atomic_load(&calls); }

int accept4(int fd, struct sockaddr *addr, socklen_t *len, int flags) {
    atomic_fetch_add(&calls, 1);
    const char *error = getenv("SOCKET_TEST_ACCEPT4_ERRNO");
    if (error) { errno = atoi(error); return -1; }
    return syscall(SYS_accept4, fd, addr, len, flags);
}

void *dlsym(void *handle, const char *name) {
    void *(*real_dlsym)(void *, const char *) = dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.2.5");
    if (getenv("SOCKET_TEST_MISSING") && strcmp(name, "accept4") == 0) return NULL;
    return real_dlsym(handle, name);
}

void *dlopen(const char *name, int flags) {
    void *(*real_dlopen)(const char *, int) = dlvsym(RTLD_NEXT, "dlopen", "GLIBC_2.2.5");
    if (!name && getenv("SOCKET_TEST_LOAD_FAIL")) return NULL;
    return real_dlopen(name, flags);
}
