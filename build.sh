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
echo  # Blank line
echo  # Blank line

# -------------------------------- | Dependencies |--------------------------------------------------------------#
# Uncomment Next 4 lines to install all necessary dependencies for kernel Compiling.

#sudo apt-get update && sudo apt-get install -y \
#  build-essential libncurses-dev bison flex libssl-dev libelf-dev bc \
#  dwarves fakeroot git clang llvm lld lldb \
#  gcc-aarch64-linux-gnu gcc-arm-linux-gnueabihf gcc-arm-linux-gnueabi patch

# ---------------------------------------------------------------------------------------------------------------- #
# ---------------------------| EXPORTS and Directory Setup |------------------------------------------------------ #
KERNEL_DEFCONFIG=gki_defconfig  # Looks for defconfig in arch/<exported_arch>/configs/
ANYKERNEL3_DIR=$PWD/AnyKernel3/ # Required by the function zip_kernel
AK3_REPO="https://github.com/akm-04/AnyKernel3.git"
AK3_BRANCH="dm3q"
MODULES_NAME="Kernel_Modules-Magisk"


# Setup the main directory where build tools are located / will be cloned
# Directory structure under $TOOLCHAIN_DIR:
#
# $TOOLCHAIN_DIR/
# ├── clang-<version>/       # e.g. clang-r547379
# │   └── bin/
# │       └── clang
# ├── gas/
# │   └── linux-x86/          # prebuilt GNU assembler
# └── build-tools/
#     └── path/
#         └── linux-x86/      # Android SDK build-tools
#
TOOLCHAIN_DIR="$HOME/Git/Clang"

# Clang version Setup
CLANG_VERSION=clang-r547379
CLANG_DIR="$TOOLCHAIN_DIR/$CLANG_VERSION"
CLANG_BINARY="$CLANG_DIR/bin/clang"

# An array that stores all make command, edit it as required. These options will be used throughout the script
MAKE_FLAGS=( \
  O=out \
  CC=clang \
  LD=ld.lld \
  LLVM=1 \
  LLVM_IAS=1 \
  "HOSTCFLAGS=-Wno-error=int-conversion -Wno-implicit-function-declaration"
)

# ---------------------------------------------------------------------------- #
#                                Function Options                              #
# ---------------------------------------------------------------------------- #

ARTIFACT="Image.gz"      # Final kernel artifact filename
BUILD_MODULES="n"        # Build modules? (y = yes, n = no)
ENABLE_BREAKPOINTS=0     # Enable script breakpoints for manual steps verification (1 = on, 0 = off)

# ---------------------------------------------------------------------------- #
#                                 SUSFS Patch                                  #
# ---------------------------------------------------------------------------- #

PATCH_SUSFS=1            # Apply SUSFS patch? (1 = yes, 0 = no)
SUSFS_CHECKOUT_HASH=""   # Specific commit SHA after cloning (empty = latest)

# ---------------------------------------------------------------------------- #
#                   KernelSU-Next  |  SUKISU  |  KernelSU                      #
#                (Enable **only one** of the following options)                #
#             Either Enable KernelSU or KernelSU-Next or SukiSU-Ultra.         #
# ---------------------------------------------------------------------------- #

## KernelSU-Next Options
ENABLE_KSU_NEXT=0        # Use KernelSU-Next? (1 = yes, 0 = no)
KSU_NEXT_STABLE=1        # Select stable branch? (1 = stable, 0 = dev)
KSU_NEXT_MANUAL_HOOKS=1  # Hooks style (1 = manual, 0 = kprobes)
KSUN_CHECKOUT_HASH=""    # Specific KernelSU-Next commit SHA

## SUKISU-Ultra Options
ENABLE_SUKISU=0          # Use SUKISU-Ultra? (1 = yes, 0 = no)
SUKI_MANUAL_HOOKS=0      # Manual Hooks for SUKISU (SUSFS version only) (1 = manual, 0 = default)
SUKI_TRACEPOINTS_HOOK=1  # Use tracepoint hook for Sukisu-Ultra (for SUSFS and Normal ver) (1 = enable, 0 = disabled)
SUKI_CHECKOUT_HASH=""    # Specific SUKISU commit SHA
PATCH_KPM=1              # Patches the kernel binary after its done compiling.
KPM_VERSION="0.12.0"     # Release tag of KPM binary

