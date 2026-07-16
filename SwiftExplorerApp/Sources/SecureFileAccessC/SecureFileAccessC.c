#include "SecureFileAccessC.h"

#include <errno.h>
#include <sys/fcntl.h>
#include <sys/param.h>

int secure_file_descriptor_path(int descriptor, char *buffer, size_t buffer_size) {
    if (buffer == NULL || buffer_size < MAXPATHLEN) {
        errno = EINVAL;
        return -1;
    }
    return fcntl(descriptor, F_GETPATH, buffer);
}
