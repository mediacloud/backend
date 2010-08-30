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
use Readonly;

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

#<<<  stop perltidy from complaining about unicode
            $csv->add_line(
                { rank => $rank, name => $name, link => $link, stat1_посетители => $stat1, stat2_хосты => $stat2, stat3_визиты => $stat3, stat4 => $stat4 } );
#>>>
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


sub get_webomer_ru_rankings
{
    my $ua = LWP::UserAgent->new;

    Readonly my $csv_fields => [ 'url', 'name', 'охват', 'демография', 'ядро', 'доля поискового трафика' ];

    my $csv = _create_class_csv_from_field_list( $csv_fields );

    for my $i ( 1 .. 200 )
    {
        my $url = "http://webomer.ru/cgi-bin/wr.fcgi?action=stat&period=month&sitet=2l&country=1&page=$i&position=";

	my $ua   = LWP::UserAgent->new;

	print STDERR "fetching $url \n";

	my $html = $ua->get( $url )->decoded_content;

	my @lines = split /\n/, $html;

	my @put_one_site_stat_lines = grep { /^put_one_site_stat/ } @lines;

	foreach my $put_one_site_stat_line (@put_one_site_stat_lines )
	{
	   $put_one_site_stat_line =~ s/put_one_site_stat\((.*)\);/$1/;
	}

	foreach my $put_one_site_stat_line (@put_one_site_stat_lines )
	{
	    #say $put_one_site_stat_line;

	    my @fields = split /,/, $put_one_site_stat_line;
	    
	    die unless scalar(@fields) == 11;

	    foreach my $field (@fields)
	    {
	      $field =~ s/^'(.*)'$/$1/;
	    }

	    #say join ',', @fields;

	    Readonly my %CORRESPONDING => (
					   'id' => 0,
					   'url'=> 1,
					   'name' => 2,
					   'охват' => 3,
					   'blank1' => 4,
					   'blank2' => 5,
					   'демография' => 6,
					   'демография_2' => 7,
					   'ядро' => 8,
					   'доля поискового трафика' => 9,
					   'change' => 10,
					  );
	    my %site_data;
	
	    @site_data{ keys %CORRESPONDING } = @fields [ values  %CORRESPONDING ];

	    if (! $site_data{ name } )
	    {
		 $site_data { name } = $site_data { url };
	    }

	    die if ( $site_data {blank_1 }  or  $site_data {blank_2 } );

	    #say Dumper (\%site_data);
	    #say Dumper([@put_one_site_stat_lines]);

	    my %csv_line;
	    @csv_line{@ {$csv_fields } } = @site_data{ @ {$csv_fields } };

	    $csv->add_line(\%csv_line);
	  }
    }

    $csv->print();
}

sub get_blogs_yandex_ru_rankings_month
{
  return _get_blogs_yandex_ru_rankings_impl('month');
}

sub get_blogs_yandex_ru_rankings_week
{
  return _get_blogs_yandex_ru_rankings_impl('week');
}

sub get_blogs_yandex_ru_rankings_6months
{
  return _get_blogs_yandex_ru_rankings_impl('6months');
}

sub _get_blogs_yandex_ru_rankings_impl
{

    (my $period) = @_;

    my $ua = LWP::UserAgent->new;

    my $csv = _create_class_csv_from_field_list(
        [ qw/ rank name мнений / ] );

    for my $i ( 1 .. 50 )
    {
        my $url = "http://blogs.yandex.ru/rating/smi/?period=$period&page=$i";

        my $tree = _fetch_url_as_html_tree( $url );

	my @p = $tree->findnodes( "//tr[\@class='film']" );

	#say Dumper([@p]);

	foreach my $p (@p)
	{
	  my @children = $p->content_list();
	
	  die unless scalar(@children) == 3;

	  my $rank = $children[0]->as_text;
	  my $name = $children[1]->as_text;
	  my $stat = $children[2]->as_text;

	  #for some reason the first site has мнений in the td so just filter it out
	  $stat =~ s/мнений//;

	  trim($name);

	  $csv->add_line ( { rank => $rank, name => $name, мнений => $stat } );
	}

        # Now that we're done with it, we must destroy it.
        $tree = $tree->delete;
    }

    $csv->print();
}

sub _look_for_single_element
{
   (my $element, my @arguments)  = @_;

   my @result_elements = $element->look_down(@arguments);

   die 'expect 1 element got ' . scalar(@result_elements) . ' for ' . join( ',', @arguments) unless scalar(@result_elements) == 1;

   my $ret = $result_elements[0];

   return $ret;
}

