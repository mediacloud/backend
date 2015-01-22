package MediaWords::Controller::Admin::CM;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;
use warnings;

use Digest::MD5;
use JSON;
use List::Compare;
use Data::Dumper;
use Gearman::JobScheduler;

use MediaWords::CM;
use MediaWords::CM::Dump;
use MediaWords::CM::Mine;
use MediaWords::DBI::Activities;
use MediaWords::DBI::Media;
use MediaWords::DBI::Stories;
use MediaWords::Solr;
use MediaWords::Solr::WordCounts;
use MediaWords::Util::Bitly;
use MediaWords::GearmanFunction::Bitly::EnqueueControversyStories;

use constant ROWS_PER_PAGE => 25;

use utf8;

use base 'Catalyst::Controller::HTML::FormFu';

#use Catalyst qw( ConfigLoader Static::Simple Unicode );

sub index : Path : Args(0)
{
    return list( @_ );
}

# list all controversies
sub list : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $controversies = $db->query( <<END )->hashes;
select c.*
    from controversies c
        left join controversy_dumps cd on ( c.controversies_id = cd.controversies_id )
    group by c.controversies_id
    order by max( coalesce( cd.dump_date, '2000-01-01'::date ) ) desc
END

    $c->stash->{ controversies } = $controversies;
    $c->stash->{ template }      = 'cm/list.tt2';
}

sub _add_controversy_date
{
    my ( $db, $controversy, $start_date, $end_date, $boundary ) = @_;

    my $existing_date = $db->query( <<END, $start_date, $end_date, $controversy->{ controversies_id } )->hash;
select * from controversy_dates where start_date = ? and end_date = ? and controversies_id = ?
END

    if ( !$existing_date )
    {
        $db->create(
            'controversy_dates',
            {
                controversies_id => $controversy->{ controversies_id },
                start_date       => $start_date,
                end_date         => $end_date
            }
        );
    }

    if ( $boundary )
    {
        $db->query( <<END, $start_date, $end_date, $controversy->{ controversies_id } )
update controversy_dates set boundary = ( start_date = ? and end_date = ? ) where controversies_id = ?
END
    }

}

# edit an existing controversy
sub edit : Local
{
    my ( $self, $c, $controversies_id ) = @_;

    my $form = $c->create_form( { load_config_file => $c->path_to() . '/root/forms/admin/cm/create_controversy.yml' } );

    my $db = $c->dbis;

    my $controversy =
      $db->query( 'select * from controversies_with_dates where controversies_id = ?', $controversies_id )->hash
      || die( "Unable to find controversy" );

    $form->default_values( $controversy );
    $form->process( $c->req );

    if ( !$form->submitted_and_valid )
    {
        $c->stash->{ form }        = $form;
        $c->stash->{ controversy } = $controversy;
        $c->stash->{ template }    = 'cm/edit_controversy.tt2';
        return;
    }
    elsif ( $c->req->params->{ preview } )
    {
        my $solr_seed_query = $c->req->params->{ solr_seed_query };
        my $pattern         = $c->req->params->{ pattern };
        $c->res->redirect( $c->uri_for( '/search', { q => $solr_seed_query, pattern => $pattern } ) );
        return;
    }

    else
    {
        my $p = $form->params;

        _add_controversy_date( $db, $controversy, $p->{ start_date }, $p->{ end_date }, 1 );

        delete( $p->{ start_date } );
        delete( $p->{ end_date } );
        delete( $p->{ preview } );

        $p->{ solr_seed_query_run } = 'f' unless ( $controversy->{ solr_seed_query } eq $p->{ solr_seed_query } );
        $p->{ process_with_bitly } //= 'f';

        $c->dbis->update_by_id( 'controversies', $controversies_id, $p );

        my $view_url = $c->uri_for( "/admin/cm/view/" . $controversies_id, { status_msg => 'Controversy updated.' } );
        $c->res->redirect( $view_url );

        return;
    }
}

# create a new controversy
sub create : Local
{
    my ( $self, $c ) = @_;

    my $form = $c->create_form( { load_config_file => $c->path_to() . '/root/forms/admin/cm/create_controversy.yml' } );

    my $db = $c->dbis;

    $c->stash->{ form }     = $form;
    $c->stash->{ template } = 'cm/create_controversy.tt2';

    # if ( defined ( $c->req->params->{ pattern } ) )
    # {
    # 	utf8::encode( $c->req->params->{ pattern } );
    # }

    # if ( defined ( $c->req->params->{ solr_seed_query } ) )
    # {
    # 	utf8::encode( $c->req->params->{ solr_seed_query } );
    # }

    $form->process( $c->request );

    if ( !$form->submitted_and_valid )
    {
        # Just show the form
        return;
    }

    # At this point the form is submitted

    my $c_name               = $c->req->params->{ name };
    my $c_pattern            = $c->req->params->{ pattern };
    my $c_solr_seed_query    = $c->req->params->{ solr_seed_query };
    my $c_description        = $c->req->params->{ description };
    my $c_start_date         = $c->req->params->{ start_date };
    my $c_end_date           = $c->req->params->{ end_date };
    my $c_process_with_bitly = ( $c->req->params->{ process_with_bitly } ? 't' : 'f' );

    if ( $c->req->params->{ preview } )
    {
        $c->res->redirect( $c->uri_for( '/search', { q => $c_solr_seed_query, pattern => $c_pattern } ) );
        return;
    }

    $db->begin;

    my $controversy = $db->create(
        'controversies',
        {
            name                => $c_name,
            pattern             => $c_pattern,
            solr_seed_query     => $c_solr_seed_query,
            solr_seed_query_run => 'f',
            description         => $c_description,
            process_with_bitly  => $c_process_with_bitly
        }
    );

    $db->create(
        'controversy_dates',
        {
            controversies_id => $controversy->{ controversies_id },
            start_date       => $c_start_date,
            end_date         => $c_end_date,
            boundary         => 't',
        }
    );

    $db->commit;

    my $status_msg = "Controversy has been created.";
    $c->res->redirect( $c->uri_for( "/admin/cm/view/$controversy->{ controversies_id }", { status_msg => $status_msg } ) );
}

# add a periods field to the controversy dump
sub add_periods_to_controversy_dump
{
    my ( $db, $controversy_dump ) = @_;

    my $periods = $db->query( <<END, $controversy_dump->{ controversy_dumps_id } )->hashes;
select distinct period from controversy_dump_time_slices
    where controversy_dumps_id = ?
    order by period;
END

    my $custom_dates = $db->query( <<END, $controversy_dump->{ controversies_id } )->hash;
select * from controversy_dates where controversies_id = ?
END

    my $expected_periods = ( $custom_dates ) ? 4 : 3;

    if ( @{ $periods } == $expected_periods )
    {
        $controversy_dump->{ periods } = 'all';
    }
    else
    {
        $controversy_dump->{ periods } = join( ", ", map { $_->{ period } } @{ $periods } );
    }
}

# get all cdtss associated with a dump, sorted consistenty and
# with a tag_name field added
sub _get_cdts_from_cd
{
    my ( $db, $cd ) = @_;

    return $db->query( <<SQL, $cd->{ controversy_dumps_id } )->hashes;
select cdts.*, coalesce( t.tag, '(all stories/no tag)' ) tag_name
    from 
        controversy_dump_time_slices cdts
        left join tags t on ( cdts.tags_id = t.tags_id )
    where 
        controversy_dumps_id = ? and
        controversy_query_slices_id is null
    order by cdts.tags_id desc, period, start_date, end_date
SQL
}

sub get_latest_full_dump_with_time_slices
{
    my ( $db, $controversy_dumps, $controversy ) = @_;

    my $latest_full_dump;
    for my $cd ( @{ $controversy_dumps } )
    {
        if ( $cd->{ periods } eq 'all' )
        {
            $latest_full_dump = $cd;
            last;
        }
    }

    return unless ( $latest_full_dump );

    my $controversy_dump_time_slices = _get_cdts_from_cd( $db, $latest_full_dump );

    map { _add_cdts_model_reliability( $db, $_ ) } @{ $controversy_dump_time_slices };

    $latest_full_dump->{ controversy_dump_time_slices } = $controversy_dump_time_slices;

    return $latest_full_dump;
}

# if there are pending controversy_links, return a hash describing the status
# of the mining process with the following fields: stories_by_iteration, queued_urls
sub _get_mining_status
{
    my ( $db, $controversy ) = @_;

    my $cid = $controversy->{ controversies_id };

    my $queued_urls = $db->query( <<END, $cid )->list;
select count(*) from controversy_links where controversies_id = ? and ref_stories_id is null
END

    return undef unless ( $queued_urls );

    my $stories_by_iteration = $db->query( <<END, $cid )->hashes;
select iteration, count(*) count
    from controversy_stories
    where controversies_id = ?
    group by iteration
    order by iteration asc
END

    return { queued_urls => $queued_urls, stories_by_iteration => $stories_by_iteration };

}

# view the details of a single controversy
sub view : Local
{
    my ( $self, $c, $controversies_id ) = @_;

    my $db = $c->dbis;

    my $controversy = $db->query( <<END, $controversies_id )->hash;
select * from controversies_with_dates where controversies_id = ?
END

    my $controversy_dumps = $db->query( <<END, $controversy->{ controversies_id } )->hashes;
select * from controversy_dumps where controversies_id = ?
    order by controversy_dumps_id desc
END

    map { add_periods_to_controversy_dump( $db, $_ ) } @{ $controversy_dumps };

    my $latest_full_dump = get_latest_full_dump_with_time_slices( $db, $controversy_dumps, $controversy );

    # Latest activities
    my Readonly $LATEST_ACTIVITIES_COUNT = 20;

    # Latest activities which directly or indirectly reference "controversies.controversies_id" = $controversies_id
    my $sql_latest_activities =
      MediaWords::DBI::Activities::sql_activities_which_reference_column( 'controversies.controversies_id',
        $controversies_id );
    $sql_latest_activities .= ' LIMIT ?';

    my $latest_activities = $db->query( $sql_latest_activities, $LATEST_ACTIVITIES_COUNT )->hashes;

    # FIXME put activity preparation (JSON decoding, description fetching) into
    # a subroutine in order to not repeat oneself.
    for ( my $x = 0 ; $x < scalar @{ $latest_activities } ; ++$x )
    {
        my $activity = $latest_activities->[ $x ];

        # Get activity description
        $activity->{ activity } = MediaWords::DBI::Activities::activity( $activity->{ name } );

        $latest_activities->[ $x ] = $activity;
    }

    # Bit.ly
    my $bitly_processing_is_enabled = MediaWords::Util::Bitly::bitly_processing_is_enabled();
    if ( $bitly_processing_is_enabled and $controversy->{ process_with_bitly } )
    {

        my $controversies_id = $controversy->{ controversies_id };

        my ( $bitly_total_stories ) = $db->query(
            <<EOF,
            SELECT COUNT(stories_id) AS total_stories
            FROM controversy_stories
            WHERE controversies_id = ?
EOF
            $controversies_id
        )->flat;
        $c->stash->{ bitly_total_stories } = $bitly_total_stories;

        my $bitly_unprocessed_stories =
          MediaWords::Util::Bitly::num_controversy_stories_without_bitly_statistics( $db, $controversies_id );
        $c->stash->{ bitly_unprocessed_stories } = $bitly_unprocessed_stories;
    }

    my $mining_status = _get_mining_status( $db, $controversy );

    my $query_slices = $db->query( <<SQL, $controversies_id )->hashes;
select * from controversy_query_slices where controversies_id = ? order by name
SQL

    $c->stash->{ controversy }                 = $controversy;
    $c->stash->{ controversy_dumps }           = $controversy_dumps;
    $c->stash->{ latest_full_dump }            = $latest_full_dump;
    $c->stash->{ latest_activities }           = $latest_activities;
    $c->stash->{ bitly_processing_is_enabled } = $bitly_processing_is_enabled;
    $c->stash->{ mining_status }               = $mining_status;
    $c->stash->{ query_slices }                = $query_slices;
    $c->stash->{ template }                    = 'cm/view.tt2';
}

# add num_stories, num_story_links, num_media, and num_media_links
# fields to the controversy_dump_time_slice
sub _add_media_and_story_counts_to_cdts
{
    my ( $db, $cdts ) = @_;

    ( $cdts->{ num_stories } ) = $db->query( "select count(*) from dump_story_link_counts" )->flat;

    ( $cdts->{ num_story_links } ) = $db->query( "select count(*) from dump_story_links" )->flat;

    ( $cdts->{ num_media } ) = $db->query( "select count(*) from dump_medium_link_counts" )->flat;

    ( $cdts->{ num_medium_links } ) = $db->query( "select count(*) from dump_medium_links" )->flat;
}

