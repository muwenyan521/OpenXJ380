#pragma once

#include <stdint.h>

#include "./settings.h"
#include "./password.h"

#define USER_REGISTRY_MAGIC    0x5552584aU
#define USER_REGISTRY_VERSION  2U
#define USER_REGISTRY_MAX_USERS 128U

typedef enum
{
    XUT_Root,
    XUT_System,
    XUT_Admin,
    XUT_Visitor,
    XUT_Custom
} UserType;

typedef struct
{
    bool ReadFile;       // 读取普通文件
    bool WriteFile;      // 写入普通文件
    bool ChangeSettings; // 更改系统设置
    bool VisitSysDir;    // 访问系统目录
    bool ReadSysFile;    // 读取系统文件
    bool WriteSysFile;   // 写入系统文件
} UserPermisson;

typedef struct
{
    char            name[64];   // 用户名
    UserType        user_type;  // 用户等级
    UserPermisson   user_prms;  // 用户权限（仅等级为Custom时可用）
    char          **envp;       // 环境变量指针
    size_t          envc;       // 环境变量数量
    int             fgproc;     // 前台进程
} UserInfo;

typedef struct
{
    char            name[64]; // 用户名
    UserType        user_type; // 用户等级
    UserPermisson   user_prms; // 用户权限（仅等级为Custom时可用）
    uint32_t        kdf_algorithm;
    uint32_t        kdf_iterations;
    uint8_t         salt[USER_PASSWORD_SALT_SIZE];
    uint8_t         verifier[USER_PASSWORD_VERIFIER_SIZE];
} UserRegistryEntry;

typedef struct
{
    uint32_t          magic;
    uint32_t          version;
    uint32_t          user_count; // 用户数量
    uint32_t          entry_size; // UserRegistryEntry 大小，便于后续版本迁移
    UserRegistryEntry uinf[USER_REGISTRY_MAX_USERS];  // 用户信息
} UserRegisterList;

void init_user();
void copy_args(char *dst[], char *src[], int n);
uint32_t user_uid(const UserInfo *user);
uint32_t user_gid(const UserInfo *user);
UserInfo *task_effective_user();
bool user_session_needs_oobe();
int user_session_list(UserInfo *out, int max_count);
int user_session_login(const char *username, const char *password);
int user_session_create_first(const char *username, const char *password);
void user_session_use_root();

extern UserInfo  root_user;
extern UserInfo *current_user;
