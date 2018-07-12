#!/bin/bash
#
# Generate Catalan stemmer Python class using a Snowball source
#
# Usage: ./generate_python_class.sh
#

PWD="$( cd "$(dirname "$0")" ; pwd -P )"
SNOWBALL_DIR="$PWD/../../../snowball/"
SNOWBALL_BIN="$SNOWBALL_DIR/snowball"

( cd "$SNOWBALL_DIR"; gmake )

"$SNOWBALL_BIN" \
    snowball_stemmer/stemmer.sbl \
    -output catalan_stemmer \
    -python \
    -name CatalanStemmer \
    -parentclassname BaseStemmer
