From AKM
===============================

This repository contains multiple branches of a Samsung SM8550-based kernel, including upstream merges, stock-based trees, and custom patches such as KernelSU and SUSFS integration.

---

## 📂 Branch Details

| Branch Name                      | Description                                                                                     |
|----------------------------------|-------------------------------------------------------------------------------------------------|
| **A-15_Upstream_Merged**         | Based on `A15_Stock_CLO` but merged with the latest AOSP upstream (GKI).         |
| **A15_Stock_CLO**                | Stock kernel merged with latest Code Linaro base + cherry-picks of my custom commits.    |
| **A14_Stock_CLO**                | Final Edgars-Cirulis's “CLO” release for OneUI 6.1 (kernel 5.15.148).             |
| **A-14_Upstream_Merged**         | Based on `A14_Stock_CLO` but with AOSP upstream merged.                               |
| **Old_AOSP_Merged_with_KSUN**    | Legacy branch mixing `A14_Stock_CLO` with older SUSFS & KernelSU patches (no longer used).     |
| **android13-5.15**               | Pure copy of Edgars-Cirulis's “android13-5.15” branch—no extra commits.                      |

---
## 🛠️ Build Instructions

1. **Clone the repo** and choose your branch:
   ```bash
   git clone https://github.com/akm-04/Samsung_kernel_sm8550-common_Upstream_KernelSU-Next_SUSFS.git
   cd Samsung_kernel_sm8550-common_Upstream_KernelSU-Next_SUSFS
   git checkout <branch name>
2. Configure build.sh at the top for your environment:
    - Use build.sh script in the root directory to start compile the kernel. Configure the build script as needed by specifying clang directories.
    - Build script has options to compile with KernelSU or apply SUSFS patches (Enable either KernelSU or SUKISU or Kernelsu-next, do not enable all or more than one), set it up by editing the variables at the top.
   ```bash
   PATCH_SUSFS=1                    # 1 = apply SUSFS patch
   ENABLE_KSU_NEXT=0                # 1 = enable KernelSU-Next
   ENABLE_SUKISU=0                  # 1 = enable SukiSU-Ultra
   ENABLE_KSU=1                     # 1 = enable classic KernelSU
| Variable              | Description                                                     | Values      |
| --------------------- | --------------------------------------------------------------- | ----------- |
| `PATCH_SUSFS`         | Apply SUSFS4KSU patch series from SimonPunk Gitlab repo                | `0` / `1`   |
| `SUSFS_CHECKOUT_HASH` | (Optional) Specific SUSFS commit SHA to checkout. Set it to empty string to fetch latest release .   | SHA or `""` |
| `ENABLE_KSU_NEXT`     | Enable KernelSU-Next integration                                | `0` / `1`   |
| `KSU_NEXT_STABLE`     | If using KernelSU-Next, pick stable (`1`) or dev (`0`) branches | `0` / `1`   |
| `KSUN_CHECKOUT_HASH`  | (Optional) Specific KernelSU-Next commit SHA to checkout. Set it to empty string to fetch latest release.   | SHA or `""` |
| `ENABLE_SUKISU`       | Enable SukiSU-Ultra integration                                 | `0` / `1`   |
| `SUKI_CHECKOUT_HASH`  | (Optional) Specific SukiSU Ultra commit SHA. Set it to empty string to fetch latest release.          | SHA or `""` |
| `ENABLE_KSU`          | Enable classic KernelSU (By tiann) integration                             | `0` / `1`   |
| `KSU_CHECKOUT_HASH`   | (Optional) Specific KernelSU commit SHA. Set it to empty string to fetch latest release.       | SHA or `""` |

3. Build the kernel by running the build script, final TWRP flashable kernel zip should be produced inside the AnyKernel3 directory.

# How do I submit patches to Android Common Kernels

1. BEST: Make all of your changes to upstream Linux. If appropriate, backport to the stable releases.
   These patches will be merged automatically in the corresponding common kernels. If the patch is already
   in upstream Linux, post a backport of the patch that conforms to the patch requirements below.
   - Do not send patches upstream that contain only symbol exports. To be considered for upstream Linux,
additions of `EXPORT_SYMBOL_GPL()` require an in-tree modular driver that uses the symbol -- so include
the new driver or changes to an existing driver in the same patchset as the export.
   - When sending patches upstream, the commit message must contain a clear case for why the patch
is needed and beneficial to the community. Enabling out-of-tree drivers or functionality is not
not a persuasive case.

2. LESS GOOD: Develop your patches out-of-tree (from an upstream Linux point-of-view). Unless these are
   fixing an Android-specific bug, these are very unlikely to be accepted unless they have been
   coordinated with kernel-team@android.com. If you want to proceed, post a patch that conforms to the
   patch requirements below.

# Common Kernel patch requirements

