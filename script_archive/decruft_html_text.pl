#!/usr/bin/perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

my $cwd;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    $cwd = "$FindBin::Bin";
}

use Readonly;

use Test::More;
use MediaWords::Crawler::Extractor;
use DBIx::Simple::MediaWords;
use MediaWords::DBI::Downloads;
use MediaWords::DB;
use MediaWords::Util::HTML;
use XML::LibXML;
use Encode;
use MIME::Base64;

sub main
{
    my @lines = <>;

    my $original_text = join '', @lines;

    my $actual_preprocessed_text = MediaWords::Util::HTML::clear_cruft_text( $original_text );

    say $actual_preprocessed_text;
}

main();

