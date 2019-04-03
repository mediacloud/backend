#!/bin/bash

set -u
set -e

psql -c "SELECT rescraping_changes(); SELECT update_feeds_from_yesterday()"
