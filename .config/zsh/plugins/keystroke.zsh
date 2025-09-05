# Run a command DIRECTLY from a keystroke:
# https://unix.stackexchange.com/a/668986/248906

# Keystroke Binding Framework
# Usage: keystroke '^o' cd_h
#   - Creates cd_h-widget that calls cd_h()  
#   - Unbinds existing ^o binding
#   - Registers and binds the widget

function keystroke() {
    local key="$1"
    local func_name="$2"
    local widget_name="${func_name}-widget"
    
    # Validate arguments
    if [[ -z "$key" || -z "$func_name" ]]; then
        echo "Usage: keystroke '<key>' <function_name>"
        echo "Example: keystroke '^o' cd_h"
        return 1
    fi
    
    # Check if the base function exists
    if ! declare -f "$func_name" >/dev/null 2>&1; then
        echo "Error: Function '$func_name' does not exist"
        echo "Define it first: function $func_name { ... }"
        return 1
    fi
    
    # Unbind existing key (silently ignore errors)
    bindkey -r "$key" 2>/dev/null
    
    # Create the widget function that calls the base function
    eval "function $widget_name { 
        $func_name
        zle reset-prompt
    }"
    
    # Register as ZLE widget
    zle -N "$widget_name"
    
    # Bind the key
    bindkey "$key" "$widget_name"
    
    # echo "✓ Bound $key → $func_name (via $widget_name)"
}

################################################################################

# Example usage - define functions then bind them
function hello_world { echo "Hello world!"; }
function cd_h { echo "jumping to hyperbase"; cd "$HOME/h/source/hyperbase"; }

keystroke '^z' hello_world
keystroke '^o' cd_h
