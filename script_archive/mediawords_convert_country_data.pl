#!/usr/bin/env perl                                                                                                                                                                             

# for a tag_set of countries, coonvert each tag into a country code and each label into a country name,
# starting with tags that are either country names or codes

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Locale::Country::Multilingual;

use MediaWords::DB;

my $_lcm = Locale::Country::Multilingual->new();

my $_country_transforms = {
    'bosnia herzegovina'           => 'bosnia and herzegovina',
    'brunei'                       => 'brunei darussalam',
    'd.r. of congo'                => 'Congo, The Democratic Republic of the',
    'hong kong (china)'            => 'hong kong',
    'laos'                         => 'Lao People\'s Democratic Republic',
    'myanmar (burma)'              => 'myanmar',
    'palestine'                    => 'palestinian territory, occupied',
    'puerto rico (u.s.)'           => 'puerto rico',
    'republic of congo'            => 'congo',
    'st. vincent & the grenadines' => 'Saint Vincent and the Grenadines',
    'taiwan (roc)'                 => 'taiwan',
    'trinidad & tobago'            => 'trinidad and tobago',
    'u.s.a.'                       => 'united states',
    'us virgin islands'            => 'Virgin Islands, U.S.',
};

sub country2code
{
    my ( $country ) = @_;

    $country =~ s/_/ /g;
    $country = lc( $country );

    $country = lc( $_country_transforms->{ $country } ) if ( $_country_transforms->{ $country } );

    my $code = ( length( $country ) > 3 ) ? $_lcm->country2code( $country ) : $country;

    warn( "no code found for '$country'" ) unless ( $code );

    return uc( $code );
}

sub code2country
{
    my ( $code ) = @_;

    return 'None' if ( $code eq 'XX' );

    my $country = $_lcm->code2country( $code );

    warn( "no country found for '$code'" ) unless ( $country );

    return $country;
}

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my $tags = $db->query( <<END )->hashes;
    select t.*
        from tags t join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
        where ts.name in ( 'gv_country', 'emm_country' )
        order by ts.name, t.tag
END

    my $lcm = Locale::Country::Multilingual->new();

    for my $tag ( @{ $tags } )
    {
        my $code    = country2code( $tag->{ tag } );
        my $country = code2country( $code );

        if ( $code && $country )
        {
            $db->query( <<END, $code, $country, $tag->{ tags_id } );
update tags set tag = ?, label = ?, show_on_media = 't' where tags_id = ?
END

            print STDERR "$code / $country\n";
        }
    }
}

main();
