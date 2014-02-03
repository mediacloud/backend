#!/bin/bash

 ~/.cabal/bin/pandoc -f markdown --table-of-contents -c api_2_0_spec.css --self-contained -t html5 api_2_0_spec.md

