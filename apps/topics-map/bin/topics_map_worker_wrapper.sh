#!/bin/bash

set -u
set -e

# Make Java subprocess use 90% of available RAM allotted to the container
MC_RAM_SIZE=$(/container_memory_limit.sh)
MC_JAVA_MX=$((MC_RAM_SIZE * 9 / 10))

exec topics_map_worker.py --memory_limit_mb $MC_JAVA_MX
