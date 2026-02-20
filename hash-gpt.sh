#!/bin/sh

# U-Boot configuration script for Spectrum SAX1V1K

# Author: Lanchon (https://github.com/Lanchon)
# Date: 2024-09-18
# License: GPL v3 or newer

# Hashes main GPT skipping header CRCs and partition GUIDs
# Assumes standard GPT size with 128 entries of 128 bytes each
hash_gpt() {
  {
    dd bs=1 count=$(( 0x210 )) 2> /dev/null
    dd bs=1 skip=4 count=0 2> /dev/null     # skip CRC at 0x210
    dd bs=1 count=$(( 0x258 - 0x214 )) 2> /dev/null
    dd bs=1 skip=4 count=0 2> /dev/null     # skip CRC at 0x258
    dd bs=1 count=$(( 0x400 - 0x25c )) 2> /dev/null

    # entries in partition array at 0x400
    n=$(( (0x4400 - 0x400) / 0x80 ))
    while [ $n != 0 ]; do
      dd bs=1 count=$(( 0x10 )) 2> /dev/null
      dd bs=1 skip=16 count=0 2> /dev/null  # skip GUID at 0x10
      dd bs=1 count=$(( 0x60 )) 2> /dev/null
      n=$(( n - 1 ))
    done
  } | md5sum | cut -d' ' -f1
}

hash_gpt "$@"

