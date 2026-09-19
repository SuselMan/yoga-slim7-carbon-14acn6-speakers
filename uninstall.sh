#!/usr/bin/env bash
# Remove everything install.sh added.
set -euo pipefail

NAME=yoga-14acn6-speakers
STATE=/var/lib/$NAME
CPIO=/boot/$NAME-acpi.cpio
CIRRUS=/lib/firmware/cirrus/cs35l41-dsp1-spk-prot-17aa3856

[ "$(id -u)" = 0 ] || { echo "ERROR: run as root (sudo $0)" >&2; exit 1; }

echo "==> Removing files"
rm -fv "$CPIO" /etc/modprobe.d/$NAME.conf /lib/firmware/hda-yoga-14acn6.fw \
	"$CIRRUS.wmfw" "$CIRRUS-l0.bin" "$CIRRUS-r0.bin"

echo "==> Removing the ACPI override from GRUB"
cpio_name=$(basename "$CPIO")
current=$(sed -n 's/^GRUB_EARLY_INITRD_LINUX_CUSTOM=//p' /etc/default/grub | tr -d "\"'")
if echo " $current " | grep -q " $cpio_name "; then
	new=$(echo " $current " | sed "s| $cpio_name | |" | xargs)
	if [ -n "$new" ]; then
		sed -i "s|^GRUB_EARLY_INITRD_LINUX_CUSTOM=.*|GRUB_EARLY_INITRD_LINUX_CUSTOM=\"$new\"|" /etc/default/grub
	else
		sed -i '/^GRUB_EARLY_INITRD_LINUX_CUSTOM=/d' /etc/default/grub
	fi
fi
update-grub

rm -rf "$STATE"
echo "==> Done. Reboot to return to the stock configuration."
