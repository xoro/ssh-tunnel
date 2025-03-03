#!/bin/sh

# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2025, Timo Pallach (timo@pallach.de).

# ssh-tunnel.sh - Script to establish a persistent reverse SSH tunnel
# This works on systems without systemd (BSD, older Linux, etc.)

# Default configuration variables
SERVER_USER="server_username"
SERVER_HOST="server.example.com"
SERVER_PORT="22"
LOCAL_PORT="22"          # SSH port on the client
REMOTE_PORT="2222"       # Port on the server that will forward to the client
MONITOR_PORT="20000"     # Port used by autossh to monitor the connection
LOCAL_USER="$(whoami)"   # Local user under which the service will run
SERVER_ALIVE_INTERVAL="60"
SERVER_ALIVE_COUNT_MAX="3"
EXIT_ON_FORWARD_FAILURE="yes"
INSTALL_SERVICE=false

# Search for configuration file in the following order:
# 1. Current directory: ./ssh-tunnel.conf
# 2. System-wide: /etc/ssh-tunnel.conf
# 3. User config: ~/.config/ssh-tunnel/ssh-tunnel.conf
CONFIG_FILE=""
if [ -f "./ssh-tunnel.conf" ]; then
    CONFIG_FILE="./ssh-tunnel.conf"
elif [ -f "/etc/ssh-tunnel.conf" ]; then
    CONFIG_FILE="/etc/ssh-tunnel.conf"
elif [ -f "$HOME/.config/ssh-tunnel/ssh-tunnel.conf" ]; then
    CONFIG_FILE="$HOME/.config/ssh-tunnel/ssh-tunnel.conf"
fi

# Load configuration from file if found
if [ -n "$CONFIG_FILE" ]; then
    echo "Loading configuration from $CONFIG_FILE"
    # Source the config file
    . "$CONFIG_FILE"
    
    # Map config file variables to script variables
    [ -n "$SERVER_SSH_USER" ] && SERVER_USER="$SERVER_SSH_USER"
    [ -n "$SERVER_SSH_HOST" ] && SERVER_HOST="$SERVER_SSH_HOST"
    [ -n "$SERVER_SSH_PORT" ] && SERVER_PORT="$SERVER_SSH_PORT"
    [ -n "$LOCAL_SSH_PORT" ] && LOCAL_PORT="$LOCAL_SSH_PORT"
    [ -n "$SERVER_SSH_FORWARD_PORT" ] && REMOTE_PORT="$SERVER_SSH_FORWARD_PORT"
    [ -n "$LOCAL_SERVICE_USER" ] && LOCAL_USER="$LOCAL_SERVICE_USER"
    
    # Convert string boolean to shell boolean
    if [ "$INSTALL_LOCAL_SERVICE" = "true" ]; then
        INSTALL_SERVICE=true
    fi
fi

# Display usage information
usage() {
    echo "Persistent Reverse SSH Tunnel Setup (Non-systemd)"
    echo "================================================="
    echo "This script establishes a persistent reverse SSH tunnel from this client machine to a server,"
    echo "allowing the server to connect back to this client. It uses autossh to automatically"
    echo "reconnect if the connection drops."
    echo ""
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -u, --server-ssh-user USER     Server username (default: $SERVER_USER)"
    echo "  -h, --server-ssh-host HOST     Server hostname or IP (default: $SERVER_HOST)"
    echo "  -p, --server-ssh-port PORT     Server SSH port (default: $SERVER_PORT)"
    echo "  -l, --local-ssh-port PORT      Local port to expose (default: $LOCAL_PORT)"
    echo "  -r, --server-ssh-forward-port PORT   Remote port on server (default: $REMOTE_PORT)"
    echo "  -s, --install-local-service    Install as a startup service (requires root)"
    echo "  -U, --local-service-user USER  Local user under which the service will run (default: $LOCAL_USER)"
    echo "  -c, --config FILE              Path to configuration file"
    echo "  --help              Display this help message"
    echo ""
    echo "Configuration file:"
    echo "  The script searches for a configuration file in the following order:"
    echo "  1. Current directory: ./ssh-tunnel.conf"
    echo "  2. System-wide: /etc/ssh-tunnel.conf"
    echo "  3. User config: ~/.config/ssh-tunnel/ssh-tunnel.conf"
    echo ""
    echo "  Command line options will override settings from the config file."
    echo "  See ssh-tunnel.conf.example for an example configuration."
    echo ""
    echo "  When installing as a service, the current configuration is saved to /etc/ssh-tunnel.conf"
    echo "  to ensure the service always uses the correct settings."
    echo ""
    echo "Example:"
    echo "  $0 --server-ssh-user admin --server-ssh-host myserver.com --server-ssh-forward-port 2222 --install-local-service"
    echo ""
    echo "After running this script, the server can connect back to this client using:"
    echo "  ssh -p \$REMOTE_PORT localhost"
    exit 1
}

