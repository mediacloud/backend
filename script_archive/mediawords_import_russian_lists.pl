#!/usr/bin/perl

# import html from http://blogs.yandex.ru/top/ as media sources / feeds

use strict;
use warnings;

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

    my $fields = [ qw/rank name link visitors/ ];

    my $csv = Class::CSV->new( fields => $fields, );

    # add header line.
    $csv->add_line( $fields );

    for my $i ( 1 .. 30 )
    {
        my $url = "http://www.liveinternet.ru/rating/ru/media//index.html?page=$i";
        print STDERR "fetching $url \n";
        my $html = $ua->get( $url )->decoded_content;

        my $tree = HTML::TreeBuilder::XPath->new;    # empty tree
        $tree->parse_content( $html );

        my @p = $tree->findnodes( '//center/form/center/table/tr/td/table/tr' );

        foreach my $p ( @p )
        {

            #say "Here's the node dumped \n";

            my @children = $p->content_list();

            unless ( scalar( @children ) == 4 )
            {

                #say "skipping wrong count";
                #say $p->dump;
                next;
            }

            unless ( all { $_->tag eq 'td' } @children )
            {

                #say "skipping ";
                #say $p->dump;
                next;
            }

            my $rank     = $children[ 0 ]->as_text;
            my $name     = $children[ 1 ]->as_text;
            my $visitors = $children[ 2 ]->as_text;

            $rank =~ s/.*? ?(\d+)\..*/\1/;

            $visitors =~ s/\D//g;

            my @a_elements = $children[ 1 ]->find( 'a' );

            die unless scalar( @a_elements ) == 1;

            my $a_element = $a_elements[ 0 ];
            my $link      = $a_element->attr( 'href' );

            #say "$rank : $name : $link : $visitors";

            $csv->add_line( { rank => $rank, name => $name, link => $link, visitors => $visitors } );
        }

        # Now that we're done with it, we must destroy it.
        $tree = $tree->delete;
    }

    $csv->print();
}

sub _create_class_csv_from_field_list
{
    ( my $fields ) = @_;

    my $csv = Class::CSV->new( fields => $fields, );

    # add header line.
    $csv->add_line( $fields );

    return $csv;
}

sub _fetch_url_as_html_tree
{
    ( my $url ) = @_;

    print STDERR "fetching $url \n";

    my $ua   = LWP::UserAgent->new;
    my $html = $ua->get( $url )->decoded_content;

    my $tree = HTML::TreeBuilder::XPath->new;    # empty tree
    $tree->parse_content( $html );

    return $tree;
}

sub get_top100_rambler_rankings
{
    my $csv = _create_class_csv_from_field_list( [ qw/ rank name link unique_visitors page_views / ] );

    my $foo;

    for my $i ( 1 .. 35 )
    {
        my $url = "http://top100.rambler.ru/navi/?theme=440&page=$i&view=full";

        my $tree = _fetch_url_as_html_tree( $url );

        my @p = $tree->findnodes( "//table[\@id='stat-top100']/tr" );

        foreach my $p ( @p )
        {

            #say STDERR "Here's the node dumped";

            my @children = $p->content_list();

            #say $p->dump;

            unless ( scalar( @children ) == 3 )
            {
                say "skipping wrong count";
                say $p->dump;
                next;
            }

            unless ( all { $_->tag eq 'td' } @children )
            {
                say "skipping ";
                say $p->dump;
                next;
            }

            my $rank     = $children[ 0 ]->as_text;
            my $visitors = $children[ 2 ]->as_text;

            $rank =~ s/.*? ?(\d+)\..*/\1/;

            #say "dumping 2dn child";
            #$children[1]->dump;

            my @a_elements = $children[ 1 ]->look_down( "_tag", "a", "class", "rt" );

            die unless scalar( @a_elements ) == 1;

            my $a_element = $a_elements[ 0 ];

            #say $a_element->dump;

            #say "Passes test continuing";

            my $link = $a_element->attr( 'href' );

            my $name = $a_element->as_text;

            #say "Link  $link";
            #say "Link_text  $name";

            my @div_class_links_list = $children[ 1 ]->look_down( "_tag", "div", "class", "links" );

            #say "divclass links element count:";

            #say  scalar( @div_class_links_list ) . "elements";

            my $div_class_links = shift @div_class_links_list;

            #say $div_class_links->dump;

            die unless $div_class_links->content_list == 2;

            my $text_child = ( $div_class_links->content_list )[ 1 ];

            die unless scalar( $text_child );

            my $rankings = $text_child;

            $rankings =~ s/ — Индекс популярности: //;

            my ( $rank1, $rank2 ) = split /\s+/, $rankings;

#NOTE: Assuming the 2 ranks are “number of unique visitors for specific period of time”; “number of page views for specific time”.

            $csv->add_line(
                { rank => $rank, name => $name, link => $link, unique_visitors => $rank1, page_views => $rank2 } );
        }

        # Now that we're done with it, we must destroy it.
        $tree = $tree->delete;
    }

    $csv->print();
}

