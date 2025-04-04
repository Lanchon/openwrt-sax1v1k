# Unbrickable Boot for Spectrum SAX1V1K

This repository contains a U-Boot configuration script to safely run official OpenWrt on the Spectrum SAX1V1K.

Because this device has secure boot enabled, the boot process cannot be interrupted.
This meant that any failed upgrade of OpenWrt (due to interruption, a bug in the image, etc) could not be recovered and instantly turned the device into a brick.
Such a brick could only be recovered via JTAG; serial access could not do the trick.
This new U-Boot configuration script fixes these issues and allows trivial recovery, even without serial access.

This script builds upon prior scripts by:
- [Paul Francis Nel](https://github.com/MeisterLone/Askey-RT5010W-D187-REV6/blob/master/Patch/open.sh)
- [Connor Yoon](https://github.com/gotofbi/Qualcommax_NSS_sax1v1k/blob/main/open.sh)

## The U-Boot Configuration Script

The script is intended to be run:
- under stock firmware during initial installation of OpenWrt (untested by me, but should work)
- under official OpenWrt firmware to upgrade the U-Boot configuration (tested)

**WARNING:** The applied U-Boot configuration reads and/or writes to certain partitions during boot:
- #18 `HLOS` (slot 0 kernel)
- #19 `HLOS_1` (slot 1 kernel)
- #36 `rsvd_5` (recovery OS, with last sector used for the boot interrupt flag)

This script verifies that the GPT is exactly as expected before applying the U-Boot configuration,
which then accesses these partitions during boot by their absolute sector numbers within the area of the eMMC.
**If you repartition the device afterwards, make sure you do not modify these partitions in any way.**

**WARNING:** The Spectrum SAX1V1K has secure boot enabled.
If Qualcomm's secure boot chain verifies the GPT, then any change at all in the GPT will brick the device.
(Note that Qualcomm's secure boot chain for Android indeed verifies the GPT.)

## The Loader Script

The applied U-Boot configuration includes a loader script that behaves as follows:
- Lets you interrupt the boot sequence via the serial console, dropping you to U-Boot shell.
- Tries to boot in sequence:
  - the main OS (a regular OpenWrt image)
  - the recovery OS (an initramfs image)
  - an OS image provided via TFTP
- Lets you force a recovery OS boot (or TFTP boot if that fails), at any time and without serial access.

### Safety

The loader does some minimal writing to the eMMC during each boot. This is safe for the following reasons:
- The loader never writes to the U-Boot environment. Thus, bricking by U-Boot environment corruption due to interrupted writes is impossible.
- It only writes to the last sector of the recovery OS partition, and automatically recovers from eventual corruption in this sector.
- There is no issue with flash wear:
  - Writing to small MTD partitions often can potentially wear them out quickly. But eMMCs work differently, they do wear-leveling on the complete flash area via their embedded FTL.
  - Small volume writes to an eMMC are completely safe, just as OpenWrt mounting the read/write overlay on every boot, or booting a regular PC with an SSD.

### The Boot Sequence

During boot you will see this sequence of flashes on the device LED:
- 3x 1-second LED flashes: early boot.
- 2-second LED OFF: wait for shell request.
  - Type Ctrl+C on the serial console during this stage to interrupt the boot sequence and gain access to the U-Boot shell.
- 5-second LED ON: wait for boot interrupt.
  - Unplug the device (or type Ctrl+C on the console) during this stage to signal a "boot interrupt" (see below).
- More LED flashing as the device continues to boot.

In order to boot the recovery OS without serial access (or boot via TFTP if the recovery OS image is corrupt or missing), you need to **force three boot interrupts in a row**.
Any non-interrupted boot will reset the count. After 3 consecutive boot interrupts, the next boot will skip the 5-second LED ON stage and boot to recovery (or via TFTP if recovery is missing or corrupt).
After this single recovery boot, the device will revert to booting the main OS normally.

### TFTP Boot

The configuration for TFTP boot is as follows:

- Router IP: `192.168.1.1`
- Server IP: `192.168.1.2`
- Netmask: `255.255.255.0`
- Filename: `recovery.img`

## Installation

Run the `configure-uboot.sh` script on the device. You can copy it to the device and run it locally, or paste it on a serial terminal or SSH shell.

**WARNING:** Some serial terminals (eg: `gtkterm`) misbehave if a large volume of text is pasted.
If available, prefer to use commands such as "send file", "send raw file", or equivalent.

### Initial Installation of OpenWrt

You can run this script under stock firmware during initial installation of OpenWrt.

Follow these installation steps:

1. Disassemble the router and connect to its serial console.
2. Boot the router and wait until it outputs "VERIFY_IB: Success. verify IB ok".
3. Hit enter to login with these credentials:
   - Username: `root`
   - Password: the serial number of the router in all caps
4. Once logged in, use a terminal command to send the raw `configure-uboot.sh` file; the script will start executing when fully transferred.
   (You can also paste its contents to the terminal instead, but see the warning above.
   Or you can copy the script to the router, `chmod +x` it, and execute it.)
   Follow the prompts and the U-Boot configuration should be installed.
5. (If step 4 fail) If the `configure-uboot.sh` failed due to unknown bootloder: First, determine which partition contains the known bootloader by checking their hashes:
   ```sh
   cat /dev/mmcblk0p15 | md5sum | cut -d' ' -f1
   cat /dev/mmcblk0p16 | md5sum | cut -d' ' -f1
   ```
   - If partition 15 is the correct one, copy it to partition 16:
   ```sh
   dd if=/dev/mmcblk0p15 of=/dev/mmcblk0p16
   ```
   - If partition 16 is the correct one, copy it to partition 15:
   ```sh
   dd if=/dev/mmcblk0p16 of=/dev/mmcblk0p15
   ```
   After copying, verify the hashes again to ensure correctness, then reboot the router. Reboot the router and do Step 4 again. If step 4 is successful then,
6. Type `reboot`, then interrupt the boot sequence early when you see the prompt "Hit Ctrl+C for shell..."; you have 2 seconds for that. You are now in the U-Boot shell.
7. Use a device (eg: your PC) that has a wired Ethernet connection. Set its IP address to `192.168.1.2` and connect it to a LAN port on the router.
8. Run a TFTP server on it. Host an OpenWrt initramfs image on the server, naming it `recovery.img`. (Download the Karnel bin file from the https://firmware-selector.openwrt.org and rename it to recovery.img)
9. Type `run boot_write_recovery_from_tftp` on the serial console to have the router download the recovery OS and write it to the recovery partition.
   You should see the message "WILL WRITE RECOVERY IN 30s..." if the download succeeded; just wait for the script to finish.
10. Reboot the router. You should see it failing to boot the main OS, then falling back to the recovery OS and succeeding.
   (If the recovery OS is correctly installed, you should not see it attempting a TFTP boot.)
   With the recovery OS running, use your browser to access LuCI at `http://192.168.1.1/`.
   Go to `System`/`Backup / Flash Firmware` and hit `Flash image...` to flash an OpenWrt sysupgrade image as the main OS. Choose to wipe settings during the flash.
11. Reboot the router and verify that it boots the main OS successfully.

### U-Boot Configuration Upgrade

You can also run this script under official OpenWrt firmware at any time, to upgrade the U-Boot configuration of the router to the latest version.
In this case serial access is not needed.
Just connect to the router via SSH, paste the contents of the `configure-uboot.sh` file on the terminal, and follow the prompts.
(Or you could copy the script to the router and run it from there.)

But if you are upgrading from an older U-Boot configuration that does not support recovery, then you do not have a recovery OS installed.
In that case, follow the procedure outlined in the next section.

### Upgrading the Recovery OS

This is not recommended unless your recovery OS is missing or corrupt. You do not want the latest OS version for recovery, as it may have some fatal issue.
You want your old trusty recovery that you already tested before and worked.

To upgrade or install the recovery OS:

1. Using SCP, transfer the desired OpenWrt initramfs image to the router, saving it as file `/tmp/recovery.img`
2. SSH to the router.
3. Type `blkdiscard -f /dev/mmcblk0p36`.
   (If you do not have the `blkdiscard` command already installed on the router, just ignore this optional cleanup step and continue.)
4. Type `dd if=/tmp/recovery.img of=/dev/mmcblk0p36`.

## U-Boot Shell Commands

If you connect to the serial console and drop to the U-Boot shell, you have several commands available:

- Control queuing of recovery OS for next boot:
  - `run boot_queue_recovery`: queue recovery on next boot
  - `run boot_queue_recovery_cancel`: cancel the pending recovery request

- Boot an OS:
  - `run boot_main`: boot the main OS
  - `run boot_recovery`: boot the recovery OS
  - `run boot_tftp`: boot via TFTP

- Boot a specific slot of the main OS (but see [this](https://github.com/openwrt/fstools/pull/9)):
  - `SLOT=0; run boot_slot`: boot slot 0
  - `SLOT=1; run boot_slot`: boot slot 1

- Flash the recovery OS:
  - `run boot_write_recovery_from_tftp`: flash the recovery OS from a TFTP server

Note that you can configure the IP addresses used for TFTP by editing the `boot_set_ip` variable, but this change will be overwritten if you later upgrade the U-Boot configuration.

## Internals

The recovery OS is stored in `/dev/mmcblk0p36` which is an unused 32 MiB partition with label `rsvd_5`. In stock firmware this partition is empty (all bytes are `0xFF`).

The last 8 bytes of the last sector of this partition is where the boot interrupt flag is stored.
It is used to keep track of interrupted boots and divert to recovery after the third consecutive interruption.

When the boot interrupt flag is valid, it contains the 32-bit words `B007F1A6 000000nn`, where `nn` is the number of consecutive interrupted boots experienced so far.
(The 2 words are written as 8 little endian bytes, ie: `A6 F1 07 B0  nn 00 00 00`.)
You can schedule a recovery boot for next boot by writing the 32-bit words `B007F1A6 000000FF` to the flag, and cancel it by writing `B007F1A6 00000000`.

Until [this OpenWrt issue](https://github.com/openwrt/fstools/pull/9) is resolved, the loader will not support A/B (a.k.a. dual slot, dual firmware) sysupgrades.

