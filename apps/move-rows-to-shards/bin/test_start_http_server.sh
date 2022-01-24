#!/bin/bash

set -u
set -e

exec java -jar /opt/move-rows-to-shards/move-rows-to-shards.jar test-http-start-workflow-fg-server

