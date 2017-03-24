#!/bin/bash
#
# Autogenerates Table of Contents from Markdown doc and inserts / updates it
# into the document between given markers:
#
#     <!-- MEDIACLOUD-TOC-START -->
#
#     This is where TOC will be inserted.
#
#     <!-- MEDIACLOUD-TOC-END -->
#

set -u
set -e

PWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "${1:-}" ]; then
    echo "Usage: $0 markdown-file.md"
    exit 1
fi

if [ `uname` == 'Darwin' ]; then
    SED=gsed
else
    SED=sed
fi

TEMP_DIR=$(mktemp -d)


MARKDOWN_FILE_PATH="$1"
if [ ! -f "$MARKDOWN_FILE_PATH" ]; then
    echo "Markdown file was not found at $MARKDOWN_FILE_PATH."
    exit 1
fi

GH_MD_TOC_PATH="$PWD/github-markdown-toc/gh-md-toc"
if [ ! -f "$GH_MD_TOC_PATH" ]; then
    echo "gh-md-toc was not found at $GH_MD_TOC_PATH."
    exit 1
fi

TOC_START_MARKER="<!-- MEDIACLOUD-TOC-START -->"
TOC_END_MARKER="<!-- MEDIACLOUD-TOC-END -->"

if ! grep -q "$TOC_START_MARKER" "$MARKDOWN_FILE_PATH"; then
    echo "File $MARKDOWN_FILE_PATH does not have TOC start marker '$TOC_START_MARKER'."
    exit 1
fi

if ! grep -q "$TOC_END_MARKER" "$MARKDOWN_FILE_PATH"; then
    echo "File $MARKDOWN_FILE_PATH does not have TOC end marker '$TOC_END_MARKER'."
    exit 1
fi

echo "Removing old TOC (so that the old TOC header doesn't get included into new TOC's header)..."
gawk -i inplace "
    BEGIN       {p=1}
    /^$TOC_START_MARKER/   {print;p=0}
    /^$TOC_END_MARKER/     {p=1}
    p" "$MARKDOWN_FILE_PATH"

echo "Generating new TOC..."
TEMP_TOC_PATH="$TEMP_DIR/toc.md"
"$GH_MD_TOC_PATH" "$MARKDOWN_FILE_PATH" > "$TEMP_TOC_PATH"
echo "----" >> "$TEMP_TOC_PATH"

echo "Removing ad..."
gawk -i inplace '!/Created by \[gh-md-toc\]/' "$TEMP_TOC_PATH"

echo "Inserting new TOC into file..."
gawk -i inplace "
    BEGIN       {p=1}
    /^$TOC_START_MARKER/   {print;system(\"cat $TEMP_TOC_PATH\");p=0}
    /^$TOC_END_MARKER/     {p=1}
    p" "$MARKDOWN_FILE_PATH"

echo "Done."
