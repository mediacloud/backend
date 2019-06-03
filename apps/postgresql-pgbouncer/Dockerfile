#
# PgBouncer
#

FROM dockermediacloud/postgresql-base:latest

# Install PgBouncer
RUN apt-get -y --no-install-recommends install pgbouncer

# Copy configuration
COPY conf/pgbouncer.ini /etc/pgbouncer/
COPY conf/userlist.txt /etc/pgbouncer/

# Server
EXPOSE 6432

# Copy wrapper script
COPY bin/pgbouncer.sh /

# No USER because wrapper script will run service as "postgres" itself

CMD ["/pgbouncer.sh"]
