#!/bin/bash
set -Eeuo pipefail

# Static constants
BUILD_START=$(date +"%s")
blue='\033[1;94m'
yellow='\033[1;33m'
nocol='\033[0m'
green='\033[1;32m'
red='\033[1;31m'
KERNELDIR=$PWD
trap 'error_handler $LINENO' ERR

echo -e " $yellow #####|                 Kernel Build Script                  |########$nocol "
echo -e " $yellow #####|     Choose Correct options as required when asked    |##########$nocol "
echo -e " $yellow #####| To use specific AOSP clang version, edit this script |######$nocol "
echo -e " $yellow #####|   and specify correct clang version and install dir  |#####$nocol "
echo -e " $yellow #####|   Configure PATCH_SUSFS, ENABLE_KSU[_NEXT], etc. at  |########$nocol "
echo -e " $yellow #####|       top of the script to enable KernelSU patches   |######### $nocol"


# -------------------------------- | Dependencies |--------------------------------------------------------------#
# Uncomment Next 4 lines to install all necessary dependencies for kernel Compiling.

#sudo apt-get update && sudo apt-get install -y \
#  build-essential libncurses-dev bison flex libssl-dev libelf-dev bc \
#  dwarves fakeroot git clang llvm lld lldb \
#  gcc-aarch64-linux-gnu gcc-arm-linux-gnueabihf gcc-arm-linux-gnueabi

# ---------------------------------------------------------------------------------------------------------------- #
# ---------------------------| EXPORTS and Directory Setup |------------------------------------------------------ #
KERNEL_DEFCONFIG=${1:-gki_defconfig}  # Looks for defconfig in arch/<exported_arch>/configs/
ANYKERNEL3_DIR=$PWD/AnyKernel3/ # Required by the function zip_kernel
CLANG_VERSION=clang-r547379
CLANG_DIR="$HOME/Git/Clang/$CLANG_VERSION"
CLANG_BINARY="$CLANG_DIR/bin/clang"
CC_CLANG=clang
export ARCH=arm64
export SUBARCH=ARM64
export PATH="$CLANG_DIR/bin:$PATH"
export KBUILD_COMPILER_STRING="$($CLANG_BINARY --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"

# An array that stores all make command, edit it as required. These options will be used throughout the script
MAKE_FLAGS=( \
  O=out \
  CC="$CC_CLANG" \
  LD=ld.lld \
  LLVM=1 \
  LLVM_IAS=1 \
)

# ---------------------------------------| Function options |------------------------------------------------------------------------ #

ARTIFACT="Image.gz"            # Variable to hold the name of the final kernel artifact. Change as required.
BUILD_MODULES="n"              # "y" = Enabled | "n" = Disabled
ENABLE_BREAKPOINTS=0           # Enabled all breakpoints in the script to interrupt after specific steps to maybe apply a manual patch.
# -----------------------------------------------------------------------------------------
PATCH_SUSFS=1                  # 1=Apply SUSFS patch from simonpunk repo     | 0=skip
SUSFS_CHECKOUT_HASH=""         # If non‐empty, SUSFS_Patch will checkout this commit after cloning.
#SUSFS_CHECKOUT_HASH="eeb4737559da1321d0f121f1b3aa75ae9567075a"  # As an example, uncomment this to Checkout to SUSFS v1.5.5.
# ------------------------------------------------------------------------------------------------------------------------------------ #


# ---------------------- | Enable either KernelSU or KernelSU-Next or SUKISU, DO NOT ENABLE BOTH OR ALL! | ----------------------------#

# ====================================== # | KernelSU-Next Options
ENABLE_KSU_NEXT=0              # 1=Use KernelSU-Next                    | 0=Skip
KSU_NEXT_STABLE=1         # 1=Use KernelSU-Next stable branches    | 0=Use KernelSU-Next Development branches. | (Only works if ENABLE_KSU_NEXT=1)
# Setting Checkout hash ignores / disables KSU_NEXT_STABLE
# If set, script will checkout this specific commit SHA, resulting in a detached HEAD regardless of branch selected.
KSUN_CHECKOUT_HASH=""
#KSUN_CHECKOUT_HASH="505502a173705243b2042bc055c43fe9d319a49e"
# -----------------------------------------------------------------------------------------

