package MediaWords::DBI::Stories;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

=head1 NAME

Mediawords::DBI::Stories - various helper functions for stories

=head1 SYNOPSIS


=head1 DESCRIPTION

This module includes various helper function for dealing with stories.

=cut

use strict;
use warnings;

use Carp;
use Encode;
use File::Temp;
use FileHandle;
use HTML::Entities;
use List::Compare;

use MediaWords::DBI::Downloads;
use MediaWords::DBI::Stories::ExtractorVersion;
use MediaWords::Languages::Language;
use MediaWords::Solr::WordCounts;
use MediaWords::StoryVectors;
use MediaWords::Util::Bitly::Schedule;
use MediaWords::Util::Config;
use MediaWords::Util::HTML;
use MediaWords::Util::Tags;
use MediaWords::Util::URL;
use MediaWords::Util::Web;

=head1 FUNCTIONS

=cut

sub _get_full_text_from_rss
{
    my ( $db, $story ) = @_;

    my $ret = html_strip( $story->{ title } || '' ) . "\n" . html_strip( $story->{ description } || '' );

    return $ret;
}

=head2 combine_story_title_description_text( $story_title, $story_description, $download_texts )

Get the combined story title, story description, and download text of the story in a consistent way.

=cut

sub combine_story_title_description_text($$$)
{
    my ( $story_title, $story_description, $download_texts ) = @_;

    return join(
        "\n***\n\n",
        html_strip( $story_title       || '' ),    #
        html_strip( $story_description || '' ),    #
        @{ $download_texts }                       #
    );
}

=head2 get_text

Get the concatenation of the story title and description and all of the download_texts associated with the story
in a consistent way.

If full_text_rss is true for the medium, just return the concatenation of the story title and description.

=cut

sub get_text
{
    my ( $db, $story ) = @_;

    if ( $story->{ full_text_rss } )
    {
        return _get_full_text_from_rss( $db, $story );
    }

    my $download_texts = $db->query(
        <<"EOF",
        SELECT download_text
        FROM download_texts AS dt,
             downloads AS d
        WHERE d.downloads_id = dt.downloads_id
              AND d.stories_id = ?
        ORDER BY d.downloads_id ASC
EOF
        $story->{ stories_id }
    )->flat;

    my $pending_download = $db->query(
        <<"EOF",
        SELECT downloads_id
        FROM downloads
        WHERE extracted = 'f'
              AND stories_id = ?
              AND type = 'content'
EOF
        $story->{ stories_id }
    )->hash;

    if ( $pending_download )
    {
        push( @{ $download_texts }, "(downloads pending extraction)" );
    }

    return combine_story_title_description_text( $story->{ title }, $story->{ description }, $download_texts );
}

=head2 get_text_for_word_counts( $db, $story )

Like get_text but it doesn't include both title + description and the extracted text.  This is what is used to fetch
text to generate story_sentences, which eventually get imported into solr.

If the text of the story ends up being shorter than the description, return the title + description instead of the
story text (some times the extractor falls down and we end up with better data just using the title + description .

=cut

sub get_text_for_word_counts
{
    my ( $db, $story ) = @_;

    my $story_text = $story->{ full_text_rss } ? _get_full_text_from_rss( $db, $story ) : get_extracted_text( $db, $story );

    my $story_description = $story->{ description } || '';

    if ( ( length( $story_text ) == 0 ) || ( length( $story_text ) < length( $story_description ) ) )
    {
        $story_text = html_strip( $story->{ title } );
        if ( $story->{ description } )
        {
            $story_text .= '.' unless ( $story_text =~ /\.\s*$/ );
            $story_text .= html_strip( $story->{ description } );
        }
    }

    return $story_text;
}

=head2 get_first_download( $db, $download )

Get the first download linking to this story.

=cut

sub get_first_download
{
    my ( $db, $story ) = @_;

    return $db->query( <<SQL, $story->{ stories_id } )->hash;
SELECT * FROM downloads WHERE stories_id = ? ORDER BY sequence ASC LIMIT 1
SQL
}

=head2 is_fully_extracted( $db, $story )

Return true if all downloads linking to this story have been extracted.

=cut

sub is_fully_extracted
{
    my ( $db, $story ) = @_;

    my ( $bool ) = $db->query(
        <<"EOF",
        SELECT BOOL_AND(extracted)
        FROM downloads
        WHERE stories_id = ?
EOF
        $story->{ stories_id }
    )->flat();

    return ( defined( $bool ) && $bool ) ? 1 : 0;
}

=head2 get_content_for_first_download( $db, $story )

Call fetch_content on the result of get_first_download().  Return undef if the download's state is not null.

=cut

sub get_content_for_first_download($$)
{
    my ( $db, $story ) = @_;

    my $first_download = get_first_download( $db, $story );

    if ( $first_download->{ state } ne 'success' )
    {
        DEBUG( sub { "First download's state is not 'success' for story " . $story->{ stories_id } } );
        return;
    }

    my $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $first_download );

    return $content_ref;
}

