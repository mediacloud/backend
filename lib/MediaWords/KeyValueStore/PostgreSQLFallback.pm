package MediaWords::KeyValueStore::PostgreSQLFallback;

# subclass of ::PostgreSQL storage method, used for debugging

use strict;
use warnings;

use Moose;
extends 'MediaWords::KeyValueStore::PostgreSQL';

use Modern::Perl "2013";

no Moose;    # gets rid of scaffolding

1;
