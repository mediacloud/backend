#
# PgBouncer
#

FROM dockermediacloud/mediacloud-postgresql-base:latest

# Install PgBouncer
RUN apt-get -y --no-install-recommends install pgbouncer

# Copy configuration
COPY conf/pgbouncer.ini /etc/pgbouncer/

# Server
EXPOSE 6432

CMD ["sudo", "su", "-", "postgres", "/bin/bash", "-c", "/usr/sbin/pgbouncer -v /etc/pgbouncer/pgbouncer.ini"]
