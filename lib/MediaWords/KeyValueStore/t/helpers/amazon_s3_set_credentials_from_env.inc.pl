#
# Set S3 credentials from environment variables (set by Travis)
#

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;

sub set_amazon_s3_test_credentials_from_env_if_needed()
{
    my $config = MediaWords::Util::Config::get_config;

    unless ( defined( $config->{ amazon_s3 }->{ test } ) )
    {
        if (    defined $ENV{ 'MC_AMAZON_S3_TEST_ACCESS_KEY_ID' }
            and defined $ENV{ 'MC_AMAZON_S3_TEST_SECRET_ACCESS_KEY' }
            and defined $ENV{ 'MC_AMAZON_S3_TEST_BUCKET_NAME' }
            and defined $ENV{ 'MC_AMAZON_S3_TEST_DIRECTORY_NAME' } )
        {
            my $new_config = make_python_variable_writable( $config );

            $new_config->{ amazon_s3 }->{ test }->{ access_key_id }     = $ENV{ 'MC_AMAZON_S3_TEST_ACCESS_KEY_ID' };
            $new_config->{ amazon_s3 }->{ test }->{ secret_access_key } = $ENV{ 'MC_AMAZON_S3_TEST_SECRET_ACCESS_KEY' };
            $new_config->{ amazon_s3 }->{ test }->{ bucket_name }       = $ENV{ 'MC_AMAZON_S3_TEST_BUCKET_NAME' };
            $new_config->{ amazon_s3 }->{ test }->{ directory_name }    = $ENV{ 'MC_AMAZON_S3_TEST_DIRECTORY_NAME' };

            MediaWords::Util::Config::set_config( $new_config );
        }
    }
}

1;