# view a controversy dump, with a list of its time slices
sub view_dump : Local
{
    my ( $self, $c, $controversy_dumps_id ) = @_;

    my $db = $c->dbis;

    my $controversy_dump = $db->query( <<END, $controversy_dumps_id )->hash;
select * from controversy_dumps where controversy_dumps_id = ?
END
    my $controversy = $db->find_by_id( 'controversies', $controversy_dump->{ controversies_id } );

    my $controversy_dump_time_slices = _get_cdts_from_cd( $db, $controversy_dump );

    map { _add_cdts_model_reliability( $db, $_ ) } @{ $controversy_dump_time_slices };

    $c->stash->{ controversy_dump }             = $controversy_dump;
    $c->stash->{ controversy }                  = $controversy;
    $c->stash->{ controversy_dump_time_slices } = $controversy_dump_time_slices;
    $c->stash->{ template }                     = 'cm/view_dump.tt2';
}

# generate a list of the top media for each of the time slices
sub _get_media_with_cdts_counts
{
    my ( $db, $cd ) = @_;

    # do this in one big complex quey because it's much faster than doing one for each cdts.
    # sort by inlink_count with each controversy and keep only the 10 lowest ranked
    # media for each time slice.
    my $top_media = $db->query( <<END, $cd->{ controversy_dumps_id } )->hashes;
with ranked_media as (
    select m.name as name,
            m.url as medium_url,
            mlc.media_id,
            mlc.controversy_dump_time_slices_id,
            cdts.model_num_media,
            cdts.start_date,
            mlc.inlink_count,
            rank() over w as inlink_count_rank,
            row_number() over w as inlink_count_row_number
        from controversy_dump_time_slices cdts
            join controversy_dumps cd on ( cdts.controversy_dumps_id = cd.controversy_dumps_id )
            join cd.medium_link_counts mlc on ( cdts.controversy_dump_time_slices_id = mlc.controversy_dump_time_slices_id )
            join cd.media m on ( mlc.media_id = m.media_id and cd.controversy_dumps_id = m.controversy_dumps_id )
        where 
            cd.controversy_dumps_id = \$1 and
            cdts.period = 'weekly' and
            mlc.inlink_count > 1        
        window w as (
            partition by mlc.controversy_dump_time_slices_id
                order by mlc.inlink_count desc )                
)

select * 
    from 
        ranked_media
    where
        inlink_count_row_number <= 10 and
        inlink_count_row_number <= model_num_media
        
    order by start_date asc, inlink_count_rank asc, media_id asc
END

    my $top_media_lookup = {};
    my $all_dates_lookup = {};
    for my $top_medium ( @{ $top_media } )
    {
        my $d = substr( $top_medium->{ start_date }, 0, 10 );
        $all_dates_lookup->{ $d } = 1;

        my $m = $top_media_lookup->{ $top_medium->{ media_id } } ||= $top_medium;

        $m->{ first_date } ||= $d;
        $m->{ first_rank } ||= $top_medium->{ inlink_count_rank };

        $m->{ count_lookup }->{ $d } =
          [ $top_medium->{ inlink_count_rank }, $top_medium->{ controversy_dump_time_slices_id } ];
        $m->{ total_weight } += 100 / $top_medium->{ inlink_count_rank };
    }

    my $sorted_media =
      [ sort { ( $a->{ first_date } cmp $b->{ first_date } ) || ( $a->{ first_rank } <=> $b->{ first_rank } ) }
          values( %{ $top_media_lookup } ) ];

    my $all_dates = [ sort { $a cmp $b } keys %{ $all_dates_lookup } ];

    for my $medium ( @{ $sorted_media } )
    {
        $medium->{ counts } = [];
        for my $d ( @{ $all_dates } )
        {
            my $count = $medium->{ count_lookup }->{ $d } || [ 0, 0 ];
            push( @{ $medium->{ counts } }, [ $d, @{ $count } ] );
        }
    }

    return $sorted_media;
}

# generate a json of the weekly counts for any medium in the top
# ten media in any week
sub view_dump_media_over_time_json : Local
{
    my ( $self, $c, $controversy_dumps_id ) = @_;

    my $db = $c->dbis;

    my $controversy_dump = $db->query( <<END, $controversy_dumps_id )->hash;
select * from controversy_dumps where controversy_dumps_id = ?
END
    my $controversy = $db->find_by_id( 'controversies', $controversy_dump->{ controversies_id } );

    my $media_with_cdts_counts = _get_media_with_cdts_counts( $db, $controversy_dump );

    $c->res->body( encode_json( $media_with_cdts_counts ) );
}

# display network viz
sub nv : Local
{
    my ( $self, $c ) = @_;

    my $live        = $c->req->params->{ l };
    my $cdts_id     = $c->req->params->{ cdts };
    my $color_field = $c->req->params->{ cf };
    my $num_media   = $c->req->params->{ nm };

    my $db = $c->dbis;

    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $cdts_id );

    $c->stash->{ cdts }             = $cdts;
    $c->stash->{ controversy_dump } = $cd;
    $c->stash->{ controversy }      = $controversy;
    $c->stash->{ live }             = $live;
    $c->stash->{ color_field }      = $color_field;
    $c->stash->{ num_media }        = $num_media;
    $c->stash->{ template }         = 'nv/nv.tt2';
}

# get json config file for network visualization.
# nv implemented in root/nv from the gephi sigma export template
sub nv_config : Local
{
    my ( $self, $c, $cdts_id, $live, $color_field, $num_media ) = @_;

    my $db = $c->dbis;

    $color_field ||= 'media_type';

    $live ||= '';

    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $cdts_id );

    my $gexf_url = $c->uri_for(
        '/admin/cm/gexf/' . $cdts->{ controversy_dump_time_slices_id },
        {
            l  => $live,
            cf => $color_field,
            nm => $num_media
        }
      ) .
      '';

    my $config_data = {
        "type"    => "network",
        "version" => "1.0",
        "data"    => $gexf_url,
        "logo"    => {
            "text" => "",
            "file" => "",
            "link" => ""
        },
        "text" => {
            "title" => "",
            "more"  => "",
            "intro" => ""
        },
        "legend" => {
            "edgeLabel"  => "",
            "colorLabel" => "",
            "nodeLabel"  => ""
        },
        "features" => {
            "search"                 => JSON::true,
            "groupSelectorAttribute" => $color_field,
            "hoverBehavior"          => "dim"
        },
        "informationPanel" => {
            "imageAttribute"       => JSON::false,
            "groupByEdgeDirection" => JSON::true
        },
        "sigma" => {
            "graphProperties" => {
                "minEdgeSize" => 0.1,
                "maxNodeSize" => 15,
                "maxEdgeSize" => 0.1,
                "minNodeSize" => 0.5
            },
            "drawingProperties" => {
                "labelThreshold"           => 10,
                "hoverFontStyle"           => "bold",
                "defaultEdgeType"          => "curve",
                "defaultLabelColor"        => "#000",
                "defaultLabelHoverColor"   => "#fff",
                "defaultLabelSize"         => 14,
                "activeFontStyle"          => "bold",
                "fontStyle"                => "bold",
                "defaultHoverLabelBGColor" => "#002147",
                "defaultLabelBGColor"      => "#ddd"
            },
            "mouseProperties" => {
                "minRatio" => 0.75,
                "maxRatio" => 20
            }
        }
    };

    my $config_json = MediaWords::Util::JSON::encode_json( $config_data, 1, 1 );

    $c->response->content_type( 'application/json; charset=UTF-8' );
    $c->response->content_length( bytes::length( $config_json ) );
    $c->res->body( $config_json );
}

# generate the d3 chart of the weekly counts for any medium in the top
# ten media in any week
sub mot : Local
{
    my ( $self, $c, $controversy_dumps_id ) = @_;

    my $db = $c->dbis;

    my $controversy_dump = $db->query( <<END, $controversy_dumps_id )->hash;
select * from controversy_dumps where controversy_dumps_id = ?
END
    my $controversy = $db->find_by_id( 'controversies', $controversy_dump->{ controversies_id } );

    $c->stash->{ controversy }      = $controversy;
    $c->stash->{ controversy_dump } = $controversy_dump;
    $c->stash->{ template }         = 'cm/mot/mot.tt2';
}

# get the media marked as the most influential media for the current time slice
sub _get_top_media_for_time_slice
{
    my ( $db, $cdts ) = @_;

    my $num_media = $cdts->{ model_num_media };

    return unless ( $num_media );

    $num_media = 20 if ( $num_media > 20 );

    my $top_media = $db->query(
        <<END,
        SELECT m.*,
               mlc.inlink_count,
               mlc.outlink_count,
               mlc.story_count,
               mlc.bitly_click_count,
               mlc.bitly_referrer_count
        FROM dump_media_with_types AS m,
             dump_medium_link_counts AS mlc
        WHERE m.media_id = mlc.media_id
        ORDER BY mlc.inlink_count DESC
        LIMIT ?
END
        $num_media
    )->hashes;

    return $top_media;
}

# get the top 20 stories for the current time slice
sub _get_top_stories_for_time_slice
{
    my ( $db ) = @_;

    my $top_stories = $db->query(
        <<END,
        SELECT s.*,
               slc.inlink_count,
               slc.outlink_count,
               slc.bitly_click_count,
               slc.bitly_referrer_count,
               m.name as medium_name,
               m.media_type
        FROM dump_stories AS s,
             dump_story_link_counts AS slc,
             dump_media_with_types AS m
        WHERE s.stories_id = slc.stories_id
          AND s.media_id = m.media_id
        ORDER BY slc.inlink_count DESC
        LIMIT ?
END
        20
    )->hashes;

    map { _add_story_date_info( $db, $_ ) } @{ $top_stories };

    return $top_stories;
}

# given the model r2 mean and sd values, return a string indicating whether the
# time slice is reliable, somewhat reliable, or not reliable
sub _add_cdts_model_reliability
{
    my ( $db, $cdts ) = @_;

    my $r2_mean   = $cdts->{ model_r2_mean }   || 0;
    my $r2_stddev = $cdts->{ model_r2_stddev } || 0;

    # compute the lowest standard reliability among the model runs
    my $lsr = $r2_mean - $r2_stddev;

    my $reliability;
    if ( $lsr > 0.85 )
    {
        $reliability = 'reliable';
    }
    elsif ( $lsr > 0.75 )
    {
        $reliability = 'somewhat';
    }
    else
    {
        $reliability = 'not';
    }

    $cdts->{ model_reliability } = $reliability;
}

# get the controversy_dump_time_slice, controversy_dump, and controversy
# for the current request
sub _get_controversy_objects
{
    my ( $db, $cdts_id ) = @_;

    die( "cdts param is required" ) unless ( $cdts_id );

    my $cdts = $db->find_by_id( 'controversy_dump_time_slices', $cdts_id ) || die( "cdts not found" );
    my $cd = $db->find_by_id( 'controversy_dumps', $cdts->{ controversy_dumps_id } );

    my $controversy = $db->query( <<END, $cd->{ controversies_id } )->hash;
select * from controversies_with_dates where controversies_id = ?
END

    # add shortcut field names to make it easier to refer to in tt2
    $cdts->{ cdts_id }          = $cdts->{ controversy_dump_time_slices_id };
    $cdts->{ cd_id }            = $cdts->{ controversy_dumps_id };
    $cdts->{ controversy_dump } = $cd;
    $cd->{ cd_id }              = $cdts->{ controversy_dumps_id };

    _add_cdts_model_reliability( $db, $cdts );

    return ( $cdts, $cd, $controversy );
}

