package MediaWords::Controller::Cosines;
use strict;
use warnings;
use parent 'Catalyst::Controller';

use Locale::Country;
use URI::Escape;
use DBIx::Simple;
use MediaWords::DBI::Stories;
use Math::Round;
use Lingua::StopWords qw{ getStopWords };

# globals for comparisons
my @media_texts;
my @word_vectors;
my %corpus;
my @text_hashes;
my $SAMPLESIZE = 100;

my @media_ids = qw{1 669 1106 1092 115 121 238 5 95 35 2 96 15 26 30 28 1097};

#my @media_ids = qw{45 70 97 47 43 62 8 669 24 72 1092 1094 11 93 78 14 4 29 66 98 57 101 1 25 17 9 31 38 40 77 104 21 34 37 6 46 79 106 19 44 5 95 35 2 96 15 26 30 28 1097};

# here's the most popular sources in ascending order qw{45 70 97 47 43 62 8 669 24 72 1092 1094 11 93 78 14 4 29 66 98 57 101 1 25 17 9 31 38 40 77 104 21 34 37 6 46 79 106 19 44 5 95 35 2 96 15 26 30 28 1097};
# my original list qw{1 669 1106 1092 1094 115 121 238};
my @media_titles = qw{New_York_Times Daily_Kos Fox_News ABC_news Bitch_Phd};

sub index : Path : Args(0)
{

    return media_tag_counts(@_);
}

#################################################################################
#
# computes cosine distance between bodies of text in a corpus of text on a euclidean
# space of unigram word types
#
#################################################################################

# I think this will be useful for general comparison of both articles/blog posts in entirety or their tags depending on context. I could
# envision using the tags to generate a set of these cosine distances to visualize news source similarity over a given time-frame or
# also to examine individual aricles within a source or multiple ones across a source.

#David suggests combine with term based search

sub cosine_distance
{
    my (@vector1) = @{ $_[0] };
    my (@vector2) = @{ $_[1] };
    if ( scalar @vector1 != scalar @vector2 )
    {
        print "error! " . scalar @vector1 . " not equal to " . scalar @vector2 . "\n";
        return "false";
    }
    my $sum;
    for ( my $i = 0 ; $i < @vector1 ; $i++ )
    {
        $sum += defined $vector1[$i] && defined $vector2[$i] ? $vector1[$i] * $vector2[$i] : 0;
    }
    my $arccos;
    if ( norm(@vector1) * norm(@vector2) > 0 )
    {
        $arccos = $sum / ( norm(@vector1) * norm(@vector2) );
    }
    else
    {
        $arccos = -1;
    }
    return $arccos;
}

sub norm
{
    my @vector = @_;
    my $sum;
    for ( my $i = 0 ; $i < @vector ; $i++ )
    {
        $sum += defined $vector[$i] ? $vector[$i] * $vector[$i] : 0;
    }
    return sqrt $sum;
}

