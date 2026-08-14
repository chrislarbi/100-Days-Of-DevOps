# Day 43 Nginx Ecommerce Container on Application Server 1

## The real-world problem
Deploying a lightweight, isolated web server to an existing application node without causing dependency conflicts on the host, while exposing it to external network traffic.

## How I approached it
Before running any commands, I verified I was actually connected to Application Server 1 and not the Jump Server. I recognized this as a standard container lifecycle task. I needed to fetch the image, start a container, and bridge the isolated network to the host network via port mapping. I decoupled the pulling of the image from the running of the container to isolate potential network errors from runtime errors.

## Key concepts

**Docker Image**
A read-only template containing the application code and dependencies. This exists to ensure consistent execution across any environment.

**Docker Container**
A running instance of an image. This exists to isolate application processes and files from the host and other applications.

**Port Mapping (-p)**
Forwarding traffic from a port on the host to a port inside the isolated container network. Because containers have private networks, this securely exposes specific services.

**Detached Mode (-d)**
Running the process in the background. This exists to keep server processes alive independently of the engineer's active terminal session.

## Solution

**Step 1: Verify environment and prerequisites**
Why: To confirm server identity and container runtime health before changing state.
Command: `hostname` and `docker info`
Reasoning Skill: The "Verify Assumptions" pattern. Never assume the infrastructure matches the ticket; always prove context first.

**Step 2: Pull the specific image**
Why: To fetch the dependency and isolate potential registry or network issues from runtime configuration issues.
Command: `docker pull nginx:stable`
Reasoning Skill: The "Explicit Artifact Retrieval" pattern. Separate fetching dependencies from execution for easier troubleshooting.

**Step 3: Run the container with port mapping and detached mode**
Why: To instantiate the image into a background process and bridge the host's port 8084 to the container's port 80.
Command: `docker run -d --name ecommerce -p 8084:80 nginx:stable`
Reasoning Skill: The "Interface Binding" pattern. When bridging isolated systems, explicitly define the mapping of external interfaces to internal ones.

## How to verify this actually works
Run `docker ps` to ensure the container is Up and the PORTS column shows 0.0.0.0:8084->80/tcp.

Trap to avoid: Just seeing the container running is not enough. Run `curl http://localhost:8084` from the host to ensure the web server is actually responding with HTML.

## Common mistakes here

Reversing the port mapping by using `-p 80:8084` instead of `8084:80`. The order is always host port followed by container port.

Forgetting detached mode. The container runs in the foreground, and when the user exits the terminal, the container dies.

Ignoring the image tag by pulling just `nginx` which defaults to the `latest` tag instead of the requested `stable` tag, leading to unpredictable software versions.

## Transferable pattern
Whenever deploying an isolated service like a container, a VM, or a serverless function, you must explicitly manage its network boundaries. The pattern is always the same: define the compute artifact, provide it runtime execution parameters like background mode, and explicitly declare the ingress port or load balancer rule that connects the outside world to the internal service.

## What I learned
[First-person reflection to be filled in]
