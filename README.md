# PowerDNS + MariaDB Docker Compose

This project provides a ready-to-use Docker Compose setup for running PowerDNS Authoritative Server with a MariaDB backend. It also supports persistent storage and can be easily integrated with Traefik as a reverse proxy for the PowerDNS web API.

## Features
- PowerDNS Authoritative Server (with MySQL backend)
- MariaDB for DNS data storage
- Persistent volumes for database and configuration
- Example Traefik integration

## Usage

### 1. Clone the repository
```sh
git clone https://github.com/afaryab/power-dns.git
cd power-dns
```

### 2. Build and start the stack
```sh
docker-compose up --build
```

- PowerDNS DNS: UDP/TCP 53
- PowerDNS Web API: http://localhost:8081/

### 3. Persistent Data
- MariaDB data is stored in `./mysql`
- PowerDNS config is stored in `./conf`

## Configuration

### Environment Variables
You can customize PowerDNS and MariaDB settings using environment variables. Create a `.env` file or set them directly in `docker-compose.yml`:

```bash
# MariaDB Configuration
MYSQL_ROOT_PASSWORD=root_pass
MYSQL_DATABASE=pdns
MYSQL_USER=pdns
MYSQL_PASSWORD=pdns_pass

# PowerDNS Configuration
PDNS_API_KEY=changeme
PDNS_WEBSERVER_PORT=8081
PDNS_WEBSERVER_ADDRESS=0.0.0.0
PDNS_WEBSERVER_ALLOW_FROM=0.0.0.0/0
```

### 4. Customizing PowerDNS
Edit the `.env` file to change database credentials, API key, or webserver settings. The entrypoint script will automatically configure PowerDNS with these values.

## Example: Docker Compose with Traefik
Below is a sample `docker-compose.traefik.yml` for running PowerDNS behind Traefik:

```yaml
version: '3.8'
services:
  powerdns:
    build: .
    container_name: powerdns
    ports:
      - "53:53/udp"
      - "53:53/tcp"
    volumes:
      - ./mysql:/var/lib/mysql
      - ./conf:/etc/powerdns
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.powerdns.rule=Host(`pdns.localhost`)"
      - "traefik.http.routers.powerdns.entrypoints=web"
      - "traefik.http.services.powerdns.loadbalancer.server.port=8081"

  traefik:
    image: traefik:v2.11
    command:
      - --api.insecure=true
      - --providers.docker=true
      - --entrypoints.web.address=:80
    ports:
      - "80:80"
      - "8080:8080" # Traefik dashboard
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
```

- Access PowerDNS API via http://pdns.localhost/ (add to your /etc/hosts if needed)
- Traefik dashboard: http://localhost:8080/

## License
MIT
