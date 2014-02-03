#!/bin/bash

 ~/.cabal/bin/pandoc --standalone --self-contained --smart --toc --toc-depth=4 \
--include-in-header=api_2_0_spec-head.html --number-sections --to=html5 \
api_2_0_spec.md --output=api_2_0_spec.html
