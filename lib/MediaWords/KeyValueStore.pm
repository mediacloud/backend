package MediaWords::KeyValueStore;

use strict;
use warnings;

use Moose::Role;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

requires 'BUILD';
requires 'fetch_content';
requires 'store_content';
requires 'remove_content';
requires 'content_exists';

no Moose;    # gets rid of scaffolding

1;
