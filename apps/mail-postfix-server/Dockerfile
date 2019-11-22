#
# Postfix server
#

FROM dockermediacloud/base:latest

# Install packages
RUN \
    #
    # Remove ssmtp (not compatible with Postfix)
    apt-get -y remove ssmtp && \
    #
    # Install Postfix
    apt-get -y --no-install-recommends install postfix && \
    #
    # Create directories for storing Postfix's data and mail queue && \
    mkdir -p /var/lib/postfix/data/ && \
    mv /var/spool/postfix/ /var/lib/postfix/queue/ && \
    chown -R postfix:postfix /var/lib/postfix/ && \
    true

# Configure Postfix
RUN \
    #
    # Set custom data and queue directories
    postconf -e data_directory=/var/lib/postfix/data/ && \
    postconf -e queue_directory=/var/lib/postfix/queue/ && \
    #
    # Configure OpenDKIM
    postconf -e milter_protocol=2 && \
    postconf -e milter_default_action=accept && \
    postconf -e smtpd_milters=inet:mail-opendkim-server:12301 && \
    postconf -e non_smtpd_milters=inet:mail-opendkim-server:12301 && \
    #
    # Relay all emails with a non-localhost destination
    postconf -e mydestination=localhost && \
    #
    # Disable IPv6
    postconf -e inet_protocols=ipv4 && \
    #
    # Accept email from Docker network
    postconf -e mynetworks=10.1.0.1/16 && \
    #
    # Don't require TLS as local clients are trusted
    postconf -e smtp_tls_security_level=may && \
    postconf -e smtpd_tls_security_level=none && \
    #
    # Disable chroot on all services as it doesn't play well with a mounted
    # volume, e.g. "smtpd" is unable to access libnss after a chroot and thus
    # resolve OpenDKIM container.
    #
    # We should be mostly fine running Postfix utilities without chroot as:
    #
    # 1) Container itself is essentialy a chroot of sorts;
    # 2) It's only other (trusted) containers that can access Postfix.
    #
    # =================================================================================================
    #                            service   type  private unpriv  chroot  wakeup  maxproc command + args
    #                                            (yes)   (yes)   (no)    (never) (100)
    # =================================================================================================
    postconf -M smtp/inet="      smtp      inet  n        -      n       -       -       smtpd"             && \
    postconf -M pickup/unix="    pickup    unix  n       -       n       60      1       pickup"            && \
    postconf -M cleanup/unix="   cleanup   unix  n       -       n       -       0       cleanup"            && \
    postconf -M tlsmgr/unix="    tlsmgr    unix  -        -      n       1000?   1       tlsmgr"            && \
    postconf -M rewrite/unix="   rewrite   unix  -        -      n       -       -       trivial-rewrite"   && \
    postconf -M bounce/unix="    bounce    unix  -        -      n       -       0       bounce"            && \
    postconf -M defer/unix="     defer     unix  -        -      n       -       0       bounce"            && \
    postconf -M trace/unix="     trace     unix  -        -      n       -       0       bounce"            && \
    postconf -M verify/unix="    verify    unix  -       -       n       -       1       verify"            && \
    postconf -M flush/unix="     flush     unix  n        -      n       1000?   0       flush"             && \
    postconf -M smtp/unix="      smtp      unix  -        -      n       -       -       smtp"              && \
    postconf -M relay/unix="     relay     unix  -        -      n       -       -       smtp"              && \
    postconf -M showq/unix="     showq     unix  n        -      n       -       -       showq"             && \
    postconf -M error/unix="     error     unix  -        -      n       -       -       error"             && \
    postconf -M retry/unix="     retry     unix  -        -      n       -       -       error"             && \
    postconf -M discard/unix="   discard   unix  -        -      n       -       -       discard"           && \
    postconf -M lmtp/unix="      lmtp      unix  -        -      n       -       -       lmtp"              && \
    postconf -M anvil/unix="     anvil     unix  -        -      n       -       1       anvil"             && \
    postconf -M scache/unix="    scache    unix  -        -      n       -       1       scache"            && \
    #
    true

# Postfix data and queue directory
VOLUME /var/lib/postfix/

# SMTP port
EXPOSE 25

# Copy wrapper script
COPY bin/postfix.sh /

# No USER because daemon will demote itself to "postfix" user itself

CMD ["/postfix.sh"]
