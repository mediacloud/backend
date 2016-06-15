#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

#use MediaWords::DB;
#use Modern::Perl "2015";
#use MediaWords::CommonLibs;

#use MediaWords::DBI::DownloadTexts;
#use MediaWords::DBI::Stories;
#use MediaWords::StoryVectors;
#use MediaWords::Util::Process;

#!/home/dlarochelle/perl5/perlbrew/perls/perl-5.14.2/bin/perl

use strict;
use 5.008001;
use Carton::CLI::MediaWords;

sub main
{
    Carton::CLI::MediaWords->new->run( @ARGV );
}

main();
