#!/usr/bin/env perl

# delete all feeds belonging to a given media source, taking care to get rid of
# all associated stories and downloads in the process

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;

use MediaWords::DB;

sub main
{
    my ( $media_id ) = @ARGV;

    die( "usage: $0 < media_id >" ) unless ( $media_id );

    my $db = MediaWords::DB::connect_to_db;

    my $medium = $db->find_by_id( 'media', $media_id ) || die( "invalid media_id '$media_id'" );
    $medium->{ feeds } = $db->query( "select * from feeds where media_id = ?", $media_id )->hashes;

    print "Are you sure you want to delete this medium?\n";

    print Dumper( $medium );

    print "y/n: ";

    my $answer = <STDIN>;
    chomp( $answer );

    return unless ( $answer eq 'y' );

    print STDERR "deleting downloads ...\n";
    $db->query( <<END, $media_id );
delete from downloads d using feeds f
    where d.feeds_id = f.feeds_id and f.media_id = ?
END

    print STDERR "deleting stories ...\n";
    $db->query( "delete from stories s where media_id = ?", $media_id );

    print STDERR "deleting feeds ...\n";
    $db->query( "delete from feeds f where media_id = ?", $media_id );
}

main();
