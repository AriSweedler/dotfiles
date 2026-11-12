# macOS 26.5 (25F71): one group inside the scroll area holds every alert and stack, on-screen
# banner or open tray alike.
nc_alert_subrole=AXNotificationCenterAlert
nc_stack_subrole=AXNotificationCenterAlertStack
nc_container_as='
try
  set grp to group 1 of scroll area 1 of group 1 of group 1 of window 1
on error
  return "fail: notification container not found"
end try'