sub get_blogs_yaca_yandex_ru_rankings
{

    (my $period) = @_;

    my $ua = LWP::UserAgent->new;

    my $csv = _create_class_csv_from_field_list(
        [ qw/ rank name link Цитируемость region address phone info / ] );

    #rank is very difficult to scrap so just fake it with a counter
    my  $rank = 1;

    for my $i ( 0 .. 100 )
    {
        my $url = "http://yaca.yandex.ru/yca/ungrp/cat/Media/$i.html";

        my $tree = _fetch_url_as_html_tree( $url );

	my @p = $tree->findnodes( '//table[@class="l-page"]/tr/td[@class="l-page__content"]/ol[@class="b-result b-result_numerated b-result_imaged"]/li[@class="b-result__item"]' );

	
	#say Dumper([@p]);

	#exit;

	foreach my $p (@p)
	{   
	  
	  # say '---------------------------';
	  # say '---------------------------';
	  # say '---------------------------';
	  # say '---------------------------';
	  # say '---------------------------';
	  # say '---------------------------';
	  #say $p->as_text;
	  #say $p->dump;

	  my @children = $p->content_list();

	  die unless scalar(@children) == 2;

	  my $h3 = $children[0];

	  die unless ($h3->tag eq 'h3')  && ($h3->attr('class') eq 'b-result__head');

	  my $b_result__name = ($h3->content_list())[0];

	  die unless $b_result__name->tag eq 'a';
	  die unless $b_result__name->attr('class') eq 'b-result__name';

	  my $name = $b_result__name->as_text;

	  trim($name);

	  my $link = $b_result__name->attr('href');

	  # say "'$name' '$link'";

	  # #say $children[1]->as_text;
	  # #say '----------------';
	  # say $children[1]->dump;

	  my @result_infos = $children[1]->look_down( "_tag", "p", "class", 'b-result__info' );

	  die unless (scalar(@result_infos) == 2) || (scalar(@result_infos) == 1 );

	  my $info = $result_infos[0]->as_text;

	  my $phone;
	  my $address;

	  if (scalar(@result_infos) == 2)
	  {
	    my @result_children = $result_infos[1]->content_list;

	     die scalar(@result_children) ."\n" . $result_infos[1]->dump 
	       unless scalar(@result_children) >= 1;
 
	     die unless  scalar(@result_children) <= 3;


	    #say $result_infos[1]->dump ;

	    if (scalar(@result_children) == 3)
	    { 
	      die if (ref ($result_children[0]));

	      $phone   = $result_children[0];
	      shift @result_children;
	    }

	    die Dumper $result_children[0] unless (ref ($result_children[0]));

	    $address = $result_children[0]->as_text;

	     # say "phone: $phone";
	     # say "address: $address";
	  }


	  #say $info;
	  #say $result_infos[1]->as_text;
	  # my @detailed_info =  $result_infos[1]->content_list;

	  # foreach my $el (@detailed_info)
	  # {
	  #    if (ref $el)
	  #      {
	  # 	 say "as_text: " . $el->as_text;
	  #      }
	  #    else
	  #      {
	  # 	 say "Scalar '$el'";
	  #      }
	  # }

	  # say $children[1]->dump;
	  my $result_url_el =  _look_for_single_element($children[1], "_tag", "span", "class", 'b-result__url' );
	  my $url = $result_url_el->as_text;

	  die "'$url' <> '$link'"unless ("http://$url/" eq $link) or  ("http://$url" eq $link);

	  my $result_quote_el = _look_for_single_element($children[1], "_tag", "span", "class", 'b-result__quote' );

	  my $result_quote = $result_quote_el->as_text;

	  # say "Result_quote: '$result_quote'";

	  my $result_region = '';

	  eval{
	  my $result_region_el = _look_for_single_element($children[1], "_tag", "a", "class", 'b-result__region' );

	  $result_region  = $result_region_el->as_text;

	  # say "result_region: '$result_region'";
		};

	  die unless $result_quote =~ /Цитируемость\:\s/;
	  my $Цитируемость= $result_quote;

	  $Цитируемость =~ s/Цитируемость\:\s//;

	  # say $Цитируемость;
	  #rank name Цитируемость region address phone info 
	  $csv->add_line ( { rank => $rank, link => $link, name => $name,  Цитируемость => $Цитируемость, region => $result_region, address => $address, phone => $phone, info => $info } );
	  $rank++;
	}

        # Now that we're done with it, we must destroy it.
        $tree = $tree->delete;
    }

    $csv->print();
}

