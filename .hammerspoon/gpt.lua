-- Helper function to generate the strings we wish to add to the prompt
local function gpt_prompt_lte_words(num_words)
  return "Answer in less than or equal to " .. tostring(num_words) .. " words"
end

-- Define a table that maps prompt engineering key codes to the strings we wish
-- to add to the prompt
local pe_key_bindings = {
  ["0"] = gpt_prompt_lte_words(100)
  ,["2"] = gpt_prompt_lte_words(20)
  ,[","] = gpt_prompt_lte_words(50)
  ,["-"] = "Answer in as few words as possible"
  ,["b"] = "Give me a bulleted list"
  ,["m"] = "Answer in as few words as possible. Answer in one line of code"
}

-- Define a function that creates a hotkey binding for a given key code
mod = {"cmd", "shift", "alt"}
local function bind_pe_keycode(key_code)
  hs.hotkey.bind(mod, key_code, function()
    hs.eventtap.keyStrokes(pe_key_bindings[key_code])
  end)
end

-- Create hotkey bindings for each key code in the table
for key_code, _ in pairs(pe_key_bindings) do
  bind_pe_keycode(key_code)
end
