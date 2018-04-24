#
# Common Media Cloud code
#

FROM mediacloud-base:latest


# Add unprivileged user
RUN \
    useradd -ms /bin/bash mediacloud && \
    echo "SELECTED_EDITOR=/usr/bin/vim.basic" > /home/mediacloud/.selected_editor && \
    echo "mediacloud soft nofile 65536" >> /etc/security/limits.conf && \
    echo "mediacloud hard nofile 65536" >> /etc/security/limits.conf && \
    true
