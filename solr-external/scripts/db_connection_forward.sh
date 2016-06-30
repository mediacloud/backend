#!/bin/bash

ssh  -o ServerAliveInterval=300  -N dlarochelle@doc.law.harvard.edu -L 6000:amanda:5432
