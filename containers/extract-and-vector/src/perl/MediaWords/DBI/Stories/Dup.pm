package MediaWords::DBI::Stories::Dup;

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use HTML::Entities;

use MediaWords::Util::ParseHTML;
use MediaWords::Util::SQL;
use MediaWords::Util::URL;

# common title prefixes that can be ignored for dup title matching
Readonly my $DUP_TITLE_PREFIXES => [
    qw/opinion analysis report perspective poll watch exclusive editorial reports breaking nyt/,
    qw/subject source wapo sources video study photos cartoon cnn today wsj review timeline/,
    qw/revealed gallup ap read experts op-ed commentary feature letters survey/
];

# break a story down into parts separated by [-:|]
sub _get_title_parts
{
    my ( $title ) = @_;

    $title = decode_entities( $title );

    $title = lc( $title );

    $title = MediaWords::Util::ParseHTML::html_strip( $title ) if ( $title =~ /\</ );
    $title = decode_entities( $title );

    my $sep_chars = '\-\:\|';

    # get rid of very common one word prefixes so that opinion: foo bar foo will match report - foo bar foo even if
    # foo bar foo never appears as a solo title
    my $prefix_re = '(?:' . join( '|', @{ $DUP_TITLE_PREFIXES } ) . ')';
    $title =~ s/^(\s*$prefix_re\s*[$sep_chars]\s*)//;

    my $title_parts;
    if ( $title =~ m~https?://[^ ]*~ )
    {
        return [ $title ];
    }
    else
    {
        $title =~ s/(\w)\:/$1 :/g;
        $title_parts = [ split( /\s*[$sep_chars]+\s*/, $title ) ];
    }

    if ( @{ $title_parts } > 1 )
    {
        unshift( @{ $title_parts }, $title );
    }

    map { s/[[:punct:]]//g; s/\s+/ /g; s/^\s+//; s/\s+$//; } @{ $title_parts };

    return $title_parts;
}

# get the difference in seconds between the newest and oldest story in the list
sub _get_story_date_range
{
    my ( $stories ) = @_;

    my $epoch_dates = [ map { MediaWords::Util::SQL::get_epoch_from_sql_date( $_->{ publish_date } ) } @{ $stories } ];

    return List::Util::max( @{ $epoch_dates } ) - List::Util::min( @{ $epoch_dates } );
}

# Get duplicate stories within the set of stories by breaking the title of each story into parts by [-:|] and looking for
# any such part that is the sole title part for any story and is at least 4 words long and is not the title of a story
# with a path-less url.  Any story that includes that title part becames a duplicate.  return a list of duplciate story
# lists. Do not return any list of duplicates with greater than 25 duplicates for fear that the title deduping is
# interacting with some title form in a goofy way.
#
# By default, assume that any solr title part that is less than 5 words long or that is associated with a story whose
# url has no path is a home page and therefore should not be considered as a possible duplicate title part.  If
# $assume_no_home_pages is true, treat every solr url part greater than two words as a potential duplicate title part.
# 
# Don't recognize twitter stories as dups, because the tweet title is the tweet text, and we want to capture retweets.
#
# FIXME make it use Python implementation
sub get_medium_dup_stories_by_title
{
    my ( $db, $stories, $assume_no_home_pages ) = @_;

    my $title_part_counts = {};
    for my $story ( @{ $stories } )
    {
        next if ( $story->{ url } && ( $story->{ url } =~ /https?:\/\/(twitter\.com)/i ) );

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
            my $dup_stories = [ values( %{ $t->{ stories } } ) ];
            if ( ( $num_stories < 26 ) || ( _get_story_date_range( $dup_stories ) < ( 7 * 86400 ) ) )
            {
                push( @{ $duplicate_stories }, $dup_stories );
            }
            else
            {
                my $dup_title = ( values( %{ $t->{ stories } } ) )[ 0 ]->{ title };

                TRACE "Cowardly refusing to mark $num_stories stories as dups [$dup_title]";
            }
        }
    }

    return $duplicate_stories;
}

# Get duplicate stories within the given set that are duplicates because the normalized url for two given stories is the
# same.  Return a list of story duplicate lists.  Do not return any list of duplicates with greater than 5 duplicates for
# fear that the url normalization is interacting with some url form in a goofy way
#
# FIXME make it use Python implementation
sub get_medium_dup_stories_by_url
{
    my ( $db, $stories ) = @_;

    my $url_lookup = {};
    for my $story ( @{ $stories } )
    {
        if ( !$story->{ url } )
        {
            WARN "No URL in story: " . Dumper( $story );
            next;
        }

        my $nu = MediaWords::Util::URL::normalize_url_lossy( $story->{ url } );
        $story->{ normalized_url } = $nu;
        push( @{ $url_lookup->{ $nu } }, $story );
    }

    return [ grep { ( @{ $_ } > 1 ) && ( @{ $_ } < 6 ) } values( %{ $url_lookup } ) ];
}

1;
