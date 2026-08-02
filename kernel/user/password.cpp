#include <fs/vfs/vfs.h>
#include <krlibc.h>
#include <proto.hpp>
#include <user/password.h>

typedef struct
{
    uint32_t state[8];
    uint64_t bit_count;
    uint8_t  buffer[64];
} Sha256Context;

static const uint32_t kSha256InitialState[8] = {
    0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU,
    0x510e527fU, 0x9b05688cU, 0x1f83d9abU, 0x5be0cd19U,
};

static const uint32_t kSha256RoundConstants[64] = {
    0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU, 0x59f111f1U, 0x923f82a4U,
    0xab1c5ed5U, 0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U, 0x72be5d74U, 0x80deb1feU,
    0x9bdc06a7U, 0xc19bf174U, 0xe49b69c1U, 0xefbe4786U, 0x0fc19dc6U, 0x240ca1ccU, 0x2de92c6fU,
    0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU, 0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U,
    0xc6e00bf3U, 0xd5a79147U, 0x06ca6351U, 0x14292967U, 0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU,
    0x53380d13U, 0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U, 0xa2bfe8a1U, 0xa81a664bU,
    0xc24b8b70U, 0xc76c51a3U, 0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U, 0x19a4c116U,
    0x1e376c08U, 0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU, 0x5b9cca4fU, 0x682e6ff3U,
    0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U, 0x90befffaU, 0xa4506cebU, 0xbef9a3f7U,
    0xc67178f2U,
};

static uint32_t sha256_rotr(uint32_t value, uint32_t bits)
{
    return (value >> bits) | (value << (32U - bits));
}

static uint32_t sha256_load_be32(const uint8_t *input)
{
    return ((uint32_t)input[0] << 24U) | ((uint32_t)input[1] << 16U) |
           ((uint32_t)input[2] << 8U) | (uint32_t)input[3];
}

static void sha256_store_be32(uint8_t *output, uint32_t value)
{
    output[0] = (uint8_t)(value >> 24U);
    output[1] = (uint8_t)(value >> 16U);
    output[2] = (uint8_t)(value >> 8U);
    output[3] = (uint8_t)value;
}

static void sha256_transform(Sha256Context *ctx, const uint8_t block[64])
{
    uint32_t w[64];
    for (int i = 0; i < 16; i++)
        w[i] = sha256_load_be32(block + (size_t)i * 4U);
    for (int i = 16; i < 64; i++)
    {
        uint32_t s0 = sha256_rotr(w[i - 15], 7) ^ sha256_rotr(w[i - 15], 18) ^ (w[i - 15] >> 3U);
        uint32_t s1 = sha256_rotr(w[i - 2], 17) ^ sha256_rotr(w[i - 2], 19) ^ (w[i - 2] >> 10U);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }

    uint32_t a = ctx->state[0];
    uint32_t b = ctx->state[1];
    uint32_t c = ctx->state[2];
    uint32_t d = ctx->state[3];
    uint32_t e = ctx->state[4];
    uint32_t f = ctx->state[5];
    uint32_t g = ctx->state[6];
    uint32_t h = ctx->state[7];
    for (int i = 0; i < 64; i++)
    {
        uint32_t s1 = sha256_rotr(e, 6) ^ sha256_rotr(e, 11) ^ sha256_rotr(e, 25);
        uint32_t ch = (e & f) ^ ((~e) & g);
        uint32_t temp1 = h + s1 + ch + kSha256RoundConstants[i] + w[i];
        uint32_t s0 = sha256_rotr(a, 2) ^ sha256_rotr(a, 13) ^ sha256_rotr(a, 22);
        uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
        uint32_t temp2 = s0 + maj;
        h = g;
        g = f;
        f = e;
        e = d + temp1;
        d = c;
        c = b;
        b = a;
        a = temp1 + temp2;
    }
    ctx->state[0] += a;
    ctx->state[1] += b;
    ctx->state[2] += c;
    ctx->state[3] += d;
    ctx->state[4] += e;
    ctx->state[5] += f;
    ctx->state[6] += g;
    ctx->state[7] += h;
    user_password_clear(w, sizeof(w));
}

static void sha256_init(Sha256Context *ctx)
{
    memcpy(ctx->state, kSha256InitialState, sizeof(ctx->state));
    ctx->bit_count = 0;
    memset(ctx->buffer, 0, sizeof(ctx->buffer));
}

static void sha256_update(Sha256Context *ctx, const uint8_t *input, size_t length)
{
    if (length == 0) return;

    size_t used = (size_t)((ctx->bit_count >> 3U) & 63U);
    ctx->bit_count += (uint64_t)length << 3U;
    if (used != 0)
    {
        size_t available = 64U - used;
        if (length < available)
        {
            memcpy(ctx->buffer + used, input, length);
            return;
        }
        memcpy(ctx->buffer + used, input, available);
        sha256_transform(ctx, ctx->buffer);
        input += available;
        length -= available;
    }

    while (length >= 64U)
    {
        sha256_transform(ctx, input);
        input += 64U;
        length -= 64U;
    }
    if (length != 0) memcpy(ctx->buffer, input, length);
}

