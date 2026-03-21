# Unbrickable Boot for Spectrum SAX1V1K

This repository contains a U-Boot configuration script to safely run official OpenWrt on the Spectrum SAX1V1K.

Because this device has secure boot enabled, the boot process cannot be interrupted.
This meant that any failed upgrade of OpenWrt (due to interruption, a bug in the image, etc) could not be recovered and instantly turned the device into a brick.
Such a brick could only be recovered via JTAG; serial access could not do the trick.
This new U-Boot configuration script fixes these issues and allows trivial recovery, even without serial access.

This script builds upon prior scripts by:
- [Paul Francis Nel](https://github.com/MeisterLone/Askey-RT5010W-D187-REV6/blob/master/Patch/open.sh)
- [Connor Yoon](https://github.com/gotofbi/Qualcommax_NSS_sax1v1k/blob/main/open.sh)

> [!IMPORTANT]
> There has been a major upgrade to the loader script.
> The old version kept track of boot attempts and triggered recovery after a number of consecutive interrupted boots were detected.
> The new version instead uses the state of the RESET button to choose a boot path.
> 
> U-Boot on this device does not support the `gpio` command which is typically used to read button states,
> but the script solves this issue by accessing the TLMM GPIO controller hardware directly.
> For reference, the old version of the script that detects boot interrupts is available in the
> [`boot-interrupt`](https://github.com/Lanchon/openwrt-sax1v1k/tree/boot-interrupt) branch.

## The U-Boot Configuration Script

The script is intended to be run:
- under stock firmware during initial installation of OpenWrt (untested by me, but should work)
- under official OpenWrt firmware to upgrade the U-Boot configuration (tested)

> [!WARNING]
> The applied U-Boot configuration reads and/or writes to certain partitions during boot:
> - #18 `HLOS` (slot 0 kernel)
> - #19 `HLOS_1` (slot 1 kernel)
> - #36 `rsvd_5` (recovery OS)
> 
> This script verifies that the GPT is exactly as expected before applying the U-Boot configuration,
> which then accesses these partitions during boot by their absolute sector numbers within the area of the eMMC.
> **If you repartition the device afterwards, make sure you do not modify these partitions in any way.**

> [!WARNING]
> The Spectrum SAX1V1K has secure boot enabled.
> If Qualcomm's secure boot chain verifies the GPT, then any change at all in the GPT will brick the device.
> (Note that Qualcomm's secure boot chain for Android indeed verifies the GPT.)

## The Loader Script

The applied U-Boot configuration includes a loader script that behaves as follows:
- Lets you interrupt the boot sequence via the serial console, dropping you to U-Boot shell.
- Tries to boot in sequence:
  - the main OS (a regular OpenWrt image)
  - the recovery OS (an initramfs image)
  - an OS image provided via TFTP
- Lets you force a recovery OS boot (or TFTP boot if that fails) at any time without serial access.

The loader script now supports dual firmware slots, complete with dual overlay filesystems.
However, official OpenWrt does not yet support A/B dual firmware sysupgrades for this device.
This support could be added later, but it would require an OpenWrt version newer than 25.12 series.

### The Boot Sequence

The loader script provides a brief window in which you can type Ctrl+C on the serial console to interrupt the boot sequence and drop to U-Boot shell.

The device LED flashes along during normal boot.
To force a non-standard boot, hold down the RESET button while you power up the device until the LED displays a solid blue color.
At this point the boot process has been paused: release RESET and the device will turn off the LED and wait.

Now you can:
- Either click RESET to boot the recovery OS.
- Or hold down RESET to switch the currently active firmware slot before booting the main OS.
  (This allows you to roll back an upgrade, assuming that the main OS supports A/B upgrades.)

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
5. Type `reboot`, then interrupt the boot sequence early when you see the prompt "Hit Ctrl+C for shell..."; you have 2 seconds for that. You are now in the U-Boot shell.
6. Use a device (eg: your PC) that has a wired Ethernet connection. Set its IP address to `192.168.1.2` and connect it to a LAN port on the router.
7. Run a TFTP server on it. Host an OpenWrt initramfs image on the server, naming it `recovery.img`.
8. Type `run boot_write_recovery_from_tftp` on the serial console to have the router download the recovery OS and write it to the recovery partition.
   You should see the message "WILL WRITE RECOVERY IN 30s..." if the download succeeded; just wait for the script to finish.
9. Reboot the router. You should see it failing to boot the main OS, then falling back to the recovery OS and succeeding.
   (If the recovery OS is correctly installed, you should not see it attempting a TFTP boot.)
   With the recovery OS running, use your browser to access LuCI at `http://192.168.1.1/`.
   Go to `System`/`Backup / Flash Firmware` and hit `Flash image...` to flash an OpenWrt sysupgrade image as the main OS. Choose to wipe settings during the flash.
10. Reboot the router and verify that it boots the main OS successfully.

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

- Boot an OS:
  - `run boot_main`: boot the main OS
  - `run boot_recovery`: boot the recovery OS
  - `run boot_tftp`: boot via TFTP

- Boot a specific slot of the main OS:
  - `SLOT=0; run boot_slot`: boot slot 0
  - `SLOT=1; run boot_slot`: boot slot 1

- Flash the recovery OS:
  - `run boot_write_recovery_from_tftp`: flash the recovery OS from a TFTP server

Note that you can configure the IP addresses used for TFTP by editing the `boot_set_ip` variable, but this change will be overwritten if you later upgrade the U-Boot configuration.

## Internals

The recovery OS is stored in `/dev/mmcblk0p36` which is an unused 32 MiB partition with label `rsvd_5`. In stock firmware this partition is empty (all bytes are `0xFF`).

[This OpenWrt PR](https://github.com/openwrt/fstools/pull/9) was finally merged, and the loader now correctly supports dual firmware slots, complete with dual overlay filesystems.
It is now possible to develop OpenWrt support for A/B dual firmware sysupgrades.
OpenWrt can detect loader support for dual firmware by cheking that the `boot_dual_slot_support` U-Boot variable is set to `1`.
If dual firmware slots are enabled, the currently active boot slot (`0` or `1`) is stored in the `boot_active_slot` U-Boot variable.
Dual firmware support can be disabled by clearing these two variables.