## KernelSU Options     | Note KernelSU-Next removed SUSFS support from their branch
ENABLE_KSU=0             # Use original KernelSU? (1 = yes, 0 = no)
KSU_CHECKOUT_HASH=""     # Specific KernelSU commit SHA

## Apatch Options
# Fetch release tags from here: https://github.com/bmax121/KernelPatch/releases
ENABLE_APATCH=1          # Apply apatch patches? superkey will be asked when patching
APATCH_VER="0.12.0"  # Release tag of Apatch binary
KPTOOLS_VER="0.11.3"     # Release tag of kptools binary

# --------------------- Variable verification and corrections -------------------------------------#

# --- ensure only one KernelSU variant is enabled ---
count=0
enabled_list=""

if [[ "$ENABLE_KSU" == "1" ]]; then
    count=$((count + 1))
    enabled_list="${enabled_list}KernelSU, "
fi

if [[ "$ENABLE_SUKISU" == "1" ]]; then
    count=$((count + 1))
    enabled_list="${enabled_list}SUKISU, "
fi

if [[ "$ENABLE_KSU_NEXT" == "1" ]]; then
    count=$((count + 1))
    enabled_list="${enabled_list}KernelSU-Next, "
fi

if [[ $count -gt 1 ]]; then
    # trim trailing ", "
    enabled_list=${enabled_list%??}
    echo -e "${red}Error:${nocol} Only one KernelSU variant may be enabled. You enabled: ${yellow}${enabled_list}${nocol}" >&2
    exit 1
fi

# ------------- ensure all assigned values are either 1 or 0 ---

if [[ "$ENABLE_KSU_NEXT" != "1" && "$ENABLE_KSU_NEXT" != "0" ]]; then
    echo -e "${yellow}Invalid ENABLE_KSU_NEXT variable value; defaulting to 0${nocol}" >&2
    ENABLE_KSU_NEXT=0
fi

if [[ "$ENABLE_SUKISU" != "1" && "$ENABLE_SUKISU" != "0" ]]; then
    echo -e "${yellow}Invalid ENABLE_SUKISU variable value; defaulting to 0${nocol}" >&2
    ENABLE_SUKISU=0
fi

if [[ "$ENABLE_KSU" != "1" && "$ENABLE_KSU" != "0" ]]; then
    echo -e "${yellow}Invalid ENABLE_KSU variable value; defaulting to 0${nocol}" >&2
    ENABLE_KSU=0
fi

if [[ "$PATCH_SUSFS" != "1" && "$PATCH_SUSFS" != "0" ]]; then
    echo -e "${yellow}Invalid PATCH_SUSFS variable value; defaulting to 0${nocol}" >&2
    PATCH_SUSFS=0
fi

# KernelSU-Next removed SUSFS branches, so if using KernelSU-Next do not apply susfs patches
if [[ "$ENABLE_KSU_NEXT" == "1" ]]; then
    PATCH_SUSFS=0
fi

# If sukisu is not enabled, do not run KPM kernel binary patches
if [[ "$ENABLE_SUKISU" != "1" ]]; then
    PATCH_KPM=0
fi

# Only one type of Hook variant maybe selected
if [[ "$SUKI_MANUAL_HOOKS" == "1" && "$SUKI_TRACEPOINTS_HOOK" == "1" ]]; then
    echo -e "${red}Error:${nocol} Only one type of SUKISU Hook variant may be applied! You enabled both SUKISU Manual Hook and Tracepoint Hook."
    exit 1
fi

# Apatch Verification | Do not apply apatch if KPM patches are selected and sukisu is enabled.
if [[ "$ENABLE_APATCH" == "1" && "$PATCH_KPM" == "1" && "$ENABLE_SUKISU" == "1" ]]; then
    echo -e "${red}Error:${nocol} SUKISU is selected: Apatch and KPM patches cannot be applied at the same time!"
    exit 1
fi

# SUKISU normal version without susfs does not support manual hooks
if [[ "$ENABLE_SUKISU" == "1" && "$PATCH_SUSFS" == "0" ]]; then
    if [[ "$SUKI_MANUAL_HOOKS" == "1" ]]; then
        echo -e "${blue}Note:${nocol} SUKISU normal (no SUSFS) does not support manual hooks — disabling SUKI_MANUAL_HOOKS."
        SUKI_MANUAL_HOOKS=0
    fi
fi
# If no KSU variant is enabled, never apply SUSFS
if [[ "$ENABLE_KSU_NEXT" == "0" && "$ENABLE_SUKISU" == "0" && "$ENABLE_KSU" == "0" ]]; then
    PATCH_SUSFS=0
