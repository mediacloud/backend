package MediaWords::GearmanFunction::ImportFeedlyStories;

=head1 NAME

MediaWords::GearmanFunction::ImportFeedlyStories - import stories from the feedly api

=head1 DESCRIPTION

Use the feedly api to backfill stories for an existing feed or media source.

=cut

use strict;
use warnings;

use Moose;
with 'MediaWords::GearmanFunction';

BEGIN
{
    use FindBin;

    # "lib/" relative to "local/bin/gjs_worker.pl":
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;

=head1 METHODS

=head2 run( $self, $args )

Call MediaWords::ImportStories::Feedly->scrape_stories() for the given feed or feeds.

$args must include either feeds_id or media_id.  If feeds_id is specified, scrape that feed.  If media_id is specified,
scrape all active feeds for that media source.

=cut

sub run($;$)
{
    my ( $self, $args ) = @_;

    die unless ( $args->{ feeds_id } || $args->{ media_id } );

    my $db = MediaWords::DB::connect_to_db();

    my $feeds = [];
    if ( $args->{ feeds_id } )
    {
        my $feed = $db->find_by_id( 'feeds', $args->{ feeds_id } );
        push( @{ $feeds }, $feed ) if ( $feed );
    }
    else
    {
        my $media_feeds = $db->query( <<SQL, $args->{ media_id } )->hashes;
select * from feeds where media_id = ? and status = 'active'
SQL
        push( @{ $feeds }, $media_feeds ) if ( $media_feeds );
    }

    say STDERR "no feeds found for args: " . Dumper( $args ) unless ( @{ $feeds } );

    my $feed_urls = [ map { $_->{ url } } @{ $feeds } ];
    my $media_id = $feeds->[ 0 ]->{ media_id };

    my $import = MediaWords::ImportStories::Feedly->new( db => $db, media_id => $media_id, feed_url => $feed_urls );

    my $import_stories;
    eval { $import_stories = $import->scrape_stories() };
    die( $@ ) if ( $@ );

    my $num_module_stories = scalar( @{ $import->module_stories } );
    my $num_import_stories = scalar( @{ $import_stories } );

    say STDERR "feedly import results: $num_module_stories feedly stories, $num_import_stories stories imported";
}

# write a single log instead of many separate logs
sub unify_logs()
{
    return 1;
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
