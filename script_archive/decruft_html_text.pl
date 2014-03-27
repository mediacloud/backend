#!/usr/bin/env perl

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

use Modern::Perl "2013";
use MediaWords::CommonLibs;
use HTML::CruftText;

# use Test::More;
# use MediaWords::Crawler::Extractor qw (preprocess);
# use DBIx::Simple::MediaWords;
# use MediaWords::DBI::Downloads;
# use MediaWords::DB;
# use XML::LibXML;
# use Encode;
# use MIME::Base64;

sub main
{
    my @lines = <>;

    my $original_text = join '', @lines;

    my @split_lines = split( /[\n\r]+/, $original_text );

    my $actual_preprocessed_text_array = HTML::CruftText::clearCruftText( \@split_lines );

    my $actual_preprocessed_text = join( "\n", map { $_ } @{ $actual_preprocessed_text_array } );

    say $actual_preprocessed_text;
}

main();

