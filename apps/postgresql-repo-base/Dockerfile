#
# PostgreSQL repository base
#

FROM gcr.io/mcback/base:latest

RUN \
    #
    # Add Add PostgreSQL GPG key
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
    #
    # Add PostgreSQL APT repository
    echo "deb http://apt.postgresql.org/pub/repos/apt/ focal-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list && \
    #
    # Fetch new repositories
    apt-get -y update && \
    #
    true
