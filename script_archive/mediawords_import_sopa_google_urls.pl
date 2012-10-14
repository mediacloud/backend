#!/usr/bin/env perl

# parse a set of csvs, each of which contains a list of urls found be
# searching google for various terms related to sopa/pipa/coica.  Insert
# each of the urls into sopa_links as links from google stories.

# usage: mediawords_import_sopa_google_urls.pl <csv file 1> [ <csv file 2> ... ]

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;

use Data::Dumper;
use Date::Format;
use Date::Parse;
use DateTime;
use Encode;
use Text::CSV_XS;

use constant SOPA_GOOGLE_SEARCH_NAME => 'Sopa Google Search';
use constant SOPA_GOOGLE_SEARCH_URL  => 'urn://sopa.google.search';

# get a list of hashes from the csv file.  return hashes with the following fields:
# [ url search rank publish_date search_date notes ]
sub get_links_from_csv
{
    my ( $file ) = @_;

    my $csv = Text::CSV_XS->new( { binary => 1 } ) || die "error using CSV_XS: " . Text::CSV_XS->error_diag();

    open my $fh, "<:encoding(utf8)", $file || die "Unable to open file $file: $!\n";

    #"URL","Search","Rank","Date of Publication","Date of Search","Notes"
    $csv->column_names( qw(url search rank publish_date search_date notes) );

    $csv->getline( $fh );

    my $links = [];
    while ( my $link = $csv->getline_hr( $fh ) )
    {
        for my $d ( qw(publish_date search_date) )
        {
            if ( $link->{ $d } )
            {
                $link->{ $d } = Date::Format::time2str( "%Y-%m-%d", Date::Parse::str2time( $link->{ $d } ) );
            }

            $link->{ search_date } ||= '2012-05-18';
        }

        push( @{ $links }, $link );
    }

    splice( @{ $links }, 50 ) if ( @{ $links } > 50 );

    return $links;
}

# find the media source for the sopa google searches, or create one if needed.
# include a 'feeds_id' field in the media source that points to the single feed for
# the media source
sub find_or_create_search_medium
{
    my ( $db ) = @_;

    my $medium = $db->query( "select m.*, f.feeds_id from media m, feeds f where m.media_id = f.media_id and m.name = ?",
        SOPA_GOOGLE_SEARCH_NAME )->hash;

    return $medium if ( $medium );

    $medium = $db->create(
        'media',
        {
            name        => SOPA_GOOGLE_SEARCH_NAME,
            url         => SOPA_GOOGLE_SEARCH_URL,
            feeds_added => 't',
            moderated   => 't'
        }
    );

    my $feed = $db->create(
        'feeds',
        {
            media_id => $medium->{ media_id },
            name     => SOPA_GOOGLE_SEARCH_NAME,
            url      => SOPA_GOOGLE_SEARCH_URL,
        }
    );

    $medium->{ feeds_id } = $feed->{ feeds_id };

    return $medium;
}

# get story representing the particular google search
sub get_search_story
{
    my ( $db, $link ) = @_;

    my $medium = find_or_create_search_medium( $db );

    my $story_url   = SOPA_GOOGLE_SEARCH_URL . "/$link->{ search }";
    my $story_title = SOPA_GOOGLE_SEARCH_NAME . ": $link->{ search }";

    my $story =
      $db->query( "select * from stories where media_id = ? and url = ?", $medium->{ media_id }, $story_url )->hash;

    return $story if ( $story );

    print "$link->{ search_date }\n";

    my $story = $db->create(
        'stories',
        {
            media_id     => $medium->{ media_id },
            url          => $story_url,
            guid         => $story_url,
            title        => $story_title,
            publish_date => $link->{ search_date },
            collect_date => DateTime->now->datetime
        }
    );

    $db->create( 'feeds_stories_map', { stories_id => $story->{ stories_id }, feeds_id => $medium->{ feeds_id } } );

    return $story;
}

# add a sopa_link for the given link.  if necessary, also add a story for the
# sopa search
sub import_link
{
    my ( $db, $link ) = @_;

    my $story = get_search_story( $db, $link );
    my $enc_url = encode( 'utf8', $link->{ url } );

    print "$story->{ stories_id } / $enc_url\n";

    my $link =
      $db->query( "select * from sopa_links where stories_id = ? and url = ?", $story->{ stories_id }, $enc_url )->hash;

    if ( !$link )
    {
        print "create link\n";
        $db->create( "sopa_links", { stories_id => $story->{ stories_id }, url => $enc_url } );
    }
}

# import the urls from the given csv file
sub import_links_from_csv
{
    my ( $db, $file ) = @_;

    print "FILE: $file\n";

    my $links = get_links_from_csv( $file );

    map { import_link( $db, $_ ) } @{ $links };
}

sub main
{
    my @csv_files = @ARGV;

    if ( !@csv_files )
    {
        die( "usage: $0 <csv file 1> [ <csv file 2> ... ]" );
    }

    my $db = MediaWords::DB::connect_to_db;

    map { import_links_from_csv( $db, $_ ) } @csv_files;
}

main();
