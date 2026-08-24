# Day 46: Nautilus Containerized LAMP Stack

## 1. Executive Summary & Problem Context

In legacy infrastructure environments, web applications are commonly deployed using a traditional bare-metal or single-VM LAMP (Linux, Apache, MySQL/MariaDB, PHP) stack. While simple to deploy initially, this model introduces several critical operational pain points at scale:
* **Environment Drift:** Minor version changes in PHP runtime, Apache modules, or Database client libraries between development, staging, and production hosts can cause subtle, hard-to-debug runtime failures.
* **Blast Radius Control:** Co-locating the web tier and database tier on the same host OS couples their dependencies. Upgrading Apache or PHP packages can inadvertently modify system library dependencies needed by the Database engine, leading to full stack outages.
* **Slow Disaster Recovery:** Rebuilding a failed server manually (installing packages, configuring vhosts, hardening databases) takes hours and is highly error-prone.

To address these vulnerabilities, this project outlines the containerization of the Nautilus LAMP tier using Docker Compose on **App Server 2 (`stapp02`)**. By packaging the web and database components into isolated containers with frozen dependencies and explicit network/volume contracts, we achieve modularity, near-instant recovery times, and consistency across all environments.

In a production environment, this transition is typically triggered by a shift toward Infrastructure as Code (IaC) or after diagnosing persistent deployment inconsistencies in CI/CD pipelines.

---

## 2. Technical Requirements & Architectural Trade-offs

The following table deconstructs the key specifications for this deployment, mapping them to their engineering objectives and the silent failure modes that would occur if missed:

| Requirement / Spec | Core Engineering Objective | Silent Failure Mode in Production |
|---|---|---|
| **Path `/opt/itadmin/docker-compose.yml`** | Standardized configuration path for automation tooling (Ansible, Jenkins) to run container management operations. | Downstream deployment automation or lab verification scripts will fail to locate the stack configuration, halting CI/CD pipelines. |
| **Container Name `php_apache`** | Bypasses default project-prefixed container naming, providing a stable, predictable handle for monitoring agents, healthcheck scripts, and log collectors. | Logs and metrics collection systems hardcoded to target `php_apache` will fail to retrieve statistics, leading to lack of observability. |
| **Image `php:8.2-apache`** | Bundles the Apache HTTP daemon directly with the PHP module pre-installed and configured to serve code out of the box. | Using a CLI-only base image (like `php:8.2`) will cause the container to exit immediately as no daemon is running, or refuse connections due to a missing web server. |
| **Host Port Mapping `3001:80`** | Bridges host network port `3001` to the container's Apache server on port `80`. Avoids collisions with default port `80` if another service is running on the host. | Bind conflicts on host port `80` can block container startup, or the web server runs successfully internally but remains completely unreachable externally. |
| **Volume Mount `/var/www/html`** | Persists application code and uploads on the host filesystem. Decouples application deployment from container lifetime. | Container restarts, updates, or redeployments will wipe the application state and uploaded media, returning the site to a clean default install. |
| **Container Name `mysql_apache`** | Adheres to strict internal naming conventions for the database service layer (legacy terminology matching common automation tests). | Automated integration tests expecting the exact name `mysql_apache` will fail to verify database connectivity. |
| **Database Image `mariadb:latest`** | Implements the MariaDB database engine. *Note: In a true production environment, pinning a specific minor/patch version (e.g., `mariadb:10.11`) is preferred to avoid breaking changes during image pulls.* | Auto-pulling a new major version during image rebuilds could silently introduce incompatible auth plugins, collation mismatches, or schema migration failures. |
| **Host Port Mapping `3306:3306`** | Exposes the MariaDB database service directly to host network space for host-level backup agents, monitoring plugins, or administrative database clients. | External backup cron jobs (e.g., `mysqldump` from a central backup node) or external DB GUIs will fail to authenticate or route to the database. |
| **Volume Mount `/var/lib/mysql`** | Ensures all database schemas, table spaces, transactional logs, and configuration state are persisted outside the container lifetime. | Standard container lifecycle updates or cleanups (`docker compose down`) will result in total, unrecoverable database loss. |
| **Env `MYSQL_DATABASE=database_apache`** | Automates the creation of the database schema on first boot, eliminating manual bootstrapping steps. | The database schema is not created, causing initial database connection attempts from the application to crash with "database not found" exceptions. |
| **Custom DB User & Complex Password** | Limits the database attack surface by preventing the web application from running under root database privileges. | If compromised, a SQL injection or Remote Code Execution (RCE) exploit on the web server grants full administrative access to the entire database system. |

