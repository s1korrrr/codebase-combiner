#ifndef SECURE_FILE_ACCESS_C_H
#define SECURE_FILE_ACCESS_C_H

#include <stddef.h>

int secure_file_descriptor_path(int descriptor, char *buffer, size_t buffer_size);

#endif
