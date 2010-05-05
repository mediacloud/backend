package MediaWords::Controller::Media;

use Encode;
use strict;
use warnings;
use base 'Catalyst::Controller';

use MediaWords::Util::Tags;
use MediaWords::Util::Web;

use Regexp::Common qw /URI/;
use YAML::Syck;
use Text::Trim;

use constant ROWS_PER_PAGE => 25;

sub make_edit_form
{
    my ( $self, $c, $action ) = @_;

    my $form = HTML::FormFu->new(
        {
            load_config_file => $c->path_to() . '/root/forms/media.yml',
            method           => 'POST',
            action           => $action
        }
    );

    $form->stash->{c} = $c;

    $form->process( $c->request );

    return $form;
}

sub create : Local
{
    my ( $self, $c ) = @_;

    $c->stash->{template} = 'media/create.tt2';
}

sub create_batch : Local
{
    my ( $self, $c ) = @_;

    $c->stash->{template} = 'media/create_batch.tt2';
}

sub find_by_url
{
    my ( $self, $c, $url ) = @_;

    my $result = $c->dbis->query( "select * from media where url = ?", $url )->hash();

    print STDERR "URL: $url\n";

    if ( !$result )
    {
        if ( $url =~ /.*[^\/]$/ )
        {
            $url .= "/";
        }
        else
        {
            chop($url);
        }

        print STDERR "URL inverted: '$url'\n";

        $result = $c->dbis->query( "select * from media where url = ?", $url )->hash();
    }
    else
    {
        print STDERR "URL found\n";
    }

    return $result;
}

# for each url in $urls, either find the medium associated with that
# url or the medium assocaited with the title from the given url or,
# if no medium is found, a newly created medium.  Return the list of
# all found or created media along with a list of error messages for the process.
sub find_or_create_media_from_urls
{
    my ( $self, $c, $urls ) = @_;

    print STDERR "find_or_create_media_from_urls\n";

    my $media         = [];
    my $messages      = [];
    my $fetch_urls    = [];
    my $url_to_medium = {};

    for my $url ( map { lc($_) } @{$urls} )
    {

        if ( !( $url =~ /$RE{URI}/ ) )
        {
            $url = "http://$url";
        }

        if ( !( $url =~ /$RE{URI}/ ) )
        {
            push( @{$messages}, "$url is not a url" );
        }
        elsif ( my $medium = $self->find_by_url( $c, $url ) )
        {
            push( @{$media}, $medium );
        }
        else
        {
            push( @{$fetch_urls}, $url );
        }
    }

    my $responses = MediaWords::Util::Web::ParallelGet($fetch_urls);
    for my $response ( @{$responses} )
    {
        my $url = $response->request->url;

        my $original_response = $response;

        while ( $original_response->previous )
        {
            $original_response = $original_response->previous;
        }

        my $original_url = $original_response->request->url;

        if ( !$response->is_success )
        {

            my $error_message = "Unable to fetch medium url '$url' " . ( $response->status_line );

            if ( $response->status_line eq '403 Bad Behavior' )
            {
                $error_message = "Bad Behavior blocks url '$url'";
            }

            push( @{$messages}, $error_message );

            next;
        }

        my $content = $response->content;

        $content = encode( "utf-8", $content );

        my ($title) = ( $content =~ /<title>(.*?)<\/title>/is );
        $title = trim($title);
        $title = substr( $title, 0, 127 );
        $title ||= $url;
        $title = trim($title);
        $title =~ s/\s+/ /g;

        my $medium = $self->find_by_url( $c, $url );    #search for the redirected URL

        if ( !$medium )
        {
            if ( $c->dbis->query( "select * from media where name = ?", $title )->hash )
            {
                my $error_message = "duplicate title $title found in database for $original_url";
                push( @{$messages}, $error_message );
                next;
            }
            else
            {
                $medium = $c->dbis->create( 'media', { name => $title, url => $url } );
            }
        }

        push( @{$media}, $medium );

        $url_to_medium->{$original_url} = $medium;
    }

    print STDERR "find_or_create_media_from_urls returning with messages: ";
    print STDERR @$messages;

    print STDERR "\n";

    return ( $media, $messages, $url_to_medium );
}

