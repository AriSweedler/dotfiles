import { DeviceIdentifier } from "karabiner.ts"

// To find a new one, go to karabiner-EventViewer > Devices & find your device.
// It may be helpful to use jq to search through the JSON blob, e.g.
//
//     jq '.[] | select(.manufacturer == "Kinesis")'
//
export type LabeledDevice = {
  label: string
  identifier: DeviceIdentifier
}

export const devices = {
  // Physical label says "Freestyle Pro", but the device reports its product
  // name as "Freestyle Edge Keyboard" in karabiner-EventViewer.
  //
  // If these device-specific mappings aren't working, perhaps a layout change
  // or firmware update has changed the product_id (observed as both 258 and
  // 259). Observe the live product_id by running `karabiner-list-keyboards`
  // (in ~/.config/bin) or via karabiner-EventViewer, then update it below.
  // An LLM can use the `--json` flag to make parsing easier:
  //     karabiner-list-keyboards --json --vendor_id 10730
  freestylePro: {
    label: "Kinesis Freestyle Pro",
    identifier: { is_keyboard: true, product_id: 258, vendor_id: 10730 },
  },
  freestyle2: {
    label: "Kinesis Freestyle 2",
    identifier: { is_keyboard: true, product_id: 37904, vendor_id: 1423 },
  },
  // Apple internal reports no vendor/product id; match the built-in flag.
  appleInternal: {
    label: "Apple Internal Keyboard",
    identifier: { is_keyboard: true, is_built_in_keyboard: true },
  },
} as const satisfies Record<string, LabeledDevice>

export const allDevices: LabeledDevice[] = Object.values(devices)
export const kinesisDevices: LabeledDevice[] = [devices.freestylePro, devices.freestyle2]
