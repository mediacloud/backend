#
# PgBouncer
#

FROM dockermediacloud/mediacloud-postgresql-base:latest

# Install PgBouncer
RUN apt-get -y --no-install-recommends install pgbouncer

# Copy configuration
COPY conf/pgbouncer.ini /etc/pgbouncer/
COPY conf/userlist.txt /etc/pgbouncer/

# Server
EXPOSE 6432

# Copy wrapper script
COPY bin /opt/mediacloud/bin

CMD ["/pgbouncer.sh"]
