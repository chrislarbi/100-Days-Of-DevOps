# Day 45: Resolving Apache HTTPD SSL Dockerfile Issues

## 1. Executive Summary & Problem Context

In containerized application pipelines, the `Dockerfile` serves as the blueprint for building immutable runtime environments. A broken or misconfigured `Dockerfile` blocks continuous integration (CI) pipelines, causing delivery delays and developer friction. 

In this lab, the development team was attempting to build a secure Apache (`httpd`) image with custom SSL certificates and configuration overrides. However, the build failed due to syntax errors, incorrect use of directives, and pathing inconsistencies.

### The "Why"
* **Environment and Build Drift:** When Dockerfiles are written using non-standard or deprecated directives, local builds might fail or produce unexpected side effects on older or newer daemon engines.
* **Blast Radius Control:** Using the wrong copy/command runner directives (like `ADD` instead of `RUN` for executing inline CLI operations) can result in bloated images or security issues (e.g., executing remote scripts without validation).
* **Operational Inconsistencies:** Misconfiguring the path resolution inside the image means that configuration files are created in the wrong directory namespaces, causing Apache to fail silently at runtime.

This documentation walks through diagnosing the syntax failures, explaining the underlying container build mechanics, and presenting the production-grade fix.

---

## 2. Technical Requirements & Architectural Trade-offs

The following table maps the requirements to their core engineering objectives and their silent failure modes in production:

| Requirement / Spec | Core Engineering Objective | Silent Failure Mode in Production |
|---|---|---|
| **Base Image `httpd:2.4.43`** | Ensures the application runs on a specific, verified version of Apache, avoiding unpredictable updates. | Using a generic `latest` tag could silently introduce breaking changes or security vulnerabilities upon subsequent builds. |
| **Use `RUN` instead of `ADD` for CLI commands** | Executes configuration edit commands (`sed`) inside the container’s filesystem layers during build time. | Using `ADD` treats the shell command as a literal string or local source file, failing the build outright or adding a junk file named after the command to the filesystem. |
| **Use `FROM` instead of `IMAGE`** | Adheres to Dockerfile syntax specifications to define the base build layer. | Using `IMAGE` is invalid syntax; the container engine rejects the file immediately, blocking the build. |
| **Verify path `/usr/local/apache2/conf/httpd.conf`** | Targets the absolute path where Apache expects its main configuration file. | Referencing relative paths (like `conf/httpd.conf`) can resolve to the wrong directory depending on the `WORKDIR` setting of the parent image, resulting in configurations being written to the wrong location. |
| **Copy SSL Certificates & Custom Content** | Separates the application configuration, static files, and secrets (`certs/server.key`) into distinct, manageable filesystem locations. | Omitting or path-misconfiguring certificate copies causes Apache to crash on startup during the SSL initialization phase. |

---

## 3. Step-by-Step Implementation & Execution Strategy

To resolve the Dockerfile issues on App Server 3 (`stapp03`), use the following strategy:

1. **Access the Environment:**
   SSH onto App Server 3 using the credentials provided:
   ```bash
   ssh banner@stapp03
   ```

2. **Inspect the Target Directory:**
   Navigate to `/opt/docker` and check the directory contents (confirming the existence of `certs/` and `html/` subfolders):
   ```bash
   cd /opt/docker
   ls -la
   ```

3. **Diagnose and Repair the Dockerfile:**
   Inspect the existing `Dockerfile`. Overwrite the invalid directives atomically using a shell heredoc to avoid `vi` concurrent write collisions:
   ```bash
   cat > Dockerfile << 'EOF'
   FROM httpd:2.4.43

   # Modify Apache config to listen on port 8080
   RUN sed -i "s/Listen 80/Listen 8080/g" /usr/local/apache2/conf/httpd.conf

   # Uncomment SSL-related modules and config includes
   RUN sed -i '/LoadModule\ ssl_module modules\/mod_ssl.so/s/^#//g' /usr/local/apache2/conf/httpd.conf \
       && sed -i '/LoadModule\ socache_shmcb_module modules\/mod_socache_shmcb.so/s/^#//g' /usr/local/apache2/conf/httpd.conf \
       && sed -i '/Include\ conf\/extra\/httpd-ssl.conf/s/^#//g' /usr/local/apache2/conf/httpd.conf

   # Copy SSL certificates
   COPY certs/server.crt /usr/local/apache2/conf/server.crt
   COPY certs/server.key /usr/local/apache2/conf/server.key

   # Copy website content
   COPY html/index.html /usr/local/apache2/htdocs/
   EOF
   ```

