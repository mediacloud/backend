package MediaWords::DBI::Stories::AP;

# routines for determining whether a given story is syndicated from the Associated Press.
# the algorithm used in this module was developed using a decision tree algorithm:
#
#           'ap_mentions_sentences',
#             '1' => '1', X
#             '0' => [ X
#                    'associated_press_mentions',
#                      '1' => [ X
#                             'quoted_associated_press_first_quarter_mentions',
#                               '1' => '1', X
#                               '0' => [ X
#                                      'dup_sentences_32',
#                                        '1' => '1', X
#                                        '0' => [ X
#                                               'associated_press_near_title',
#                                                 '1' => '1', X
#                                                 '0' => [ X
#                                                        'ap_news_mentions',
#                                                          '1' => '1', X
#                                                          '0' => [ X
#                                                                 'ap_mentions',
#                                                                   '1' => '1', X
#                                                                   '0' => '0' X
#                                        '2' => [ X
#                                                 'associated_press_near_title', X
#                                                   '1' => '1', X
#                                                   '0' => [ X
#                                                          'associated_press_tag_mentions', X
#                                                            '1' => '0', X
#                                                            '0' => '1' X
#                      '0' => [
#                             'dup_sentences_32',
#                               '1' => [
#                                        'ap_mentions',
#                                          '1' => [
#                                                 'ap_mentions_uppercase_location',
#                                                   '1' => '1',
#                                                   '0' => '0'
#                                          '0' => '0'
#                               '0' => '0',
#                               '2' => '1'

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.dbi.stories.ap' );

use MediaWords::DBI::Downloads;
use MediaWords::Util::CSV;

use Digest::MD5 qw(md5);

sub _get_story_content
{
    my ( $db, $story ) = @_;

    if ( $story->{ content } )
    {
        return $story->{ content };
    }

    my $download = $story->{ download };
    if ( !$download )
    {
        $download = $db->query( <<SQL, $story->{ stories_id } )->hash;
select * from downloads where stories_id = \$1 order by downloads_id limit 1
SQL
    }

    # There might be no download at all for full text RSS story
    return '' unless ( $download );

    return '' unless ( $download->{ state } eq 'success' );

    my $content;

    eval { $content = MediaWords::DBI::Downloads::fetch_content( $db, $download ) };
    if ( $@ or ( !defined $content ) )
    {
        WARN "error fetching content: $@";
        return 0;
    }

    $story->{ content } = $content;

    return $story->{ content };
}

sub _get_ap_media_id($)
{
    my ( $db ) = @_;

    my ( $ap_media_id ) = $db->query( "select media_id from media where name = ?", get_ap_medium_name() )->flat;

    return $ap_media_id;
}

sub _get_ap_dup_sentence_lengths_from_db
{
    my ( $db, $story ) = @_;

    my $ap_media_id = _get_ap_media_id( $db );

    return [] unless ( defined( $ap_media_id ) );

    my $sentences = $db->query( <<SQL )->hashes;
with sentence_md5s as (
    select md5( ss.sentence ) md5_sentence
        from story_sentences ss
        where ss.stories_id = $story->{ stories_id } and
        ss.media_id <> $ap_media_id
)

select * from story_sentences
    where media_id = $ap_media_id and
        md5( sentence ) in ( select md5_sentence from sentence_md5s );
SQL

    my $sentence_lengths = [ map { length( $_->{ sentence } ) } @{ $sentences } ];

    return $sentence_lengths;
}

# given raw html content, extract the content and parse it into sentences using the existing mediacloud pipeline code
sub _get_sentences_from_content($)
{
    my ( $story ) = @_;

    my $content = $story->{ content };

    my $text = MediaWords::DBI::Downloads::extract_content( $content )->{ extracted_text };

    my $lang = MediaWords::Languages::Language::language_for_code( $story->{ language } )
      || MediaWords::Languages::Language::default_language();

    my $sentences = $lang->split_text_to_sentences( $text );

    return $sentences;
}

sub _get_ap_dup_sentence_lengths_from_content($$)
{
    my ( $db, $story ) = @_;

    my $ap_media_id = _get_ap_media_id( $db );

    return [] unless ( defined( $ap_media_id ) );

    my $sentences = _get_sentences_from_content( $story );

    my $md5s = [ map { Digest::MD5::md5_hex( $_ ) } @{ $sentences } ];

    my $md5_list = join( ',', map { $db->quote( $_ ) } @{ $md5s } );

    my $sentence_lengths = $db->query( <<SQL )->flat;
select length(sentence) len from story_sentences
    where media_id = $ap_media_id and
        md5( sentence ) in ( $md5_list );
SQL

    return $sentence_lengths;
}

sub _get_ap_dup_sentence_lengths
{
    my ( $db, $story ) = @_;

    if ( $story->{ stories_id } )
    {
        return _get_ap_dup_sentence_lengths_from_db( $db, $story );
    }

    return _get_ap_dup_sentence_lengths_from_content( $db, $story );
}

sub _get_content_pattern_matches
{
    my ( $db, $story, $pattern, $restrict_to_first ) = @_;

    my $content = _get_story_content( $db, $story );

    if ( $restrict_to_first )
    {
        $content = substr( $content, 0, int( length( $content ) * $restrict_to_first ) );
    }

    my @matches = $content =~ /$pattern/;

    return scalar( @matches );
}

sub _get_text_pattern_matches
{
    my ( $db, $story, $pattern ) = @_;

    my $text = MediaWords::DBI::Stories::get_text( $db, $story );

    my @matches = $text =~ /$pattern/;

    return scalar( @matches );
}

