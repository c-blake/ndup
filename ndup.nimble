# Package
version     = "0.1.9"
author      = "Charles Blake"
description = "Near-Duplicate File Detection"
license     = "MIT/ISC"
bin         = @[ "framed", "ndup/setFile", "ndup/nsets", "ndup/pHash" ]

# Dependencies
requires "nim >= 1.6.0", "cligen >= 1.8.3", "bu >= 0.18.6"
