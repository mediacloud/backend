#!/usr/bin/perl

# run a loop extracting the text of any downloads that have not been extracted yet

# usage: mediawords_extract_text.pl [<process num> <num of processes>]
#
# to run several instances in parallel, supply the number of the given process and the total number of processes
# example:
# mediawords_extract_tags.pl 1 4 &
# mediawords_extract_tags.pl 2 4 &
# mediawords_extract_tags.pl 3 4 &
# mediawords_extract_tags.pl 4 4 &

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

BEGIN
{
    use constant MODULES => qw(Calais);

    for my $module ( MODULES )
    {
        eval( "use MediaWords::Tagger::${module};" );
        if ( $@ )
        {
            die( "error loading $module: $@" );
        }
    }
}

use Encode;
use MediaWords::DB;
use DBIx::Simple;
use DBIx::Simple::MediaWords;
use MediaWords::Tagger;
use MediaWords::Crawler::Extractor;
use MediaWords::DBI::Downloads;
use List::Uniq ':all';

my $_tags_id_cache     = {};
my $_tag_sets_id_cache = {};
my $_html_stripper;

# get cached id of the tag.  create the tag if necessary.
sub get_tags_id
{
    my ( $db, $tag_sets_id, $term ) = @_;

    if ( $_tags_id_cache->{ $tag_sets_id }->{ $term } )
    {
        return $_tags_id_cache->{ $tag_sets_id }->{ $term };
    }

    my $tag = $db->resultset( 'Tags' )->find_or_create(
        {
            tag         => $term,
            tag_sets_id => $tag_sets_id
        }
    );

    $_tags_id_cache->{ $tag_sets_id }->{ $term } = $tag->tags_id;

    return $tag->tags_id;
}

#TODO replace the add_tags here and in mediawords_extract_text with a single function
# generate tags for the extracted text and add them to the download's story
sub strip_html
{
    my ( $text ) = @_;
    $_html_stripper ||= HTML::Strip->new;

    $_html_stripper->eof();

    my $ret = $_html_stripper->parse( $text );

    return $ret;
}

my $_tags_id_cache = {};
my $_html_stripper;

# get cached id of the tag.  create the tag if necessary.
sub get_tag_sets_id
{
    my ( $db, $tag_set_name ) = @_;

    if ( $_tag_sets_id_cache->{ $tag_set_name } )
    {

        #        print STDERR "get_tag_sets_id returning: " .  $_tag_sets_id_cache->{$tag_set_name} . "\n";
        return $_tag_sets_id_cache->{ $tag_set_name };
    }

    my $tag_set = $db->resultset( 'TagSets' )->find_or_create( { name => $tag_set_name } );

    $_tag_sets_id_cache->{ $tag_set_name } = $tag_set->tag_sets_id;

    return $tag_set->tag_sets_id;
}

my $_dbs = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
  || die DBIx::Simple::MediaWords->error;

# generate tags for the extracted text and add them to the download's story
sub add_tags
{
    my ( $db, $download, $extracted_text ) = @_;

    $_html_stripper ||= HTML::Strip->new;

    my $result = $_dbs->query( "select title, description from stories where stories_id = ?", $download->{ stories_id } );

    my ( $title, $description ) = @{ $result->array() };

    my $text =
      encode( 'utf8',
        strip_html( $title || '' ) . "\n" . strip_html( $description || '' ) . "\n" . ( $extracted_text || '' ) );

    $_html_stripper->eof;

    my @modules_list = ( MODULES );
    my $tags_hash = MediaWords::Tagger::get_tags_for_modules( $text, \@modules_list, $download );

    for my $tag_set_name ( keys( %{ $tags_hash } ) )
    {
        my @terms = @{ $tags_hash->{ $tag_set_name } };

        add_tags_to_db( $db, $tag_set_name, \@terms, $download->{ stories_id } );
    }
}

sub add_tags_to_db
{
    my ( $db, $tag_set_name, $terms, $stories_id ) = @_;

    my $tag_set_id = get_tag_sets_id( $db, $tag_set_name );

    for my $term ( uniq( @{ $terms } ) )
    {
        $_dbs->query( "INSERT INTO stories_tags_map (tags_id, stories_id) VALUES (?, ?) ",
            get_tags_id( $db, $tag_set_id, $term ), $stories_id );

        #         $db->resultset('StoriesTagsMap')->find_or_create(
        #                                                          {
        #                                                           tags_id    => get_tags_id( $db, $tag_set_id, $term ),
        #                                                           stories_id => $stories_id
        #                 }
        #                                                         );
    }

    print STDERR "TAGS $tag_set_name: " . join( ',', map { "<$_>" } @{ $terms } ) . "\n";
}

