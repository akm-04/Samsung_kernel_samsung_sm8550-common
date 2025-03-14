#!/bin/bash

#set -e

BUILD_START=$(date +"%s")
blue='\033[1;34m'
yellow='\033[1;33m'
nocol='\033[0m'
green='\033[1;32m'
red='\033[1;31m'
MAKE_MODULE=0      # This flag is used to disable generating modules permanently
KERNELDIR=$PWD
# Speed up build process
MAKE="./makeparallel"


echo -e " $yellow #####|               AOSP-Nethunter_build.sh                |########$nocol "
echo -e " $yellow #####|     Choose Correct options as required when asked    |##########$nocol "
echo -e " $yellow #####| To use specific AOSP clang version, edit this script |######$nocol "
echo -e " $yellow #####|            and specify correct clang version         |#####$nocol "

KERNEL_DEFCONFIG=gki_defconfig
ANYKERNEL3_DIR=$PWD/AnyKernel3/
export ARCH=arm64
export SUBARCH=ARM64
CLANG_BINARY="$CLANG_DIR/bin/clang"
CLANG_VERSION=clang-r450784e
CC_CLANG=clang
CLANG_DIR="/home/akm/Git/Clang/$CLANG_VERSION"
export PATH="$CLANG_DIR/bin:$PATH"
export KBUILD_COMPILER_STRING="$($CLANG_BINARY --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"

# Define variable to hold the name of the kernel artifact
ARTIFACT="Image.gz"

clone() {
    if ! [ -d "$CLANG_DIR" ]; then
        echo "Clang not found! Cloning..."
        mkdir -p "$CLANG_DIR"
        if ! wget --show-progress -O "$CLANG_DIR/${CLANG_VERSION}.tar.gz" "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/${CLANG_VERSION}.tar.gz"; then
            echo "Cloning failed! Aborting..."
            exit 1
        fi
        echo "Cloning successful. Extracting the tar file..."
        tar -xzf "$CLANG_DIR/${CLANG_VERSION}.tar.gz" -C "$CLANG_DIR"
        rm "$CLANG_DIR/${CLANG_VERSION}.tar.gz"
    fi
}

initializeTest() {
    # Prompt for module-only compilation
    while true; do
        read -rp "Do you want to only compile the Modules? (y or n): " MOD_ONLY
        case $MOD_ONLY in
        [Yy]*)
            BUILD_MODULES="y"
            FINAL_KERNEL_ZIP=null
            read -rp "Enter the final module zip name: " MODULES_NAME
            break
            ;;
        [Nn]*)
            BUILD_MODULES="n"
            break
            ;;
        *)
            echo "Please enter 'y' or 'n'."
            ;;
        esac
    done

    # Prompt for the final kernel zip name
    while [ "$MOD_ONLY" != "y" ]; do
        read -rp "Enter the desired name for the final kernel zip file (<kernel_name>.zip): " FINAL_KERNEL_ZIP
        if [ -z "$FINAL_KERNEL_ZIP" ]; then
            echo "Please enter a valid name for the final kernel zip file."
        else
            break
        fi
    done

    # Prompt for building modules if not MOD_ONLY
    if [ "$MOD_ONLY" != "y" ]; then
        while true; do
            read -rp "Do you want to build modules? (y/n): " BUILD_MODULES
            case $BUILD_MODULES in
            [Yy]*)
                # Prompt for the final module zip name
                while true; do
                    read -rp "Enter the final module zip name: " MODULES_NAME
                    if [ -z "$MODULES_NAME" ]; then
                        echo "Please enter a valid name for the final module zip file."
                    else
                        break
                    fi
                done
                break
                ;;
            [Nn]*)
                MODULES_NAME=null
                break
                ;;
            *)
                echo "Please enter 'y' or 'n'."
                ;;
            esac
        done
    fi
}

