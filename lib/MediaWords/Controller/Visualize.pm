package MediaWords::Controller::Visualize;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use Encode;
use strict;
use warnings;
use base 'Catalyst::Controller';

use Data::Dumper;

use MediaWords::Util::Tags;
use MediaWords::Util::Web;

use Regexp::Common qw /URI/;

#use YAML::Syck;
use URI::Escape;

use MediaWords::Languages::Language;

use constant ROWS_PER_PAGE => 25;

# cache google encoding lookup table
my $_google_chart_simple_encoding_lookup;

# get lookup table for google chart simple encoding values
# http://code.google.com/apis/chart/formats.html#simple
sub get_google_chart_simple_encoding_lookup
{
    my ( $v ) = @_;

    if ( !$_google_chart_simple_encoding_lookup )
    {
        my $i = 0;
        for my $c ( ( 'A' .. 'Z' ), ( 'a' .. 'z' ), ( 0 .. 9 ) )
        {
            $_google_chart_simple_encoding_lookup->{ $i++ } = $c;
        }
    }

    return $_google_chart_simple_encoding_lookup;
}

sub generate_line_chart_url
{
    my ( $terms, $title, $num_days, $slice_counts, $slice ) = @_;

    my $time_slices       = [];
    my $time_slicely_data = [];
    for my $time_slice ( 0 .. $num_days )
    {
        push @{ $time_slices }, $time_slice;
    }

    for ( my $i = 0 ; $i < @{ $terms } ; $i++ )
    {
        my $data = [];

        my $time_slice_count = 0;
        for my $time_slice ( @{ $time_slices } )
        {
            for my $slice_count ( @{ $slice_counts->{ $terms->[ $i ] } } )
            {
                if ( $slice_count->{ days } == $time_slice )
                {
                    $time_slice_count += $slice_count->{ count };
                    if ( $time_slice % $slice == 0 )
                    {
                        $time_slice_count = $time_slice_count / $slice;
                        push @{ $data }, $time_slice_count;
                        $time_slice_count = 0;
                        last;
                    }
                }
            }
        }

        push @{ $time_slicely_data }, $data;
    }

    my $params = [];

    # find single max value of all time slices
    my $max = 0;
    for my $counts ( @{ $time_slicely_data } )
    {
        for my $count ( @{ $counts } )
        {
            if ( !$max || ( $count > $max ) )
            {
                $max = $count;
            }
        }
    }

    # normalize to 60 to be able to use simple encoding (which we need to be able to fit all the data into the url)
    my $enc = get_google_chart_simple_encoding_lookup();
    push(
        @{ $params },
        'chd=s:' . join(
            ',',
            map {
                join( '', map { $enc->{ int( $_ * ( 60 / $max ) ) } } @{ $_ } )
            } @{ $time_slicely_data }
        )
    );

    # title
    push( @{ $params }, 'chtt=' . $title );

    # legend for lines
    push( @{ $params }, 'chdl=' . join( '|', map { s/\|/-/g; uri_escape( $_ ); } @{ $terms } ) );

    # legend for x axis
    my $days;
    if ( @{ $time_slices } <= 4 )
    {
        $days = $time_slices;
    }
    else
    {
        for ( my $n = 0 ; $n < 3 ; $n++ )
        {
            my $i = $n * ( @{ $time_slices } / 3 );
            push( @{ $days }, $time_slices->[ int( $i ) ] );
        }
        push( @{ $days }, $time_slices->[ @{ $time_slices } - 1 ] );
    }

    push( @{ $params }, 'chxt=x,y&chxl=0:|' . join( '|', @{ $days } ) . '|1:||20|40|60' );

    # size
    push( @{ $params }, 'chs=450x250' );

    # type
    push( @{ $params }, 'cht=lc' );

    # color
    my $colors = [ qw(ff0000 00ff00 0000ff ff8888 88ff88 8888ff 88ffff ff88ff ffff88 888888) ];
    while ( @{ $colors } > @{ $terms } )
    {
        pop( @{ $colors } );
    }
    push( @{ $params }, 'chco=' . join( ',', @{ $colors } ) );

    my $url = 'http://chart.apis.google.com/chart?' . join( '&', @{ $params } );

    return $url;

}