=head2 get_existing_tags( $db, $story, $tag_set_name )

Get tags belonging to the tag set with the given name and associated with this story.

=cut

sub get_existing_tags
{
    my ( $db, $story, $tag_set_name ) = @_;

    my $tag_set = $db->find_or_create( 'tag_sets', { name => $tag_set_name } );

    my $ret = $db->query(
        <<"EOF",
        SELECT stm.tags_id
        FROM stories_tags_map AS stm,
             tags
        WHERE stories_id = ?
              AND stm.tags_id = tags.tags_id
              AND tags.tag_sets_id = ?
EOF
        $story->{ stories_id },
        $tag_set->{ tag_sets_id }
    )->flat;

    return $ret;
}

=head2 get_existing_tags_as_string( $db, $stories_id )

Get list of tags associated with the story in 'tag_set_name:tag' format.

=cut

sub get_existing_tags_as_string
{
    my ( $db, $stories_id ) = @_;

    # Take note of the old tags
    my $tags = $db->query(
        <<"EOF",
            SELECT stm.stories_id,
                   CAST(ARRAY_AGG(ts.name || ':' || t.tag) AS TEXT) AS tags
            FROM tags t,
                 stories_tags_map stm,
                 tag_sets ts
            WHERE t.tags_id = stm.tags_id
                  AND stm.stories_id = ?
                  AND t.tag_sets_id = ts.tag_sets_id
            GROUP BY stm.stories_id,
                     t.tag_sets_id
            ORDER BY tags
            LIMIT 1
EOF
        $stories_id
    )->hash;

    if ( ref( $tags ) eq 'HASH' and $tags->{ stories_id } )
    {
        $tags = $tags->{ tags };
    }
    else
    {
        $tags = '';
    }

    return $tags;
}

=head2 update_rss_full_text_field( $db, $story )

Set stories.full_text_rss to the value of the medium's full_text_rss field.  If the new value is different than
$story->{ full_text_rss }, update the value in the db.

=cut

sub update_rss_full_text_field
{
    my ( $db, $story ) = @_;

    my $medium = $db->query( "select * from media where media_id = ?", $story->{ media_id } )->hash;

    my $full_text_in_rss = ( $medium->{ full_text_rss } ) ? 1 : 0;

    #This is a temporary hack to work around a bug in XML::FeedPP
    $full_text_in_rss = 0 if ( defined( $story->{ description } ) && ( length( $story->{ description } ) == 0 ) );

    if ( defined( $story->{ full_text_rss } ) && ( $story->{ full_text_rss } != $full_text_in_rss ) )
    {
        $story->{ full_text_rss } = $full_text_in_rss;
        $db->query(
            <<"EOF",
            UPDATE stories
            SET full_text_rss = ?
            WHERE stories_id = ?
EOF
            $full_text_in_rss, $story->{ stories_id }
        );
    }

    return $story;
}

=head2 fetch_content( $db, $story )

Fetch the content of the first download of the story.

=cut

sub fetch_content($$)
{
    my ( $db, $story ) = @_;

    my $download = $db->query(
        <<"EOF",
        SELECT *
        FROM downloads
        WHERE stories_id = ?
        order by downloads_id
EOF
        $story->{ stories_id }
    )->hash;

    return $download ? MediaWords::DBI::Downloads::fetch_content( $db, $download ) : \'';
}

=head2 get_db_module_tags( $db, $story, $module )

Get the tags for the given module associated with the given story from the db

=cut

