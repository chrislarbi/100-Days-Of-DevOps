#!/bin/bash
# Day 42: Create a Custom Docker Bridge Network (media) on App Server 2 (stapp02)
#
# Description:
# Creates a custom user-defined Docker bridge network named 'media'
# with an explicit subnet and IP range (192.168.30.0/24).

set -e

echo "=== Step 1: Create custom Docker bridge network 'media' ==="
docker network create \
  -d bridge \
  --subnet=192.168.30.0/24 \
  --ip-range=192.168.30.0/24 \
  media

echo "=== Step 2: Inspect and verify created network ==="
docker network inspect media
