import { FromAndToKeyCode, Manipulator, map, rule } from "karabiner.ts"
import { kinesisDevices } from "./utils/devices.ts"

const swapKeys = (keyA: FromAndToKeyCode, keyB: FromAndToKeyCode) => [
  map(keyA, undefined, 'any').to(keyB),
  map(keyB, undefined, 'any').to(keyA),
]

const kinesisIf = {
  type: 'device_if' as const,
  identifiers: kinesisDevices.flatMap(d => d.identifiers),
}

export const homeRow = [
  rule('Right option → Hyper')
    .manipulators([
      map('right_option').toHyper().toIfAlone('right_option'),
    ]),

  // NOTE: Set "Press 🌐 key to" → "Do Nothing" in System Settings → Keyboard
  // so macOS doesn't intercept the Globe key before Karabiner sees it.
  // karabiner.ts types don't model apple_vendor_top_case_key_code, so this
  // manipulator is raw JSON behind a cast.
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
  rule('Kinesis menu → Hyper')
    .condition(kinesisIf)
    .manipulators([
      map('application').toHyper(),
    ]),

  // The Freestyle 2 only has a Windows layout. Match it on the Freestyle Pro
  // so both Kinesis boards behave the same, and keep the swap in Karabiner
  // instead of keyboard firmware.
  rule('Kinesis swaps command and option')
    .condition(kinesisIf)
    .manipulators([
      ...swapKeys('left_command', 'left_option'),
    ]),

  rule('Caps locks is ctrl')
    .manipulators([
      map('caps_lock', undefined, 'any').to('left_control'),
    ]),
]
