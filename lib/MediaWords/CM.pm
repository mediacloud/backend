package MediaWords::CM;

# General controversy mapper utilities

use strict;
use warnings;

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use Getopt::Long;
use Data::Dumper;
use MediaWords::DBI::Queries;
use MediaWords::GearmanFunction::SearchStories;

# Create a new controversy
# (returns controversies_id on successful creation, die()s on error)
sub create_controversy($$$$$$)
{
    my ( $db, $name, $pattern, $start_date, $end_date, $media_sets_ids ) = @_;

    my $controversies_id = undef;

    $db->begin;

    eval {

        unless ( ref $media_sets_ids )
        {
            die "media_sets_ids must be a arrayref.";
        }

        # Validate controversy pattern
        my $regex = eval { qr/$pattern/ };
        if ( $@ )
        {
            die "Invalid pattern: $@";
        }

        # find or create a new query for the given date range and set of media
        # sets using MediaWords::DBI::queries::find_or_create_query_by_params
        my $query = MediaWords::DBI::Queries::find_or_create_query_by_params(
            $db,
            {
                start_date     => $start_date,
                end_date       => $end_date,
                media_sets_ids => $media_sets_ids
            }
        );
        unless ( $query )
        {
            die "Unable to create a new query.";
        }
        unless ( defined $query->{ queries_id } )
        {
            die "Queries ID is undefined.";
        }

        # create a new query_story_search with specified regex pattern and
        # pointing to the above query
        # ($c->dbis->create() breaks the foreign key constraint, no idea why)
        $db->insert(
            'query_story_searches',
            {
                queries_id       => $query->{ queries_id } + 0,
                pattern          => $pattern,
                search_completed => 'f'
            }
        );
        my $query_story_searches_id = $db->last_insert_id( undef, undef, 'query_story_searches', undef );
        unless ( $query_story_searches_id )
        {
            die "Query story search ID is undefined.";
        }

        # create a new controversy pointing to the query_story_search
        $db->insert(
            'controversies',
            {
                name                    => $name,
                query_story_searches_id => $query_story_searches_id
            }
        );
        $controversies_id = $db->last_insert_id( undef, undef, 'controversies', undef );
        unless ( $controversies_id )
        {
            die "Controversies ID is undefined.";
        }

        # start a job to process the query_story_search
        my $args = { query_story_searches_id => $query_story_searches_id };
        my $gearman_job_id = MediaWords::GearmanFunction::SearchStories->enqueue_on_gearman( $args );
        say STDERR "Enqueued story search query '$query_story_searches_id' with Gearman job ID: $gearman_job_id";

    };

    if ( $@ )
    {
        # Abort transaction because dying further
        my $error_msg = $@;
        $db->rollback;
        die "$error_msg";
    }

    # Things went fine at this point
    $db->commit;

    return $controversies_id;
}

# get a list controversies that match the controversy option, which can either be an id
# or a pattern that matches controversy names. Die if no controversies are found.
sub require_controversies_by_opt
{
    my ( $db, $controversy_opt ) = @_;

    if ( !defined( $controversy_opt ) )
    {
        Getopt::Long::GetOptions( "controversy=s" => \$controversy_opt ) || return;
    }

    die( "Usage: $0 --controversy < id or pattern >" ) unless ( $controversy_opt );

    my $controversies;
    if ( $controversy_opt =~ /^\d+$/ )
    {
        $controversies = $db->query( "select * from controversies where controversies_id = ?", $controversy_opt )->hashes;
        die( "No controversies found by id '$controversy_opt'" ) unless ( @{ $controversies } );
    }
    else
    {
        $controversies = $db->query( "select * from controversies where name ~* ?", '^' . $controversy_opt . '$' )->hashes;
        die( "No controversies found by pattern '$controversy_opt'" ) unless ( @{ $controversies } );
    }

    return $controversies;
}

1;
