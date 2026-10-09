#!/usr/bin/env bash
# Enable the bass speakers (2x Cirrus CS35L41) on Lenovo Yoga Slim 7 Carbon 14ACN6 (82L0).
# See README.md for what this does and why. Undo with ./uninstall.sh.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
NAME=yoga-14acn6-speakers
STATE=/var/lib/$NAME
CPIO=/boot/$NAME-acpi.cpio
MODPROBE=/etc/modprobe.d/$NAME.conf
HDA_FW=/lib/firmware/hda-yoga-14acn6.fw
CIRRUS=/lib/firmware/cirrus/cs35l41-dsp1-spk-prot-17aa3856

# Lenovo "Audio Driver for Windows 11 (64-bit)" DS552749, v6.0.9366.1
DRIVER_URL=https://download.lenovo.com/consumer/mobiles/31ys04afrguh2nc0.exe
FW_WMFW="Playback_6.47.0/Firmware/CS35L41/RevB2/halo_cspl_RAM_revB2_29.49.0.wmfw"
FW_L0="tunings/Lenovo-S760-17AA383D_20210811/17AA383D_20210811_A0.bin"
FW_R0="tunings/Lenovo-S760-17AA383D_20210811/17AA383D_20210811_A1.bin"
SHA_WMFW=cfee644db22850bb4a6ddae98144ba73c0756f98939d7bb5f905ae2b8468a525
SHA_L0=fa4933981c7686e450b7c5982ee40a4932f6fb0e7346325fdb8d0dcc3f172147
SHA_R0=9fa124561147d014f23600073450f6ddfe662f1aae38f3724542a14236213aee

DRY_RUN=0
DRIVER_EXE=
FORCE=0

usage() {
	cat <<EOF
Usage: sudo $0 [--dry-run] [--driver-exe FILE] [--force]

  --dry-run          build everything in a temp dir, change nothing on the system
  --driver-exe FILE  use an already downloaded Lenovo driver package instead of downloading
  --force            skip the laptop model check
EOF
}

while [ $# -gt 0 ]; do
	case $1 in
	--dry-run) DRY_RUN=1 ;;
	--driver-exe) DRIVER_EXE=$(realpath "$2"); shift ;;
	--force) FORCE=1 ;;
	-h|--help) usage; exit 0 ;;
	*) usage; exit 1 ;;
	esac
	shift
done

info() { echo "==> $*"; }
warn() { echo "WARNING: $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

# Run a command, or only print it in dry-run mode
run() {
	if [ $DRY_RUN = 1 ]; then echo "    [dry-run] $*"; else "$@"; fi
}

[ "$(id -u)" = 0 ] || die "run as root (sudo $0)"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- checks ---------------------------------------------------------------

info "Checking the machine"
product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
version=$(cat /sys/class/dmi/id/product_version 2>/dev/null || true)
if [ "$product" != 82L0 ] && [ $FORCE = 0 ]; then
	die "this is '$product $version', not a Yoga Slim 7 Carbon 14ACN6 (82L0). Use --force to try anyway."
fi

codec=$(grep -l "Realtek ALC287" /proc/asound/card*/codec#* 2>/dev/null | head -1 || true)
[ -n "$codec" ] || die "Realtek ALC287 codec not found"
grep -q "Subsystem Id: 0x17aa3856" "$codec" || [ $FORCE = 1 ] ||
	die "unexpected codec subsystem id (want 0x17aa3856)"
card=$(echo "$codec" | sed -E 's|/proc/asound/card([0-9]+)/.*|\1|')

lockdown=$(cat /sys/kernel/security/lockdown 2>/dev/null || echo "[none]")
case $lockdown in
*"[none]"*) ;;
*) die "kernel lockdown is active ($lockdown), usually because of Secure Boot. The ACPI table upgrade is blocked under lockdown; disable Secure Boot first." ;;
esac