sub get_news_yandex_ru_smi_rankings
{

    (my $period) = @_;

    my $ua = LWP::UserAgent->new;

    my $csv = _create_class_csv_from_field_list(
        [ qw/ name messages articles interviews phone head_title head_person  address url media_url_text / ] );

    for my $i ( 0 .. 0 )
    {
        my $url = "http://news.yandex.ru/smi/newstube";

        my $tree = _fetch_url_as_html_tree( $url );

	my @p = $tree->findnodes( '//dl[@class="news"]' );

	die unless scalar(@p) == 1;

	#say $p[0]->dump;

	my $dt = $p[0];

	my @children = $dt->content_list();

	die unless scalar(@children) == 3;
	
	my $dt_head = $children[0];

	die unless $dt_head->tag eq 'dt';

	die unless $dt_head->attr('class') eq 'head';

	#say "Dumping dt";
	
	#say $dt_head->dump;

	my $dt_span = ($dt_head->content_list())[2];

	die unless $dt_span->tag eq 'span';

	my $media_name = $dt_span->as_text;

	#say "$media_name";

	#exit;

	#say Dumper([@p]);

	my $dd_info = $children[2];

	die unless $dd_info->tag eq 'dd';

	die unless $dd_info->attr('class') eq 'info';

	#say $dd_info->dump;

	my @li_s = $dd_info->look_down( "_tag", "li");

	die unless scalar(@li_s) == 4;

	my $a_url = ($li_s[0]->content_list())[0];

	die unless $a_url->tag eq 'a';
	die unless $a_url->attr('class') eq 'url';

	my $media_url = $a_url->attr('href');
	my $media_url_text = $a_url->as_text;

	#say "media_url:'$media_url' media_url_text:'$media_url_text'";

	my $li_head_person = $li_s[1];

	my $li_head_person_text = $li_head_person->as_text;

	say $li_head_person_text;

	die unless $li_head_person_text =~ /.*: .*/;

	$li_head_person_text =~ m/(.*): (.*)/;

	my $head_title = $1;
	my $head_person = $2;

	my $li_address = $li_s[2];

	my $li_address_text = $li_address->as_text;

	die unless $li_address_text =~ /Адрес: .*/;

	my $address = 	$li_address_text;
	$address =~ s/Адрес: (.*)/$1/;

	my $li_phone = $li_s[3];
	my $li_phone_text = $li_phone->as_text;

	die unless $li_phone_text =~ /Телефон: .*/;

	my $phone = 	$li_phone_text;
	$phone =~ s/Телефон: (.*)/$1/;
	#say "phone:$phone,editor:$editor_name,address:$address";
	#say "media_url:'$media_url' media_url_text:'$media_url_text'";
	#exit;

	my @dl_totals = $tree->findnodes( '//dl[@class="total"]' );

	die unless scalar(@dl_totals) == 1;

	#say $dl_totals[0]->dump;

	my $dl_totals_text =  $dl_totals[0]->as_text;
	die  $dl_totals_text unless $dl_totals_text =~ /Последние обновления:/;

	die  $dl_totals_text unless $dl_totals_text =~ /Последние обновления:сообщений — (\d+) \(\+\d+\), статей — (\d+) \(\+\d+\), интервью — (\d+)/;

	$dl_totals_text =~ /Последние обновления:сообщений — (\d+) \(\+\d+\), статей — (\d+) \(\+\d+\), интервью — (\d+)/;

	#translations: сообщений messages, статей articles, интервью interviews
	my $messages   = $1;
	my $articles   = $2;
	my $interviews = $3;

	$csv->add_line( {name=>$media_name, messages=>$messages, articles=>$articles,interviews=>$interviews, phone=>$phone, head_title => $head_title, head_person=>$head_person,address=>$address, url=>$media_url, media_url_text=>$media_url_text });

        # Now that we're done with it, we must destroy it.
        $tree = $tree->delete;
    }

    $csv->print();
}

sub main
{
    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    get_news_yandex_ru_smi_rankings();
    #get_blogs_yandex_ru_rankings_6months();
    #get_blogs_yandex_ru_rankings_month();
    #get_blogs_yandex_ru_rankings_week();
}

main();
