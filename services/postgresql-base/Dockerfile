#
# PostgreSQL base
#

FROM mediacloud-base:latest

# Add Add PostgreSQL GPG key
RUN wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

# Add PostgreSQL APT repository
RUN add-apt-repository "deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main"

# Fetch new repositories
RUN apt-get -y update
