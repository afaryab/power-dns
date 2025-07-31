FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies and PowerDNS repo
RUN apt-get update && \
    apt-get install -y curl lsb-release gnupg mysql-client && \
    curl -fsSL https://repo.powerdns.com/FD380FBB-pub.asc | gpg --dearmor -o /usr/share/keyrings/pdns-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/pdns-archive-keyring.gpg arch=amd64] http://repo.powerdns.com/ubuntu $(lsb_release -cs)-auth-47 main" > /etc/apt/sources.list.d/pdns.list && \
    apt-get update && \
    apt-get install -y pdns-server pdns-backend-mysql && \
    rm -rf /var/lib/apt/lists/*

# Expose DNS and webserver ports
EXPOSE 53/udp 53/tcp 8081

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
