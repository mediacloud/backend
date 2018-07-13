#
# Various one-off tools
#

FROM mediacloud-common:latest

# Install dependencies
RUN \
    #
    # Required by Perl::Tidy
    apt-get -y --no-install-recommends install libtidy-dev && \
    #
    true

# Run the tool
# (ENTRYPOINT because the tool's path is to follow)
ENTRYPOINT ["bash", "-c"]