sub get_top_mail_ru_rankings
{
    my $ua = LWP::UserAgent->new;

    my $csv = _create_class_csv_from_field_list(
        [ qw/ rank name link stat1_посетители stat2_хосты stat3_визиты stat4 / ] );

    for my $i ( 1 .. 33 )
    {
        my $url = "http://top.mail.ru/Rating/MassMedia/month/Visitors/$i.html";

        my $tree = _fetch_url_as_html_tree( $url );

        my @p = $tree->findnodes( "//table[\@class='Rating bbGreen']/tr" );

        shift @p;

        foreach my $p ( @p )
        {

            #say "Here's the node dumped";
            #say $p->dump;

            my @children = $p->content_list();

            unless ( scalar( @children ) == 7 )
            {
                if ( scalar( @children ) == 1 )
                {
                    my $child = $children[ 0 ];

                    if ( $child->tag eq 'td' && $child->attr( 'class' ) eq 'new_direct' )
                    {

                        #say "skipping but not dying";
                        next;
                    }
                }
                say "skipping wrong count:" . scalar( @children );
                say $p->dump;
                die;
                next;
            }

            unless ( all { $_->tag eq 'td' } @children )
            {
                say "skipping ";
                say $p->dump;
                next;
            }

            my $rank = $children[ 0 ]->as_text;
            $rank =~ s/.*? ?(\d+)\..*/\1/;

            #say "rank:$rank";

            my $stat1 = $children[ 2 ]->as_text;
            my $stat2 = $children[ 3 ]->as_text;
            my $stat3 = $children[ 4 ]->as_text;
            my $stat4 = $children[ 5 ]->as_text;

            #say "stat1:$stat1,stat2:$stat2,stat3:$stat3,stat4:$stat4";

            #say "dumping 2dn child";
            #$children[1]->dump;

            my @a_elements = $children[ 1 ]->look_down( "_tag", "a", "name", $rank );

            die unless scalar( @a_elements ) == 1;

            my $a_element = $a_elements[ 0 ];

            #say $a_element->dump;

            #say "Passes test continuing";

            my $link = $a_element->attr( 'href' );
            $link =~ s/.*&url=//;

            my $name = $a_element->as_text;

            #say "Link '$link'";
            #say "Link_text  '$name'";

            $csv->add_line(
                { rank => $rank, name => $name, link => $link, stat1_посетители => $stat1, stat2_хосты => $stat2, stat3_визиты => $stat3, stat4 => $stat4 } );
        }

        # Now that we're done with it, we must destroy it.
        $tree = $tree->delete;
    }

    $csv->print();
}

sub get_mediaguide_ru_rankings_circulation
{
    my $sort = 1;

    _get_mediaguide_ru_rankings_impl($sort);
}

sub get_mediaguide_ru_rankings_rating
{
    my $sort = 2;

    _get_mediaguide_ru_rankings_impl($sort);
}

sub _get_mediaguide_ru_rankings_impl
{
    (my $sort) = @_;

    my $ua = LWP::UserAgent->new;

    my $csv = _create_class_csv_from_field_list(
        [ qw/ name media_type Город Тема Тираж Рейтинг / ] );

    for my $i ( 1 .. 50 )
    {
        my $url = "http://www.mediaguide.ru/?p=list&page=$i&sort=$sort";

        my $tree = _fetch_url_as_html_tree( $url );

        #my @p = $tree->findnodes( "/html/body/table/tbody/tr[3]/td[2]/table/tbody/tr/td/index/div/div/" );

	my @p = $tree->findnodes( "//html/body/table/tr[3]/td[2]/table/tr/td/div/div" );

	#say Dumper([@p]);
        my $first = shift @p;
 
	die unless $first->attr( 'style' ) eq 'float: left;' ;
	
	#say $first->dump;

	my $div_index = 0;
	while ($div_index <= $#p)
        {
	    my $div_searchResName = $p[$div_index];

            #say "Here's the searchResName node dumped";
            #say $div_searchResName->dump;

	    #say $div_searchResName->as_text;

	    my $name = $div_searchResName->as_text;;

	    die $div_searchResName->attr( 'class' ) unless $div_searchResName->attr( 'class' ) =~ 'searchResName\d?';

	    $div_index++;

	    my $div_searchResBody = $p[$div_index];

            #say "Here's the searchResBody node dumped";
            #say $div_searchResBody->dump;

	    die $div_searchResBody->attr( 'class' ) unless $div_searchResBody->attr( 'class' ) eq 'searchResBody';

	    my $body_text = $div_searchResBody->as_text;

	    $body_text =~ s/Тема: (.*)Тираж: /Тема: $1. Тираж: /;
	    $body_text =~ s/Тираж: \./Тираж:  \./;
	    $body_text =~ s/серт\. НТС\./серт\.НТС\./;

	    #ay $body_text;
	    my @rankings = (split '\. ', $body_text);

	    foreach my $rank (@rankings)
	    {
	      $rank =~ s/(.+) $/$1  /;
	    }

	    my $media_type = shift @rankings;

	    my $hash ={ map { split '\: ', $_ } @rankings };

	    #say Dumper($hash);

	    $hash->{name} = $name;

	    $hash->{media_type} = $media_type;

	    $csv->add_line ($hash);

	    $div_index++;

	    next;
	  }

	#exit;

        # Now that we're done with it, we must destroy it.
        $tree = $tree->delete;
    }

    $csv->print();
}

sub main
{
    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    get_mediaguide_ru_rankings_rating();
}

main();
