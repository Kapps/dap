#!/bin/bash

# Basic install script for dap:
#	Adds dap to the system path (/usr/local/bin on Linux/OSX, on Windows the CWD is added to the global PATH variable)
#	On Linux/OSX, adds bash autocomplete support, provided that the bash-completion package is installed.

set -e

# Error codes:
# Environment errors:
	# 999 - Script not supported on this platform
	# 998 - User has not built dap yet
	# 997 - Missing dependency

PLATFORM_UNKNOWN=0
PLATFORM_WINDOWS=1
PLATFORM_OSX=2
PLATFORM_LINUX=3

platform=$PLATFORM_UNKNOWN
binprefix=""

# Platform detection courtesy of http://stackoverflow.com/a/27776822/592845
case "$(uname -s)" in

   Darwin)
     platform=$PLATFORM_OSX
	 binprefix="/usr/local/bin"
     ;;

   Linux)
     platform=$PLATFORM_LINUX
	 binprefix="/usr/local/bin"
     ;;

   CYGWIN*|MINGW32*|MSYS*)
     platform=$PLATFORM_WINDOWS
	 binprefix="/usr/bin"
     ;;

   *)
     echo 'The dap install script is not supported on this platform.'
	 exit 999 
     ;;
esac

if [[ -z "$binprefix$" ]]; then
	echo 'Could not detect platform equivalent of /usr/local/bin.'
	exit 999
fi

linkpath="$binprefix/dap"

if [[ $platform != $PLATFORM_WINDOWS && -e "$linkpath" ]]; then
	echo "Skipping appending to path: $linkpath already exists"
elif [[ ! -f "$(pwd)/dap" ]]; then
	echo 'You must first build dap prior to running this script.'
	exit 998
else
	echo 'Requesting sudo access in order to link the file.'
	sudo ln -s "$(pwd)/dap" "$linkpath"
	echo "Created symlink from $linkpath to $(pwd)/dap."
	sudo chmod og+x "$(pwd)/dap"
	echo 'Added owner and group execute permission.'
fi

completionfname="dap-completion.bash"
completionfnamedst=""
completiondir=""
completionautoenable=0
if [[ $platform == $PLATFORM_WINDOWS ]]; then
	completiondir="/etc"
	completionfnamedst="dap-completion.bash"
	completionautoenable=0
elif [[ $platform == $PLATFORM_OSX ]]; then
	completiondir="/usr/local/etc/bash_completion.d"
	completionfnamedst="dap"
	completionautoenable=1
elif [[ $platform == $PLATFORM_LINUX ]]; then
	completiondir="/etc/bash_completion.d"
	completionfnamedst="dap"
	completionautoenable=1
else
	echo 'Unable to get bash completion directory.'
	exit 999
fi

if [[ ! -e "$completiondir" ]]; then
	echo "Bash completion directory $completiondir did not exist."
	echo "Install bash-completion using your package manager then run this script again."
	exit 997
fi

if [[ -e "$completiondir/$completionfnamedst" ]]; then
	echo 'Skipping linking of bash completion file as it already exists.'
else
	sudo ln -s "$(pwd)/$completionfname" "$completiondir/$completionfnamedst"
	sudo chmod go+x "$completiondir/$completionfnamedst"
	echo "Created link from $completiondir/$completionfnamedst to $(pwd)/$completionfname."
	if [[ $platform == $PLATFORM_OSX ]]; then
		echo 'If you have not already, and you are using brew, you will need to add the following to ~/.bash_profile:'
		echo 'if [ -f $(brew --prefix)/etc/bash_completion ]; then'
		echo '    . $(brew --prefix)/etc/bash_completion'
		echo 'fi'
	elif [[ $platform == $PLATFORM_WINDOWS ]]; then
		echo "This platform does not support automatically enabling bash completion."
		echo "Please add 'source $completiondir/$completionfnamedst' to /etc/profile."
	elif [[ $platform == $PLATFORM_LINUX ]]; then
		echo "This should be sufficient to enable bash completion in new instances of bash."
		echo "If bash completion is not functional, please add 'source $completiondir/$completionfnamedst' to /etc/profile."
	else
		echo 'Unknown platform: internal error'
		exit 999
	fi
fi

echo 'Installation complete.'
echo 'If any errors were encountered, you can re-run this script after fixing them.'
