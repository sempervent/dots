# ~/.pythonrc.py - Python Interactive Shell Configuration
# https://github.com/sempervent/dotfiles

import sys
import os
import atexit
import readline
from pathlib import Path

# History file
histfile = os.path.expanduser("~/.python_history")
try:
    readline.read_history_file(histfile)
    # Limit history file size
    readline.set_history_length(10000)
except FileNotFoundError:
    pass

atexit.register(readline.write_history_file, histfile)

# Tab completion
try:
    import rlcompleter
    if sys.platform == 'darwin':
        readline.parse_and_bind("bind ^I rl_complete")
    else:
        readline.parse_and_bind("tab: complete")
except ImportError:
    pass

# Color support for interactive Python
try:
    from IPython import embed
    HAS_IPYTHON = True
except ImportError:
    HAS_IPYTHON = False

# Custom functions
def cls():
    """Clear screen"""
    os.system('clear' if os.name != 'nt' else 'cls')

def cd(path):
    """Change directory"""
    os.chdir(os.path.expanduser(path))
    print(f"Changed to: {os.getcwd()}")

# Pretty print by default
try:
    from pprint import pprint
    import builtins
    builtins.pp = pprint
except ImportError:
    pass

# Start IPython if available
if HAS_IPYTHON and 'IPython' in sys.modules:
    # Use IPython for better experience
    pass


