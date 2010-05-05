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
use MediaWords::Crawler::Extractor qw (preprocess);
use DBIx::Simple::MediaWords;
use MediaWords::DBI::Downloads;
use MediaWords::DB;
use XML::LibXML;
use Encode;
use MIME::Base64;
use Perl6::Say;

sub main
{
    my @lines = <>;

    my $original_text = join '', @lines;

    my $actual_preprocessed_text_array = HTML::CruftText::clearCruftText($original_text);

    my $actual_preprocessed_text = join( "\n", map { $_  } @{$actual_preprocessed_text_array} );

    say $actual_preprocessed_text;
}

main();