sub main
{

    my ( $process_num, $num_processes ) = @ARGV;

    $process_num   ||= 1;
    $num_processes ||= 1;

    my $db = MediaWords::DB->authenticate();

    my $dbs = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
      || die DBIx::Simple::MediaWords->error;

    my $downloads_processed = 0;

    #make sure that we get a download_id tagged by add_calais_tags and not the extractor
    my $start_download_id = $dbs->query(
"select min(parent) from (select parent from downloads where type = 'calais' order by downloads_id desc limit 1000) as foo"
    )->hash->{ min };

    print STDERR "start_download_id $start_download_id\n";

    while ( 1 )
    {
        print STDERR "while(1) loop\n";

        my $unextracted_downloads_query =
" select content.* from downloads content left join downloads calais ON  (content.downloads_id=calais.parent and calais.type='calais') where content.extracted and content.type='content' and calais.parent is null limit 80000";

        #optimize the query so that postgresql doesn't have to look through the whole downloads table
        $unextracted_downloads_query =
          "select * from downloads where type = 'content' and downloads_id >= ? and downloads_id <= ?";

        print STDERR "Running query '$unextracted_downloads_query'\n";

        my $download_batch_size = 1000;

        my $downloads =
          $dbs->query( $unextracted_downloads_query, $start_download_id, $start_download_id + $download_batch_size );

        $start_download_id += $download_batch_size;

        print STDERR "query completed for $unextracted_downloads_query\n";

        my $download_found;
        my $previous_processed_down_load_end_time = time();
        while ( my $download = $downloads->hash() )
        {

            $downloads_processed++;

            if ( $downloads_processed > 1000 )
            {

                #                exit;
            }

            print STDERR ' while ( my $download' . "\n";

            # ignore downloads for multi-processor runs
            if ( ( $download->{ downloads_id } + $process_num ) % $num_processes )
            {
                print STDERR "Ignoring  " . $download->{ downloads_id } . "  + $process_num \n";
                next;
            }

            my @rows = $dbs->query( "select * from downloads where downloads.parent = ? and downloads.type='calais'",
                $download->{ downloads_id } )->array;

            print @rows;

            if ( @rows > 0 )
            {
                print STDERR "download " . $download->{ downloads_id } . " already calaised\n";
                next;
            }

            print STDERR "processing download id:" . $download->{ downloads_id } . "  -- " .
              ( ( time() ) - $previous_processed_down_load_end_time ) . " since last download processed\n";

            $download_found = 1;

            my $extracted_text_start_time = time();

            my $extracted_text = MediaWords::DBI::Downloads::get_previously_extracted_text( $dbs, $download );

            if ( !( $extracted_text ) )
            {
                print STDERR "skipping calais tagging from empty content: '$extracted_text'  from " .
                  $download->{ downloads_id } . "\n";
                my $calais_download = $db->resultset( 'Downloads' )->create(
                    {
                        feeds_id      => $download->{ feeds_id },
                        stories_id    => $download->{ stories_id },
                        parent        => $download->{ downloads_id },
                        url           => $download->{ url },
                        host          => lc( ( URI::Split::uri_split( $download->{ url } ) )[ 1 ] ),
                        type          => 'calais',
                        sequence      => $download->{ sequence } + 1,
                        state         => 'success',
                        priority      => $download->{ priority } + 1,
                        download_time => 'now()',
                        path          => 'ERROR_EMPTY_SOURCE_CONTENT',
                        extracted     => 'f'
                    }
                );
                next;
            }

            my $extracted_text_end_time = time();

            print STDERR "Got extracted text took " . ( $extracted_text_end_time - $extracted_text_start_time ) .
              " secs : " .
              length( $extracted_text ) . "characters\n";

            add_tags( $db, $download, $extracted_text );

            print "\n";
            print STDERR "Completed calais tagging download\n";

            $previous_processed_down_load_end_time = time();

        }

        if ( !$download_found )
        {
            print STDERR "no downloads found. sleeping ...\n";

            sleep 1;
        }

        print STDERR "Completed batches calais tagging downloads\n";
    }
}

eval { main(); };

print "exit: $@\n";