sub create_do : Local
{
    my ( $self, $c ) = @_;

    my $urls = [ map { $_ =~ s/[\n\r\s]//g; lc($_) } split( "\n", $c->request->param('urls') ) ];

    my ( $media, $messages ) = $self->find_or_create_media_from_urls( $c, $urls );

    my $status_msg = join( "\n", @{$messages} );

    if ( @{$media} )
    {
        $c->response->redirect(
            $c->uri_for(
                '/media/batch_edit_tags/' . join( '/', map { $_->{media_id} } @{$media} ),
                { status_msg => $status_msg }
            )
        );
    }
    else
    {
        $c->response->redirect(
            $c->uri_for( '/media/create', { status_msg => 'No media sources created: ' . $status_msg } ) );
    }
}

sub create_with_tags_do : Local
{
    my ( $self, $c ) = @_;

    print STDERR "START: create_with_tags_do\n";

    my $media_source_strings = [ map { $_ =~ s/$[\n\r\s]*//; lc($_) } split( "\n", $c->request->param('urls') ) ];

    my @media_list;

    my @already_existing_pages;

    my @existing_urls;

    foreach my $media_source_string (@$media_source_strings)
    {
        my ( $url_string, $tags_string ) = split( /\s+/, $media_source_string, 2 );

        print STDERR "url_string: $url_string, tags_string: $tags_string \n";
        my @tags = split( /\s*,\s*/, $tags_string, 0 );

        my $medium = $self->find_by_url( $c, $url_string );
        if ($medium)
        {
            print STDERR "Found existing media: " . $url_string . "\n";
            push @existing_urls, $url_string;
        }

        push @media_list, [ $url_string, \@tags, $medium ];
    }

    my @urls_to_create;

    foreach my $media_source_info (@media_list)
    {
        if ( !$media_source_info->[2] )
        {
            push @urls_to_create, $media_source_info->[0];
        }
    }

    my ( $media, $messages, $url_to_medium_map ) = $self->find_or_create_media_from_urls( $c, \@urls_to_create );
    my $retry_download = 0;

    foreach my $media_source_info (@media_list)
    {
        if ( !$media_source_info->[2] )
        {
            $media_source_info->[2] =
              $url_to_medium_map->{ $media_source_info->[0] };    # $self->find_by_url( $c, $media_source_info->[0] );
        }

        #TODO remove this block with retry_download is always going to false
        if ( $retry_download && ( !$media_source_info->[2] ) )
        {

            my ( $tmp_media_list, $messages_tmp ) = $self->find_or_create_media_from_urls( $c, [ $media_source_info->[0] ] );

            $media_source_info->[2] = pop @$tmp_media_list;

            if ( !defined $media_source_info->[2] )
            {
                push @{$messages}, "media info not found for:  $media_source_info->[0]";
            }
            else
            {
                push @{$messages}, @{$messages_tmp};
            }
        }
    }

    print STDERR "Messages: ";
    print STDERR @{$messages};
    print STDERR "\n";

    foreach my $media_source_info (@media_list)
    {

        #        print STDERR join ":", @{$media_source_info};
        #        print STDERR "\n";
        if ( !defined( $media_source_info->[2] ) )
        {
            next;
        }

        my $media_source_messages      = [];
        my $media_source_messages_good = [];

        my $media_id = $media_source_info->[2]->{media_id};
        foreach my $tags ( $media_source_info->[1] )
        {
            foreach my $tag_string (@$tags)
            {
                my ( $tag_set, $tag_name ) = split ":", $tag_string;

                print STDERR '($tag_set, $tag_name) ' . "($tag_set, $tag_name)\n";

                if ( !( $tag_set && $tag_name ) )
                {
                    push @{$media_source_messages}, "invalid tag string $tag_string";
                    next;
                }

                my $tag_sets_id = $self->getTagSetId( $c, $tag_set, $media_source_messages );

                if ( !defined($tag_sets_id) )
                {
                    next;
                }

                my $tags_id = $self->findOrCreateTagId( $c, $tag_sets_id, $tag_name, $media_source_messages );

                defined($tags_id) || die "could not find tag $tag_name in $tag_set";

                my $media_tag =
                  $c->dbis->query( "select * from media_tags_map where tags_id = ? and media_id = ?", $tags_id, $media_id )
                  ->fetch;
                if ( !$media_tag )
                {
                    $c->dbis->create( 'media_tags_map', { tags_id => $tags_id, media_id => $media_id } );
                    push @{$media_source_messages_good}, "added tag $tag_string";
                }
            }
        }

        if ( !( @{$media_source_messages} ) )
        {
            push @{$messages}, "Successfully Added/Updated: $media_source_info->[0]";
        }

        foreach my $mesg ( @{$media_source_messages_good} )
        {
            push @{$messages}, "$media_source_info->[0]: " . $mesg;
        }

        foreach my $mesg ( @{$media_source_messages} )
        {
            push @{$messages}, "$media_source_info->[0]: " . $mesg;
        }
    }

    my $status_msg = join "\n", @{$messages};

    $status_msg =~ s/\n+/\n/g;

    print STDERR "status_msg: $status_msg\n";

    $c->flash->{url_list} = $c->request->param('urls');

    $c->flash->{results} = $status_msg;

    $c->response->redirect( $c->uri_for('/media/create_batch') );
}

sub findOrCreateTagId
{
    my ( $self, $c, $tag_sets_id, $tag_name ) = @_;

    return $c->dbis->find_or_create( 'tags', { tag => $tag_name, tag_sets_id => $tag_sets_id } )->{tags_id};
}

sub getTagSetId
{
    my ( $self, $c, $tag_set_name, $messages ) = @_;

    my $tag_set = $c->dbis->query( "select * from tag_sets where name = ?", $tag_set_name )->hash;

    if ( !defined($tag_set) )
    {
        push @{$messages}, "tag_set $tag_set_name not found";
        return;
    }

    my $tag_sets_id = $tag_set->{tag_sets_id};

    print STDERR "tag_sets_id: $tag_sets_id\n";
    return $tag_sets_id;
}

sub edit : Local
{
    my ( $self, $c, $id ) = @_;

    $id += 0;

    my $form = $self->make_edit_form( $c, $c->uri_for("/media/edit_do/$id") );

    my $medium = $c->dbis->find_by_id( 'media', $id );

    $form->default_values($medium);

    $c->stash->{form}     = $form;
    $c->stash->{template} = 'media/edit.tt2';
    $c->stash->{title}    = 'Edit Media Source';
}

sub edit_do : Local
{
    my ( $self, $c, $id ) = @_;

    my $form = $self->make_edit_form( $c, $c->uri_for("/media/edit_do/$id") );
    my $medium = $c->dbis->find_by_id( 'media', $id );

    if ( !$form->submitted_and_valid )
    {
        $c->stash->{form}     = $form;
        $c->stash->{template} = 'media/edit.tt2';
        $c->stash->{title}    = 'Edit Media Source';
    }
    else
    {
        $c->dbis->update_by_id( 'media', $id, $form->params );

        $c->response->redirect(
            $c->uri_for( '/feeds/list/' . $medium->{media_id}, { status_msg => 'Media source updated.' } ) );
    }
}

sub delete : Local
{
    my ( $self, $c, $id, $confirm ) = @_;

    my $media = $c->dbis->find_by_id( 'media', $id );

    my $status_msg;

    my ($deleteme_tags_id) =
      $c->dbis->query( "select tags_id from tags t, tag_sets ts "
          . "where t.tag_sets_id = ts.tag_sets_id and "
          . "t.tag = 'deleteme' and ts.name = 'workflow'" )->flat;

    my ($marked_for_deletion) =
      $c->dbis->query( "select 1 from media_tags_map " . "where tags_id = $deleteme_tags_id and media_id = ?", $id )->flat;

    if ($marked_for_deletion)
    {
        $status_msg = 'Medium already marked for deletion.';
        $c->response->redirect( $c->uri_for( "/media/list", { status_msg => $status_msg } ) );
    }
    elsif ( !defined($confirm) )
    {
        $c->stash->{medium}   = $media;
        $c->stash->{template} = 'media/delete.tt2';
    }
    else
    {
        if ( $confirm ne 'yes' )
        {
            $status_msg = 'Media source NOT marked for deletion.';
        }
        else
        {
            $c->dbis->query( "insert into media_tags_map (tags_id, media_id) values (?, ?)", $deleteme_tags_id, $id );
            $status_msg = 'Media source marked for deletion.';
        }

        $c->response->redirect( $c->uri_for( '/media/list', { status_msg => $status_msg } ) );
    }
}

# search for media matching search for the given keyword
# return the matching media from the given page along with a
# Data::Page object for the results
sub search_paged_media
{
    my ( $self, $c, $q, $page, $rows_per_page ) = @_;

    $q =~ s/^\s+//g;
    $q =~ s/\s+$//g;
    $q =~ s/'/''/g;

    $q = $c->dbis->dbh->quote( lc("%$q%") );

    return $c->dbis->query_paged_hashes(
"select distinct m.media_id as media_id, m.name as name, m.url as url from media m left join ( media_tags_map mtm join (tags t join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id) ) on ( mtm.tags_id = t.tags_id) ) on (m.media_id = mtm.media_id) where (m.name like $q or m.url like $q or lower(ts.name||':'||t.tag) like $q) order by m.name",
        $page, $rows_per_page
    );
}

# display search form, and results of a query was submitted.
sub search : Local
{
    my ( $self, $c ) = @_;

    my $form = HTML::FormFu->new(
        {
            load_config_file => $c->path_to() . '/root/forms/media_search.yml',
            method           => 'GET',
            action           => ''
        }
    );

    $form->process( $c->request );

    my $p = $c->request->param('p') || 1;
    my $q = $c->request->param('q');
    my $f = $c->request->param('f');
    my @m = $c->request->param('m');

    my ( $media, $pager );

    if ($q)
    {
        ( $media, $pager ) = $self->search_paged_media( $c, $q, $p, ROWS_PER_PAGE );
    }
    elsif ($f)
    {
        ( $media, $pager ) = $c->dbis->query_paged_hashes(
            "select * from media m "
              . "where not exists (select 1 from feeds f where f.media_id = m.media_id) "
              . "order by media_id desc",
            $p, ROWS_PER_PAGE
        );
    }
    elsif (@m)
    {
        $media = $c->dbis->query( "select * from media where media_id in (??) order by name", @m )->hashes;
    }
    else
    {
        ( $media, $pager ) = $c->dbis->query_paged_hashes( "select * from media order by name", $p, ROWS_PER_PAGE );
    }

    for my $m ( @{$media} )
    {
        $m->{tag_names} = $c->dbis->query(
            "select ts.name||':'||t.tag from tags t, media_tags_map mtm, tag_sets ts "
              . "where t.tags_id = mtm.tags_id and t.tag_sets_id = ts.tag_sets_id and mtm.media_id = ?",
            $m->{media_id}
        )->flat;
        ( $m->{feed_count} ) = $c->dbis->query( "select count(*) from feeds where media_id = ?", $m->{media_id} )->flat;
    }

    $c->stash->{media}     = $media;
    $c->stash->{pager}     = $pager;
    $c->stash->{pager_url} = $c->uri_for( '/media/search', { q => $q, m => \@m, f => $f } );

    $c->stash->{q}        = $q;
    $c->stash->{form}     = $form;
    $c->stash->{template} = 'media/search.tt2';
}

# alias for search
sub list : Local
{
    my $self = shift(@_);
    return $self->search(@_);
}

sub edit_tags : Local
{
    my ( $self, $c, $media_id ) = @_;

    if ( !$media_id )
    {
        die("no media_id");
    }

    my $medium = $c->dbis->find_by_id( 'media', $media_id );
    if ( !$medium )
    {
        die("Unable to find medium $media_id");
    }

    my $action = $c->uri_for( '/media/edit_tags_do/' . $media_id );

    my $form = MediaWords::Util::Tags->make_edit_tags_form( $c, $action, $media_id, 'media' );

    $c->stash->{form}     = $form;
    $c->stash->{medium}   = $medium;
    $c->stash->{template} = 'media/edit_tags.tt2';
}

sub edit_tags_do : Local
{
    my ( $self, $c, $media_id ) = @_;

    if ( !$media_id )
    {
        die("no media_id");
    }

    my $medium = $c->dbis->find_by_id( 'media', $media_id );
    if ( !$medium )
    {
        die("Unable to find medium $media_id");
    }

    my $action = $c->uri_for('/media/edit_tags_do/') . $media_id;
    my $form = MediaWords::Util::Tags->make_edit_tags_form( $c, $action, $media_id, 'media' );

    if ( !$form->submitted_and_valid )
    {
        return $self->edit_tags( $c, $media_id );
    }

    MediaWords::Util::Tags->save_tags( $c, $media_id, 'media' );

    $c->response->redirect( $c->uri_for( "/feeds/list/" . $media_id, { status_msg => 'Tags updated.' } ) );
}

sub batch_edit_tags : Local
{
    my ( $self, $c, @media_ids ) = @_;

    if ( !@media_ids )
    {
        die("no media_ids");
    }

    my @media = $c->dbis->query( "select * from media where media_id in (??) order by name asc", @media_ids )->hashes;

    my $action = $c->uri_for( '/media/batch_edit_tags_do/' . join( '/', @media_ids ) );

    my $form = MediaWords::Util::Tags->make_edit_tags_form( $c, $action, undef, 'media' );

    $c->stash->{media}    = \@media;
    $c->stash->{form}     = $form;
    $c->stash->{template} = 'media/batch_edit_tags.tt2';
}

sub batch_edit_tags_do : Local
{
    my ( $self, $c, @media_ids ) = @_;

    if ( !@media_ids )
    {
        die("no media_ids");
    }

    for my $media_id (@media_ids)
    {
        MediaWords::Util::Tags->save_tags( $c, $media_id, 'media', 1 );
    }

    $c->response->redirect( $c->uri_for( "/media/list", { m => \@media_ids, status_msg => 'Tags updated.' } ) );
}

=head1 AUTHOR

Hal Roberts

=head1 LICENSE

GPL

=cut

1;
