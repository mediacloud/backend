#!/usr/bin/env perl

# dedup topic spidered media

# the basic method of this script is to:
# * group media sources by identical domains (eg. www.nytimes.com, nytimes.com, and articles.nytimes.com);
# * for each domain group, aggressively try to identify cases for which we should just automatically
#   merge all media within the given group (as in the above example);
# * otherwise, prompt the user to choose whether and how to dedup the media within the domain.
#
# currently this script just marks media as dups by setting the dup_media_id field in the media source.
# in the future, we are moving to actually removing the duplicate media source.

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Getopt::Long;
use URI;

use MediaWords::DB;
use MediaWords::DBI::Media;
use MediaWords::Util::Tags;
use MediaWords::Util::URL;

sub mark_medium_as_dup
{
    my ( $db, $source_medium, $target_medium ) = @_;

    return if ( $source_medium->{ media_id } == $target_medium->{ media_id } );

    if ( $target_medium->{ dup_media_id } )
    {
        say "target medium has dup_media_id set. skipping ...";
        return;
    }

    if ( $target_medium->{ foreign_rss_links } )
    {
        say "target medium has foreign_rss_links = true. skipping ...";
        return;
    }

    say "$source_medium->{ name } -> $target_medium->{ name }";

    $source_medium->{ dup_media_id } = $target_medium->{ media_id };
    $source_medium->{ hide }         = 1;

    $db->query( <<END, $target_medium->{ media_id }, $source_medium->{ media_id } );
update media set dup_media_id = ? where media_id = ?
END
}

# mark the medium as not dup
sub mark_medium_is_not_dup
{
    my ( $db, $medium ) = @_;

    $medium->{ is_not_dup } = 1;

    $db->query( "update media set is_not_dup = true where media_id = ?", $medium->{ media_id } );
}

