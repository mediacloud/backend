#
# Webapp
#

FROM mediacloud-common:latest

# Install Apache
RUN \
    apt-get -y --no-install-recommends install apache2 && \
    apt-get -y --no-install-recommends install libapache2-mod-fcgid && \
    a2enmod alias && \
    a2enmod env && \
    a2enmod fcgid && \
    a2enmod mime && \
    a2enmod rewrite && \
    true

# Set up logging
RUN \
    rm -f /var/log/apache2/access.log && \
    rm -f /var/log/apache2/error.log && \
    ln -s /proc/1/fd/1 /var/log/access.log && \
    ln -s /proc/1/fd/2 /var/log/error.log && \
    true

# Configure Apache
COPY conf/001-mediacloud.conf /etc/apache2/sites-available/
RUN \
    a2dissite 000-default && \
    a2ensite 001-mediacloud && \
    true

# FIXME
#
# (optional) URL to redirect /login/register page to
#apache2_redirect_login_register_url: https://tools.mediacloud.org/#/user/signup
#
# (optional) URL to redirect /login/forgot page to
#apache2_redirect_login_forgot_url: https://tools.mediacloud.org/#/user/request-password-reset

# Copy static files
RUN mkdir /mediacloud/
COPY src/root/ /mediacloud/root/

# Copy Perl sources
COPY src/perl/ /usr/share/perl5/

# Install Perl dependencies
RUN \
    cd /usr/share/perl5/ && \
    cpanm \
        --mirror "$MEDIACLOUD_PERL_CPAN_MIRROR" \
        --mirror-only \
        --notest \
        --verbose \
        --installdeps \
        . && \
    rm cpanfile && \
    rm -rf /root/.cpanm/ && \
    true

# Session data
RUN mkdir /var/lib/mediacloud-session/
VOLUME /var/lib/mediacloud-session/

# Apache's port
EXPOSE 80

# Run Apache
CMD ["apachectl", "-d", ".", "-f", "/etc/apache2/apache2.conf", "-e", "info", "-DFOREGROUND"]
