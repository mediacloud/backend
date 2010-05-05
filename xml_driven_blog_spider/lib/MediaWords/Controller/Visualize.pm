package MediaWords::Controller::Visualize;

use Encode;
use strict;
use warnings;
use base 'Catalyst::Controller';

use Data::Dumper;

use MediaWords::Util::Tags;
use MediaWords::Util::Web;

use Regexp::Common qw /URI/;
use YAML::Syck;
use Text::Trim;
use URI::Escape;

use Lingua::Stem;

use constant ROWS_PER_PAGE => 25;

# cache google encoding lookup table
my $_google_chart_simple_encoding_lookup;

# get lookup table for google chart simple encoding values
# http://code.google.com/apis/chart/formats.html#simple
sub get_google_chart_simple_encoding_lookup
{
    my ($v) = @_;

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
    my ( $terms, $num_days, $slice_counts ) = @_;

    my $time_slices       = [];
    my $time_slicely_data = [];
    for my $time_slice ( 0 .. $num_days )
    {
        push @{$time_slices}, $time_slice;
    }

    for ( my $i = 0 ; $i < @{$terms} ; $i++ )
    {
        my $data = [];

        for my $time_slice ( @{$time_slices} )
        {
            my $time_slice_count = 0;
            for my $slice_count ( @{ $slice_counts->{ $terms->[$i] } } )
            {
                if ( $slice_count->{days} == $time_slice )
                {
                    $time_slice_count = $slice_count->{count};
                    last;
                }
            }
            push @{$data}, $time_slice_count;
        }

        push @{$time_slicely_data}, $data;
    }

    my $params = [];

    # data scaling
    my $max = 1;
    for my $counts ( @{$time_slicely_data} )
    {
        for my $count ( @{$counts} )
        {
            if ( !$max || ( $count > $max ) )
            {
                $max = $count;
            }
        }
    }

    # data
    # normalize to 60 to be able to use simple encoding (which we need to be able to fit all the data into the url)
    my $enc = get_google_chart_simple_encoding_lookup();
    push(
        @{$params},
        'chd=s:' . join(
            ',',
            map {
                join( '', map { $enc->{ int( $_ * ( 60 / $max ) ) } } @{$_} )
              } @{$time_slicely_data}
        )
    );

    # legend for lines
    push( @{$params}, 'chdl=' . join( '|', map { s/\|/-/g; uri_escape($_); } @{$terms} ) );

    # legend for x axis
    my $days;
    if ( @{$time_slices} <= 4 )
    {
        $days = $time_slices;
    }
    else
    {
        for ( my $n = 0 ; $n < 3 ; $n++ )
        {
            my $i = $n * ( @{$time_slices} / 3 );
            push( @{$days}, $time_slices->[ int($i) ] );
        }
        push( @{$days}, $time_slices->[ @{$time_slices} - 1 ] );
    }

    push( @{$params}, 'chxt=x&chxl=0:|' . join( '|', @{$days} ) );

    # size
    push( @{$params}, 'chs=600x250' );

    # type
    push( @{$params}, 'cht=lc' );

    # color
    my $colors = [qw(ff0000 00ff00 0000ff ff8888 88ff88 8888ff 88ffff ff88ff ffff88 888888)];
    while ( @{$colors} > @{$terms} )
    {
        pop( @{$colors} );
    }
    push( @{$params}, 'chco=' . join( ',', @{$colors} ) );

    my $url = 'http://chart.apis.google.com/chart?' . join( '&', @{$params} );

    print STDERR "google chart url: $url\n";

    return $url;

}

