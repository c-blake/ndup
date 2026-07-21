# Package
version     = "0.3.0"
author      = "Charles Blake"
description = "Near-Duplicate File Detection"
license     = "MIT/ISC"
bin       = @["framed", "ndup/setFile", "ndup/nsets", "ndup/pHash", "ndup/like"]

# Dependencies
requires "nim >= 1.6.0", "cligen >= 1.11.0", "bu >= 0.19.0"
