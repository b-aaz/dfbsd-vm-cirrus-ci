#!/bin/sh

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

# Compile the search binary.
cc srch.c -o srch

# Installs the required programs.
pkg install -y tmux qemu-nox11 vim

# Download the DFBSD image.
fetch https://github.com/vmactions/dragonflybsd-builder/releases/download/v0.9.8/dragonflybsd-6.4.2.qcow2.zst

# Unpack the DFBSD image.
cat dragonflybsd-6.4.2.qcow2.zst | zstd -d > dfbsd.qcow2
rm dragonflybsd-6.4.2.qcow2.zst 

# Create a tmux session that the VM  will start in.
tmux new-session -d

# Send the VM start command
tmux send-keys -l "qemu-system-x86_64 -drive file=dfbsd.qcow2,if=ide -m 1G -smp 1 -device e1000,netdev=n1,mac=52:54:98:76:54:32 -netdev user,id=n1,net=192.168.122.0/24,dhcpstart=192.168.122.50,hostfwd=tcp::10022-:22 -nographic"

# Start the VM
tmux send-keys Enter

# Store the VM console output
tmux pipe-pane -O "cat >> /tmp/vm-log" 

# Waiting for BIOS to start
(tail -f -n +1  /tmp/vm-log & ) |  ./srch 'DF/FBSD' 

# Boot the default BIOS option without waiting.
tmux send-keys Enter 

# Waiting for loader to start 
(tail -f -n +1  /tmp/vm-log & ) |  ./srch 'Booting in'

# Stop the loader boot timer
tmux send-keys -l " "

# Wait for it to stop
(tail -f -n +1  /tmp/vm-log & ) |  ./srch 'Countdown'

# Get into the loader prompt
tmux send-keys -l "9"
tmux send-keys Enter

# Wait for the prompt to appear
(tail -f -n +1  /tmp/vm-log & ) |  ./srch 'OK'

# The loader prompt will bug out when we send the keys too fast. So we need to
# send the keys and normal typing speeds.

# Enable the serial console
tmux_sendkeys_slow 'set console=comconsole'
sleep 1
tmux send-keys Enter
sleep 1

# Boot the kernel
tmux_sendkeys_slow 'boot'
sleep 1
tmux send-keys Enter

# Wait for getty to appear and login
(tail -f -n +1  /tmp/vm-log & ) |  ./srch 'login:'

# Login with the root user
tmux send-keys -l 'root'
tmux send-keys Enter
