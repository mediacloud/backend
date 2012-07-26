#!/usr/bin/env perl

# dump the all stories belonging to the given query, including the extracted text of each story, as a csv

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::DBI::Queries;
use MediaWords::Util::CSV;

sub main
{
    my ( $queries_id ) = @ARGV;

    if ( !$queries_id )
    {
        die( "usage: $0 <queries_id>" );
    }

    my $db = MediaWords::DB::connect_to_db;

    my $query = MediaWords::DBI::Queries::find_query_by_id( $db, $queries_id ) || die( "no query for '$queries_id'" );

    my $stories = MediaWords::DBI::Queries::get_stories_with_text( $db, $query );

    my $csv = MediaWords::Util::CSV::get_hashes_as_encoded_csv( $stories );

    binmode( STDOUT, 'utf-8' );

    print $csv;

}

main();

