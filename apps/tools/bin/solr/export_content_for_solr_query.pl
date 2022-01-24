#!/usr/bin/env perl

# run a solr query.  save the content of each of the returned stories

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Encode;
use File::Path;
use File::Slurp;
use Getopt::Long;

use MediaWords::DB;
use MediaWords::DBI::Stories;
use MediaWords::Solr;

Readonly my $MAX_ROWS => 10_000_000;

# get the requested form of content for the story
sub get_content
{
    my ( $db, $stories_id, $content_type ) = @_;

    if ( $content_type eq 'sentences' )
    {
        my ( $sentences ) = $db->query( <<SQL, $stories_id )->flat;
select string_agg( sentence, ' ' ) from (
    select sentence from story_sentences where stories_id = \$1 order by stories_id ) q
SQL
        return $sentences;
    }
    elsif ( $content_type eq 'text' )
    {
        my ( $text ) = $db->query( <<SQL,
            SELECT STRING_AGG(download_text, ' ')
            FROM (
                SELECT download_text
                FROM download_texts AS dt
                    JOIN downloads AS d USING (downloads_id)
                WHERE d.stories_id = \$1
                ORDER BY downloads_id
            ) AS q
SQL
            $stories_id
        )->flat;
        return $text;
    }
    elsif ( $content_type eq 'raw' )
    {
        my $story = $db->require_by_id( 'stories', $stories_id );
        my $content = MediaWords::DBI::Downloads::get_content_for_first_download( $db, $story );
        return $content;
    }
    else
    {
        die( "Unknown content type '$content_type'" );
    }
}

# dump the content of each story to a file with the namd <id>.txt in the given directory
sub dump_stories_to_dir
{
    my ( $db, $stories_ids, $dir, $content_type ) = @_;

    if ( !-d $dir )
    {
        mkdir( $dir ) || die( "Unable to make dir: $!" );
    }

    for my $stories_id ( @{ $stories_ids } )
    {
        DEBUG( "fetching content for $stories_id ..." );

        my $content = get_content( $db, $stories_id, $content_type ) || '';

        my $padded_stories_id = sprintf( "%012d", $stories_id );
        my $dirs = [ $padded_stories_id =~ m/../g ];
        my $path = $dir . '/' . join( '/', @{ $dirs } );
        File::Path::make_path( $path );

        File::Slurp::write_file( "$path/$padded_stories_id.txt", encode( 'utf8', $content ) );

        DEBUG( "wrote content length " . length( $content ) );
    }
}

# do a test run of the text extractor
sub main
{
    my ( $query, $filter_query, $dir, $content_type );

    GetOptions(
        'query|q=s'        => \$query,
        'filter_query|fq=s'=> \$filter_query,
        'dir|d=s'          => \$dir,
        'content_type|c=s' => \$content_type
    ) || die( "error parsing options" );

    die( "usage: $0 -q <solr or sql query> -d <output dir> [-c text|sentences|raw] [-fq filter query]" )
        unless ( $query && $dir );

    $content_type ||= 'sentences';

    my $db = MediaWords::DB::connect_to_db();

    my $stories_ids;
    if ( $query =~ /^select/i )
    {
        DEBUG( "running sql query ..." );

        $stories_ids = $db->query( $query )->flat;
    }
    else
    {
        DEBUG( "running solr search ..." );

        my $params = { q => $query, fq => $filter_query, rows => $MAX_ROWS };
        $stories_ids = MediaWords::Solr::search_solr_for_stories_ids( $db, $params );
    }

    DEBUG( "found " . scalar( @{ $stories_ids } ) . " stories" );

    die( "max stories returned" ) if ( scalar( @{ $stories_ids } ) >= $MAX_ROWS );

    dump_stories_to_dir( $db, $stories_ids, $dir, $content_type );
}

main();
