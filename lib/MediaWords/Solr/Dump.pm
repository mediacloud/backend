package MediaWords::Solr::Dump;

use forks;

# code to dump postgres data for import into solr

use strict;
use warnings;

use CHI;
use Data::Dumper;
use Digest::MD5;
use Encode;
use FileHandle;
use HTTP::Request;
use JSON;
use LWP::UserAgent;
use List::MoreUtils;
use List::Util;
use Parallel::ForkManager;
use Readonly;
use Text::CSV_XS;
use URI::Escape;

use MediaWords::DB;

use MediaWords::Solr;

my $_solr_select_url;

# order and names of fields exported to and imported from csv
Readonly my @CSV_FIELDS =>
  qw/stories_id media_id story_sentences_id solr_id publish_date publish_day sentence_number sentence title language
  processed_stories_id media_sets_id tags_id_media tags_id_stories tags_id_story_sentences/;

# numbner of lines in each chunk of csv to import
Readonly my $CSV_CHUNK_LINES => 10_000;

# how many sentences to fetch at a time from the postgres query
Readonly my $FETCH_BLOCK_SIZE => 10_000;

# max number of updated queued stories to import in one delta import
Readonly my $MAX_QUEUED_STORIES => 100_000;

# mark date before generating dump for storing in solr_imports after successful import
my $_import_date;

# run a postgres query and generate a table that lookups on the first column by the second column.
# assign that lookup to $data_lookup->{ $name }.
sub _set_lookup
{
    my ( $db, $data_lookup, $name, $query ) = @_;

    my $sth = $db->query( $query );

    my $lookup = {};
    while ( my $row = $sth->array )
    {
        $lookup->{ $row->[ 1 ] } = $row->[ 0 ];
    }

    $data_lookup->{ $name } = $lookup;
}

# add enough stories from the solr_import_stories
# queue to the stories_solr_import table that there are up to
# $MAX_QUEUED_STORIES in stories_solr_import for each solr_import
sub _add_media_stories_to_import
{
    my ( $db, $import_date, $num_delta_stories ) = @_;

    my $max_queued_stories = List::Util::max( 0, $MAX_QUEUED_STORIES - $num_delta_stories );
    my $num_queued_stories = $db->query( <<END, $max_queued_stories )->rows;
insert into delta_import_stories ( stories_id ) select stories_id from solr_import_stories limit ?
END

    if ( $num_queued_stories > 0 )
    {
        my ( $total_queued_stories ) = $db->query( "select count(*) from solr_import_stories" )->flat;

        print STDERR "added $num_queued_stories / $total_queued_stories queued stories to the import\n";
    }

}

