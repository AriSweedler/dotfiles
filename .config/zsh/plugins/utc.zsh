# utc TIMESTAMP: an ISO 8601 time (a trailing Z allowed) as local time and as UTC.
# The timestamp reaches python as an argument, never as source text, so any quote in it is data.
function utc() {
  local timestamp="${1:?utc needs an ISO 8601 timestamp}"
  python3 -c '
import datetime, sys
dt = datetime.datetime.fromisoformat(sys.argv[1].removesuffix("Z") + ("+00:00" if sys.argv[1].endswith("Z") else ""))
print(f"Local Time: ... {dt.astimezone()}")
print(f"UTC Time: ..... {dt.astimezone(datetime.timezone.utc)}")
' "${timestamp}"
}

# timedelta T1 T2: the time from T1 to T2 (ISO 8601, a trailing Z allowed); a T2 before T1 says
# "Negative delta" and prints the size.
function timedelta() {
  local t1="${1:?timedelta needs two ISO 8601 timestamps}" t2="${2:?timedelta needs two ISO 8601 timestamps}"
  python3 -c '
import datetime, sys
def parse(s):
  return datetime.datetime.fromisoformat(s.removesuffix("Z") + ("+00:00" if s.endswith("Z") else ""))
delta = parse(sys.argv[2]) - parse(sys.argv[1])
if delta.days < 0:
  print("Negative delta")
  delta = -delta
print(f"Time delta in seconds: {delta.total_seconds()}")
print(f"Time delta: {delta}")
' "${t1}" "${t2}"
}
