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
