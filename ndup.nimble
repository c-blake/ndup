# Package
version     = "0.1.1"
author      = "Charles Blake"
description = "Near-Duplicate File Detection"
license     = "MIT/ISC"
bin         = @[ "framed", "ndup/setFile", "ndup/nsets" ]

# Dependencies
requires "nim >= 1.6.0", "cligen >= 1.6.3", "bu >= 0.8.3"
