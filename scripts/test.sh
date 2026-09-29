#!/bin/bash
# Command Line Tools ship Swift Testing but don't put it on the default search path,
# and their _Testing_Foundation overlay has no module file, so cross-import overlays are disabled.
set -euo pipefail
cd "$(dirname "$0")/.."
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift test -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays -Xswiftc -F -Xswiftc "$F" -Xlinker -F -Xlinker "$F" -Xlinker -rpath -Xlinker "$F" "$@"
