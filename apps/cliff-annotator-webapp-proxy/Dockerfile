#
# Proxy to CLIFF annotator, roundrobins between cliff-annotator instances
#

FROM gcr.io/mcback/nginx-base:latest

# Copy configuration
COPY nginx/include/cliff-annotator-webapp-proxy.conf /etc/nginx/include/

# Web server's port
EXPOSE 8080

# Run Nginx
CMD ["nginx"]
