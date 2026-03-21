#!/bin/sh

# U-Boot configuration script for Spectrum SAX1V1K

# Author: Lanchon (https://github.com/Lanchon)
# Date: 2024-09-18
# License: GPL v3 or newer

# This script builds upon prior scripts by:
# - Paul Francis Nel (https://github.com/MeisterLone/Askey-RT5010W-D187-REV6/blob/master/Patch/open.sh)
# - Connor Yoon (https://github.com/gotofbi/Qualcommax_NSS_sax1v1k/blob/main/open.sh)

# This script can be ran on stock and official OpenWrt firmwares.
# It is designed to either be copied to the device or be directly pasted on a serial or ssh shell.

# WARNING: Some serial terminals (eg: gtkterm) misbehave if a large volume of text is pasted.
# If available, prefer to use commands such as "send file", "send raw file", or equivalent.

# WARNING: The applied U-Boot configuration reads and/or writes to certain partitions during boot:
# - #18 'HLOS' (slot 0 kernel)
# - #19 'HLOS_1' (slot 1 kernel)
# - #36 'rsvd_5' (recovery OS, with last sector used for the boot interrupt flag)
# This script verifies that the GPT is exactly as expected before applying the U-Boot configuration,
# which then accesses these partitions by their absolute sector numbers within the area of the eMMC.
# If you repartition the device afterwards, make sure you do not modify these partitions in any way.

# WARNING: The Spectrum SAX1V1K has secure boot enabled. If Qualcomm's secure boot chain verifies
# the GPT, then any change at all in the GPT will brick the device. (Note that Qualcomm's secure
# boot chain for Android indeed verifies the GPT.)

error() {
  echo
  echo "ERROR:" "$@"
  echo "press ctrl+c to stop..."
  cat > /dev/null
  echo
  exit 1
}

pause() {
  echo "WARNING:" "$@"
  echo "enter 'yes' to continue or ctrl+c to stop..."
  while true; do
    if [[ "$( head -n1 )" == "yes" ]]; then break; fi
  done
  echo
}

# Hashes main GPT skipping header CRCs and partition GUIDs
# Assumes standard GPT size with 128 entries of 128 bytes each
hash_gpt() {
  {
    dd bs=1 count=$(( 0x210 )) 2> /dev/null
    dd bs=1 skip=4 count=0 2> /dev/null     # skip CRC at 0x210
    dd bs=1 count=$(( 0x258 - 0x214 )) 2> /dev/null
    dd bs=1 skip=4 count=0 2> /dev/null     # skip CRC at 0x258
    dd bs=1 count=$(( 0x400 - 0x25c )) 2> /dev/null

    # entries in partition array at 0x400
    n=$(( (0x4400 - 0x400) / 0x80 ))
    while [ $n != 0 ]; do
      dd bs=1 count=$(( 0x10 )) 2> /dev/null
      dd bs=1 skip=16 count=0 2> /dev/null  # skip GUID at 0x10
      dd bs=1 count=$(( 0x60 )) 2> /dev/null
      n=$(( n - 1 ))
    done
  } | md5sum | cut -d' ' -f1
}

configure_uboot() {

echo
echo "starting configuration script..."
echo
echo

# Check GPT

local gpt_hash="$( dd if=/dev/mmcblk0 bs=512 count=34 2> /dev/null | hash_gpt )"
echo "generalized GPT hash: $gpt_hash"

case "$gpt_hash" in
  c91c4fcf647afb683cceab7ac5c54e96)
    break
    ;;
  *)
    error "unknown GPT hash! dump GPT and contact support forum"
    ;;
esac
echo "found known GPT!"
echo

# Check U-Boot

local uboot0_hash="$( cat /dev/mmcblk0p15 | md5sum | cut -d' ' -f1 )"
local uboot1_hash="$( cat /dev/mmcblk0p16 | md5sum | cut -d' ' -f1 )"
echo "U-Boot slot 0 hash: $uboot0_hash"
echo "U-Boot slot 1 hash: $uboot1_hash"

if [[ "$uboot0_hash" != "$uboot1_hash" ]]; then
    error "U-Boot hashes for slots 0 and 1 do not match! contact support forum"
fi
echo "U-Boot hashes for slots 0 and 1 match"

