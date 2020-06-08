#!/usr/bin/env bash
#
# Update certificates
#
# Adapted from https://github.com/docker-library/openjdk/blob/master/14/jdk/Dockerfile
#

set -Eeuo pipefail

if ! [ -d "$JAVA_HOME" ]; then
    echo >&2 "error: missing JAVA_HOME environment variable"
    exit 1
fi

# 8-jdk uses "$JAVA_HOME/jre/lib/security/cacerts" and 8-jre and 11+ uses "$JAVA_HOME/lib/security/cacerts" directly (no "jre" directory)
cacertsFile=
for f in "$JAVA_HOME/lib/security/cacerts" "$JAVA_HOME/jre/lib/security/cacerts"; do
    if [ -e "$f" ]; then
        cacertsFile="$f"
        break
    fi
done

if [ -z "$cacertsFile" ] || ! [ -f "$cacertsFile" ]; then
    echo >&2 "error: failed to find cacerts file in $JAVA_HOME"
    exit 1
fi

trust extract \
    --overwrite \
    --format=java-cacerts \
    --filter=ca-anchors \
    --purpose=server-auth \
    "$cacertsFile"
