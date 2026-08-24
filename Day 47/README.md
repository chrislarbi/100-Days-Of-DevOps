# Day 47: Dockerizing and Deploying a Python App on App Server 3

## Project Overview & Objectives

In modern infrastructure management, deploying applications directly to virtual machines or bare-metal servers often leads to "works on my machine" issues. This project demonstrates how to package a Python application into a reproducible Docker container and deploy it to a target environment—specifically, **App Server 3**—to achieve environment parity and process reliability.

The objectives of this task include:
1. Writing a multi-layer `Dockerfile` inside the `/python_app` directory that containerizes a Python server.
2. Implementing Docker best practices, such as proper build caching and non-caching package installation.
3. Exposing internal port `6200` from the application container.
4. Building the Docker image under the name `nautilus/python-app`.
5. Running the container named `pythonapp_nautilus`, mapping host port `8093` to container port `6200`.
6. Verifying the application's responsiveness on App Server 3.

---

## Core Concepts Explained (For Beginners)

### 1. Why Containerize vs. Bare-Metal/Virtual Environments?
Running applications bare-metal or inside basic virtual environments (like `venv` or `conda`) has several limitations:
* **Environment Drift:** Minor library versions, OS dependencies, or host configurations might differ between development and staging/production servers.
* **Lack of Process Isolation:** If multiple applications run on the same server, they share the same OS libraries and port namespaces. Upgrading a dependency for one application might break another (dependency hell).
* **Manual Lifespan Fragility:** Ad-hoc scripts started with `nohup python server.py &` can easily die during OOM (Out Of Memory) events or server restarts, requiring manual recovery.

Containerization solves this by bundling the application, its specific runtime version (e.g., Python 3.9), and system dependencies into a lightweight, immutable image. The container behaves identically wherever it runs.

### 2. EXPOSE vs. Port Mapping (-p)
There is a common point of confusion between the `EXPOSE` instruction in a `Dockerfile` and the `-p` flag in the `docker run` command:
* **`EXPOSE 6200` (Metadata):** This is purely documentation. It tells developers and orchestration tools (like Kubernetes or ECS) that the application inside the container is configured to listen on port `6200`. It does **not** publish or open ports on the host machine.
* **`-p 8093:6200` (Network Bridge):** This performs the actual network port binding. It instructs Docker to bind to port `8093` on the host machine and route all incoming traffic on that port directly to port `6200` inside the container's isolated network namespace. Without this mapping, external traffic cannot reach the container.

### 3. Layer Caching and Directive Ordering
Docker builds images sequentially, line by line. Each directive (`FROM`, `COPY`, `RUN`) creates a new read-only image layer. 
* Docker caches these layers. If a layer and all preceding layers haven't changed, Docker reuses the cached layer instead of rebuilding it, saving time.
* If a layer changes, **all subsequent layers are invalidated** and must be rebuilt.
* By copying `requirements.txt` and running `pip install` *before* copying the rest of the application code, we optimize the build cache. Since source code changes frequently but project dependencies do not, subsequent builds will skip the time-consuming `pip install` step entirely.

### 4. PID 1 and Foreground Execution
In Linux systems, the process with Process ID 1 (PID 1) is the initialization process (like `systemd` or `sysvinit`). It is responsible for reaping orphan processes and forwarding signals.
* Inside a Docker container, the command specified in `CMD` runs as PID 1.
* Docker monitors PID 1. If PID 1 terminates, the container stops immediately.
* If your application daemonizes itself (e.g., runs in the background using `nohup` or forks to a background process), the starter process (PID 1) will exit, causing Docker to think the container has finished its execution and terminate it. The application process inside the container must run in the **foreground** to keep the container alive.

---

## Step-by-Step Implementation & Code

### The `/python_app/Dockerfile`
Create the following `Dockerfile` at the root of the `/python_app` directory:

