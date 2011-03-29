#!/usr/bin/perl

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::StoryVectors;
use MediaWords::Util::SQL;

sub main 
{
    my $db = MediaWords::DB::connect_to_db;
    
    $db->dbh->{ AutoCommit } = 0;

    my $topics = $db->query( "select * from dashboard_topics where start_date > '2010-04-01'" )->hashes;
        
    for my $topic ( @{ $topics } )
    {
        print STDERR "updating: $topic->{ name }\n";
        MediaWords::StoryVectors::update_aggregate_words( $db, '2010-04-01', $topic->{ start_date }, 0, $topic->{ dashboard_topics_id } );
    }
    
    my $topics = $db->query( "select * from dashboard_topics where end_date < now()" )->hashes;
    
    my ( $yesterday ) = $db->query( "select ( now() - interval '12 hours' )::date" )->flat;
    for my $topic ( @{ $topics } )
    {
        print STDERR "updating: $topic->{ name }\n";
        MediaWords::StoryVectors::update_aggregate_words( $db, $topic->{ end_date }, $yesterday, 0, $topic->{ dashboard_topics_id } );
    }
        
}

main();