#!/usr/bin/perl
use Algorithm::SVM;
use Algorithm::SVM::DataSet;
use Encode;
use HTML::TreeBuilder;
use String::Tokenizer;
#my $root = HTML::TreeBuilder->new;
#$root->parse_file('normalize.html') || die $!;

	my %wordList=();
	my $innerTextTotal = 0;
	my $innerHtmlTotal = 0;
	my $paragraphTotal = 0;
	my $innerTextStrTotal ="";
	my $stopWordTotal = 0;
	
	my $fileName = shift;
	my $svm = new Algorithm::SVM(Type   => 'C-SVC',
                              Kernel => 'radial',
                              Gamma  => 64,
                              C      => 8);
	$svm->load('news-ku.model');
  
	loadStopWords( );
	computeAllTotalValues($fileName);
	#print $innerTextTotal."\n";
	#print $innerHtmlTotal."\n";
	#print $paragraphTotal."\n";
	#print  "NbStopWords: ".$stopWordTotal."\n";

	binmode STDOUT, ":utf8";
	traverse($fileName);
	@hashkeys = keys(%wordList);
	print scalar(@hashkeys);

	


sub loadStopWords {
	open(STOPWORDLIST,"stopWords.txt") ;
   my $cnt = 0;
   while ($record = <STOPWORDLIST>) {
			 my $word = $record;
			 $word =~s/\s+$//;
          $wordList{$word} = $word;
			 #print "Word: ".$wordList{$word};
        	 my $length = length($word);
        	 #print " Length : $length"."\n";
          $cnt = $cnt +1;
  	}
	close(STOPWORDLIST);
}


sub traverse{

   my $root = HTML::TreeBuilder->new;
   $root->parse_file($_[0]);
	
	traverseRecurse($root);
}

sub isStructuralTag {
	my $tagName = $_[0];
	if ($tagName eq "ul" || $tagName eq "li" || $tagName eq "div" || $tagName eq "table" || $tagName eq "tr" || $tagName eq "td" || $tagName eq "span") {
   	return 1;
	} else {
		return 0;
	}
}

sub calculateLinkLength{
	my $currentNode = $_[0];
	my $textLinkLength = 0;
	my @links = $currentNode->find_by_tag_name('a');

	foreach my $link (@links) {
		$textLinkLength = $textLinkLength + length($link->as_text( )) ;
	}	

	return $textLinkLength;
}

sub getFeatureVector{
	my $featureVector = "";
	my $currentNode = $_[0];

	# INNER TEXT
	my $innerTextLength = length($currentNode->as_text( ));
	my $innerTextLengthNormalized = length($currentNode->as_text( ))/$innerTextTotal;
	#print $innerTextLengthNormalized;	
	# INNER HTML
	my $innerHtmlLength = length($currentNode->as_HTML( ));
	my $innerHtmlLengthNormalized = length($currentNode->as_HTML( ))/$innerHtmlTotal;
	#print $innerHtmlLengthNormalized;
	# PARAGRAPH NUM
	my @parArr =  $currentNode->find_by_tag_name('p');
	my $parNumNormalized = scalar(@parArr) /$paragraphTotal ;
	#print $parNumNormalized;

	# STOP WORD RATIO
	my $currentNodeText = $currentNode->as_text( );
	
	#Tokenize
	my $tokenizer = String::Tokenizer->new($currentNodeText,' ',String::Tokenizer->IGNORE_WHITESPACE);

	my $iterator = $tokenizer->iterator();
	my $stopWordNum = 0;
	while ($iterator->hasNextToken()) {
        my $token = $iterator->nextToken();
        $token =~s/\s+$//;
		  if (exists  $wordList{$token} ) {
				$stopWordNum = $stopWordNum + 1;	
		  }
        #print "Token: $token \n";
	}

	$linkLength = calculateLinkLength($currentNode);
	my $stopWordRatio = 0;
	if (length($currentNode->as_text( )) > 0) {
		$nbStopWord = $nbStopWord * (($innerTextLength-$linkLength) /$innerTextLength);
	}
	my $stopWordRatio = $stopWordNum / $stopWordTotal;
	if ($stopWordRatio > 0.75) {
	 #  print "Stopword Ratio : ".$stopWordRatio;
#		print $currentNode->as_text( );
	}	
	# LINK TEXT RATIO
	my $linkTextRatio = 0;
	if ($innerTextLength > 0) {
		$linkTextRatio = $linkLength/$innerTextLength;
	}
	#print "Link to Text Ratio : ".$linkTextRatio;
	
	$featureVector = $featureVector.$innerTextLengthNormalized.",".$innerHtmlLengthNormalized.",".$parNumNormalized.",".$stopWordRatio.",".$linkTextRatio;
	my @featureVector = ($innerTextLengthNormalized,$innerHtmlLengthNormalized,$parNumNormalized,$stopWordRatio,$linkTextRatio);
#	print $featureVector."\n";
}
sub traverseRecurse {
  my $element = $_[0];
  #return if $element->tag eq 'table';   # prune!
  foreach my $child ($element->content_list) {
        if (ref $child ) {#&& isStructuralTag($child->tag( )) == 1) {  # it's an element
        # get feature vector
        #  classify
        #  if content then return
			if (isStructuralTag($child->tag( )) == 1) {
        		my @featureVector = getFeatureVector($child);
				#print "@featureVector";
				my $ds = new Algorithm::SVM::DataSet(Label => 1);
				my $cnt = 0;
				foreach my $feature (@featureVector) {
					#$ds->attribute($cnt,$feature);
					$cnt = $cnt +1;
				}

				$ds->attribute($_, $featureVector[$_ - 1]) for(1..scalar(@featureVector));
				my $result = $svm->predict($ds);
#				print $result;
				if ($result == 1) { # MAIN CONTENT
					#print "@featureVector";
					#if (length($child->as_text( )) > 0) {
						print " Text: ".$child->as_text( ); 
					#}
				}
				#print $result;
				#if ($result == 1) {
			#		$text =  $child->as_text( );
			#		print $text;
			#	}
        	 	print "\n";	
			}
         traverseRecurse($child);  # recurse!
        } else {           
				# it's a text node!
            #$text .= $child;
        }
   }
   return;
}
                                      
sub computeAllTotalValues {
	my $root = HTML::TreeBuilder->new;
	$root->parse_file($_[0]);
	my @body = $root->find_by_tag_name('body');
	$innerTextTotal = length($body[0]->as_text( ));
	$innerHtmlTotal = length($body[0]->as_HTML( ));
	my @parArr = $root->find_by_tag_name('p');
	$paragraphTotal = scalar(@parArr);
	$innerTextStrTotal = $body[0]->as_text( );


	my $tokenizer = String::Tokenizer->new($innerTextStrTotal,' ',String::Tokenizer->IGNORE_WHITESPACE);

	my $iterator = $tokenizer->iterator();

	while ($iterator->hasNextToken()) {
        my $token = $iterator->nextToken();
		  $token =~s/\s+$//;
		 if (exists $wordList{$token} ){
			$stopWordTotal = $stopWordTotal + 1;
		 }else {
		 }
#        print "Token: $token ";
#		  print " length:".length($token)."\n";
	}

	$root->delete;
}
