package MediaWords::Solr;

use strict;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

# functions for searching the solr server

use JSON;
use List::Util;

use MediaWords::Languages::Language;
use MediaWords::Util::Web;
use List::MoreUtils qw ( uniq );

# execute a query on the solr server using the given params.
# return the raw encoded json from solr.  return a maximum of
# 1 million sentences.
sub query_encoded_json
{
    my ( $params ) = @_;

    $params->{ wt } = 'json';
    $params->{ rows } //= 1000;
    $params->{ df }   //= 'sentence';

    $params->{ rows } = List::Util::min( $params->{ rows }, 1000000 );

    my $url = MediaWords::Util::Config::get_config->{ mediawords }->{ solr_select_url };

    my $ua = MediaWords::Util::Web::UserAgent;

    $ua->timeout( 300 );
    $ua->max_size( undef );

    # print STDERR "executing solr query ...\n";
    # print STDERR Dumper( $params );
    my $res = $ua->post( $url, $params );

    say STDERR "solr query response received.\n";

    if ( !$res->is_success )
    {
        die( "Error fetching solr response: " . $res->as_string );
    }

    return $res->content;
}

# execute a query on the solr server using the given params.
# return a hash generated from the json results
sub query
{
    my ( $params ) = @_;

    my $json = query_encoded_json( $params );

    my $data;
    eval { $data = decode_json( $json ) };
    if ( $@ )
    {
        die( "Error parsing solr json: $@\n$json" );
    }

    if ( $data->{ error } )
    {
        die( "Error received from solr: '$json'" );
    }

    return $data;
}

# return all of the story ids that match the solr query
sub search_for_stories_ids
{
    my ( $params ) = @_;

    # say STDERR "MediaWords::Solr::search_for_stories_ids";

    $params = { %{ $params } };

    $params->{ fl } = 'stories_id';

    # say STDERR Dumper( $params );

    my $response = query( $params );

    # say STDERR Dumper( $response );

    my $uniq_stories_ids = [ uniq( map { $_->{ stories_id } } @{ $response->{ response }->{ docs } } ) ];

    return $uniq_stories_ids;
}

sub number_of_matching_documents
{
    my ( $params ) = @_;

    $params = { %{ $params } };

    undef $params->{ sort };

    $params->{ rows } = 0;

    my $response = query( $params )->{ response };

    #say STDERR Dumper( $response );

    #say STDERR $response->{ numFound };

    return $response->{ numFound };
}

sub max_processed_stories_id
{
    my ( $self, $c ) = @_;

    my $params = {};

    $params->{ q } = '*:*';

    $params->{ sort } = "processed_stories_id desc";

    $params->{ rows } = 1;

    my $response = query( $params );

    my $max_processed_stories_id = $response->{ response }->{ docs }->[ 0 ]->{ processed_stories_id };

    return $max_processed_stories_id;
}

# return all of the story ids that match the solr query
sub search_for_processed_stories_ids
{
    my ( $params ) = @_;

    # say STDERR "MediaWords::Solr::search_for_stories_ids";

    $params = { %{ $params } };

    $params->{ fl } = 'processed_stories_id';

    # say STDERR Dumper( $params );

    my $response = query( $params );

    # say STDERR Dumper( $response );

    my $uniq_ids = [ uniq( map { $_->{ processed_stories_id } } @{ $response->{ response }->{ docs } } ) ];

    return $uniq_ids;
}

# given a list of hashes, each with a stories_id field, query postgres to attach
# the rest of the story metadata to each hash. assumes that each stories_id appears
# only once in the stories list.  Fails if given more than 500 stories
sub _attach_story_data_to_stories_ids_chunk
{
    my ( $db, $stories ) = @_;

    die( "stories list has more than 500 members" ) unless ( @{ $stories } <= 500 );

    my $stories_id_list = join( ',', map { $_->{ stories_id } } @{ $stories } );

    my $story_data = $db->query( <<END )->hashes;
select s.stories_id, s.title, s.publish_date, s.url, s.guid, s.media_id, s.language, m.name media_name
    from stories s join media m on ( s.media_id = m.media_id )
    where s.stories_id in ( $stories_id_list )
END

    my $story_data_lookup = {};
    map { $story_data_lookup->{ $_->{ stories_id } } = $_ } @{ $story_data };

    for my $story ( @{ $stories } )
    {
        if ( $story_data = $story_data_lookup->{ $story->{ stories_id } } )
        {
            map { $story->{ $_ } = $story_data->{ $_ } } keys( %{ $story_data } );
        }
    }
}

