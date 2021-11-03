#
# Proxy to Solr's management webapp
#

FROM mc2021/nginx-base:latest

# Copy configuration
COPY nginx/include/solr-shard-webapp-proxy.conf /etc/nginx/include/

# Web server's port
EXPOSE 8983

# Run Nginx
CMD ["nginx"]
