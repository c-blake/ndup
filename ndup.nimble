# Package
version     = "0.1.6"
author      = "Charles Blake"
description = "Near-Duplicate File Detection"
license     = "MIT/ISC"
bin         = @[ "framed", "ndup/setFile", "ndup/nsets", "ndup/pHash" ]

# Dependencies
requires "nim >= 1.6.0", "cligen >= 1.6.14", "bu >= 0.9.6"