sub generate_bar_chart_url
{
    my ( $term_counts ) = @_;

    my $params = [];
    my $data   = [];
    my $terms  = [];
    my $max    = 0;
    foreach my $term_count ( @{ $term_counts } )
    {
        push @{ $terms }, $term_count->{ term };

        push @{ $data }, $term_count->{ count };

        if ( $term_count->{ count } > $max )
        {
            $max = $term_count->{ count };
        }
    }

    my $normalized = [ map ( int( ( $_ * 100 ) / $max ), @{ $data } ) ];

    push( @{ $params }, 'chd=t:' . join( ',', @{ $normalized } ) );

    my $y = [];
    for ( my $n = 0 ; $n < 3 ; $n++ )
    {
        my $i = $n * ( $max / 3 );
        push( @{ $y }, int( $i ) );
    }
    push( @{ $y }, $max );

    push( @{ $params }, 'chxt=x,y&chxl=0:|' . join( '|', @{ $y } ) . '|1:|' . join( '|', reverse( @{ $terms } ) ) );

    push( @{ $params }, 'chs=600x450' );

    push( @{ $params }, 'cht=bhs' );

    push( @{ $params }, 'chco=4D89F9' );

    my $url = 'http://chart.apis.google.com/chart?' . join( '&', @{ $params } );

    print STDERR "google chart url: $url\n";

    return $url;

}

sub trim($)
{
    my $string = shift;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}