# Parse command line arguments
while [ $# -gt 0 ]; do
    case $1 in
        -u|--server-ssh-user)
            SERVER_USER="$2"
            shift 2
            ;;
        -h|--server-ssh-host)
            SERVER_HOST="$2"
            shift 2
            ;;
        -p|--server-ssh-port)
            SERVER_PORT="$2"
            shift 2
            ;;
        -l|--local-ssh-port)
            LOCAL_PORT="$2"
            shift 2
            ;;
        -r|--server-ssh-forward-port)
            REMOTE_PORT="$2"
            shift 2
            ;;
        -s|--install-local-service)
            INSTALL_SERVICE=true
            shift
            ;;
        -U|--local-service-user)
            LOCAL_USER="$2"
            shift 2
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            # Re-load the config file with the new path
            if [ -f "$CONFIG_FILE" ]; then
                echo "Loading configuration from $CONFIG_FILE"
                . "$CONFIG_FILE"
                
                # Map config file variables to script variables (only if not already set by command line)
                [ -n "$SERVER_SSH_USER" ] && SERVER_USER="$SERVER_SSH_USER"
                [ -n "$SERVER_SSH_HOST" ] && SERVER_HOST="$SERVER_SSH_HOST"
                [ -n "$SERVER_SSH_PORT" ] && SERVER_PORT="$SERVER_SSH_PORT"
                [ -n "$LOCAL_SSH_PORT" ] && LOCAL_PORT="$LOCAL_SSH_PORT"
                [ -n "$SERVER_SSH_FORWARD_PORT" ] && REMOTE_PORT="$SERVER_SSH_FORWARD_PORT"
                [ -n "$LOCAL_SERVICE_USER" ] && LOCAL_USER="$LOCAL_SERVICE_USER"
                
                # Convert string boolean to shell boolean
                if [ "$INSTALL_LOCAL_SERVICE" = "true" ]; then
                    INSTALL_SERVICE=true
                fi
            else
                echo "Error: Configuration file $CONFIG_FILE not found."
                exit 1
            fi
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required parameters
if [ -z "$SERVER_USER" ] || [ -z "$SERVER_HOST" ]; then
    echo "Error: Server username and hostname are required."
    usage
fi

# Detect init system
detect_init_system() {
    if [ -d "/etc/rc.d" ]; then
        echo "bsd"
    elif [ -d "/etc/init.d" ]; then
        echo "sysv"
    else
        echo "unknown"
    fi
}

