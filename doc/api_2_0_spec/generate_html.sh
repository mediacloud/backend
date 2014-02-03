#!/bin/bash

pandoc -s -S --toc --toc-depth=4 --include-in-header=api_2_0_spec-head.html api_2_0_spec.md -o api_2_0_spec.html

