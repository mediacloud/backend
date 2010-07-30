#!/usr/bin/perl

# import html from http://blogs.yandex.ru/top/ as media sources / feeds

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Encode;
use HTTP::Request;
use LWP::UserAgent;
use Text::Trim;
use HTML::TreeBuilder;
use HTML::TreeBuilder::XPath;

use DBIx::Simple::MediaWords;
use Feed::Scrape;
use MediaWords::DB;
use Data::Dumper;
use Perl6::Say;
use Class::CSV;
use utf8;
use List::MoreUtils qw(any all none notall true false firstidx first_index 
                           lastidx last_index insert_after insert_after_string 
                           apply after after_incl before before_incl indexes 
                           firstval first_value lastval last_value each_array
                           each_arrayref pairwise natatime mesh zip uniq minmax);
use constant COLLECTION_TAG => 'russian_yandex_20100316';

sub get_liveinternet_ru_rankings
{
   my $ua = LWP::UserAgent->new;

    my $fields = [qw/rank name link visitors/];

    my $csv = Class::CSV->new(
    fields         => $fields,
			     );

    # add header line.
    $csv->add_line($fields);


    for my $i ( 1 .. 30 )
    {
        my $url = "http://www.liveinternet.ru/rating/ru/media//index.html?page=$i";
        print STDERR "fetching $url \n";
        my $html = $ua->get( $url )->decoded_content;

	my $tree = HTML::TreeBuilder::XPath->new; # empty tree
	$tree->parse_content($html);

	my @p= $tree->findnodes( '//center/form/center/table/tr/td/table/tr');

	foreach my $p (@p)
	  {
	    #say "Here's the node dumped \n";
	    
	    my @children = $p->content_list();
	    
	    unless( scalar(@children) == 4)
	      {
		#say "skipping wrong count";
		#say $p->dump;
		next;
	      }

	    unless (all {$_->tag eq 'td' } @children)
	      {
		#say "skipping ";
		#say $p->dump;
		next;
	      }

	    my $rank     = $children[0]->as_text;
	    my $name     = $children[1]->as_text;
	    my $visitors = $children[2]->as_text;

	    $rank  =~ s/.*? ?(\d+)\..*/\1/;

	    $visitors =~ s/\D//g;

	    my @a_elements = $children[1]->find('a');

	    die unless scalar(@a_elements) == 1;

	    my $a_element = $a_elements[0];
	    my $link = $a_element->attr('href');

	    #say "$rank : $name : $link : $visitors";
	    
	    $csv->add_line( { rank => $rank, name => $name, link => $link, visitors => $visitors } );
	  }

	# Now that we're done with it, we must destroy it.
	$tree = $tree->delete;
    }

    $csv->print();
}

sub get_top100_rambler_rankings
{
   my $ua = LWP::UserAgent->new;

    my $fields = [qw/ rank name link unique_visitors page_views /];

    my $csv = Class::CSV->new(
    fields         => $fields,
			     );

    # add header line.
    $csv->add_line($fields);

    my $foo;

    for my $i ( 1 .. 35 )
    {
        my $url = "http://top100.rambler.ru/navi/?theme=440&page=$i&view=full";
        print STDERR "fetching $url \n";
        my $html = $ua->get( $url )->decoded_content;

	my $tree = HTML::TreeBuilder::XPath->new; # empty tree
	$tree->parse_content($html);

	my @p= $tree->findnodes( "//table[\@id='stat-top100']/tr");

	foreach my $p (@p)
	  {
	    #say STDERR "Here's the node dumped";
	    
	    my @children = $p->content_list();

	    #say $p->dump;

	    unless( scalar(@children) == 3)
	      {
		say "skipping wrong count";
		say $p->dump;
		next;
	      }

	    unless (all {$_->tag eq 'td' } @children)
	      {
		say "skipping ";
		say $p->dump;
		next;
	      }

	    my $rank     = $children[0]->as_text;
	    my $visitors = $children[2]->as_text;

	    $rank  =~ s/.*? ?(\d+)\..*/\1/;


	    #say "dumping 2dn child";

	    #$children[1]->dump;

	    my @a_elements = $children[1]->look_down( 
						"_tag", "a",
						"class", "rt"
						) ;


	    die unless scalar(@a_elements) == 1;

	    my $a_element = $a_elements[0];

	    #say $a_element->dump;

	    #say "Passes test continuing";


	    my $link = $a_element->attr('href');

	    my $name = $a_element->as_text;

	    #say "Link  $link";
	    #say "Link_text  $name";

	    my @div_class_links_list = $children[1]->look_down( 
						"_tag", "div",
						"class", "links"
						) ;

	    #say "divclass links element count:";

	    #say  scalar( @div_class_links_list ) . "elements";

	    my $div_class_links = shift @div_class_links_list;

	    #say $div_class_links->dump;

	    die unless $div_class_links->content_list == 2;

	    my $text_child = ($div_class_links->content_list)[1];

	    die unless scalar($text_child);

	    my $rankings = $text_child;

	    $rankings =~ s/ — Индекс популярности: //;
	    
	    my ($rank1, $rank2) = split /\s+/, $rankings;

	    #NOTE: Assuming the 2 ranks are “number of unique visitors for specific period of time”; “number of page views for specific time”.

	    $csv->add_line( { rank => $rank, name => $name, link => $link, unique_visitors => $rank1, page_views => $rank2 } );
	  }

	# Now that we're done with it, we must destroy it.
	$tree = $tree->delete;
    }

    $csv->print();
}

sub main
{
    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    get_top100_rambler_rankings;
}

main();
