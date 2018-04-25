#
# RabbitMQ server
#

FROM mediacloud-base:latest

# Add Erlang Solutions GPG key
RUN wget -qO - https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc | apt-key add -

# Add RabbitMQ GPG key
RUN wget -qO - https://dl.bintray.com/rabbitmq/Keys/rabbitmq-release-signing-key.asc | apt-key add -

# Add Bintray.com GPG key
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 379CE192D401AB61

# Add Erlang Solutions APT repository
# (RabbitMQ > 3.7 requires newer Erlang than is provided by Ubuntu 16.04)
RUN add-apt-repository "deb https://packages.erlang-solutions.com/ubuntu xenial contrib"

# Add RabbitMQ APT repository
RUN add-apt-repository "deb https://dl.bintray.com/rabbitmq/debian xenial main"

# Fetch new repositories
RUN apt-get -y update

# Install RabbitMQ
# (Some Erlang + RabbitMQ combinations have problems (e.g. OOM with many messages), so the version is pinned)
RUN apt-get -y --no-install-recommends install "rabbitmq-server=3.7.3*"

# Copy configuration
COPY --chown=rabbitmq:rabbitmq conf/* /etc/rabbitmq/

# Mnesia database
VOLUME /var/lib/rabbitmq/mnesia/

# Server
EXPOSE 5672

# Web management
EXPOSE 15672

# Run RabbitMQ
COPY bin/rabbitmq.sh /
CMD ["/rabbitmq.sh"]