sub generate_bar_chart_url
{
    my ($term_counts) = @_;

    my $params = [];
    my $data   = [];
    my $terms  = [];
    my $max    = 0;
    foreach my $term_count ( @{$term_counts} )
    {
        push @{$terms}, $term_count->{term};

        push @{$data}, $term_count->{count};

        if ( $term_count->{count} > $max )
        {
            $max = $term_count->{count};
        }
    }

    my $normalized = [ map ( int( ( $_ * 100 ) / $max ), @{$data} ) ];

    print STDERR "@{$normalized}\n";

    push( @{$params}, 'chd=t:' . join( ',', @{$normalized} ) );

    my $y = [];
    for ( my $n = 0 ; $n < 3 ; $n++ )
    {
        my $i = $n * ( $max / 3 );
        push( @{$y}, int($i) );
    }
    push( @{$y}, $max );

    push( @{$params}, 'chxt=x,y&chxl=0:|' . join( '|', @{$y} ) . '|1:|' . join( '|', reverse( @{$terms} ) ) );

    push( @{$params}, 'chs=600x450' );

    push( @{$params}, 'cht=bhs' );

    push( @{$params}, 'chco=4D89F9' );

    my $url = 'http://chart.apis.google.com/chart?' . join( '&', @{$params} );

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
sub query_term_in_media
{
    my ( $self, $c, $params ) = @_;

    my $slice_counts;

    # sql query
    my ( $columns, $table, $conditions, $group );

    # url
    my $url;

    # stemming
    my $stemmer = Lingua::Stem->new;
    my $stems   = $stemmer->stem( @{ $params->{'terms'} } );

    if ( $params->{'type'} eq 'term' )
    {
        if ( @{ $params->{'media'} } > 0 )
        {
            $table = " daily_media_words ";
        }
        else
        {
            $table = " daily_mc_words ";
        }

        push @{$conditions}, " stem = ? ";
    }
    elsif ( $params->{'type'} eq 'tag' )
    {
        $table =
            " ( stories_tags_map inner join tags "
          . " on stories_tags_map.tags_id = tags.tags_id ) "
          . " inner join stories on stories_tags_map.stories_id = stories.stories_id ";

        push @{$conditions}, " tag = ? ";
    }

    my ( $from, $to, $num_days );
    if ( $params->{'from'} ne "" && defined $params->{'to'} ne "" )
    {
        $from     = $params->{'from'};
        $to       = $params->{'to'};
        $num_days = $c->dbis->query( "select extract('days' from (now() - ?) ) - extract('days' from (now() - ?) ) as days",
            $params->{'from'}, $params->{'to'} )->flat->[0];

        push @{$conditions}, " $table.publish_day between ? and ? ";

        push @{$columns}, " extract('days' from (now() - ?) ) - extract('days' from (now() - $table.publish_day) ) as days ";
    }
    else
    {
        $num_days = $params->{'preset'} || 1;
        $from     = 0;
        $to       = $params->{'preset'} || 1;

        push @{$conditions}, " extract('days' from (now() - $table.publish_day) ) between ? and ? ";

        push @{$columns}, " ? - extract('days' from (now() - $table.publish_day) ) as days ";
    }

    if ( @{$stems} == 1 && @{ $params->{'media'} } > 1 )
    {
        push @{$columns}, " stem_count*1000/cast(total_count as float) as count ";

        $table =
            " daily_media_words inner join total_daily_media_words on "
          . " (daily_media_words.publish_day = total_daily_media_words.publish_day "
          . " and daily_media_words.media_id = total_daily_media_words.media_id) ";

        push @{$conditions}, " daily_media_words.media_id = ? ";

        my $condition = " media_id in ( " . join( ',', map( '?', @{ $params->{'media'} } ) ) . " ) ";
        my $media_id_name_array =
          $c->dbis->query( "select name, media_id from media where " . $condition, @{ $params->{'media'} } )->hashes;

        my ( $media_id_name_map, $media );
        foreach my $map ( @{$media_id_name_array} )
        {
            $media_id_name_map->{ $map->{'media_id'} } = $map->{'name'};
        }

        for ( my $i = 0 ; $i < @{ $params->{'media'} } ; $i++ )
        {
            my $query = " select " . join( ' , ', @{$columns} ) . " from $table where " . join( ' and ', @{$conditions} );
            print STDERR $query, "\n";

            if ( $params->{'from'} ne "" && defined $params->{'to'} ne "" )
            {
                $slice_counts->{ $media_id_name_map->{ $params->{'media'}->[$i] } } =
                  $c->dbis->query( $query, $from, $stems->[0], $from, $to, $params->{'media'}->[$i] )->hashes;
            }
            else
            {
                $slice_counts->{ $params->{'media'}->[$i] } =
                  $c->dbis->query( $query, $num_days, $from, $to, $stems->[0], $params->{'media'}->[$i] )->hashes;
            }

            push @{$media}, $media_id_name_map->{ $params->{'media'}->[$i] };
        }
        $url = generate_line_chart_url( $media, $num_days, $slice_counts );
    }
    else
    {
        push @{$columns}, " stem_count as count ";

        push @{$conditions}, " media_id in ( " . join( ',', map( '?', @{ $params->{'media'} } ) ) . " ) "
          if ( @{ $params->{'media'} } > 0 );

        for ( my $i = 0 ; $i < @{$stems} ; $i++ )
        {
            my $query = " select " . join( ' , ', @{$columns} ) . " from $table where " . join( ' and ', @{$conditions} );
            print STDERR $query, "\n";

            if ( $params->{'from'} ne "" && defined $params->{'to'} ne "" )
            {
                $slice_counts->{ $stems->[$i] } =
                  $c->dbis->query( $query, $from, $stems->[$i], $from, $to, @{ $params->{'media'} } )->hashes;
            }
            else
            {
                $slice_counts->{ $stems->[$i] } =
                  $c->dbis->query( $query, $num_days, $stems->[$i], $from, $to, @{ $params->{'media'} } )->hashes;
            }
        }
        $url = generate_line_chart_url( $stems, $num_days, $slice_counts );
    }

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

    if ( $params->{'type'} eq 'term' )
    {
        push @{$columns}, " stem ";
        push @{$columns}, " sum(stem_count) as count ";

        if ( @{ $params->{'media'} } > 0 )
        {
            $table = " weekly_media_words ";
        }
        else
        {
            $table = " weekly_mc_words ";
        }
    }
    elsif ( $params->{'type'} eq 'tag' )
    {
        push @{$columns}, " tag as term ";
        push @{$columns}, " count(*) as count ";

        $table =
" ( stories_tags_map inner join tags on stories_tags_map.tags_id = tags.tags_id ) inner join stories on stories_tags_map.stories_id = stories.stories_id ";
    }

    my ( $from, $to );
    if ( $params->{'from'} ne "" && defined $params->{'to'} ne "" )
    {
        $from = $params->{'from'};
        $to   = $params->{'to'};
        push @{$conditions}, " publish_week between ? and ? ";
        push @{$conditions}, " is_stop_stem( 'long', stem) ";
    }
    else
    {
        $from = 0;
        $to = $params->{'preset'} || 1;
        push @{$conditions}, " extract('days' from (now() - publish_week) ) between ? and ? ";
    }

    push @{$conditions}, " media_id in ( " . join( ',', map( '?', @{ $params->{'media'} } ) ) . " ) "
      if ( @{ $params->{'media'} } > 0 );

    $group = " group by stem ";
    $order = " order by count desc ";
    $limit = " limit 10 ";

    my $query =
        " select "
      . join( ' , ', @{$columns} )
      . " from $table where "
      . join( ' and ', @{$conditions} )
      . $group
      . $order
      . $limit;
    print STDERR $query, "\n";

    $term_counts = $c->dbis->query( $query, $from, $to, @{ $params->{'media'} } )->hashes;

    # generate and return google bar-chart url for the term counts
    # my $url = generate_bar_chart_url($term_counts);
    my $terms;
    if ( @{$term_counts} > 0 )
    {
        foreach my $term_count ( @{$term_counts} )
        {
            push @{$terms}, $term_count->{'stem'};
        }

        $params->{'terms'} = $terms;

        $url = $self->query_term_in_media( $c, $params );
    }

    return $url;
}

# display search form, and by default display the bar graph for top ten tags in today's stories
sub home : Local
{
    my ( $self, $c ) = @_;

    # search form
    my $form = HTML::FormFu->new(
        {
            load_config_file => $c->path_to() . '/root/forms/visualize.yml',
            method           => 'GET',
            action           => ''
        }
    );

    $form->process( $c->request );

    # list of media to populate the drop-down menu in the form
    my $m = $c->dbis->query("select media_id, name from media")->hashes;
    my @media;
    push @media, [ 0, 'All' ];
    foreach ( sort { $a->{'name'} gt $b->{'name'} } @{$m} )
    {
        push( @media, [ $_->{'media_id'}, $_->{'name'} ] );
    }
    my $select = $form->get_element( { name => 'media' } );
    $select->options( \@media );

    # form parameters
    my $params;

    my $type           = $c->request->param('type') || 'term';
    my $term_list      = $c->request->param('term');
    my $preset         = $c->request->param('time_preset');
    my $from           = $c->request->param('from');
    my $to             = $c->request->param('to');
    my @media_selected = $c->request->param('media');

    $params->{'type'}   = $type;
    $params->{'preset'} = $preset;
    $params->{'from'}   = $from;
    $params->{'to'}     = $to;

    # if 'None' is selected in media, then initialize the selected media list to empty array
    if ( defined $media_selected[0] && $media_selected[0] eq '0' )
    {
        $params->{'media'} = [];
    }
    else
    {
        $params->{'media'} = \@media_selected;
    }

    my $url = "";

    # if a list of terms are specified, generate a line graph for the terms
    if ($term_list)
    {
        $term_list =~ s/\s*,\s*/,/;
        my @terms = split( /,/, $term_list );
        $params->{'terms'} = \@terms;

        $url = $self->query_term_in_media( $c, $params );
    }

    # if no terms are specified, generate a bar graph of top ten terms
    else
    {
        $url = $self->query_top_terms_in_media( $c, $params );
    }

    $c->stash->{form}     = $form;
    $c->stash->{url}      = $url;
    $c->stash->{template} = 'visualize/search.tt2';
}

=head1 AUTHOR

Srivani Narra

=head1 LICENSE

AGPL

=cut

1;