# get a media_type_stats hash for the given time slice that has the following format:
# { story_count =>
#   [ { media_type => 'Blog', num_stories => $num_stories, percent_stories => $percent_stories },
#     { media_type => 'Tech Media', num_stories => $num_stories, percent_stories => $percent_stories },
#     ...
#   ]
# { link_weight =>
#   [ { media_type => 'Blog', link_weight => $link_weight, percent_link_weight => $percent_link_weight },
#     { media_type => 'General Online News Media', link_weight => $link_weight, percent_link_weight => $percent_link_weight },
#     ...
#   ]
#
# optionally only include stories in the given list of stories_ids.
# must be called within a transaction.
sub _get_media_type_stats_for_time_slice
{
    my ( $db, $stories_ids ) = @_;

    my $stories_clause = '1=1';
    if ( $stories_ids )
    {
        my $ids_table = $db->get_temporary_ids_table( $stories_ids );
        $stories_clause = "s.stories_id in ( select id from $ids_table )";
    }

    my $story_count = $db->query( <<END )->hashes;
with media_type_stats as (
    select
            s.media_type,
            count(*) num_stories,
            sum( inlink_count ) link_weight
        from
            dump_stories_with_types s 
            join dump_story_link_counts slc on ( s.stories_id = slc.stories_id )
        where
            $stories_clause
        group by s.media_type
),

media_type_sums as (
    select sum( num_stories ) sum_num_stories, sum( link_weight ) sum_link_weight from media_type_stats
)

select
        media_type,
        num_stories,
        case when sum_num_stories = 0
            then 
                0
            else 
                round( ( num_stories / sum_num_stories ) * 100 ) 
            end percent_stories,
        link_weight,
        case when sum_link_weight = 0
            then
                0
            else
                round( ( link_weight / sum_link_weight ) * 100 ) 
            end percent_link_weight
    from
        media_type_stats
        cross join media_type_sums
    order by num_stories desc;
END

    my $link_weight = [ @{ $story_count } ];
    $link_weight = [ sort { $b->{ link_weight } <=> $a->{ link_weight } } @{ $link_weight } ];

    return { story_count => $story_count, link_weight => $link_weight };
}

# view timelices, with links to csv and gexf files
sub view_time_slice : Local
{
    my ( $self, $c, $cdts_id ) = @_;

    my $db = $c->dbis;

    $db->begin;

    my $live = $c->req->param( 'l' );

    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $cdts_id );

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, $live );

    MediaWords::CM::Dump::update_cdts_counts( $db, $cdts, $live ) if ( $live );

    my $top_media = _get_top_media_for_time_slice( $db, $cdts );
    my $top_stories = _get_top_stories_for_time_slice( $db, $cdts );
    my $media_type_stats = _get_media_type_stats_for_time_slice( $db );

    $db->commit;

    $c->stash->{ cdts }             = $cdts;
    $c->stash->{ controversy_dump } = $cd;
    $c->stash->{ controversy }      = $controversy;
    $c->stash->{ top_media }        = $top_media;
    $c->stash->{ top_stories }      = $top_stories;
    $c->stash->{ media_type_stats } = $media_type_stats;
    $c->stash->{ live }             = $live;
    $c->stash->{ template }         = 'cm/view_time_slice.tt2';
}

# download a csv field from controversy_dump_time_slices_id or generate the
# csv for the same data live from the controversy data.
sub _download_cdts_csv
{
    my ( $c, $cdts_id, $table, $live ) = @_;

    die( "illegal table name '$table'" ) unless ( grep { $_ eq $table } qw(stories story_links media medium_links) );

    my $db = $c->dbis;

    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $cdts_id );

    my ( $csv, $file );
    if ( $live )
    {
        $db->begin;

        MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, $live );

        $csv  = eval( 'MediaWords::CM::Dump::get_' . $table . '_csv( $db, $cdts )' );
        $file = "${ table }.csv";

        MediaWords::CM::Dump::discard_temp_tables( $db );

        $db->commit;
    }
    else
    {
        $file = $table . '.csv';
        ( $csv ) = $db->query( <<END, $cdts->{ controversy_dump_time_slices_id }, $file )->flat;
select file_content from cdts_files where controversy_dump_time_slices_id = ? and file_name = ?
END
    }

    $c->response->header( "Content-Disposition" => "attachment;filename=$file" );
    $c->response->content_type( 'text/csv; charset=UTF-8' );
    $c->response->content_length( bytes::length( $csv ) );
    $c->response->body( $csv );
}

# download the stories_csv for the given time slice
sub dump_stories : Local
{
    my ( $self, $c, $controversy_dump_time_slices_id ) = @_;

    _download_cdts_csv( $c, $controversy_dump_time_slices_id, 'stories', $c->req->params->{ l } );
}

# download the story_links_csv for the given time slice
sub dump_story_links : Local
{
    my ( $self, $c, $controversy_dump_time_slices_id ) = @_;

    _download_cdts_csv( $c, $controversy_dump_time_slices_id, 'story_links', $c->req->params->{ l } );
}

# download the media_csv for the given time slice
sub dump_media : Local
{
    my ( $self, $c, $controversy_dump_time_slices_id ) = @_;

    _download_cdts_csv( $c, $controversy_dump_time_slices_id, 'media', $c->req->params->{ l } );
}

# download the medium_links_csv for the given time slice
sub dump_medium_links : Local
{
    my ( $self, $c, $controversy_dump_time_slices_id ) = @_;

    _download_cdts_csv( $c, $controversy_dump_time_slices_id, 'medium_links', $c->req->params->{ l } );
}

# download the gexf file for the time slice.  if the 'l' param is 1, use live data instead of
# dumped data for the time slice.  if using a dump, use an existing media.gexf file if it exists.
sub gexf : Local
{
    my ( $self, $c, $cdts_id, $csv ) = @_;

    my $l           = $c->req->params->{ l };
    my $color_field = $c->req->params->{ cf };
    my $num_media   = $c->req->params->{ nm };

    my $db = $c->dbis;

    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $cdts_id );

    my $gexf;

    if ( !$l )
    {
        ( $gexf ) = $db->query( <<END, $cdts->{ controversy_dump_time_slices_id } )->flat;
select file_content from cdts_files where controversy_dump_time_slices_id = ? and file_name = 'media.gexf'
END
    }

    if ( !$gexf )
    {
        MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, $l );
        $gexf = MediaWords::CM::Dump::get_gexf_dump( $db, $cdts, $color_field, $num_media );
    }

    my $base_url = $c->uri_for( '/' );

    $gexf =~ s/\[_mc_base_url_\]/$base_url/g;

    my $file = "media.gexf";

    $c->response->header( "Content-Disposition" => "attachment;filename=$file" );
    $c->response->content_type( 'text/gexf; charset=UTF-8' );
    $c->response->content_length( bytes::length( $gexf ) );
    $c->response->body( $gexf );
}

# download a csv field from controversy_dumps
sub _download_cd_csv
{
    my ( $c, $controversy_dumps_id, $csv ) = @_;

    my $field = $csv . '_csv';

    my $db = $c->dbis;

    my $cd = $db->find_by_id( 'controversy_dumps', $controversy_dumps_id );

    my $file = "${ csv }_$cd->{ controversy_dumps_id }.csv";

    $c->response->header( "Content-Disposition" => "attachment;filename=$file" );
    $c->response->content_type( 'text/csv; charset=UTF-8' );
    $c->response->content_length( bytes::length( $cd->{ $field } ) );
    $c->response->body( $cd->{ $field } );
}

# download the daily_counts_csv for the given dump
sub dump_daily_counts : Local
{
    my ( $self, $c, $controversy_dumps_id ) = @_;

    _download_cd_csv( $c, $controversy_dumps_id, 'daily_counts' );
}

# download the weekly_counts_csv for the given dump
sub dump_weekly_counts : Local
{
    my ( $self, $c, $controversy_dumps_id ) = @_;

    _download_cd_csv( $c, $controversy_dumps_id, 'weekly_counts' );
}

# return the latest dump if it is not the dump to which the cdts belongs.  otherwise return undef.
sub _get_latest_controversy_dump
{
    my ( $db, $cdts ) = @_;

    my $latest_dump = $db->query( <<END, $cdts->{ controversy_dump_time_slices_id } )->hash;
select latest.* from controversy_dumps latest, controversy_dumps current, controversy_dump_time_slices cdts
    where cdts.controversy_dump_time_slices_id = ? and
        current.controversy_dumps_id = cdts.controversy_dumps_id and
        latest.controversy_dumps_id > current.controversy_dumps_id and
        latest.controversies_id = current.controversies_id
    order by latest.controversy_dumps_id desc
    limit 1
END

    return $latest_dump;
}

# fetch the medium from the dump_media table
sub _get_medium_from_dump_tables
{
    my ( $db, $media_id ) = @_;

    return $db->query( "select * from dump_media_with_types where media_id = ?", $media_id )->hash;
}

# get the medium with the medium_stories, inlink_stories, and outlink_stories and associated
# counts. assumes the existence of dump_* stories as created by
# MediaWords::CM::Dump::setup_temporary_dump_tables
sub _get_medium_and_stories_from_dump_tables
{
    my ( $db, $media_id ) = @_;

    my $medium = _get_medium_from_dump_tables( $db, $media_id );

    return unless ( $medium );

    $medium->{ stories } = $db->query(
        <<END,
        SELECT s.*,
               m.name AS medium_name,
               m.media_type,
               slc.inlink_count,
               slc.outlink_count,
               slc.bitly_click_count,
               slc.bitly_referrer_count
        FROM dump_stories AS s,
             dump_media_with_types AS m,
             dump_story_link_counts AS slc
        WHERE s.stories_id = slc.stories_id
          AND s.media_id = m.media_id
          AND s.media_id = ?
        ORDER BY slc.inlink_count DESC
END
        $media_id
    )->hashes;
    map { _add_story_date_info( $db, $_ ) } @{ $medium->{ stories } };

    $medium->{ inlink_stories } = $db->query(
        <<END,
        SELECT DISTINCT s.*,
                        sm.name AS medium_name,
                        sm.media_type,
                        sslc.inlink_count,
                        sslc.outlink_count,
                        sslc.bitly_click_count,
                        sslc.bitly_referrer_count
        FROM dump_stories AS s,
             dump_story_link_counts AS sslc,
             dump_media_with_types AS sm,
             dump_stories AS r,
             dump_story_link_counts AS rslc,
             dump_controversy_links_cross_media AS cl
        WHERE s.stories_id = sslc.stories_id
          AND r.stories_id = rslc.stories_id
          AND s.media_id = sm.media_id
          AND s.stories_id = cl.stories_id
          AND r.stories_id = cl.ref_stories_id
          AND r.media_id = ?
        ORDER BY sslc.inlink_count DESC
END
        $media_id
    )->hashes;

    map { _add_story_date_info( $db, $_ ) } @{ $medium->{ inlink_stories } };

    $medium->{ outlink_stories } = $db->query(
        <<END,
        SELECT DISTINCT r.*,
                        rm.name AS medium_name,
                        rm.media_type,
                        rslc.inlink_count,
                        rslc.outlink_count,
                        rslc.bitly_click_count,
                        rslc.bitly_referrer_count
        FROM dump_stories AS s,
             dump_story_link_counts AS sslc,
             dump_stories AS r,
             dump_story_link_counts AS rslc,
             dump_media_with_types AS rm,
             dump_controversy_links_cross_media AS cl
        WHERE s.stories_id = sslc.stories_id
          AND r.stories_id = rslc.stories_id
          AND r.media_id = rm.media_id
          AND s.stories_id = cl.stories_id
          AND r.stories_id = cl.ref_stories_id
          AND s.media_id = ?
        ORDER BY rslc.inlink_count DESC
END
        $media_id
    )->hashes;

    map { _add_story_date_info( $db, $_ ) } @{ $medium->{ outlink_stories } };

    $medium->{ story_count }   = scalar( @{ $medium->{ stories } } );
    $medium->{ inlink_count }  = scalar( @{ $medium->{ inlink_stories } } );
    $medium->{ outlink_count } = scalar( @{ $medium->{ outlink_stories } } );

    return $medium;
}

# get data about the medium as it existed in the given time slice.  include medium_stories,
# inlink_stories, and outlink_stories from the time slice as well.
sub _get_cdts_medium_and_stories
{
    my ( $db, $cdts, $media_id ) = @_;

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts );

    my $medium = _get_medium_and_stories_from_dump_tables( $db, $media_id );

    MediaWords::CM::Dump::discard_temp_tables( $db );

    return $medium;
}

# get live data about the medium within the given controversy.  Include medium_stories,
# inlink_stories, and outlink_stories.
sub _get_live_medium_and_stories
{
    my ( $db, $controversy, $cdts, $media_id ) = @_;

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, 1 );

    my $medium = _get_medium_and_stories_from_dump_tables( $db, $media_id );

    MediaWords::CM::Dump::discard_temp_tables( $db );

    return $medium;
}

