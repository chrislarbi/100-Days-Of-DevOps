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
Why: I wanted to be sure I was on the right server before touching anything. Running `hostname` and `docker info` took five seconds and saved me from potentially running commands on the wrong machine.
Command: `hostname` and `docker info`

**Step 2: Pull the specific image**
Why: I pulled the image separately rather than going straight to `docker run`. If something goes wrong with the registry or the network, I know exactly where the failure is instead of guessing.
Command: `docker pull nginx:stable`

**Step 3: Run the container with port mapping and detached mode**
Why: The task required port 8084 on the host to forward to port 80 inside the container, and the container needed to keep running after I closed my terminal.
Command: `docker run -d --name ecommerce -p 8084:80 nginx:stable`

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

I had pulled Docker images plenty of times before, but this was the first time I deliberately separated the `pull` from the `run` as a troubleshooting habit rather than just doing it out of habit. It made me realize how much easier it is to debug when each step has one job.

The port mapping order also caught me for a second — I keep wanting to write it as container-to-host because that feels like the direction data flows, but Docker reads it as host-to-container (`-p host:container`). Writing it down here so it sticks.

Verifying with `curl` after `docker ps` was a good reminder that a running container isn't the same as a working service. The container was up within seconds, but I wouldn't have trusted it without hitting the endpoint.
