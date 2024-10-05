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

# Example usage
#
#     utc "2024-09-30T16:35:58.441Z"
#