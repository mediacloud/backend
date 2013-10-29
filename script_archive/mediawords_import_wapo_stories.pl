#!/usr/bin/env perl

# add a story for every story in the wapo archives here:
# 

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Date::Format;
use Encode;
use LWP::Simple;

use MediaWords::DB;
use MediaWords::Util::SQL;

use constant WAPO_MEDIA_ID => 2;
use constant START_DATE => '2012-09-01';
use constant END_DATE => '2012-09-02';
#use constant END_DATE => '2013-06-01';

sub get_archive_page_content
{
    my ( $date ) = @_;
    
    my $url_date = Date::Format::time2str( "%Y/%b/%d", MediaWords::Util::SQL::get_epoch_from_sql_date( $date ) );
    
    my $html = LWP::Simple::get( "http://articles.washingtonpost.com/$url_date" );
    
    die( "Unable to fetch html for date $url_date" ) unless ( $html );
    
    return $html;
}

sub import_story
{
    my ( $db, $url, $title, $date ) = @_;
    
    my $existing_story = $db->query( <<END, WAPO_MEDIA_ID, $title )->hash;
select * from stories where media_id = ? and lower( title ) = lower( ? )
END
    if ( $existing_story )
    {
        print STDERR "match\n";
        return;
    }

}

sub import_date
{
    my ( $db, $date ) = @_;
    
    my $html = get_archive_page_content( $date );
    
    while ( $html =~ m~<li><h3><a title=\"([^\"]*)\"\s+href=\"([^\"]*)\">~gsm )
    {
        my ( $title, $url ) = ( $1, $2 );
        print STDERR "$date: '$url' '$title'\n";
        import_story( $db, $url, $title, $date );
    }
}

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    for ( my $date = START_DATE; $date lt END_DATE; $date = MediaWords::Util::SQL::increment_day( $date ) )
    {
        print STDERR "date: $date\n";
        import_date( $db, $date );
    }
}

main();