sub get_db_module_tags
{
    my ( $db, $story, $module ) = @_;

    my $tag_set = $db->find_or_create( 'tag_sets', { name => $module } );

    return $db->query(
        <<"EOF",
        SELECT t.tags_id AS tags_id,
               t.tag_sets_id AS tag_sets_id,
               t.tag AS tag
        FROM stories_tags_map AS stm,
             tags AS t,
             tag_sets AS ts
        WHERE stm.stories_id = ?
              AND stm.tags_id = t.tags_id
              AND t.tag_sets_id = ts.tag_sets_id
              AND ts.name = ?
EOF
        $story->{ stories_id },
        $module
    )->hashes;
}

=head2 get_extracted_text( $db, $story )

Return the concatenated download_texts associated with the story.

=cut

sub get_extracted_text
{
    my ( $db, $story ) = @_;

    my $download_texts = $db->query(
        <<"EOF",
        SELECT dt.download_text
        FROM downloads AS d,
             download_texts AS dt
        WHERE dt.downloads_id = d.downloads_id
              AND d.stories_id = ?
        ORDER BY d.downloads_id
EOF
        $story->{ stories_id }
    )->hashes;

    return join( ".\n\n", map { $_->{ download_text } } @{ $download_texts } );
}

=head2 get_extracted_html_from_db( $db, $story )

Get extracted html for the story by using existing text extraction results.

=cut

sub get_extracted_html_from_db
{
    my ( $db, $story ) = @_;

    my $download_texts = $db->query( <<END, $story->{ stories_id } )->hashes;
select dt.downloads_id, dt.download_texts_id
	from downloads d, download_texts dt
	where dt.downloads_id = d.downloads_id and d.stories_id = ? order by d.downloads_id
END

    return join( "\n", map { MediaWords::DBI::DownloadTexts::get_extracted_html_from_db( $db, $_ ) } @{ $download_texts } );
}

=head2 is_new( $db, $story )

Return true if this story should be considered new for the given media source.  This is used by FeedHandler to determine
whether to add a new story for a feed item url.

A story is new if no story with the same url or guid exists in the same media source and if no story exists with the
same title in the same media source in the same calendar day.

=cut

sub is_new
{
    my ( $dbs, $story ) = @_;

    my $db_story = $dbs->query( <<"END", $story->{ guid }, $story->{ media_id } )->hash;
SELECT * FROM stories WHERE guid = ? AND media_id = ?
END

    return 0 if ( $db_story || ( $story->{ title } eq '(no title)' ) );

    # unicode hack to deal with unicode brokenness in XML::Feed
    my $title = Encode::is_utf8( $story->{ title } ) ? $story->{ title } : decode( 'utf-8', $story->{ title } );

    # we do the goofy " + interval '1 second'" to force postgres to use the stories_title_hash index
    $db_story = $dbs->query( <<END, $title, $story->{ media_id }, $story->{ publish_date } )->hash;
SELECT 1
    FROM stories
    WHERE
        md5( title ) = md5( ? ) AND
        media_id = ? AND
        date_trunc( 'day', publish_date )  + interval '1 second' =
            date_trunc( 'day', ?::date ) + interval '1 second'
    FOR UPDATE
END

    return 0 if ( $db_story );

    return 1;
}

# re-extract the story for the given download
sub _reextract_download
{
    my ( $db, $download ) = @_;

    if ( $download->{ url } =~ /jpg|pdf|doc|mp3|mp4$/i )
    {
        warn "Won't reextract download " .
          $download->{ downloads_id } . " because the URL doesn't look like it could contain text.";
        return;
    }

    eval { MediaWords::DBI::Downloads::process_download_for_extractor( $db, $download, "restore", 1, 1 ); };
    if ( $@ )
    {
        warn "extract error processing download $download->{ downloads_id }: $@";
    }
}

=head2 extract_and_process_story( $story, $db, $process_num )

Extract all of the downloads for the given story and then call process_extracted_story();

=cut

sub extract_and_process_story
{
    my ( $story, $db, $process_num ) = @_;

    my $downloads = $db->query( <<SQL, $story->{ stories_id } )->hashes;
SELECT * FROM downloads WHERE stories_id = ? AND type = 'content' ORDER BY downloads_id ASC
SQL

    foreach my $download ( @{ $downloads } )
    {
        MediaWords::DBI::Downloads::extract_and_create_download_text( $db, $download );
    }

    process_extracted_story( $story, $db, 0, 0 );

    $db->commit;
}