# return undef if given fields in the given objects are the same and the
# list_field in the given lists are the same.   Otherwise return a string list
# of the fields and lists for which there are differences.
sub _get_object_diffs
{
    my ( $a, $b, $fields, $lists, $list_field ) = @_;

    my $diffs = [];

    for my $field ( @{ $fields } )
    {
        push( @{ $diffs }, $field ) if ( $a->{ $field } ne $b->{ $field } );
    }

    for my $list ( @{ $lists } )
    {
        my $a_ids = [ map { $_->{ $list_field } } @{ $a->{ $list } } ];
        my $b_ids = [ map { $_->{ $list_field } } @{ $b->{ $list } } ];

        my $lc = List::Compare->new( $a_ids, $b_ids );
        if ( !$lc->is_LequivalentR() )
        {
            my $list_name = $list;
            $list_name =~ s/_/ /g;
            push( @{ $diffs }, $list_name );
        }
    }

    return ( @{ $diffs } ) ? join( ", ", @{ $diffs } ) : undef;
}

# check each of the following for differences between the live and dump medium:
# * name
# * url
# * ids of stories
# * ids of inlink_stories
# * ids of outlink_stories
#
# return undef if there are no diffs and otherwise a string list of the
# attributes (above) for which there are differences
sub _get_live_medium_diffs
{
    my ( $dump_medium, $live_medium ) = @_;

    if ( !$live_medium )
    {
        return 'medium is no longer in controversy';
    }

    return _get_object_diffs(
        $dump_medium, $live_medium,
        [ qw(name url) ],
        [ qw(stories inlink_stories outlink_stories) ], 'stories_id'
    );
}

# view medium:
# * live if l=1 is specified, otherwise as a snapshot
# * within the context of a time slice if a time slice is specific
#   via cdts=<id>, otherwise within a whole controversy if 'c=<id>'
sub medium : Local
{
    my ( $self, $c, $media_id ) = @_;

    my $db = $c->dbis;

    $db->begin;

    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $c->req->param( 'cdts' ) );

    my $live = $c->req->param( 'l' );
    my $live_medium = _get_live_medium_and_stories( $db, $controversy, $cdts, $media_id );

    my ( $medium, $live_medium_diffs, $latest_controversy_dump );
    if ( $live )
    {
        $medium = $live_medium;
    }
    else
    {
        $medium = _get_cdts_medium_and_stories( $db, $cdts, $media_id );
        $live_medium_diffs = _get_live_medium_diffs( $medium, $live_medium );
        $latest_controversy_dump = _get_latest_controversy_dump( $db, $cdts );
    }

    $db->commit;

    $c->stash->{ cdts }                    = $cdts;
    $c->stash->{ controversy_dump }        = $cd;
    $c->stash->{ controversy }             = $controversy;
    $c->stash->{ medium }                  = $medium;
    $c->stash->{ latest_controversy_dump } = $latest_controversy_dump;
    $c->stash->{ live_medium_diffs }       = $live_medium_diffs;
    $c->stash->{ live }                    = $live;
    $c->stash->{ live_medium }             = $live_medium;
    $c->stash->{ template }                = 'cm/medium.tt2';
}

# add the following fields to the story:
# * date_is_reliable
# * undateable
sub _add_story_date_info
{
    my ( $db, $story ) = @_;

    $story->{ date_is_reliable } = MediaWords::DBI::Stories::date_is_reliable( $db, $story );
    $story->{ undateable } = MediaWords::DBI::Stories::is_undateable( $db, $story );
}

# get the story along with inlink_stories and outlink_stories and the associated
# counts.  assumes the existence of dump_* stories as created by
# MediaWords::CM::Dump::setup_temporary_dump_tables
sub _get_story_and_links_from_dump_tables
{
    my ( $db, $stories_id ) = @_;

    # if the below query returns nothing, the return type of the server prepared statement
    # may differ from the first call, which throws a postgres error, so we need to
    # disable server side prepares
    $db->dbh->{ pg_server_prepare } = 0;

    my $story = $db->query( "select * from dump_stories where stories_id = ?", $stories_id )->hash;

    return unless ( $story );

    $story->{ medium } = $db->query( "select * from dump_media_with_types where media_id = ?", $story->{ media_id } )->hash;

    _add_story_date_info( $db, $story );

    $story->{ inlink_stories } = $db->query(
        <<END,
        SELECT DISTINCT s.*,
                        sm.name AS medium_name,
                        sm.media_type,
                        sslc.inlink_count,
                        sslc.outlink_count,
                        sslc.bitly_click_count,
                        sslc.bitly_referrer_count
        FROM dump_stories AS s,
             dump_story_link_counts AS sslc,
             dump_media_with_types AS sm,
             dump_stories AS r,
             dump_story_link_counts AS rslc,
             dump_controversy_links_cross_media AS cl
        WHERE s.stories_id = sslc.stories_id
          AND r.stories_id = rslc.stories_id
          AND s.media_id = sm.media_id
          AND s.stories_id = cl.stories_id
          AND r.stories_id = cl.ref_stories_id
          AND cl.ref_stories_id = ?
        ORDER BY sslc.inlink_count DESC
END
        $stories_id
    )->hashes;

    map { _add_story_date_info( $db, $_ ) } @{ $story->{ inlink_stories } };

    $story->{ outlink_stories } = $db->query(
        <<END,
        SELECT DISTINCT r.*,
                        rm.name AS medium_name,
                        rm.media_type,
                        rslc.inlink_count,
                        rslc.outlink_count,
                        rslc.bitly_click_count,
                        rslc.bitly_referrer_count
        FROM dump_stories AS s,
             dump_story_link_counts AS sslc,
             dump_stories AS r,
             dump_story_link_counts AS rslc,
             dump_media_with_types AS rm,
             dump_controversy_links_cross_media AS cl
        WHERE s.stories_id = sslc.stories_id
          AND r.stories_id = rslc.stories_id
          AND r.media_id = rm.media_id
          AND s.stories_id = cl.stories_id
          AND r.stories_id = cl.ref_stories_id
          AND cl.stories_id = ?
        ORDER BY rslc.inlink_count DESC
END
        $stories_id
    )->hashes;

    map { _add_story_date_info( $db, $_ ) } @{ $story->{ outlink_stories } };

    $story->{ inlink_count }  = scalar( @{ $story->{ inlink_stories } } );
    $story->{ outlink_count } = scalar( @{ $story->{ outlink_stories } } );

    return $story;
}

# get data about the story as it existed in the given time slice.  include
# outlinks and inlinks, as well as the date guess method.
sub _get_cdts_story_and_links
{
    my ( $db, $cdts, $stories_id ) = @_;

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts );

    my $story = _get_story_and_links_from_dump_tables( $db, $stories_id );

    MediaWords::CM::Dump::discard_temp_tables( $db );

    return $story;
}

# get data about the story as it exists now in the database, optionally
# in the date range of the if specified
sub _get_live_story_and_links
{
    my ( $db, $controversy, $cdts, $stories_id ) = @_;

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, 1 );

    my $story = _get_story_and_links_from_dump_tables( $db, $stories_id );

    MediaWords::CM::Dump::discard_temp_tables( $db );

    return $story;
}

# check each of the following for differences between the live and dump story:
# * title
# * url
# * publish_date
# * ids of inlink_stories
# * ids of outlink_stories
# * date_is_reliable
# * undateable
#
# return undef if there are no diffs and otherwise a string list of the
# attributes (above) for which there are differences
sub _get_live_story_diffs
{
    my ( $dump_story, $live_story ) = @_;

    if ( !$live_story )
    {
        return 'story is no longer in controversy';
    }

    return _get_object_diffs(
        $dump_story, $live_story,
        [ qw(title url publish_date date_is_reliable undateable) ],
        [ qw(inlink_stories outlink_stories) ], 'stories_id'
    );
}

# view story as it existed in a dump time slice
sub story : Local
{
    my ( $self, $c, $stories_id ) = @_;

    my $db = $c->dbis;

    $db->begin;

    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $c->req->param( 'cdts' ) );

    my $live = $c->req->param( 'l' );
    my $live_story = _get_live_story_and_links( $db, $controversy, $cdts, $stories_id );

    my ( $story, $live_story_diffs, $latest_controversy_dump );
    if ( $live )
    {
        $story = $live_story;
    }
    else
    {
        $story = _get_cdts_story_and_links( $db, $cdts, $stories_id );
        $live_story_diffs = _get_live_story_diffs( $story, $live_story );
        $latest_controversy_dump = _get_latest_controversy_dump( $db, $cdts );
    }

    $story->{ extracted_text } = MediaWords::DBI::Stories::get_extracted_text( $db, $story );
    $story->{ controversy_match } = MediaWords::CM::Mine::story_matches_controversy_pattern( $db, $controversy, $story );

    $db->commit;

    my $confirm_remove = $c->req->params->{ confirm_remove };

    $c->stash->{ cdts }                    = $cdts;
    $c->stash->{ controversy_dump }        = $cd;
    $c->stash->{ controversy }             = $controversy;
    $c->stash->{ story }                   = $story;
    $c->stash->{ latest_controversy_dump } = $latest_controversy_dump;
    $c->stash->{ live_story_diffs }        = $live_story_diffs;
    $c->stash->{ live }                    = $live;
    $c->stash->{ live_story }              = $live_story;
    $c->stash->{ confirm_remove }          = $confirm_remove;
    $c->stash->{ template }                = 'cm/story.tt2';
}

# get the text for a sql query that returns all of the story ids that
# match the given search query within solr.
sub _get_stories_id_search_query
{
    my ( $db, $q ) = @_;

    return 'select stories_id from dump_story_link_counts' unless ( $q );

    $q =~ s/^\s+//;
    $q =~ s/\s+$//;

    my $period_stories_ids = $db->query( "select stories_id from dump_story_link_counts" )->flat;

    my $stories_clause = "stories_id:(" . join( ' ', @{ $period_stories_ids } ) . ")";

    my $stories_ids = MediaWords::Solr::search_for_stories_ids( $db, { q => $q, fq => $stories_clause } );

    return @{ $stories_ids } ? join( ',', @{ $stories_ids } ) : -1;
}

# get solr params for running a query against solr in the given time slice
sub _get_solr_params_for_time_slice_query
{
    my ( $cdts, $q ) = @_;

    my $params = { fq => "{~ controversy_dump_time_slice:$cdts->{ controversy_dump_time_slices_id } }" };

    $params->{ q } = ( defined( $q ) && $q ne '' ) ? $q : '*:*';

    return $params;
}

# get the top words used by the given set of stories, sorted by tfidf against all words
# in the controversy
sub _get_story_words ($$$$$;$)
{
    my ( $db, $controversy, $cdts, $q, $sort_by_count, $num_words ) = @_;

    my $solr_p = _get_solr_params_for_time_slice_query( $cdts, $q );
    my $stories_ids = MediaWords::Solr::search_for_stories_ids( $db, $solr_p );

    if ( !$num_words )
    {
        $num_words = int( log( scalar( @{ $stories_ids } ) + 1 ) * 10 );
        $num_words = ( $num_words < 100 ) ? $num_words : 100;
    }

    my $story_words = MediaWords::Solr::WordCounts->new( db => $db, %{ $solr_p } )->get_words;

    splice( @{ $story_words }, $num_words );

    if ( !$sort_by_count )
    {
        for my $story_word ( @{ $story_words } )
        {
            my $solr_df_query = "{~ controversy:$controversy->{ controversies_id } }";

            my $df = MediaWords::Solr::get_num_found(
                $db,
                {
                    q  => "+sentence:" . $story_word->{ term },
                    fq => $solr_df_query
                }
            );

            if ( $df )
            {
                $story_word->{ tfidf }       = $story_word->{ count } / sqrt( $df );
                $story_word->{ total_count } = $df;
            }
            else
            {
                $story_word->{ tfidf } = 0;
            }
        }
        $story_words = [ sort { $b->{ tfidf } <=> $a->{ tfidf } } @{ $story_words } ];
    }

    map { $story_words->[ $_ ]->{ rank } = $_ + 1 } ( 0 .. $#{ $story_words } );

    return $story_words;
}

# remove all stories in the stories_ids cgi param from the controversy
sub remove_stories : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $cdts_id = $c->req->params->{ cdts };
    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $cdts_id );

    my $live             = $c->req->params->{ l };
    my $stories_ids      = $c->req->params->{ stories_ids };
    my $controversies_id = $controversy->{ controversies_id };

    $stories_ids = [ $stories_ids ] if ( $stories_ids && !ref( $stories_ids ) );

    for my $stories_id ( @{ $stories_ids } )
    {
        _remove_story_from_controversy( $db, $stories_id, $controversies_id, $c->user->username,
            $c->req->params->{ reason } );
    }

    my $status_msg = scalar( @{ $stories_ids } ) . " stories removed from controversy.";
    $c->res->redirect( $c->uri_for( "/admin/cm/view_time_slice/$cdts_id", { l => $live, status_msg => $status_msg } ) );
}

