#!/usr/bin/perl
#


open(STOPWORDLIST,"stopWords.txt") ;

my %wordList = ();
my $cnt = 0;
while ($record = <STOPWORDLIST>) {
#	my $word = $record;
#	$word = trim($word);
	my $word = $record;
	$word =~s/\s+$//;
	$wordList{$word} = $word;
	$cnt = $cnt +1;	
	
}
#
#
for my $key (keys(%wordList)) {
	print "Word: ".$wordList{$key};
	my $length = length($key);
	print " Length : $length"."\n";
}
my $sample = "the";

    print "Value EXISTS, but may be undefined.\n" if exists  $wordList{$sample};
    print "Value is DEFINED, but may be false.\n" if defined $wordList{ $sample };
    print "Value is TRUE at hash key $key.\n"     if         $wordList{ $sample };

close(STOPWORDLIST);
