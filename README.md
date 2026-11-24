# SwordFS

A minimal SwiftUI filesystem browser for iPhone 15 Pro Max (A17 Pro) on **iOS 18.1.1**, powered by the DarkSword kernel exploit (vendored from [wh1te4ever/darksword-kexploit-fun](https://github.com/wh1te4ever/darksword-kexploit-fun), which is based on [opa334/darksword-kexploit](https://github.com/opa334/darksword-kexploit)).

> ⚠️ **This is experimental kernel-exploit software.** It runs a race-style kernel exploit in your own process. A failure can crash (panic) the device or just kill the app. Back up before use. Offsets for 18.1.1 A17 are transcribed from the vendored repo and have **not been device-tested** from this codebase.

## What it does

1. **Kernel exploit** (`kexploit_opa334`): IOSurface `PurpleGfxMem` physically-contiguous mapping + `pwritev`/`preadv` vs `mach_vm_map(VM_FLAGS_OVERWRITE)` TOCTOU → OOB physical read/write → ICMPv6 socket spray → `icmp6_filter` corruption → stable kernel read/write. KASLR defeated via `socket → so_proto → pr_input`.
   - A17 Pro is not A18, so `pe_init()` + `pe_v1()` is used; `pe_v2` (A18-only) is left untouched.
2. **Sandbox escape** (`patch_sandbox_ext` from `utils/sandbox.m`): rewrites the app's own sandbox label/extension in-kernel to get read/write at `/`. Falls back to borrowing an extension set from a privileged daemon if the in-place patch does not verify.
3. **Root credentials**: patches the process ucred (`cr_uid`/`cr_ruid`/`cr_svuid` = 0, `ngroups` = 1, `groups`/`cr_rgid`/`cr_svgid` = 0) via `proc_ro → p_ucred`.
4. **Browsing**: after 2+3, plain POSIX / `FileManager` calls see the whole filesystem — no vnode traversal APIs needed in the UI layer.

## Layout

```
SwordFS/
├── project.yml                  XcodeGen spec
├── Makefile / build_ipa.sh      build + ldid fake-sign + IPA packaging
└── SwordFS/
    ├── Info.plist
    ├── SwordFS.entitlements     required private entitlements
    ├── SwordFS-Bridging-Header.h
    ├── SwordFSApp.swift
    ├── Bridge/                  ObjC wrapper around the exploit
    ├── Core/                    FileSystemService + ExploitController
    ├── UI/                      ExploitView (log) + BrowserView
    └── Exploit/                 vendored exploit + UI-free LogTextView shim
        ├── kexploit/            kexploit_opa334, krw, kutils, offsets, vnode, xpaci, machine_info
        ├── utils/sandbox.*      patch_sandbox_ext / borrow_sandbox_ext / check_sandbox_var_rw
        └── research/            sandbox_research structs, apfs_fsnode.h
```

## Building

On a Mac (Xcode 16+, plus `brew install xcodegen ldid`):

```sh
make          # produces build/SwordFS.ipa
# or
./build_ipa.sh
```

The app is built **unsigned**, then fake-signed with `ldid -S SwordFS/SwordFS.entitlements`. The exploit needs `IOSurfaceRoot`/`AGX*` user-client access, `proc_info-allow`, and platform-application entitlements — a plain developer certificate cannot grant these.

## Installing on iOS 18.1.1

- **TrollStore does not support 18.1.1** (only up to 18.1 / 18.2 betas on some devices — don't count on it here).
- Use an installer that leverages the same sparse-restore family of exploits for arbitrary entitlements. Note the [SparseBox caveat](https://github.com/khanhduytran0/SparseBox/issues/95): SparseBox itself advertises support only up to 18.1b5, though some users report sparse-restore still landing on 18.1.1. [LARA](https://github.com/rooootdev/lara) (which itself uses the DarkSword kexploit on 17.0–18.7.1) can be used as an on-device toolbox/installer route.
- Whichever installer you use, it must install with the entitlements from `SwordFS.entitlements` intact.

## Using the app

1. Launch → tap **Run exploit**. The log console shows the exploit's live `printf` stream.
2. When it reports **READY** (uid 0, sandbox escaped), tap **Open file browser**.
3. Navigate with bookmarks or "Go to path…". Files preview as text or hex; rename/delete/new-folder work through plain POSIX calls.
4. On unrecoverable exploit failure the process calls `exit()` (upstream behavior) — just relaunch and retry. If the phone panics, reboot and try again; the race sometimes needs a couple of launches.

## Notes / caveats

- `offsets_init()` accepts iOS 17.0–26.0; the 18.1 A17 overrides in `offsets.m` set the thread offsets, while the 18.0 block supplies `icmp6filt 0x148`, `so_usecount 0x254`, `so_proto 0x20`, `inp_gencnt 0x78`, `proc_ro/p_ucred 0x20`, `cr_label 0x78`.
- The vendored `kexploit_opa334.h` redefines `printf` to also call `log_write()`; our UI-free `Exploit/LogTextView.h/.m` shim keeps that contract and forwards lines to the SwiftUI log via a hook.
- This is **not** a jailbreak: kernel r/w + sandbox escape + root creds only. No PPL/CoreTrust bypass; AMFI still enforces code signatures.
- Kernel primitives (`kread64`, `kwrite64`, `kreadbuf`, `kwritebuf`, `selfProc`) are exposed through `SwordFSBridge` if you want to experiment beyond the browser.
