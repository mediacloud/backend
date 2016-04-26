package MediaWords::Controller::Admin::CM::Bitly;

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Bitly;
use MediaWords::Job::Bitly::EnqueueAllControversyStories;

use base 'Catalyst::Controller::HTML::FormFu';

sub index : Path : Args(0)
{
    return status( @_ );
}

# Show Bit.ly processing status (number of total and unprocessed controversy stories)
sub status : Local
{
    my ( $self, $c, $controversies_id ) = @_;

    unless ( MediaWords::Util::Bitly::bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    my $db = $c->dbis;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id );
    unless ( $controversy )
    {
        die "Controversy $controversies_id was not found";
    }

    unless ( $controversy->{ process_with_bitly } )
    {
        die "Controversy $controversies_id is not set up for Bit.ly processing; please set controversies.process_with_bitly";
    }

    my ( $total_stories ) = $db->query( <<SQL, $controversies_id )->flat;
SELECT COUNT(stories_id) AS total_stories
FROM controversy_stories
WHERE controversies_id = ?
SQL

    my $unprocessed_stories =
      MediaWords::Util::Bitly::num_controversy_stories_without_bitly_statistics( $db, $controversies_id );

    $c->stash->{ controversy }               = $controversy;
    $c->stash->{ bitly_total_stories }       = $total_stories;
    $c->stash->{ bitly_unprocessed_stories } = $unprocessed_stories;
    $c->stash->{ template }                  = 'cm/bitly/status.tt2';
}

# enqueue a job which will, in turn, enqueue all controversy's stories
# for Bit.ly processing
sub add_to_queue : Local
{
    my ( $self, $c, $controversies_id ) = @_;

    unless ( MediaWords::Util::Bitly::bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    my $db = $c->dbis;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id );
    unless ( $controversy )
    {
        die "Controversy $controversies_id was not found";
    }

    unless ( $controversy->{ process_with_bitly } )
    {
        die "Controversy $controversies_id is not set up for Bit.ly processing; please set controversies.process_with_bitly";
    }

    my $args = { controversies_id => $controversies_id };
    my $job_id = MediaWords::Job::Bitly::EnqueueAllControversyStories->enqueue_on_gearman( $args );
    unless ( $job_id )
    {
        die "Job didn't return a job ID for controversy ID $controversies_id";
    }

    my $url = $c->uri_for( "/admin/cm/view/$controversies_id",
        { status_msg => "Controversy's stories will soon be enqueued for Bit.ly processing." } );
    $c->res->redirect( $url );
}

1;