# generate line-graph for the terms in the media
# ($params->{ 'terms' } is an array of terms in the form of 'term1 language_code1', 'term2 language_code2', etc.)
sub query_term_in_media
{
    my ( $self, $c, $params ) = @_;

    my $title = " Term usage ( ";

    my $time_slice = 1;

    my $slice_counts;

    # sql query
    my ( $columns, $table, $conditions, $group );

    # url
    my $url;

    # terms and languages
    my $terms_languages = [];
    foreach my $term_language ( @{ $params->{ 'terms' } } )
    {
        my ( $term, $language ) = split( ' ', $term_language );
        push( @{ $terms_languages }, { 'term' => $term, 'language' => $language } );
    }

    # Create a stems clause
    my @stems_clauses;      # "(stem = 'x1' AND language = 'y1') OR (stem = 'x2' AND language = 'y2') OR ..."
    my @stems_languages;    # 'stem1 [language1]', 'stem2 [language2]', ...
    for my $term_language ( @{ $terms_languages } )
    {
        my @term      = ( $term_language->{ term } );
        my $lang_code = $term_language->{ language };
        my $lang      = MediaWords::Languages::Language::language_for_code( $lang_code );
        my $stem      = $lang->stem( @term );
        $stem = @{ $stem }[ 0 ];

        push( @stems_languages, $stem . ' [' . $lang_code . ']' );
        push( @stems_clauses,
            '(stem = ' . $c->dbis->dbh->quote( $stem ) . ' AND language = ' . $c->dbis->dbh->quote( $lang_code ) . ')' );
    }
    my $stems_clause = ' (' . join( ' OR ', @stems_clauses ) . ') ';
    push @{ $conditions }, $stems_clause;

    if ( @{ $params->{ 'media' } } > 0 || @{ $params->{ 'media_type' } } > 0 )
    {
        $table = " daily_media_words ";
    }
    else
    {
        $table = " daily_mc_words ";
    }

    my ( $from, $to, $num_days );
    if ( $params->{ 'from' } ne "" && defined $params->{ 'to' } ne "" )
    {
        $from     = $params->{ 'from' };
        $to       = $params->{ 'to' };
        $num_days = $c->dbis->query(
            <<EOF,
            SELECT EXTRACT('days' FROM (NOW() - ?) ) - EXTRACT('days' FROM (NOW() - ?) ) AS days
EOF
            $params->{ 'from' },
            $params->{ 'to' }
        )->flat->[ 0 ];

        push @{ $conditions }, " $table.publish_day BETWEEN ? AND ? ";

        push @{ $columns },
          " EXTRACT('days' FROM (NOW() - ?) ) - EXTRACT('days' FROM (NOW() - $table.publish_day) ) AS days ";
    }
    else
    {
        $num_days = $params->{ 'preset' } || 7;
        my $now = time();
        my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( $now );
        my ( $yyyy, $mm, $dd ) = ( $year + 1900, $mon + 1, $mday );
        $to = $yyyy . "-" . $mm . "-" . $dd;
        my $then = $now - 86400 * $num_days;
        ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( $then );
        ( $yyyy, $mm, $dd ) = ( $year + 1900, $mon + 1, $mday );
        $from = $yyyy . "-" . $mm . "-" . $dd;

        push @{ $conditions }, " $table.publish_day BETWEEN ? AND ? ";

        push @{ $columns }, " ? - EXTRACT('days' FROM (NOW() - $table.publish_day) ) AS days ";
    }

    $title .= "$from - $to )";

    $time_slice *= $num_days;

    if ( @stems_languages == 1 )
    {
        push @{ $columns }, " stem_count*1000/CAST(total_count AS float) AS count ";

        $table = <<EOF;
            daily_media_words INNER JOIN total_daily_media_words ON (
                daily_media_words.publish_day = total_daily_media_words.publish_day
                AND daily_media_words.media_id = total_daily_media_words.media_id)
EOF

        my ( $media_id_name_map, $media );
        my $list;

        if ( @{ $params->{ 'media_type' } } > 0 )
        {
            push @{ $conditions }, " daily_media_words.media_id IN (SELECT media_id FROM media_tags_map WHERE tags_id = ?) ";
            push @{ $conditions },
              " total_daily_media_words.media_id IN (SELECT media_id FROM media_tags_map WHERE tags_id = ?) ";

            my $condition = " tags_id IN ( " . join( ',', map( '?', @{ $params->{ 'media_type' } } ) ) . " ) ";
            my $media_id_name_array =
              $c->dbis->query( "SELECT tags_id, tag FROM tags WHERE " . $condition, @{ $params->{ 'media_type' } } )->hashes;

            foreach my $map ( @{ $media_id_name_array } )
            {
                $media_id_name_map->{ $map->{ 'tags_id' } } = $map->{ 'tag' };
            }

            $list = $params->{ 'media_type' };
            for ( my $i = 0 ; $i < @{ $list } ; $i++ )
            {
                my $query =
                  " SELECT " . join( ' , ', @{ $columns } ) . " FROM $table WHERE " . join( ' AND ', @{ $conditions } );
                print STDERR $query, "\n";

                if ( $params->{ 'from' } ne "" && defined $params->{ 'to' } ne "" )
                {
                    $slice_counts->{ $media_id_name_map->{ $list->[ $i ] } } =
                      $c->dbis->query( $query, $from, $from, $to, $list->[ $i ], $list->[ $i ] )->hashes;
                }
                else
                {
                    $slice_counts->{ $media_id_name_map->{ $list->[ $i ] } } =
                      $c->dbis->query( $query, $num_days, $from, $to, $list->[ $i ], $list->[ $i ] )->hashes;
                }

                push @{ $media }, $media_id_name_map->{ $list->[ $i ] };
            }
            $time_slice *= @{ $list };
        }
        elsif ( @{ $params->{ 'media' } } > 0 )
        {
            push @{ $conditions }, " daily_media_words.media_id = ? ";

            my $condition = " media_id IN ( " . join( ',', map( '?', @{ $params->{ 'media' } } ) ) . " ) ";
            my $media_id_name_array =
              $c->dbis->query( "SELECT name, media_id FROM media WHERE " . $condition, @{ $params->{ 'media' } } )->hashes;

            foreach my $map ( @{ $media_id_name_array } )
            {
                $media_id_name_map->{ $map->{ 'media_id' } } = $map->{ 'name' };
            }

            $list = $params->{ 'media' };
            $time_slice *= @{ $list };
            for ( my $i = 0 ; $i < @{ $list } ; $i++ )
            {
                my $query =
                  " SELECT " . join( ' , ', @{ $columns } ) . " FROM $table WHERE " . join( ' AND ', @{ $conditions } );
                print STDERR $query, "\n";

                if ( $params->{ 'from' } ne "" && defined $params->{ 'to' } ne "" )
                {
                    $slice_counts->{ $media_id_name_map->{ $list->[ $i ] } } =
                      $c->dbis->query( $query, $from, $from, $to, $list->[ $i ] )->hashes;
                }
                else
                {
                    $slice_counts->{ $media_id_name_map->{ $list->[ $i ] } } =
                      $c->dbis->query( $query, $num_days, $from, $to, $list->[ $i ] )->hashes;
                }

                push @{ $media }, $media_id_name_map->{ $list->[ $i ] };
            }
        }
        else
        {
            $table = <<EOF;
                daily_mc_words INNER JOIN total_daily_mc_words ON (
                    daily_mc_words.publish_day = total_daily_mc_words.publish_day)
EOF

            my $query =
              " SELECT " . join( ' , ', @{ $columns } ) . " FROM $table where " . join( ' AND ', @{ $conditions } );
            print STDERR $query, "\n";

            if ( $params->{ 'from' } ne "" && defined $params->{ 'to' } ne "" )
            {
                $slice_counts->{ $stems_languages[ 0 ] } = $c->dbis->query( $query, $from, $from, $to )->hashes;
            }
            else
            {
                $slice_counts->{ $stems_languages[ 0 ] } = $c->dbis->query( $query, $num_days, $from, $to )->hashes;
            }

            push @{ $media }, $stems_languages[ 0 ];
        }

        if ( $time_slice > 800 )
        {
            my $temp = $time_slice;
            $time_slice = int( $temp / 800 ) + 1;
        }
        else
        {
            $time_slice = 1;
        }

        $url = generate_line_chart_url( $media, $title, $num_days, $slice_counts, $time_slice );
    }
    else
    {
        push @{ $columns }, " stem_count*1000/CAST(total_count AS float) AS count ";

        my $media;

        $time_slice *= @stems_languages;

        if ( @{ $params->{ 'media_type' } } > 0 )
        {
            $media = $c->dbis->query(
                " SELECT media_id FROM media_tags_map WHERE tags_id IN ( " .
                  join( ',', map( '?', @{ $params->{ 'media_type' } } ) ) . " ) ",
                @{ $params->{ 'media_type' } }
            )->flat;
        }
        elsif ( @{ $params->{ 'media' } } > 0 )
        {
            $media = $params->{ 'media' };
        }

        if ( defined $media && @{ $media } > 0 )
        {
            push @{ $conditions }, " $table.media_id IN ( " . join( ',', map( $_, @{ $media } ) ) . " ) ";
            push @{ $conditions }, " total_daily_media_words.media_id IN ( " . join( ',', map( $_, @{ $media } ) ) . " ) ";

            $table = <<EOF;
                daily_media_words INNER JOIN total_daily_media_words ON (
                    daily_media_words.publish_day = total_daily_media_words.publish_day
                    AND daily_media_words.media_id = total_daily_media_words.media_id)
EOF

            for ( my $i = 0 ; $i < @stems_languages ; $i++ )
            {
                my $query =
                  " SELECT " . join( ' , ', @{ $columns } ) . " FROM $table where " . join( ' AND ', @{ $conditions } );
                print STDERR $query, "\n";

                if ( $params->{ 'from' } ne "" && defined $params->{ 'to' } ne "" )
                {
                    $slice_counts->{ $stems_languages[ $i ] } = $c->dbis->query( $query, $from, $from, $to )->hashes;
                }
                else
                {
                    $slice_counts->{ $stems_languages[ $i ] } = $c->dbis->query( $query, $num_days, $from, $to )->hashes;
                }
            }
        }
        else
        {
            $table = <<EOF;
                daily_mc_words INNER JOIN total_daily_mc_words ON (
                    daily_mc_words.publish_day = total_daily_mc_words.publish_day )
EOF

            for ( my $i = 0 ; $i < @stems_languages ; $i++ )
            {
                my $query =
                  " SELECT " . join( ' , ', @{ $columns } ) . " FROM $table WHERE " . join( ' AND ', @{ $conditions } );
                print STDERR $query, "\n";

                if ( $params->{ 'from' } ne "" && defined $params->{ 'to' } ne "" )
                {
                    $slice_counts->{ $stems_languages[ $i ] } = $c->dbis->query( $query, $from, $from, $to )->hashes;
                }
                else
                {
                    $slice_counts->{ $stems_languages[ $i ] } = $c->dbis->query( $query, $num_days, $from, $to )->hashes;
                }
            }
        }

        if ( $time_slice > 800 )
        {
            my $temp = $time_slice;
            $time_slice = int( $temp / 800 ) + 1;
        }
        else
        {
            $time_slice = 1;
        }

        $url = generate_line_chart_url( \@stems_languages, $title, $num_days, $slice_counts, $time_slice );
    }

    print STDERR "chart_url: $url\n";

    # generate and return the google line-chart url
    return $url;
}