# ====================================== # | SUKISU-Ultra Options
ENABLE_SUKISU=0                # 1=Use SUKISU                           | 0=Skip
SUKISU_STABLE=0                # 1=Use SUKISU SUSFS Stable branches    | 0=Use SUKISU SUSFS Development branches. | (Only works if ENABLE_SUKISU=1)
# Setting Checkout hash ignores / disables SUKISU_STABLE
# If set, script will checkout this specific commit SHA, resulting in a detached HEAD regardless of branch selected.
SUKI_CHECKOUT_HASH=""

# ====================================== # | KernelSU Options
ENABLE_KSU=1                   # 1=Use KernelSU                         | 0=Skip. | (Auto applies KernelSU SUSFS patches if PATCH_SUSFS=1)
# If set, script will checkout this specific commit SHA, resulting in a detached HEAD regardless of branch selected.
KSU_CHECKOUT_HASH=""


# -------------------------------------- Information and miscellaneous Functions ------------------------------------------------------#

log_section() {
  echo  # Blank line
  echo -e "${blue}#####################################################################${nocol}"
  echo -e "${yellow}========================================================${nocol}"
  echo -e "${green}$1${nocol}"
  echo -e "${yellow}========================================================${nocol}"
  echo -e "${blue}#####################################################################${nocol}"
  echo  # Blank line
  echo  # Blank line

}


start() {
    FINAL_KERNEL_ZIP=""
    while true; do
        read -rp "Enter final kernel zip name (format: <kernel_name>.zip): " FINAL_KERNEL_ZIP

        # Strip all whitespace and stray CR
        FINAL_KERNEL_ZIP="${FINAL_KERNEL_ZIP//[[:space:]]/}"
        FINAL_KERNEL_ZIP="${FINAL_KERNEL_ZIP//$'\r'/}"

        # 1) Reject truly empty input
        if [[ -z "$FINAL_KERNEL_ZIP" ]]; then
            echo -e "${yellow}Input cannot be empty.${nocol}"
            continue
        fi

        # 2) Append .zip only once
        if [[ "$FINAL_KERNEL_ZIP" != *.zip ]]; then
            FINAL_KERNEL_ZIP="${FINAL_KERNEL_ZIP}.zip"
        fi

        break
    done

    echo -e "Final Kernel name is set to $FINAL_KERNEL_ZIP"
}

error_handler() {
    local lineno="$1"
    echo
    echo -e "${red}❌ Error on line ${lineno}. Aborting...${nocol}"
    echo

    # Yellow explanatory text
    echo -e "${yellow}It looks like the build script exited early."
    echo -e "To clean your tree, run one of the following commands to undo KernelSU/Next/SUKISU changes:${nocol}"
    echo

    echo
    echo -e "  ${blue}# If you used SUKISU:${nocol}"
    echo -e "  ${nocol}curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s -- --cleanup${nocol}"
    echo

    echo 
    echo -e "  ${blue}# If you used KernelSU‑Next:${nocol}"
    echo -e "  ${nocol}curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next-susfs/kernel/setup.sh" | bash -s -- --cleanup${nocol}"

    echo
    echo -e "  ${blue}# If you used stock KernelSU:${nocol}"
    echo -e "  ${nocol}curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s -- --cleanup${nocol}"
    echo

    echo
    echo -e "${blue}To clean the changes caused by patches, run the following command.${nocol}"
    echo -e "${red}WARNING: This will reset your repo to a pristine state and "
    echo -e "destroy any uncommitted changes. Proceed with caution!${nocol}"
    echo

    echo -e "  ${yellow}git reset --hard HEAD && git clean -xfd${nocol}"
    echo

    exit 1
}

clone() {
    log_section "Clone Function Start"
    if ! [ -d "$CLANG_DIR" ]; then
        echo -e "${red}Clang not found! Cloning...${nocol}"
        mkdir -p "$CLANG_DIR"

        if ! wget --show-progress -O "$CLANG_DIR/${CLANG_VERSION}.tar.gz" "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/${CLANG_VERSION}.tar.gz"; then
            echo "${red}Cloning failed! Aborting...${nocol}"
            exit 1
        fi

        echo "${yellow}Cloning successful. Extracting the tar file...${nocol}"
        tar -xzf "$CLANG_DIR/${CLANG_VERSION}.tar.gz" -C "$CLANG_DIR"
        rm "$CLANG_DIR/${CLANG_VERSION}.tar.gz"
    fi

    echo -e "${green}Correct Clang version is cloned and setup!${nocol}"
}


