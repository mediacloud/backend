#!/usr/bin/env perl
#
# Extract plain text corpus from a live Media Cloud database
#
# Usage:
#   ./extract_corpus_from_mediacloud.pl --language=en > corpus.txt
#
# Run:
#   ./extract_corpus_from_mediacloud.pl --help
# for more options (e.g. story separator).
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use utf8;
use Getopt::Long;
use Regexp::Common qw /URI/;

sub extract_corpus_from_mc_database($$$)
{
    my ( $language, $output_file, $story_separator ) = @_;

    # Output file or STDOUT
    if ( $output_file ne '-' )
    {
        open( OUTPUT, '>', $output_file ) or die $!;
    }
    else
    {
        open( OUTPUT, '>&', \*STDOUT ) or die $!;
    }

    binmode( OUTPUT, ":utf8" );

    # Connect to the database
    my $db = MediaWords::DB::connect_to_db;

    # Print out story texts
    my $story_texts = $db->query(
        <<"EOF",
        SELECT stories.stories_id,
               ARRAY_TO_STRING(ARRAY_AGG(download_texts.download_text), ' ') AS story_text
        FROM stories
            INNER JOIN downloads ON stories.stories_id = downloads.stories_id
            INNER JOIN download_texts ON downloads.downloads_id = download_texts.downloads_id
        WHERE stories.language = ?
        GROUP BY stories.stories_id
        ORDER BY stories.stories_id
EOF
        $language
    )->hashes;

    my $story_count = @{ $story_texts };
    my $x           = 0;
    for my $story_text ( @{ $story_texts } )
    {
        my $text = $story_text->{ story_text };

        # Remove URLs
        $text =~ s/$RE{URI}{HTTP}//gs;

        # Remove double spaces and line breaks
        $text =~ s/ +/ /gs;
        $text =~ s/\n\n+/\n\n/gs;

        # Remove separator if it is a part of the text
        $text =~ s/\n\Q$story_separator\E\n//gs;
        $text =~ s/^\Q$story_separator\E\n//gs;
        $text =~ s/\n\Q$story_separator\E$//gs;

        print OUTPUT $text;

        ++$x;
        if ( $x < $story_count )
        {
            print OUTPUT "\n$story_separator\n\n";
        }
    }

    close OUTPUT unless $output_file eq '-';
}

sub main
{
    binmode( STDOUT, ":utf8" );
    binmode( STDERR, ":utf8" );

    my $language        = '';                    # Story language to limit the corpus to
    my $output_file     = '-';                   # Corpus output file; default is STDOUT
    my $story_separator = '----------------';    # Delimiter to separate one story (article) from another

    my Readonly $usage =
      "Usage: $0" . ' --language=en' . ' [--output_file=corpus.txt]' . ' [--story_separator=----------------]';

    GetOptions(
        'language=s'        => \$language,
        'output_file=s'     => \$output_file,
        'story_separator=s' => \$story_separator,
    ) or die "$usage\n";
    die "$usage\n" unless ( $language and $output_file and $story_separator );

    say STDERR "starting --  " . localtime();

    extract_corpus_from_mc_database( $language, $output_file, $story_separator );

    say STDERR "finished --  " . localtime();
}

main();
