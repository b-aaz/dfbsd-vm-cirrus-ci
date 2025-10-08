#!/bin/sh

set -e
set -x

# Splits the string in the first argument to chars each on a line.
char_split(){
tmp="$1"
while [ -n "$tmp" ]
do
 rest="${tmp#?}"
 first="${tmp%"$rest"}"
 echo "$first"
 tmp="$rest"
done
}

# Sends the string in the first argument slowly one char at a time at typing
# speeds to the tmux window.
tmux_sendkeys_slow(){
IFS=$'\n';
for i in $(char_split "$1")
do
 tmux send-keys -l "$i"
 sleep .1
done
}

# Delete and recreate ssh keys.
rm -rf /root/.ssh/
ssh-keygen -q -t ed25519 -N "" -f /root/.ssh/id_ed25519

# Add the host details so that we can ssh and rsync easily.
cat > /root/.ssh/config << EOF
Host vm
	HostName 10.0.0.1
	User root
	Port 22
EOF

# Compile and install the search binary.
cc ./.ci/srch.c -o /usr/local/bin/srch

# Installs the required programs.
pkg install -y tmux qemu-nox11 fusefs-sshfs rsync samba420

# Download the DFBSD image.
fetch https://github.com/vmactions/dragonflybsd-builder/releases/download/v0.9.8/dragonflybsd-6.4.2.qcow2.zst -o /tmp/dfbsd.qcow2.zstd

# Unpack the VM image.
zstd --rm -d /tmp/dfbsd.qcow2.zstd -o /tmp/dfbsd.qcow2

# Create a tmux session that the VM  will start in.
tmux new-session -d

# Get the hosts number of CPUs.
hncpu=$(sysctl -n hw.ncpu)

# Get the hosts amount of memory in megabytes.
hmem=$(( $(sysctl -n hw.physmem)/1024/1024 ))

# Send the VM start command.
tmux send-keys -l "qemu-system-x86_64 -drive file=/tmp/dfbsd.qcow2,if=ide -m ${hmem}M -smp $hncpu -device e1000,netdev=n1 -netdev tap,id=n1 -nographic"

# Start the VM.
tmux send-keys Enter

# Store the VM console output.
tmux pipe-pane -O "cat >> /tmp/vm-log" 

# Waiting for BIOS to start.
(tail -f -n +1  /tmp/vm-log & ) | srch 'DF/FBSD' 

# Boot the default BIOS option without waiting.
tmux send-keys Enter 

# Waiting for loader to start.
(tail -f -n +1  /tmp/vm-log & ) | srch 'Booting in'

# Stop the loader boot timer.
tmux send-keys -l " "

# Wait for it to stop.
(tail -f -n +1  /tmp/vm-log & ) | srch 'Countdown'

# Get into the loader prompt.
tmux send-keys -l "9"
tmux send-keys Enter

# Wait for the prompt to appear.
(tail -f -n +1  /tmp/vm-log & ) | srch 'OK'

# The loader prompt will bug out when we send the keys too fast. So we need to
# send the keys and normal typing speeds.

# Enable the serial console.
tmux_sendkeys_slow 'set console=comconsole'
sleep 1
tmux send-keys Enter
sleep 1

# Boot the kernel.
tmux_sendkeys_slow 'boot'
sleep 1
tmux send-keys Enter

# Wait for getty to appear and login.
(tail -f -n +1  /tmp/vm-log & ) | srch 'login:'

# Login with the root user.
tmux send-keys -l 'root'
tmux send-keys Enter

tmux send-keys -l 'unalias rm'
tmux send-keys Enter
# Add the hosts ssh key to VM.
tmux send-keys -l 'rm -rf /root/.ssh/*'
tmux send-keys Enter
tmux send-keys -l 'touch /root/.ssh/authorized_keys'
tmux send-keys Enter
tmux send-keys -l 'chmod 600 /root/.ssh/authorized_keys'
tmux send-keys Enter
tmux send-keys -l 'echo "'"$(cat /root/.ssh/id_ed25519.pub | tr -d "\n")"'" >>  /root/.ssh/authorized_keys'
tmux send-keys Enter

# Setting up the networking.

# Setup the guest network.
tmux send-keys -l 'pkill dhclient'
tmux send-keys Enter
tmux send-keys -l 'ifconfig em0 inet 10.0.0.1/24'
tmux send-keys Enter
tmux send-keys -l 'route add default 10.0.0.2'
tmux send-keys Enter

# Set the VM interface ip address.
ifconfig tap0 inet 10.0.0.2/24

# Enable gateway.
sysctl net.inet.ip.forwarding=1

# Enable PF NAT.
cat > /etc/pf.conf << 'EOF'
ext_if="vtnet0"
int_if="tap0"
nat pass on $ext_if from $int_if:network to any -> ($ext_if)
EOF
service pf onestart

# Add the VM to the known hosts.
ssh-keyscan 10.0.0.1 > /root/.ssh/known_hosts

# Mount the VMs root in host.
kldload fusefs
mkdir /mnt/vm
sshfs vm:/ /mnt/vm

# Add hostnames for the VM and the host.
# (For fixing a NFS bug and also ascetic reasons.)

# VM.
ssh vm "echo '10.0.0.1 vm.vmrun.local'   >> /etc/hosts"
ssh vm "echo '10.0.0.2 host.vmrun.local' >> /etc/hosts"

# Host.
echo '10.0.0.1 vm.vmrun.local'   >> /etc/hosts
echo '10.0.0.2 host.vmrun.local' >> /etc/hosts

# We now have ssh and will use it for the further commands.

# Install SAMBA on the VM.
ssh vm "pkg install -y samba416"