# if one medium has the root domain as the url and is a public set, mark everything as the dup of that medium.
# require the parent medium to be a public_set medium if there are any public_set media among $media
sub mark_dups_of_root_domain
{
    my ( $db, $domain, $media ) = @_;

    return if ( @{ $media } > 5 );

    my $require_public_set = scalar( grep { $_->{ public_set } } @{ $media } );

    for my $a ( @{ $media } )
    {
        next if ( $require_public_set && !$a->{ public_set } );
        if ( !$a->{ dup_media_id } && ( $a->{ url_c } =~ m~^https?://(www\.)?$domain/?~ ) )
        {
            for my $b ( @{ $media } )
            {
                next if ( $a->{ media_id } == $b->{ media_id } || $b->{ dup_media_id } );

                mark_medium_as_dup( $db, $b, $a );
            }
        }
    }
}

# if one medium already has other media pointing to it as the dup, use that medium
# as the dup for all other media in the domain
sub mark_dups_of_existing_dup
{
    my ( $db, $domain, $media ) = @_;

    return if ( @{ $media } > 5 );

    for my $m ( @{ $media } )
    {
        if ( $m->{ dup_media_id } )
        {
            my $a = $db->find_by_id( 'media', $m->{ dup_media_id } );

            for my $b ( @{ $media } )
            {
                next if ( $a->{ media_id } == $b->{ media_id } || $b->{ dup_media_id } );

                mark_medium_as_dup( $db, $b, $a );
            }
        }
    }
}

# check for media that are canonical url duplicates and mark one of each pair as a duplicate
sub mark_canonical_url_duplicates
{
    my ( $db, $domain, $media ) = @_;

    map { $_->{ url_c } = MediaWords::Util::URL::normalize_url_lossy( $_->{ url } ) } @{ $media };

    $media = [ sort { length( $a->{ url } ) <=> length( $b->{ url } ) } @{ $media } ];

    for my $a ( @{ $media } )
    {
        next if ( $a->{ dup_media_id } );

        for my $b ( @{ $media } )
        {
            next if ( $a->{ media_id } == $b->{ media_id } || $b->{ dup_media_id } );

            if ( MediaWords::Util::URL::urls_are_equal( $a->{ url_c }, $b->{ url_c } ) )
            {
                mark_medium_as_dup( $db, $b, $a );
            }
        }
    }
}

# prompt user for media merge command and return the command
sub prompt_for_dup_media
{
    my ( $db, $domain, $media ) = @_;

    my $ordered_media = [ sort { $b->{ num_stories } <=> $a->{ num_stories } } @{ $media } ];

    while ( 1 )
    {
        say "DOMAIN: $domain";
        for ( my $i = 0 ; $i < @{ $ordered_media } ; $i++ )
        {
            my $m = $ordered_media->[ $i ];

            my $labels =
              join( ' ', map { uc( $_ ) } grep { $m->{ $_ } } qw(public_set is_not_dup is_spidered foreign_rss_links) );

            if ( !$m->{ hide } )
            {
                say "$i: $m->{ name }";
                say "\tmedia_id: $m->{ media_id }";
                say "\tnum_stories: $m->{ num_stories }";
                say "\turl: $m->{ url }";
                say "\tlabels: $labels\n";
            }
        }

        say "Action (h for help):";

        my $line = <STDIN>;
        chomp( $line );
        my $command = [ split( / /, $line ) ];

        my $help = <<END;
<n>
to mark all remaining media as not dups

or

<source media num> <target media num>
to mark source media num as dup of target media num
where source media num can be 'a' for all or a specific number
END

        if ( $command->[ 0 ] eq 'h' )
        {
            say( $help );
        }
        elsif ( $command->[ 0 ] eq 'n' )
        {
            return undef;
        }
        elsif ( @{ $command } eq 2 )
        {
            my ( $s, $t ) = @{ $command };
            if (   ( $s =~ /^(a|\d+)$/ )
                && ( $t =~ /^\d+$/ )
                && ( $s eq 'a' || $ordered_media->[ $s ] )
                && $ordered_media->[ $t ] )
            {
                my $target_medium = $ordered_media->[ $t ];
                my $source_media = ( $s eq 'a' ) ? [ grep { !$_->{ hide } } @{ $media } ] : [ $ordered_media->[ $s ] ];

                return ( $source_media, $target_medium );
            }
        }

        ERROR "Invalid command.";
        say $help;
    }
}

# return list of all media that are not hidden and have not been marked is_not_dup
sub get_unprocessed_media
{
    my ( $media ) = @_;

    return [ grep { !( $_->{ hide } || $_->{ is_not_dup } || $_->{ dup_media_id } ) } @{ $media } ];
}

# prompt the user to decide whether domain-equivalent media sources are duplicates of one another
sub dedup_media
{
    my ( $db, $domain, $media ) = @_;

    while ( 1 )
    {
        my ( $source_media, $target_medium ) = prompt_for_dup_media( $db, $domain, $media );

        if ( !$source_media )
        {
            map { mark_medium_is_not_dup( $db, $_ ) } @{ $media };
            return;
        }

        for my $source_medium ( @{ $source_media } )
        {
            mark_medium_as_dup( $db, $source_medium, $target_medium );
        }

        my $unprocessed_media = get_unprocessed_media( $media );
        last unless ( @{ $unprocessed_media } > 1 );
    }
}

# return true if we should ignore this domain.  ignore the domain if
# the domain is blank, the number of media is less than 2, the domain matches
# one of a few patterns, or there are more than 5 not_dup media already in the domain
sub ignore_domain
{
    my ( $domain, $domain_media ) = @_;

    return 1 if ( !$domain );

    return 1 if ( $domain =~ /(\.edu|\.us|\.blogspot\..*)$/ );

    my $media_with_stories = [ grep { $_->{ num_stories } > 0 } @{ $domain_media } ];
    return 1 if ( scalar( @{ $media_with_stories } ) < 1 );

    my $unprocessed_media = get_unprocessed_media( $domain_media );
    return 1 if ( scalar( @{ $unprocessed_media } ) < 2 );

    my $not_dup_media = [ grep { $_->{ is_not_dup } } @{ $domain_media } ];
    return 1 if ( scalar( @{ $not_dup_media } ) >= 5 );

    return 0;
}

sub main
{
    my $topics_ids = [ @ARGV ];

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    my $db = MediaWords::DB::connect_to_db;

    my $spidered_tag = MediaWords::Util::Tags::lookup_tag( $db, 'spidered:spidered' )
      || die( "Unable to find spidered:spidered tag" );

    # do this goofy temp table before the bit query below to get the pg query planner not to a slow nested index lookup
    $db->query( <<SQL );
create temporary table public_set_media as

with public_tags as ( select * from tags where show_on_media )

select media_id, 1 public_set from media m
  where m.media_id in (
      select media_id
          from media_tags_map mtm
              join public_tags t using ( tags_id )
      )
SQL

    my $topics_ids_list = @{ $topics_ids } ? join( ',', map { int( $_ ) } @{ $topics_ids } ) : '';
    my $topics_clause = $topics_ids_list ? "topics_id in ($topics_ids_list)" : "1=1";

    # only dedup media that are either not spidered or are associated with topic stories
    # (this eliminates spidered media not actually associated with any topic story)
    my $media = $db->query( <<SQL, $spidered_tag->{ tags_id } )->hashes;
with
    spidered_media as ( select distinct media_id from media_tags_map mtm where mtm.tags_id = ? ),
    topic_media as ( select distinct media_id from snap.live_stories where $topics_clause )

select distinct m.*,
        coalesce( sm.media_id, 0 ) is_spidered,
        coalesce( mh.num_stories_y, 0 ) num_stories,
        coalesce( psm.public_set, 0 ) public_set
    from
        media m
        left join spidered_media sm on ( m.media_id = sm.media_id )
        left join media_health mh on ( m.media_id = mh.media_id )
        left join public_set_media psm on ( m.media_id = psm.media_id )
        left join topic_media tm on ( m.media_id = tm.media_id )
    where
        m.dup_media_id is null and
        ( ( sm.media_id is null ) or ( tm.media_id is not null ) )
  order by public_set desc, num_stories desc, media_id
SQL

    my $media_domain_lookup = {};
    map { push( @{ $media_domain_lookup->{ MediaWords::Util::URL::get_url_distinctive_domain( $_->{ url } ) } }, $_ ) }
      @{ $media };

    # find just the domains that have more than one unprocessed media source
    while ( my ( $domain, $domain_media ) = each( %{ $media_domain_lookup } ) )
    {
        delete( $media_domain_lookup->{ $domain } ) if ( ignore_domain( $domain, $domain_media ) );
    }

    my $num_domains = scalar( values( %{ $media_domain_lookup } ) );

    my $i = 1;
    while ( my ( $domain, $domain_media ) = each( %{ $media_domain_lookup } ) )
    {
        say $i++ . "/ $num_domains";

        # try to auto-dedup via various methods
        mark_dups_of_existing_dup( $db, $domain, $domain_media );
        mark_canonical_url_duplicates( $db, $domain, $domain_media );
        mark_dups_of_root_domain( $db, $domain, $domain_media );

        # only do the manual deduping if the auto-deduping fails to mark all dups
        my $unprocessed_media = get_unprocessed_media( $domain_media );

        dedup_media( $db, $domain, $domain_media ) if ( @{ $unprocessed_media } > 1 );
    }
}

main();
