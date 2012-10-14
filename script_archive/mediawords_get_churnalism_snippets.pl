#!/usr/bin/env perl

# call churnalism api and print out json results
use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;
use LWP::UserAgent;

use MediaWords::DB;
use MediaWords::DBI::Stories;

use constant CHURNALISM_API => 'http://ec2-50-16-162-209.compute-1.amazonaws.com/api/search/';

# get list of stories, including the extracted text
sub get_stories
{
    my ( $db, $start_date, $end_date, $media_sets_ids ) = @_;
    
    my $media_sets_ids_list = join( ',', @{ $media_sets_ids } );
    
    my $query  = <<END;
select * from stories s, media_sets_media_map msmm
    where s.media_id = msmm.media_id and msmm.media_sets_id in ( $media_sets_ids_list ) and
        date_trunc( 'day', s.publish_date ) between '$start_date'::date and '$end_date'::date
END

    my $stories = $db->query( $query )->hashes;
    
    map { $_->{ text } = MediaWords::DBI::Stories::get_text( $db, $_ ) } @{ $stories };
    
    return $stories;
}

# call churnalism api and print out json results
sub print_churnalism_results
{
    my ( $story ) = @_;
    
    print STDERR "fetching response for $story->{ title }\n";
    
    my $ua = LWP::UserAgent->new();
    
    $ua->agent( 'Media Cloud (hroberts@cyber.law.harvard.edu)' );
    
    my $res = $ua->post( CHURNALISM_API, { title => $story->{ title }, url => $story->{ url }, text => $story->{ text } } );
    
    if ( $res->is_success )
    {
        print $res->content 
    }
    else
    {
        # print STDERR "ERROR FETCHING '$story->{ url }'\n";
        warn( "ERROR FETCHING '$story->{ url }'\n" . $res->request->as_string . "\n" . $res->as_string );
    }
}

sub main 
{
    my ( $start_date, $end_date, $media_sets_ids );

    $media_sets_ids = [];

    Getopt::Long::GetOptions(
        "start_date=s" => \$start_date,
        "end_date=s" => \$end_date,
        "media_set=s" => $media_sets_ids ) || return;

    die( "usage: $0 --start_date < start date > --end_date < end date > [ --media_set < media set id > ... ]" )
        unless ( $start_date && $end_date && @{ $media_sets_ids } );
    
    my $db = MediaWords::DB::connect_to_db;
    
    my $stories = get_stories( $db, $start_date, $end_date, $media_sets_ids );
    
    map { print_churnalism_results( $_ ) } @{ $stories };
}

main();