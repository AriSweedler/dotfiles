# macOS 26.6.2 (25G83): an on-screen banner sits directly in the scroll area; the open tray still
# wraps its alerts in one group, as 26.5 did.
nc_alert_subrole=AXNotificationCenterAlert
nc_stack_subrole=AXNotificationCenterAlertStack
nc_container_as='
try
  set grp to scroll area 1 of group 1 of group 1 of window 1
on error
  return "fail: notification container not found"
end try
set sr0 to ""
try
  set sr0 to (subrole of UI element 1 of grp) as text
end try
if sr0 is not "@ALERT@" and sr0 is not "@STACK@" then
  try
    set grp to group 1 of grp
  on error
    return "fail: notification container not found"
  end try
end if'