# update disable_triggers for given story if needed
sub _update_story_disable_triggers
{
    my ( $db, $story ) = @_;

    my $config_disable_triggers = MediaWords::DB::story_triggers_disabled() ? 1 : 0;
    my $story_disable_triggers = $story->{ disable_triggers } ? 1 : 0;

    if ( $config_disable_triggers != $story_disable_triggers )
    {
        $db->query(
            "UPDATE stories SET disable_triggers  = ? WHERE stories_id = ?",
            MediaWords::DB::story_triggers_disabled(),
            $story->{ stories_id }
        );
    }
}

=head2 process_extracted_story( $story, $db, $no_dedup_sentences, $no_vector )

Do post extraction story processing work: call MediaWords::StoryVectors::update_story_sentences_and_language() and queue
corenlp annotation and bitly fetching tasks.

=cut

sub process_extracted_story
{
    my ( $story, $db, $no_dedup_sentences, $no_vector ) = @_;

    unless ( $no_vector )
    {
        MediaWords::StoryVectors::update_story_sentences_and_language( $db, $story, 0, $no_dedup_sentences );
    }

    _update_story_disable_triggers( $db, $story );

    MediaWords::DBI::Stories::ExtractorVersion::update_extractor_version_tag( $db, $story );

    my $stories_id = $story->{ stories_id };

    if (    MediaWords::Util::CoreNLP::annotator_is_enabled()
        and MediaWords::Util::CoreNLP::story_is_annotatable( $db, $stories_id ) )
    {
        # Story is annotatable with CoreNLP; enqueue for CoreNLP annotation
        # (which will run mark_as_processed() on its own)
        MediaWords::Job::AnnotateWithCoreNLP->add_to_queue( { stories_id => $stories_id } );

    }
    else
    {
        # Story is not annotatable with CoreNLP; add to "processed_stories" right away
        unless ( MediaWords::DBI::Stories::mark_as_processed( $db, $stories_id ) )
        {
            die "Unable to mark story ID $stories_id as processed";
        }
    }

    # Add to Bit.ly queue
    if ( MediaWords::Util::Bitly::Schedule::story_processing_is_enabled() )
    {
        MediaWords::Util::Bitly::Schedule::add_to_processing_schedule( $db, $stories_id );
    }
}

=head2 restore_download_content( $db, $download, $story_content )

Replace the the download with the given content and reextract the download.

=cut

sub restore_download_content
{
    my ( $db, $download, $story_content ) = @_;

    MediaWords::DBI::Downloads::store_content( $db, $download, \$story_content );
    _reextract_download( $db, $download );
}

=head2 download_is_broken( $db, $download )

Check to see whether the given download is broken

=cut

sub download_is_broken($$)
{
    my ( $db, $download ) = @_;

    my $content_ref;
    eval { $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $download ); };

    return 0 if ( $content_ref && ( length( $$content_ref ) > 32 ) );

    return 1;
}

=head2 get_broken_download_content

For each download, refetch the content and add a { content } field with the fetched content.

=cut

sub get_broken_download_content
{
    my ( $db, $downloads ) = @_;

    my $urls = [ map { URI->new( $_->{ url } )->as_string } @{ $downloads } ];

    my $responses = MediaWords::Util::Web::ParallelGet( $urls );

    my $download_lookup = {};
    map { $download_lookup->{ URI->new( $_->{ url } )->as_string } = $_ } @{ $downloads };

    for my $response ( @{ $responses } )
    {
        my $original_url = MediaWords::Util::Web->get_original_request( $response )->uri->as_string;

        $download_lookup->{ $original_url }->{ content } = $response->decoded_content;
    }
}

=head2 fix_story_downloads_if_needed( $db, $story )

If this story is one of the ones for which we lost the download content, refetch, restore, and reextract
the content.

=cut

