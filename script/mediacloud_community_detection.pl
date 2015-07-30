#!/usr/bin/env perl
use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::CommonLibs;
use Modern::Perl "2013";
use SNA::Network;
use Encode;
use XML::FeedPP;
use Data::Dumper;
use MediaWords::DB;
use List::Util qw(first);
use List::MoreUtils qw(firstidx);
use MediaWords::Controller::Admin::CM;
use Text::CSV;
use CGI qw(:standard);

# query the db for media and links and create an SNA::Network graph from the results.
# return the SNA::Network object.
sub create_graph
{
    my ( $db )      = @_;
    my ( $cdts_id ) = @ARGV;
    my ( $cdts, $cd, $controversy ) = MediaWords::Controller::Admin::CM::_get_controversy_objects( $db, $cdts_id );
    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, 1 );
    my $net   = SNA::Network->new();
    my $media = $db->query(
        "select dm.*, dmlc.* from dump_media dm, dump_medium_link_counts dmlc
  where dm.media_id in
    ( ( select source_media_id from dump_medium_links ) union
      ( select ref_media_id from dump_medium_links ) ) and dm.media_id = dmlc.media_id  
   order by dmlc.inlink_count desc limit 500"
    )->hashes;

    my $media_links         = $db->query( "select * from dump_medium_links" )->hashes;
    my $node_id             = 0;
    my %medium_lookup       = ();
    my %medium_index_lookup = ();

    #my %medium_links = count_aggregate_links( $media_links );

    for my $medium ( @{ $media } )
    {
        my $mediaid = $medium->{ 'media_id' };
        my $name    = $medium->{ 'name' };
        my $links   = $medium->{ 'inlink_count' };
        if ( !exists( $medium_lookup{ $mediaid } ) )
        {
            $net->create_node_at_index(
                index    => $node_id,
                name     => $name,
                media_id => $mediaid,
                links    => $links
            );
            $medium_lookup{ $mediaid }       = $mediaid;
            $medium_index_lookup{ $mediaid } = $node_id;
            $node_id++;
        }
    }
    for my $medium ( @{ $media_links } )
    {
        my $source_mediaid = $medium->{ 'source_media_id' };
        my $target_mediaid = $medium->{ 'ref_media_id' };
        my $links          = $medium->{ 'link_count' };
        if ( ( exists $medium_lookup{ $source_mediaid } ) and ( exists $medium_lookup{ $target_mediaid } ) )
        {
            $net->create_edge(
                source_index => $medium_index_lookup{ $source_mediaid },
                target_index => $medium_index_lookup{ $target_mediaid },
                weight       => 1
            );
        }
    }
    return $net;
}

# given an SNA::Network object with a graph representing the media graph
sub detect_communities
{
    my ( $net ) = @_;
    my $fh;
    my $num_communities = SNA::Network::Algorithm::Louvain::identify_communities_with_louvain( $net );
    open $fh, ">:encoding(utf8)", "communities.csv";
    say $fh "Media_id:", "\t", "Media_name:", "\t", "Community_id: ", "\t", "Links:";
    foreach my $community ( $net->communities )
    {

        foreach my $member ( $community->members )
        {
            my $unformatted_links = Dumper( $member->{ 'links' } );
            my $unformatted_name  = Dumper( $member->{ 'name' } );
            my $unformatted_id    = Dumper( $member->{ 'media_id' } );
            $unformatted_links =~ s{\A\$VAR\d+\s*=\s*}{};
            $unformatted_name =~ s{\A\$VAR\d+\s*=\s*}{};
            $unformatted_id =~ s{\A\$VAR\d+\s*=\s*}{};
            my $formatted_links = eval $unformatted_links;
            my $formatted_name  = eval $unformatted_name;
            my $formatted_id    = eval $unformatted_id;
            say $fh $formatted_id, "\t", $formatted_name, "\t", $community->index, "\t", $formatted_links;
        }
    }
    close $fh;
}

sub main
{
    my $db  = MediaWords::DB::connect_to_db;
    my $net = create_graph( $db );
    detect_communities( $net );
}
main();