# main comparison routine
sub compare_sources
{
    my ($db) = @_;

    # parses files (really any string works) into an array of hash refs to hashes of word types to word token counts
    foreach my $media (@media_texts)
    {
        my $hash = {};
        foreach my $article (@$media)
        {
            my $text = lc($article);
            $text =~ s/[^\w^'^ ]//gi;
            $text =~ s/\s+/ /g;
            while ( $text =~ s/(.*?)\s+// )
            {

                #print "token: $1\n";
                if ( $hash->{$1} )
                {
                    $hash->{$1} = $hash->{$1} + 1;
                }
                else
                {
                    $hash->{$1} = 1;
                }
            }

            #print "token: $text\n";
            if ( $hash->{$text} )
            {
                $hash->{$text} = $hash->{$text} + 1;
            }
            else
            {
                $hash->{$text} = 1;
            }
        }

        #clear out stopwords
        my $stopwords = getStopWords('en');
        while ( $stopwords =~ s/(.*?)\s+// )
        {
            if ( $hash->{$1} )
            {
                $hash->{$1} = 0;
            }
        }
        push( @text_hashes, $hash );
    }

    print STDERR "building corpus hash\n";

    # collects all word types in corpus into a master hash, %corpus: word type => array index
    for ( my $index = 0 ; $index < @text_hashes ; ++$index )
    {
        my $hash    = $text_hashes[$index];
        my $counter = 0;
        foreach my $key ( keys %$hash )
        {
            $corpus{$key} = $counter++ unless $corpus{$key};
        }
    }

    print STDERR "building word vectors\n";

    # generates a word vector for each text using %corpus to get array index for each word type
    # and word tokens to get
    for ( my $index = 0 ; $index < @text_hashes ; ++$index )
    {
        my $hash = $text_hashes[$index];
        my @word_vector;
        foreach my $key ( keys %corpus )
        {
            $word_vector[ $corpus{$key} ] = $hash->{$key};
        }
        $word_vectors[$index] = [@word_vector];
    }

    print STDERR "computing cosine distances\n";

    # computes cosine distance for all vectors in @word_vectors
    my $distances    = [];
    my $media_names  = [];
    my $largest_dif  = 0;
    my $smallest_dif = 1;

    for ( my $index = 0 ; $index < @word_vectors ; ++$index )
    {
        my $subdistances = [];
        for ( my $index2 = 0 ; $index2 < $index ; ++$index2 )
        {
            my $distance = cosine_distance( $word_vectors[$index], $word_vectors[$index2] );
            $largest_dif  = $distance if $distance > $largest_dif;
            $smallest_dif = $distance if $distance < $smallest_dif;
            $subdistances->[$index2] = $distance;
        }
        $distances->[$index] = $subdistances;
        my @media_name = $db->query( "select name from media where media_id =?", $media_ids[$index] )->flat;
        $media_names->[$index] = $media_name[0];
    }

    for ( my $index = 0 ; $index < @word_vectors ; ++$index )
    {
        for ( my $index2 = @word_vectors ; $index2 > $index ; --$index2 )
        {
            $distances->[$index]->[$index2] = $distances->[$index2]->[$index];
        }
    }

    print "results:<br />";
    for ( my $i = 0 ; $i < scalar @$distances ; ++$i )
    {
        my $subdistance = $distances->[$i];
        for ( my $j = 0 ; $j < $i ; ++$j )
        {
            print "distance between text $media_names->[$i] and $media_names->[$j] is:\n"
              . $subdistance->[$j]
              . " absolute units<br />";    #"
        }
    }
    print "<br />normalized table<br />";
    print "<table style='text-align:center;'>\n";
    print "<tr>\n";
    print "<td></td>\n";
    for ( my $j = 0 ; $j < scalar @$distances ; ++$j )
    {
        print "<td>" . $media_names->[$j] . "</td>\n";
    }
    print "</tr>";
    for ( my $i = 0 ; $i < scalar @$distances - 1 ; ++$i )
    {
        my $subdistance = $distances->[$i];
        print "<tr>\n";

        print "<td>" . $media_names->[$i] . "</td>\n";
        for ( my $j = 0 ; $j < $i ; ++$j )
        {
            my $color = round( 255 * ( $subdistance->[$j] - $smallest_dif ) / ( $largest_dif - $smallest_dif ) );
            printf( "<td style='background:#%02x%02x%02x;", 255 - $color, $color, 128 );

            #incase of dynamic text coloring
            print "color:#000000;";    # if $color < 80;
            print "'>"
              . round( 1000000 * ( $subdistance->[$j] - $smallest_dif ) / ( $largest_dif - $smallest_dif ) ) / 1000000
              . "</td>\n";
        }
        print "<td>same</td>\n";       #"

        for ( my $j = $i ; $j < scalar @$distances - 2 ; ++$j )
        {
            my $color = round( 255 * ( $subdistance->[ $j + 1 ] - $smallest_dif ) / ( $largest_dif - $smallest_dif ) );
            printf( "<td style='background:#%02x%02x%02x;", 255 - $color, $color, 128 );

            #incase of dynamic text coloring
            print "color:#000000;";    # if $color < 80;
            print "'>"
              . round( 1000000 * ( $subdistance->[ $j + 1 ] - $smallest_dif ) / ( $largest_dif - $smallest_dif ) ) / 1000000
              . "</td>\n";
        }

        print "</tr>\n";
    }
    print "</table>\n";
}

# generate and stash the medium, media_tag_counts, and chart_url template
# for the given num
sub build_media_data
{
    my ( $self, $c, $num ) = @_;

    my $media_id = $media_ids[$num];    #$c->request->param('media_id_' . $num);
    print STDERR $media_id . " " . $num . " db index and array index\n";
    if ( !$media_id )
    {
        return;
    }

    my $filename = "media_" . $media_id . "_size_" . $SAMPLESIZE;
    print STDERR $filename;

    my $array = [];

    if ( -e $filename )
    {

        #file exists, read it
        open FILE, "<", $filename or die $!;
        my @lines = <FILE>;
        print STDERR "file $filename was " . scalar @lines . " lines long\n";

        for ( my $j = 0 ; $j < scalar @lines ; ++$j )
        {
            $array->[$j] = $lines[$j];
        }

    }
    else
    {
        open FILE, ">", $filename or die $!;

        my $medium = $c->dbis->find_by_id( 'media', $media_id );

        if ( !$medium )
        {
            die("Unable to find medium $media_id");
        }

        # this should be done using $medium->query probably
        my ($num_of_stories) = $c->dbis->query( "select count(*) from stories where media_id=?;", $media_id )->flat;

        my $increment;    #change to some parameter later
        my $i = 0;

        while ( $i < $num_of_stories / $SAMPLESIZE )
        {
            ++$i;
            $increment = $i;
        }

        $increment = $i;

        print STDERR $increment . " = increment\n";
        my @story_indexes = $c->dbis->query( "select stories_id from stories where media_id=?;", $media_id )->arrays;
        print STDERR "size of stories array is " . scalar @story_indexes . "\n";

        for ( my $j = 0 ; ( $j * $increment ) < $num_of_stories ; ++$j )
        {
            my $story_id = @story_indexes[ $j * $increment ]->[0];
            print STDERR round( $j * 1000 / $SAMPLESIZE ) / 10 . "% of the way done: " . $story_id . " is being read\n";

            #testing printf printf STDERR ("%x",round($j*1000/$SAMPLESIZE)/10);
            my $story = $c->dbis->query( "select * from stories where stories_id =?", $story_id )->hash;
            my $text = MediaWords::DBI::Stories::get_text( $c->dbis, $story );
            $array->[$j] = $text;
            print FILE $text . "\n";
        }

        close FILE;
    }

    push( @media_texts, $array );
}

# return the top ten tags for the given medium
sub media_tag_counts : Local
{

    my ( $self, $c ) = @_;

    print STDERR "Start\n";

    @media_texts  = ();
    @word_vectors = ();
    %corpus       = ();
    @text_hashes  = ();

    print "<html><head><title>Cosine Distances</title><head><body>";
    for my $i ( 0 .. scalar @media_ids )
    {
        $self->build_media_data( $c, $i );
    }

    compare_sources( $c->dbis );

    my @all_media = $c->dbis->query("select * from media order by name asc")->hashes;

    # increase from 1000 to handle all media
    $Template::Directive::WHILE_MAX = 2000;

    $c->stash->{all_media} = [@all_media];
    $c->stash->{template}  = 'cosines/media_tag_counts.tt2';
}

=head1 AUTHOR

,,,

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