# display a word cloud of the words in the stories given in the stories_ids cgi param
# optionaly tfidf'd to all stories in the given controversy
sub word_cloud : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    $db->begin;

    my $cdts_id = $c->req->params->{ cdts };
    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $cdts_id );

    my $live          = $c->req->params->{ l };
    my $q             = $c->req->params->{ q };
    my $sort_by_count = $c->req->params->{ sort_by_count };

    my $words = _get_story_words( $db, $controversy, $cdts, $q, $sort_by_count );

    $c->stash->{ cdts }             = $cdts;
    $c->stash->{ controversy_dump } = $cd;
    $c->stash->{ controversy }      = $controversy;
    $c->stash->{ live }             = $live;
    $c->stash->{ words }            = $words;
    $c->stash->{ q }                = $q;
    $c->stash->{ sort_by_count }    = $sort_by_count;
    $c->stash->{ template }         = 'cm/words.tt2';
}

# do a basic story search based on the story sentences, title, url, media name, and media url
sub search_stories : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    $db->begin;

    my $cdts_id = $c->req->params->{ cdts } + 0;
    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $cdts_id );

    my $live = $c->req->params->{ l };
    my $reason = $c->req->params->{ reason } || '';

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, $live );

    my $query = $c->req->params->{ q };
    my $search_query = _get_stories_id_search_query( $db, $query );

    my $order = $c->req->params->{ order } || '';
    my $order_clause = $order eq 'bitly_click_count' ? 'slc.bitly_click_count desc' : 'slc.inlink_count desc';

    my $stories = $db->query(
        <<"END"
        SELECT s.*,
               m.name AS medium_name,
               m.media_type,
               slc.inlink_count,
               slc.outlink_count,
               slc.bitly_click_count,
               slc.bitly_referrer_count
        FROM dump_stories AS s,
             dump_media_with_types AS m,
             dump_story_link_counts AS slc
        WHERE s.stories_id = slc.stories_id
          AND s.media_id = m.media_id
          AND s.stories_id IN ( $search_query )          
        ORDER BY $order_clause
        limit 1000
END
    )->hashes;

    map { _add_story_date_info( $db, $_ ) } @{ $stories };

    MediaWords::CM::Dump::discard_temp_tables( $db );

    $db->commit;

    my $controversies_id = $controversy->{ controversies_id };

    if ( $c->req->params->{ missing_solr_stories } )
    {
        my $solr_query       = "{! controversy:$controversy->{ controversies_id } }";
        my $solr_stories_ids = MediaWords::Solr::search_for_stories_ids( $db, { q => $solr_query } );
        my $solr_lookup      = {};
        map { $solr_lookup->{ $_ } = 1 } @{ $solr_stories_ids };
        $stories = [ grep { !$solr_lookup->{ $_->{ stories_id } } } @{ $stories } ];
    }

    if ( $c->req->params->{ remove_stories } )
    {
        $db->begin;

        eval {
            map { _remove_story_from_controversy( $db, $_->{ stories_id }, $controversies_id, $c->user->username, $reason ) }
              @{ $stories };
        };
        if ( $@ )
        {
            $db->rollback;

            my $error = "Unable to remove stories: $@";
            $c->res->redirect( $c->uri_for( "/admin/cm/view_time_slice/$cdts_id", { l => $live, status_msg => $error } ) );
            return;
        }

        $db->commit;

        my $status_msg = "stories removed from controversy.";
        $c->res->redirect( $c->uri_for( "/admin/cm/view_time_slice/$cdts_id", { l => $live, status_msg => $status_msg } ) );
        return;
    }

    $c->stash->{ cdts }             = $cdts;
    $c->stash->{ controversy_dump } = $cd;
    $c->stash->{ controversy }      = $controversy;
    $c->stash->{ stories }          = $stories;
    $c->stash->{ query }            = $query;
    $c->stash->{ live }             = $live;
    $c->stash->{ template }         = 'cm/stories.tt2';
}

# if the search query is a number and returns a medium in the controversy,
# add the medium to the beginning of the search results
sub _add_id_medium_to_search_results ($$$)
{
    my ( $db, $media, $query ) = @_;

    return unless ( $query =~ /^[0-9]+$/ );

    my $id_medium = $db->query(
        <<END,
        SELECT DISTINCT m.*,
                        mlc.inlink_count,
                        mlc.outlink_count,
                        mlc.bitly_click_count,
                        mlc.bitly_referrer_count,
                        mlc.story_count
        FROM dump_story_link_counts AS slc
            JOIN stories AS s ON ( slc.stories_id = s.stories_id )
            JOIN dump_media_with_types AS m ON ( s.media_id = m.media_id )
            JOIN dump_medium_link_counts AS mlc ON ( m.media_id = mlc.media_id )
        WHERE s.media_id = ?
END
        $query
    )->hash;

    if ( $id_medium )
    {
        unshift( @{ $media }, $id_medium );
    }
}

# do a basic media search based on the story sentences, title, url, media name, and media url
sub search_media : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    $db->begin;

    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $c->req->param( 'cdts' ) );

    my $live = $c->req->param( 'l' );

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, $live );

    my $query = $c->req->param( 'q' );
    my $search_query;

    if ( $query )
    {
        my $stories_id_query = _get_stories_id_search_query( $db, $query );
        $search_query = "AND m.media_id IN ( select media_id from dump_stories where stories_id in ( $stories_id_query ) )";
    }
    else
    {
        $search_query = '';
    }

    my $order = $c->req->params->{ order } || '';
    my $order_clause = $order eq 'bitly_click_count' ? 'mlc.bitly_click_count desc' : 'mlc.inlink_count desc';

    my $media = $db->query(
        <<"END"
        SELECT DISTINCT m.*,
                        mlc.inlink_count,
                        mlc.outlink_count,
                        mlc.bitly_click_count,
                        mlc.bitly_referrer_count,
                        mlc.story_count
        FROM dump_media_with_types AS m,
             dump_medium_link_counts AS mlc
        WHERE m.media_id = mlc.media_id
          $search_query
        ORDER BY $order_clause
        limit 1000
END
    )->hashes;

    MediaWords::CM::Dump::discard_temp_tables( $db );

    $db->commit;

    $c->stash->{ cdts }             = $cdts;
    $c->stash->{ controversy_dump } = $cd;
    $c->stash->{ controversy }      = $controversy;
    $c->stash->{ media }            = $media;
    $c->stash->{ query }            = $query;
    $c->stash->{ live }             = $live;
    $c->stash->{ template }         = 'cm/media.tt2';
}

# remove the given story from the given controversy; die()s on error
sub _remove_story_from_controversy($$$$$)
{
    my ( $db, $stories_id, $controversies_id, $user, $reason ) = @_;

    $reason ||= '';

    eval {

        # Do the change
        MediaWords::CM::Mine::remove_story_from_controversy( $db, $stories_id, $controversies_id );

        # Log the activity
        my $change = { 'stories_id' => $stories_id + 0 };
        unless (
            MediaWords::DBI::Activities::log_activity(
                $db, 'cm_remove_story_from_controversy',
                $user, $controversies_id, $reason, $change
            )
          )
        {
            die "Unable to log the story removal activity.";
        }

    };
    if ( $@ )
    {
        die "Unable to remove story $stories_id from controversy $controversies_id: $@";
    }
}

# merge source_media_id into target_media_id
sub merge_media : Local : FormConfig
{
    my ( $self, $c, $media_id ) = @_;

    my $db = $c->dbis;

    $db->begin;

    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $c->req->param( 'cdts' ) );

    my $live = 1;

    $c->stash->{ controversy } = $controversy;
    $c->stash->{ cd }          = $cd;
    $c->stash->{ cdts }        = $cdts;
    $c->stash->{ live }        = $live;

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, $live );

    my $medium = _get_medium_from_dump_tables( $db, $media_id );

    my $to_media_id = $c->req->param( 'to_media_id' ) // 0;
    $to_media_id = $to_media_id + 0;
    my $to_medium = _get_medium_from_dump_tables( $db, $to_media_id ) if ( $to_media_id );

    MediaWords::CM::Dump::discard_temp_tables( $db );

    $db->commit;

    my $cdts_id = $cdts->{ controversy_dump_time_slices_id } + 0;

    if ( !$medium )
    {
        my $error = 'This medium no longer exists in the live data';
        my $u = $c->uri_for( "/admin/cm/view/$controversy->{ controversies_id }", { error_msg => $error } );
        $c->response->redirect( $u );
        return;
    }

    my $form = $c->stash->{ form };

    if ( !$form->submitted_and_valid )
    {
        $c->stash->{ medium }   = $medium;
        $c->stash->{ template } = 'cm/merge_media.tt2';
        return;
    }

    if ( !$to_medium )
    {
        my $error = 'The destination medium no longer exists in the live data';
        my $u = $c->uri_for( "/admin/cm/medium/$media_id", { cdts => $cdts_id, error_msg => $error } );
        $c->response->redirect( $u );
        return;
    }

    # Start transaction
    $db->begin;

    my $reason = $c->req->param( 'reason' ) || '';

    # Make the merge
    eval { MediaWords::CM::Mine::merge_dup_medium_all_controversies( $db, $medium, $to_medium ); };
    if ( $@ )
    {
        $db->rollback;

        my $error = "Unable to merge media: $@";
        my $u = $c->uri_for( "/admin/cm/medium/$media_id", { cdts => $cdts_id, error_msg => $error } );
        $c->response->redirect( $u );
        return;
    }

    # Log the activity
    my $change = {
        'media_id'    => $media_id + 0,
        'to_media_id' => $to_media_id + 0,
        'cdts_id'     => $cdts_id + 0
    };
    unless (
        MediaWords::DBI::Activities::log_activity(
            $db, 'cm_media_merge', $c->user->username, $controversy->{ controversies_id } + 0,
            $reason, $change
        )
      )
    {
        $db->rollback;

        my $error = "Unable to log the activity of merging media.";
        my $u = $c->uri_for( "/admin/cm/medium/$media_id", { cdts => $cdts_id, error_msg => $error } );
        $c->response->redirect( $u );
        return;
    }

    # Things went fine
    $db->commit;

    my $status_msg = 'The media have been merged in all controversies.';
    my $u = $c->uri_for( "/admin/cm/medium/$to_media_id", { cdts => $cdts_id, status_msg => $status_msg, l => 1 } );
    $c->response->redirect( $u );
    return;
}

# merge $story into $to_story in $controversy
sub _merge_stories
{
    my ( $c, $controversy, $story, $to_story, $reason ) = @_;

    $reason ||= '';

    my $db = $c->dbis;

    return 1 if ( $story->{ stories_id } == $to_story->{ stories_id } );

    eval { MediaWords::CM::Mine::merge_dup_story( $db, $controversy, $story, $to_story ); };
    if ( $@ )
    {
        $db->rollback;

        print STDERR "Unable to merge stories: $@\n";
        return 0;
    }

    # Log the activity
    my $change = { stories_id => $story->{ stories_id }, to_stories_id => $to_story->{ stories_id } };

    my $logged =
      MediaWords::DBI::Activities::log_activity( $db, 'cm_story_merge', $c->user->username,
        $controversy->{ controversies_id },
        $reason, $change );

    if ( !$logged )
    {
        $db->rollback;

        print STDERR "Unable to log the activity of merging stories.\n";
        return 0;
    }

    return 1;
}

