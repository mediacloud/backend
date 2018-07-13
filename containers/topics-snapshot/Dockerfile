#
# Topic snapshot worker
#

FROM mediacloud-topics-base:latest

# Install dependencies
RUN \
    #
    # GEXF generation
    apt-get -y --no-install-recommends install graphviz && \
    apt-get -y --no-install-recommends install graphviz-dev && \
    apt-get -y --no-install-recommends install libgraphviz-dev && \
    #
    true
