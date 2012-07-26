package MediaWords::Pg::DependsList;

#A list of all modules needed by Pg/PL Perl stored procedures

use strict;

use HTML::StripPP;
use HTML::Entities qw( decode_entities  );
use Devel::Peek qw(Dump);
use Encode;
use List::Util qw(min);
use Lingua::StopWords;
use Lingua::Stem::Snowball;
use Data::Dumper;
use Time::Local;

1;
