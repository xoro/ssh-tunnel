<!-- 
SPDX-License-Identifier: BSD-2-Clause
Copyright (c) 2025, Timo Pallach (timo@pallach.de).
-->

# Accessing Client Host Through SSH From Server

This project provides a complete solution for creating persistent reverse SSH tunnels, allowing servers to securely connect back to client machines that may be behind firewalls or NAT. The included scripts work across various Unix-like systems and handle automatic reconnection and service installation.

## Overview

Normally, SSH connections flow from client → server. However, there are scenarios where you need the opposite:
- Accessing machines behind NAT/firewalls
- Providing remote support to clients
- Accessing home devices from work
- Creating a backdoor for administrative access

This project provides a solution for establishing a persistent SSH tunnel that works across different system configurations.

## Prerequisites

- SSH server running on both the client and server machines
- SSH client installed on both machines
- For persistent service connections: `autossh` package (will be automatically installed when needed)

### Why SSH Server on the Client Machine?

You might wonder why an SSH server is needed on the client machine. Here's why:

1. **Destination for the Connection**: The whole purpose of a reverse SSH tunnel is to allow the server to connect back to the client. When you run `ssh -p 2222 localhost` on the server, that connection is being forwarded through the tunnel to the SSH server running on the client machine. Without an SSH server on the client, there would be nothing to connect to.

2. **Authentication and Access Control**: The SSH server on the client provides authentication, encryption, and access control for the incoming connections from the server. This ensures that only authorized users can connect to the client machine.

3. **Command Execution**: Once connected, the SSH server on the client allows you to execute commands, transfer files, or perform other SSH-related operations on the client machine.

4. **Tunnel Establishment**: The client initiates the connection to the server using the SSH client, but for the server to connect back, it needs an SSH server on the client to accept the connection.

Here's how the process works:

1. The client machine runs `ssh-tunnel.sh`, which uses the SSH client to connect to the server.
2. This connection establishes a tunnel that forwards a port on the server (e.g., 2222) back to the SSH server port (typically 22) on the client.
3. When someone on the server connects to localhost:2222, that connection is securely forwarded through the tunnel to the SSH server on the client.
4. The SSH server on the client then handles authentication and provides access to the client machine.

## SSH Tunnel Script

The `ssh-tunnel.sh` script establishes a reverse SSH tunnel from the client to the server. It works on various systems including those without systemd (BSD, older Linux, etc.).

### Command Line Options

The script supports the following command line options:

| Option | Long Option | Description | Default |
|--------|-------------|-------------|---------|
| `-u` | `--server-ssh-user USER` | Server username | server_username |
| `-h` | `--server-ssh-host HOST` | Server hostname or IP | server.example.com |
| `-p` | `--server-ssh-port PORT` | Server SSH port | 22 |
| `-l` | `--local-ssh-port PORT` | Local port to expose (SSH port on the client) | 22 |
| `-r` | `--server-ssh-forward-port PORT` | Remote port on server that will forward to the client | 2222 |
| `-s` | `--install-local-service` | Install as a startup service (requires root) | - |
| `-U` | `--local-service-user USER` | Local user under which the service will run | Current user |
| - | `--help` | Display help message | - |

### Usage

On the client machine for a temporary connection:

```bash
./ssh-tunnel.sh --server-ssh-user server_username --server-ssh-host server.example.com --server-ssh-forward-port 2222
```

This creates a tunnel where port 2222 on the server forwards to port 22 (SSH) on the client. The script uses standard SSH for direct execution.

Then, on the server:

```bash
ssh -p 2222 localhost
```

This will connect you back to the client machine.

For a permanent setup, you can install it as a service:

```bash
sudo ./ssh-tunnel.sh --server-ssh-user server_username --server-ssh-host server.example.com --server-ssh-forward-port 2222 --install-local-service
# or with doas on BSD systems
doas ./ssh-tunnel.sh --server-ssh-user server_username --server-ssh-host server.example.com --server-ssh-forward-port 2222 --install-local-service
```

When installing as a service, the script will automatically check for and install `autossh` if needed.

### Features

- **Compatibility-focused design**:
  - Uses standard short options for SSH (`-N`, `-R`, `-p`, `-o`)
  - Works across macOS, Linux, and BSD systems
- **Efficient resource usage**:
  - Only installs `autossh` when needed for service installation
  - Uses regular SSH for direct execution
- **Automatic reconnection** when installed as a service:
  - Uses `autossh` to automatically reconnect if the connection drops
- **Flexible deployment options**:
  - Supports direct execution for testing
  - Supports service installation for persistence
- **Automatic service installation** based on your init system:
  - For BSD systems: Creates an rc.d script and adds it to rc.conf
  - For SysV init systems: Creates an init.d script and enables it
  - For unknown systems: Sets up a crontab entry to check and restart the tunnel
- Configurable ports and connection settings
- Detailed usage information with `--help` flag

## Security Considerations

Reverse SSH tunnels can pose security risks if not properly configured:

1. **Authentication**: Always use key-based authentication instead of passwords
2. **Restricted Access**: On the server, consider restricting which users can connect through the forwarded port
3. **Firewall Rules**: Ensure your firewall rules are properly configured
4. **Port Selection**: Avoid using common ports that might be targeted by attackers

## Troubleshooting

### Connection Refused

If you get "Connection refused" when trying to connect from the server:

1. Verify the tunnel is active on the client
2. Check if the SSH server is running on the client
3. Ensure the specified ports are not blocked by firewalls

### Tunnel Disconnects

If the tunnel frequently disconnects:

1. Make sure you're using the script with the `--install-local-service` option for persistent connections
2. Adjust the ServerAliveInterval and ServerAliveCountMax settings if needed
3. Check for network issues or firewalls that might be timing out the connection

### Service Installation Fails

If you get errors when installing as a service:

1. For permission errors: Make sure you're using sudo or doas
2. For other errors: Check the script output for specific error messages

## Advanced Configuration

For more advanced setups, consider:

- Using SSH keys with restricted commands
- Setting up jump hosts for multi-hop scenarios
- Configuring GatewayPorts for access from other machines
- Using SSH config files for simplified connections