# merge stories_id into to_stories_id
sub merge_stories : Local : FormConfig
{
    my ( $self, $c, $stories_id ) = @_;

    my $db = $c->dbis;

    $db->begin;

    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $c->req->param( 'cdts' ) );

    my $live = 1;

    $c->stash->{ controversy } = $controversy;
    $c->stash->{ cd }          = $cd;
    $c->stash->{ cdts }        = $cdts;
    $c->stash->{ live }        = $live;

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, $live );

    my $story = $db->query( "select * from dump_stories where stories_id = ?", $stories_id )->hash;

    my $to_stories_id = $c->req->param( 'to_stories_id' ) + 0;
    my $to_story = $db->query( "select * from dump_stories where stories_id = ?", $to_stories_id )->hash
      if ( $to_stories_id );

    MediaWords::CM::Dump::discard_temp_tables( $db );

    $db->commit;

    my $cdts_id = $cdts->{ controversy_dump_time_slices_id } + 0;

    if ( !$story )
    {
        my $error = 'The requested story no longer exists in the live data';
        my $u = $c->uri_for( "/admin/cm/view/$controversy->{ controversies_id }", { error_msg => $error } );
        $c->response->redirect( $u );
        return;
    }

    my $form = $c->stash->{ form };

    if ( !$form->submitted_and_valid )
    {
        $c->stash->{ story }    = $story;
        $c->stash->{ template } = 'cm/merge_stories.tt2';
        return;
    }

    # Start transaction
    $db->begin;

    my $reason = $c->req->param( 'reason' ) || '';

    # Make the merge
    my $stories_merged = _merge_stories( $c, $controversy, $story, $to_story, $reason );

    $db->commit;

    my $status_msg;
    if ( !$stories_merged )
    {
        $status_msg = 'There was an error merging the stories.';
    }
    else
    {
        $status_msg = 'The stories have been merged in this controversy.';
    }

    my $u = $c->uri_for( "/admin/cm/story/$to_stories_id", { cdts => $cdts_id, status_msg => $status_msg, l => 1 } );
    $c->response->redirect( $u );
}

# parse story ids and associated urls from param names, along
# with the associated assume_match and manual_redirect options for
# each url.  call MediaWords::Util::URL::unredirect_story on
# each story and its urls and associated options.
sub unredirect_param_stories
{
    my ( $c ) = @_;

    my $db = $c->dbis;

    my $story_urls = {};
    for my $name ( keys( %{ $c->req->params } ) )
    {
        next unless ( $name =~ /^include_url_(\d+)_(\d+)_(.*)$/ );
        my ( $stories_id, $controversies_id, $url ) = ( $1, $2, $3 );

        my $param_tag = "${ stories_id }_${ controversies_id }_${ url }";

        my $url_options = {
            url             => $url,
            assume_match    => $c->req->params->{ "assume_match_${ param_tag }" },
            manual_redirect => $c->req->params->{ "manual_redirect_${ param_tag }" }
        };

        push( @{ $story_urls->{ $stories_id }->{ $controversies_id } }, $url_options );
    }

    while ( my ( $stories_id, $controversy_urls ) = each( %{ $story_urls } ) )
    {
        while ( my ( $controversies_id, $urls ) = each( %{ $controversy_urls } ) )
        {
            my $story = $db->find_by_id( 'stories', $stories_id )
              || die( "Unable to find story '$stories_id'" );

            my $controversy = $db->find_by_id( 'controversies', $controversies_id )
              || die( "Unable to find controversy '$controversies_id'" );

            MediaWords::CM::Mine::unredirect_story( $db, $controversy, $story, $urls );
        }
    }
}

# action to confirm splitting up media source based on its stories' original, unredirected urls
sub unredirect_medium : Local
{
    my ( $self, $c, $media_id ) = @_;

    my $db = $c->dbis;

    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $c->req->param( 'cdts' ) );
    my $live = 1;

    my $medium = $db->find_by_id( 'media', $media_id ) || die( "Unable to find medium '$media_id'" );

    if ( $c->req->params->{ submit } )
    {
        MediaWords::CM::Mine::add_medium_url_to_ignore_redirects( $db, $medium );
        unredirect_param_stories( $c );

        my $msg = "The medium has been reprocessed to use the original urls of its stories.";
        $c->res->redirect( $c->uri_for( "/admin/cm/view/$controversy->{ controversies_id }", { status_msg => $msg } ) );
        return;
    }

    my $stories = $db->query( "select * from stories where media_id = ?", $media_id )->hashes;

    map { $_->{ original_urls } = MediaWords::CM::Mine::get_story_original_urls( $db, $_ ) } @{ $stories };

    $c->stash->{ controversy } = $controversy;
    $c->stash->{ cd }          = $cd;
    $c->stash->{ cdts }        = $cdts;
    $c->stash->{ live }        = $live;
    $c->stash->{ stories }     = $stories;
    $c->stash->{ medium }      = $medium;
    $c->stash->{ template }    = 'cm/unredirect_medium.tt2';
}

# List all activities
sub activities : Local
{
    my ( $self, $c, $controversies_id ) = @_;

    my $p = $c->request->param( 'p' ) || 1;

    my $controversy = $c->dbis->query(
        <<END,
        SELECT *
        FROM controversies
        WHERE controversies_id = ?
END
        $controversies_id
    )->hash;

    # Activities which directly or indirectly reference "controversies.controversies_id" = $controversies_id
    my $sql_activities =
      MediaWords::DBI::Activities::sql_activities_which_reference_column( 'controversies.controversies_id',
        $controversies_id );

    my ( $activities, $pager ) = $c->dbis->query_paged_hashes( $sql_activities, [], $p, ROWS_PER_PAGE );

    # FIXME put activity preparation (JSON decoding, description fetching) into
    # a subroutine in order to not repeat oneself.
    for ( my $x = 0 ; $x < scalar @{ $activities } ; ++$x )
    {
        my $activity = $activities->[ $x ];

        # Get activity description
        $activity->{ activity } = MediaWords::DBI::Activities::activity( $activity->{ name } );

        # Decode activity descriptions from JSON
        $activity->{ description } =
          MediaWords::DBI::Activities::decode_activity_description( $activity->{ name }, $activity->{ description_json } );

        $activities->[ $x ] = $activity;
    }

    $c->stash->{ controversy } = $controversy;
    $c->stash->{ activities }  = $activities;
    $c->stash->{ pager }       = $pager;
    $c->stash->{ pager_url }   = $c->uri_for( '/admin/cm/activities/' . $controversies_id ) . '?';

    $c->stash->{ template } = 'cm/activities.tt2';
}

# delete list of story ids from controversy
sub delete_stories : Local
{
    my ( $self, $c, $controversies_id ) = @_;

    my $db = $c->dbis;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id )
      || die( "unable to find controversy '$controversies_id'" );

    my $stories_ids_list = $c->req->params->{ stories_ids } || '';
    my $stories_ids = [ grep { /^\d+$/ } split( /\s+/, $stories_ids_list ) ];

    if ( !@{ $stories_ids } )
    {
        $c->stash->{ error_msg }   = 'no valid story ids in list' if ( $stories_ids_list );
        $c->stash->{ controversy } = $controversy;
        $c->stash->{ template }    = 'cm/delete_stories.tt2';
        return;
    }

    for my $stories_id ( @{ $stories_ids } )
    {
        _remove_story_from_controversy( $db, $stories_id, $controversies_id, $c->user->username, 'batch removal' );
    }

    my $status_msg = scalar( @{ $stories_ids } ) . " stories removed from controversy.";
    $c->res->redirect( $c->uri_for( "/admin/cm/view/$controversies_id", { status_msg => $status_msg } ) );
}

# merge list of stories, in keep_id,delete_id format
sub merge_stories_list : Local
{
    my ( $self, $c, $controversies_id ) = @_;

    my $db = $c->dbis;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id )
      || die( "unable to find controversy '$controversies_id'" );

    my $stories_ids_list = $c->req->params->{ stories_ids } || '';

    if ( !$stories_ids_list )
    {
        $c->stash->{ controversy } = $controversy;
        $c->stash->{ template }    = 'cm/merge_stories_list.tt2';
        return;
    }

    my $stories_ids_pairs = MediaWords::Util::CSV::get_csv_string_as_matrix( $stories_ids_list );

    $db->begin;

    my $stories_merged = 1;
    for my $stories_id_pair ( @{ $stories_ids_pairs } )
    {
        my ( $keep_stories_id, $delete_stories_id ) = @{ $stories_id_pair };

        my $keep_story   = $db->find_by_id( 'stories', $keep_stories_id );
        my $delete_story = $db->find_by_id( 'stories', $delete_stories_id );

        $stories_merged = _merge_stories( $c, $controversy, $delete_story, $keep_story );
        last unless ( $stories_merged );
    }

    $db->commit if ( $stories_merged );

    my $status_msg;
    if ( $stories_merged )
    {
        $status_msg = 'The stories have been merged in this controversy.';
    }
    else
    {
        $status_msg = 'There was an error merging the stories.';
    }

    my $u = $c->uri_for( "/admin/cm/view/$controversies_id", { status_msg => $status_msg } );
    $c->response->redirect( $u );
}

# get metrics for links between partisan communities in the form of:
# [
#  [
#   {
#     'source_tag' => 'partisan_2012_liberal',
#     'log_inlink_count' => '29.1699250014423',
#     'ref_tag' => 'partisan_2012_liberal',
#     'source_tags_id' => 29,
#     'inlink_count' => '32',
#     'media_link_count' => '26',
#     'ref_tags_id' => 29
#   },
#   {
#     'source_tag' => 'partisan_2012_liberal',
#     'log_inlink_count' => '38.1536311941017',
#     'ref_tag' => 'partisan_2012_libertarian',
#     'source_tags_id' => 29,
#     'inlink_count' => '61',
#     'media_link_count' => '25',
#     'ref_tags_id' => 30
#   },
#   ...
#  ], [ ... ], ... ]
sub _get_partisan_link_metrics
{
    my ( $db, $stories_ids ) = @_;

    my $stories_clause = '1=1';
    if ( $stories_ids )
    {
        my $ids_table = $db->get_temporary_ids_table( $stories_ids );
        $stories_clause = "s.stories_id in ( select id from $ids_table )";
    }

    my $query = <<END;
-- partisan collection tags
with partisan_tags as (
    select t.* 
        from
            tags t 
            join tag_sets ts on (t.tag_sets_id = ts.tag_sets_id )
        where
            ts.name = 'collection' and
            t.tag in ( 'partisan_2012_liberal', 'partisan_2012_conservative', 'partisan_2012_libertarian' )
),

-- all stories in the controversy belonging to the media tagged with one of the partisan collection tags
partisan_stories as (
    select s.*, t.*
        from 
            dump_stories s
            join dump_media_tags_map mtm on ( s.media_id = mtm.media_id )
            join dump_tags t on ( mtm.tags_id = t.tags_id )
            join partisan_tags pt on ( t.tags_id = pt.tags_id )
            join dump_tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
        where
            $stories_clause
),

-- full matrix of all partisan tags joined to one another
partisan_tags_matrix as ( 
    select 
            at.tags_id tags_id_a, 
            at.tag tag_a, 
            at.label label_a,
            bt.tags_id tags_id_b, 
            bt.tag tag_b, 
            bt.label label_b
        from 
            partisan_tags at
            cross join partisan_tags bt
),

-- matrix of all partisan tags that have links to one another
sparse_matrix as (
    select distinct 
            ss.tags_id source_tags_id,
            rs.tags_id ref_tags_id,
            count(*) over w media_link_count,
            sum( log( count(*) + 1 ) / log ( 2 ) ) over w log_inlink_count,
            sum( count(*) ) over w inlink_count
        from 
            partisan_stories ss
            join dump_story_links sl on ( ss.stories_id = sl.source_stories_id )
            join partisan_stories rs on ( rs.stories_id = sl.ref_stories_id )
        group by ss.media_id, ss.tags_id, rs.media_id, rs.tags_id
        window w as ( partition by ss.tags_id, rs.tags_id )
        order by ss.tags_id, rs.tags_id
)

-- join the full matrix to the sparse matrix to add 0 values for partisan tag <-> partisan tag
-- combination that have no links between them (which are not present in the sparse matrix )
select
        ptm.tags_id_a source_tags_id,
        ptm.tag_a as source_tag,
        ptm.label_a as source_label,
        ptm.tags_id_b ref_tags_id,
        ptm.tag_b ref_tag,
        ptm.label_b as ref_label,
        coalesce( sm.media_link_count, 0 ) media_link_count,
        coalesce( sm.log_inlink_count, 0 ) log_inlink_count,
        coalesce( sm.inlink_count, 0 ) inlink_count
    from
        partisan_tags_matrix ptm
        left join sparse_matrix sm on 
            ( ptm.tags_id_a = sm.source_tags_id and ptm.tags_id_b = sm.ref_tags_id )

END

    my $link_metrics = $db->query( $query )->hashes;

    # arrange results into a list of lists, sorted by source tags id
    my $last_source_tags_id = 0;
    my $metrics_table       = [];
    for my $m ( @{ $link_metrics } )
    {
        if ( $last_source_tags_id != $m->{ source_tags_id } )
        {
            push( @{ $metrics_table->[ @{ $metrics_table } ] }, $m );
            $last_source_tags_id = $m->{ source_tags_id };
        }
        else
        {
            push( @{ $metrics_table->[ @{ $metrics_table } - 1 ] }, $m );
        }
    }

    return $metrics_table;
}

