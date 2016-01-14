#
# Set S3 credentials from environment variables (set by Travis)
#

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

            $config->{ amazon_s3 }->{ test }->{ access_key_id }     = $ENV{ 'MC_AMAZON_S3_TEST_ACCESS_KEY_ID' };
            $config->{ amazon_s3 }->{ test }->{ secret_access_key } = $ENV{ 'MC_AMAZON_S3_TEST_SECRET_ACCESS_KEY' };
            $config->{ amazon_s3 }->{ test }->{ bucket_name }       = $ENV{ 'MC_AMAZON_S3_TEST_BUCKET_NAME' };
            $config->{ amazon_s3 }->{ test }->{ directory_name }    = $ENV{ 'MC_AMAZON_S3_TEST_DIRECTORY_NAME' };

            # FIXME Awful trick to modify config's cache
            $MediaWords::Util::Config::_config = $config;
        }
    }
}

1;
