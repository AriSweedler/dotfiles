import { DeviceIdentifier, FromAndToKeyCode, Manipulator, map, rule } from "karabiner.ts"

// Device identifiers
//
// To find a new one, go to karabiner-EventViewer > Devices & find your device.
// It may be helpful to use jq to search through the JSON blob
//
//     jq '.[] | select(.manufacturer == "Kinesis")'
//
const devices: Record<string, DeviceIdentifier> = {
  kinesisFreestylePro: {
    is_keyboard: true,
    product_id: 258,
    vendor_id: 10730,
  },
  kinesisFreestyle2: {
    is_keyboard: true,
    product_id: 37904,
    vendor_id: 1423,
  }
}

// Helper to swap two keys, preserving any modifiers
const swapKeys = (keyA: FromAndToKeyCode, keyB: FromAndToKeyCode): Manipulator[] => [
  {
    type: 'basic',
    from: {
      key_code: keyA,
      modifiers: { optional: ['any'] },
    },
    to: [{ key_code: keyB }],
  },
  {
    type: 'basic',
    from: {
      key_code: keyB,
      modifiers: { optional: ['any'] },
    },
    to: [{ key_code: keyA }],
  },
];

export const homeRow = [
  rule('Right option → Hyper').manipulators([
    map('right_option').toHyper().toIfAlone('right_option'),
  ]),
  rule('Kinesis swaps command and option')
    .condition({
      type: 'device_if',
      identifiers: Object.values(devices),
    })
    .manipulators([
      ...swapKeys('left_command', 'left_option')
    ]),
]