# generate report on partisan behavior within set
sub partisan : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $cdts_id = $c->req->params->{ cdts };
    my $live    = $c->req->params->{ l };

    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $cdts_id );

    $db->begin;

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, undef );

    my $metrics_table = _get_partisan_link_metrics( $db );

    $db->commit;

    $c->stash->{ metrics_table } = $metrics_table;
    $c->stash->{ controversy }   = $controversy;
    $c->stash->{ cd }            = $cd;
    $c->stash->{ cdts }          = $cdts;
    $c->stash->{ live }          = $live;
    $c->stash->{ template }      = 'cm/partisan.tt2';
}

# given a list of word lists as returned by _get_story_words, add a { key_word => 1 } field
# to each word hash for which the rank of that word is higher than the rank for that
# word in any other list
sub _highlight_key_words
{
    my ( $word_lists ) = @_;

    my $word_rank_lookup = {};
    for my $word_list ( @{ $word_lists } )
    {
        for my $word ( @{ $word_list } )
        {
            my $stem = $word->{ stem };
            my $rank = $word->{ rank };
            if ( !$word_rank_lookup->{ $stem } )
            {
                $word_rank_lookup->{ $stem } = { rank => $rank, key_word => $word };
                $word->{ key_word } = 1;
            }
            elsif ( $word_rank_lookup->{ $stem }->{ rank } > $rank )
            {
                $word_rank_lookup->{ $stem }->{ key_word }->{ key_word } = 0;
                $word_rank_lookup->{ $stem } = { rank => $rank, key_word => $word };
                $word->{ key_word } = 1;
            }
            elsif ( $word_rank_lookup->{ $stem }->{ rank } == $rank )
            {
                $word_rank_lookup->{ $stem }->{ key_word }->{ key_word } = 0;
            }
        }
    }

}

# get the overall time slice for the controversy dump associated with this time slice
sub _get_overall_time_slice
{
    my ( $db, $cdts, $cd ) = @_;

    return $cdts if ( $cdts->{ period } eq 'overall' );

    my $overall_cdts = $db->query( <<END, $cdts->{ controversy_dumps_id } )->hash;
select cdts.* from controversy_dump_time_slices cdts where controversy_dumps_id = ? and period = 'overall'
END

    die( "Unable to find overall time slice" ) unless ( $overall_cdts );

    return $overall_cdts;
}

# display the 20 most popular words for the 10 most influential media in the given time slice
# or for the 10 most influential media overall
sub influential_media_words : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $cdts_id = $c->req->params->{ cdts };

    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $cdts_id );

    my $live    = $c->req->params->{ l };
    my $q       = $c->req->params->{ q };
    my $overall = $c->req->params->{ overall };

    my $media_cdts = $overall ? _get_overall_time_slice( $db, $cdts, $cd ) : $cdts;

    $db->begin;
    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $media_cdts, $controversy, $live );
    my $top_media = _get_top_media_for_time_slice( $db, $media_cdts );
    $db->commit;

    my $num_media = 10;
    my $num_words = 20;

    my $display_media = [];
    my $hide_media    = [];
    for my $medium ( @{ $top_media } )
    {
        my $q = "media_id:$medium->{ media_id }";
        $medium->{ words } = _get_story_words( $db, $controversy, $cdts, $q, 1, 20 );
        splice( @{ $medium->{ words } }, $num_words );

        if ( @{ $medium->{ words } } >= ( $num_words / 2 ) )
        {
            push( @{ $display_media }, $medium );
        }
        else
        {
            push( @{ $hide_media }, $medium );
        }

        last if ( @{ $display_media } >= $num_media );
    }

    $top_media = $display_media;

    my $top_words = _get_story_words( $db, $controversy, $cdts, undef, 1 );

    _highlight_key_words( [ $top_words, map { $_->{ words } } @{ $top_media } ] );

    $c->stash->{ cdts }        = $cdts;
    $c->stash->{ cd }          = $cd;
    $c->stash->{ controversy } = $controversy;
    $c->stash->{ live }        = $live;
    $c->stash->{ top_media }   = $top_media;
    $c->stash->{ hide_media }  = $hide_media;
    $c->stash->{ q }           = $q;
    $c->stash->{ top_words }   = $top_words;
    $c->stash->{ overall }     = $overall;
    $c->stash->{ template }    = 'cm/influential_media_words.tt2';
}

# update the media type of the given controversy.  if the submitted tag is a 'media_type'
# tag, delete any existing media_type_tag_sets_id tag first.
sub _update_media_type
{
    my ( $db, $medium, $tags_id, $controversy ) = @_;

    my $tag = $db->query( <<END, $tags_id )->hash;
select * from tags_with_sets where tags_id = ?
END

    if ( $tag->{ tag_set_name } eq 'media_type' )
    {
        $db->query( <<END, $medium->{ media_id }, $controversy->{ media_type_tag_sets_id } );
delete from media_tags_map mtm
    using 
        tags t
    where 
        mtm.tags_id = t.tags_id and
        t.tag_sets_id = \$2 and
        mtm.media_id = \$1
END
    }

    MediaWords::DBI::Media::update_media_type( $db, $medium, $tags_id );
}

# process form values to add media types according to form parameters.
# each relevant form param has a name of 'media_type_<media_id>'
# (eg. 'media_type_123') and the tags_id of the media_type tag to add.
sub _process_add_media_type_params
{
    my ( $c, $controversy ) = @_;

    my $db = $c->dbis;

    for my $type_param ( keys( %{ $c->req->params } ) )
    {
        next unless ( $type_param =~ /media_type_(\d+)/ );

        my $media_id = $1;
        my $tags_id  = $c->req->params->{ $type_param };

        my $medium = $db->query( "select * from media_with_media_types where media_id = ?", $media_id )->hash
          || die( "Unable to find medium '$media_id'" );

        _update_media_type( $db, $medium, $tags_id, $controversy );
    }
}

sub _get_media_for_typing : Local
{
    my ( $c, $cdts, $controversy ) = @_;

    my $db = $c->dbis;

    my $retype_media_type = $c->req->params->{ retype_media_type } || 'Not Typed';
    my $last_media_id     = $c->req->params->{ last_media_id }     || 0;

    $db->begin;
    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, 1 );

    my $media = $db->query( <<END, $retype_media_type )->hashes;
with ranked_media as (
    select m.*, 
            mlc.inlink_count, 
            mlc.outlink_count, 
            mlc.story_count,
            rank() over ( order by mlc.inlink_count desc, m.media_id desc ) r
        from 
            dump_media_with_types m, 
            dump_medium_link_counts mlc
        where
            m.media_id = mlc.media_id
        order by r
)

select *
    from 
        ranked_media m
    where
        m.media_type = ? and
        ( ( $last_media_id = 0 ) or
          ( r > ( select r from ranked_media where media_id = $last_media_id limit 1 ) ) )
    limit 10    
END

    $db->commit;

    return $media;
}

# page for adding media types to 'not type'd media
sub add_media_types : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $c->req->params->{ cdts } );
    my $retype_media_type = $c->req->params->{ retype_media_type };

    _process_add_media_type_params( $c, $controversy );

    my $media = _get_media_for_typing( $c, $cdts, $controversy );
    my $last_media_id = @{ $media } ? $media->[ $#{ $media } ]->{ media_id } : 0;

    my $media_types = MediaWords::DBI::Media::get_media_type_tags( $db, $controversy->{ controversies_id } );

    $c->stash->{ controversy }       = $controversy;
    $c->stash->{ cd }                = $cd;
    $c->stash->{ cdts }              = $cdts;
    $c->stash->{ live }              = 1;
    $c->stash->{ media }             = $media;
    $c->stash->{ last_media_id }     = $last_media_id;
    $c->stash->{ media_types }       = $media_types;
    $c->stash->{ retype_media_type } = $retype_media_type;
    $c->stash->{ template }          = 'cm/add_media_types.tt2';
}

# delete all controversy_dates in the controversy
sub delete_all_dates : Local
{
    my ( $self, $c, $controversies_id ) = @_;

    my $db = $c->dbis;

    my $controversy = $db->query( "select * from controversies_with_dates where controversies_id = ?", $controversies_id )
      || die( "Unable to find controversy" );

    $db->query( <<END, $controversies_id );
delete from controversy_dates where not bounday and controversies_id = ?
END

}

# delet a single controversy_dates row
sub delete_date : Local
{
    my ( $self, $c, $controversies_id ) = @_;

    my $db = $c->dbis;

    my $controversy = $db->query( "select * from controversies_with_dates where controversies_id = ?", $controversies_id )
      || die( "Unable to find controversy" );

    my $start_date = $c->req->params->{ start_date };
    my $end_date   = $c->req->params->{ end_date };

    die( "missing start_date or end_date" ) unless ( $start_date && $end_date );

    $db->query( <<END, $controversies_id, $start_date, $end_date );
delete from controversy_dates where controversies_id = ? and start_date = ? and end_date = ? and not boundary
END

    $c->res->redirect( $c->uri_for( '/admin/cm/edit_dates/' . $controversies_id, { status_msg => 'Date deleted.' } ) );
}

# add timeslice dates for every $interval days
sub _add_interval_dates
{
    my ( $db, $controversy, $interval ) = @_;

    return unless ( $interval > 0 );

    sub increment_day { MediaWords::Util::SQL::increment_day( @_ ) }

    my $last_interval_start = increment_day( $controversy->{ end_date }, -1 * $interval );

    for ( my $i = $controversy->{ start_date } ; $i lt $last_interval_start ; $i = increment_day( $i, $interval ) )
    {
        _add_controversy_date( $db, $controversy, $i, increment_day( $i, $interval ) );
    }
}

# add custom time slice range to controversy_dates
sub add_date : Local
{
    my ( $self, $c, $controversies_id ) = @_;

    my $db = $c->dbis;

    my $controversy =
      $db->query( "select * from controversies_with_dates where controversies_id = ?", $controversies_id )->hash
      || die( "Unable to find controversy" );

    my $interval   = $c->req->params->{ interval } + 0;
    my $start_date = $c->req->params->{ start_date };
    my $end_date   = $c->req->params->{ end_date };

    if ( $interval )
    {
        _add_interval_dates( $db, $controversy, $interval );
    }
    else
    {
        my $valid_date = qr/^\d\d\d\d-\d\d-\d\d$/;
        if ( !( ( $start_date =~ $valid_date ) && ( $end_date =~ $valid_date ) ) )
        {
            $c->res->redirect(
                $c->uri_for( '/admin/cm/edit_dates/' . $controversies_id, { error_msg => 'Invalid date format.' } ) );
            return;
        }

        die( "missing start_date or end_date" ) unless ( $start_date && $end_date );

        _add_controversy_date( $db, $controversy, $start_date, $end_date );
    }

    $c->res->redirect( $c->uri_for( '/admin/cm/edit_dates/' . $controversies_id, { status_msg => 'Dates added.' } ) );
}

# edit list of controversy_dates for the controversy
sub edit_dates : Local
{
    my ( $self, $c, $controversies_id ) = @_;

    my $db = $c->dbis;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id ) || die( "Unable to find controversy" );

    my $controversy_dates = $db->query( <<END, $controversies_id )->hashes;
select cd.* from controversy_dates cd where cd.controversies_id = ? order by cd.start_date, cd.end_date desc 
END

    $c->stash->{ controversy }       = $controversy;
    $c->stash->{ controversy_dates } = $controversy_dates;
    $c->stash->{ template }          = 'cm/edit_dates.tt2';
}

# find existing media_type_tag_set for controversy or create a new one
# if one does not already exist
sub _find_or_create_controversy_media_type
{
    my ( $db, $controversy ) = @_;

    if ( my $tag_sets_id = $controversy->{ media_type_tag_sets_id } )
    {
        return $db->find_by_id( 'tag_sets', $tag_sets_id );
    }

    my $tag_set = {
        name        => "controversy_" . $controversy->{ controversies_id } . "_media_types",
        label       => "Media Types for " . $controversy->{ name } . " Controversy",
        description => "These tags are media types specific to the " . $controversy->{ name } . " controversy"
    };

    $tag_set = $db->create( 'tag_sets', $tag_set );

    my $not_typed_tag = {
        tag   => 'Not Typed',
        label => 'Not Typed',
        description =>
          'Choose to indicate that this medium should be typed according to its universal type in this controversy',
        tag_sets_id => $tag_set->{ tag_sets_id }
    };

    $db->create( 'tags', $not_typed_tag );

    $db->query( <<END, $tag_set->{ tag_sets_id }, $controversy->{ controversies_id } );
update controversies set media_type_tag_sets_id = ? where controversies_id = ?
END

    return $tag_set;
}

