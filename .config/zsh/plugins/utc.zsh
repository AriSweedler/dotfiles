# Function to convert timestamp to local time and UTC
function utc() {
  timestamp="${1:?}"
  python3 -c "
import datetime

# Get str from user
dt_str_usr = '$timestamp'

# Normalize from illumio to iso style
dt_str_iso = dt_str_usr
if dt_str_usr.endswith('Z'):
  dt_str_iso = dt_str_usr.replace('Z', '+00:00')

# Parse as a datetime
dt = datetime.datetime.fromisoformat(dt_str_iso)

# Express as local and as UTC
print(f'Local Time: ... {dt.astimezone()}')
print(f'UTC Time: ..... {dt.astimezone(datetime.timezone.utc)}')
"
}

function timedelta() {
  local t1="${1:?}"
  local t2="${2:?}"
  python3 -c "
import datetime

# Get str from user
dt_str_usr1 = '$t1'
dt_str_usr2 = '$t2'

# Parse as a datetime
dt1 = datetime.datetime.fromisoformat(dt_str_usr1)
dt2 = datetime.datetime.fromisoformat(dt_str_usr2)
delta = dt2 - dt1
if delta.days < 0:
  print('Negative delta')
  delta = -delta

# Pretty print the delta
print(f'Time delta in seconds: {delta.total_seconds()}')
print(f'Time delta: {delta}')
"
}
