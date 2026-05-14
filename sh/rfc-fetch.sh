#!/bin/bash
mkdir -p rfc            # This took about 45 minutes for me
cd rfc                  # ..and needs about 500 MiB space
( for num in {1..9968}; do   # Range valid circa 2026-05-13
    echo https://www.rfc-editor.org/rfc/rfc${num}.txt
  done ) | wget -N -i - # -N update is ~3X faster than xfer
