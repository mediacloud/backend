#!/usr/bin/perl
use HTML::TreeBuilder;
use String::Tokenizer;


#GLOBAL VARIABLE

my $innerTextTotal = 0;
my $innerHtmlTotal = 0;




my $root = HTML::TreeBuilder->new;
$root->parse_file('normalize.html') || die $!;






my @par = $root->find_by_tag_name('p');
my $parNum = scalar(@par);
print "Number of paragraph : $parNum \n";

my @body = $root->find_by_tag_name('body');
my @target = $root->find_by_tag_name('table');
#print $body[0]->as_text( ) ;
#print $body[0]->as_HTML( );

my @links = $target[0]->find_by_tag_name('a');

my $str ="";
foreach my $node (@links) {
	$str = $str. $node->as_text( );
}

print "$str";

my $allText = $body[0]->as_text( );

my $tokenizer = String::Tokenizer->new($allText,' ',String::Tokenizer->IGNORE_WHITESPACE);

my $iterator = $tokenizer->iterator();

while ($iterator->hasNextToken()) {
	my $token = $iterator->nextToken();
	print "Token: $token \n";
}
$root->delete
