#!/bin/bash

pandoc -s -S --toc --toc-depth=4 -c api_2_0_spec.css api_2_0_spec.md -o api_2_0_spec.html

