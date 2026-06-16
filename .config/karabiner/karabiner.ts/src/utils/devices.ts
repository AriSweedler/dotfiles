import { DeviceIdentifier } from "karabiner.ts"

// To find a new one, go to karabiner-EventViewer > Devices & find your device.
// It may be helpful to use jq to search through the JSON blob, e.g.
//
//     jq '.[] | select(.manufacturer == "Kinesis")'
//
export type LabeledDevice = {
  label: string
  identifiers: DeviceIdentifier[]
}

export const devices = {
  // Physical label says "Freestyle Pro", but the device reports its product
  // name as "Freestyle Edge Keyboard" in karabiner-EventViewer.
  //
  // The Kinesis "gear/recycle" button toggles a mass-storage/drive-exposer mode
  // that re-enumerates the keyboard under a different product_id (seen as both
  // 258 and 259), so match both. Observe the live product_id by running
  // `karabiner-list-keyboards` (in ~/.config/bin) or via karabiner-EventViewer,
  // then add it below. An LLM can use the `--json` flag for easier parsing:
  //     karabiner-list-keyboards --json --vendor_id 10730
  freestylePro: {
    label: "Kinesis Freestyle Pro",
    identifiers: [
      { is_keyboard: true, product_id: 258, vendor_id: 10730 },
      { is_keyboard: true, product_id: 259, vendor_id: 10730 },
    ],
  },
  freestyle2: {
    label: "Kinesis Freestyle 2",
    identifiers: [{ is_keyboard: true, product_id: 37904, vendor_id: 1423 }],
  },
  // Apple internal reports no vendor/product id; match the built-in flag.
  appleInternal: {
    label: "Apple Internal Keyboard",
    identifiers: [{ is_keyboard: true, is_built_in_keyboard: true }],
  },
} satisfies Record<string, LabeledDevice>

export const allDevices: LabeledDevice[] = Object.values(devices)
export const kinesisDevices: LabeledDevice[] = [devices.freestylePro, devices.freestyle2]