local uboot_ver
local uboot_hack
case "$uboot0_hash" in
  f3066582267c857e24097b4aecd3e9a1)
    uboot_ver="1.3.3 [spf11.1_csu2] Dec 09 2020 (variant f306)"
    uboot_hack="mw 4a910cd0 0a000007 1; mw 4a91dc6c 0a000006 1; go 4a96433c"
    break
    ;;
  ab709449c98f89cfa57e119b0f37b388)
    uboot_ver="1.3.3 [spf11.1_csu2] Jan 27 2021 (variant ab70)"
    uboot_hack="mw 4a911044 0a000007 1; mw 4a91dfdc 0a000006 1; go 4a9647cc"
    break
    ;;
  d75be109e242ee8923cb45f1cb082f83)
    uboot_ver="1.3.3 [spf11.1_csu2] Apr 22 2021 (variant d75b, untested)"
    uboot_hack="mw 4a910f88 0a000007 1; mw 4a91df24 0a000006 1; go 4a964714"
    break
    ;;
  7bc2f7766b270ea120495334cd1e5c56)
    uboot_ver="1.5.0 [spf11.4_csu1] Feb 24 2022 (untested)"
    uboot_hack="mw 4a9115a8 0a000007 1; mw 4a91e514 0a000006 1; go 4a966ba4"
    break
    ;;
  85ae38d2a62b124f431ba5baba6b42ad)
    uboot_ver="1.5.1 [spf11.4_csu2] Jun 15 2022"
    uboot_hack="mw 4a9115c8 0a000007 1; mw 4a91e534 0a000006 1; go 4a966bc4"
    break
    ;;
  baf03dfc53dde25c54a351091ae48b84)
    uboot_ver="1.5.9 [spf11.5_cs] Aug 19 2024 (untested)"
    uboot_hack="mw 4a912258 0a000007 1; mw 4a91f1c8 0a000006 1; go 4a9679f0"
    break
    ;;
  *)
    error "unknown U-Boot hash! dump U-Boot (/dev/mmcblk0p15) and contact support forum"
    ;;
esac
echo "found known U-Boot! version: $uboot_ver"
echo

# Configure U-Boot environment

pause "about to configure U-Boot environment"

if [[ ! -f /etc/fw_env.config ]]; then
  echo "/dev/mmcblk0p14 0x0 0x40000 0x40000 1" > /etc/fw_env.config
fi


## Boot stages

### Stage 1: Allow U-Boot shell access via serial port

fw_setenv boot_stage1 'echo "Hit Ctrl+C for shell..."; sleep 2 || exit; run boot_stage1_ok'
fw_setenv boot_stage1_ok 'run boot_stage2'

### Stage 2: Choose main or recovery OS based on history boot interruptions

fw_setenv boot_stage2 'run boot_stage2_flag_read; run boot_stage2_choose'

fw_setenv boot_stage2_choose 'if itest *43FFFFFC == 0; then BOOT_NUM=1; run boot_stage2_try; elif itest *43FFFFFC == 1; then BOOT_NUM=2; run boot_stage2_try; elif itest *43FFFFFC == 2; then BOOT_NUM=3; run boot_stage2_try; else run boot_stage2_skip; fi'
fw_setenv boot_stage2_try 'run boot_stage2_flag_write; echo; echo "## Info: waiting for boot interrupt #$BOOT_NUM..."; sleep 5 || exit; BOOT_NUM=0; run boot_stage2_flag_write; echo; run boot_stage2_ok'
fw_setenv boot_stage2_skip 'echo "## Info: max boot interrupt count reached"; BOOT_NUM=0; run boot_stage2_flag_write; echo; run boot_stage2_fail'

# Sector 0x509E21 is the last sector of mmcblk0p36 'rsvd_5' (contains the recovery OS and the boot interrupt flag in its last sector):
fw_setenv boot_stage2_flag_read 'mmc read 43FFFE00 0x509E21 1; echo "Current boot interrupt flag:"; md 43FFFFF8 2; if itest *43FFFFF8 != B007F1A6; then echo "## Warning: invalid boot flag"; mw 43FFFFF8 B007F1A6 1; mw 43FFFFFC 0 1; fi'
fw_setenv boot_stage2_flag_write 'mw 43FFFFFC "$BOOT_NUM" 1; echo "Write boot interrupt flag:"; md 43FFFFF8 2; mmc write 43FFFE00 0x509E21 1'

fw_setenv boot_stage2_ok 'run boot_stage3'
fw_setenv boot_stage2_fail 'run boot_stage4'

### Stage 3: Attempt to boot main OS, or continue to recovery OS on error

fw_setenv boot_stage3 'echo "## Info: booting main OS..."; sleep 1 || exit; run boot_main; echo "## Error: main OS boot failed"; echo; run boot_stage3_fail'
fw_setenv boot_stage3_fail 'run boot_stage4'

### Stage 4: Attempt to boot recovery OS, or continue to TFTP boot on error

fw_setenv boot_stage4 'echo "## Info: booting recovery OS..."; sleep 1 || exit; run boot_recovery; echo "## Error: recovery OS boot failed"; echo; run boot_stage4_fail'
fw_setenv boot_stage4_fail 'run boot_stage5'

### Stage 5: Attempt to boot from TFTP server

fw_setenv boot_stage5 'echo "## Info: booting via TFTP..."; sleep 1 || exit; run boot_tftp; echo "## Error: TFTP boot failed"'


## Manual commands

### Control queuing of recovery OS for next boot