static void sha256_final(Sha256Context *ctx, uint8_t output[USER_PASSWORD_VERIFIER_SIZE])
{
    uint64_t bit_count = ctx->bit_count;
    size_t used = (size_t)((bit_count >> 3U) & 63U);
    ctx->buffer[used++] = 0x80U;
    if (used > 56U)
    {
        memset(ctx->buffer + used, 0, 64U - used);
        sha256_transform(ctx, ctx->buffer);
        used = 0;
    }
    memset(ctx->buffer + used, 0, 56U - used);
    for (int i = 0; i < 8; i++)
        ctx->buffer[56 + i] = (uint8_t)(bit_count >> (56U - (uint32_t)i * 8U));
    sha256_transform(ctx, ctx->buffer);
    for (int i = 0; i < 8; i++)
        sha256_store_be32(output + (size_t)i * 4U, ctx->state[i]);
    user_password_clear(ctx, sizeof(*ctx));
}

static void hmac_sha256(const uint8_t *key, size_t key_length, const uint8_t *data0, size_t data0_length,
                        const uint8_t *data1, size_t data1_length,
                        uint8_t output[USER_PASSWORD_VERIFIER_SIZE])
{
    uint8_t key_block[64];
    uint8_t inner_hash[USER_PASSWORD_VERIFIER_SIZE];
    memset(key_block, 0, sizeof(key_block));
    if (key_length > sizeof(key_block))
    {
        Sha256Context hash_ctx;
        sha256_init(&hash_ctx);
        sha256_update(&hash_ctx, key, key_length);
        sha256_final(&hash_ctx, key_block);
    }
    else if (key_length != 0)
    {
        memcpy(key_block, key, key_length);
    }

    uint8_t ipad[64];
    uint8_t opad[64];
    for (size_t i = 0; i < sizeof(key_block); i++)
    {
        ipad[i] = key_block[i] ^ 0x36U;
        opad[i] = key_block[i] ^ 0x5cU;
    }

    Sha256Context ctx;
    sha256_init(&ctx);
    sha256_update(&ctx, ipad, sizeof(ipad));
    sha256_update(&ctx, data0, data0_length);
    sha256_update(&ctx, data1, data1_length);
    sha256_final(&ctx, inner_hash);

    sha256_init(&ctx);
    sha256_update(&ctx, opad, sizeof(opad));
    sha256_update(&ctx, inner_hash, sizeof(inner_hash));
    sha256_final(&ctx, output);

    user_password_clear(key_block, sizeof(key_block));
    user_password_clear(inner_hash, sizeof(inner_hash));
    user_password_clear(ipad, sizeof(ipad));
    user_password_clear(opad, sizeof(opad));
}

void user_password_make_verifier(const char *password, const uint8_t salt[USER_PASSWORD_SALT_SIZE],
                                 uint32_t iterations,
                                 uint8_t verifier[USER_PASSWORD_VERIFIER_SIZE])
{
    uint8_t block_index[4] = {0, 0, 0, 1};
    uint8_t u[USER_PASSWORD_VERIFIER_SIZE];
    uint8_t next[USER_PASSWORD_VERIFIER_SIZE];
    if (iterations == 0) iterations = USER_PASSWORD_KDF_ITERATIONS;

    hmac_sha256((const uint8_t *)password, strlen(password), salt, USER_PASSWORD_SALT_SIZE,
                block_index, sizeof(block_index), u);
    memcpy(verifier, u, USER_PASSWORD_VERIFIER_SIZE);
    for (uint32_t round = 1; round < iterations; round++)
    {
        hmac_sha256((const uint8_t *)password, strlen(password), u, sizeof(u), NULL, 0, next);
        for (size_t i = 0; i < USER_PASSWORD_VERIFIER_SIZE; i++)
        {
            verifier[i] ^= next[i];
            u[i] = next[i];
        }
    }
    user_password_clear(u, sizeof(u));
    user_password_clear(next, sizeof(next));
    user_password_clear(block_index, sizeof(block_index));
}

bool user_password_verify(const char *password, const uint8_t salt[USER_PASSWORD_SALT_SIZE],
                          uint32_t iterations,
                          const uint8_t verifier[USER_PASSWORD_VERIFIER_SIZE])
{
    uint8_t candidate[USER_PASSWORD_VERIFIER_SIZE];
    user_password_make_verifier(password, salt, iterations, candidate);
    bool ok = user_password_constant_time_equal(candidate, verifier, USER_PASSWORD_VERIFIER_SIZE);
    user_password_clear(candidate, sizeof(candidate));
    return ok;
}

bool user_password_constant_time_equal(const uint8_t *a, const uint8_t *b, size_t size)
{
    if (a == NULL || b == NULL) return false;
    uint8_t diff = 0;
    for (size_t i = 0; i < size; i++)
        diff |= (uint8_t)(a[i] ^ b[i]);
    return diff == 0;
}

void user_password_clear(void *buffer, size_t size)
{
    volatile uint8_t *p = (volatile uint8_t *)buffer;
    while (size-- != 0)
        *p++ = 0;
}

void user_password_fill_salt(uint8_t salt[USER_PASSWORD_SALT_SIZE])
{
    memset(salt, 0, USER_PASSWORD_SALT_SIZE);
    vfs_node_t random = vfs_open("/dev/urandom");
    if (random != NULL)
    {
        size_t read = vfs_read(random, salt, 0, USER_PASSWORD_SALT_SIZE);
        vfs_close(random);
        if (read == USER_PASSWORD_SALT_SIZE) return;
    }

    uint64_t state = nanoTime() ^ (uint64_t)(uintptr_t)salt ^ 0x9e3779b97f4a7c15ULL;
    for (size_t i = 0; i < USER_PASSWORD_SALT_SIZE; i++)
    {
        state ^= state >> 12U;
        state ^= state << 25U;
        state ^= state >> 27U;
        salt[i] = (uint8_t)((state * 0x2545f4914f6cdd1dULL) >> 56U);
    }
}