# setup 'csr' cursor in postgres as the query to import the story_sentences
sub _declare_sentences_cursor
{
    my ( $db, $date_clause, $num_proc, $proc ) = @_;

    $db->dbh->do( <<END );
declare csr cursor for

    select
        ss.stories_id,
        ss.media_id,
        ss.story_sentences_id,
        ss.stories_id || '!' || ss.story_sentences_id solr_id,
        to_char( date_trunc( 'minute', publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_date,
        to_char( date_trunc( 'hour', publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_day,
        ss.sentence_number,
        ss.sentence,
        null title,
        ss.language

    from story_sentences ss

    where ( ss.stories_id % $num_proc = $proc - 1 )
        $date_clause
END

}

# setup 'csr' cursor in postgres as the query to import the story titles
sub _declare_titles_cursor
{
    my ( $db, $date_clause, $num_proc, $proc ) = @_;

    $db->dbh->do( <<END );
declare csr cursor for

    select
        s.stories_id,
        s.media_id,
        0 story_sentences_id,
        s.stories_id || '!' || 0 solr_id,
        to_char( date_trunc( 'minute', s.publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_date,
        to_char( date_trunc( 'hour', s.publish_date ), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') publish_day,
        0,
        null sentence,
        s.title,
        s.language

    from stories s

    where ( s.stories_id % $num_proc = $proc - 1 )
        $date_clause
END

}

# incrementally read the results from the 'csr' postgres cursor and print out the resulting
# sorl dump csv to the file
sub _print_csv_to_file_from_csr
{
    my ( $db, $fh, $data_lookup, $print_header ) = @_;

    my $fields = \@CSV_FIELDS;

    my $csv = Text::CSV_XS->new( { binary => 1 } );

    if ( $print_header )
    {
        $csv->combine( @{ $fields } );
        $fh->print( $csv->string . "\n" );
    }

    my $imported_stories_ids = {};
    my $i                    = 0;
    while ( 1 )
    {
        my $sth = $db->dbh->prepare( "fetch $FETCH_BLOCK_SIZE from csr" );

        $sth->execute;

        last if 0 == $sth->rows;

        # use fetchrow_arrayref to optimize fetching and lookup speed below -- perl
        # cpu is a significant bottleneck for this script
        while ( my $row = $sth->fetchrow_arrayref )
        {
            my $stories_id         = $row->[ 0 ];
            my $media_id           = $row->[ 1 ];
            my $story_sentences_id = $row->[ 2 ];

            my $processed_stories_id = $data_lookup->{ ps }->{ $stories_id };
            next unless ( $processed_stories_id );

            my $media_sets_list   = $data_lookup->{ media_sets }->{ $media_id }        || '';
            my $media_tags_list   = $data_lookup->{ media_tags }->{ $media_id }        || '';
            my $stories_tags_list = $data_lookup->{ stories_tags }->{ $stories_id }    || '';
            my $ss_tags_list      = $data_lookup->{ ss_tags }->{ $story_sentences_id } || '';

            $csv->combine( @{ $row }, $processed_stories_id, $media_sets_list, $media_tags_list, $stories_tags_list,
                $ss_tags_list );
            $fh->print( encode( 'utf8', $csv->string . "\n" ) );

            $imported_stories_ids->{ $stories_id } = 1;
        }

        print STDERR time . " " . ( ++$i * $FETCH_BLOCK_SIZE ) . "\n";    # unless ( ++$i % 10 );
    }

    $db->dbh->do( "close csr" );

    return [ keys %{ $imported_stories_ids } ];
}

# get the date clause that restricts the import of all subsequent queries to just the
# delta stories
sub _get_delta_import_date_clause
{
    my ( $db, $delta ) = @_;

    return '' unless ( $delta );

    my ( $import_date ) = $db->query( "select import_date from solr_imports order by import_date desc limit 1" )->flat;

    $import_date //= '2000-01-01';

    print STDERR "importing delta from $import_date...\n";

    $db->query( <<END, $import_date );
create temporary table delta_import_stories as
select distinct stories_id
from story_sentences ss
where ss.db_row_last_updated > \$1
END
    my ( $num_delta_stories ) = $db->query( "select count(*) from delta_import_stories" )->flat;
    print STDERR "found $num_delta_stories stories for import ...\n";

    _add_media_stories_to_import( $db, $import_date, $num_delta_stories );

    return "and stories_id in ( select stories_id from delta_import_stories )";
}

# get the $data_lookup hash that has lookup tables for values to include
# for each of the processed_stories, media_sets, media_tags, stories_tags,
# and ss_tags fields for export to solr.
#
# This is basically just a manual
# client side join that we do in perl because we can get postgres to stream
# results much more quickly if we don't ask it to do this giant join on the
# server side.
sub _get_data_lookup
{
    my ( $db, $num_proc, $proc, $date_clause ) = @_;

    my $data_lookup = {};

    _set_lookup( $db, $data_lookup, 'ps', <<END );
select processed_stories_id, stories_id from processed_stories where stories_id % $num_proc = $proc - 1 $date_clause
END

    _set_lookup( $db, $data_lookup, 'media_sets', <<END );
select string_agg( media_sets_id::text, ';' ) media_sets_id, media_id from media_sets_media_map group by media_id
END
    _set_lookup( $db, $data_lookup, 'media_tags', <<END );
select string_agg( tags_id::text, ';' ) tag_list, media_id from media_tags_map group by media_id
END
    _set_lookup( $db, $data_lookup, 'stories_tags', <<END );
select string_agg( tags_id::text, ';' ) tag_list, stories_id
    from stories_tags_map
    where stories_id % $num_proc = $proc - 1 $date_clause
    group by stories_id
END
    _set_lookup( $db, $data_lookup, 'ss_tags', <<END );
select string_agg( tags_id::text, ';' ) tag_list, story_sentences_id
    from story_sentences_tags_map
    group by story_sentences_id
END

    return $data_lookup;
}

# print a csv dump of the postgres data to $file.
# run as job proc out of num_proc jobs, where each job is printg
# a separate set of data.
# if delta is true, only dump the data changed since the last dump
sub _print_csv_to_file_single_job
{
    my ( $db, $file, $num_proc, $proc, $delta ) = @_;

    # recreate db for forked processes
    $db ||= MediaWords::DB::connect_to_db;

    my $fh = FileHandle->new( ">$file" ) || die( "Unable to open file '$file': $@" );

    my $date_clause = _get_delta_import_date_clause( $db, $delta );

    my $data_lookup = _get_data_lookup( $db, $num_proc, $proc, $date_clause );

    $db->begin;

    print STDERR "exporting sentences ...\n";
    _declare_sentences_cursor( $db, $date_clause, $num_proc, $proc );
    my $sentence_stories_ids = _print_csv_to_file_from_csr( $db, $fh, $data_lookup, 1 );

    print STDERR "exporting titles ...\n";
    _declare_titles_cursor( $db, $date_clause, $num_proc, $proc );
    my $title_stories_ids = _print_csv_to_file_from_csr( $db, $fh, $data_lookup, 0 );

    $db->commit;

    return [ List::MoreUtils::uniq( @{ $sentence_stories_ids }, @{ $title_stories_ids } ) ];
}

# print a csv dump of the postgres data to $file_spec.
# run num_proc jobs in parallel to generate the dump.
# assume that the script is running on num_machines different machines.
# if delta is true, only dump the data changed since the last dump.
sub print_csv_to_file
{
    my ( $db, $file_spec, $num_proc, $delta, $min_proc, $max_proc ) = @_;

    $num_proc //= 1;
    $min_proc //= 1;
    $max_proc //= $num_proc;

    my $files;

    if ( $num_proc == 1 )
    {
        return _print_csv_to_file_single_job( $db, $file_spec, 1, 1, $delta );
    }
    else
    {
        my $threads = [];

        for my $proc ( $min_proc .. $max_proc )
        {
            # every generated file should have a unique id so that the
            # file positioncaches don't get reused between imports
            my $file_id = Digest::MD5::md5_hex( "$$-" . time() );
            my $file    = "$file_spec-$file_id-$proc";

            push( @{ $files }, $file );

            push( @{ $threads },
                threads->create( \&_print_csv_to_file_single_job, undef, $file, $num_proc, $proc, $delta ) );
        }

        my $all_stories_ids = [];
        for my $thread ( @{ $threads } )
        {
            my $stories_ids = $thread->join();
            push( @{ $all_stories_ids }, $stories_ids );
        }

        return $all_stories_ids;
    }
}

# get the solr select url; cache after the first call
sub _get_solr_select_url
{
    return $_solr_select_url if ( $_solr_select_url );

    my $db = MediaWords::DB::connect_to_db;

    $_solr_select_url = MediaWords::Solr::get_solr_select_url( $db );

    return $_solr_select_url;
}

# query solr for the given story_sentences_id and return true the story_sentences_id already exists in solr
sub _sentence_exists_in_solr
{
    my ( $story_sentences_id ) = @_;

    my $solr_select_url = _get_solr_select_url();

    my $ua = MediaWords::Util::Web::UserAgent;

    my $res = $ua->post( $solr_select_url, { q => "story_sentences_id:$story_sentences_id", rows => 0, wt => 'json' } );

    if ( !$res->is_success )
    {
        warn( "unable to query solr for story_sentences_id $story_sentences_id: " . $res->content );
        return 0;
    }

    my $json = $res->content;

    my $data;
    eval { $data = decode_json( $json ) };

    die( "Error parsing solr json: $@\n$json" ) if ( $@ );

    die( "Error received from solr: '$json'" ) if ( $data->{ error } );

    return $data->{ response }->{ numFound } ? 1 : 0;
}

# send a request to MediaWords::Solr::get_solr_url.  return 1
# on success and 0 on error.  if $staging is true, use the staging
# collection; otherwise use the live collection.
sub _solr_request
{
    my ( $url, $staging, $content ) = @_;

    # print STDERR "requesting url: $url ...\n";

    my $solr_url = MediaWords::Solr::get_solr_url;

    my $db = MediaWords::DB::connect_to_db;

    my $collection =
      $staging ? MediaWords::Solr::get_staging_collection( $db ) : MediaWords::Solr::get_live_collection( $db );

    my $abs_url = "${ solr_url }/${ collection }/${ url }";

    my $ua = LWP::UserAgent->new;

    # should be able to process about this fast.  otherwise, time out and throw error so that we can continue processing
    my $timeout;
    my $req;

    if ( $content )
    {
        $timeout = 120;

        $req = HTTP::Request->new( POST => $abs_url );
        $req->header( 'Content-type',   'text/plain; charset=utf-8' );
        $req->header( 'Content-length', length( $content ) );
        $req->content( $content );
    }
    else
    {
        $timeout = 500;
        $req = HTTP::Request->new( GET => $abs_url );
    }

    my $res;
    eval {
        local $SIG{ ALRM } = sub { die "alarm" };

        alarm $timeout;

        $res = $ua->request( $req );

        alarm 0;
    };

    if ( $@ )
    {
        die( $@ ) unless ( $@ =~ /^alarm at/ );

        say STDERR "timed out request";
        return "timed out request for $abs_url";
    }

    if ( !$res->is_success )
    {
        say STDERR "request failed:\n" . $res->content;
        return "request failed for $abs_url: " . $res->as_string;
    }

    return 0;
}

# return cache of the pos to read next from each file
sub _get_file_pos_cache
{
    my $mediacloud_data_dir = MediaWords::Util::Config::get_config->{ mediawords }->{ data_dir };

    return CHI->new(
        driver           => 'File',
        expires_in       => '1 year',
        expires_variance => '0.1',
        root_dir         => "${ mediacloud_data_dir }/cache/solr_import_file_pos",
        depth            => 4
    );
}

# get the file position to read next from the given file
sub _get_file_pos
{
    my ( $file ) = @_;

    my $abs_file = File::Spec->rel2abs( $file );

    my $cache = _get_file_pos_cache();

    return $cache->get( $abs_file ) || 0;
}

sub _set_file_pos
{
    my ( $file, $pos ) = @_;

    my $abs_file = File::Spec->rel2abs( $file );

    my $cache = _get_file_pos_cache();

    return $cache->set( $abs_file, $pos );
}

sub _get_file_errors_cache
{
    my ( $file ) = @_;

    my $abs_file = File::Spec->rel2abs( $file );

    my $mediacloud_data_dir = MediaWords::Util::Config::get_config->{ mediawords }->{ data_dir };

    return CHI->new(
        driver           => 'File',
        expires_in       => '1 year',
        expires_variance => '0.1',
        root_dir         => "${ mediacloud_data_dir }/cache/solr_import_file_errors/" . Digest::MD5::md5_hex( $abs_file ),
        depth            => 4
    );
}

# get a list of all errors for the file in the form { message => $error_message, pos => $pos }
sub _get_all_file_errors
{
    my ( $file ) = @_;

    my $cache = _get_file_errors_cache( $file );

    my $errors = $cache->dump_as_hash;

    return [ values( %{ $errors } ) ];
}

# add an error for the given file in the form { message => $error_message, pos => $pos }
sub _add_file_error
{
    my ( $file, $error ) = @_;

    my $cache = _get_file_errors_cache( $file );

    $cache->set( $error->{ pos }, $error );
}

# remove an error from the file
sub _remove_file_error
{
    my ( $file, $error ) = @_;

    my $cache = _get_file_errors_cache( $file );

    $cache->remove( $error->{ pos } );
}

# get chunk of $CSV_CHUNK_LINES csv lines from the csv file starting at _get_file_post. use _set_file_pos
# to advance the position pointer tot the next position in the file.  return undef if there is no more data
# to get from the file
sub get_encoded_csv_data_chunk
{
    my ( $file, $single_pos ) = @_;

    my $fh = FileHandle->new;
    $fh->open( $file ) || die( "unable to open file '$file': $!" );

    flock( $fh, 2 ) || die( "Unable to lock file '$file': $!" );

    my $pos = defined( $single_pos ) ? $single_pos : _get_file_pos( $file );

    $fh->seek( $pos, 0 ) || die( "unable to seek to pos '$pos' in file '$file': $!" );

    my $csv_data;
    my $i = 0;

    my ( $first_story_sentences_id, $last_story_sentences_id );
    while ( ( $i < $CSV_CHUNK_LINES ) && ( my $line = <$fh> ) )
    {
        # skip header line
        next if ( !$i && ( $line =~ /^[a-z_,]+$/ ) );

        if ( !defined( $first_story_sentences_id ) )
        {
            $line =~ /^\d+\,\d+\,(\d+)\,/;
            $first_story_sentences_id = $1 || 0;
        }

        $csv_data .= $line;

        $i++;
    }

    # get the final line using the csv parser so that we deal with multi lines correctly.  don't do this for all
    # lines because it is much slower than just copying the text.
    if ( $i == $CSV_CHUNK_LINES )
    {
        my $csv = Text::CSV_XS->new( { binary => 1 } );
        if ( my $row = $csv->getline( $fh ) )
        {
            $csv->combine( @{ $row } );

            $csv_data .= $csv->string . "\n";

            $last_story_sentences_id = $row->[ 2 ];
        }
    }

    # set last_story_sentences_id to an invalid id in case we didn't get a last csv line,
    # which will just cause get_chunk_delta to assume that it cannot be found
    $last_story_sentences_id //= 0;

    if ( !$single_pos )
    {
        _set_file_pos( $file, $fh->tell );

        # this error gets removed once the chunk has been successfully processed so that
        # chunks in progress will get restarted if the process is killed
        _add_file_error( $file, { pos => $pos, message => 'in progress' } );
    }

    $fh->close || die( "Unable to close file '$file': $!" );

    return {
        csv                      => encode( 'utf8', $csv_data ),
        pos                      => $pos,
        first_story_sentences_id => $first_story_sentences_id,
        last_story_sentences_id  => $last_story_sentences_id
    };
}

# get the solr url to which to send csv data
sub _get_import_url
{
    my ( $delta ) = @_;

    my $overwrite = $delta ? 'true' : 'false';

    my $fieldnames = join( ',', @CSV_FIELDS );

    my $url_fields = {
        'commit'                              => 'false',
        'header'                              => 'false',
        'fieldnames'                          => $fieldnames,
        'overwrite'                           => $overwrite,
        'f.media_sets_id.split'               => 'true',
        'f.media_sets_id.separator'           => ';',
        'f.tags_id_media.split'               => 'true',
        'f.tags_id_media.separator'           => ';',
        'f.tags_id_stories.split'             => 'true',
        'f.tags_id_stories.separator'         => ';',
        'f.tags_id_story_sentences.split'     => 'true',
        'f.tags_id_story_sentences.separator' => ';',
        'skip'                                => 'field_type,id,solr_import_date'
    };

    my $url_args_string = join( '&', map { "$_=" . uri_escape( $url_fields->{ $_ } ) } keys( %{ $url_fields } ) );

    return "update/csv?$url_args_string";
}

# print to STDERR a list of remaining errors on the given file
sub _print_file_errors
{
    my ( $file ) = @_;

    my $errors = _get_all_file_errors( $file );

    say STDERR "errors for file '$file':\n" . Dumper( $errors ) if ( @{ $errors } );

}

# find all error chunks saved for this file in the _file_errors_cache, and reprocess every error chunk
sub _reprocess_file_errors
{
    my ( $pm, $file, $staging ) = @_;

    my $import_url = _get_import_url( 1 );

    my $errors = _get_all_file_errors( $file );

    say STDERR "reprocessing all errors for $file ...";

    for my $error ( @{ $errors } )
    {
        my $data = get_encoded_csv_data_chunk( $file, $error->{ pos } );

        _remove_file_error( $file, { pos => $data->{ pos } } );

        next unless ( $data->{ csv } );

        print STDERR "reprocessing $file position $data->{ pos } ...\n";

        $pm->start and next;

        if ( my $error = _solr_request( $import_url, $staging, $data->{ csv } ) )
        {
            _add_file_error( $file, { pos => $data->{ pos }, message => $error } );
        }

        $pm->finish;
    }

    $pm->wait_all_children;
}

# return the delta setting for the given chunk, which if true indicates that we cannot assume that
# all of the story_sentence_ids in the given chunk are not already in solr.
#
# we base this decision on lookups of the first ssid and the last ssid in the chunk:
# * if the last chunk_delta was 0, return 0 (run import with overwrite = false for rest of file)
# * if first ssid is not in solr, delta = 0 (run import with overwrite = false)
# * if the first ssid is in solr but the last is not, delta = 1 (run import with overwrite = true)
# * if the first ssid is in solr and the last ssid is in solr, delta = -1 (do not run import)
sub _get_chunk_delta
{
    my ( $chunk, $last_chunk_delta ) = @_;

    return 0 if ( defined( $last_chunk_delta ) && ( $last_chunk_delta == 0 ) );

    if ( !_sentence_exists_in_solr( $chunk->{ first_story_sentences_id } ) )
    {
        return 0;
    }

    if ( !_sentence_exists_in_solr( $chunk->{ last_story_sentences_id } ) )
    {
        return 1;
    }

    return -1;
}

# import a single csv dump file into solr using blocks
sub _import_csv_single_file
{
    my ( $file, $delta, $staging, $jobs ) = @_;

    my $pm = Parallel::ForkManager->new( $jobs );

    my $file_size = ( stat( $file ) )[ 7 ] || 1;

    my $start_time = time;
    my $start_pos;
    my $last_chunk_delta;

    # commit before we start the loop so that the solr lookups in get_chunk_delta will see previous updates
    _solr_request( "update?commit=true" );

    while ( my $data = get_encoded_csv_data_chunk( $file ) )
    {
        last unless ( $data->{ csv } );

        $start_pos //= $data->{ pos };

        my $progress = int( $data->{ pos } * 100 / $file_size );
        my $partial_progress = ( ( $data->{ pos } + 1 ) - $start_pos ) / ( ( $file_size - $start_pos ) + 1 );

        my $elapsed_time = ( time + 1 ) - $start_time;

        my $remaining_time = int( $elapsed_time * ( 1 / $partial_progress ) ) - $elapsed_time;

        my $chunk_delta = _get_chunk_delta( $data, $last_chunk_delta );
        $last_chunk_delta = $chunk_delta;

        say STDERR
          "importing $file position $data->{ pos } [ delta $chunk_delta, ${progress}%, $remaining_time secs left ] ...";

        if ( $chunk_delta < 0 )
        {
            _remove_file_error( $file, { pos => $data->{ pos } } );
            next;
        }

        $pm->start and next;

        my $import_url = _get_import_url( $chunk_delta );

        my $error = _solr_request( $import_url, $staging, $data->{ csv } );

        _remove_file_error( $file, { pos => $data->{ pos } } );

        _add_file_error( $file, { pos => $data->{ pos }, message => $error } ) if ( $error );

        $pm->finish;
    }

    $pm->wait_all_children;

    _reprocess_file_errors( $pm, $file, $staging );

    _print_file_errors( $file );

    return 1;
}

# import csv dump files into solr.  if there are multiple files,
# import up to 4 at a time.  If $staging is true, import into the
# staging collection.
sub import_csv_files
{
    my ( $files, $delta, $staging, $jobs ) = @_;

    $jobs ||= 1;

    for my $file ( @{ $files } )
    {
        _import_csv_single_file( $file, $delta, $staging, $jobs );
    }

    for my $file ( @{ $files } )
    {
        _print_file_errors( $file );
    }

    return 1;
}

# store in memory the current date according to postgres
sub mark_import_date
{
    my ( $db ) = @_;

    $_import_date = $db->query( "select now()" )->flat;
}

# store the date marked by mark_import_date in solr_imports
sub save_import_date
{
    my ( $db, $delta, $stories_ids ) = @_;

    die( "import date has not been marked" ) unless ( $_import_date );

    my $full_import = $delta ? 'f' : 't';
    $db->query( <<SQL, $_import_date, $full_import, scalar( @{ $stories_ids } ) );
insert into solr_imports( import_date, full_import, num_stories ) values ( ?, ?, ? )
SQL

}

# delete the given stories from solr
sub delete_stories
{
    my ( $stories_ids, $staging ) = @_;

    return 1 unless ( $stories_ids && @{ $stories_ids } );

    print STDERR "deleting " . scalar( @{ $stories_ids } ) . " stories ...\n";

    # send requests in chunks so the requests are not too big
    my $chunk_size = 100;
    for ( my $i = 0 ; $i < @{ $stories_ids } ; $i += $chunk_size )
    {
        my $ceil = List::Util::min( scalar( @{ $stories_ids } ), $i + $chunk_size ) - 1;
        my $chunk_ids = [ ( @{ $stories_ids } )[ $i .. $ceil ] ];

        my $chunk_ids_list = join( ' ', @{ $chunk_ids } );
        my $r =
          _solr_request( "update?stream.body=<delete><query>+stories_id:(${ chunk_ids_list })</query></delete>", $staging );

        if ( $r )
        {
            warn( $r );
            return 0;
        }
    }

    return 1;
}

# delete all stories from solr
sub delete_all_sentences
{
    my ( $staging ) = @_;

    print STDERR "deleting all sentences ...\n";

    my $r = _solr_request( "update?commit=true&stream.body=<delete><query>*:*</query></delete>", $staging );

    if ( $r )
    {
        warn( $r );
        return 0;
    }

    return 1;
}

# get a temp file name to for a delta dump
sub _get_dump_file
{
    my $data_dir = MediaWords::Util::Config::get_config->{ mediawords }->{ data_dir };

    my $dump_dir = "$data_dir/solr_dumps";

    mkdir( $dump_dir ) unless ( -d $dump_dir );

    my ( $fh, $filename ) = File::Temp::tempfile( 'solr-delta.csvXXXX', DIR => $dump_dir );
    close( $fh );

    return $filename;
}

# delete stories that have just been imported from the media import queue
sub delete_stories_from_import_queue
{
    my ( $db, $delta ) = @_;

    if ( $delta )
    {
        $db->query( <<END );
delete from solr_import_stories where stories_id in ( select stories_id from delta_import_stories )
END
    }
    else
    {
        # if we just completed a full import, drop the whole current stories queue
        $db->query( "truncate table solr_import_stories" );
    }
}

sub maybe_production_solr
{
    my ( $db ) = @_;

    my $num_sentences = MediaWords::Solr::get_num_found( $db, { q => '*:*', rows => 0 } );

    die( "Unable to query solr for number of sentences" ) unless ( defined( $num_sentences ) );

    return ( $num_sentences > 100_000_000 );
}

# generate and import dump.  optionally generate delta dump since beginning of last
# full or delta dump.  optionally delete all solr data after generating dump and before
# importing
sub generate_and_import_data
{
    my ( $delta, $delete, $staging, $jobs ) = @_;

    die( "cannot import with delta and delete both true" ) if ( $delta && $delete );

    my $db = MediaWords::DB::connect_to_db;

    die( "refusing to delete maybe production solr" ) if ( $delete && maybe_production_solr( $db ) );

    my $dump_file = _get_dump_file();

    mark_import_date( $db );

    print STDERR "generating dump ...\n";
    my $stories_ids = print_csv_to_file( $db, $dump_file, 1, $delta ) || die( "dump failed." );

    if ( $delta )
    {
        print STDERR "deleting updated stories ...\n";
        delete_stories( $stories_ids, $staging ) || die( "delete stories failed." );
    }
    elsif ( $delete )
    {
        print STDERR "deleting all stories ...\n";
        delete_all_sentences( $staging ) || die( "delete all sentences failed." );
    }

    print STDERR "importing dump ...\n";
    import_csv_files( [ $dump_file ], $delta, $staging, $jobs ) || die( "import failed." );

    save_import_date( $db, $delta, $stories_ids );
    delete_stories_from_import_queue( $db, $delta );

    # if we're doing a full import, do a delta to catchup with the data since the start of the import
    if ( !$delta )
    {
        generate_and_import_data( 1, 0, $staging );
    }

    unlink( $dump_file );
}

1;
