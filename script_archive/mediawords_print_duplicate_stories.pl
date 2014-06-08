#!/usr/bin/env perl

# given a list of stories_ids one per line, print any duplicates

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::DBI::Stories;

sub print_dup_stories
{
    my ( $dup_stories ) = @_;

    for my $dup_story_list ( @{ $dup_stories } )
    {
        print "\t-\n";
        map { print "\t\t$_->{ title } [$_->{ url }]\n" } @{ $dup_story_list };
    }
}

sub main
{
    binmode( STDERR, "utf8" );
    binmode( STDOUT, "utf8" );

    my $db = MediaWords::DB::connect_to_db;

    my $stories = [];
    while ( my $stories_id = <> )
    {
        chomp( $stories_id );
        my $story = $db->find_by_id( 'stories', $stories_id ) || die( "unable to find story '$stories_id'" );
        push( $stories, $story );
    }

    my $title_dup_stories = MediaWords::DBI::Stories::get_medium_dup_stories_by_title( $db, $stories );
    my $url_dup_stories = MediaWords::DBI::Stories::get_medium_dup_stories_by_url( $db, $stories );

    print "TITLE DUPS:\n";
    print_dup_stories( $title_dup_stories );

    print "URL DUPS:\n";
    print_dup_stories( $url_dup_stories );
}

main();
