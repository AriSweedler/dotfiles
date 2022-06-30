function! PrintUndotreeWithStrftime()
  " Only print the last 15 entries
  let l:entries = get(undotree(), 'entries')[-15:]

  " Map/join got too messy...
  echom "Most recent changes happened at the following times:"
  for entry in entries
    let time_formatted = strftime("%H:%M", get(entry, "time"))
    echom "Time: " . time_formatted . " - seq=".get(entry, "seq")
  endfor
endfunction
