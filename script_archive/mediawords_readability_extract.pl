#!/usr/bin/env perl

#
# Enqueue MediaWords::GearmanFunction::CM::DumpControversy job
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;

use MediaWords::CommonLibs;

#use MediaWords::CM::Dump;
#use MediaWords::DB;
#use MediaWords::CM;
#use MediaWords::GearmanFunction;
#use MediaWords::GearmanFunction::CM::DumpControversy;
#use Gearman::JobScheduler;

use MediaWords::Thrift::Extractor;

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    $| = 1;

    my $file_name;

    Getopt::Long::GetOptions( "file=s" => \$file_name ) || return;

    die( "Usage: $0 --file < html file >" ) unless ( $file_name );

    my $raw_html = "<html><title>article title</title><body><p>paragraph 1</p></body>";

    my $result = MediaWords::Thrift::Extractor::extract_html( $raw_html );

    say Dumper( $result );
}

main();

__END__