sub fix_story_downloads_if_needed
{
    my ( $db, $story ) = @_;

    if ( $story->{ url } =~ /livejournal.com/ )
    {

        # hack to fix livejournal extra pages, which are misparsing errors from Pager.pm
        $db->query( <<END, $story->{ stories_id } );
delete from downloads where stories_id = ? and sequence > 1
END
    }

    my $downloads = $db->query( <<END, $story->{ stories_id } )->hashes;
select * from downloads where stories_id = ? order by downloads_id
END

    my $broken_downloads = [ grep { download_is_broken( $db, $_ ) } @{ $downloads } ];

    my $fetch_downloads = [];
    for my $download ( @{ $broken_downloads } )
    {
        if ( my $cached_download = $story->{ cached_downloads }->{ $download->{ downloads_id } } )
        {
            $download->{ content } = MediaWords::Util::Web::get_cached_link_download( $cached_download );
        }
        else
        {
            push( @{ $fetch_downloads }, $download );
        }
    }

    get_broken_download_content( $db, $fetch_downloads );

    for my $download ( @{ $broken_downloads } )
    {
        restore_download_content( $db, $download, $download->{ content } );
    }
}

=head2 add_missing_story_sentences( $db, $story )

If no story_sentences exist for the story, add them.

=cut

sub add_missing_story_sentences
{
    my ( $db, $story ) = @_;

    my $ss = $db->query( "select 1 from story_sentences ss where stories_id = ?", $story->{ stories_id } )->hash;

    return if ( $ss );

    INFO( sub { "ADD SENTENCES [$story->{ stories_id }]" } );

    MediaWords::StoryVectors::update_story_sentences_and_language( $db, $story, 0, 0, 1 );
}

=head2 get_all_sentences( $db, $story )

Parse sentences in story from the extracted text.  return in the form:

    { sentence => $sentence, ss => $matching_story_sentence, stories_id => $stories_id }

The list of returned sentences includes sentences that are deduped before storing story_sentences for each story. This
function is useful for comparing against the stored story_sentences.

=cut

sub get_all_sentences
{
    my ( $db, $story ) = @_;

    # Tokenize into sentences
    my $lang = MediaWords::Languages::Language::language_for_code( $story->{ language } )
      || MediaWords::Languages::Language::default_language();

    my $text = get_text( $db, $story );
    unless ( defined $text )
    {
        warn "Text for story " . $story->{ stories_id } . " is undefined.";
        return;
    }
    unless ( length( $text ) )
    {
        warn "Story " . $story->{ stories_id } . " text is an empty string.";
        return;
    }

    my $raw_sentences = $lang->get_sentences( $text );
    unless ( defined $raw_sentences )
    {
        die "Sentences for story " . $story->{ stories_id } . " are undefined.";
    }
    unless ( scalar @{ $raw_sentences } )
    {
        warn "Story " . $story->{ stories_id } . " doesn't have any sentences.";
        return;
    }

    my $all_sentences = [];
    for my $sentence ( @{ $raw_sentences } )
    {
        my $ss = $db->query( <<END, $sentence, $story->{ stories_id } )->hash;
select * from story_sentences where sentence = \$1 and stories_id = \$2
END

        push( @{ $all_sentences }, { sentence => $sentence, ss => $ss, stories_id => $story->{ stories_id } } );
    }

    return $all_sentences;
}

=head2 mark_as_processed( $db, $stories_id )

Mark the story as processed by inserting an entry into 'processed_stories'.  Return true on success, false on failure.

=cut

sub mark_as_processed($$)
{
    my ( $db, $stories_id ) = @_;

    eval {
        $db->insert( 'processed_stories',
            { stories_id => $stories_id, disable_triggers => MediaWords::DB::story_triggers_disabled() } );
    };
    if ( $@ )
    {
        warn "Unable to insert story ID $stories_id into 'processed_stories': $@";
        return 0;
    }
    else
    {
        return 1;
    }
}

=head2 attach_story_data_to_stories( $stories, $story_data, $list_field )

Given two lists of hashes, $stories and $story_data, each with
a stories_id field in each row, assign each key:value pair in
story_data to the corresponding row in $stories.  If $list_field
is specified, push each the value associate with key in each matching
stories_id row in story_data field into a list with the name $list_field
in stories.

=cut

sub attach_story_data_to_stories
{
    my ( $stories, $story_data, $list_field ) = @_;

    map { $_->{ $list_field } = [] } @{ $stories } if ( $list_field );

    unless ( scalar @{ $story_data } )
    {
        return;
    }

    my $story_data_lookup = {};
    for my $sd ( @{ $story_data } )
    {
        if ( $list_field )
        {
            $story_data_lookup->{ $sd->{ stories_id } } //= { $list_field => [] };
            push( @{ $story_data_lookup->{ $sd->{ stories_id } }->{ $list_field } }, $sd );
        }
        else
        {
            $story_data_lookup->{ $sd->{ stories_id } } = $sd;
        }
    }

    for my $story ( @{ $stories } )
    {
        if ( my $sd = $story_data_lookup->{ $story->{ stories_id } } )
        {
            map { $story->{ $_ } = $sd->{ $_ } } keys( %{ $sd } );
        }
    }
}