for cmd in iasl innoextract cpio python3 curl; do
	command -v $cmd >/dev/null || die "'$cmd' not found. On Ubuntu/Debian: sudo apt install acpica-tools innoextract cpio python3 curl"
done

BOOTLOADER=
if command -v update-grub >/dev/null 2>&1 && [ -f /etc/default/grub ]; then
	BOOTLOADER=grub
elif command -v bootctl >/dev/null 2>&1 && [ -d /boot/efi/loader/entries ]; then
	BOOTLOADER=systemd-boot
else
	die "neither a usable GRUB installation nor systemd-boot was found"
fi
info "Detected boot loader: $BOOTLOADER"

# Needed kernel pieces: generic CS35L41 HDA driver and the ASUS quirk chain we borrow
kver=$(uname -r)
modinfo -k "$kver" snd_hda_scodec_cs35l41_i2c >/dev/null 2>&1 || die "kernel $kver has no snd_hda_scodec_cs35l41_i2c module"
# The 1043:1463 quirk (ASUS GA402X) is in the kernel since ~6.7; tested on 7.0
min=6.8
[ "$(printf '%s\n' "$min" "${kver%%-*}" | sort -V | head -1)" = "$min" ] ||
	die "kernel $kver is too old, need $min or newer"

# --- ACPI override --------------------------------------------------------

info "Building the ACPI override"
mkdir -p "$WORK/cpio/kernel/firmware/acpi"
[ $DRY_RUN = 1 ] || mkdir -p "$STATE"
if [ -f "$STATE/dsdt-original.aml" ]; then
	cp "$STATE/dsdt-original.aml" "$WORK/dsdt.aml"
else
	cat /sys/firmware/acpi/tables/DSDT > "$WORK/dsdt.aml"
	[ $DRY_RUN = 1 ] || cp "$WORK/dsdt.aml" "$STATE/dsdt-original.aml"
fi
python3 "$HERE/acpi/patch-dsdt.py" "$WORK/dsdt.aml" "$WORK/cpio/kernel/firmware/acpi/dsdt.aml"
iasl -p "$WORK/cpio/kernel/firmware/acpi/cs35l41-spk1" "$HERE/acpi/cs35l41-spk1.asl" >/dev/null ||
	die "failed to compile the SSDT"
(cd "$WORK/cpio" && find kernel | cpio -H newc --create --owner=0:0 --quiet > "$WORK/acpi.cpio")
run install -m644 "$WORK/acpi.cpio" "$CPIO"

cpio_name=$(basename "$CPIO")
if [ "$BOOTLOADER" = grub ]; then
	info "Adding the override to GRUB"
	current=$(sed -n 's/^GRUB_EARLY_INITRD_LINUX_CUSTOM=//p' /etc/default/grub | tr -d "\"'")
	if ! echo " $current " | grep -q " $cpio_name "; then
		new=$(echo "$current $cpio_name" | xargs)
		run cp /etc/default/grub "$STATE/grub.default.bak"
		if [ -n "$current" ] || grep -q '^GRUB_EARLY_INITRD_LINUX_CUSTOM=' /etc/default/grub; then
			run sed -i "s|^GRUB_EARLY_INITRD_LINUX_CUSTOM=.*|GRUB_EARLY_INITRD_LINUX_CUSTOM=\"$new\"|" /etc/default/grub
		elif [ $DRY_RUN = 1 ]; then
			echo "    [dry-run] append GRUB_EARLY_INITRD_LINUX_CUSTOM=\"$new\" to /etc/default/grub"
		else
			echo "GRUB_EARLY_INITRD_LINUX_CUSTOM=\"$new\"" >> /etc/default/grub
		fi
	fi
	run update-grub