# Function to save current configuration to system-wide location
save_config_for_service() {
    echo "Saving current configuration to /etc/ssh-tunnel.conf for service use"
    cat > /etc/ssh-tunnel.conf << EOF
# SSH Tunnel Configuration File
# Created by ssh-tunnel.sh service installation on $(date)
# This file is used by the ssh-tunnel service

# Server SSH connection details
SERVER_SSH_USER="$SERVER_USER"
SERVER_SSH_HOST="$SERVER_HOST"
SERVER_SSH_PORT="$SERVER_PORT"

# Port forwarding configuration
LOCAL_SSH_PORT="$LOCAL_PORT"
SERVER_SSH_FORWARD_PORT="$REMOTE_PORT"

# Service installation options
INSTALL_LOCAL_SERVICE="true"
LOCAL_SERVICE_USER="$LOCAL_USER"

# Advanced options
MONITOR_PORT="$MONITOR_PORT"
SERVER_ALIVE_INTERVAL="$SERVER_ALIVE_INTERVAL"
SERVER_ALIVE_COUNT_MAX="$SERVER_ALIVE_COUNT_MAX"
EXIT_ON_FORWARD_FAILURE="$EXIT_ON_FORWARD_FAILURE"
EOF
    chmod 644 /etc/ssh-tunnel.conf
}

# Function to install as a service
install_service() {
    # Check if autossh is installed
    if ! command -v autossh > /dev/null 2>&1; then
        echo "autossh is not installed. Installing..."
        if command -v apt-get > /dev/null 2>&1; then
            sudo apt-get update
            sudo apt-get install -y autossh
        elif command -v yum > /dev/null 2>&1; then
            sudo yum install -y autossh
        elif command -v pkg > /dev/null 2>&1; then
            sudo pkg install autossh
        elif command -v brew > /dev/null 2>&1; then
            brew install autossh
        else
            echo "Error: Could not install autossh. Please install it manually."
            exit 1
        fi
    fi

    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: Installing as a service requires root privileges."
        echo "Please run with sudo or doas when using the -s option."
        exit 1
    fi

    # Save current configuration to system-wide location
    save_config_for_service

    INIT_SYSTEM=$(detect_init_system)
    echo "Detected init system: $INIT_SYSTEM"
    
    # Create the command that will be run with short options
    CMD="/usr/bin/autossh -M $MONITOR_PORT -N -R $REMOTE_PORT:localhost:$LOCAL_PORT -o \"ServerAliveInterval $SERVER_ALIVE_INTERVAL\" -o \"ServerAliveCountMax $SERVER_ALIVE_COUNT_MAX\" -o \"ExitOnForwardFailure $EXIT_ON_FORWARD_FAILURE\" -p $SERVER_PORT $SERVER_USER@$SERVER_HOST"
    
    case $INIT_SYSTEM in
        bsd)
            # Create rc script for BSD systems
            cat > /etc/rc.d/reverse_ssh << EOF
#!/bin/sh
#
# PROVIDE: reverse_ssh
# REQUIRE: NETWORKING
# KEYWORD: shutdown

. /etc/rc.subr

name="reverse_ssh"
rcvar="reverse_ssh_enable"
command="/usr/bin/autossh"
command_args="-M $MONITOR_PORT -N -R $REMOTE_PORT:localhost:$LOCAL_PORT -o ServerAliveInterval=$SERVER_ALIVE_INTERVAL -o ServerAliveCountMax=$SERVER_ALIVE_COUNT_MAX -o ExitOnForwardFailure=$EXIT_ON_FORWARD_FAILURE -p $SERVER_PORT $SERVER_USER@$SERVER_HOST"
pidfile="/var/run/\${name}.pid"
start_cmd="\${name}_start"
stop_cmd="\${name}_stop"
reverse_ssh_user="$LOCAL_USER"

reverse_ssh_start()
{
    echo "Starting \${name}."
    /usr/sbin/daemon -u \${reverse_ssh_user} -p \${pidfile} -f \${command} \${command_args}
}

