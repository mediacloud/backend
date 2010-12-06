#!/usr/bin/perl -w

# create media_tag_tag_counts table by querying the database tags / feeds / stories

use strict;

#use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use XML::LibXML;
use Getopt::Long;
use Readonly;
use Carp;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::Stories;
use Data::Dumper;
use Encode;
use MIME::Base64;
use Perl6::Say;
use HTML::TreeBuilder;
use HTML::TreeBuilder::XPath;

sub main
{

    my $story_id;

    my $usage = "author detect options";

    GetOptions( 'story=s' => \$story_id, ) or die "$usage\n";

    die $usage unless $story_id;

    my $db = MediaWords::DB::connect_to_db;

    #say "story: $story_id";

    my $story = $db->find_by_id( 'stories', $story_id );

    my $content = MediaWords::DBI::Stories::get_initial_download_content( $db, $story );

    #say "dl content:${$content}";

    my $tree = HTML::TreeBuilder::XPath->new;    # empty tree
    $tree->parse_content( $$content );

    my @nodes = $tree->findnodes( '//meta[@name="byl"]' );

    my $node = pop @nodes;

    if ( !$node )
    {

        @nodes = $tree->findnodes( '//address[@class="byline author vcard"]' );

        $node = pop @nodes;

        if ( !$node )
        {
            say "couldn't find byline for $story_id";
            exit;
        }

        say $node->as_text;
        exit;

    }

    #say $node;

    #say Dumper([$node]);

    #say $node->dump;

    my $content_attr = $node->attr( 'content' );

    say $content_attr;
}

main();
