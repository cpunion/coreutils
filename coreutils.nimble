[Package]
name          = "coreutils"
version       = "0.1.0"
author        = "Anonymous"
description   = "Nim rewrite of the GNU coreutils"
license       = "MIT"

bin = "wc"

binDir = "bin"
srcDir = "src"

[Deps]
Requires: "nim >= 0.11.0"
