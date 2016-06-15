# Single story statistics
package MediaWords::Util::Bitly::StoryStats;

sub new($$;$$)
{
    my $class = shift;
    my ( $stories_id, $dates_and_clicks ) = @_;

    my $self = {};
    bless $self, $class;

    if ( ref( $dates_and_clicks ) ne ref( {} ) )
    {
        die "dates_and_clicks must be a hashref (click_date => click_count)";
    }

    $self->{ stories_id }       = $stories_id;
    $self->{ dates_and_clicks } = $dates_and_clicks;

    return $self;
}

sub total_click_count($)
{
    my $self = shift;

    my $total_click_count = 0;
    foreach my $date ( keys %{ $self->{ dates_and_clicks } } )
    {
        $total_click_count += $self->{ dates_and_clicks }->{ $date };
    }
    return $total_click_count;
}

1;