fi

# -------------------------------------- Cloning Functions and setup enviroment ------------------------------------------------------#

# Toybox patch from build-tools gives issues when applying patches with fuzz.
# So force user debian patch binary
patch() {
#   Replace the path with your patch binary path | find path by running "which patch" in terminal.
#   $ which patch
#   /usr/bin/patch

    /usr/bin/patch "$@"
}
export -f patch

setup_env(){
    log_section "Setup Environment"

    # Ensure all toolchains are present
    clone_clang
    #clone_build_tools
    #clone_gas

    # Now export paths and variables
    #export PATH=$TOOLCHAIN_DIR/build-tools/path/linux-x86:$PATH
    #export PATH=$TOOLCHAIN_DIR/gas/linux-x86:$PATH
    export PATH="$CLANG_DIR/bin:$PATH"
    export KBUILD_COMPILER_STRING="$($CLANG_BINARY --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"

    export ARCH=arm64
    export SUBARCH=ARM64
    export CROSS_COMPILE=aarch64-linux-gnu-
    export CLANG_TRIPLE=aarch64-linux-gnu-
    export CC="$CLANG_DIR/bin/clang"
    export TARGET_SOC=kalama
    export LD=ld.lld
    export LLVM=1
    export LLVM_IAS=1

    echo -e "${green}Environment set up done!${nocol}"
}

clone_clang() {
    log_section "Cloning Clang Function Start"
    if ! [ -d "$CLANG_DIR" ]; then
        echo -e "${yellow}⚠️  Clang directory not found:${nocol} $CLANG_DIR"
        read -p "Press ENTER to clone to this path, or Ctrl+C to abort and edit the script to configure correct cloning directory: "
        echo -e "${red}Cloning clang at $CLANG_DIR ...${nocol}"
        mkdir -p "$CLANG_DIR"
# ----------------------------------------------------
# Link for cloning clang 20+
        if ! wget --show-progress -O "$CLANG_DIR/${CLANG_VERSION}.tar.gz" "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/${CLANG_VERSION}.tar.gz"; then
            echo "${red}Cloning failed! Aborting...${nocol}"
            exit 1
        fi
# ------------------------------------------------------------------------------
# Available clangs on this link 
# clang-3289846/ clang-r399163b/ clang-r416183b/ clang-r416183b1/ clang-r416183c/ clang-r416183c1/ clang-r428724/ clang-r433403/
#        if ! wget --show-progress -O "$CLANG_DIR/${CLANG_VERSION}.tar.gz" "https://android.googlesource.com/platform//prebuilts/clang/host/linux-x86/+archive/1c1069109f294e9ffbdc1ff8541394ab4b5d941d/${CLANG_VERSION}.tar.gz"; then
#            echo "${red}Cloning failed! Aborting...${nocol}"
#            exit 1
#        fi
# ------------------------------------------------------
        echo "${yellow}Cloning successful. Extracting the tar file...${nocol}"
        tar -xzf "$CLANG_DIR/${CLANG_VERSION}.tar.gz" -C "$CLANG_DIR"
        rm "$CLANG_DIR/${CLANG_VERSION}.tar.gz"
    fi

    echo -e "${green}Correct Clang version is cloned and setup at $CLANG_DIR ..${nocol}"
}

clone_gas(){
    log_section "Cloning gas Function Start"
    if ! [ -d "$TOOLCHAIN_DIR/gas/linux-x86" ]; then
        echo -e "${yellow}⚠️  gas directory not found:${nocol} $TOOLCHAIN_DIR/gas/linux-x86"
        read -p "Press ENTER to clone to this path, or Ctrl+C to abort and edit the script to configure correct cloning directory: "
        echo -e "${red}Cloning gas at $TOOLCHAIN_DIR/gas/linux-x86 ...${nocol}"
        mkdir -p "$TOOLCHAIN_DIR/gas"

        if ! git clone https://android.googlesource.com/platform/prebuilts/gas/linux-x86 \
            "$TOOLCHAIN_DIR/gas/linux-x86"; then
            echo -e "${red}Cloning gas failed! Aborting...${nocol}"
            exit 1
        fi

        echo -e "${green}gas successfully cloned!${nocol}"
    else
        echo -e "${green}gas already present at $TOOLCHAIN_DIR/gas/linux-x86${nocol}"
    fi
}