reverse_ssh_stop()
{
    if [ -e \${pidfile} ]; then
        kill \`cat \${pidfile}\`
    fi
}

load_rc_config \$name
run_rc_command "\$1"
EOF
            chmod 755 /etc/rc.d/reverse_ssh
            
            # Enable the service
            echo 'reverse_ssh_enable="YES"' >> /etc/rc.conf
            
            echo "Service installed. It will start on next boot."
            echo "To start it now, run: /etc/rc.d/reverse_ssh start"
            ;;
            
        sysv)
            # Create init script for SysV init systems
            cat > /etc/init.d/reverse-ssh << EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          reverse-ssh
# Required-Start:    \$network \$remote_fs \$syslog
# Required-Stop:     \$network \$remote_fs \$syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Reverse SSH tunnel
# Description:       Establishes a reverse SSH tunnel to a remote server
### END INIT INFO

DAEMON=/usr/bin/autossh
DAEMON_ARGS="-M $MONITOR_PORT -N -R $REMOTE_PORT:localhost:$LOCAL_PORT -o ServerAliveInterval=$SERVER_ALIVE_INTERVAL -o ServerAliveCountMax=$SERVER_ALIVE_COUNT_MAX -o ExitOnForwardFailure=$EXIT_ON_FORWARD_FAILURE -p $SERVER_PORT $SERVER_USER@$SERVER_HOST"
NAME=reverse-ssh
PIDFILE=/var/run/\$NAME.pid
USER=$LOCAL_USER
HOME_DIR=\$(getent passwd \$USER | cut -d: -f6)

case "\$1" in
  start)
    echo "Starting \$NAME"
    export AUTOSSH_GATETIME=0
    start-stop-daemon --start --background --make-pidfile --pidfile \$PIDFILE --chuid \$USER --exec \$DAEMON -- \$DAEMON_ARGS
    ;;
  stop)
    echo "Stopping \$NAME"
    start-stop-daemon --stop --pidfile \$PIDFILE
    rm -f \$PIDFILE
    ;;
  restart)
    \$0 stop
    \$0 start
    ;;
  status)
    if [ -e \$PIDFILE ]; then
      echo "\$NAME is running, pid: \`cat \$PIDFILE\`"
    else
      echo "\$NAME is NOT running"
      exit 1
    fi
    ;;
  *)
    echo "Usage: \$0 {start|stop|restart|status}"
    exit 1
    ;;
esac

exit 0
EOF
            chmod 755 /etc/init.d/reverse-ssh
            
            # Enable the service
            if command -v update-rc.d > /dev/null 2>&1; then
                update-rc.d reverse-ssh defaults
            elif command -v chkconfig > /dev/null 2>&1; then
                chkconfig --add reverse-ssh
                chkconfig reverse-ssh on
            fi
            
            echo "Service installed. It will start on next boot."
            echo "To start it now, run: /etc/init.d/reverse-ssh start"
            ;;
            
        *)
            # For unknown init systems, create a crontab entry
            echo "Unknown init system. Setting up a crontab entry instead."
            
            # Create a wrapper script
            mkdir -p /usr/local/bin
            cat > /usr/local/bin/reverse_ssh_wrapper.sh << EOF
#!/bin/sh
# Load configuration
if [ -f "/etc/ssh-tunnel.conf" ]; then
    . /etc/ssh-tunnel.conf
    
    # Map config file variables to script variables
    [ -n "\$SERVER_SSH_USER" ] && SERVER_USER="\$SERVER_SSH_USER"
    [ -n "\$SERVER_SSH_HOST" ] && SERVER_HOST="\$SERVER_SSH_HOST"
    [ -n "\$SERVER_SSH_PORT" ] && SERVER_PORT="\$SERVER_SSH_PORT"
    [ -n "\$LOCAL_SSH_PORT" ] && LOCAL_PORT="\$LOCAL_SSH_PORT"
    [ -n "\$SERVER_SSH_FORWARD_PORT" ] && REMOTE_PORT="\$SERVER_SSH_FORWARD_PORT"
    [ -n "\$MONITOR_PORT" ] && MONITOR_PORT="\$MONITOR_PORT"
    [ -n "\$SERVER_ALIVE_INTERVAL" ] && SERVER_ALIVE_INTERVAL="\$SERVER_ALIVE_INTERVAL"
    [ -n "\$SERVER_ALIVE_COUNT_MAX" ] && SERVER_ALIVE_COUNT_MAX="\$SERVER_ALIVE_COUNT_MAX"
    [ -n "\$EXIT_ON_FORWARD_FAILURE" ] && EXIT_ON_FORWARD_FAILURE="\$EXIT_ON_FORWARD_FAILURE"
fi

export AUTOSSH_GATETIME=0
CMD="/usr/bin/autossh -M $MONITOR_PORT -N -R $REMOTE_PORT:localhost:$LOCAL_PORT -o \"ServerAliveInterval $SERVER_ALIVE_INTERVAL\" -o \"ServerAliveCountMax $SERVER_ALIVE_COUNT_MAX\" -o \"ExitOnForwardFailure $EXIT_ON_FORWARD_FAILURE\" -p $SERVER_PORT $SERVER_USER@$SERVER_HOST"
pgrep -f "autossh.*$REMOTE_PORT:localhost:$LOCAL_PORT" > /dev/null || \$CMD
EOF
            chmod 755 /usr/local/bin/reverse_ssh_wrapper.sh
            
            # Add to crontab to run every 5 minutes, but for the specific user
            if [ -f /usr/bin/crontab ]; then
                (su - $LOCAL_USER -c "crontab -l 2>/dev/null"; echo "*/5 * * * * /usr/local/bin/reverse_ssh_wrapper.sh") | su - $LOCAL_USER -c "crontab -"
                echo "Crontab entry added for user '$LOCAL_USER'. The script will check every 5 minutes if the tunnel is running."
            else
                echo "Warning: Could not add crontab entry. Please add it manually for user '$LOCAL_USER':"
                echo "*/5 * * * * /usr/local/bin/reverse_ssh_wrapper.sh"
            fi
            
            echo "To start it now, run as user '$LOCAL_USER': /usr/local/bin/reverse_ssh_wrapper.sh"
            ;;
    esac
    
    # Start the service immediately
    case $INIT_SYSTEM in
        bsd)
            /etc/rc.d/reverse_ssh start
            ;;
        sysv)
            /etc/init.d/reverse-ssh start
            ;;
        *)
            su - $LOCAL_USER -c "/usr/local/bin/reverse_ssh_wrapper.sh"
            ;;
    esac
    
    echo "Service installed and started."
    echo "Configuration saved to /etc/ssh-tunnel.conf"
    echo "You can modify this file to change the service settings."
}

# Main execution
echo "Setting up persistent reverse SSH tunnel..."
echo "Server: $SERVER_USER@$SERVER_HOST:$SERVER_PORT"
echo "Local port: $LOCAL_PORT"
echo "Remote port: $REMOTE_PORT"
echo ""

if [ "$INSTALL_SERVICE" = true ]; then
    install_service
else
    echo "Executing: ssh -N -R $REMOTE_PORT:localhost:$LOCAL_PORT -p $SERVER_PORT $SERVER_USER@$SERVER_HOST"
    echo ""
    echo "This will allow the server to connect back to this client using:"
    echo "  ssh -p $REMOTE_PORT localhost"
    echo ""
    echo "Press Ctrl+C to terminate the tunnel."
    echo ""
    
    # Establish the tunnel using regular SSH with short options
    ssh -N -R $REMOTE_PORT:localhost:$LOCAL_PORT \
        -o ServerAliveInterval=$SERVER_ALIVE_INTERVAL \
        -o ServerAliveCountMax=$SERVER_ALIVE_COUNT_MAX \
        -o ExitOnForwardFailure=$EXIT_ON_FORWARD_FAILURE \
        -p $SERVER_PORT $SERVER_USER@$SERVER_HOST
fi 