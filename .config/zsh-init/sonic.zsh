function sonic::open_dir() {
  local -r SONIC_DIR='/Users/ari/Desktop/life/apartment/3 - 43Diamond/sonic receipts'
  run_cmd open "$SONIC_DIR"
}

function sonic() {
  local -r SONIC_DIR='/Users/ari/Desktop/life/apartment/3 - 43Diamond/sonic receipts'

  # Manage filesystem stuff
  local invoice
  if ! invoice="$(sonic::_file)"; then
    log::err "Failed to file away the sonic invoice"
    return 1
  fi

  # Open up splitwise then the sonic folder. Return to this terminal window
  local -r splitwise_group_url="https://secure.splitwise.com/#/groups/20951549"
  run_cmd open -a Firefox "$splitwise_group_url"
  run_cmd open "$invoice"
  run_cmd open "$SONIC_DIR"
  run_cmd open -a Terminal

  # Parse information from the pdf
  IFS=',' read date_start_mdy date_end_mdy amount <<< "$(sonic::_extract_from_pdf "$invoice")"
  IFS='/' read ds_m ds_d ds_y <<< "$date_start_mdy"
  IFS='/' read de_m de_d de_y <<< "$date_end_mdy"
  local -r new_invoice_name="${ds_y:?}_${ds_m:?}_${ds_d:?}-${de_y:?}_${de_m:?}_${de_d:?}"
  local -r splitwise_description="Sonic internet $date_start_mdy - $date_end_mdy"

  # Place a suggestion for the new name on your clipboard
  log::info "We will place 'invoice_name' then 'description' then 'amount' on your clipboard"
  wait_for_keypress

  # Do the 3 stages
  clipboard "$new_invoice_name" --description "New invoice name"
  wait_for_keypress "Open 'SONIC_DIR' to rename the invoice"
  open "$SONIC_DIR"
  wait_for_keypress

  clipboard "$splitwise_description" --description "Splitwise description"
  wait_for_keypress "Open splitwise to enter the transaction name"
  open -a Firefox
  wait_for_keypress

  clipboard "$amount" --description "amount"
  wait_for_keypress "Open splitwise to enter the transaction amount"
  open -a Firefox
  wait_for_keypress
}

function sonic::_file() {
  local -r SONIC_DIR='/Users/ari/Desktop/life/apartment/3 - 43Diamond/sonic receipts'

  # Make sure there's an 'invoice' in Downloads
  local -r download_dir="$HOME/Downloads"
  local invoice="$(compgen -G "$download_dir/invoice*")"
  if ! [ -f "$invoice" ]; then
    log::err "No sonic invoice found | download_dir='$download_dir'"
    ls -1 "$download_dir"
    return 1
  fi

  # Move it to the invoices folder
  if ! [ -d "$SONIC_DIR" ]; then
    log::err "Could not find sonic directory | SONIC_DIR='$SONIC_DIR'"
    return 1
  fi
  run_cmd mv "$invoice" "$SONIC_DIR"
  invoice="$SONIC_DIR/$(basename "$invoice")"
  echo "$invoice"
}

# Comma separated tuple: start,end,amount. To be consumed with `IFS=',' read ...`
function sonic::_extract_from_pdf() {
  # Parse args
  local -r invoice="${1:?}"

  # Validate args
  if ! [ -f "$invoice" ]; then
    log::err "Could not extract information from missing invoice | invoice='$invoice'"
    return 1
  fi
  if ! grep -q '\.pdf$' <<< "$invoice"; then
    log::err "sonic invoice is not a pdf - parsing will fail | invoice='$invoice'"
    return 1
  fi

  # Do the parsing.
  #
  # Awk is getting this line of text:
  #
  #     Current Charges 4/27/23 - 5/26/23 $88.15
  #
  pdfgrep 'Current Charges' "$invoice" | awk '/-/ {print $3","$5","$6}' | tr -d '$'
}
