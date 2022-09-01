#!/bin/bash
mkdir -p rfc            # This took about 45 minutes for me
cd rfc                  # ..and needs about 500 MiB space
( for num in {1..9199}; do   # Range valid circa 2022-08-20
    echo https://www.rfc-editor.org/rfc/rfc${num}.txt
  done ) | wget -N -i - # -N update is ~3X faster than xfer
