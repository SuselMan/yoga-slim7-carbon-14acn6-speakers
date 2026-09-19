/*
 * Yoga Slim 7 Carbon 14ACN6 (82L0): CS35L41 bass amps.
 * BIOS exposes them as CLSA0102 without _DSD, which Linux doesn't know.
 * Present them as generic CSC3551 with the properties the driver needs.
 * The original _HID in DSDT is renamed to XHID by a binary patch.
 */
DefinitionBlock ("", "SSDT", 2, "LENOVO", "CS35L41", 0x00000003)
{
    External (_SB_.I2CA.SPK1, DeviceObj)

    Scope (\_SB.I2CA.SPK1)
    {
        Name (_HID, "CSC3551")
        Name (_SUB, "17AA3856")
        Name (_DSD, Package ()
        {
            ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301"),
            Package ()
            {
                Package () { "cirrus,dev-index", Package () { 0x40, 0x41 } },
                Package () { "reset-gpios", Package () { \_SB.I2CA.SPK1, Zero, Zero, Zero, \_SB.I2CA.SPK1, Zero, Zero, Zero } },
                Package () { "cirrus,speaker-position", Package () { Zero, One } },
                // External VSPK supply, amp boost disabled (Windows INF for CLSA0102/S760: ExternalVspkControl=1, BST_EN=00)
                // GPIO1: VSPK switch, GPIO2: interrupt; no boost-* props => external boost
                Package () { "cirrus,gpio1-func", Package () { One, One } },
                Package () { "cirrus,gpio2-func", Package () { 0x02, 0x02 } }
            }
        })
    }
}
