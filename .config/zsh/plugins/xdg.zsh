function xdg() {
  echo "XDG_CONFIG_HOME='$XDG_CONFIG_HOME'
  * User-specific configuration files
  * These should be versioned in git
"

  echo "XDG_DATA_HOME='$XDG_DATA_HOME'
  * User-specific data files essential for the application to function
  correctly. These files are generally static and do not change frequently. This
  can include things like icons, documentation, and other resources that the
  application needs to run.
  * If you delete these, it will be an issue and they will need to be
  re-installed.
  * This is where you should put important scripts that are only local. Code
  that lives here should be collected and backed up.
"

  echo "XDG_STATE_HOME='$XDG_STATE_HOME'
  * Ephemeral data files that pertain to the application's current state, such
  as swap files, logs, or history. These files can be safely cleared without
  losing critical data.
  * Users never write this - only programs
"
  echo

  echo "XDG_CACHE_HOME='$XDG_CACHE_HOME'
  * Ephemeral data files used to speed up application processes, such as history
  files and cache. Clearing this may affect program behavior, mainly in terms of
  speed and sometimes correctness
  * Users never write this - only programs
"
}
