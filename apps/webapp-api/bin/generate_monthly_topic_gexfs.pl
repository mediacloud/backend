#!/usr/bin/env perl

# generate overall and monthly gexfs for a topic, eliminating some large platform media sources

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Encode;
use File::Slurp;

use MediaWords::TM::Snapshot::GEXF;
use MediaWords::TM::Snapshot::Views;


main();