# generate bar-graph for the top ten terms in the media
sub query_top_terms_in_media
{
    my ( $self, $c, $params ) = @_;

    my $term_counts;

    # sql query
    my ( $columns, $table, $conditions, $group, $order, $limit );

    my $url;

    push @{ $columns }, " stem ";
    push @{ $columns }, " MAX(term) AS term ";
    push @{ $columns }, " SUM(stem_count) AS count ";

    if ( @{ $params->{ 'media' } } > 0 || @{ $params->{ 'media_type' } } > 0 )
    {
        $table = " top_500_weekly_media_words ";
    }
    else
    {
        $table = " weekly_mc_words ";
    }

    my ( $from, $to );
    if ( $params->{ 'from' } ne "" && defined $params->{ 'to' } ne "" )
    {
        $from = $params->{ 'from' };
        $to   = $params->{ 'to' };
        push @{ $conditions }, " $table.publish_week BETWEEN ? AND ? ";
        push @{ $conditions }, " NOT is_stop_stem( 'long', stem, language) ";
    }
    else
    {
        $from = 0;
        $to = $params->{ 'preset' } || 7;
        push @{ $conditions }, " $table.publish_week BETWEEN NOW() - INTERVAL '$to days' AND NOW() ";
    }

    my $media;

    if ( @{ $params->{ 'media_type' } } > 0 )
    {
        $media = $c->dbis->query(
            " SELECT media_id FROM media_tags_map WHERE tags_id IN ( " .
              join( ',', map( '?', @{ $params->{ 'media_type' } } ) ) . " ) ",
            @{ $params->{ 'media_type' } }
        )->flat;
    }
    else
    {
        $media = $params->{ 'media' };
    }

    push @{ $conditions }, " $table.media_id IN ( " . join( ',', map( '?', @{ $media } ) ) . " ) "
      if ( @{ $media } > 0 );

    $group = " GROUP BY stem ";
    $order = " ORDER BY count DESC ";
    $limit = " LIMIT 10 ";

    my $query = " SELECT " .
      join( ' , ', @{ $columns } ) . " FROM $table WHERE " . JOIN( ' AND ', @{ $conditions } ) . $group . $order . $limit;
    print STDERR $query, "\n";

    if ( $params->{ 'from' } ne "" && defined $params->{ 'to' } ne "" )
    {
        $term_counts = $c->dbis->query( $query, $from, $to, @{ $media } )->hashes;
    }
    else
    {
        $term_counts = $c->dbis->query( $query, @{ $media } )->hashes;
    }

    # generate and return google bar-chart url for the term counts
    # my $url = generate_bar_chart_url($term_counts);
    my $terms;
    if ( @{ $term_counts } > 0 )
    {
        foreach my $term_count ( @{ $term_counts } )
        {
            push @{ $terms }, $term_count->{ 'term' };
        }

        $params->{ 'terms' } = $terms;

        $url = $self->query_term_in_media( $c, $params );
    }

    return $url;
}

