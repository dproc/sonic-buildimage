#!/bin/bash
## This script is to generate an ONIE installer image based on a file system overload

## Read ONIE image related config file
. ./onie-image.conf
[ -n "$ONIE_IMAGE_PART_SIZE" ] || {
    echo "Error: Invalid ONIE_IMAGE_PART_SIZE in onie image config file"
    exit 1
}
[ -n "$ONIE_INSTALLER_PAYLOAD" ] || {
    echo "Error: Invalid ONIE_INSTALLER_PAYLOAD in onie image config file"
    exit 1
}

IMAGE_VERSION=$(. functions.sh && sonic_get_version)

generate_onie_installer_image()
{
    # Copy platform-specific ONIE installer config files where onie-mk-demo.sh expects them
    rm -rf ./installer/x86_64/platforms/
    mkdir -p ./installer/x86_64/platforms/
    for VENDOR in `ls ./device`; do
        for PLATFORM in `ls ./device/$VENDOR`; do
            if [ -f ./device/$VENDOR/$PLATFORM/installer.conf ]; then
                cp ./device/$VENDOR/$PLATFORM/installer.conf ./installer/x86_64/platforms/$PLATFORM
            fi

            if [ "$IMAGE_TYPE" = "raw" ] && [ -f ./device/$VENDOR/$PLATFORM/nos_to_sonic_grub.cfg ]; then
                sed -i -e "s/%%IMAGE_VERSION%%/$IMAGE_VERSION/g" ./device/$VENDOR/$PLATFORM/nos_to_sonic_grub.cfg
                echo "IMAGE_VERSION is $IMAGE_VERSION"
            fi
        done
    done

    ## Generate an ONIE installer image
    ## Note: Don't leave blank between lines. It is single line command.
    ./onie-mk-demo.sh $TARGET_PLATFORM $TARGET_MACHINE $TARGET_PLATFORM-$TARGET_MACHINE-$ONIEIMAGE_VERSION \
          installer platform/$TARGET_MACHINE/platform.conf $OUTPUT_ONIE_IMAGE OS $IMAGE_VERSION $ONIE_IMAGE_PART_SIZE \
          $ONIE_INSTALLER_PAYLOAD
}

if [ "$IMAGE_TYPE" = "onie" ]; then
    echo "Build ONIE installer"
    mkdir -p `dirname $OUTPUT_ONIE_IMAGE`
    sudo rm -f $OUTPUT_ONIE_IMAGE

    generate_onie_installer_image

## Build a raw partition dump image using the ONIE installer that can be
## used to dd' in-lieu of using the onie-nos-installer. Used while migrating
## into SONiC from other NOS.
elif [ "$IMAGE_TYPE" = "raw" ]; then

    echo "Build RAW image"
    mkdir -p `dirname $OUTPUT_RAW_IMAGE`
    sudo rm -f $OUTPUT_RAW_IMAGE

    generate_onie_installer_image

    echo "Creating SONiC raw partition : $OUTPUT_RAW_IMAGE of size $RAW_IMAGE_DISK_SIZE MB"
    fallocate -l "$RAW_IMAGE_DISK_SIZE"M $OUTPUT_RAW_IMAGE

    ## Generate a compressed 8GB partition dump that can be used to 'dd' in-lieu of using the onie-nos-installer
    ## Run the installer 
    ## The 'build' install mode of the installer is used to generate this dump.
    sudo chmod a+x $OUTPUT_ONIE_IMAGE
    sudo ./$OUTPUT_ONIE_IMAGE

    [ -r $OUTPUT_RAW_IMAGE ] || {
        echo "Error : $OUTPUT_RAW_IMAGE not generated!"
        exit 1
    }

    gzip $OUTPUT_RAW_IMAGE

    [ -r $OUTPUT_RAW_IMAGE.gz ] || {
        echo "Error : gzip $OUTPUT_RAW_IMAGE failed!"
        exit 1
    }

    mv $OUTPUT_RAW_IMAGE.gz $OUTPUT_RAW_IMAGE
    echo "The compressed raw image is in $OUTPUT_RAW_IMAGE"

## Use 'aboot' as target machine category which includes Aboot as bootloader
elif [ "$IMAGE_TYPE" = "aboot" ]; then
    echo "Build Aboot installer"
    mkdir -p `dirname $OUTPUT_ABOOT_IMAGE`
    sudo rm -f $OUTPUT_ABOOT_IMAGE
    sudo rm -f $ABOOT_BOOT_IMAGE
    ## Add main payload
    cp $ONIE_INSTALLER_PAYLOAD $OUTPUT_ABOOT_IMAGE
    ## Add Aboot boot0 file
    j2 -f env files/Aboot/boot0.j2 ./onie-image.conf > files/Aboot/boot0
    sed -i -e "s/%%IMAGE_VERSION%%/$IMAGE_VERSION/g" files/Aboot/boot0
    pushd files/Aboot && zip -g $OLDPWD/$OUTPUT_ABOOT_IMAGE boot0; popd
    pushd files/Aboot && zip -g $OLDPWD/$ABOOT_BOOT_IMAGE boot0; popd
    echo "$IMAGE_VERSION" >> .imagehash
    zip -g $OUTPUT_ABOOT_IMAGE .imagehash
    zip -g $ABOOT_BOOT_IMAGE .imagehash
    rm .imagehash
    echo "SWI_VERSION=42.0.0" > version
    echo "SWI_MAX_HWEPOCH=1" >> version
    echo "SWI_VARIANT=US" >> version
    zip -g $OUTPUT_ABOOT_IMAGE version
    zip -g $ABOOT_BOOT_IMAGE version
    rm version

    zip -g $OUTPUT_ABOOT_IMAGE $ABOOT_BOOT_IMAGE
    rm $ABOOT_BOOT_IMAGE
else
    echo "Error: Non supported target platform: $TARGET_PLATFORM"
    exit 1
fi
