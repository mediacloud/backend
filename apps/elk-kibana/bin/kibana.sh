#!/bin/bash

set -u
set -e


exec /opt/kibana/bin/kibana \
    --cpu.cgroup.path.override=/ \
    --cpuacct.cgroup.path.override=/
