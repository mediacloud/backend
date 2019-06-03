#
# Generate retweet foci
#

FROM dockermediacloud/topics-base:latest

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["topics_generate_retweet_foci.pl"]
