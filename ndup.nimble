# Package
version     = "0.2.0"
author      = "Charles Blake"
description = "Near-Duplicate File Detection"
license     = "MIT/ISC"
bin       = @["framed", "ndup/setFile", "ndup/nsets", "ndup/pHash", "ndup/like"]

# Dependencies
requires "nim >= 1.6.0", "cligen >= 1.10.0", "bu >= 0.18.13"
