#!/usr/bin/perl

# parse the sentence of the story
use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}
use MediaWords::DB;
use Lingua::EN::Sentence::MediaWords;

sub main
{
    my ( $stories_id ) = @ARGV;

    $stories_id || die( "usage: mediawords_parse_sentences.pl <stories_id>" );

    binmode STDOUT, ":utf8";

    my $db = MediaWords::DB::connect_to_db;

    my ( $text ) = $db->query(
        "select download_text from download_texts dt, downloads d " .
          "  where d.downloads_id = dt.downloads_id and d.stories_id = ?",
        $stories_id
    )->flat;

    my $sentences = Lingua::EN::Sentence::MediaWords::get_sentences( $text ) || return;

    print join( " - ", @{ $sentences } ) . "\n";
}

main();
