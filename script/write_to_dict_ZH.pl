use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}
use utf8;
use Encode;

#this is code is to add a list of words into the dictionary
sub write_to_dict
{
    my $params            = shift;
    my ( %new_word_freq ) = %$params;
    my $dict_encoding     = "utf8";
    my %word_freq         = {};
    my $FH;
    my $word;
    my $freq;
    my $line;

    #location of the dictionary
    my $dict = 'lib/MediaWords/Languages/zh_dict.txt';

    open $FH, $dict or die "Cant open file dict\n";
    while ( my $line = <$FH> )
    {
        chomp $line;
        $line = decode( "utf8", $line );
        ( $word, $freq ) = split( /\s+/, $line );
        $word_freq{ $word } = $freq;
    }
    close $FH;

    while ( ( $word, $freq ) = each( %new_word_freq ) )
    {
        if ( $freq )
        {
            $word_freq{ $word } = $new_word_freq{ $word };
        }
    }

    open $FH, ">" . $dict or die "Cant open file dict\n";
    foreach $word ( sort hashValueDescending( keys( %word_freq ) ) )
    {
        $freq = $word_freq{ $word };
        if ( $freq =~ m!\d! and $word =~ m!^(\p{Han})! )
        {
            $line = $word . "   " . $freq . "\n";
            $line = encode( "utf8", $line );
            print $FH $line;
        }
    }
    close $FH;

    sub hashValueDescending
    {
        $word_freq{ $b } <=> $word_freq{ $a };
    }
}

#this function is used to clean up the redundencies and non-Chinese entries in dictionary
sub clean_dict
{
    my $dict_encoding = "utf8";
    my %word_freq     = {};
    my $FH;
    my $word;
    my $freq;
    my $line;
    my $dict = "lib/Lingua/ZH/dict.txt";

    open $FH, $dict or die "Cant open file dict\n";
    while ( my $line = <$FH> )
    {
        chomp $line;
        $line = decode( "utf8", $line );
        ( $word, $freq ) = split( /\s+/, $line );
        $word_freq{ $word } = $freq;
    }
    close $FH;

    open $FH, ">" . $dict or die "Cant open file dict\n";
    foreach $word ( sort hashValueDescending1( keys( %word_freq ) ) )
    {
        $freq = $word_freq{ $word };
        if ( $freq =~ m!\d! and $word =~ m!^(\p{Han})! )
        {
            $line = $word . "   " . $freq . "\n";
            $line = encode( "utf8", $line );
            print $FH $line;
        }
    }
    close $FH;

    sub hashValueDescending1
    {
        $word_freq{ $b } <=> $word_freq{ $a };
    }
}

#this method is to add a list of words from existing file
sub add_word_list
{
    my $list_file = shift;
    my $FH;
    open $FH, $list_file or die "cannot open file";
    my @list = ();
    while ( my $line = <$FH> )
    {
        chomp $line;
        $line = decode( "utf8", $line );
        push @list, $line;
    }
    my %word_freq = {};
    foreach my $word ( @list )
    {
        $word_freq{ $word } = 1;
    }
    write_to_dict( \%word_freq );
}

sub main1
{
    my %input = {};
    $input{ "小泽锐仁" } = 1;
    write_to_dict( \%input );
}

sub main
{
    clean_dict;
}
main;
