# macOS defaults every machine gets (was ~/.config/macos.sh). A switch writes them and restarts
# the Dock and Finder when they change.
{ ... }:
{
  system.defaults = {
    finder = {
      FXEnableExtensionChangeWarning = false; # no warning when changing a file extension
      ShowPathbar = true;
      _FXShowPosixPathInTitle = true; # full POSIX path as the window title
    };
    dock = {
      mineffect = "suck";
      minimize-to-application = true; # minimize windows into their application's icon
      show-process-indicators = true; # indicator lights for open applications
      showhidden = true; # hidden applications' icons translucent
      mru-spaces = false; # don't rearrange Spaces by most recent use
      orientation = "left";
    };
    CustomUserPreferences."com.apple.dock".no-bouncing = true; # stop Dock icons bouncing
  };
}
