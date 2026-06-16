import { FromAndToKeyCode, Manipulator, map, rule } from "karabiner.ts"
import { devices, kinesisDevices } from "./utils/devices"

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
  rule('Right option → Hyper')
    .manipulators([
      map('right_option').toHyper().toIfAlone('right_option'),
    ]),

  // NOTE: Set "Press 🌐 key to" → "Do Nothing" in System Settings → Keyboard
  // so macOS doesn't intercept the Globe key before Karabiner sees it.
  rule('Globe → Hyper')
    .manipulators([
      {
        type: 'basic',
        from: {
          apple_vendor_top_case_key_code: 'keyboard_fn',
          modifiers: { optional: ['any'] },
        },
        to: [{
          key_code: 'left_shift',
          modifiers: ['left_command', 'left_control', 'left_option'],
        }],
      } as unknown as Manipulator,
    ]),

  // Mirrors the Globe → Hyper rule above so the Mac and Kinesis behave the
  // same. 'Menu' key emits `application` on the Freestyle Pro.
  rule('Kinesis Freestyle Pro menu → Hyper')
    .condition({
      type: 'device_if',
      identifiers: devices.freestylePro.identifiers,
    })
    .manipulators([
      map('application').toHyper(),
    ]),

  rule('Kinesis swaps command and option')
    .condition({
      type: 'device_if',
      identifiers: kinesisDevices.flatMap(d => d.identifiers),
    })
    .manipulators([
      ...swapKeys('left_command', 'left_option'),
    ]),

  rule('Caps locks is ctrl')
    .manipulators([
      {
        type: 'basic',
        from: {
          key_code: 'caps_lock',
          modifiers: {
            optional: ['any'],
          },
        },
        to: [{ key_code: 'left_control' }],
      },
    ]),
]
