#!/bin/bash

set -u
set -e

exec /opt/kibana/bin/kibana \
	--ops.cGroupOverrides.cpuPath=/ \
	--ops.cGroupOverrides.cpuAcctPath=/