=head2 attach_story_meta_data_to_stories( $db, $stories )

Call attach_story_data_to_stories_ids with a basic query that includes the fields:
stories_id, title, publish_date, url, guid, media_id, language, media_name.

=cut

sub attach_story_meta_data_to_stories
{
    my ( $db, $stories ) = @_;

    $db->begin;

    my $ids_table = $db->get_temporary_ids_table( [ map { $_->{ stories_id } } @{ $stories } ] );

    my $story_data = $db->query( <<END )->hashes;
select s.stories_id, s.title, s.publish_date, s.url, s.guid, s.media_id, s.language, m.name media_name
    from stories s join media m on ( s.media_id = m.media_id )
    where s.stories_id in ( select id from $ids_table )
END

    attach_story_data_to_stories( $stories, $story_data );

    $db->commit;

    return $stories;
}

# break a story down into parts separated by [-:|]
sub _get_title_parts
{
    my ( $title ) = @_;

    $title = decode_entities( $title );

    $title = lc( $title );
    $title =~ s/\s+/ /g;
    $title =~ s/^\s+//;
    $title =~ s/\s+$//;

    $title = html_strip( $title ) if ( $title =~ /\</ );
    $title = decode_entities( $title );

    my $title_parts;
    if ( $title =~ m~http://[^ ]*^~ )
    {
        $title_parts = [ $title ];
    }
    else
    {
        $title_parts = [ split( /\s*[-:|]+\s*/, $title ) ];
    }

    map { s/^\s+//; s/\s+$//; s/[[:punct:]]//g; } @{ $title_parts };

    if ( @{ $title_parts } > 1 )
    {
        unshift( @{ $title_parts }, $title );
    }

    return $title_parts;
}

=head2 get_medium_dup_stories_by_title( $db, $stories, $assume_no_home_pages )

Get duplicate stories within the set of stories by breaking the title of each story into parts by [-:|] and looking for
any such part that is the sole title part for any story and is at least 4 words long and is not the title of a story
with a path-less url.  Any story that includes that title part becames a duplicate.  return a list of duplciate story
lists. Do not return any list of duplicates with greater than 25 duplicates for fear that the title deduping is
interacting with some title form in a goofy way.

By default, assume that any solr title part that is less than 5 words long or that is associated with a story whose
url has no path is a home page and therefore should not be considered as a possible duplicate title part.  If
$assume_no_home_pages is true, treat every solr url part greater than two words as a potential duplicate title part.

Don't recognize twitter stories as dups, because the tweet title is the tweet text, and we want to capture retweets.


=cut

sub get_medium_dup_stories_by_title
{
    my ( $db, $stories, $assume_no_home_pages ) = @_;

    my $title_part_counts = {};
    for my $story ( @{ $stories } )
    {
        next if ( $_->{ url } && ( $_->{ url } =~ /https?:\/\/(twitter\.com|t\.co)/i ) );

        my $title_parts = _get_title_parts( $story->{ title } );

        for ( my $i = 0 ; $i < @{ $title_parts } ; $i++ )
        {
            my $title_part = $title_parts->[ $i ];

            if ( $i == 0 )
            {
                my $num_words = scalar( split( / /, $title_part ) );
                my $uri_path = MediaWords::Util::URL::get_url_path_fast( $story->{ url } );

                # solo title parts that are only a few words might just be the media source name
                next if ( ( $num_words < 5 ) && !$assume_no_home_pages );

                # likewise, a solo title of a story with a url with no path is probably the media source name
                next if ( ( $uri_path =~ /^\/?$/ ) && !$assume_no_home_pages );

                $title_part_counts->{ $title_parts->[ 0 ] }->{ solo } = 1;
            }

            # this function needs to work whether or not the story has already been inserted into the db
            my $id = $story->{ stories_id } || $story->{ guid };

            $title_part_counts->{ $title_part }->{ count }++;
            $title_part_counts->{ $title_part }->{ stories }->{ $id } = $story;
        }
    }

    my $duplicate_stories = [];
    for my $t ( grep { $_->{ solo } } values( %{ $title_part_counts } ) )
    {
        my $num_stories = scalar( keys( %{ $t->{ stories } } ) );
        if ( $num_stories > 1 )
        {
            if ( $num_stories < 26 )
            {
                push( @{ $duplicate_stories }, [ values( %{ $t->{ stories } } ) ] );
            }
            else
            {
                my $dup_title = ( values( %{ $t->{ stories } } ) )[ 0 ]->{ title };

                # warn( "cowardly refusing to mark $num_stories stories as dups [$dup_title]" );
            }
        }
    }

    return $duplicate_stories;
}

=head2 get_medium_dup_stories_by_url( $db, $stories )

Get duplicate stories within the given set that are duplicates because the normalized url for two given stories is the
same.  Return a list of story duplicate lists.  Do not return any list of duplicates with greater than 5 duplicates for
fear that the url normalization is interacting with some url form in a goofy way

=cut

sub get_medium_dup_stories_by_url
{
    my ( $db, $stories ) = @_;

    my $url_lookup = {};
    for my $story ( @{ $stories } )
    {
        if ( !$story->{ url } )
        {
            warn( "no url in story: " . Dumper( $story ) );
            next;
        }

        my $nu = MediaWords::Util::URL::normalize_url_lossy( $story->{ url } );
        $story->{ normalized_url } = $nu;
        push( @{ $url_lookup->{ $nu } }, $story );
    }

    return [ grep { ( @{ $_ } > 1 ) && ( @{ $_ } < 6 ) } values( %{ $url_lookup } ) ];
}

=head2 get_medium_dup_stories_by_guid( $db, $stories )

Get duplicate stories within the given set that have duplicate guids

=cut

sub get_medium_dup_stories_by_guid
{
    my ( $db, $stories ) = @_;

    my $guid_lookup = {};
    for my $story ( @{ $stories } )
    {
        die( "no guid in story: " . Dumper( $story ) ) unless ( $story->{ guid } );
        push( @{ $guid_lookup->{ $story->{ guid } } }, $story );
    }

    return [ grep { @{ $_ } > 1 } values( %{ $guid_lookup } ) ];
}

# get a postgres cursor that will return the concatenated story_sentences for each of the given stories_ids.  use
# $sentence_separator to join the sentences for each story.
sub _get_story_word_matrix_cursor($$$)
{
    my ( $db, $stories_ids, $sentence_separator ) = @_;

    my $cursor = 'story_text';

    my $ids_table = $db->get_temporary_ids_table( $stories_ids );
    $db->query( <<SQL, $sentence_separator );
declare story_text cursor for
    select stories_id, language, string_agg( sentence, \$1 ) $cursor
        from story_sentences
        where stories_id in ( select id from $ids_table )
        group by stories_id, language
SQL

    return $cursor;
}

# give a file in the form returned by get_story_word_matrix_file() but missing trailing 0s in some lines, pad all lines
# that have fewer than the size of $word_list with enough additional 0's to make all lines have $num_items items.
sub _pad_story_word_matrix_file($$)
{
    my ( $unpadded_file, $word_list ) = @_;

    my $num_items = @{ $word_list } + 1;

    my $unpadded_fh = FileHandle->new( $unpadded_file ) || die( "Unable to open file '$unpadded_file': $!" );

    my ( $padded_fh, $padded_file ) = File::Temp::tempfile;

    while ( my $line = <$unpadded_fh> )
    {
        chomp( $line );
        my $items = [ split( ',', $line ) ];

        if ( scalar( @{ $items } ) < $num_items )
        {
            $line .= ",0" x ( $num_items - scalar( @{ $items } ) );
        }

        $padded_fh->print( "$line\n" );
    }

    $padded_fh->close();
    $unpadded_fh->close();

    return $padded_file;
}

# remove stopwords from the $stem_count list, using the $language and stop word $length
sub _remove_stopwords_from_stem_vector($$$)
{
    my ( $stem_counts, $language_code, $length ) = @_;

    return unless ( $language_code && $length );

    my $language = MediaWords::Languages::Language::language_for_code( $language_code ) || return;

    my $stop_words = $language->get_stop_word_stems( $length );

    map { delete( $stem_counts->{ $_ } ) if ( $stop_words->{ $_ } ) } keys( %{ $stem_counts } );
}

=head2 get_story_word_matrix_file( $db, $stories_ids, $max_words, $stopword_length )

Given a list of stories_ids, generate a matrix consisting of the vector of word stem counts for each stories_id on each
line.  Return a hash of story word counts and a list of word stems.

The list of story word counts is in the following format:
{
    { <stories_id> =>
        { <word_id_1> => <count>,
          <word_id_2 => <count>
        }
    },
    ...
]

The id of each word is the indes of the given word in the word list.  The word list is a list of lists, with each
member list consisting of the stem followed by the most commonly used term.

For example, for stories_ids 1 and 2, both of which contain 4 mentions of 'foo' and 10 of 'bars', the word count
has and and word list look like:

[ { 1 => { 0 => 4, 1 => 10 } }, { 2 => { 0 => 4, 1 => 10 } } ]

[ [ 'foo', 'foo' ], [ 'bar', 'bars' ] ]

The story_sentences for each story will be used for word counting. If $max_words is specified, only the most common
$max_words will be used for each story.

If $stopword_length is specified, a stopword list of size 'tiny', 'short', or 'long' is used for each story language.

The function uses MediaWords::Util::IdentifyLanguage to identify the stemming and stopwording language for each story.
If the language of a given story is not supported, stemming and stopwording become null operations.  For the list of
languages supported, see @MediaWords::Langauges::Language::_supported_languages.

=cut

sub get_story_word_matrix($$;$$)
{
    my ( $db, $stories_ids, $max_words, $stopword_length ) = @_;

    my $word_index_lookup   = {};
    my $word_index_sequence = 0;
    my $word_term_counts    = {};

    $db->begin;
    my $sentence_separator = 'SPLITSPLIT';
    my $story_text_cursor = _get_story_word_matrix_cursor( $db, $stories_ids, $sentence_separator );

    my $word_matrix = {};
    while ( my $stories = $db->query( "fetch 100 from $story_text_cursor" )->hashes )
    {
        last unless ( @{ $stories } );

        for my $story ( @{ $stories } )
        {
            my $wc = MediaWords::Solr::WordCounts->new( language => $story->{ language } );
            $wc->include_stopwords( 1 );
            $wc->languages( [ $story->{ language } ] );

            my $stem_counts = $wc->count_stems( [ split( $sentence_separator, $story->{ story_text } ) ] );

            _remove_stopwords_from_stem_vector( $stem_counts, $story->{ language }, $stopword_length );

            my $stem_count_list = [];
            while ( my ( $stem, $data ) = each( %{ $stem_counts } ) )
            {
                push( @{ $stem_count_list }, [ $stem, $data->{ count }, $data->{ terms } ] );
            }

            if ( $max_words )
            {
                $stem_count_list = [ sort { $b->[ 1 ] <=> $a->[ 1 ] } @{ $stem_count_list } ];
                splice( @{ $stem_count_list }, 0, $max_words );
            }

            my $stem_vector = {};
            for my $stem_count ( @{ $stem_count_list } )
            {
                my ( $stem, $count, $terms ) = @{ $stem_count };

                $word_index_lookup->{ $stem } //= $word_index_sequence++;
                my $index = $word_index_lookup->{ $stem };

                $stem_vector->{ $index } = $count;

                map { $word_term_counts->{ $stem }->{ $_ } += $terms->{ $_ } } keys( %{ $terms } );
            }

            $word_matrix->{ $story->{ stories_id } } = $stem_vector;
        }
    }

    $db->commit;

    my $word_list = [];
    for my $stem ( keys( %{ $word_index_lookup } ) )
    {
        my $term_pairs = [];
        while ( my ( $term, $count ) = each( %{ $word_term_counts->{ $stem } } ) )
        {
            push( @{ $term_pairs }, [ $term, $count ] );
        }

        $term_pairs = [ sort { $b->[ 1 ] <=> $a->[ 1 ] } @{ $term_pairs } ];
        $word_list->[ $word_index_lookup->{ $stem } ] = [ $stem, $term_pairs->[ 0 ]->[ 0 ] ];
    }

    return ( $word_matrix, $word_list );
}

1;