else
	info "Adding the override to systemd-boot"
	ESP=/boot/efi
	ESP_CPIO="$ESP/EFI/$cpio_name"
	INITRD_LINE="initrd /EFI/$cpio_name"
	run install -Dm644 "$WORK/acpi.cpio" "$ESP_CPIO"
	found_entry=0
	for entry in "$ESP"/loader/entries/Pop_OS-*.conf; do
		[ -f "$entry" ] || continue
		found_entry=1
		if grep -Fqx "$INITRD_LINE" "$entry"; then
			continue
		fi
		if [ $DRY_RUN = 1 ]; then
			echo "    [dry-run] add '$INITRD_LINE' before the first initrd line in $entry"
		else
			awk -v line="$INITRD_LINE" '''
				BEGIN { added=0 }
				!added && $1 == "initrd" { print line; added=1 }
				{ print }
				END { if (!added) print line }
			''' "$entry" > "$WORK/loader-entry.conf"
			cp "$WORK/loader-entry.conf" "$entry"
		fi
	done
	[ "$found_entry" = 1 ] || die "no Pop!_OS systemd-boot entries found in $ESP/loader/entries"
fi

# --- HDA codec: bass pin + CS35L41 binding ----------------------------------

info "Configuring the Realtek codec (card $card)"
commas=$(printf '%*s' "$card" '' | tr ' ' ',')
run install -m644 "$HERE/hda/hda-yoga-14acn6.fw" "$HDA_FW"
if [ $DRY_RUN = 1 ]; then
	echo "    [dry-run] write $MODPROBE: options snd-hda-intel model=${commas}1043:1463 patch=${commas}hda-yoga-14acn6.fw"
else
	cat > "$MODPROBE" <<EOF
# Yoga Slim 7 Carbon 14ACN6 bass speakers ($NAME)
# 1043:1463 = ALC285_FIXUP_ASUS_I2C_HEADSET_MIC: bass pin 0x17 on DAC 0x02 + 2x CS35L41 on I2C
options snd-hda-intel model=${commas}1043:1463 patch=${commas}hda-yoga-14acn6.fw
EOF
fi

# --- CS35L41 DSP firmware and speaker tuning from the Lenovo driver ---------

info "Getting CS35L41 firmware from the Lenovo Windows driver"
if [ -z "$DRIVER_EXE" ]; then
	DRIVER_EXE=$WORK/lenovo-audio.exe
	curl -fL --progress-bar -A "Mozilla/5.0" -o "$DRIVER_EXE" "$DRIVER_URL" ||
		die "download failed; get the package manually from Lenovo support (DS552749) and pass --driver-exe"
fi
innoextract -s -d "$WORK/drv" -I "CsAudio/csaudioext" "$DRIVER_EXE" >/dev/null
ext=$(find "$WORK/drv" -type d -name csaudioext | head -1)
[ -n "$ext" ] || die "CsAudio/csaudioext not found in $DRIVER_EXE"

check() { # file, sha256
	[ -f "$ext/$1" ] || die "$1 missing in the driver package"
	echo "$2  $ext/$1" | sha256sum -c --quiet - || die "checksum mismatch for $1"
}
check "$FW_WMFW" $SHA_WMFW
check "$FW_L0" $SHA_L0
check "$FW_R0" $SHA_R0
run install -Dm644 "$ext/$FW_WMFW" "$CIRRUS.wmfw"
run install -Dm644 "$ext/$FW_L0" "$CIRRUS-l0.bin"
run install -Dm644 "$ext/$FW_R0" "$CIRRUS-r0.bin"

# --- done ---------------------------------------------------------------

if [ "$BOOTLOADER" = grub ] &&
	grep -q '^\s*initrd' /boot/grub/grub.cfg 2>/dev/null &&
	grep -E '^\s*initrd' /boot/grub/grub.cfg | grep -vq "$cpio_name"; then
	warn "some GRUB entries don't load $cpio_name (custom entries, e.g. from grub-customizer)."
	warn "The bass speakers won't work when booting those entries."
fi

if [ $DRY_RUN = 1 ]; then
	info "Dry run finished, nothing was changed"
else
	info "Done. Reboot, then check: sudo dmesg | grep cs35l41"
fi
