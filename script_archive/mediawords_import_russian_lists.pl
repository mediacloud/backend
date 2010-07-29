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

sub main
{
    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    get_liveinternet_ru_rankings
}

main();

__END__

"></a><a href="http://unab0mber.livejournal.com/" title="Abandon all hope ye who enter here">
