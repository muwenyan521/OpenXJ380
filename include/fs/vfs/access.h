#pragma once

#include <stdint.h>

#ifndef __cplusplus
#    ifndef bool
typedef enum
{
    false = 0,
    true  = 1,
} bool;
#    endif
#endif

enum {
    VFS_ACCESS_EXECUTE = 1,
    VFS_ACCESS_WRITE   = 2,
    VFS_ACCESS_READ    = 4,
};

static inline bool vfs_access_allowed(uint16_t mode, uint32_t owner, uint32_t group, uint32_t uid, uint32_t gid,
                                      uint8_t requested)
{
    if (uid == 0) return true;

    uint8_t granted;
    if (uid == owner)
        granted = (uint8_t)((mode >> 6) & 7);
    else if (gid == group)
        granted = (uint8_t)((mode >> 3) & 7);
    else
        granted = (uint8_t)(mode & 7);
    return (granted & requested) == requested;
}