clone_build_tools(){
    log_section "Cloning build-tools Function Start"
    # check for the linux-x86 prebuilts inside build-tools
    if ! [ -d "$TOOLCHAIN_DIR/build-tools/path/linux-x86" ]; then
        echo -e "${yellow}⚠️  build-tools directory not found:${nocol} $TOOLCHAIN_DIR/build-tools/path/linux-x86"
        read -p "Press ENTER to clone to this path, or Ctrl+C to abort and edit the script to configure correct cloning directory: "
        echo -e "${red}Cloning build-tools at $TOOLCHAIN_DIR/build-tools ...${nocol}"
        mkdir -p "$TOOLCHAIN_DIR/build-tools"

        if ! git clone https://android.googlesource.com/platform/prebuilts/build-tools \
                       "$TOOLCHAIN_DIR/build-tools"; then
            echo -e "${red}Cloning build-tools failed! Aborting...${nocol}"
            exit 1
        fi

        echo -e "${green}build-tools successfully cloned!${nocol}"
    else
        echo -e "${green}build-tools already present at $TOOLCHAIN_DIR/build-tools/path/linux-x86${nocol}"
    fi
}


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
    rm -rf "$ANYKERNEL3_DIR/Image"
    rm -rf "$ANYKERNEL3_DIR/Image.gz"
    rm -rf "$ANYKERNEL3_DIR/dtbo.img"

    # Only remove SUSFS sources if we’re patching SUSFS
    if [ "${PATCH_SUSFS:-0}" -eq 1 ]; then
        echo -e "$yellow**** Removing SUSFS folder/patch ****$nocol"
        rm -rf susfs4ksu 50_add_susfs_in_gki-android13-5.15.patch
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

    if [ ! -d "$ANYKERNEL3_DIR" ]; then
        echo -e "${blue}|| AnyKernel3 not found, cloning branch '$AK3_BRANCH'…${nocol}"
        if ! git clone --depth 1 --branch "$AK3_BRANCH" "$AK3_REPO" "$ANYKERNEL3_DIR"; then
            echo -e "${red}❌ Failed to clone AnyKernel3 from $AK3_REPO (branch $AK3_BRANCH). Aborting.${nocol}"
            exit 1
        fi
        echo -e "${green}✅ Cloned AnyKernel3 ($AK3_BRANCH) into $ANYKERNEL3_DIR${nocol}"
    fi

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

    # Apply KPM and apatch patches on generated kernel binary before zipping if selected.
    if [[ "$PATCH_KPM" == "1" ]]; then
        KPM_Patch
    elif [[ "$ENABLE_APATCH" == "1" ]]; then
        APATCH
    else
        echo -e "$yellow**** Copying $ARTIFACT to anykernel 3 folder ****$nocol"
        cp "$KERNELDIR/out/arch/arm64/boot/$ARTIFACT" "$ANYKERNEL3_DIR/"
    fi

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

    if [[ "${ENABLE_APATCH:-0}" == "1" ]]; then
        echo -e "${green}***********************************************${nocol}"
        echo -e "${green}*${nocol} Apatch SUPERKEY: ${nocol}${SUPER_KEY}"
        echo -e "${green}*${nocol} ${yellow}Use: paste this value into the Apatch Manager on-device to gain root access${nocol}"
        echo -e "${green}***********************************************${nocol}"
    fi
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
    clang --version

    #-----------------------Defconfig stuff-----------------------------------
    echo -e "$yellow**** Kernel defconfig is set to $KERNEL_DEFCONFIG ****$nocol"
    echo -e "$blue***********************************************"
    echo "       NOW MAKING _defconfig : $KERNEL_DEFCONFIG        "
    echo -e "***********************************************$nocol"
    #make O=out CC=clang $KERNEL_DEFCONFIG
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
    log_section "Building Modules Now"
    echo -e "Final Module name is set to $MODULES_NAME"
    echo # Blank line
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
            clang --version
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
                DEPMOD=depmod \
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
                DEPMOD=depmod \
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
                DEPMOD=depmod \
                "-j$(nproc)" \
                 2>&1 | tee -a build.log || {
                    echo "Error installing modules"
                    exit 1
            }
            modules_src_dir=$(echo "out/modules/lib/modules"/*)
            KVER=$(basename "$modules_src_dir")
            echo "Detected kernel version: $KVER"
            depmod -b "$KERNELDIR/out/modules" "$KVER"  \
                2>&1 | tee -a build.log
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
        if [[ "$KSU_NEXT_MANUAL_HOOKS" == "1" ]]; then
            log_section "Started Applying KernelSU-Next Manual Hook Patches "
            if ! cp KSUN_Manual-Hooks.diff KSUN_Manual-Hooks.patch; then
                echo -e "${red}Manual hook patch not found in $KERNELDIR ! Aborting.${nocol}"
                exit 1
            fi
            if patch -p1 --fuzz=3 < KSUN_Manual-Hooks.patch; then
                echo -e "${green}KernelSU-Next Manual Hook Patch applied successfully.${nocol}"
                rm -f KSUN_Manual-Hooks.patch
                echo -e "${blue}Disabling KSU_KPROBES_HOOK and other configs in defconfig .... …${nocol}"
                ./scripts/config \
                    --file "arch/${ARCH}/configs/${KERNEL_DEFCONFIG}" \
                    --disable KSU_KPROBES_HOOK
                if [[ "$PATCH_SUSFS" == "1" ]]; then
                    ./scripts/config \
                        --file "arch/${ARCH}/configs/${KERNEL_DEFCONFIG}" \
                        --disable KSU_SUSFS_SUS_SU
                    ./scripts/config \
                        --file "arch/${ARCH}/configs/${KERNEL_DEFCONFIG}" \
                        --disable KSU_SUSFS_ENABLE_LOG
                fi
            else
                echo -e "${red}ERROR: KernelSU-Next Manual Hook Patch did not apply cleanly. Aborting.${nocol}"
                exit 1
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
            echo -e "${blue}Cloning SUKISU-Ultra (SUSFS) main branch and setting it up .... …${nocol}"
            curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s susfs-main
            if [[ -n "$SUKI_CHECKOUT_HASH" ]]; then
                echo -e "${blue}[SUKISU SUSFS main: Checkout hash set, Switching to detached head..] Checking out commit $SUKI_CHECKOUT_HASH…${nocol}"
                (cd KernelSU && git checkout "$SUKI_CHECKOUT_HASH") \
                    || { echo -e "${red}[SUKISU_SUSFS_main:] Checkout $SUKI_CHECKOUT_HASH failed${nocol}"; exit 1; }
                cd "$KERNELDIR" || exit 1
            fi
            echo -e "${green}SUKISU (SUSFS) framework clonning and setup done!.${nocol}"
            if [[ "$PATCH_KPM" == "1" ]]; then
                echo -e "${blue}Enabling KPM in defconfig .... …${nocol}"
                ./scripts/config \
                    --file "arch/${ARCH}/configs/${KERNEL_DEFCONFIG}" \
                    --enable KPM
            fi
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
            if [[ "$PATCH_KPM" == "1" ]]; then
                echo -e "${blue}Enabling KPM in defconfig .... …${nocol}"
                ./scripts/config \
                    --file "arch/${ARCH}/configs/${KERNEL_DEFCONFIG}" \
                    --enable KPM
            fi
            if [[ "$ENABLE_BREAKPOINTS" == "1" ]]; then
                read -p "Breakpoint after Cloning SUKISU Detected! Press Enter to continue..."
            fi
        fi
        if [[ "$SUKI_MANUAL_HOOKS" == "1" ]]; then
            log_section "Started Applying SUKISU Manual Hook Patches "
            if ! cp KSUN_Manual-Hooks.diff KSUN_Manual-Hooks.patch; then
                echo -e "${red}Manual hook patch not found in $KERNELDIR ! Aborting.${nocol}"
                exit 1
            fi
            if patch -p1 --fuzz=3 < KSUN_Manual-Hooks.patch; then
                echo -e "${green}SUKISU Manual Hook Patch applied successfully.${nocol}"
                rm -f KSUN_Manual-Hooks.patch
                echo -e "${blue}Making necessary defconfig changes .... …${nocol}"
                ./scripts/config \
                    --file "arch/${ARCH}/configs/${KERNEL_DEFCONFIG}" \
                    --enable KSU_MANUAL_HOOK
                ./scripts/config \
                    --file "arch/${ARCH}/configs/${KERNEL_DEFCONFIG}" \
                    --disable KSU_DEBUG
                if [[ "$PATCH_SUSFS" == "1" ]]; then
                    ./scripts/config \
                        --file "arch/${ARCH}/configs/${KERNEL_DEFCONFIG}" \
                        --disable KSU_SUSFS_SUS_SU
                    ./scripts/config \
                        --file "arch/${ARCH}/configs/${KERNEL_DEFCONFIG}" \
                        --disable KSU_SUSFS_ENABLE_LOG
                fi
            else
                echo -e "${red}ERROR: SUKISU Manual Hook Patch did not apply cleanly. Aborting.${nocol}"
                exit 1
            fi
        fi
        if [[ "$SUKI_TRACEPOINTS_HOOK" == "1" ]]; then
            log_section "Started Applying SUKISU Tracepoint Hook Patches "
            if ! cp sukisu_tracepoint_hooks.diff sukisu_tracepoint_hooks.patch; then
                echo -e "${red}Tracepoint hook patch not found in $KERNELDIR ! Aborting.${nocol}"
                exit 1
            fi
            if patch -p1 --fuzz=3 < sukisu_tracepoint_hooks.patch; then
                echo -e "${green}SUKISU Tracepoint Hook Patch applied successfully.${nocol}"
                rm -f sukisu_tracepoint_hooks.patch
                echo -e "${blue}Making necessary defconfig changes .... …${nocol}"
                ./scripts/config \
                    --file "arch/${ARCH}/configs/${KERNEL_DEFCONFIG}" \
                    --enable KSU_TRACEPOINT_HOOK
                ./scripts/config \
                    --file "arch/${ARCH}/configs/${KERNEL_DEFCONFIG}" \
                    --disable KSU_DEBUG
                if [[ "$PATCH_SUSFS" == "1" ]]; then
                    ./scripts/config \
                        --file "arch/${ARCH}/configs/${KERNEL_DEFCONFIG}" \
                        --disable KSU_SUSFS_SUS_SU
                    ./scripts/config \
                        --file "arch/${ARCH}/configs/${KERNEL_DEFCONFIG}" \
                        --disable KSU_SUSFS_ENABLE_LOG
                fi
            else
                echo -e "${red}ERROR: SUKISU Tracepoint Hook Patch did not apply cleanly. Aborting.${nocol}"
                exit 1
            fi
        fi
    fi
}

KPM_Patch() {
    log_section "Now applying KPM patch"
    cd $KERNELDIR

    echo -e "$yellow**** Copying generated Image to anykernel 3 folder ****$nocol"
    cp "$KERNELDIR/out/arch/arm64/boot/Image" "$ANYKERNEL3_DIR/"
    cd $ANYKERNEL3_DIR/

    echo -e "$yellow**** Cloning KPM patch binary ****$nocol"
    wget --tries=3 "https://github.com/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/download/${KPM_VERSION}/patch_linux"
    chmod +x patch_linux
    echo -e "$yellow**** Now patching the Kernel Binary with KPM****$nocol"
    echo  # Blank line
    ./patch_linux
    rm -rf Image patch_linux
    mv oImage Image

    if [[ "$ARTIFACT" == "Image.gz" ]]; then
        echo "Compressing Image -> Image.gz"
        gzip -n -k -f -9 ./Image > ./Image.gz
        rm -rf Image
    fi
    cd $KERNELDIR
}

APATCH() {
    log_section "Now applying apatch patches"
    cd $KERNELDIR

    echo -e "$yellow**** Copying generated Image to anykernel 3 folder ****$nocol"
    cp "$KERNELDIR/out/arch/arm64/boot/Image" "$ANYKERNEL3_DIR/"
    cd $ANYKERNEL3_DIR/

    echo -e "$yellow**** Cloning apatch and other needed binaries ****$nocol"
    wget --tries=3 "https://github.com/bmax121/KernelPatch/releases/download/${KPTOOLS_VER}/kptools-linux"
    wget --tries=3 "https://github.com/bmax121/KernelPatch/releases/download/${APATCH_VER}/kpimg-android"
    chmod +x kptools-linux
    echo -e "$yellow**** Now patching the Kernel Binary with APATCH****$nocol"
    echo  # Blank line
    read -rp "Enter a strong SUPERKEY for apatch (atleast 8 characters with letters and numbers): " SUPER_KEY
    echo  # Blank line
    export SUPER_KEY
    ./kptools-linux -p --image Image --skey "${SUPER_KEY}" --kpimg kpimg-android --out oImage
    rm -rf Image kptools-linux kpimg-android
    mv oImage Image

    if [[ "$ARTIFACT" == "Image.gz" ]]; then
        echo "Compressing Image -> Image.gz"
        gzip -n -k -f -9 ./Image > ./Image.gz
        rm -rf Image
    fi
    cd $KERNELDIR
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
    # Setup the enviroment
    setup_env
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
