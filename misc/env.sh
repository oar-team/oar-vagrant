# This file set the environment (PATH) for oar-vagrant misc functions: linked cloned VMs and snapshots
if [ -e "$PWD/misc/env.sh" ]; then
  PATH=$PWD/misc/bin:$PATH
elif [ -e "$PWD/../misc/env.sh" ]; then
  PATH=$PWD/../misc/bin:$PATH
else
  echo "Please source this file from either OAR-vagrant top directory or one of it's subdirectory." >&2
fi