# display search form, and by default display the bar graph for top ten tags in today's stories
sub home : Local
{
    my ( $self, $c ) = @_;

    # search form
    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/visualize.yml',
            method           => 'get',
            action           => ''
        }
    );

    $form->process( $c->request );

    # list of media to populate the drop-down menu in the form
    my $m = $c->dbis->query( "SELECT media_id, name FROM media" )->hashes;

    foreach ( @{ $m } )
    {
        $_->{ 'name' } =~ s/\s+/ /g;
        $_->{ 'name' } = lc( $_->{ 'name' } );
        $_->{ 'name' } =~ s/[^\w ]*//g;
        $_->{ 'name' } = trim( $_->{ 'name' } );
    }

    my @media;
    push @media, [ 0, 'All' ];
    foreach ( sort { $a->{ 'name' } cmp $b->{ 'name' } } @{ $m } )
    {
        push( @media, [ $_->{ 'media_id' }, substr( $_->{ 'name' }, 0, 30 ) ] );
    }
    my $select = $form->get_element( { name => 'media' } );
    $select->options( \@media );

    # list of media types to populate the drop-down menu in the form
    # my $mt = $c->dbis->query(<<EOF
    #     SELECT tags.tags_id,
    #            tags.tag
    #     FROM tags
    #         INNER JOIN tag_sets ON (tags.tag_sets_id = tag_sets.tag_sets_id)
    #     WHERE tag_sets.name = 'media_type'
    # EOF
    #     )->hashes;
    # my @media_type;
    # foreach ( sort { $a->{'tag'} gt $b->{'tag'} } @{$mt} )
    # {
    #     push( @media_type, [ $_->{'tags_id'}, $_->{'tag'} ] );
    # }
    #
    # $select = $form->get_element( { name => 'media_type' } );
    # $select->options( \@media_type );

    # form parameters
    my $params;

    my $type                = $c->request->param( 'type' ) || 'term';
    my $term_list           = $c->request->param( 'term' );
    my $preset              = $c->request->param( 'preset' );
    my $from                = $c->request->param( 'from' ) || "";
    my $to                  = $c->request->param( 'to' ) || "";
    my @media_selected      = $c->request->param( 'media' );
    my @media_type_selected = $c->request->param( 'media_type' );

    $params->{ 'type' }   = $type;
    $params->{ 'preset' } = $preset;
    $params->{ 'from' }   = $from;
    $params->{ 'to' }     = $to;

    if ( defined $media_type_selected[ 0 ] )
    {
        $params->{ 'media' }      = [];
        $params->{ 'media_type' } = \@media_type_selected;
    }
    else
    {
        $params->{ 'media_type' } = [];

        # if 'None' is selected in media, then initialize the selected media list to empty array
        if ( defined $media_selected[ 0 ] && $media_selected[ 0 ] eq '0' )
        {
            $params->{ 'media' } = [];
        }
        else
        {
            $params->{ 'media' } = \@media_selected;
        }
    }

    my $url = "";

    # if a list of terms are specified, generate a line graph for the terms
    if ( $term_list )
    {
        $term_list =~ s/\s*,\s*/,/;
        my @terms = split( /[,\s]+/, $term_list );
        $params->{ 'terms' } = \@terms;

        $url = $self->query_term_in_media( $c, $params );
    }

    # if no terms are specified, generate a bar graph of top ten terms
    else
    {
        $url = $self->query_top_terms_in_media( $c, $params );
    }

    $c->stash->{ form }     = $form;
    $c->stash->{ url }      = $url;
    $c->stash->{ template } = 'visualize/search.tt2';
}

=head1 AUTHOR

Srivani Narra

=head1 LICENSE

AGPL

=cut

1;