- All patches must conform to the Linux kernel coding standards and pass `scripts/checkpatch.pl`
- Patches shall not break gki_defconfig or allmodconfig builds for arm, arm64, x86, x86_64 architectures
(see  https://source.android.com/setup/build/building-kernels)
- If the patch is not merged from an upstream branch, the subject must be tagged with the type of patch:
`UPSTREAM:`, `BACKPORT:`, `FROMGIT:`, `FROMLIST:`, or `ANDROID:`.
- All patches must have a `Change-Id:` tag (see https://gerrit-review.googlesource.com/Documentation/user-changeid.html)
- If an Android bug has been assigned, there must be a `Bug:` tag.
- All patches must have a `Signed-off-by:` tag by the author and the submitter

Additional requirements are listed below based on patch type

## Requirements for backports from mainline Linux: `UPSTREAM:`, `BACKPORT:`

- If the patch is a cherry-pick from Linux mainline with no changes at all
    - tag the patch subject with `UPSTREAM:`.
    - add upstream commit information with a `(cherry picked from commit ...)` line
    - Example:
        - if the upstream commit message is
```
        important patch from upstream

        This is the detailed description of the important patch

        Signed-off-by: Fred Jones <fred.jones@foo.org>
```
>- then Joe Smith would upload the patch for the common kernel as
```
        UPSTREAM: important patch from upstream

        This is the detailed description of the important patch

        Signed-off-by: Fred Jones <fred.jones@foo.org>

        Bug: 135791357
        Change-Id: I4caaaa566ea080fa148c5e768bb1a0b6f7201c01
        (cherry picked from commit c31e73121f4c1ec41143423ac6ce3ce6dafdcec1)
        Signed-off-by: Joe Smith <joe.smith@foo.org>
```

- If the patch requires any changes from the upstream version, tag the patch with `BACKPORT:`
instead of `UPSTREAM:`.
    - use the same tags as `UPSTREAM:`
    - add comments about the changes under the `(cherry picked from commit ...)` line
    - Example:
```
        BACKPORT: important patch from upstream

        This is the detailed description of the important patch

        Signed-off-by: Fred Jones <fred.jones@foo.org>

        Bug: 135791357
        Change-Id: I4caaaa566ea080fa148c5e768bb1a0b6f7201c01
        (cherry picked from commit c31e73121f4c1ec41143423ac6ce3ce6dafdcec1)
        [joe: Resolved minor conflict in drivers/foo/bar.c ]
        Signed-off-by: Joe Smith <joe.smith@foo.org>
```

## Requirements for other backports: `FROMGIT:`, `FROMLIST:`,

- If the patch has been merged into an upstream maintainer tree, but has not yet
been merged into Linux mainline
    - tag the patch subject with `FROMGIT:`
    - add info on where the patch came from as `(cherry picked from commit <sha1> <repo> <branch>)`. This
must be a stable maintainer branch (not rebased, so don't use `linux-next` for example).
    - if changes were required, use `BACKPORT: FROMGIT:`
    - Example:
        - if the commit message in the maintainer tree is
```
        important patch from upstream

        This is the detailed description of the important patch

        Signed-off-by: Fred Jones <fred.jones@foo.org>
```
>- then Joe Smith would upload the patch for the common kernel as
```
        FROMGIT: important patch from upstream

        This is the detailed description of the important patch

        Signed-off-by: Fred Jones <fred.jones@foo.org>

        Bug: 135791357
        (cherry picked from commit 878a2fd9de10b03d11d2f622250285c7e63deace
         https://git.kernel.org/pub/scm/linux/kernel/git/foo/bar.git test-branch)
        Change-Id: I4caaaa566ea080fa148c5e768bb1a0b6f7201c01
        Signed-off-by: Joe Smith <joe.smith@foo.org>
```


- If the patch has been submitted to LKML, but not accepted into any maintainer tree
    - tag the patch subject with `FROMLIST:`
    - add a `Link:` tag with a link to the submittal on lore.kernel.org
    - add a `Bug:` tag with the Android bug (required for patches not accepted into
a maintainer tree)
    - if changes were required, use `BACKPORT: FROMLIST:`
    - Example:
```
        FROMLIST: important patch from upstream

        This is the detailed description of the important patch

        Signed-off-by: Fred Jones <fred.jones@foo.org>

        Bug: 135791357
        Link: https://lore.kernel.org/lkml/20190619171517.GA17557@someone.com/
        Change-Id: I4caaaa566ea080fa148c5e768bb1a0b6f7201c01
        Signed-off-by: Joe Smith <joe.smith@foo.org>
```

## Requirements for Android-specific patches: `ANDROID:`

- If the patch is fixing a bug to Android-specific code
    - tag the patch subject with `ANDROID:`
    - add a `Fixes:` tag that cites the patch with the bug
    - Example:
```
        ANDROID: fix android-specific bug in foobar.c

        This is the detailed description of the important fix

        Fixes: 1234abcd2468 ("foobar: add cool feature")
        Change-Id: I4caaaa566ea080fa148c5e768bb1a0b6f7201c01
        Signed-off-by: Joe Smith <joe.smith@foo.org>
```

- If the patch is a new feature
    - tag the patch subject with `ANDROID:`
    - add a `Bug:` tag with the Android bug (required for android-specific features)

