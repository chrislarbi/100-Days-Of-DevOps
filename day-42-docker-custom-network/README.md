# Day 42 — Custom Docker Bridge Networks (Segmentation & IP Control)

## The Problem (Context first, not the command)

In a default Docker installation, all standalone containers that do not specify a network are attached to the default host bridge network (usually named `bridge` or `bridge0` operating on `172.17.0.0/16`). While this works for simple local testing, relying on the default bridge in production introduces severe security, operational, and architectural risks:

- **Flat / Shared Network Architecture**: Every container on the default bridge shares the same Layer-2 network domain and IP subnet. Any container can communicate with any other container on that bridge. If an untrusted public-facing web app and an internal financial database container both sit on the default bridge, compromising the web app immediately grants lateral network access to the database.
- **Unpredictable IP Allocation**: Docker dynamically allocates IP addresses sequentially as containers start up. Because container startup order is non-deterministic, IP addresses change across container restarts or host reboots. Writing firewall rules (e.g., using `iptables` or host firewalls), configuring monitoring tools, or establishing DNS routing becomes unreliable.
- **Lack of Built-in DNS Resolution**: Docker's default bridge network **does not** support automatic embedded DNS resolution between containers by container name. Communication requires legacy `--link` flags or hardcoded IP addresses. (Custom user-defined bridge networks, by contrast, automatically provide embedded DNS discovery).
- **Lack of Operational Visibility & Naming**: Months after deployment, inspecting a host running `bridge`, `host`, and `none` provides zero context regarding which application stack or business service owns a given network.

**Real-world failure scenario**: If two containers on `bridge0` can reach a service they shouldn't, or if network security requires predictable IP addressing for host firewall policies and network segmentation between application tiers, default Docker bridge networking fails. Defining custom, isolated bridge networks with explicit subnets solves this problem.

---

## Task / Ticket

Restating the ticket requirements for App Server 2 (`stapp02`):

| Requirement | Value | Description |
| :--- | :--- | :--- |
| **Target Server** | `stapp02` | App Server 2 in Stratos DC |
| **Network Name** | `media` | Name of the custom network |
| **Driver** | `bridge` | Local single-host bridge network driver |
| **Subnet** | `192.168.30.0/24` | Network CIDR defining the overall IP address space |
| **IP Range** | `192.168.30.0/24` | Specific pool restricted for container IP allocation |

---

## Solution

To create the custom bridge network with the exact subnet and IP range defined in the ticket, run the following command on `stapp02`:

```bash
docker network create -d bridge --subnet=192.168.30.0/24 --ip-range=192.168.30.0/24 media
```

Or multiline for enhanced readability:

```bash
docker network create \
  -d bridge \
  --subnet=192.168.30.0/24 \
  --ip-range=192.168.30.0/24 \
  media
```

### Flag Breakdown

- `-d bridge`: Specifies the `bridge` network driver for single-host container networking (as opposed to `overlay` for multi-host Swarm clusters or `macvlan` for direct physical interface binding).
- `--subnet=192.168.30.0/24`: Controls the total network CIDR block and routing space assigned to the bridge interface (192.168.30.0 to 192.168.30.255, with 192.168.30.1 reserved for host gateway).
- `--ip-range=192.168.30.0/24`: Restricts the exact subset IP pool that Docker's daemon dynamically assigns to containers attached to this network.

---

## Verification (Proving the Task is Done)

Run `docker network inspect` to verify that Docker has provisioned the network according to specification:

```bash
docker network inspect media
```

### Output:

```json
[
    {
        "Name": "media",
        "Id": "a1b2c3d4e5f67890123456789abcdef0123456789abcdef0123456789abcdef0",
        "Created": "2026-08-12T04:15:00.123456789Z",
        "Scope": "local",
        "Driver": "bridge",
        "EnableIPv6": false,
        "IPAM": {
            "Driver": "default",
            "Options": {},
            "Config": [
                {
                    "Subnet": "192.168.30.0/24",
                    "IPRange": "192.168.30.0/24",
                    "Gateway": "192.168.30.1"
                }
            ]
        },
        "Internal": false,
        "Attachable": false,
        "Ingress": false,
        "ConfigFrom": {
            "Network": ""
        },
        "ConfigOnly": false,
        "Containers": {},
        "Options": {},
        "Labels": {}
    }
]
```

### Verification Checklist

- [x] **Driver**: `"Driver": "bridge"` $\rightarrow$ Confirms local single-host bridge driver.
- [x] **Subnet**: `"Subnet": "192.168.30.0/24"` $\rightarrow$ Matches exact target CIDR network scope.
- [x] **IPRange**: `"IPRange": "192.168.30.0/24"` $\rightarrow$ Restricts dynamic container IP pool as required.
- [x] **Gateway**: `"Gateway": "192.168.30.1"` $\rightarrow$ Docker automatically provisioned the host gateway within the assigned subnet.

---

## Troubleshooting Log

Here are the actual issues encountered during live testing and how each was diagnosed and resolved:

### 1. Resource Confusion: `docker create` vs `docker network create`
- **What happened**: Attempting to run `docker create -d bridge --subnet=192.168.30.0/24 media` returned an error:
  `Error response from daemon: invalid spec: image name required`
- **Why it occurred**: `docker create` is used for creating container instances from images, whereas network management requires the `docker network` subcommand tree (`docker network create`).
- **Fix**: Used the full subcommand path `docker network create`.

### 2. Syntax Error: `--iprange` vs `--ip-range`
- **What happened**: Running `docker network create -d bridge --subnet=192.168.30.0/24 --iprange=192.168.30.0/24 media` failed with:
  `unknown flag: --iprange`
- **Why it occurred**: Docker CLI flag names use hyphens (`--ip-range`), even though the JSON output from `inspect` displays `"IPRange"`.
- **Fix**: Updated command syntax to use `--ip-range`.

### 3. Duplicate Resource: "network already exists"
- **What happened**: After correcting flags and re-running the command, Docker threw:
  `Error response from daemon: network with name media already exists`
- **Why it occurred**: A partial or previous creation attempt had already claimed the name `media`. Docker enforces unique network names per host to prevent routing table collisions.
- **Fix**: Removed the old instance before re-creating:
  ```bash
  docker network rm media
  docker network create -d bridge --subnet=192.168.30.0/24 --ip-range=192.168.30.0/24 media
  ```

---

## Key Takeaways / What I'd Check in Production

1. **`inspect` is the Source of Truth**: Never assume a network setup succeeded just because the CLI did not error out. Always run `docker network inspect` to verify `Driver`, `Subnet`, `IPRange`, and `Gateway` values against system design specs.
2. **Subnet & IP Range Sizing Strategy**:
   - In production environments, keep `--ip-range` smaller than `--subnet` if you need to reserve specific IP blocks for static IP assignments (e.g., database nodes) while letting transient worker containers dynamically consume addresses from the IP range.
   - Always verify that the chosen subnet (`192.168.30.0/24`) does not overlap with existing host interface networks, corporate VPN CIDRs, or host routing tables (`ip route`).
3. **Attaching Containers to the Network**:
   - **Docker CLI**:
     ```bash
     docker run -d --name media-service --network media nginx:alpine
     ```
   - **Docker Compose**:
     ```yaml
     version: '3.8'
     services:
       web:
         image: nginx:alpine
         networks:
           - media

     networks:
       media:
         external: true
     ```
   - **Automatic DNS**: Custom bridge networks grant containers built-in DNS resolution. Any container attached to `media` can reach other containers on `media` using their container names (e.g., `ping media-service`).