# add a new media type tag
sub add_media_type : Local
{
    my ( $self, $c, $controversies_id ) = @_;

    my $form = $c->create_form( { load_config_file => $c->path_to() . '/root/forms/admin/cm/controversy_media_type.yml' } );

    my $db = $c->dbis;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id ) || die( "Unable to find controversy" );

    $c->stash->{ controversy } = $controversy;
    $c->stash->{ form }        = $form;
    $c->stash->{ template }    = 'cm/add_media_type.tt2';

    $form->process( $c->request );

    return unless ( $form->submitted_and_valid );

    my $p = $form->params;

    my $tag_set = _find_or_create_controversy_media_type( $db, $controversy );

    my $tag = {
        tag         => $p->{ tag },
        label       => $p->{ label },
        description => $p->{ description },
        tag_sets_id => $tag_set->{ tag_sets_id }
    };

    $db->create( 'tags', $tag );

    my $status_msg = "Media type has been created.";
    $c->res->redirect(
        $c->uri_for( "/admin/cm/edit_media_types/$controversy->{ controversies_id }", { status_msg => $status_msg } ) );
}

# delete a single media type
sub delete_media_type : Local
{
    my ( $self, $c, $tags_id ) = @_;

    my $db = $c->dbis;

    my $tag = $db->find_by_id( 'tags', $tags_id ) || die( "Unable to find tag" );

    my $controversy = $db->query( <<END, $tag->{ tag_sets_id } )->hash;
select * from controversies where media_type_tag_sets_id = ?
END

    die( "Unable to find controversy" ) unless ( $controversy );

    $c->dbis->query( "delete from tags where tags_id = ?", $tags_id );

    my $status_msg = "Media type has been deleted.";
    $c->res->redirect(
        $c->uri_for( "/admin/cm/edit_media_types/$controversy->{ controversies_id }", { status_msg => $status_msg } ) );
}

# edit single controversy media type tag
sub edit_media_type : Local
{
    my ( $self, $c, $tags_id ) = @_;

    my $form = $c->create_form( { load_config_file => $c->path_to() . '/root/forms/admin/cm/controversy_media_type.yml' } );

    my $db = $c->dbis;

    my $tag = $db->find_by_id( 'tags', $tags_id ) || die( "Unable to find tag" );

    my $controversy = $db->query( <<END, $tag->{ tag_sets_id } )->hash;
select * from controversies where media_type_tag_sets_id = ?
END

    die( "Unable to find controversy" ) unless ( $controversy );

    $form->default_values( $tag );
    $form->process( $c->req );

    if ( !$form->submitted_and_valid )
    {
        $c->stash->{ form }        = $form;
        $c->stash->{ controversy } = $controversy;
        $c->stash->{ tag }         = $tag;
        $c->stash->{ template }    = 'cm/edit_media_type.tt2';
        return;
    }

    my $p = $form->params;

    $tag->{ tag }         = $p->{ tag };
    $tag->{ label }       = $p->{ label };
    $tag->{ description } = $p->{ description };

    $c->dbis->update_by_id( 'tags', $tags_id, $tag );

    my $controversies_id = $controversy->{ controversies_id };
    $c->res->redirect(
        $c->uri_for( "/admin/cm/edit_media_types/$controversies_id", { status_msg => 'Media type updated.' } ) );
}

# edit list of controversy specific media types
sub edit_media_types : Local
{
    my ( $self, $c, $controversies_id ) = @_;

    my $db = $c->dbis;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id ) || die( "Unable to find controversy" );

    my $media_types = $db->query( <<END, $controversies_id )->hashes;
select t.* 
    from tags t
        join controversies c on ( c.media_type_tag_sets_id = t.tag_sets_id )
    where 
        c.controversies_id = ? 
    order by t.tag
END

    $c->stash->{ controversy } = $controversy;
    $c->stash->{ media_types } = $media_types;
    $c->stash->{ template }    = 'cm/edit_media_types.tt2';
}

# get a simple count of stories that belong to each partisan media set
sub _get_partisan_counts
{

    my ( $db, $stories_ids ) = @_;

    my $stories_clause = '1=1';
    if ( $stories_ids )
    {
        my $ids_table = $db->get_temporary_ids_table( $stories_ids );
        $stories_clause = "s.stories_id in ( select id from $ids_table )";
    }

    my $query = <<END;
-- partisan collection tags
with partisan_tags as (
    select t.* 
        from
            tags t 
            join tag_sets ts on (t.tag_sets_id = ts.tag_sets_id )
        where
            ts.name = 'collection' and
            t.tag in ( 'partisan_2012_liberal', 'partisan_2012_conservative', 'partisan_2012_libertarian' )
),

-- all stories in the controversy belonging to the media tagged with one of the partisan collection tags
partisan_stories as (
    select s.*, t.*
        from 
            dump_stories s
            join dump_media_tags_map mtm on ( s.media_id = mtm.media_id )
            join dump_tags t on ( mtm.tags_id = t.tags_id )
            join partisan_tags pt on ( t.tags_id = pt.tags_id )
            join dump_tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
        where
            $stories_clause
)

select
        ps.tag,
        ps.label,
        count(*) as num_stories
    from partisan_stories ps
    group by ps.tags_id, ps.tag, ps.label
    order by count(*) desc
END

    return $db->query( $query )->hashes;
}

# various stats about an enumerated list of stories
sub story_stats : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $cdts_id = $c->req->params->{ cdts };
    my ( $cdts, $cd, $controversy ) = _get_controversy_objects( $db, $cdts_id );

    my $title = $c->req->params->{ title };
    my $live  = $c->req->params->{ l };
    my $q     = $c->req->params->{ q };

    my $solr_p = _get_solr_params_for_time_slice_query( $cdts, $q );
    my $stories_ids = MediaWords::Solr::search_for_stories_ids( $db, $solr_p );

    my $num_stories = scalar( @{ $stories_ids } );

    $db->begin;

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, $live );

    my $media_type_stats = _get_media_type_stats_for_time_slice( $db, $stories_ids );
    my $partisan_counts = _get_partisan_counts( $db, $stories_ids );

    # my $partisan_metrics = _get_partisan_link_metrics( $db, $stories_ids );

    $db->commit;

    $c->stash->{ title }            = $title;
    $c->stash->{ cdts }             = $cdts;
    $c->stash->{ controversy_dump } = $cd;
    $c->stash->{ controversy }      = $controversy;
    $c->stash->{ media_type_stats } = $media_type_stats;
    $c->stash->{ partisan_counts }  = $partisan_counts;
    $c->stash->{ num_stories }      = $num_stories;
    $c->stash->{ live }             = $live;
    $c->stash->{ template }         = 'cm/story_stats.tt2';
}

# enqueue a Gearman job which will, in turn, enqueue all controversy's stories
# for Bit.ly processing
sub enqueue_stories_for_bitly : Local
{
    my ( $self, $c, $controversies_id ) = @_;

    unless ( MediaWords::Util::Bitly::bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    my $db = $c->dbis;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id );
    unless ( $controversy )
    {
        die "Controversy $controversies_id was not found";
    }

    unless ( $controversy->{ process_with_bitly } )
    {
        die "Controversy $controversies_id is not set up for Bit.ly processing; please set controversies.process_with_bitly";
    }

    my $args = { controversies_id => $controversies_id };
    my $gearman_job_id = MediaWords::GearmanFunction::Bitly::EnqueueControversyStories->enqueue_on_gearman( $args );
    unless ( $gearman_job_id )
    {
        die "Gearman job didn't return a job ID for controversy ID $controversies_id";
    }

    my $url = $c->uri_for( "/admin/cm/view/$controversies_id",
        { status_msg => "Controversy's stories will soon be enqueued for Bit.ly processing." } );
    $c->res->redirect( $url );
}

# create a controersy_query_slice and associated shell controversy_dump_time_slices
# for the query slice in the latest controversy_dump
sub _create_query_slice
{
    my ( $db, $controversy, $p ) = @_;

    my $query_slice = {
        controversies_id => $controversy->{ controversies_id },
        name             => $p->{ name },
        query            => $p->{ query },
        all_time_slices  => $p->{ all_time_slices } || 0
    };

    my $cqs = $db->create( 'controversy_query_slices', $query_slice );

    my $controversy_dumps = $db->query( <<END, $controversy->{ controversies_id } )->hashes;
select * from controversy_dumps where controversies_id = ?
    order by controversy_dumps_id desc
END

    map { add_periods_to_controversy_dump( $db, $_ ) } @{ $controversy_dumps };

    my $latest_full_dump = get_latest_full_dump_with_time_slices( $db, $controversy_dumps, $controversy );

    my $cdtss = $latest_full_dump->{ controversy_dump_time_slices };
    $cdtss = [ $cdtss->[ 0 ] ] unless ( $cqs->{ all_time_slices } );

    for my $cdts ( @{ $cdtss } )
    {
        delete( $cdts->{ controversy_dump_time_slices_id } );
        delete( $cdts->{ model_reliability } );
        delete( $cdts->{ tag_name } );

        $cdts->{ controversy_query_slices_id } = $cqs->{ controversy_query_slices_id };
        $cdts->{ is_shell }                    = 1;

        $db->create( 'controversy_dump_time_slices', $cdts );
    }
}

# add a new query slice
sub add_query_slice : Local
{
    my ( $self, $c, $controversies_id ) = @_;

    my $form = $c->create_form( { load_config_file => $c->path_to() . '/root/forms/admin/cm/controversy_query_slice.yml' } );

    my $db = $c->dbis;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id ) || die( "Unable to find controversy" );

    $c->stash->{ controversy } = $controversy;
    $c->stash->{ form }        = $form;
    $c->stash->{ template }    = 'cm/add_query_slice.tt2';

    $form->process( $c->request );

    return unless ( $form->submitted_and_valid );

    my $p            = $form->params;
    my $redirect_url = "/admin/cm/edit_query_slices/$controversy->{ controversies_id }";

    my $query_slice = $db->query( <<SQL, $controversies_id, $p->{ name } )->hash;
select * from controversy_query_slices where controversies_id = ? and lower( name ) = lower( ? )
SQL

    if ( $query_slice )
    {
        return $c->res->redirect( $redirect_url, { error_msg => "Slice with the name '$p->{ name }' already exists." } );
    }

    _create_query_slice( $db, $controversy, $p );

    $c->res->redirect( $c->uri_for( $redirect_url, { status_msg => "Query slice has been created." } ) );
}

# delete a single media type
sub delete_query_slice : Local
{
    my ( $self, $c, $controversy_query_slices_id ) = @_;

    my $db = $c->dbis;

    my $cqs = $db->find_by_id( 'controversy_query_slices', $controversy_query_slices_id ) || die( "Slice not found" );

    $db->begin;

    # try to delete all empty shell time slices before deleting the query time slices
    $db->query( <<SQL, $controversy_query_slices_id );
delete from controversy_dump_time_slices where controversy_query_slices_id = ? and is_shell
SQL

    # this will fail and generate an error if there are any non empty time slices, which
    # is fine because the ui shouldn't allow the user to call on a query that has any non-empty time slices
    $db->delete_by_id( "controversy_query_slices", $controversy_query_slices_id );
    $db->commit;

    my $status_msg = "Query slice has been deleted.";
    $c->res->redirect(
        $c->uri_for( "/admin/cm/edit_query_slices/$cqs->{ controversies_id }", { status_msg => $status_msg } ) );
}

# edit list of controversy specific media types
sub edit_query_slices : Local
{
    my ( $self, $c, $controversies_id ) = @_;

    my $db = $c->dbis;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id ) || die( "Unable to find controversy" );

    my $query_slices = $db->query( <<SQL, $controversies_id )->hashes;
select cqs.*,
    exists (
        select 1 
        from controversy_dump_time_slices cdts 
        where
            cdts.controversy_query_slices_id = cqs.controversy_query_slices_id and
            not( cdts.is_shell )
    ) has_non_shell_time_slice
from controversy_query_slices cqs
where controversies_id = ? 
order by name
SQL

    $c->stash->{ controversy }  = $controversy;
    $c->stash->{ query_slices } = $query_slices;
    $c->stash->{ template }     = 'cm/edit_query_slices.tt2';
}

1;