sub _get_sentence_pattern_matches
{
    my ( $db, $story, $pattern ) = @_;

    my $sentences;
    if ( $story->{ stories_id } )
    {
        $sentences = $db->query( <<SQL, $story->{ stories_id } )->flat;
select sentence from story_sentences where stories_id = ?
SQL
    }
    else
    {
        $sentences = $story->{ sentences };
    }

    my $text = join( ' ', @{ $sentences } );

    my @matches = $text =~ /$pattern/;

    return scalar( @matches );
}

sub _get_all_string_match_positions
{
    my ( $haystack, $needle ) = @_;

    my $positions = [];
    my $offset    = 0;

    while ( ( my $pos = index( substr( $haystack, $offset ), $needle ) ) > 0 )
    {
        push( @{ $positions }, $pos + $offset );
        $offset = $offset + $pos + 1;
    }

    return $positions;
}

sub _get_associated_press_near_title
{
    my ( $db, $story ) = @_;

    my $content = lc( _get_story_content( $db, $story ) );

    $content =~ s/\s+/ /g;

    my $title_positions = _get_all_string_match_positions( $content, lc( $story->{ title } ) );
    my $ap_positions    = _get_all_string_match_positions( $content, 'associated press' );

    for my $title_p ( @{ $title_positions } )
    {
        for my $ap_p ( @{ $ap_positions } )
        {
            return 1 if ( abs( $title_p - $ap_p ) < 256 );
        }
    }

    return 0;
}

# return the number of sentences in the story that are least 32 characters long and are a duplicate
# of a sentence in the associated press media source
sub _get_dup_sentences_32
{
    my ( $db, $story ) = @_;

    my $sentence_lengths = _get_ap_dup_sentence_lengths( $db, $story );

    my $num_sentences = scalar( grep { $_ >= 32 } @{ $sentence_lengths } );

    return 0 unless $num_sentences;

    return ( $num_sentences > 10 ) ? 2 : 1;
}

# return 1 if the stories is syndicated by the ap, 0 otherwise.  uses the decision tree at the top of the module.
#
# the story object must have a title field and either a stories_id field or a content and a language field
sub is_syndicated
{
    my ( $db, $story ) = @_;

    if ( !$story->{ stories_id } && ( defined( $story->{ content } ) && defined( $story->{ language } ) ) )
    {
        die( '$story object must have a title field and either a stories_id field or a content and a language field' );
    }

    # shallow copy story so that we can cache data in the object with introducing side effects
    $story = { %{ $story } };

    # add a sentences field if this is an external story.  do this here so that we don't have to do it repeatedly below
    if ( !$story->{ stories_id } )
    {
        $story->{ sentences } = _get_sentences_from_content( $story );
    }

    my $ap_mentions_sentences = _get_sentence_pattern_matches( $db, $story, qr/\(ap\)/i );
    if ( $ap_mentions_sentences ) { TRACE( 'ap: ap_mentions_sentences' ); return 1 }
    else
    {
        my $associated_press_mentions = _get_content_pattern_matches( $db, $story, qr/associated press/i );
        if ( $associated_press_mentions )
        {
            my $quoted_associated_press_mentions =
              _get_content_pattern_matches( $db, $story, qr/["\'\|].{0,8}associated press.{0,8}["\'\|]/i );
            if ( $quoted_associated_press_mentions ) { TRACE( 'ap: quoted_associated_press' ); return 1 }
            else
            {
                my $dup_sentences_32 = _get_dup_sentences_32( $db, $story );
                if ( $dup_sentences_32 == 1 ) { TRACE( 'ap: assoc press -> dup_sentences_32' ); return 1 }
                elsif ( $dup_sentences_32 == 0 )
                {
                    my $associated_press_near_title = _get_associated_press_near_title( $db, $story );
                    if ( $associated_press_near_title ) { TRACE( 'ap: assoc press -> near title' ); return 1 }
                    else
                    {
                        my $ap_news_mentions = _get_content_pattern_matches( $db, $story, qr/ap news/i );
                        if   ( $ap_news_mentions ) { TRACE( 'ap: assoc press -> ap news' );    return 1 }
                        else                       { TRACE( 'ap: assoc press -> no ap news' ); return 0 }
                    }
                }
                else    # $dup_sentences_32 == 2
                {
                    my $associated_press_near_title = _get_associated_press_near_title( $db, $story );
                    if ( $associated_press_near_title ) { TRACE( 'ap: assoc press near title' ); return 1 }
                    else
                    {
                        my $associated_press_tag_mentions =
                          _get_content_pattern_matches( $db, $story, qr/\<[^\<\>]*associated press[^\<\>]*\>/i );
                        if   ( $associated_press_tag_mentions ) { TRACE( 'ap: assoc press title -> tag' );    return 0 }
                        else                                    { TRACE( 'ap: assoc press title -> no tag' ); return 1 }
                    }
                }
            }
        }
        else
        {
            my $dup_sentences_32 = _get_dup_sentences_32( $db, $story );
            if ( $dup_sentences_32 == 1 )
            {
                my $ap_mentions_uppercase_location = _get_text_pattern_matches( $db, $story, qr/[A-Z]+\s*\(AP\)/ );
                if   ( $ap_mentions_uppercase_location ) { TRACE( 'ap: single dup sentence -> ap upper' ); return 1 }
                else                                     { TRACE( 'ap: single dup sentence -> no upper' ); return 0 }
            }
            elsif ( $dup_sentences_32 == 0 ) { TRACE( 'ap: no features' );        return 0 }
            else                             { TRACE( 'ap: dup sentences > 10' ); return 1 }    # $dup_sentences_32 == 2
        }
    }

    # should not get here -- all branches should be covered above
    WARNING( 'is_syndicated: fell through decision tree' );
    return 0;
}

1;
