package MediaWords::ActionRole::Throttled;

#
# Action role that limits (API) requests
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose::Role;
with 'MediaWords::ActionRole::AbstractAuthenticatedActionRole';
use namespace::autoclean;

use List::MoreUtils qw/ any /;
use HTTP::Status qw(:constants);

use MediaWords::DBI::Auth::Limits;

around execute => sub {

    my $orig = shift;
    my $self = shift;
    my ( $controller, $c ) = @_;

    eval {

        my ( $user_email, $user_roles ) = $self->_user_email_and_roles( $c );
        unless ( $user_email and $user_roles )
        {
            $c->response->status( HTTP_FORBIDDEN );
            die $MediaWords::ActionRole::AbstractAuthenticatedActionRole::INVALID_API_KEY_MESSAGE;
        }

        # Admin users are effectively unlimited
        my $roles_exempt_from_user_limits   = MediaWords::DBI::Auth::Limits::roles_exempt_from_user_limits();
        my $user_is_exempt_from_user_limits = 0;

        foreach my $exempt_role ( @{ $roles_exempt_from_user_limits } )
        {
            if ( any { $_ eq $exempt_role } @{ $user_roles } )
            {
                $user_is_exempt_from_user_limits = 1;
                last;
            }
        }

        unless ( $user_is_exempt_from_user_limits )
        {

            # Fetch limits
            my $limits = $c->dbis->query(
                <<EOF,
                SELECT auth_users.auth_users_id,
                       auth_users.email,
                       weekly_requests_limit,
                       weekly_requested_items_limit,
                       weekly_requests_sum,
                       weekly_requested_items_sum

                FROM auth_users
                    INNER JOIN auth_user_limits
                        ON auth_users.auth_users_id = auth_user_limits.auth_users_id,
                    auth_user_limits_weekly_usage( \$1 )

                WHERE auth_users.email = \$1
                LIMIT 1
EOF
                $user_email
            )->hash;

            die( "no limits found for user" ) unless ( $limits );

            my $weekly_requests_limit        = ( $limits->{ weekly_requests_limit }        // 0 ) + 0;
            my $weekly_requested_items_limit = ( $limits->{ weekly_requested_items_limit } // 0 ) + 0;
            my $weekly_requests_sum          = ( $limits->{ weekly_requests_sum }          // 0 ) + 0;
            my $weekly_requested_items_sum   = ( $limits->{ weekly_requested_items_sum }   // 0 ) + 0;

            my $throttled_message = <<END;
You have exceeded your quota of requests or stories. Please contact
info\@mediacloud.org with quota questions.
END

            if ( $weekly_requests_limit > 0 )
            {
                if ( $weekly_requests_sum >= $weekly_requests_limit )
                {
                    $c->response->status( HTTP_TOO_MANY_REQUESTS );
                    die "User exceeded weekly requests limit of $weekly_requests_limit. $throttled_message";
                }
            }

            if ( $weekly_requested_items_limit > 0 )
            {
                if ( $weekly_requested_items_sum >= $weekly_requested_items_limit )
                {
                    $c->response->status( HTTP_TOO_MANY_REQUESTS );
                    die
"User exceeded weekly requested items (stories) limit of $weekly_requested_items_limit. $throttled_message";
                }
            }
        }
    };

    if ( $@ )
    {
        my $message = $@;

        push( @{ $c->stash->{ auth_errors } }, $message );
        $c->detach();
        return undef;
    }

    return $self->$orig( @_ );
};

1;
