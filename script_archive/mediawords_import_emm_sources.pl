#!/usr/bin/env perl
#
# Import emm_sources.xml as media sources
#
# Usage: ./mediawords_import_emm_sources.pl --input_file=~/Desktop/emm_sources.xml
#        - or -
#        ./mediawords_import_emm_sources.pl \
#            --input_file=~/Desktop/emm_sources.xml \
#            --collection_tag=europe_media_monitor_20121015
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use utf8;

use XML::TreePP;
use Data::Dumper;
use Getopt::Long;
use Encode;
use MediaWords::DB;
use MediaWords::Util::Tags;

# Strip string from whitespace
sub _strip_string
{
    my $string = shift;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}

# Don't leave spaces in tags, make lowercase too
sub _tagify_string
{
    my $string = shift;
    $string = _strip_string( $string );
    $string =~ s/\s/_/gs;
    $string = lc( $string );
    $string = encode( 'UTF-8', $string );
    return $string;
}

# Stoplist generator
sub main
{
    binmode( STDOUT, ':utf8' );
    binmode( STDERR, ':utf8' );

    my $input_file     = undef;                              # Input file to read emm_sources.xml from
    my $collection_tag = 'europe_media_monitor_20121015';    # Collection tag to add to every medium

    my Readonly $usage = "Usage: $0" . ' --input_file=emm_sources.xml' . ' [--collection_tag=europe_media_monitor_20121015]';

    GetOptions(
        'input_file=s'     => \$input_file,
        'collection_tag:s' => \$collection_tag,
    ) or die "$usage\n";
    die "$usage\n" unless ( $input_file and $collection_tag );

    say STDERR "starting --  " . localtime();

    my $dbis = MediaWords::DB::connect_to_db;

    my $tpp = XML::TreePP->new();
    $tpp->set( utf8_flag => 1 );
    my $tree = $tpp->parsefile( $input_file );

    # Start transaction
    $dbis->begin_work;

    for my $source ( @{ $tree->{ 'sources' }->{ 'source' } } )
    {

        # print 'Source: ' . Dumper($source);

        my @required_arguments = ( '-name', '-url', '-type', '-subject', '-country', '-region', '-category', '-lang' );
        my $skip_source = 0;
        for my $argument ( @required_arguments )
        {
            unless ( $source->{ $argument } )
            {
                print STDERR "Skipping source that does not have a required '$argument' argument: " . Dumper( $source );
                $skip_source = 1;
            }
        }
        if ( $skip_source )
        {
            next;
        }

        my $media_url = encode( 'UTF-8', _strip_string( $source->{ '-url' } ) );

        # Add missing 'http://'
        if ( $media_url !~ /http:\/\//i and $media_url !~ /https:\/\//i and $media_url =~ /www/i )
        {
            $media_url = 'http://' . $media_url;
        }

        # 'hhttp://www.beta.rs/' fix
        if ( $media_url =~ /^hhttp:\/\//i )
        {
            $media_url =~ s/^hhttp:\/\//http:\/\//;
        }

        # "Le Journal Francophone de Budapest | Toute l'actualité hongroise en français" fix
        if ( $media_url =~ /^Le Journal Francophone de Budapest/i )
        {
            $media_url = 'http://www.jfb.hu/';
        }

        my $media_to_add = {
            name        => encode( 'UTF-8', _strip_string( $source->{ '-name' } ) ),
            url         => $media_url,
            moderated   => 'f',
            feeds_added => 'f',
        };
        my $media_tags_to_add = [

            # Blanket tag for emm_sources.xml media
            'collection:' . _tagify_string( $collection_tag ),

            # Additional arguments
            'emm_type:' . _tagify_string( $source->{ '-type' } ),
            'emm_subject:' . _tagify_string( $source->{ '-subject' } ),
            'emm_country:' . _tagify_string( $source->{ '-country' } ),
            'emm_region:' . _tagify_string( $source->{ '-region' } ),
            'emm_category:' . _tagify_string( $source->{ '-category' } ),
            'emm_lang:' . _tagify_string( $source->{ '-lang' } ),
        ];

        # Create / fetch media
        my $medium = undef;
        if (
            $medium = $dbis->query(
                <<"EOF",
            SELECT *
            FROM media
            WHERE name = ? OR url = ?
EOF
                $media_to_add->{ name }, $media_to_add->{ url }
            )->hash
          )
        {
            print STDERR "Using existing medium with duplicate title '" .
              $media_to_add->{ name } . "' or URL '" . $media_to_add->{ url } . "'.\n";
        }
        else
        {
            $medium = $dbis->create( 'media', $media_to_add );
        }

        for my $tag_set_and_tag ( @{ $media_tags_to_add } )
        {

            # Create / fetch tag
            my $tag = MediaWords::Util::Tags::lookup_or_create_tag( $dbis, $tag_set_and_tag );
            unless ( $tag )
            {
                $dbis->rollback;
                die "Unable to create / fetch tag '$tag_set_and_tag'.\n";
            }

            # Map media to a tag
            unless (
                $dbis->find_or_create(
                    'media_tags_map', { tags_id => $tag->{ tags_id }, media_id => $medium->{ media_id } }
                )
              )
            {
                $dbis->rollback;
                die "Unable to assign '$tag_set_and_tag' to media '" .
                  $medium->{ name } . "' (" . $medium->{ media_id } . ").\n";
            }

        }

        print STDERR "Will add / update media '" . $medium->{ name } . "'\n";
    }

    print STDERR "Committing...\n";
    $dbis->commit;

    say STDERR "finished --  " . localtime();
}

main();
