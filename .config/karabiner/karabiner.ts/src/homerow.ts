import { map, rule } from "karabiner.ts"

// Device-specific condition
const kinesisDevice = {
  is_keyboard: true,
  product_id: 37904,
  vendor_id: 1423,
}

// Helper to swap two keys, preserving any modifiers
const swapKeys = (keyA: string, keyB: string): Manipulator[] => [
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

export default homeRow = [
  rule('Right option → Hyper').manipulators([
    map('right_option').toHyper().toIfAlone('right_option'),
  ]),
  rule('Kinesis swaps command and option')
    .condition({
      type: 'device_if',
      identifiers: [kinesisDevice],
    })
    .manipulators([
      ...swapKeys('left_command', 'left_option')
    ]),
]
