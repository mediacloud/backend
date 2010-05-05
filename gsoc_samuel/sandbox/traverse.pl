#!/usr/bin/perl
use HTML::TreeBuilder;

my $root = HTML::TreeBuilder->new;
$root->parse_file('normalize.html') || die $!;

#my $text;
#sub text_no_tables {
  #if ref $_[0] && $_[0]->tag eq 'table';
#   if (ref $_[0] && $_[0]->tag eq 'a') {
 # 	print $_[0]->as_HTML();
  	#print 
	#print "\n" ;
	
 # $text .= $_[0] unless ref $_[0];  # only append text nodex
 # return 1;                         # all is copacetic
#}

#my $counter = 1;

#for ($count=1; $count < 10000; $count++) {
#	print $count;
#	print "\n";
#	$root->traverse([\&text_no_tables]);
#}
#print $text;
#
#

my $text = '';
sub scan_for_non_table_text {
  my $element = $_[0];
  #return if $element->tag eq 'table';   # prune!
  foreach my $child ($element->content_list) {
    if (ref $child) {  # it's an element
	# get feature vector
	#  classify
	#  if content then return
      print $child->tag( )."\n";
      scan_for_non_table_text($child);  # recurse!
    } else {           # it's a text node!
      #$text .= $child;
    }
  }
  return;
}
scan_for_non_table_text($root);