---

## 3. Step-by-Step Implementation & Execution Strategy

To execute this solution reliably on App Server 2 (`stapp02`), use the following sequence of operations:

1. **Verify Target Environment & Pre-requisites:**
   Confirm you have SSH'd into App Server 2 (`stapp02`) and that the Docker daemon and Docker Compose plugin are installed and running:
   ```bash
   ssh steve@stapp02
   docker --version
   docker compose version
   ```

2. **Prepare Directory Context:**
   Create the directory `/opt/itadmin/` to host the Compose configuration and verify ownership:
   ```bash
   sudo mkdir -p /opt/itadmin
   cd /opt/itadmin
   ```

3. **Verify Host Storage Bind Mounts:**
   Ensure the host directories intended for persistent storage (`/var/www/html` and `/var/lib/mysql`) exist. 
   > **Warning:** If these directories do not exist on the host, the Docker daemon will create them automatically as `root:root` when launching the containers. This can prevent the non-root Apache or MariaDB container processes from having write permissions. Pre-create them and ensure correct user permissions.
   ```bash
   sudo mkdir -p /var/www/html
   sudo mkdir -p /var/lib/mysql
   ```

4. **Define the Compose Configuration:**
   Create the configuration file `/opt/itadmin/docker-compose.yml` with the detailed definitions for the services.

5. **Deploy the Container Stack:**
   Launch the stack in detached mode so that it runs in the background:
   ```bash
   sudo docker compose up -d
   ```

6. **Validate Health Status:**
   Verify that both containers are running and in the `Up` state. Check the initialization logs to ensure no crash loops occur.

---

## 4. Final Solution & Production Code

Here is the complete `/opt/itadmin/docker-compose.yml` file:

```yaml
version: "3.8"

services:
  web:
    image: php:8.2-apache          # PHP 8.2 + Apache HTTP daemon bundle
    container_name: php_apache     # Predictable container naming for monitoring/ops scripts
    ports:
      - "3001:80"                  # Maps host port 3001 to container port 80 (Apache listener)
    volumes:
      - /var/www/html:/var/www/html # Bind mount mapping host directory directly into container
    restart: unless-stopped        # Configures container restart policy upon crash or system reboot
    depends_on:
      - db                         # Orchestrates order; starts DB container prior to Web container

  db:
    image: mariadb:latest          # Deploys official MariaDB engine
    container_name: mysql_apache   # Ticket-specified naming override
    ports:
      - "3306:3306"                # Bridges host port 3306 to container database port 3306
    volumes:
      - /var/lib/mysql:/var/lib/mysql # Persistent database volume mounting
    environment:
      MYSQL_DATABASE: database_apache
      MYSQL_USER: apache_user      # Application database account
      MYSQL_PASSWORD: "S3cur3P@ssApp!" # Secure application password
      MYSQL_ROOT_PASSWORD: "R00tS3cur3P@ss!" # Required root admin password
    restart: unless-stopped
```

### OS & Kernel-Level Mechanics Under the Hood