clean_kernel() {
    log_section "Clean_Kernel function start"
    cd "$KERNELDIR"

    # Always do clean build
    echo -e "$yellow**** Cleaning / Removing 'out' folder ****$nocol"
    rm -rf out
    mkdir -p out

    echo -e "$yellow**** Cleaning 'AnyKernel3' folder / any previous builds ****$nocol"
    rm -f "$ANYKERNEL3_DIR"/*.zip
    rm -rf "$ANYKERNEL3_DIR/$ARTIFACT"
    rm -rf "$ANYKERNEL3_DIR/dtbo.img"

    # Only remove SUSFS sources if we’re patching SUSFS
    if [ "${PATCH_SUSFS:-0}" -eq 1 ]; then
        echo -e "$yellow**** Removing SUSFS folder/patch ****$nocol"
        rm -rf susfs4ksu 50_add_susfs_in_gki-5.15*.patch
    fi

    # Only remove KSU trees if any KSU variant is enabled
    if [ "${ENABLE_KSU_NEXT:-0}" -eq 1 ] || \
       [ "${ENABLE_SUKISU:-0}"    -eq 1 ] || \
       [ "${ENABLE_KSU:-0}"       -eq 1 ]; then
        echo -e "$yellow**** Removing KSU source folders ****$nocol"
        rm -rf KernelSU-Next KernelSU
    fi
}


zip_kernel() {
    log_section "Now zipping Kernel image into TWRP flashable zip"
    cd $KERNELDIR

    echo -e "$blue***********************************************"
    echo "   COMPILING FINISHED! NOW MAKING IT INTO FLASHABLE ZIP "
    echo -e "***********************************************$nocol"

    echo -e "$yellow**** Verify that $ARTIFACT is produced ****$nocol"
    ls $PWD/out/arch/arm64/boot/$ARTIFACT

    echo -e "$yellow**** Verifying AnyKernel3 Directory ****$nocol"
    ls $ANYKERNEL3_DIR

    echo -e "$yellow**** Removing leftovers from anykernel3 folder ****$nocol"
    rm -rf "$ANYKERNEL3_DIR/$ARTIFACT"
    rm -rf "$ANYKERNEL3_DIR"/*.zip
    rm -rf "$ANYKERNEL3_DIR"/dtbo.img
    if [ ! -f "$KERNELDIR/out/arch/arm64/boot/$ARTIFACT" ]; then
        echo -e "$red**** Error: $ARTIFACT not found! Build failed. ****$nocol"
        exit 1
    fi

    # Generate today's date and time in the format YYYYMMDD_HHMMSS
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

    # Append timestamp to the final kernel zip file name
    FINAL_KERNEL_ZIP_WITH_TIMESTAMP="${FINAL_KERNEL_ZIP%.*}_${TIMESTAMP}.zip"
    export FINAL_KERNEL_ZIP_WITH_TIMESTAMP

    echo -e "$yellow**** Copying $ARTIFACT to anykernel 3 folder ****$nocol"
    cp "$KERNELDIR/out/arch/arm64/boot/$ARTIFACT" "$ANYKERNEL3_DIR/"

    echo -e "$green**** Time to zip up! ****$nocol"
    cd $ANYKERNEL3_DIR/
    zip -r9 $FINAL_KERNEL_ZIP_WITH_TIMESTAMP * -x README $FINAL_KERNEL_ZIP_WITH_TIMESTAMP
    #cp $ANYKERNEL3_DIR/$FINAL_KERNEL_ZIP_WITH_TIMESTAMP $KERNELDIR/$FINAL_KERNEL_ZIP_WITH_TIMESTAMP

    echo -e "$green**** Done, generated flashable zip successfully ****$nocol"

    # Output the location of the generated zip file
    echo -e "$yellow**** Generated Zip File Location: $KERNELDIR/AnyKernel3/$FINAL_KERNEL_ZIP_WITH_TIMESTAMP ****$nocol"

    cd ..
}


summary() {
    log_section "Build Complete! Now Producing Summary ....."
    echo -e "$blue***********************************************"
            echo "         Summary for the Entire Build                 "
            echo -e "***********************************************$nocol"

    echo -e "$green**** Done, here is your checksum and other info ****$nocol"
    BUILD_END=$(date +"%s")
    DIFF=$(($BUILD_END - $BUILD_START))
    echo -e "$yellow Full Build completed in $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds.$nocol"
    echo -e "$yellow**** Generated Zip File Location: $KERNELDIR/AnyKernel3/$FINAL_KERNEL_ZIP_WITH_TIMESTAMP ****$nocol"
    echo -e "$blue**** Checksum for kernel zip ****$nocol"
    sha1sum "$KERNELDIR/AnyKernel3/$FINAL_KERNEL_ZIP_WITH_TIMESTAMP"
    if [ "$BUILD_MODULES" == "y" ]; then
        echo -e "$green**** Checksum for Module zip ****$nocol" && sha1sum "$KERNELDIR/Mod/$MOD_NAME" && echo -e "$green**** Generated Module Zip File Location: $KERNELDIR/Mod/$MOD_NAME ****$nocol"
    fi
}


# ---------------------------------------------------- |Build Functions - Tweak parameters as needed| -------------------------------------------------#
build_kernel() {
    log_section "Now Building Kernel ....."
    cd $KERNELDIR
    # ----------------------Toolchain Info ----------------------------------
    echo -e "$green*** Using this Clang Version to compile kernel *** $nocol"
    $CC_CLANG --version

    #-----------------------Defconfig stuff-----------------------------------
    echo -e "$yellow**** Kernel defconfig is set to $KERNEL_DEFCONFIG ****$nocol"
    echo -e "$blue***********************************************"
    echo "       NOW MAKING _defconfig : $KERNEL_DEFCONFIG        "
    echo -e "***********************************************$nocol"
    #make O=out CC="$CC_CLANG" $KERNEL_DEFCONFIG
    make \
        "${MAKE_FLAGS[@]}" \
        "$KERNEL_DEFCONFIG" \
        "-j$(nproc)" \
        2>&1 | tee build.log
    echo #blank line

    #------------------------Kernel Stuff-------------------------------------
    echo -e "$blue***********************************************"
    echo "         NOW COMPILING KERNEL!                  "
    echo -e "***********************************************$nocol"

    make \
        "${MAKE_FLAGS[@]}" \
        "-j$(nproc)" \
        2>&1 | tee -a build.log   # append to the same log
    echo #blank line

    #---------------------------Build Summary------------------------------------
    BUILD_MID=$(date +"%s")
    MID_DIFF=$(($BUILD_MID - $BUILD_START))
    echo -e "$yellow Kernel Compiled in $(($MID_DIFF / 60)) minute(s) and $(($MID_DIFF % 60)) seconds.$nocol"
}


build_modules() {
    #------------- Name verification starts -------------#
    log_section "Building Modules Now"
    MODULES_NAME=""
    while true; do
        read -rp "Enter final Module zip name (format: <Module_name>.zip): " MODULES_NAME
        # Strip all whitespace and stray CR
        MODULES_NAME="${MODULES_NAME//[[:space:]]/}"
        MODULES_NAME="${MODULES_NAME//$'\r'/}"
        # 1) Reject truly empty input
        if [[ -z "$MODULES_NAME" ]]; then
            echo -e "${yellow}Input cannot be empty.${nocol}"
            continue
        fi
        # 2) Append .zip only once
        if [[ "$MODULES_NAME" != *.zip ]]; then
            MODULES_NAME="${MODULES_NAME}.zip"
        fi
        # Now we have a valid, non-empty name (with .zip)
        break
    done
    echo -e "Final Module name is set to $MODULES_NAME"
    echo # Blank line
    #------------- Name verification ends --------------#
    cd "$KERNELDIR"
    # Build modules if selected by the user
    if [[ "$BUILD_MODULES" == "y" ]]; then
        echo -e "|| Preparing NetErnel_modules folder in $KERNELDIR ||"

        # Ensure NetErnel_modules exists, clone if missing
        if [[ ! -d "$KERNELDIR/NetErnel_modules" ]]; then
            echo -e "${yellow}NetErnel_modules folder not found; cloning from GitHub...${nocol}"
            if git clone https://github.com/akm-04/NetErnels-Modules.git NetErnel_modules; then
                echo -e "${green}Cloned NetErnels-Modules into NetErnel_modules successfully.${nocol}"
            else
                echo -e "${red}**** Error: Failed to clone NetErnels-Modules repo. ****${nocol}"
                exit 1
            fi
        fi

        # At this point NetErnel_modules exists
        echo -e "|| Copying NetErnel_modules folder to Mod/ ||"
        rm -rf "$KERNELDIR/Mod"                # ensure a clean Mod/ directory
        if cp -r "$KERNELDIR/NetErnel_modules" "$KERNELDIR/Mod"; then
            echo -e "${green}Copied NetErnel_modules into Mod successfully.${nocol}"
        else
            echo -e "${red}**** Error: Failed to copy 'NetErnel_modules' to 'Mod' folder. ****${nocol}"
            exit 1
        fi
        if [ "$BUILD_MODULES" == "y" ]; then
            echo -e "$blue***********************************************"
            echo "         NOW Compiling Modules!                 "
            echo -e "***********************************************$nocol"

            echo -e "$green*** Using this Clang Version to compile module*** $nocol"
            $CC_CLANG --version
            echo -e "$yellow**** Kernel defconfig is set to $KERNEL_DEFCONFIG ****$nocol"
            echo -e "$blue***********************************************"
            echo "       NOW MAKING _defconfig : $KERNEL_DEFCONFIG        "
            echo -e "***********************************************$nocol"
            make \
                "${MAKE_FLAGS[@]}" \
                "$KERNEL_DEFCONFIG" \
                "-j$(nproc)" \
                2>&1 | tee -a build.log
            echo #blank line
            echo -e "$yellow**** Preparing Modules ****$nocol"
            make \
                "${MAKE_FLAGS[@]}" \
                modules_prepare \
                "-j$(nproc)" \
                INSTALL_MOD_PATH="$KERNELDIR/out/modules" \
                2>&1 | tee -a build.log || {
                    echo "Error preparing modules"
                    exit 1
            }
            echo #blank line

            echo -e "$yellow**** Building Modules ****$nocol"
            make \
                "${MAKE_FLAGS[@]}" \
                modules \
                INSTALL_MOD_PATH="$KERNELDIR/out/modules" \
                "-j$(nproc)" \
                2>&1 | tee -a build.log || {
                    echo "Error building modules"
                    exit 1
            }
            echo #blank line
            echo -e "$yellow**** Installing Modules ****$nocol"

            make \
                "${MAKE_FLAGS[@]}" \
                modules_install \
                INSTALL_MOD_PATH="$KERNELDIR/out/modules" \
                "-j$(nproc)" \
                 2>&1 | tee -a build.log || {
                    echo "Error installing modules"
                    exit 1
            }
            echo #blank line
        fi

        echo -e "$blue***********************************************"
        echo "         Zipping Modules!                  "
        echo -e "***********************************************$nocol"

        if [ ! -d "Mod" ]; then
            echo -e "$red**** Error: 'Mod' folder not found. Make sure the build_modules step was executed correctly. ****$nocol"
            exit 1
        fi

        # Generate today's date and time in the format YYYYMMDD_HHMMSS
        TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

        # Append timestamp to the module zip file name
        MODULES_NAME_WITH_TIMESTAMP="${MODULES_NAME%.*}_${TIMESTAMP}.zip"

        find "$KERNELDIR"/out/modules -type f -iname '*.ko' -exec cp {} Mod/system/lib/modules/ \; || {
            echo "Error copying modules"
            exit 1
        }
        cd $KERNELDIR
        cd Mod

        rm -rf system/lib/modules/placeholder
        zip -r9 $MODULES_NAME_WITH_TIMESTAMP . -x ".git*" -x "LICENSE.md" -x "*.zip"
        MOD_NAME="$MODULES_NAME_WITH_TIMESTAMP"
        # Print a message indicating success
        echo -e "$green**** Module.zip created successfully ****$nocol"

        # Output the location of the generated module.zip file
        echo -e "$green**** Generated Module Zip File Location: $KERNELDIR/Mod/$MOD_NAME ****$nocol"

        cd $KERNELDIR

        MODULES_MID=$(date +"%s")
        MODULES_DIFF=$(($MODULES_MID - $BUILD_START))
        echo -e "$yellow Modules Compiled in $(($MODULES_DIFF / 60)) minute(s) and $(($MODULES_DIFF % 60)) seconds.$nocol"

    else
        echo -e "$yellow**** Skipping building modules as per user choice ****$nocol"
    fi
}



# ------------------------------------- Patches -----------------------------------------------------------#

APPLY_PATCHES() {
    # Ensure we’re in the kernel root
    cd "$KERNELDIR" || { echo -e "${red}ERROR: Could not cd to $KERNELDIR${nocol}"; exit 1; }

    # 1) Install KernelSU (stock) if requested
    if [[ "$ENABLE_KSU" == "1" ]]; then
        log_section "Applying KernelSU (stock) setup"
        Enable_KernelSU
    fi

    # 2) Install KernelSU-Next if requested (chooses SUSFS vs stock branch internally)
    if [[ "$ENABLE_KSU_NEXT" == "1" ]]; then
        log_section "Applying KernelSU-Next setup"
        Enable_KernelSU-Next
    fi

    if [[ "$ENABLE_SUKISU" == "1" ]]; then
        log_section "Applying SUKISU setup"
        Enable_SUKISU-ultra
    fi

    # 3) Apply SUSFS patches (into main tree, and into KernelSU tree if enabled)
    if [[ "$PATCH_SUSFS" == "1" ]]; then
        log_section "Cloning and Applying SUSFS patches"
        SUSFS_Patch
    fi
}


# Apply the SUSFS patches into your kernel tree
SUSFS_Patch() {
    cd $KERNELDIR
    if [[ "$PATCH_SUSFS" == "1" ]]; then

        # 1) Clone the susfs4ksu repo (contains fs code and patch)
        echo -e "${blue}Cloning susfs4ksu branch gki-android13-5.15…${nocol}"
        git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-android13-5.15
        
        # 1.5) Optional checkout
        if [[ -n "$SUSFS_CHECKOUT_HASH" ]]; then
            echo -e "${blue}[SUSFS: Checkout hash set, Switching to detached head..] Checking out commit $SUSFS_CHECKOUT_HASH…${nocol}"
            (cd susfs4ksu && git checkout "$SUSFS_CHECKOUT_HASH") \
                || { echo -e "${red}[SUSFS] Checkout $SUSFS_CHECKOUT_HASH failed${nocol}"; exit 1; }
            cd "$KERNELDIR" || exit 1
        fi

        # 2) Copy over filesystem and headers
        echo -e "${yellow}Copying SUSFS filesystem and headers…${nocol}"
        cp susfs4ksu/kernel_patches/fs/* fs/
        cp susfs4ksu/kernel_patches/include/linux/* include/linux/

        # 3) Copy the actual patch file
        echo -e "${yellow}Copying SUSFS patch file…${nocol}"
        cp susfs4ksu/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch .

        # 4) Apply the patch, with conflict handling
        log_section "Started Applying SUSFS Patches "
        if patch -p1 --fuzz=3 < 50_add_susfs_in_gki-android13-5.15.patch; then
            echo -e "${green}SUSFS Patch applied successfully.${nocol}"
            if [[ "$ENABLE_KSU" == "1" ]]; then
                log_section "Started Applying SUSFS Patches to KernelSU"
                cp susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch KernelSU/
                cd KernelSU
                if patch -p1 --fuzz=3 < 10_enable_susfs_for_ksu.patch; then
                    echo -e "${green}KernelSU SUSFS Patch applied successfully.${nocol}"
                    rm -f 10_enable_susfs_for_ksu.patch
                    cd $KERNELDIR
                fi
            fi
            if [[ "$ENABLE_BREAKPOINTS" == "1" ]]; then
                read -p "Breakpoint after applying SUSFS patch Detected! Press Enter to continue..."
            fi
            echo -e "${yellow}Removing susfs4ksu directory and patch file...${nocol}"
            rm -rf susfs4ksu 50_add_susfs_in_gki-android13-5.15.patch
            echo -e "${green}SUSFS patch applied and cleaned up.${nocol}"
        else
            echo -e "${red}Patch failed with conflicts. Exiting.${nocol}" >&2
            exit 1
        fi
    fi
}


# Clone and set up the KernelSU‑Next framework itself
Enable_KernelSU-Next() {
    cd $KERNELDIR
    if [[ "$ENABLE_KSU_NEXT" == "1" ]]; then
        if [[ "$PATCH_SUSFS" == "1" ]]; then

            if [[ "$KSU_NEXT_STABLE" == "1" ]]; then
                echo -e "${blue}Cloning KernelSU-Next (SUSFS Stable Branch) ...…${nocol}"
                curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next-susfs/kernel/setup.sh" | bash -s next-susfs
                if [[ -n "$KSUN_CHECKOUT_HASH" ]]; then
                    echo -e "${blue}[KernelSU-Next SUSFS Stable: Checkout hash set, Switching to detached head..] Checking out commit $KSUN_CHECKOUT_HASH…${nocol}"
                    (cd KernelSU-Next && git checkout "$KSUN_CHECKOUT_HASH") \
                        || { echo -e "${red}[KernelSU-Next_Stable] Checkout $KSUN_CHECKOUT_HASH failed${nocol}"; exit 1; }
                    cd "$KERNELDIR" || exit 1
                fi
            else
                echo -e "${blue}Cloning KernelSU-Next (SUSFS Development Branch) ...…${nocol}"
                curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next-susfs/kernel/setup.sh" | bash -s next-susfs-dev
                if [[ -n "$KSUN_CHECKOUT_HASH" ]]; then
                    echo -e "${blue}[KernelSU-Next SUSFS Development: Checkout hash set, Switching to detached head..] Checking out commit $KSUN_CHECKOUT_HASH…${nocol}"
                    (cd KernelSU-Next && git checkout "$KSUN_CHECKOUT_HASH") \
                        || { echo -e "${red}[KernelSU-Next_Development] Checkout $KSUN_CHECKOUT_HASH failed${nocol}"; exit 1; }
                    cd "$KERNELDIR" || exit 1
                fi
            fi
            echo -e "${green}KernelSU-Next (SUSFS) framework clonning and setup done!.${nocol}"
            if [[ "$ENABLE_BREAKPOINTS" == "1" ]]; then
                read -p "Breakpoint after Cloning KernelSU-Next SUSFS Detected! Press Enter to continue..."
            fi
        else
            if [[ "$KSU_NEXT_STABLE" == "1" ]]; then
                echo -e "${blue}Cloning KernelSU-Next Latest release.... …${nocol}"
                curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -
                if [[ -n "$KSUN_CHECKOUT_HASH" ]]; then
                    echo -e "${blue}[KernelSU-Next Stable: Checkout hash set, Switching to detached head..] Checking out commit $KSUN_CHECKOUT_HASH…${nocol}"
                    (cd KernelSU-Next && git checkout "$KSUN_CHECKOUT_HASH") \
                        || { echo -e "${red}[KernelSU-Next_Stable] Checkout $KSUN_CHECKOUT_HASH failed${nocol}"; exit 1; }
                    cd "$KERNELDIR" || exit 1
                fi
            else
                echo -e "${blue}Cloning KernelSU-Next Next Development release.... …${nocol}"
                curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -s next
                if [[ -n "$KSUN_CHECKOUT_HASH" ]]; then
                    echo -e "${blue}[KernelSU-Next Development: Checkout hash set, Switching to detached head..] Checking out commit $KSUN_CHECKOUT_HASH…${nocol}"
                    (cd KernelSU-Next && git checkout "$KSUN_CHECKOUT_HASH") \
                        || { echo -e "${red}[KernelSU-Next_Development] Checkout $KSUN_CHECKOUT_HASH failed${nocol}"; exit 1; }
                    cd "$KERNELDIR" || exit 1
                fi
            fi
            echo -e "${green}KernelSU-Next framework clonning and setup done!.${nocol}"
            if [[ "$ENABLE_BREAKPOINTS" == "1" ]]; then
                read -p "Breakpoint after Cloning KernelSU-Next Detected! Press Enter to continue..."
            fi
        fi
    fi

}


Enable_KernelSU() {
    cd $KERNELDIR
    if [[ "$ENABLE_KSU" == "1" ]]; then
        echo -e "${blue}Cloning KernelSU .... …${nocol}"
        curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -
        if [[ -n "$KSU_CHECKOUT_HASH" ]]; then
            echo -e "${blue}[KernelSU: Checkout hash set, Switching to detached head..] Checking out commit $KSU_CHECKOUT_HASH…${nocol}"
            (cd KernelSU && git checkout "$KSU_CHECKOUT_HASH") \
                || { echo -e "${red}[KernelSU] Checkout $KSU_CHECKOUT_HASH failed${nocol}"; exit 1; }
            cd "$KERNELDIR" || exit 1
        fi
        echo -e "${green}KernelSU framework clonning and setup done!.${nocol}"
        if [[ "$ENABLE_BREAKPOINTS" == "1" ]]; then
            read -p "Breakpoint after Cloning KernelSU Detected! Press Enter to continue..."
        fi
    fi
}

Enable_SUKISU-ultra() {
    cd $KERNELDIR
    if [[ "$ENABLE_SUKISU" == "1" ]]; then
        if [[ "$PATCH_SUSFS" == "1" ]]; then

            if [[ "$SUKISU_STABLE" == "1" ]]; then
                echo -e "${blue}Cloning SUKISU (SUSFS) Stable branch and setting it up .... …${nocol}"
                curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s susfs-stable
                if [[ -n "$SUKI_CHECKOUT_HASH" ]]; then
                    echo -e "${blue}[SUKISU SUSFS Stable: Checkout hash set, Switching to detached head..] Checking out commit $SUKI_CHECKOUT_HASH…${nocol}"
                    (cd KernelSU && git checkout "$SUKI_CHECKOUT_HASH") \
                        || { echo -e "${red}[SUKISU_SUSFS_Stable:] Checkout $SUKI_CHECKOUT_HASH failed${nocol}"; exit 1; }
                    cd "$KERNELDIR" || exit 1
                fi
            else
                echo -e "${blue}Cloning SUKISU (SUSFS) Development branch and setting it up .... …${nocol}"
                curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s susfs-dev
                if [[ -n "$SUKI_CHECKOUT_HASH" ]]; then
                    echo -e "${blue}[SUKISU SUSFS: Checkout hash set, Switching to detached head..] Checking out commit $SUKI_CHECKOUT_HASH…${nocol}"
                    (cd KernelSU && git checkout "$SUKI_CHECKOUT_HASH") \
                        || { echo -e "${red}[SUKISU_SUSFS_Development:] Checkout $SUKI_CHECKOUT_HASH failed${nocol}"; exit 1; }
                    cd "$KERNELDIR" || exit 1
                fi
            fi
            echo -e "${green}SUKISU (SUSFS) framework clonning and setup done!.${nocol}"
            echo -e "${blue}Enabling KPM in defconfig .... …${nocol}"
            ./scripts/config \
                --file "arch/${ARCH}/configs/${KERNEL_DEFCONFIG}" \
                --enable KPM
            if [[ "$ENABLE_BREAKPOINTS" == "1" ]]; then
                read -p "Breakpoint after Cloning SUKISU SUSFS Detected! Press Enter to continue..."
            fi
        else
            echo -e "${blue}Cloning SUKISU and setting it up .... …${nocol}"
            curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s main
            if [[ -n "$SUKI_CHECKOUT_HASH" ]]; then
                echo -e "${blue}[SUKISU: Checkout hash set, Switching to detached head..] Checking out commit $SUKI_CHECKOUT_HASH…${nocol}"
                (cd KernelSU && git checkout "$SUKI_CHECKOUT_HASH") \
                    || { echo -e "${red}[SUKISU:] Checkout $SUKI_CHECKOUT_HASH failed${nocol}"; exit 1; }
                cd "$KERNELDIR" || exit 1
            fi
            echo -e "${green}SUKISU framework clonning and setup done!.${nocol}"
            echo -e "${blue}Enabling KPM in defconfig .... …${nocol}"
            ./scripts/config \
                --file "arch/${ARCH}/configs/${KERNEL_DEFCONFIG}" \
                --enable KPM
            if [[ "$ENABLE_BREAKPOINTS" == "1" ]]; then
                read -p "Breakpoint after Cloning SUKISU Detected! Press Enter to continue..."
            fi
        fi
    fi
}

Final_CLEANUP() {
    cd "$KERNELDIR" || exit 1

    if [[ "$ENABLE_KSU" == "1" ]]; then
        log_section "Final Clean: Removing KernelSU Framework"
        curl -fsSL \
          "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" \
          | bash -s -- --cleanup \
          || { echo -e "${red}KernelSU cleanup failed!${nocol}"; exit 1; }
    fi

    if [[ "$ENABLE_KSU_NEXT" == "1" ]]; then
        log_section "Final Clean: Removing KernelSU-Next Framework"
        curl -fsSL \
          "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next-susfs/kernel/setup.sh" \
          | bash -s -- --cleanup \
          || { echo -e "${red}KernelSU-Next cleanup failed!${nocol}"; exit 1; }
    fi

    if [[ "$ENABLE_SUKISU" == "1" ]]; then
        log_section "Final Clean: Removing SUKISU Framework"
        curl -fsSL \
          "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" \
          | bash -s -- --cleanup \
          || { echo -e "${red}KernelSU-Next cleanup failed!${nocol}"; exit 1; }
    fi

    log_section "To reset repository to pristine state and clean SUSFS patches, run the following command:"
    echo -e "${blue}Warning! Running this command will also reset any uncommited changes that haven't been pushed yet!${nocol}"
    echo
    echo -e "${yellow}git reset --hard HEAD && git clean -xfd${nocol}"
}

# ------------------- # Call and test functions as needed # ------------------------------- # 

main() {
    start
    # Clean previous build artifacts
    clean_kernel
    # Clone necessary repos
    clone
    # Apply patches in correct order
    APPLY_PATCHES
    build_kernel
    zip_kernel
    if [ "$BUILD_MODULES" == "y" ]; then
        build_modules
    fi
    # Final summary and cleanup
    summary
    Final_CLEANUP
}

# Invoke main
main
