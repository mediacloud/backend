#!/usr/bin/perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::Crawler::Extractor;
use Getopt::Long;
use HTML::Strip;
use DBIx::Simple::MediaWords;
use MediaWords::DB;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::DownloadTexts;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );
use XML::LibXML;
use Data::Dumper;

use Digest::SHA qw(sha1 sha1_hex sha1_base64);

use MediaWords::CommonLibs;

#use XML::LibXML::CDATASection;
use Encode;
use MIME::Base64;
use Lingua::EN::Sentence::MediaWords;

use XML::FeedPP;
use XML::TreePP;

#use XML::LibXML::Enhanced;

# do a test run of the text extractor
sub main
{

    my $content;

    my $dump_file = 'content.txt';

    open CONTENT_FILE, "<", $dump_file;

    while ( <CONTENT_FILE> )
    {
        $content .= $_;
    }

    my $type = 'string';

    my $fp;

    say "starting eval for content:\n$content";

    #my $opts = { map { $_ => $args->{$_} } grep { ! /^-/ } keys %$args };

    my $opts = {};

    #    my $VERSION = 'foo';

    my $TREEPP_OPTIONS = {

        #    force_array => [qw( item rdf:li entry )],
        #  first_out   => [qw( -xmlns:rdf -xmlns -rel -type url title link )],
        #   last_out    => [qw( description image item items entry -width -height )],
        #    user_agent  => "XML-FeedPP/$VERSION ",
    };

    my $tpp = XML::TreePP->new( %$TREEPP_OPTIONS, %$opts );

    $tpp->parse( $content );

    #    eval { $fp = XML::FeedPP->new( $content, -type => $type ); };

    say "finished";
}

main();