* **Network Bridging (iptables & NAT):** The `ports` directive is not just a configuration property; it commands the Docker engine to manipulate the host kernel's routing tables. Docker uses the `userland-proxy` and inserts DNAT (Destination Network Address Translation) rules in the host's `iptables` under the custom `DOCKER` chain. Traffic hitting `stapp02:3001` is rewritten at the packet level to redirect to the container's private IP (e.g. `172.18.0.3`) on port `80`.
* **Filesystem Bind Mounts:** The `volumes` definitions utilize the Linux kernel's Virtual File System (VFS) to map host directories directly into the container's mount namespace. No copy-on-write overhead is involved for these paths. Because of this, file ownership UIDs match directly between the host and container. For example, `www-data` inside the container runs as UID `33`, meaning host directories mapped here must allow read/write access to UID `33`.
* **Dependency Orchestration Limits:** The `depends_on` directive only manages the container startup sequence at the Docker engine event level. It does *not* wait for the database engine inside the container to be fully initialized and ready to accept TCP connections before initiating the web server.

---

## 5. Verification, Testing & Production Gotchas

### Senior-Engineer Verification Steps

1. **Active State Verification:**
   Ensure both containers are in an active `Up` status and not displaying exit or restart loops:
   ```bash
   docker ps -a --filter "name=php_apache" --filter "name=mysql_apache"
   ```

2. **Validate HTTP End-to-End Handshake:**
   Perform an HTTP call directly against the mapped host port to verify that the Apache service inside the container is responding:
   ```bash
   curl -I localhost:3001/
   ```
   *Expected Response:* HTTP 200 OK headers with server details (e.g., `Server: Apache/2.4.68 (Debian)`).

3. **Verify Database Initialization Status:**
   Examine the logs of the database container to verify that the SQL engine has completed startup and is ready for traffic:
   ```bash
   docker logs mysql_apache
   ```
   *Look for:* `mysqld: ready for connections.` at the end of the log output.

4. **Verify Container Internal Networking:**
   Test database resolution and login from the web container using the Compose internal DNS network:
   ```bash
   docker exec -it php_apache bash -c "apt-get update && apt-get install -y default-mysql-client && mysql -h db -u apache_user -pdatabase_apache"
   ```

---

## Production Gotchas & Edge Cases

### Gotcha 1: The Database Initialization Race Condition
**Symptom:** The web application boots up and immediately crashes with database connection timeout or refused errors, even though `docker ps` shows both containers are `Up`.
* **Root Cause:** While `depends_on` starts the database container first, the MariaDB initialization entrypoint scripts can take 10–30 seconds to bootstrap on first launch. If the web container tries to query the database during this boot window, the connection fails.
* **Fix:** Configure a healthcheck block in the compose file under the database service, and configure the web service to wait for the healthcheck to succeed:
  ```yaml
  db:
    ...
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "apache_user", "-pS3cur3P@ssApp!"]
      interval: 5s
      timeout: 5s
      retries: 5
  web:
    ...
    depends_on:
      db:
        condition: service_healthy
  ```

### Gotcha 2: Stale Host Database Volume Mismatch
**Symptom:** The database container continuously restarts, showing log errors like `Table space mismatch` or `InnoDB: Page size does not match`.
* **Root Cause:** If `/var/lib/mysql` on the host contains leftover metadata or structural files from a different database version (or MySQL) and is mounted into a fresh MariaDB container, the engines collide.
* **Fix:** Back up any relevant data, clear the host directory path `/var/lib/mysql`, and let the database rebuild on a clean initialization cycle.

### Gotcha 3: Bind Mount Directory Permission Mismatch
**Symptom:** Accessing the web server returns a `403 Forbidden` or `500 Internal Server Error`, and Apache logs display `Permission denied: /var/www/html/index.php`.
* **Root Cause:** The host directory was created as `root:root` with restricted permissions (`700`). The Apache process running inside the container as the low-privilege `www-data` user (UID `33`) is blocked from reading the directory.
* **Fix:** Grant the appropriate read/write permissions on the host directory:
  ```bash
  sudo chown -R 33:33 /var/www/html
  sudo chmod -R 755 /var/www/html
  ```
