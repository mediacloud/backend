#!/bin/bash
#
# Generate Lithuanian stemmer Python class using a Snowball source
#
# Usage: ./generate_python_class.sh
#

PWD="$( cd "$(dirname "$0")" ; pwd -P )"
SNOWBALL_DIR="$PWD/../../../snowball/"
SNOWBALL_BIN="$SNOWBALL_DIR/snowball"

( cd "$SNOWBALL_DIR"; gmake )

"$SNOWBALL_BIN" \
    snowball_stemmer/conservative.sbl \
    -output lithuanian_stemmer \
    -python \
    -name LithuanianStemmer \
    -parentclassname BaseStemmer