4. **Verify the Context and Build the Image:**
   Build the Docker image, ensuring you provide the path argument (`.`) representing the current directory context.
   ```bash
   docker build -t httpd-ssl-image .
   ```

5. **Test and Verify the Running Container:**
   Instantiate the container to confirm Apache starts up correctly and listens on port `8080`:
   ```bash
   docker run -d -p 8080:8080 --name test-apache httpd-ssl-image
   curl -I http://localhost:8080/
   ```

---

## 4. Final Solution & Production Code

The corrected and production-grade `/opt/docker/Dockerfile` is structured as follows:

```dockerfile
# 1. Declare base image layer
FROM httpd:2.4.43

# 2. Modify listening port to non-root port 8080
RUN sed -i "s/Listen 80/Listen 8080/g" /usr/local/apache2/conf/httpd.conf

# 3. Enable SSL and Session Cache modules by uncommenting httpd.conf lines
RUN sed -i '/LoadModule\ ssl_module modules\/mod_ssl.so/s/^#//g' /usr/local/apache2/conf/httpd.conf \
    && sed -i '/LoadModule\ socache_shmcb_module modules\/mod_socache_shmcb.so/s/^#//g' /usr/local/apache2/conf/httpd.conf \
    && sed -i '/Include\ conf\/extra\/httpd-ssl.conf/s/^#//g' /usr/local/apache2/conf/httpd.conf

# 4. Copy required SSL assets into target config directory
COPY certs/server.crt /usr/local/apache2/conf/server.crt
COPY certs/server.key /usr/local/apache2/conf/server.key

# 5. Populate web root directory with custom index file
COPY html/index.html /usr/local/apache2/htdocs/
```

### OS & Container-Engine Level Mechanics

* **Directive Translation:** The container engine translates `FROM` to pull the specific image layers from Docker Hub. If the image layers already exist locally, it accesses them directly from the local overlay2 storage layer.
* **Build Context Pathing (`.`):** When executing `docker build -t <tag> .`, the trailing dot indicates the build context. The Docker client packages all files in `/opt/docker` and uploads them to the Docker daemon. Directives like `COPY` lookup files *only* relative to this build context. This is why `certs/` and `html/` must exist in the same directory as the `Dockerfile`.
* **Execution of `RUN` Commands:** Each `RUN` directive commits a new intermediary layer. In this case, `RUN sed ...` spawns a temporary container, executes the shell modification using `/bin/sh -c`, commits the modified file system layer, and cleans up the temporary container.

---

## 5. Verification, Testing & Production Gotchas

### Senior-Engineer Verification Steps

1. **Verify Build Process:**
   Verify that the image builds without errors and registers with the local daemon:
   ```bash
   docker images | grep httpd-ssl-image
   ```

2. **Verify Port Handshakes:**
   Run a temporary instance of the built container and test the HTTP endpoint from the host:
   ```bash
   docker run -d -p 8080:8080 --name debug_httpd httpd-ssl-image
   curl -I http://localhost:8080/
   ```
   *Expected Response:* HTTP 200 OK headers with `Server: Apache/2.4.43 (Unix) OpenSSL/1.1.1d`.

3. **Check Container Runtime Logs:**
   Ensure no startup errors occur due to missing configuration files or malformed certificates:
   ```bash
   docker logs debug_httpd
   ```

---

## Production Gotchas & Edge Cases

### Gotcha 1: "requires 1 argument" Build Failure
**Symptom:** Running `docker build -t httpd-ssl-image` fails with `ERROR: docker: 'docker buildx build' requires 1 argument`.
* **Root Cause:** The Docker CLI needs an explicit path to identify the build context. Omitting the trailing `.` fails the argument validation of the command builder.
* **Fix:** Always append the context directory (typically `.` for the current working directory):
  ```bash
  docker build -t httpd-ssl-image .
  ```

### Gotcha 2: Concurrency Write Conflicts in `vi` (E949 Error)
**Symptom:** Saving edits in `vi` throws `E949: File changed while writing` or shows backup file lock issues.
* **Root Cause:** This is caused by concurrent writes or external monitoring processes (like workspace syncs or automation grading checks) touching the file while a user has it open.
* **Fix:** Quit out of the editor using `:q!` and overwrite the file directly using an atomic shell redirection heredoc (`cat > Dockerfile << 'EOF'`).
