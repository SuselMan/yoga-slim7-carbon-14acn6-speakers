# Bass speakers on Lenovo Yoga Slim 7 Carbon 14ACN6 (Linux)

On Linux, the Yoga Slim 7 Carbon 14ACN6 (82L0, Ryzen 5000) only plays through
its two tweeters. The two bass speakers stay silent and the sound is thin and flat.
This repository makes all four speakers work, with the same speaker protection
and tuning that Windows uses.

Known reports: [kernel bugzilla 215632](https://bugzilla.kernel.org/show_bug.cgi?id=215632),
[Lenovo forum](https://forums.lenovo.com/t5/Ubuntu/Yoga-Slim-7-Carbon-14ACN6-Linux-Audio/m-p/5158856),
[milkovsky/Linux-on-Lenovo-Slim-7-Carbon-AMD](https://github.com/milkovsky/Linux-on-Lenovo-Slim-7-Carbon-AMD#speakers).

**Status:** works on Kubuntu 24.04 with kernel 7.0 (the Ubuntu HWE kernel).
It needs no kernel rebuild and no custom modules.

## Requirements

- Yoga Slim 7 Carbon 14ACN6, model 82L0. The Realtek ALC287 codec reports subsystem id `17aa:3856`.
- Secure Boot **disabled**. Loading ACPI tables from the initrd is blocked under kernel lockdown.
- Kernel 6.8 or newer. Tested on 7.0.
- GRUB. systemd-boot and other bootloaders need the ACPI cpio added by hand, see [How it works](#how-it-works).
- Packages: `sudo apt install acpica-tools innoextract cpio python3 curl`

## Install

```sh
git clone https://github.com/SuselMan/yoga-slim7-carbon-14acn6-speakers
cd yoga-slim7-carbon-14acn6-speakers
sudo ./install.sh --dry-run   # optional: show what would be done
sudo ./install.sh
sudo reboot
```

The script downloads the Lenovo Windows audio driver, about 110 MB, to extract
the amplifier firmware. If the download fails, get "Audio Driver for Windows 11
(64-bit)" (DS552749) from Lenovo support and run
`sudo ./install.sh --driver-exe /path/to/the.exe`.

After the reboot, check:

```console
$ sudo dmesg | grep -E 'cs35l41.*(Bound|Firmware Loaded)'
cs35l41-hda i2c-CSC3551:00-cs35l41-hda.0: Firmware Loaded - Type: spk-prot, Gain: 17
cs35l41-hda i2c-CSC3551:00-cs35l41-hda.0: CS35L41 Bound - SSID: 17AA3856, BST: 1, VSPK: 1, CH: L, FW EN: 1, SPKID: -19
cs35l41-hda i2c-CSC3551:00-cs35l41-hda.1: Firmware Loaded - Type: spk-prot, Gain: 17
cs35l41-hda i2c-CSC3551:00-cs35l41-hda.1: CS35L41 Bound - SSID: 17AA3856, BST: 1, VSPK: 1, CH: R, FW EN: 1, SPKID: -19
```

Errors like `Enable(1) failed: -110` or `Amp short error` mean something is wrong. Please open an issue.

## Uninstall

```sh
sudo ./uninstall.sh
sudo reboot
```

## How it works

The bass speakers are driven by two Cirrus Logic CS35L41 smart amplifiers on
I²C (addresses 0x40/0x41). The Realtek ALC287 feeds them over I²S. Linux fails
at three points:

1. **ACPI.** The BIOS describes the amplifiers as `\_SB.I2CA.SPK1`, HID
   `CLSA0102`, with both I²C addresses in one node and no `_DSD` properties.
   Linux knows `CLSA0100`/`CLSA0101` (Legion 7) but not `CLSA0102`. The list of
   multi-address ACPI devices sits in the core kernel (`drivers/acpi/scan.c`), so
   a module cannot fix it.

   *Fix:* an ACPI table override loaded from an early initrd. The DSDT is binary
   patched in place: `SPK1._HID` is renamed to `XHID`, same length, see
   `acpi/patch-dsdt.py`. A small SSDT (`acpi/cs35l41-spk1.asl`) gives the node the
   generic `CSC3551` HID, `_SUB 17AA3856`, and the `_DSD` that the `cs35l41-hda`
   driver expects. The DSDT is read from your own machine; no BIOS tables are shipped.

2. **Codec.** The amplifiers only get an I²S clock while ALC287 pin `0x17` is
   enabled and powered, but the BIOS marks that pin as unconnected. Without the
   clock, the amplifier PLL never locks and they fail with
   `Enable(1) failed: -110`. The pin also has to share DAC `0x02` with the
   tweeters. Otherwise the generic parser gives it DAC `0x06`, which is powered
   down during stereo playback, and the clock stops again.

   *Fix:* `snd-hda-intel model=,1043:1463` borrows an existing kernel quirk chain
   (ASUS GA402X, `ALC285_FIXUP_ASUS_I2C_HEADSET_MIC`). The chain forces pin
   `0x17` onto DAC `0x02` and binds two CS35L41 amplifiers on I²C.
   `hda/hda-yoga-14acn6.fw` enables pin `0x17` as a speaker and reverts the chain's
   ASUS microphone pin changes.

3. **Amplifier configuration and tuning.** The Windows Cirrus driver INF lists
   `CLSA0102` as "S760": external speaker supply (`ExternalVspkControl=1`), the
   internal boost converter off, and speaker tuning `Lenovo-S760-17AA383D`.
   Enabling the internal boost instead causes `Amp short error`.

   *Fix:* the SSDT sets external boost. The installer extracts the matching DSP
   firmware (`halo_cspl_RAM_revB2_29.49.0.wmfw`) and the per-speaker tuning
   (`17AA383D_20210811_A0/A1.bin`) from the Lenovo driver, checks their SHA-256,
   and installs them as `/lib/firmware/cirrus/cs35l41-dsp1-spk-prot-17aa3856{.wmfw,-l0.bin,-r0.bin}`.

Files installed:

| Path | Purpose |
|---|---|
| `/boot/yoga-14acn6-speakers-acpi.cpio` | patched DSDT + SSDT, early initrd |
| `/etc/default/grub` (`GRUB_EARLY_INITRD_LINUX_CUSTOM`) | loads the cpio before the normal initrd |
| `/etc/modprobe.d/yoga-14acn6-speakers.conf` | `model=` and `patch=` for `snd-hda-intel` |
| `/lib/firmware/hda-yoga-14acn6.fw` | HDA pin configuration |
| `/lib/firmware/cirrus/cs35l41-dsp1-spk-prot-17aa3856*` | amplifier DSP firmware and tuning (from Lenovo) |
| `/var/lib/yoga-14acn6-speakers/` | original DSDT and a backup of `/etc/default/grub` |

For systemd-boot and similar bootloaders, add the cpio as the first `initrd` line of the boot entry.

**Custom GRUB entries** (for example, made with grub-customizer) have hard-coded
`initrd` lines and don't pick up `GRUB_EARLY_INITRD_LINUX_CUSTOM`. The installer
warns about them. Add the cpio to those entries by hand.

## Notes

- There is no speaker calibration. Windows stores calibration in an EFI variable
  that the Linux driver can read, but Windows had never run the calibration on
  the test machine, so the defaults are used. So far this has worked fine.
- The Cirrus/Lenovo firmware files are not part of this repository, because
  they may not be redistributed. The installer downloads them from Lenovo.
- The proper fix belongs in the kernel: `CLSA0102` support in `scan.c`,
  `serial-multi-instantiate`, and the `cs35l41` property quirks, plus an ALC287
  quirk for `17aa:3856`. The firmware belongs in linux-firmware.
- No warranty. The author tested this on one laptop. It changes how your
  speakers are driven, so use it at your own risk.

## Кратко по-русски

Скрипт включает басовые динамики (2× Cirrus CS35L41) на Yoga Slim 7 Carbon
14ACN6 (82L0) под Linux: `sudo ./install.sh`, затем перезагрузка. Удаление:
`sudo ./uninstall.sh`. Secure Boot должен быть выключен. Нужно ядро 6.8+,
проверено на 7.0. Прошивку усилителей скрипт берёт из официального
Windows-драйвера Lenovo. Как это работает, описано выше в разделе «How it works».

## License

Scripts and ACPI/HDA sources: MIT, see [LICENSE](LICENSE). The firmware extracted
from the Lenovo driver stays under its original license.