```dockerfile
# 1. Base image: Provides a minimal Python 3.9 runtime environment and system libraries
FROM python:3.9-slim

# 2. Working Directory: Sets the active directory inside the container's filesystem
WORKDIR /python_app/src

# 3. Cache Optimization: Copy only the requirements file first to utilize layer caching
COPY src/requirements.txt .

# 4. Dependency Installation: Install libraries without saving a local download cache
RUN pip install --no-cache-dir -r requirements.txt

# 5. Application Code: Copy the remaining source files (including server.py)
COPY src/ .

# 6. Metadata Documentation: Declare the application port
EXPOSE 6200

# 7. Execution: Run server.py in the foreground (PID 1) using JSON array (exec) format
CMD ["python", "server.py"]
```

### Build the Image
To build the image, navigate to `/python_app` and run:

```bash
cd /python_app
docker build -t nautilus/python-app .
```
> **Note:** The trailing `.` is the build context. It tells Docker to look for the `Dockerfile` in the current directory and allows it to access the `src/` folder.

### Run the Container
Instantiate the container using the built image:

```bash
docker run -d \
  --name pythonapp_nautilus \
  -p 8093:6200 \
  nautilus/python-app
```
* `-d`: Detached mode. Runs the container in the background.
* `--name pythonapp_nautilus`: Gives the container a deterministic name for easy tracking.
* `-p 8093:6200`: Binds host port `8093` to container port `6200`.

---

## Verification & Testing

Verify that the deployment was successful by running the following checks on App Server 3:

1. **Verify Container Status:**
   Check if the container is running and check its uptime status.
   ```bash
   docker ps -a --filter name=pythonapp_nautilus
   ```

2. **Verify Logs:**
   Inspect the application runtime outputs for any startup errors or execution warnings.
   ```bash
   docker logs pythonapp_nautilus
   ```

3. **Verify Port Mappings:**
   Confirm that the network bridge has bound the correct host port to the container port.
   ```bash
   docker port pythonapp_nautilus
   ```

4. **Functional Testing (HTTP Call):**
   Make a test request to the application using curl on the mapped host port.
   ```bash
   curl http://localhost:8093/
   ```

5. **Deep Container Inspection:**
   Verify from inside the container namespace that the server process is indeed listening on port `6200`.
   ```bash
   docker exec -it pythonapp_nautilus sh -c "netstat -tulpn || ss -tulpn"
   ```

---

## Troubleshooting & Edge Cases (Real-World Insight)

### 1. Syntax Errors in `CMD` (Exit Code 2 / Unterminated Quoted String)
A common mistake when writing a `Dockerfile` is mixing single and double quotes inside the `CMD` JSON array form, like this:
```dockerfile
CMD ["python", 'server.py"]
```
Because this is invalid JSON, Docker silently falls back to executing the command in **shell form**:
```bash
/bin/sh -c '["python", 'server.py"]'
```
The shell chokes on the unbalanced single/double quotes, printing `/bin/sh: 1: Syntax error: Unterminated quoted string` to stdout and exiting with **Exit Code 2**. Since the shell was PID 1, the container immediately terminates.
* **Diagnosis:** Running `docker ps -a` shows `Exited (2)`. `docker port` will return nothing, and `curl` commands will fail.
* **Fix:** Use standard matching double quotes for all elements inside the exec form: `CMD ["python", "server.py"]`.

### 2. Name Conflicts (Conflict: Container Name in Use)
If you try to run a new container with the name `pythonapp_nautilus` while a stopped or crashed container with that same name still exists, you will see this error:
```text
docker: Error response from daemon: Conflict. The container name "/pythonapp_nautilus" is already in use by container "...". You have to remove (or rename) that container to be able to reuse that name.
```
* **Fix:** Stop (if running) and remove the conflicting container before launching the new one:
  ```bash
  docker rm pythonapp_nautilus
  docker run -d --name pythonapp_nautilus -p 8093:6200 nautilus/python-app
  ```

### 3. Connection Refused
If running `curl http://localhost:8093/` returns `curl: (7) Failed to connect to localhost port 8093: Connection refused`, investigate the following:
* **Reversed Ports:** Confirm you did not run `-p 6200:8093` (which binds host `6200` to container `8093`). Check `docker port pythonapp_nautilus`.
* **Binding to localhost inside the Container:** If `server.py` binds to host `127.0.0.1` inside its own code, it will only accept traffic originating from within the container itself. To resolve this, ensure the Python server code binds to `0.0.0.0` (all network interfaces), allowing the Docker bridge network to successfully forward traffic to it.
