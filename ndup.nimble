# Package
version     = "0.1.0"
author      = "Charles Blake"
description = "Near-Duplicate File Detection"
license     = "MIT/ISC"
bin         = @[ "framed", "ndup/setFile", "ndup/nsets" ]

# Dependencies
requires "nim >= 1.6.0", "cligen >= 1.5.28", "bu >= 0.2.0"
