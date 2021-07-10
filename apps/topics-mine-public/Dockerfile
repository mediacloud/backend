#
# Mine public topic worker
#

FROM mc2021/topics-mine:latest

# Copy worker script
COPY bin /opt/mediacloud/bin

USER mediacloud

CMD ["topics_mine_public_worker.pl"]
