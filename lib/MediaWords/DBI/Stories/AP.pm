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

    return '' unless ( $download->{ state } eq 'success' );

    my $content_ref;

    eval { $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $download ) };
    if ( $@ || !$content_ref )
    {
        warn( "error fetching content: $@" );
        return 0;
    }

    $story->{ content } = $$content_ref;

    return $story->{ content };
}

sub _get_ap_dup_sentence_lengths
{
    my ( $db, $story ) = @_;

    my ( $ap_media_id ) = $db->query( "select media_id from media where name = 'Associated Press - Full Feed'" )->flat;

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

    my $sentences = $db->query( "select sentence from story_sentences where stories_id = ?", $story->{ stories_id } )->flat;

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

# set the value in the story->{ ap_features } hash
sub _set_feature
{
    my ( $story, $name, $value, $set_features ) = @_;

    return unless ( $set_features );

    $story->{ ap_features }->{ $name } = $value;
}

# return 1 if the stories is syndicated by the ap, 0 otherwise.  uses the decision tree at the top of the module.
sub is_syndicated
{
    my ( $db, $story, $set_features ) = @_;

    my $ap_mentions_sentences = _get_sentence_pattern_matches( $db, $story, qr/\(ap\)/i );
    _set_feature( $story, 'ap_mentions_sentences', $ap_mentions_sentences, $set_features );
    if ( $ap_mentions_sentences ) { return 1 }
    else
    {
        my $associated_press_mentions = _get_content_pattern_matches( $db, $story, qr/associated press/i );
        _set_feature( $story, 'associated_press_mentions', $associated_press_mentions, $set_features );
        if ( $associated_press_mentions )
        {
            my $quoted_associated_press_first_quarter_mentions =
              _get_content_pattern_matches( $db, $story, qr/["\'\|].{0,8}associated press.{0,8}["\'\|]/i );
            _set_feature(
                $story,
                'quoted_associated_press_first_quarter_mentions',
                $quoted_associated_press_first_quarter_mentions,
                $set_features
            );
            if ( $quoted_associated_press_first_quarter_mentions ) { return 1 }
            else
            {
                my $dup_sentences_32 = _get_dup_sentences_32( $db, $story );
                _set_feature( $story, 'dup_sentences_32', $dup_sentences_32, $set_features );
                if ( $dup_sentences_32 == 1 ) { return 1 }
                elsif ( $dup_sentences_32 == 0 )
                {
                    my $associated_press_near_title = _get_associated_press_near_title( $db, $story );
                    _set_feature( $story, 'associated_press_near_title', $associated_press_near_title, $set_features );
                    if ( $associated_press_near_title ) { return 1 }
                    else
                    {
                        my $ap_news_mentions = _get_content_pattern_matches( $db, $story, qr/ap news/i );
                        _set_feature( $story, 'ap_news_mentions', $ap_news_mentions, $set_features );
                        if   ( $ap_news_mentions ) { return 1 }
                        else                       { return 0 }
                    }
                }
                else    # $dup_sentences_32 == 2
                {
                    my $associated_press_near_title = _get_associated_press_near_title( $db, $story );
                    _set_feature( $story, 'associated_press_near_title', $associated_press_near_title, $set_features );
                    if ( $associated_press_near_title ) { return 1 }
                    else
                    {
                        my $associated_press_tag_mentions =
                          _get_content_pattern_matches( $db, $story, qr/\<[^\<\>]*associated press[^\<\>]*\>/i );
                        _set_feature(
                            $story,
                            'associated_press_tag_mentions',
                            $associated_press_tag_mentions,
                            $set_features
                        );
                        if   ( $associated_press_tag_mentions ) { return 0 }
                        else                                    { return 1 }
                    }
                }
            }
        }
        else
        {
            my $dup_sentences_32 = _get_dup_sentences_32( $db, $story );
            _set_feature( $story, 'dup_sentences_32', $dup_sentences_32, $set_features );
            if ( $dup_sentences_32 == 1 )
            {
                my $ap_mentions_uppercase_location = _get_text_pattern_matches( $db, $story, qr/[A-Z]+\s*\(AP\)/ );
                _set_feature( $story, 'ap_mentions_uppercase_location', $ap_mentions_uppercase_location, $set_features );
                if   ( $ap_mentions_uppercase_location ) { return 1 }
                else                                     { return 0 }
            }
            elsif ( $dup_sentences_32 == 0 ) { return 0 }
            else                             { return 1 }    # $dup_sentences_32 == 2
        }
    }

    return 0;
}

1;