clean_kernel() {
    cd $KERNELDIR
    # Always do clean build lol
    echo -e "$yellow**** Cleaning / Removing 'out' folder ****$nocol"
    # make clean             # Can cause issues
    # make mrproper  # Can cause issues
    rm -rf out
    mkdir -p out
    # make O=out clean       # Unnecessary after running rm -rf out
    # make O=out mrproper    # Unnecessary

    echo -e "$yellow**** Removing 'Mod' and 'libufdt' folders ****$nocol"
    rm -rf Mod
    rm -rf "$KERNELDIR/scripts/ufdt/libufdt"

    echo -e "$yellow**** Cleaning 'AnyKernel3' folder / any previous builds ****$nocol"
    rm -f "$ANYKERNEL3_DIR"/*.zip
    rm -rf $ANYKERNEL3_DIR/$ARTIFACT
    rm -rf $ANYKERNEL3_DIR/dtbo.img
}

build_kernel() {
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
    make O=out \
        CC="$CC_CLANG" \
        LD=ld.lld \
        LLVM=1 \
        LLVM_IAS=1 \
        $KERNEL_DEFCONFIG \
        -j$(nproc) 2>&1 | tee build.log

    #------------------------Kernel Stuff-------------------------------------
    echo -e "$blue***********************************************"
    echo "         NOW COMPILING KERNEL!                  "
    echo -e "***********************************************$nocol"

    make O=out \
        CC="$CC_CLANG" \
        LD=ld.lld \
        LLVM=1 \
        LLVM_IAS=1 \
        -j$(nproc) 2>&1 | tee build.log

    #---------------------------Build Summary------------------------------------
    BUILD_MID=$(date +"%s")
    MID_DIFF=$(($BUILD_MID - $BUILD_START))
    echo -e "$yellow Kernel Compiled in $(($MID_DIFF / 60)) minute(s) and $(($MID_DIFF % 60)) seconds.$nocol"
}

build_modules() {
    cd $KERNELDIR
    # Build modules if selected by the user
    if [ "$BUILD_MODULES" == "y" ]; then
        echo -e "|| Copying NetErnel_modules folder From $KERNELDIR ||"
        
        if [ -d "$KERNELDIR/NetErnel_modules" ]; then
            cp -r "$KERNELDIR/NetErnel_modules" "$KERNELDIR/Mod" || {
                echo -e "$red**** Error: Failed to copy 'NetErnel_modules' to 'Mod' folder. ****$nocol"
                exit 1
            }
        else
            echo -e "$red**** Error: 'NetErnel_modules' folder not found in the kernel root directory. ****$nocol"
            exit 1
        fi

        if [ "$MAKE_MODULE" == "0" ]; then
            echo -e "$blue***********************************************"
            echo "         NOW Compiling Modules!                 "
            echo -e "***********************************************$nocol"

            echo -e "$green*** Using this Clang Version to compile module*** $nocol"
            $CC_CLANG --version
            echo -e "$yellow**** Kernel defconfig is set to $KERNEL_DEFCONFIG ****$nocol"
            echo -e "$blue***********************************************"
            echo "       NOW MAKING _defconfig : $KERNEL_DEFCONFIG        "
            echo -e "***********************************************$nocol"
            make O=out \
                CC="$CC_CLANG" \
                LD=ld.lld \
                LLVM=1 \
                LLVM_IAS=1 \
                $KERNEL_DEFCONFIG \
                -j$(nproc) 2>&1 | tee build.log
            echo -e "$yellow**** Preparing Modules ****$nocol"
            make O=out \
                CC="$CC_CLANG" \
                LD=ld.lld \
                LLVM=1 \
                LLVM_IAS=1 \
                modules_prepare || {
                echo "Error preparing modules"
                exit 1
            }

            echo -e "$yellow**** Building Modules ****$nocol"
            make O=out \
                CC="$CC_CLANG" \
                LD=ld.lld \
                LLVM=1 \
                LLVM_IAS=1 \
                modules INSTALL_MOD_PATH="$KERNELDIR"/out/modules || {
                echo "Error building modules"
                exit 1
            }
            echo -e "$yellow**** Installing Modules ****$nocol"

            make O=out \
                CC="$CC_CLANG" \
                LD=ld.lld \
                LLVM=1 \
                LLVM_IAS=1 \
                modules_install INSTALL_MOD_PATH="$KERNELDIR"/out/modules || {
                echo "Error installing modules"
                exit 1
            }
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

zip_kernel() {
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

    # Generate today's date and time in the format YYYYMMDD_HHMMSS
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

    # Append timestamp to the final kernel zip file name
    FINAL_KERNEL_ZIP_WITH_TIMESTAMP="${FINAL_KERNEL_ZIP%.*}_${TIMESTAMP}.zip"

    echo -e "$yellow**** Copying $ARTIFACT to anykernel 3 folder ****$nocol"
    cp "$KERNELDIR/out/arch/arm64/boot/$ARTIFACT" "$ANYKERNEL3_DIR/"
    
    if [ $BUILD_DTBOIMG = "1" ]
    then
        echo -e "$yellow**** Copying dtbo.img to anykernel 3 folder ****$nocol"
        cp "$KERNELDIR"/out/arch/arm64/boot/dtbo.img $ANYKERNEL3_DIR/dtbo.img
    fi

    echo -e "$green**** Time to zip up! ****$nocol"
    cd $ANYKERNEL3_DIR/
    zip -r9 $FINAL_KERNEL_ZIP_WITH_TIMESTAMP * -x README $FINAL_KERNEL_ZIP_WITH_TIMESTAMP
    #cp $ANYKERNEL3_DIR/$FINAL_KERNEL_ZIP_WITH_TIMESTAMP $KERNELDIR/$FINAL_KERNEL_ZIP_WITH_TIMESTAMP

    echo -e "$green**** Done, generated flashable zip successfully ****$nocol"

    # Output the location of the generated zip file
    echo -e "$green**** Generated Zip File Location: $KERNELDIR/Anykernel3/$FINAL_KERNEL_ZIP_WITH_TIMESTAMP ****$nocol"

    cd ..
}

summary() {
    echo -e "$blue***********************************************"
            echo "         Summary for the Entire Build                 "
            echo -e "***********************************************$nocol"

    echo -e "$green**** Done, here is your checksum and other info ****$nocol"
    BUILD_END=$(date +"%s")
    DIFF=$(($BUILD_END - $BUILD_START))
    echo -e "$green Full Build completed in $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds.$nocol"
    echo -e "$green**** Generated Zip File Location: $KERNELDIR/Anykernel3/$FINAL_KERNEL_ZIP_WITH_TIMESTAMP ****$nocol"
    echo -e "$green**** Checksum for kernel zip ****$nocol"
    sha1sum "$KERNELDIR/AnyKernel3/$FINAL_KERNEL_ZIP_WITH_TIMESTAMP"

    [ -n "$MOD_NAME" ] && echo -e "$green**** Checksum for Module zip ****$nocol" && sha1sum "$KERNELDIR/Mod/$MOD_NAME" && echo -e "$green**** Generated Module Zip File Location: $KERNELDIR/Mod/$MOD_NAME ****$nocol"
}

# Call and test functions as needed

# Function to clone the AOSP Clang (specify directory first!!)
clone

main() {
    initializeTest
    clean_kernel

    if [ "$MOD_ONLY" == "n" ]; then
        build_kernel
        zip_kernel
    fi

    build_modules
    summary
}

# Call the main function to start execution
main



