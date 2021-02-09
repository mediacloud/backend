#
# Proxy to RabbitMQ's management webapp
#

FROM gcr.io/mcback/nginx-base:latest

# Copy configuration
COPY nginx/include/rabbitmq-server-webapp-proxy.conf /etc/nginx/include/

# Web server's port
EXPOSE 15672

# Run Nginx
CMD ["nginx"]
