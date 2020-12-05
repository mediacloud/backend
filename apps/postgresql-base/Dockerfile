#
# PostgreSQL base
#

FROM dockermediacloud/base:latest

# Add Add PostgreSQL GPG key
RUN curl -L https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

# Add PostgreSQL APT repository
RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ focal-pgdg main" > /etc/apt/sources.list.d/pgdg.list

# Fetch new repositories
RUN apt-get -y update