# given a list of hashes, each with a stories_id field, query postgres to attach
# the following story data to each hash:
# title, publish_date, url, guid, media_name, media_id, language
# assumes that each stories_id appears only once in the stories list.
sub _attach_story_data_to_stories_ids
{
    my ( $db, $stories ) = @_;

    # first sort so that each chunk query includes maxmimally adjacent stories_ids
    my $sorted_stories = [ sort { $a->{ stories_id } <=> $b->{ stories_id } } @{ $stories } ];

    # break up into chunks of 500 to avoid overly large postgres queries (max 8192 characters)
    my $chunk_size = 500;
    for ( my $i = 0 ; $i < @{ $sorted_stories } ; $i += $chunk_size )
    {
        my $chunk_end = List::Util::min( $#{ $stories }, $i + $chunk_size - 1 );
        my $stories_chunk = [ @{ $stories }[ $i .. $chunk_end ] ];
        _attach_story_data_to_stories_ids_chunk( $db, $stories_chunk );
    }
}

# return all of the story ids that match the solr query
sub search_for_processed_stories_ids_with_groups
{
    my ( $params ) = @_;

    # say STDERR "MediaWords::Solr::search_for_stories_ids";

    $params = { %{ $params } };

    $params->{ fl } = 'processed_stories_id';

    $params->{ 'group' } = 'true';

    $params->{ 'group.limit' } = 0;
    $params->{ 'group.field' } = 'processed_stories_id';

    say STDERR Dumper( $params );

    my $response = query( $params );

    say STDERR "Solr_response\n" . Dumper( $response );

    my $groups = $response->{ grouped }->{ processed_stories_id }->{ groups };

    say STDERR Dumper( $groups );

    say STDERR Dumper( map { $_->{ groupValue } } @{ $groups } );

    my $uniq_ids = [ uniq( map { $_->{ processed_stories_id } } @{ $response->{ response }->{ docs } } ) ];

    return $uniq_ids;
}

# return all of the stories that match the solr query.  attach a list of matching sentences in story order
# to each story as well as the stories.* fields from postgres.

# limit to first $num_sampled stories $num_sampled is specified.  return first rows returned by solr
# if $random is not true (and only an estimate of the total number of matching stories ).  fetch all results
# from solr and return a random sample of those rows if $random is true (and an exact count of the number of
# matching stories
#
# returns the (optionally sampled) stories and the total number of matching stories.
sub search_for_stories_with_sentences
{
    my ( $db, $params, $num_sampled, $random ) = @_;

    $params = { %{ $params } };

    $params->{ fl } = 'stories_id,sentence,story_sentences_id';

    $params->{ rows } = ( $num_sampled ) ? ( $num_sampled * 2 ) : 1000000;

    $params->{ sort } = 'random_1 asc' if ( $random );

    my $response = query( $params );

    my $stories_lookup = {};
    for my $doc ( @{ $response->{ response }->{ docs } } )
    {
        $stories_lookup->{ $doc->{ stories_id } } ||= [];
        push( @{ $stories_lookup->{ $doc->{ stories_id } } }, $doc );
    }

    my $stories = [];
    while ( my ( $stories_id, $sentences ) = each( %{ $stories_lookup } ) )
    {
        my $ordered_sentences = [ sort { $a->{ story_sentences_id } <=> $b->{ story_sentences_id } } @{ $sentences } ];
        push( @{ $stories }, { stories_id => $stories_id, sentences => $ordered_sentences } );
    }

    my $num_stories = @{ $stories };
    if ( $num_sampled && ( $num_stories > $num_sampled ) )
    {
        map { $_->{ _s } = Digest::MD5::md5_hex( $_->{ stories_id } ) } @{ $stories };
        $stories = [ ( sort { $a->{ _s } cmp $b->{ _s } } @{ $stories } )[ 0 .. ( $num_sampled - 1 ) ] ];
        $num_stories = int( $response->{ response }->{ numFound } / 2 );
    }

    _attach_story_data_to_stories_ids( $db, $stories );

    return ( $stories, $num_stories );
}

# execute the query and return only the number of documents found
sub get_num_found
{
    my ( $params ) = @_;

    $params = { %{ $params } };
    $params->{ rows } = 0;

    my $res = query( $params );

    return $res->{ response }->{ numFound };
}

# get sorted list of most common words in sentences matching a solr query.  exclude stop words from the
# long_stop_word list.  assumes english stemming and stopwording for now.
sub count_words
{
    my ( $params ) = @_;

    my $ua = MediaWords::Util::Web::UserAgent();

    $ua->timeout( 300 );
    $ua->max_size( undef );

    my $url = MediaWords::Util::Config::get_config->{ mediawords }->{ solr_wc_url };

    my $res = $ua->post( $url, $params );

    die( "error retrieving words from solr: " . $res->as_string ) unless ( $res->is_success );

    my $words = from_json( $res->content, { utf8 => 1 } );

    die( "Unable to parse json" ) unless ( ( ref( $words ) eq 'HASH' ) && ( $words->{ words } ) );

    $words = $words->{ words };

    # only support english for now
    my $language  = MediaWords::Languages::Language::language_for_code( 'en' );
    my $stopstems = $language->get_long_stop_word_stems();

    my $stopworded_words = [];
    for my $word ( @{ $words } )
    {
        next if ( length( $word->{ stem } ) < 3 );

        # we have restem the word because solr uses a different stemming implementation
        my $stem = $language->stem( $word->{ term } )->[ 0 ];

        push( @{ $stopworded_words }, $word ) unless ( $stopstems->{ $stem } );
    }

    return $stopworded_words;
}

1;
