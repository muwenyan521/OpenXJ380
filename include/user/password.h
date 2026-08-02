#pragma once

#include <stdint.h>

typedef __SIZE_TYPE__ user_password_size_t;

#ifndef __cplusplus
#    ifndef bool
typedef enum
{
    false = 0,
    true  = 1,
} bool;
#    endif
#endif

#define USER_PASSWORD_INPUT_MAX       64U
#define USER_PASSWORD_SALT_SIZE       16U
#define USER_PASSWORD_VERIFIER_SIZE   32U
#define USER_PASSWORD_KDF_PBKDF2_SHA256 1U
#define USER_PASSWORD_KDF_ITERATIONS  4096U

void user_password_fill_salt(uint8_t salt[USER_PASSWORD_SALT_SIZE]);
void user_password_make_verifier(const char *password, const uint8_t salt[USER_PASSWORD_SALT_SIZE],
                                 uint32_t iterations,
                                 uint8_t verifier[USER_PASSWORD_VERIFIER_SIZE]);
bool user_password_verify(const char *password, const uint8_t salt[USER_PASSWORD_SALT_SIZE],
                          uint32_t iterations,
                          const uint8_t verifier[USER_PASSWORD_VERIFIER_SIZE]);
bool user_password_constant_time_equal(const uint8_t *a, const uint8_t *b, user_password_size_t size);
void user_password_clear(void *buffer, user_password_size_t size);
