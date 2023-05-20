# Package
version     = "0.1.4"
author      = "Charles Blake"
description = "Near-Duplicate File Detection"
license     = "MIT/ISC"
bin         = @[ "framed", "ndup/setFile", "ndup/nsets", "ndup/pHash" ]

# Dependencies
requires "nim >= 1.6.0", "cligen >= 1.6.4", "bu >= 0.8.5"
