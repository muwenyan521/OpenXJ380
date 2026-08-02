from __future__ import annotations

import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class SecurityBaselineTests(unittest.TestCase):
    def _compile_and_run(self, source: str, *sources: str) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            source_path = Path(tmp) / "test.c"
            binary_path = Path(tmp) / "test"
            source_path.write_text(textwrap.dedent(source), encoding="utf-8")
            subprocess.run(
                [
                    "cc",
                    "-std=gnu11",
                    "-Wall",
                    "-Wextra",
                    "-Werror",
                    "-fno-builtin",
                    "-I",
                    str(ROOT / "boot" / "include"),
                    "-I",
                    str(ROOT / "include"),
                    str(source_path),
                    *(str(ROOT / source) for source in sources),
                    "-o",
                    str(binary_path),
                ],
                check=True,
            )
            subprocess.run([str(binary_path)], check=True)

    def test_boot_elf_validation_rejects_malformed_images(self) -> None:
        self._compile_and_run(
            r"""
            #include <elf.h>

            int main(void)
            {
                unsigned char image[sizeof(Elf64_Ehdr) + sizeof(Elf64_Phdr)] = {0};
                Elf64_Ehdr *ehdr = (Elf64_Ehdr *)image;
                Elf64_Phdr *phdr = (Elf64_Phdr *)(image + sizeof(Elf64_Ehdr));
                UINT64 first = 0;
                UINT64 last = 0;

                ehdr->e_ident[0] = 0x7f;
                ehdr->e_ident[1] = 'E';
                ehdr->e_ident[2] = 'L';
                ehdr->e_ident[3] = 'F';
                ehdr->e_ident[4] = 2;
                ehdr->e_ident[5] = 1;
                ehdr->e_type = 2;
                ehdr->e_machine = 62;
                ehdr->e_version = 1;
                ehdr->e_ehsize = sizeof(Elf64_Ehdr);
                ehdr->e_phoff = sizeof(Elf64_Ehdr);
                ehdr->e_phentsize = sizeof(Elf64_Phdr);
                ehdr->e_phnum = 1;
                ehdr->e_entry = 0x100000;
                phdr->p_type = PT_LOAD;
                phdr->p_offset = 0;
                phdr->p_vaddr = 0x100000;
                phdr->p_filesz = 1;
                phdr->p_memsz = 1;

                if (!ValidateElf64Image(image, sizeof(image), 0x100000, 0x200000, &first, &last)) return 1;
                if (first != 0x100000 || last != 0x100001) return 2;

                ehdr->e_ident[0] = 0;
                if (ValidateElf64Image(image, sizeof(image), 0x100000, 0x200000, &first, &last)) return 3;
                ehdr->e_ident[0] = 0x7f;

                phdr->p_filesz = 2;
                phdr->p_memsz = 1;
                if (ValidateElf64Image(image, sizeof(image), 0x100000, 0x200000, &first, &last)) return 4;
                phdr->p_filesz = 1;
                phdr->p_memsz = 1;

                phdr->p_offset = sizeof(image);
                if (ValidateElf64Image(image, sizeof(image), 0x100000, 0x200000, &first, &last)) return 5;
                phdr->p_offset = 0;

                ehdr->e_phoff = sizeof(image);
                if (ValidateElf64Image(image, sizeof(image), 0x100000, 0x200000, &first, &last)) return 6;
                return 0;
            }
            """
        )

    def test_boot_number_formatting_uses_caller_owned_buffers(self) -> None:
        self._compile_and_run(
            r"""
            #include <bootlib.h>

            int main(void)
            {
                char hex[19];
                char dec[21];
                if (!Hex2Char(0x1234, hex, sizeof(hex))) return 1;
                if (strcmp(hex, "0x1234") != 0) return 2;
                if (!Dec2Char(18446744073709551615ULL, dec, sizeof(dec))) return 3;
                if (strcmp(dec, "18446744073709551615") != 0) return 4;
                if (Hex2Char(1, hex, 3)) return 5;
                if (Dec2Char(10, dec, 2)) return 6;
                return 0;
            }
            """,
            "boot/bootlib.c",
        )

    def test_vfs_permission_helper_selects_owner_group_and_other_bits(self) -> None:
        self._compile_and_run(
            r"""
            #include <fs/vfs/access.h>

            int main(void)
            {
                if (!vfs_access_allowed(0640, 10, 20, 10, 99, VFS_ACCESS_READ)) return 1;
                if (!vfs_access_allowed(0640, 10, 20, 11, 20, VFS_ACCESS_READ)) return 2;
                if (vfs_access_allowed(0640, 10, 20, 11, 20, VFS_ACCESS_WRITE)) return 3;
                if (vfs_access_allowed(0640, 10, 20, 11, 21, VFS_ACCESS_READ)) return 4;
                if (!vfs_access_allowed(0000, 10, 20, 0, 99, VFS_ACCESS_WRITE)) return 5;
                return 0;
            }
            """
        )

    def test_vfs_fullpath_is_not_fixed_to_256_bytes(self) -> None:
        source = (ROOT / "driver/fs/vfs/vfs.cpp").read_text(encoding="utf-8")
        function = source.split("char *vfs_get_fullpath", 1)[1].split("\n}", 1)[0]
        self.assertNotIn("malloc(256)", function)
        self.assertNotIn("strcat(", function)

    def test_fatfs_dup_opens_an_independent_handle(self) -> None:
        source = (ROOT / "driver/fs/fatfs/fatfs.cpp").read_text(encoding="utf-8")
        function = source.split("vfs_node_t fatfs_dup", 1)[1].split("\n}", 1)[0]
        self.assertNotIn("tar->handle       = src->handle", function)
        self.assertTrue("f_open(" in function or "f_opendir(" in function)

    def test_user_registry_does_not_store_or_compare_plaintext_passwords(self) -> None:
        source = (ROOT / "kernel/user/user.cpp").read_text(encoding="utf-8")
        self.assertNotIn("strcmp(password, registry.uinf[i].password)", source)
        self.assertNotIn("strncpy(registry.uinf[1].password, password", source)
        self.assertNotIn("strcpy(current_user->password, info->password)", source)
        self.assertIn("if (authenticated == NULL) return -EACCES;", source)

    def test_user_registry_uses_versioned_salted_verifiers(self) -> None:
        header = (ROOT / "include/user/user.h").read_text(encoding="utf-8")
        user_info = header.split("} UserInfo;", 1)[0].rsplit("typedef struct", 1)[1]
        self.assertNotIn("password", user_info)
        self.assertIn("USER_REGISTRY_MAGIC", header)
        self.assertIn("USER_REGISTRY_VERSION", header)
        self.assertIn("entry_size", header)
        self.assertIn("salt[USER_PASSWORD_SALT_SIZE]", header)
        self.assertIn("verifier[USER_PASSWORD_VERIFIER_SIZE]", header)

        password_header = (ROOT / "include/user/password.h").read_text(encoding="utf-8")
        self.assertIn("USER_PASSWORD_KDF_PBKDF2_SHA256", password_header)

        user_source = (ROOT / "kernel/user/user.cpp").read_text(encoding="utf-8")
        self.assertIn("USER_PASSWORD_KDF_PBKDF2_SHA256", user_source)

        password_source = (ROOT / "kernel/user/password.cpp").read_text(encoding="utf-8")
        self.assertIn("kSha256RoundConstants", password_source)
        self.assertIn("user_password_constant_time_equal", password_source)
        self.assertIn("user_password_fill_salt", password_source)
        self.assertIn("user_password_clear", password_source)

        xtui_source = (ROOT / "kernel/syscall/xapi/xtui.cpp").read_text(encoding="utf-8")
        self.assertIn("USER_PASSWORD_INPUT_MAX", xtui_source)
        self.assertIn("user_password_clear(kpassword", xtui_source)
        self.assertNotIn("sizeof(((UserInfo *)0)->password)", xtui_source)

    def test_file_syscalls_enforce_owner_group_mode_boundaries(self) -> None:
        source = (ROOT / "kernel/syscall/sys.cpp").read_text(encoding="utf-8")
        self.assertIn("current_user_can_search_node", source)
        self.assertIn("require_path_parent_access(npath, VFS_ACCESS_WRITE)", source)
        self.assertIn("check_node_access(node, mode)", source)
        self.assertIn("require_parent_node_access(oldnode, VFS_ACCESS_WRITE)", source)
        self.assertIn("require_parent_node_access(node, VFS_ACCESS_WRITE)", source)
        self.assertIn("current_user_owns_node(node)", source)
        self.assertIn("current_user_can_update_node_times", source)
        self.assertIn("current_uid() != 0", source)
        self.assertIn("current_user_can_access(handle->node, VFS_ACCESS_WRITE)", source)
        self.assertIn("current_user_can_access(src_handle->node, VFS_ACCESS_READ)", source)

        open_function = source.split("static uint64_t open_kernel_path", 1)[1].split("sys_(open", 1)[0]
        self.assertIn("current_user_can_reach_node(node)", open_function)

        readlink_function = source.split("sys_(readlink)", 1)[1].split("sys_(readlinkat", 1)[0]
        self.assertIn("current_user_can_reach_node(node)", readlink_function)

        statfs_function = source.split("sys_(statfs", 1)[1].split("sys_(fstatfs", 1)[0]
        self.assertIn("vfs_cwd_path_build(kpath)", statfs_function)
        self.assertIn("current_user_can_reach_node(node)", statfs_function)

        self.assertGreaterEqual(source.count("VFS_ACCESS_READ | VFS_ACCESS_EXECUTE"), 2)


if __name__ == "__main__":
    unittest.main()
