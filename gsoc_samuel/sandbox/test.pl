#!/usr/bin/perl
use HTML::TreeBuilder;


my $root = HTML::TreeBuilder->new;
$root->parse_file('hello.html') || die $!;



my $header = $root->look_down('_tag', 'head');
my $body = $root->look_down('_tag', 'body');





$root->dump;
my $scriptStr = "";
open(IN,"<script.js");
my @lines = <IN> ;
foreach my $str (@lines) {
	$scriptStr = $scriptStr.$str;
} 
close IN;
print $scriptStr;

my $script = HTML::Element->new('script');
$script->push_content($scriptStr);
$header->push_content($script);

$body->attr('onMouseOver','block(event)');
$body->attr('onMouseOut','unblock(event)');
$body->attr('onMouseDown','retrieveElementInfo(event)');


#Flush it out
open(OUT,">after.html");
print OUT $root->as_HTML(undef, "  ");
close OUT;
$root->delete;