fw_setenv boot_queue_recovery 'run boot_stage2_flag_read; BOOT_NUM=FF; run boot_stage2_flag_write'
fw_setenv boot_queue_recovery_cancel 'run boot_stage2_flag_read; BOOT_NUM=0; run boot_stage2_flag_write'

### Boot main OS

fw_setenv boot_main 'if "$boot_active_slot" == "1"; then SLOT=1; else SLOT=0; fi; run boot_slot'

fw_setenv boot_slot 'run boot_set_slot_$SLOT || exit; run boot_set_type_squashfs; run boot_hack; mmc read 44000000 "$KERNEL" 0x4000 && bootm'
# Sector 0x8A22 is the start of mmcblk0p18 'HLOS' (contains the slot 0 kernel):
fw_setenv boot_set_slot_0 'KERNEL=0x8A22; ROOTFS=/dev/mmcblk0p20; OVERLAY=rootfs_data'
# Sector 0xCA22 is the start of mmcblk0p19 'HLOS_1' (contains the slot 1 kernel):
fw_setenv boot_set_slot_1 'KERNEL=0xCA22; ROOTFS=/dev/mmcblk0p22; OVERLAY=rootfs_data_1'

### Boot recovery OS

# Sector 0x4F9E22 is the start of mmcblk0p36 'rsvd_5' (contains the recovery OS and the boot interrupt flag in its last sector):
fw_setenv boot_recovery 'run boot_set_type_initramfs; run boot_hack; mmc read 44000000 0x4F9E22 0x10000 && bootm'

### Boot from TFTP server

fw_setenv boot_tftp 'run boot_set_type_initramfs; run boot_set_ip; run boot_hack; echo; echo "## Info: waiting for network..."; sleep 5 || exit; tftpboot recovery.img && bootm'

### Write recovery OS partition from TFTP server

# Sector 0x4F9E22 is the start of mmcblk0p36 'rsvd_5' (contains the recovery OS and the boot interrupt flag in its last sector):
fw_setenv boot_write_recovery_from_tftp 'run boot_set_type_initramfs; run boot_set_ip; run boot_hack; sleep 5 || exit; tftpboot recovery.img || exit; echo; echo "WILL WRITE RECOVERY IN 30s..."; sleep 30 || exit; mmc write 44000000 0x4F9E22 0x10000'


## Shared auxiliary functions

fw_setenv boot_set_ip 'setenv ipaddr 192.168.1.1; setenv netmask 255.255.255.0; setenv serverip 192.168.1.2'

fw_setenv boot_set_type_initramfs 'setenv loadaddr 44000000; setenv bootargs console=ttyMSM0,115200n8 $EXTRAARGS'
fw_setenv boot_set_type_squashfs 'setenv loadaddr 44000000; setenv bootargs console=ttyMSM0,115200n8 root=$ROOTFS rootwait fstools_overlay_name=$OVERLAY $EXTRAARGS'


## U-Boot hack (WARNING: depends on U-Boot version!)

fw_setenv boot_hack "$uboot_hack"


echo "success!"
echo
echo

# Configure 'bootcmd'

local bootcmd="run boot_stage1"

if [[ "$( fw_printenv bootcmd )" != "bootcmd=$bootcmd" ]]; then

  echo "the new boot code has been configured but not activated"
  echo
  echo "the current boot command is:"
  fw_printenv bootcmd
  echo
  echo "to activate the new code, it needs to be set to:"
  echo "bootcmd=$bootcmd"
  echo

  pause "about to set 'bootcmd' to activate the new code"

  fw_setenv bootcmd "$bootcmd"

  echo "success!"
  echo
  echo

fi

# Clean up old boot code

if fw_printenv setup_and_boot > /dev/null 2>&1; then

  echo "it seems that this device has older boot code configured"
  echo
  echo "the code in these U-Boot variables is no longer needed:"
  echo "  fix_uboot, read_hlos_emmc, set_custom_bootargs, setup_and_boot"
  echo

  pause "do you want to delete this variables? (recommended)"

  fw_setenv fix_uboot
  fw_setenv read_hlos_emmc
  fw_setenv set_custom_bootargs
  fw_setenv setup_and_boot

  echo "success!"
  echo
  echo

fi

# Notes

echo "notes:"
echo
echo "this script does NOT install main or recovery OSes"
echo "you have to do that yourself to complete the installation"
echo
echo "if you have serial console access you can type:"
echo "- 'ctrl+c' during boot to access the U-Boot shell"
echo "- 'run boot_tftp' to boot via TFTP"
echo "- 'run boot_write_recovery_from_tftp' to flash the recovery OS"
echo "- 'run boot_recovery' to boot the recovery OS now"
echo "- 'run boot_queue_recovery' to queue recovery for next boot"
echo
echo "in OpenWrt you can flash a recovery image by typing:"
echo "- 'dd if=recovery.img of=/dev/mmcblk0p36'"
echo
echo

}

configure_uboot "$@"

