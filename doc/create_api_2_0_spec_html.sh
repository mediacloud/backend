#!/bin/bash

pandoc -f markdown --table-of-contents --self-contained -t html5 api_2_0_spec.md
