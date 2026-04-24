#!/usr/bin/env bash

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
#=================================================
#	System Required: CentOS 7/8,Debian/ubuntu,oraclelinux
#	Description: BBR+BBRplus+Lotserver
#	Version: 100.0.4.17
#	Author: 千影,cx9208,YLX
#	更新内容及反馈:  https://blog.ylx.me/archives/783.html
#=================================================

# RED='\033[0;31m'
# GREEN='\033[0;32m'
# YELLOW='\033[0;33m'
# SKYBLUE='\033[0;36m'
# PLAIN='\033[0m'

sh_ver="100.0.4.17"
github="raw.githubusercontent.com/torr9522/Linux-NetSpeed/tcpx.sh"
AUTO_CLEAN_OLD_KERNELS="${TCPX_AUTO_CLEAN_OLD_KERNELS:-0}"
KERNEL_MODE_BANNER="不卸内核"
KERNEL_MODE_NOTICE="保留旧内核，仅切换默认启动项"
PEER_SCRIPT_REMOTE_URL="https://raw.githubusercontent.com/torr9522/Linux-NetSpeed/tcp.sh/tcp.sh"

imgurl=""
headurl=""
github_network=1

Green_font_prefix="\033[32m"
Red_font_prefix="\033[31m"
Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Green_font_prefix}[注意]${Font_color_suffix}"

if [ -f "/etc/sysctl.d/bbr.conf" ]; then
	rm -rf /etc/sysctl.d/bbr.conf
fi

# 检查当前用户是否为 root 用户
if [ "$EUID" -ne 0 ]; then
	echo "请使用 root 用户身份运行此脚本"
	exit
fi

# 脚本已经要求 root 运行，统一将内部 sudo 调用降级为直接执行，
# 避免在未安装 sudo 的精简系统上报错。
sudo() {
	"$@"
}

show_kernel_install_finish_notice() {
	echo -e "${Tip} 当前默认模式为${KERNEL_MODE_NOTICE}"
	echo -e "${Tip} ${Red_font_prefix}请检查上面是否有内核信息，无内核千万别重启${Font_color_suffix}"
	echo -e "${Tip} ${Red_font_prefix}rescue 不是正常内核，要排除这个${Font_color_suffix}"
	echo -e "${Tip} 重启 VPS 后，请重新运行脚本继续配置加速功能"
}

AUTO_REBOOT_TARGET_MENU=""
AUTO_REBOOT_DELAY="${TCPX_AUTO_REBOOT_DELAY:-1}"

should_auto_reboot_after_action() {
	[[ -n "${AUTO_REBOOT_TARGET_MENU}" ]]
}

schedule_auto_reboot_after_success() {
	local menu_id="$1"
	local expected_kernel="${2:-}"
	local verifier="/tmp/linux-netspeed-auto-reboot-${menu_id}-$$.sh"
	local log_file="/var/log/linux-netspeed-auto-reboot.log"

	cat >"${verifier}" <<'EOF_AUTO_REBOOT'
#!/usr/bin/env bash
set +e
menu_id="$1"
expected_kernel="$2"
delay="$3"
log_file="$4"

trap 'rm -f "$0"' EXIT

log() {
	printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"${log_file}"
}

check_menu_success() {
	case "${menu_id}" in
	1 | 2)
		[[ -n "${expected_kernel}" ]] || return 1
		if [[ ! -f "/boot/vmlinuz-${expected_kernel}" ]] && [[ ! -f "/boot/initrd.img-${expected_kernel}" ]]; then
			return 1
		fi
		if [[ -f /etc/default/grub ]] && ! grep -q "${expected_kernel}" /etc/default/grub; then
			return 1
		fi
		return 0
		;;
	3 | 6)
		[[ "$(cat /proc/sys/net/core/default_qdisc 2>/dev/null)" == "fq" ]] || return 1
		[[ "$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)" == "bbr" ]]
		;;
	4 | 7)
		[[ "$(cat /proc/sys/net/core/default_qdisc 2>/dev/null)" == "fq_pie" ]] || return 1
		[[ "$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)" == "bbr" ]]
		;;
	5 | 8)
		[[ "$(cat /proc/sys/net/core/default_qdisc 2>/dev/null)" == "cake" ]] || return 1
		[[ "$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)" == "bbr" ]]
		;;
	9)
		grep -Fq 'net.ipv4.tcp_retries2 = 8' /etc/sysctl.d/99-sysctl.conf || return 1
		grep -Fq 'net.core.somaxconn = 32768' /etc/sysctl.d/99-sysctl.conf || return 1
		grep -Fq '1000000' /etc/security/limits.conf
		;;
	10)
		grep -Fq 'net.core.netdev_max_backlog = 100000' /etc/sysctl.d/99-sysctl.conf || return 1
		grep -Fq 'net.ipv4.tcp_congestion_control = bbr' /etc/sysctl.d/99-sysctl.conf || return 1
		grep -Fq 'DefaultLimitNOFILE=infinity' /etc/systemd/system.conf
		;;
	*)
		return 1
		;;
	esac
}

for _ in $(seq 1 90); do
	if check_menu_success; then
		log "menu ${menu_id} verification passed; rebooting in ${delay}s"
		sleep "${delay}"
		reboot >/dev/null 2>&1 || systemctl reboot >/dev/null 2>&1 || shutdown -r now >/dev/null 2>&1
		exit 0
	fi
	sleep 2
done

log "menu ${menu_id} verification timed out; reboot skipped"
exit 1
EOF_AUTO_REBOOT

	chmod +x "${verifier}"
	nohup bash "${verifier}" "${menu_id}" "${expected_kernel}" "${AUTO_REBOOT_DELAY}" "${log_file}" >/dev/null 2>&1 &
	disown 2>/dev/null || true
	echo -e "${Info} 已启动后台成功检测，验证通过后将在 ${AUTO_REBOOT_DELAY} 秒后自动重启服务器。"
	echo -e "${Info} 后台日志: ${log_file}"
}

run_menu_action_with_auto_reboot() {
	local menu_id="$1"
	local action_name="$2"
	local expected_kernel=""
	local status=0

	AUTO_REBOOT_TARGET_MENU="${menu_id}"
	"${action_name}"
	status=$?
	expected_kernel="${kernel_version:-}"
	AUTO_REBOOT_TARGET_MENU=""

	if [[ ${status} -eq 0 ]]; then
		schedule_auto_reboot_after_success "${menu_id}" "${expected_kernel}"
	fi

	return "${status}"
}

run_local_or_remote_script() {
	local remote_url="$1"
	shift
	local script_dir=""
	local candidate=""
	script_dir="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" >/dev/null 2>&1 && pwd -P)"

	for candidate in "$@"; do
		if [[ -f "${script_dir}/${candidate}" ]]; then
			bash "${script_dir}/${candidate}"
			return $?
		fi
	done

	bash <(wget -qO- "$remote_url")
}

#优化系统配置
optimizing_system_old() {
	if [ ! -f "/etc/sysctl.d/99-sysctl.conf" ]; then
		touch /etc/sysctl.d/99-sysctl.conf
	fi
	sed -i '/net.ipv4.tcp_retries2/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_slow_start_after_idle/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_fastopen/d' /etc/sysctl.conf
	sed -i '/fs.file-max/d' /etc/sysctl.conf
	sed -i '/fs.inotify.max_user_instances/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_syncookies/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_fin_timeout/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_tw_reuse/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_max_syn_backlog/d' /etc/sysctl.conf
	sed -i '/net.ipv4.ip_local_port_range/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_max_tw_buckets/d' /etc/sysctl.conf
	sed -i '/net.ipv4.route.gc_timeout/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_synack_retries/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_syn_retries/d' /etc/sysctl.conf
	sed -i '/net.core.somaxconn/d' /etc/sysctl.conf
	sed -i '/net.core.netdev_max_backlog/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_timestamps/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_max_orphans/d' /etc/sysctl.conf
	sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf

	echo "net.ipv4.tcp_retries2 = 8
net.ipv4.tcp_slow_start_after_idle = 0
fs.file-max = 1000000
fs.inotify.max_user_instances = 8192
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_max_tw_buckets = 6000
net.ipv4.route.gc_timeout = 100
net.ipv4.tcp_syn_retries = 1
net.ipv4.tcp_synack_retries = 1
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_max_orphans = 32768
# forward ipv4
#net.ipv4.ip_forward = 1" >>/etc/sysctl.d/99-sysctl.conf
	sysctl --system
	echo "*               soft    nofile           1000000
*               hard    nofile          1000000" >/etc/security/limits.conf
	echo "ulimit -SHn 1000000" >>/etc/profile
	if should_auto_reboot_after_action; then
		echo -e "${Info} 当前操作已启用后台检测，验证通过后将自动重启。"
		return 0
	fi
	read -p "需要重启VPS后，才能生效系统优化配置，是否现在重启 ? [Y/n] :" yn
	[ -z "${yn}" ] && yn="y"
	if [[ $yn == [Yy] ]]; then
		echo -e "${Info} VPS 重启中..."
		reboot
	fi
}

optimizing_system_johnrosen1() {
	if [ ! -f "/etc/sysctl.d/99-sysctl.conf" ]; then
		touch /etc/sysctl.d/99-sysctl.conf
	fi
	sed -i '/net.ipv4.tcp_fack/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_early_retrans/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.neigh.default.unres_qlen/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_max_orphans/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.netfilter.nf_conntrack_buckets/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/kernel.pid_max/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/vm.nr_hugepages/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.core.optmem_max/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.conf.all.route_localnet/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.conf.all.forwarding/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.conf.default.forwarding/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv6.conf.all.forwarding/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv6.conf.default.forwarding/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv6.conf.lo.forwarding/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv6.conf.lo.disable_ipv6/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv6.conf.all.accept_ra/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv6.conf.default.accept_ra/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.core.netdev_max_backlog/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.core.netdev_budget/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.core.netdev_budget_usecs/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/fs.file-max /d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.core.rmem_max/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.core.wmem_max/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.core.rmem_default/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.core.wmem_default/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.core.somaxconn/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.icmp_echo_ignore_all/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.icmp_echo_ignore_broadcasts/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.icmp_ignore_bogus_error_responses/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.conf.all.accept_redirects/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.conf.default.accept_redirects/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.conf.all.secure_redirects/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.conf.default.secure_redirects/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.conf.all.send_redirects/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.conf.default.send_redirects/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.conf.default.rp_filter/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.conf.all.rp_filter/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_keepalive_time/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_keepalive_intvl/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_keepalive_probes/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_synack_retries/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_syncookies/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_rfc1337/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_timestamps/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_tw_reuse/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_fin_timeout/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.ip_local_port_range/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_max_tw_buckets/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_fastopen/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_rmem/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_wmem/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.udp_rmem_min/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.udp_wmem_min/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_mtu_probing/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.conf.all.arp_ignore /d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.conf.default.arp_ignore/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.conf.all.arp_announce/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.conf.default.arp_announce/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_autocorking/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_slow_start_after_idle/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_max_syn_backlog/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.core.default_qdisc/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_notsent_lowat/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_no_metrics_save/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_ecn/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_ecn_fallback/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_frto/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv6.conf.all.accept_redirects/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv6.conf.default.accept_redirects/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/vm.swappiness/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.ip_unprivileged_port_start/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/vm.overcommit_memory/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.neigh.default.gc_thresh3/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.neigh.default.gc_thresh2/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.neigh.default.gc_thresh1/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv6.neigh.default.gc_thresh3/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv6.neigh.default.gc_thresh2/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv6.neigh.default.gc_thresh1/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.netfilter.nf_conntrack_max/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.nf_conntrack_max/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.netfilter.nf_conntrack_tcp_timeout_fin_wait/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.netfilter.nf_conntrack_tcp_timeout_time_wait/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.netfilter.nf_conntrack_tcp_timeout_close_wait/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.netfilter.nf_conntrack_tcp_timeout_established/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/fs.inotify.max_user_instances/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/fs.inotify.max_user_watches/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_low_latency/d' /etc/sysctl.d/99-sysctl.conf

	cat >'/etc/sysctl.d/99-sysctl.conf' <<EOF
net.ipv4.tcp_fack = 1
net.ipv4.tcp_early_retrans = 3
net.ipv4.neigh.default.unres_qlen=10000  
net.ipv4.conf.all.route_localnet=1
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1
#net.ipv6.conf.all.forwarding = 1  #awsipv6问题
net.ipv6.conf.default.forwarding = 1
net.ipv6.conf.lo.forwarding = 1
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.lo.disable_ipv6 = 0
net.ipv6.conf.all.accept_ra = 2
net.ipv6.conf.default.accept_ra = 2
net.core.netdev_max_backlog = 100000
net.core.netdev_budget = 50000
net.core.netdev_budget_usecs = 5000
#fs.file-max = 51200
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 67108864
net.core.wmem_default = 67108864
net.core.optmem_max = 65536
net.core.somaxconn = 1000000
net.ipv4.icmp_echo_ignore_all = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.all.rp_filter = 0
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 2
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 0
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_tw_reuse = 0
net.ipv4.tcp_fin_timeout = 15
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_autocorking = 0
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_max_syn_backlog = 819200
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_no_metrics_save = 0
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_ecn_fallback = 1
net.ipv4.tcp_frto = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.neigh.default.gc_thresh3=8192
net.ipv4.neigh.default.gc_thresh2=4096
net.ipv4.neigh.default.gc_thresh1=2048
net.ipv6.neigh.default.gc_thresh3=8192
net.ipv6.neigh.default.gc_thresh2=4096
net.ipv6.neigh.default.gc_thresh1=2048
net.ipv4.tcp_orphan_retries = 1
net.ipv4.tcp_retries2 = 5
vm.swappiness = 1
vm.overcommit_memory = 1
kernel.pid_max=64000
net.netfilter.nf_conntrack_max = 262144
net.nf_conntrack_max = 262144
## Enable bbr
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_low_latency = 1
EOF
	sysctl -p
	sysctl --system
	echo always >/sys/kernel/mm/transparent_hugepage/enabled

	cat >'/etc/systemd/system.conf' <<EOF
[Manager]
#DefaultTimeoutStartSec=90s
DefaultTimeoutStopSec=30s
#DefaultRestartSec=100ms
DefaultLimitCORE=infinity
DefaultLimitNOFILE=infinity
DefaultLimitNPROC=infinity
DefaultTasksMax=infinity
EOF

	cat >'/etc/security/limits.conf' <<EOF
root     soft   nofile    1000000
root     hard   nofile    1000000
root     soft   nproc     unlimited
root     hard   nproc     unlimited
root     soft   core      unlimited
root     hard   core      unlimited
root     hard   memlock   unlimited
root     soft   memlock   unlimited
*     soft   nofile    1000000
*     hard   nofile    1000000
*     soft   nproc     unlimited
*     hard   nproc     unlimited
*     soft   core      unlimited
*     hard   core      unlimited
*     hard   memlock   unlimited
*     soft   memlock   unlimited
EOF

	sed -i '/ulimit -SHn/d' /etc/profile
	sed -i '/ulimit -SHu/d' /etc/profile
	echo "ulimit -SHn 1000000" >>/etc/profile

	if grep -q "pam_limits.so" /etc/pam.d/common-session; then
		:
	else
		sed -i '/required pam_limits.so/d' /etc/pam.d/common-session
		echo "session required pam_limits.so" >>/etc/pam.d/common-session
	fi
	systemctl daemon-reload
	if should_auto_reboot_after_action; then
		echo -e "${Info} 当前操作已启用后台检测，验证通过后将自动重启。"
		return 0
	fi
	echo -e "${Info}优化方案2应用结束，可能需要重启！"
}

#处理传进来的参数 直接优化
err() {
	echo "错误: $1"
	exit 1
}

while [ $# -gt 0 ]; do
	case $1 in
	op0)
		optimizing_system_old # 调用函数
		exit
		;;
	op1)
		optimizing_system_johnrosen1 # 调用函数
		exit
		;;
	op2)
		update_sysctl_interactive # 调用函数
		exit
		;;
	op3)
		etit_sysctl_interactive # 调用函数
		exit
		;;
	*)
		err "未知选项: \"$1\""
		;;
	esac
	shift # 移动到下一个参数
done

# 检查github网络
check_github() {
	# 检测域名的可访问性函数
	check_domain() {
		local domain="$1"
		if ! curl --max-time 5 --head --silent --fail "$domain" >/dev/null; then
			echo -e "${Error}无法访问 $domain，请检查网络或者本地DNS 或者访问频率过快而受限"
			github_network=0
		fi
	}

	# 检测所有域名的可访问性
	check_domain "https://raw.githubusercontent.com"
	check_domain "https://api.github.com"
	check_domain "https://github.com"

	if [ "$github_network" -eq 0 ]; then
		echo -e "${Error}github网络访问受限，将影响内核的安装以及脚本的检查更新，1秒后继续运行脚本"
		sleep 1
	else
		# 所有域名均可访问，打印成功提示
		echo -e "${Green_font_prefix}github可访问${Font_color_suffix}，继续执行脚本..."
	fi
}

#检查连接
checkurl() {
	local url="$1"
	local maxRetries=3
	local retryDelay=2

	if [[ -z "$url" ]]; then
		echo "错误：缺少URL参数！"
		exit 1
	fi

	local retries=0
	local responseCode=""

	while [[ -z "$responseCode" && $retries -lt $maxRetries ]]; do
		responseCode=$(curl --max-time 6 -s -L -m 10 --connect-timeout 5 -o /dev/null -w "%{http_code}" "$url")

		if [[ -z "$responseCode" ]]; then
			((retries++))
			sleep $retryDelay
		fi
	done

	if [[ -n "$responseCode" && ("$responseCode" == "200" || "$responseCode" =~ ^3[0-9]{2}$) ]]; then
		echo "下载地址检查OK，继续！"
	else
		echo "下载地址检查出错，退出！"
		exit 1
	fi
}

#cn处理github加速
check_cn() {
	local original_url="$1"
	local current_ip=""
	local response=""
	local country=""
	local combined_url=""
	local response_code=""
	local suffixes=(
		"https://gh.con.sh/"
		"https://gh-proxy.com/"
		"https://ghp.ci/"
		"https://gh.m-l.cc/"
		"https://down.npee.cn/?"
		"https://mirror.ghproxy.com/"
		"https://ghps.cc/"
		"https://gh.api.99988866.xyz/"
		"https://git.886.be/"
		"https://hub.gitmirror.com/"
		"https://pd.zwc365.com/"
		"https://gh.ddlc.top/"
		"https://slink.ltd/"
		"https://github.moeyy.xyz/"
		"https://ghproxy.crazypeace.workers.dev/"
		"https://gh.h233.eu.org/"
	)

	# 获取当前IP和地区信息，失败时直接回退原始链接，不中断主流程。
	current_ip=$(curl -fsSL --max-time 3 https://api.ipify.org 2>/dev/null || true)
	if [[ -z "$current_ip" ]]; then
		echo "$original_url"
		return 0
	fi

	response=$(curl -fsSL --max-time 3 "http://ip-api.com/json/$current_ip" 2>/dev/null || true)
	country=$(printf '%s' "$response" | sed -n 's/.*"countryCode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
	if [[ "$country" != "CN" ]]; then
		echo "$original_url"
		return 0
	fi

	for suffix in "${suffixes[@]}"; do
		combined_url="${suffix}${original_url}"
		response_code=$(curl --max-time 2 -sL -o /dev/null -w "%{http_code}" -I "$combined_url" 2>/dev/null || true)
		if [[ "$response_code" =~ ^2[0-9]{2}$ ]]; then
			echo "$combined_url"
			return 0
		fi
	done

	echo "$original_url"
	return 0
}

#下载
download_file() {
	local url="$1"
	local filename="$2"
	local status=1
	local i

	for i in 1 2 3; do
		wget --tries=3 --timeout=20 --no-verbose "$url" -O "$filename"
		status=$?
		[[ $status -eq 0 ]] && break
		sleep 2
	done

	if [[ $status -ne 0 ]] && command -v curl >/dev/null 2>&1; then
		curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 600 "$url" -o "$filename"
		status=$?
	fi

	if [[ $status -eq 0 ]]; then
		echo -e "\e[32m文件下载成功或已经是最新。\e[0m"
	else
		echo -e "\e[31m文件下载失败，退出状态码: $status\e[0m"
		exit 1
	fi
}

#檢查賦值
check_empty() {
	local var_value=$1

	if [[ -z $var_value ]]; then
		echo "$var_value 是空值，退出！"
		exit 1
	fi
}

#检查磁盘空间
check_disk_space() {
	# 检查是否存在 bc 命令
	if ! command -v bc &>/dev/null; then
		echo "安装 bc 命令..."
		# 检查系统类型并安装相应的 bc 包
		if [ -f /etc/redhat-release ]; then
			yum install -y bc
		elif [ -f /etc/debian_version ]; then
			apt-get update
			apt-get install -y bc
		else
			echo "无法确定系统类型，请手动安装 bc 命令。"
			return 1
		fi
	fi

	# 获取当前磁盘剩余空间
	available_space=$(df -h / | awk 'NR==2 {print $4}')

	# 移除单位字符，例如"GB"，并将剩余空间转换为数字
	available_space=$(echo "$available_space" | sed 's/G//')

	# 如果剩余空间小于等于0，则输出警告信息
	if [ $(echo "$available_space <= 0" | bc) -eq 1 ]; then
		echo "警告：磁盘空间已用尽，请勿重启，先清理空间。建议先卸载刚才安装的内核来释放空间，仅供参考。"
	else
		echo "当前磁盘剩余空间：$available_space GB"
	fi
}

#安装BBR内核
installbbr() {
	kernel_version="5.9.6"
	bit=$(uname -m)
	rm -rf bbr
	mkdir bbr && cd bbr || exit

	if [[ "${OS_type}" == "CentOS" ]]; then
		if [[ ${version} == "7" ]]; then
			if [[ ${bit} == "x86_64" ]]; then
				echo -e "如果下载地址出错，可能当前正在更新，超过半天还是出错请反馈，大陆自行解决污染问题"

				headurl=https://github.com/torr9522/Linux-NetSpeed/releases/download/Centos_Kernel_6.1.35_latest_bbr_2023.06.22-0855/kernel-headers-6.1.35-1.x86_64.rpm
				imgurl=https://github.com/torr9522/Linux-NetSpeed/releases/download/Centos_Kernel_6.1.35_latest_bbr_2023.06.22-0855/kernel-6.1.35-1.x86_64.rpm

				check_empty $imgurl
				headurl=$(check_cn $headurl)
				imgurl=$(check_cn $imgurl)

				download_file "$headurl" kernel-headers-c7.rpm
				download_file "$imgurl" kernel-c7.rpm
				yum install -y kernel-c7.rpm
				yum install -y kernel-headers-c7.rpm
			else
				echo -e "${Error} 不支持x86_64以外的系统 !" && exit 1
			fi
		fi

		elif [[ "${OS_type}" == "Debian" ]]; then
			if [[ ${bit} == "x86_64" ]]; then
				echo -e "如果下载地址出错，可能当前正在更新，超过半天还是出错请反馈，大陆自行解决污染问题"
				releases_json=$(curl -fsSL 'https://api.github.com/repos/torr9522/Linux-NetSpeed/releases' 2>/dev/null || true)
				github_tag=$(printf '%s\n' "$releases_json" | grep 'Debian_Kernel' | grep '_latest_bbr_' | head -n 1 | awk -F '"' '{print $4}' | awk -F '[/]' '{print $8}')
				release_api="https://api.github.com/repos/torr9522/Linux-NetSpeed/releases/tags/${github_tag}"
				release_json=$(curl -fsSL "$release_api" 2>/dev/null || true)
				github_ver=$(printf '%s\n' "$release_json" | awk -F '"' '/browser_download_url/ && /linux-headers/ && /amd64\.deb/ {print $4; exit}' | awk -F '[/]' '{print $9}' | awk -F '[-]' '{print $3}' | awk -F '[_]' '{print $1}')
				check_empty "$github_ver"
				echo -e "获取的版本号为:${Green_font_prefix}${github_ver}${Font_color_suffix}"
				kernel_version=$github_ver
				detele_kernel_head
				headurl=$(printf '%s\n' "$release_json" | awk -F '"' '/browser_download_url/ && /linux-headers/ && /amd64\.deb/ {print $4; exit}')
				imgurl=$(printf '%s\n' "$release_json" | awk -F '"' '/browser_download_url/ && /linux-image/ && /amd64\.deb/ {print $4; exit}')

			check_empty "$headurl"
			check_empty "$imgurl"
			headurl=$(check_cn "$headurl")
			imgurl=$(check_cn "$imgurl")

			download_file "$headurl" linux-headers-d10.deb
			download_file "$imgurl" linux-image-d10.deb
			dpkg -i linux-image-d10.deb
			dpkg -i linux-headers-d10.deb
			elif [[ ${bit} == "aarch64" ]]; then
				echo -e "如果下载地址出错，可能当前正在更新，超过半天还是出错请反馈，大陆自行解决污染问题"
				releases_json=$(curl -fsSL 'https://api.github.com/repos/torr9522/Linux-NetSpeed/releases' 2>/dev/null || true)
				github_tag=$(printf '%s\n' "$releases_json" | grep 'Debian_Kernel' | grep '_arm64_' | grep '_bbr_' | head -n 1 | awk -F '"' '{print $4}' | awk -F '[/]' '{print $8}')
				release_api="https://api.github.com/repos/torr9522/Linux-NetSpeed/releases/tags/${github_tag}"
				release_json=$(curl -fsSL "$release_api" 2>/dev/null || true)
				github_ver=$(printf '%s\n' "$release_json" | awk -F '"' '/browser_download_url/ && /linux-headers/ && /arm64\.deb/ {print $4; exit}' | awk -F '[/]' '{print $9}' | awk -F '[-]' '{print $3}' | awk -F '[_]' '{print $1}')
				echo -e "获取的版本号为:${Green_font_prefix}${github_ver}${Font_color_suffix}"
				kernel_version=$github_ver
				detele_kernel_head
				headurl=$(printf '%s\n' "$release_json" | awk -F '"' '/browser_download_url/ && /linux-headers/ && /arm64\.deb/ {print $4; exit}')
				imgurl=$(printf '%s\n' "$release_json" | awk -F '"' '/browser_download_url/ && /linux-image/ && /arm64\.deb/ {print $4; exit}')

			check_empty "$headurl"
			check_empty "$imgurl"
			headurl=$(check_cn "$headurl")
			imgurl=$(check_cn "$imgurl")

			download_file "$headurl" linux-headers-d10.deb
			download_file "$imgurl" linux-image-d10.deb
			dpkg -i linux-image-d10.deb
			dpkg -i linux-headers-d10.deb
		else
			echo -e "${Error} 不支持x86_64及arm64/aarch64以外的系统 !" && exit 1
		fi
	fi

	cd .. && rm -rf bbr

	BBR_grub
	show_kernel_install_finish_notice
	check_kernel
}

#安装BBRplus内核 4.14.129
installbbrplus() {
	kernel_version="4.14.160-bbrplus"
	bit=$(uname -m)
	rm -rf bbrplus
	mkdir bbrplus && cd bbrplus || exit
	if [[ "${OS_type}" == "CentOS" ]]; then
		if [[ ${version} == "7" ]]; then
			if [[ ${bit} == "x86_64" ]]; then
				kernel_version="4.14.129_bbrplus"
				detele_kernel_head
				headurl=https://raw.githubusercontent.com/torr9522/Linux-NetSpeed/tcpx.sh/bbrplus/centos/7/kernel-headers-4.14.129-bbrplus.rpm
				imgurl=https://raw.githubusercontent.com/torr9522/Linux-NetSpeed/tcpx.sh/bbrplus/centos/7/kernel-4.14.129-bbrplus.rpm

				headurl=$(check_cn $headurl)
				imgurl=$(check_cn $imgurl)

				download_file "$headurl" kernel-headers-c7.rpm
				download_file "$imgurl" kernel-c7.rpm
				yum install -y kernel-c7.rpm
				yum install -y kernel-headers-c7.rpm
			else
				echo -e "${Error} 不支持x86_64以外的系统 !" && exit 1
			fi
		fi

	elif [[ "${OS_type}" == "Debian" ]]; then
		if [[ ${bit} == "x86_64" ]]; then
			kernel_version="4.14.129-bbrplus"
			detele_kernel_head
			headurl=https://raw.githubusercontent.com/torr9522/Linux-NetSpeed/tcpx.sh/bbrplus/debian-ubuntu/x64/linux-headers-4.14.129-bbrplus.deb
			imgurl=https://raw.githubusercontent.com/torr9522/Linux-NetSpeed/tcpx.sh/bbrplus/debian-ubuntu/x64/linux-image-4.14.129-bbrplus.deb

			headurl=$(check_cn $headurl)
			imgurl=$(check_cn $imgurl)

			wget -O linux-headers.deb "$headurl"
			wget -O linux-image.deb "$imgurl"

			dpkg -i linux-image.deb
			dpkg -i linux-headers.deb
		else
			echo -e "${Error} 不支持x86_64以外的系统 !" && exit 1
		fi
	fi

	cd .. && rm -rf bbrplus
	BBR_grub
	show_kernel_install_finish_notice
	check_kernel
}

#安装xanmod内核  from xanmod.org
installxanmod() {
	echo -e "xanmod这个自编译版本不维护了，后续请用官方编译版本，知悉."
	#https://api.github.com/repos/ylx2016/kernel/releases?page=1&per_page=100
	#releases?page=1&per_page=100
	kernel_version="5.5.1-xanmod1"
	bit=$(uname -m)
	if [[ ${bit} != "x86_64" ]]; then
		echo -e "${Error} 不支持x86_64以外的系统 !" && exit 1
	fi
	rm -rf xanmod
	mkdir xanmod && cd xanmod || exit
	if [[ "${OS_type}" == "CentOS" ]]; then
		if [[ ${version} == "7" ]]; then
			if [[ ${bit} == "x86_64" ]]; then
				echo -e "如果下载地址出错，可能当前正在更新，超过半天还是出错请反馈，大陆自行解决污染问题"
				headurl=https://github.com/torr9522/Linux-NetSpeed/releases/download/Centos_Kernel_5.15.95-xanmod1_lts_latest_2023.02.24-2159/kernel-headers-5.15.95_xanmod1-1.x86_64.rpm
				imgurl=https://github.com/torr9522/Linux-NetSpeed/releases/download/Centos_Kernel_5.15.95-xanmod1_lts_latest_2023.02.24-2159/kernel-5.15.95_xanmod1-1.x86_64.rpm

				check_empty $imgurl
				headurl=$(check_cn $headurl)
				imgurl=$(check_cn $imgurl)

				download_file "$headurl" kernel-headers-c7.rpm
				download_file "$imgurl" kernel-c7.rpm
				yum install -y kernel-c7.rpm
				yum install -y kernel-headers-c7.rpm
			else
				echo -e "${Error} 不支持x86_64以外的系统 !" && exit 1
			fi
		elif [[ ${version} == "8" ]]; then
			echo -e "如果下载地址出错，可能当前正在更新，超过半天还是出错请反馈，大陆自行解决污染问题"
			headurl=https://github.com/torr9522/Linux-NetSpeed/releases/download/Centos_Kernel_5.15.81-xanmod1_lts_C8_latest_2022.12.06-1614/kernel-headers-5.15.81_xanmod1-1.x86_64.rpm
			imgurl=https://github.com/torr9522/Linux-NetSpeed/releases/download/Centos_Kernel_5.15.81-xanmod1_lts_C8_latest_2022.12.06-1614/kernel-5.15.81_xanmod1-1.x86_64.rpm

			check_empty $imgurl
			headurl=$(check_cn $headurl)
			imgurl=$(check_cn $imgurl)

			wget -O kernel-headers-c8.rpm "$headurl"
			wget -O kernel-c8.rpm "$imgurl"
			yum install -y kernel-c8.rpm
			yum install -y kernel-headers-c8.rpm
		fi

	elif [[ "${OS_type}" == "Debian" ]]; then

		if [[ ${bit} == "x86_64" ]]; then
			echo -e "如果下载地址出错，可能当前正在更新，超过半天还是出错请反馈，大陆自行解决污染问题"
			headurl=https://github.com/torr9522/Linux-NetSpeed/releases/download/Debian_Kernel_5.15.95-xanmod1_lts_latest_2023.02.24-2210/linux-headers-5.15.95-xanmod1_5.15.95-xanmod1-1_amd64.deb
			imgurl=https://github.com/torr9522/Linux-NetSpeed/releases/download/Debian_Kernel_5.15.95-xanmod1_lts_latest_2023.02.24-2210/linux-image-5.15.95-xanmod1_5.15.95-xanmod1-1_amd64.deb

			check_empty $imgurl
			headurl=$(check_cn $headurl)
			imgurl=$(check_cn $imgurl)

			download_file "$headurl" linux-headers-d10.deb
			download_file "$imgurl" linux-image-d10.deb
			dpkg -i linux-image-d10.deb
			dpkg -i linux-headers-d10.deb
		else
			echo -e "${Error} 不支持x86_64以外的系统 !" && exit 1
		fi
	fi

	#cd .. && rm -rf xanmod
	BBR_grub
	show_kernel_install_finish_notice
	check_kernel
}

#启用BBR+fq
startbbrfq() {
	remove_bbr_lotserver
	echo "net.core.default_qdisc=fq" >>/etc/sysctl.d/99-sysctl.conf
	echo "net.ipv4.tcp_congestion_control=bbr" >>/etc/sysctl.d/99-sysctl.conf
	sysctl --system
	echo -e "${Info}BBR+FQ修改成功，重启生效！"
}

#启用BBR+fq_pie
startbbrfqpie() {
	remove_bbr_lotserver
	echo "net.core.default_qdisc=fq_pie" >>/etc/sysctl.d/99-sysctl.conf
	echo "net.ipv4.tcp_congestion_control=bbr" >>/etc/sysctl.d/99-sysctl.conf
	sysctl --system
	echo -e "${Info}BBR+FQ_PIE修改成功，重启生效！"
}

#启用BBR+cake
startbbrcake() {
	remove_bbr_lotserver
	echo "net.core.default_qdisc=cake" >>/etc/sysctl.d/99-sysctl.conf
	echo "net.ipv4.tcp_congestion_control=bbr" >>/etc/sysctl.d/99-sysctl.conf
	sysctl --system
	echo -e "${Info}BBR+cake修改成功，重启生效！"
}

#启用BBR2+FQ
startbbr2fq() {
	remove_bbr_lotserver
	echo "net.core.default_qdisc=fq" >>/etc/sysctl.d/99-sysctl.conf
	echo "net.ipv4.tcp_congestion_control=bbr" >>/etc/sysctl.d/99-sysctl.conf
	sysctl --system
	echo -e "${Info}BBR3修改成功，重启生效！"
}

#启用BBR2+FQ_PIE
startbbr2fqpie() {
	remove_bbr_lotserver
	echo "net.core.default_qdisc=fq_pie" >>/etc/sysctl.d/99-sysctl.conf
	echo "net.ipv4.tcp_congestion_control=bbr" >>/etc/sysctl.d/99-sysctl.conf
	sysctl --system
	echo -e "${Info}BBR3修改成功，重启生效！"
}

#启用BBR2+CAKE
startbbr2cake() {
	remove_bbr_lotserver
	echo "net.core.default_qdisc=cake" >>/etc/sysctl.d/99-sysctl.conf
	echo "net.ipv4.tcp_congestion_control=bbr" >>/etc/sysctl.d/99-sysctl.conf
	sysctl --system
	echo -e "${Info}BBR3修改成功，重启生效！"
}

#卸载bbr+锐速
remove_bbr_lotserver() {
	sed -i '/net.ipv4.tcp_ecn/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.core.default_qdisc/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv4.tcp_ecn/d' /etc/sysctl.conf
	sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
	sysctl --system

	rm -rf bbrmod

	if [[ -e /appex/bin/lotServer.sh ]]; then
		echo | bash <(wget -qO- https://raw.githubusercontent.com/torr9522/Linux-NetSpeed/tcpx.sh/selfhost/lotServerInstall.sh) uninstall
	fi
	clear
	# echo -e "${Info}:清除bbr/lotserver加速完成。"
	# sleep 1s
}

#卸载全部加速
remove_all() {
	rm -rf /etc/sysctl.d/*.conf
	#rm -rf /etc/sysctl.conf
	#touch /etc/sysctl.conf
	if [ ! -f "/etc/sysctl.conf" ]; then
		touch /etc/sysctl.conf
	else
		cat /dev/null >/etc/sysctl.conf
	fi
	sysctl --system
	sed -i '/DefaultTimeoutStartSec/d' /etc/systemd/system.conf
	sed -i '/DefaultTimeoutStopSec/d' /etc/systemd/system.conf
	sed -i '/DefaultRestartSec/d' /etc/systemd/system.conf
	sed -i '/DefaultLimitCORE/d' /etc/systemd/system.conf
	sed -i '/DefaultLimitNOFILE/d' /etc/systemd/system.conf
	sed -i '/DefaultLimitNPROC/d' /etc/systemd/system.conf

	sed -i '/soft nofile/d' /etc/security/limits.conf
	sed -i '/hard nofile/d' /etc/security/limits.conf
	sed -i '/soft nproc/d' /etc/security/limits.conf
	sed -i '/hard nproc/d' /etc/security/limits.conf

	sed -i '/ulimit -SHn/d' /etc/profile
	sed -i '/ulimit -SHn/d' /etc/profile
	sed -i '/required pam_limits.so/d' /etc/pam.d/common-session

	systemctl daemon-reload

	rm -rf bbrmod
	sed -i '/net.ipv4.tcp_retries2/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_slow_start_after_idle/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_fastopen/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_ecn/d' /etc/sysctl.conf
	sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
	sed -i '/fs.file-max/d' /etc/sysctl.conf
	sed -i '/net.core.rmem_max/d' /etc/sysctl.conf
	sed -i '/net.core.wmem_max/d' /etc/sysctl.conf
	sed -i '/net.core.rmem_default/d' /etc/sysctl.conf
	sed -i '/net.core.wmem_default/d' /etc/sysctl.conf
	sed -i '/net.core.netdev_max_backlog/d' /etc/sysctl.conf
	sed -i '/net.core.somaxconn/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_syncookies/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_tw_reuse/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_tw_recycle/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_fin_timeout/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_keepalive_time/d' /etc/sysctl.conf
	sed -i '/net.ipv4.ip_local_port_range/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_max_syn_backlog/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_max_tw_buckets/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_rmem/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_wmem/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_mtu_probing/d' /etc/sysctl.conf
	sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
	sed -i '/fs.inotify.max_user_instances/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_syncookies/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_fin_timeout/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_tw_reuse/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_max_syn_backlog/d' /etc/sysctl.conf
	sed -i '/net.ipv4.ip_local_port_range/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_max_tw_buckets/d' /etc/sysctl.conf
	sed -i '/net.ipv4.route.gc_timeout/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_synack_retries/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_syn_retries/d' /etc/sysctl.conf
	sed -i '/net.core.somaxconn/d' /etc/sysctl.conf
	sed -i '/net.core.netdev_max_backlog/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_timestamps/d' /etc/sysctl.conf
	sed -i '/net.ipv4.tcp_max_orphans/d' /etc/sysctl.conf
	if [[ -e /appex/bin/lotServer.sh ]]; then
		bash <(wget -qO- https://raw.githubusercontent.com/torr9522/Linux-NetSpeed/tcpx.sh/selfhost/lotServerInstall.sh) uninstall
	fi
	clear
	echo -e "${Info}:清除加速完成。"
	sleep 1s
}

#切换到卸载内核版本
gototcp() {
	clear
	run_local_or_remote_script \
		"${PEER_SCRIPT_REMOTE_URL}" \
		"tcp.sh" \
		"../Linux-NetSpeed-tcp/tcp.sh"
}

#切换到秋水逸冰BBR安装脚本
gototeddysun_bbr() {
	clear
	bash <(wget -qO- https://raw.githubusercontent.com/torr9522/Linux-NetSpeed/tcpx.sh/selfhost/bbr.sh)
}

#切换到一键DD安装系统脚本 新手勿入
gotodd() {
	clear
	echo DD使用git.beta.gs的脚本，知悉
	sleep 1.5
	bash <(wget -qO- https://raw.githubusercontent.com/torr9522/Linux-NetSpeed/tcpx.sh/selfhost/NewReinstall.sh)
}

#切换到检查当前IP质量/媒体解锁/邮箱通信脚本
gotoipcheck() {
	clear
	sleep 1.5
	bash <(wget -qO- https://raw.githubusercontent.com/torr9522/Linux-NetSpeed/tcpx.sh/selfhost/ip.sh)
	#bash <(wget -qO- https://IP.Check.Place)
}

#禁用IPv6
closeipv6() {
	clear
	sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv6.conf.lo.disable_ipv6/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
	sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf
	sed -i '/net.ipv6.conf.lo.disable_ipv6/d' /etc/sysctl.conf

	echo "net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1" >>/etc/sysctl.d/99-sysctl.conf
	sysctl --system
	echo -e "${Info}禁用IPv6结束，可能需要重启！"
}

#开启IPv6
openipv6() {
	clear
	sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv6.conf.lo.disable_ipv6/d' /etc/sysctl.d/99-sysctl.conf
	sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
	sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf
	sed -i '/net.ipv6.conf.lo.disable_ipv6/d' /etc/sysctl.conf
	sed -i '/net.ipv6.conf.all.accept_ra/d' /etc/sysctl.conf
	sed -i '/net.ipv6.conf.default.accept_ra/d' /etc/sysctl.conf

	echo "net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.lo.disable_ipv6 = 0
net.ipv6.conf.all.accept_ra = 2
net.ipv6.conf.default.accept_ra = 2" >>/etc/sysctl.d/99-sysctl.conf
	sysctl --system
	echo -e "${Info}开启IPv6结束，可能需要重启！"
}

#开始菜单
start_menu() {
	clear
	echo && echo -e "TCP加速 一键安装管理脚本 ${Red_font_prefix}[v${sh_ver%-local}] ${KERNEL_MODE_BANNER}${Font_color_suffix}  母鸡慎用
${Green_font_prefix}0.${Font_color_suffix} 切换到卸载内核版本
${Green_font_prefix}18.${Font_color_suffix} 切换到一键DD系统脚本
${Green_font_prefix}19.${Font_color_suffix} 切换到检查当前IP质量/媒体解锁/邮箱通信脚本
 ———————————————————————————— 内核安装 —————————————————————————————
 ${Green_font_prefix}1.${Font_color_suffix} 安装 BBR原版内核              ${Green_font_prefix}2.${Font_color_suffix} XanMod Kernel（支持 BBR3）
 ———————————————————————————— 加速启用 —————————————————————————————
 ${Green_font_prefix}3.${Font_color_suffix} 使用BBR+FQ加速                       ${Green_font_prefix}6.${Font_color_suffix} 使用BBR3+FQ加速
 ${Green_font_prefix}4.${Font_color_suffix} 使用BBR+FQ_PIE加速                 ${Green_font_prefix}7.${Font_color_suffix} 使用BBR3+FQ_PIE加速
 ${Green_font_prefix}5.${Font_color_suffix} 使用BBR+CAKE加速                   ${Green_font_prefix}8.${Font_color_suffix} 使用BBR3+CAKE加速
 ———————————————————————————— 系统配置 —————————————————————————————
${Green_font_prefix}9.${Font_color_suffix} 系统配置优化旧                ${Green_font_prefix}10.${Font_color_suffix} 系统配置优化新
${Green_font_prefix}11.${Font_color_suffix} 禁用IPv6                        ${Green_font_prefix}12.${Font_color_suffix} 开启IPv6
${Green_font_prefix}13.${Font_color_suffix} 手动提交合并内核参数     ${Green_font_prefix}14.${Font_color_suffix} 手动编辑内核参数
 ———————————————————————————— 内核管理 —————————————————————————————
${Green_font_prefix}15.${Font_color_suffix} 查看排序内核             ${Green_font_prefix}16.${Font_color_suffix} 删除保留指定内核
${Green_font_prefix}17.${Font_color_suffix} 卸载全部加速             ${Green_font_prefix}99.${Font_color_suffix} 退出脚本
————————————————————————————————————————————————————————————————" &&
		check_status
	get_system_info
	echo -e " 信息： ${Font_color_suffix}$opsy ${Green_font_prefix}$virtual${Font_color_suffix} $arch ${Green_font_prefix}$kern${Font_color_suffix} "
	if [[ ${kernel_status} == "noinstall" ]]; then
		echo -e " 状态: ${Green_font_prefix}未安装${Font_color_suffix} 加速内核 ${Red_font_prefix}请先安装内核${Font_color_suffix}"
	else
		echo -e " 状态: ${Green_font_prefix}已安装${Font_color_suffix} ${Red_font_prefix}${kernel_status}${Font_color_suffix} 加速内核 , ${Green_font_prefix}${run_status}${Font_color_suffix} ${Red_font_prefix}${brutal}${Font_color_suffix}"

	fi
	echo -e " 拥塞控制算法:: ${Green_font_prefix}${net_congestion_control}${Font_color_suffix} 队列算法: ${Green_font_prefix}${net_qdisc}${Font_color_suffix} 内核headers：${Green_font_prefix}${headers_status}${Font_color_suffix}"

	read -p " 请输入数字 :" num
	case "$num" in
	0)
		gototcp
		;;
	1)
		run_menu_action_with_auto_reboot 1 check_sys_bbr
		;;
	2)
		run_menu_action_with_auto_reboot 2 check_sys_xanmod_main_kept
		;;
	3)
		run_menu_action_with_auto_reboot 3 startbbrfq
		;;
	4)
		run_menu_action_with_auto_reboot 4 startbbrfqpie
		;;
	5)
		run_menu_action_with_auto_reboot 5 startbbrcake
		;;
	6)
		run_menu_action_with_auto_reboot 6 startbbr2fq
		;;
	7)
		run_menu_action_with_auto_reboot 7 startbbr2fqpie
		;;
	8)
		run_menu_action_with_auto_reboot 8 startbbr2cake
		;;
	9)
		run_menu_action_with_auto_reboot 9 optimizing_system_old
		;;
	10)
		run_menu_action_with_auto_reboot 10 optimizing_system_johnrosen1
		;;
	11)
		closeipv6
		;;
	12)
		openipv6
		;;
	13)
		update_sysctl_interactive
		;;
	14)
		edit_sysctl_interactive
		;;
	15)
		BBR_grub
		;;
	16)
		detele_kernel_custom
		;;
	17)
		remove_all
		;;
	18)
		gotodd
		;;
	19)
		gotoipcheck
		;;
	99)
		exit 1
		;;
	*)
		clear
		echo -e "${Error}:请输入正确数字 [0-99]"
		sleep 5s
		start_menu
		;;
	esac
}
#############内核管理组件#############

#删除多余内核
detele_kernel() {
	local kernels=()
	local pkg=""

	if [[ "${AUTO_CLEAN_OLD_KERNELS}" != "1" ]]; then
		echo -e "${Info} 当前模式保留旧 image 内核，跳过清理。"
		return 0
	fi

	if [[ "${OS_type}" == "CentOS" ]]; then
		mapfile -t kernels < <(rpm -qa | grep '^kernel' | grep -v "${kernel_version}" | grep -v 'noarch' || true)
	elif [[ "${OS_type}" == "Debian" ]]; then
		mapfile -t kernels < <(dpkg -l | awk '/^ii/ {print $2}' | grep '^linux-image' | grep -v "${kernel_version}" || true)
	fi

	if (( ${#kernels[@]} == 0 )); then
		echo -e "${Info} 未检测到需要卸载的旧 image 内核。"
		return 0
	fi

	echo -e "${Info} 检测到 ${#kernels[@]} 个其余内核，开始卸载..."
	for pkg in "${kernels[@]}"; do
		echo -e "${Info} 开始卸载 ${pkg} 内核..."
		if [[ "${OS_type}" == "CentOS" ]]; then
			rpm --nodeps -e "${pkg}"
		else
			apt-get purge -y "${pkg}"
			apt-get autoremove -y
		fi
		echo -e "${Info} 卸载 ${pkg} 内核完成，继续..."
	done

	echo -e "${Info} 内核卸载完毕，继续..."
}

detele_kernel_head() {
	local kernels=()
	local pkg=""

	if [[ "${AUTO_CLEAN_OLD_KERNELS}" != "1" ]]; then
		echo -e "${Info} 当前模式保留旧 headers 内核，跳过清理。"
		return 0
	fi

	if [[ "${OS_type}" == "CentOS" ]]; then
		mapfile -t kernels < <(rpm -qa | grep '^kernel-headers' | grep -v "${kernel_version}" | grep -v 'noarch' || true)
	elif [[ "${OS_type}" == "Debian" ]]; then
		mapfile -t kernels < <(dpkg -l | awk '/^ii/ {print $2}' | grep '^linux-headers' | grep -v "${kernel_version}" || true)
	fi

	if (( ${#kernels[@]} == 0 )); then
		echo -e "${Info} 未检测到需要卸载的旧 headers 内核。"
		return 0
	fi

	echo -e "${Info} 检测到 ${#kernels[@]} 个其余 headers 内核，开始卸载..."
	for pkg in "${kernels[@]}"; do
		echo -e "${Info} 开始卸载 ${pkg} headers 内核..."
		if [[ "${OS_type}" == "CentOS" ]]; then
			rpm --nodeps -e "${pkg}"
		else
			apt-get purge -y "${pkg}"
			apt-get autoremove -y
		fi
		echo -e "${Info} 卸载 ${pkg} headers 内核完成，继续..."
	done

	echo -e "${Info} headers 内核卸载完毕，继续..."
}

detele_kernel_custom() {
	BBR_grub
	read -p " 查看上面内核输入需保留保留保留的内核关键词(如:5.15.0-11) :" kernel_version
	detele_kernel
	detele_kernel_head
	BBR_grub
}

#-----------------------------------------------------------------------
# 函数: update_sysctl_interactive (V4 - 增加错误忽略参数)
# 功能: 以交互方式安全地更新 sysctl 配置文件并应用。
#       命令执行失败时，将不会回滚文件更改。
#-----------------------------------------------------------------------
update_sysctl_interactive() {
	# 强制使用C语言环境，确保正则表达式的行为可预测且一致。
	local LC_ALL=C

	# --- 配置与参数解析 ---
	local CONF_FILE="/etc/sysctl.d/99-sysctl.conf"
	local TMP_FILE
	local BACKUP_FILE
	local ignore_apply_error=true

	# --- 帮助函数 ---
	log_info() {
		echo "[INFO] $1"
	}

	log_error() {
		echo "[ERROR] $1" >&2
	}

	log_warn() {
		echo "[WARN] $1" >&2
	}

	# --- 主逻辑 ---

	# 1. 权限检查
	if [[ $EUID -ne 0 ]]; then
		log_error "此函数必须以 root 权限运行，请使用 sudo。"
		return 1
	fi

	# 2. 交互式获取用户输入
	log_info "请输入或粘贴您要设置的 sysctl 参数 (格式: key = value)。"
	log_info "可参考TCP迷之调参，https://omnitt.com/"
	log_info "注释行(以 # 或 ; 开头)和空行将被忽略。"
	log_info "最后一行请以空行结束 可手动回车加一行空行"
	log_info "输入完成后，请按 Ctrl+D 结束输入。"

	readarray -t user_input

	if [ ${#user_input[@]} -eq 0 ]; then
		log_info "没有接收到任何输入，操作已取消。"
		return 0
	fi

	# 确保配置文件存在
	touch "$CONF_FILE"

	# 3. 创建临时文件
	TMP_FILE=$(mktemp) || {
		log_error "无法创建临时文件"
		return 1
	}
	trap 'rm -f "$TMP_FILE"' RETURN

	cp "$CONF_FILE" "$TMP_FILE"

	local -A params_to_add
	local all_params_valid=true

	# 4. 预处理所有输入，检查合法性
	log_info "正在校验所有输入参数..."
	for line in "${user_input[@]}"; do
		trimmed_line=$(echo "$line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

		if [[ -z "$trimmed_line" ]] || [[ "$trimmed_line" =~ ^[[:space:]]*[#\;] ]]; then
			continue
		fi

		if ! [[ "$trimmed_line" =~ ^[[:space:]]*([a-zA-Z0-9._-]+)[[:space:]]*=[[:space:]]*(.*)[[:space:]]*$ ]]; then
			log_error "格式无效: '$trimmed_line'. 期望格式为 'key = value'."
			all_params_valid=false
			continue
		fi

		local key="${BASH_REMATCH[1]}"
		local value="${BASH_REMATCH[2]}"

		if ! sysctl -N "$key" >/dev/null 2>&1; then
			log_error "参数键名无效: '$key' 不是一个有效的内核参数。"
			all_params_valid=false
			continue
		fi

		local formatted_param="$key = $value"

		if grep -q -E "^[[:space:]]*${key//./\\.}([[:space:]]*)=.*" "$TMP_FILE"; then
			sed -i -E "s|^[[:space:]]*${key//./\\.}([[:space:]]*)=.*|$formatted_param|" "$TMP_FILE"
			log_info "已更新参数: $formatted_param"
		else
			if [[ -z "${params_to_add[$key]}" ]]; then
				params_to_add["$key"]="$formatted_param"
			fi
		fi
	done

	if ! $all_params_valid; then
		log_error "检测到无效参数，操作已中止。配置文件未做任何更改。"
		return 1
	fi

	# 5. 将所有新参数追加到临时文件末尾
	if [ ${#params_to_add[@]} -gt 0 ]; then
		log_info "正在添加新参数..."
		echo "" >>"$TMP_FILE"
		for key in "${!params_to_add[@]}"; do
			echo "${params_to_add[$key]}" >>"$TMP_FILE"
			log_info "已添加新参数: ${params_to_add[$key]}"
		done
	fi

	# 6. 原子替换与应用
	BACKUP_FILE="${CONF_FILE}.bak_$(date +%Y%m%d_%H%M%S)"
	cp "$CONF_FILE" "$BACKUP_FILE"
	log_info "原始文件已备份到 $BACKUP_FILE"

	mv "$TMP_FILE" "$CONF_FILE"
	chown root:root "$CONF_FILE"
	chmod 644 "$CONF_FILE"
	trap - RETURN

	# 7. 应用配置并进行错误处理
	log_info "正在应用新�� sysctl 设置..."
	if apply_output=$(sysctl -p "$CONF_FILE" 2>&1); then
		log_info "Sysctl 设置已成功应用。"
		echo "--- 应用输出 ---"
		echo "$apply_output"
		echo "------------------"
		rm -f "$BACKUP_FILE"
	else
		# 应用失败时的逻辑
		if [[ "$ignore_apply_error" == "true" ]]; then
			log_warn "应用 sysctl 设置失败，但根据指令已忽略错误。"
			log_warn "配置文件 '${CONF_FILE}' 已被更新，但部分设置可能未生效。"
			log_warn "--- 错误详情 ---"
			echo "$apply_output" >&2
			echo "------------------"
			rm -f "$BACKUP_FILE" # 忽略错误，所以也删除备份
			return 0             # 返回成功状态
		else
			log_error "应用 sysctl 设置失败！正在回滚..."
			log_error "--- 错误详情 ---"
			echo "$apply_output"
			echo "------------------"

			mv "$BACKUP_FILE" "$CONF_FILE"
			log_info "正在恢复到之前的设置..."
			sysctl -p "$CONF_FILE" >/dev/null 2>&1

			log_error "回滚完成。配置文件已恢复，问题备份文件保留在 $BACKUP_FILE"
			return 1
		fi
	fi

	return 0
}

edit_sysctl_interactive() {
	local target_file="/etc/sysctl.d/99-sysctl.conf"
	local editor_cmd=""

	# --- 1. 检查文件是否存在 ---
	if [ ! -f "$target_file" ]; then
		echo "文件 $target_file 不存在。"
		# (Y/n) 格式，n/N 以外的任何输入（包括回车）都将继续
		read -r -p "您想现在创建并编辑它吗？ (Y/n): " create_choice

		case "$create_choice" in
		[nN])
			echo "操作已取消。"
			return 0 # 0 表示成功（用户主动取消）
			;;
		*)
			echo "好的，准备创建并打开编辑器..."
			# 注意：我们不需要在这里 'touch' 文件。
			# 'sudo' 配合编辑器（如 nano 或 vi）在保存时会自动创建文件。
			;;
		esac
	fi

	# --- 2. 检查并选择编辑器 ---
	if command -v nano >/dev/null; then
		# 优先使用 nano
		editor_cmd="nano"
	else
		# nano 不存在，提示安装
		echo "首选编辑器 'nano' 未安装。"
		# (Y/n) 格式，n/N 以外的任何输入（包括回车）都将继续
		read -r -p "您想现在安装 'nano' 吗？ (Y/n): " install_choice

		case "$install_choice" in
		[nN])
			# 用户不安装，回退到 vi
			echo "好的，将使用 'vi' 编辑器。"
			echo "提示：'vi' 启动后，按 'i' 键进入插入模式，'Esc' 键退出插入模式，"
			echo "   然后输入 ':wq' 保存并退出，或 ':q!' 不保存退出。"
			editor_cmd="vi"
			;;
		*)
			# 这是一个安全的设计：函数不应该自己执行安装。
			# 它应该指导用户，然后退出，让用户安装后重试。
			echo "请在您的终端中运行:"
			echo "  sudo apt install nano  (适用于 Debian/Ubuntu)"
			echo "  sudo dnf install nano  (适用于 Fedora/RHEL 8+)"
			echo "  sudo yum install nano  (适用于 CentOS 7)"
			echo "安装完成后，请重新运行此函数。"
			echo "操作已取消。"
			return 1 # 1 表示一个非0的退出码，表示未完成
			;;
		esac
	fi

	# --- 3. 执行编辑 ---
	echo "正在使用 $editor_cmd 打开 $target_file..."
	echo "请注意：编辑系统文件需要管理员权限，您可能需要输入密码。"

	# 使用 sudo 来运行编辑器，以便有权限写入 /etc/sysctl.d/ 目录
	if ! sudo "$editor_cmd" "$target_file"; then
		echo "编辑器 '$editor_cmd' 启动失败或异常退出。"
		echo "请检查您的 sudo 权限或编辑器是否正确安装。"
		return 1
	fi

	# --- 4. (修改) 默认直接应用 ---
	echo ""
	echo "编辑完成。"
	echo "正在应用 $target_file 中的设置..."

	# -p 参数会从指定文件中加载设置
	sudo sysctl -p "$target_file"
	echo "已执行应用，部分可能需要重启生效"
}

#更新引导
BBR_grub() {
	if [[ "${OS_type}" == "CentOS" ]]; then
		if [[ ${version} == "6" ]]; then
			if [ -f "/boot/grub/grub.conf" ]; then
				sed -i 's/^default=.*/default=0/g' /boot/grub/grub.conf
			elif [ -f "/boot/grub/grub.cfg" ]; then
				grub-mkconfig -o /boot/grub/grub.cfg
				grub-set-default 0
			elif [ -f "/boot/efi/EFI/centos/grub.cfg" ]; then
				grub-mkconfig -o /boot/efi/EFI/centos/grub.cfg
				grub-set-default 0
			elif [ -f "/boot/efi/EFI/redhat/grub.cfg" ]; then
				grub-mkconfig -o /boot/efi/EFI/redhat/grub.cfg
				grub-set-default 0
			else
				echo -e "${Error} grub.conf/grub.cfg 找不到，请检查."
				exit
			fi
		elif [[ ${version} == "7" ]]; then
			if [ -f "/boot/grub2/grub.cfg" ]; then
				grub2-mkconfig -o /boot/grub2/grub.cfg
				grub2-set-default 0
			elif [ -f "/boot/efi/EFI/centos/grub.cfg" ]; then
				grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
				grub2-set-default 0
			elif [ -f "/boot/efi/EFI/redhat/grub.cfg" ]; then
				grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg
				grub2-set-default 0
			else
				echo -e "${Error} grub.cfg 找不到，请检查."
				exit
			fi
		elif [[ ${version} == "8" ]]; then
			if [ -f "/boot/grub2/grub.cfg" ]; then
				grub2-mkconfig -o /boot/grub2/grub.cfg
				grub2-set-default 0
			elif [ -f "/boot/efi/EFI/centos/grub.cfg" ]; then
				grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
				grub2-set-default 0
			elif [ -f "/boot/efi/EFI/redhat/grub.cfg" ]; then
				grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg
				grub2-set-default 0
			else
				echo -e "${Error} grub.cfg 找不到，请检查."
				exit
			fi
			grubby --info=ALL | awk -F= '$1=="kernel" {print i++ " : " $2}'
		fi
	elif [[ "${OS_type}" == "Debian" ]]; then
		if _exists "update-grub"; then
			update-grub
		elif [ -f "/usr/sbin/update-grub" ]; then
			/usr/sbin/update-grub
		else
			apt install grub2-common -y
			update-grub
		fi
		set_debian_grub_default_kernel
	fi
	check_disk_space
}

set_debian_grub_default_kernel() {
	local grub_cfg="/boot/grub/grub.cfg"
	local grub_default_file="/etc/default/grub"
	local advanced_title=""
	local entry_title=""
	local default_path=""
	local tmp_file=""

	[[ -n "${kernel_version:-}" ]] || return 0
	[[ -f "${grub_cfg}" ]] || return 0

	advanced_title=$(awk -F"'" '/^submenu / {print $2; exit}' "${grub_cfg}")
	entry_title=$(awk -F"'" -v kv="${kernel_version}" '$0 ~ /^[[:space:]]*menuentry / && $2 ~ ("Linux " kv "($|[[:space:](])") {print $2; exit}' "${grub_cfg}")

	if [[ -z "${entry_title}" ]]; then
		echo -e "${Error} 未在 grub.cfg 中找到目标内核 ${kernel_version} 的菜单项，请检查."
		return 1
	fi

	if [[ -n "${advanced_title}" ]]; then
		default_path="${advanced_title}>${entry_title}"
	else
		default_path="${entry_title}"
	fi

	tmp_file="$(mktemp)"
	awk -v val="GRUB_DEFAULT=\"${default_path}\"" '
		BEGIN { updated = 0 }
		/^GRUB_DEFAULT=/ {
			if (!updated) {
				print val
				updated = 1
			}
			next
		}
		{ print }
		END {
			if (!updated) {
				print val
			}
		}
	' "${grub_default_file}" >"${tmp_file}" && cat "${tmp_file}" >"${grub_default_file}"
	rm -f "${tmp_file}"

	if _exists "update-grub"; then
		update-grub
	elif [ -f "/usr/sbin/update-grub" ]; then
		/usr/sbin/update-grub
	fi

	echo -e "${Info} 已设置 Debian 默认启动内核为: ${kernel_version}"
}

#简单的检查内核
check_kernel() {
	if [[ -z "$(find /boot -type f -name 'vmlinuz-*' ! -name 'vmlinuz-*rescue*')" ]]; then
		echo -e "\033[0;31m警告: 未发现可用内核文件，请勿重启系统，可先使用菜单 30 安装默认内核救急！\033[0m"
	else
		echo -e "\033[0;32m发现内核文件，看起来可以重启。\033[0m"
	fi
}

#############内核管理组件#############

#############系统检测组件#############

#检查系统
check_sys() {
	if [[ -f /etc/redhat-release ]]; then
		release="centos"
	elif grep -qi "debian" /etc/issue; then
		release="debian"
	elif grep -qi "ubuntu" /etc/issue; then
		release="ubuntu"
	elif grep -qi -E "centos|red hat|redhat" /etc/issue || grep -qi -E "centos|red hat|redhat" /proc/version; then
		release="centos"
	fi

	if [[ -f /etc/debian_version ]]; then
		OS_type="Debian"
		echo "检测为Debian通用系统，判断有误请反馈"
	elif [[ -f /etc/redhat-release || -f /etc/centos-release || -f /etc/fedora-release ]]; then
		OS_type="CentOS"
		echo "检测为CentOS通用系统，判断有误请反馈"
	else
		echo "Unknown"
	fi

	#from https://github.com/oooldking

	_exists() {
		local cmd="$1"
		if eval type type >/dev/null 2>&1; then
			eval type "$cmd" >/dev/null 2>&1
		elif command >/dev/null 2>&1; then
			command -v "$cmd" >/dev/null 2>&1
		else
			which "$cmd" >/dev/null 2>&1
		fi
		local rt=$?
		return ${rt}
	}

	get_opsy() {
		if [ -f /etc/os-release ]; then
			awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release
		elif [ -f /etc/lsb-release ]; then
			awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release
		elif [ -f /etc/system-release ]; then
			cat /etc/system-release | awk '{print $1,$2}'
		fi
	}

	get_system_info() {
		opsy=$(get_opsy)
		arch=$(uname -m)
		kern=$(uname -r)
		virt_check
	}
	# from LemonBench
	virt_check() {
		if [ -f "/usr/bin/systemd-detect-virt" ]; then
			Var_VirtType="$(/usr/bin/systemd-detect-virt)"
			# 虚拟机检测
			if [ "${Var_VirtType}" = "qemu" ]; then
				virtual="QEMU"
			elif [ "${Var_VirtType}" = "kvm" ]; then
				virtual="KVM"
			elif [ "${Var_VirtType}" = "zvm" ]; then
				virtual="S390 Z/VM"
			elif [ "${Var_VirtType}" = "vmware" ]; then
				virtual="VMware"
			elif [ "${Var_VirtType}" = "microsoft" ]; then
				virtual="Microsoft Hyper-V"
			elif [ "${Var_VirtType}" = "xen" ]; then
				virtual="Xen Hypervisor"
			elif [ "${Var_VirtType}" = "bochs" ]; then
				virtual="BOCHS"
			elif [ "${Var_VirtType}" = "uml" ]; then
				virtual="User-mode Linux"
			elif [ "${Var_VirtType}" = "parallels" ]; then
				virtual="Parallels"
			elif [ "${Var_VirtType}" = "bhyve" ]; then
				virtual="FreeBSD Hypervisor"
			# 容器虚拟化检测
			elif [ "${Var_VirtType}" = "openvz" ]; then
				virtual="OpenVZ"
			elif [ "${Var_VirtType}" = "lxc" ]; then
				virtual="LXC"
			elif [ "${Var_VirtType}" = "lxc-libvirt" ]; then
				virtual="LXC (libvirt)"
			elif [ "${Var_VirtType}" = "systemd-nspawn" ]; then
				virtual="Systemd nspawn"
			elif [ "${Var_VirtType}" = "docker" ]; then
				virtual="Docker"
			elif [ "${Var_VirtType}" = "rkt" ]; then
				virtual="RKT"
			# 特殊处理
			elif [ -c "/dev/lxss" ]; then # 处理WSL虚拟化
				Var_VirtType="wsl"
				virtual="Windows Subsystem for Linux (WSL)"
			# 未匹配到任何结果, 或者非虚拟机
			elif [ "${Var_VirtType}" = "none" ]; then
				Var_VirtType="dedicated"
				virtual="None"
				local Var_BIOSVendor
				Var_BIOSVendor="$(dmidecode -s bios-vendor)"
				if [ "${Var_BIOSVendor}" = "SeaBIOS" ]; then
					Var_VirtType="Unknown"
					virtual="Unknown with SeaBIOS BIOS"
				else
					Var_VirtType="dedicated"
					virtual="Dedicated with ${Var_BIOSVendor} BIOS"
				fi
			fi
		elif [ ! -f "/usr/sbin/virt-what" ]; then
			Var_VirtType="Unknown"
			virtual="[Error: virt-what not found !]"
		elif [ -f "/.dockerenv" ]; then # 处理Docker虚拟化
			Var_VirtType="docker"
			virtual="Docker"
		elif [ -c "/dev/lxss" ]; then # 处理WSL虚拟化
			Var_VirtType="wsl"
			virtual="Windows Subsystem for Linux (WSL)"
		else # 正常判断流程
			Var_VirtType="$(virt-what | xargs)"
			local Var_VirtTypeCount
			Var_VirtTypeCount="$(echo "$Var_VirtTypeCount" | wc -l)"
			if [ "${Var_VirtTypeCount}" -gt "1" ]; then # 处理嵌套虚拟化
				virtual="echo ${Var_VirtType}"
				Var_VirtType="$(echo "${Var_VirtType}" | head -n1)"                         # 使用检测到的第一种虚拟化继续做判断
			elif [ "${Var_VirtTypeCount}" -eq "1" ] && [ "${Var_VirtType}" != "" ]; then # 只有一种虚拟化
				virtual="${Var_VirtType}"
			else
				local Var_BIOSVendor
				Var_BIOSVendor="$(dmidecode -s bios-vendor)"
				if [ "${Var_BIOSVendor}" = "SeaBIOS" ]; then
					Var_VirtType="Unknown"
					virtual="Unknown with SeaBIOS BIOS"
				else
					Var_VirtType="dedicated"
					virtual="Dedicated with ${Var_BIOSVendor} BIOS"
				fi
			fi
		fi
	}

	#检查依赖
	if [[ "${OS_type}" == "CentOS" ]]; then
		# 检查是否安装了 ca-certificates 包，如果未安装则安装
		if ! rpm -q ca-certificates >/dev/null; then
			echo '正在安装 ca-certificates 包...'
			yum install ca-certificates -y
			update-ca-trust force-enable
		fi
		echo 'CA证书检查OK'

		# 检查并安装 curl、wget、dmidecode 和 redhat-lsb-core 包
		for pkg in curl wget dmidecode redhat-lsb-core; do
			if ! rpm -q "$pkg" >/dev/null 2>&1; then
				echo "未安装 $pkg，正在安装..."
				yum install -y "$pkg"
			else
				echo "$pkg 已安装。"
			fi
		done

		# 专门检查 lsb_release 命令
		if command -v lsb_release >/dev/null 2>&1; then
			echo "lsb_release 已安装。"
		else
			echo "lsb_release 未安装，尝试安装 redhat-lsb-core..."
			# 确保 epel-release 已安装（如果需要）
			if ! rpm -q epel-release >/dev/null 2>&1; then
				echo "安装 epel-release..."
				yum install -y epel-release
			fi
			# 再次尝试安装 redhat-lsb-core
			yum install -y redhat-lsb-core
			# 验证 lsb_release 是否安装成功
			if command -v lsb_release >/dev/null 2>&1; then
				echo "lsb_release 安装成功。"
			else
				echo "错误：无法安装 lsb_release，请检查 yum 存储库或包的可用性。"
			fi
		fi

	elif [[ "${OS_type}" == "Debian" ]]; then
		# 检查是否安装了 ca-certificates 包，如果未安装则安装
		if ! dpkg-query -W ca-certificates >/dev/null; then
			echo '正在安装 ca-certificates 包...'
			apt-get update || apt-get --allow-releaseinfo-change update && apt-get install ca-certificates -y
			update-ca-certificates
		fi
		echo 'CA证书检查OK'

		# 检查并安装 curl、wget 和 dmidecode 包
		for pkg in curl wget dmidecode; do
			if ! type $pkg >/dev/null 2>&1; then
				echo "未安装 $pkg，正在安装..."
				apt-get update || apt-get --allow-releaseinfo-change update && apt-get install $pkg -y
			else
				echo "$pkg 已安装。"
			fi
		done

		if [ -x "$(command -v lsb_release)" ]; then
			echo "lsb_release 已安装"
		else
			echo "lsb_release 未安装，现在开始安装..."
			apt-get install lsb-release -y
		fi

	else
		echo "不支持的操作系统发行版：${release}"
		exit 1
	fi
}

#检查Linux版本
check_version() {
	if [[ -s /etc/redhat-release ]]; then
		version=$(grep -oE "[0-9.]+" /etc/redhat-release | cut -d . -f 1)
	else
		version=$(grep -oE "[0-9.]+" /etc/issue | cut -d . -f 1)
	fi
	bit=$(uname -m)
	#check_github
}

#检查安装bbr的系统要求
check_sys_bbr() {
	check_version
	if [[ "${OS_type}" == "CentOS" ]]; then
		if [[ ${version} == "7" ]]; then
			installbbr
		else
			echo -e "${Error} BBR内核不支持当前系统 ${release} ${version} ${bit} !" && exit 1
		fi
	elif [[ "${OS_type}" == "Debian" ]]; then
		apt-get --fix-broken install -y && apt-get autoremove -y
		installbbr
	else
		echo -e "${Error} BBR内核不支持当前系统 ${release} ${version} ${bit} !" && exit 1
	fi
}

check_sys_bbrplus() {
	check_version
	if [[ "${OS_type}" == "CentOS" ]]; then
		if [[ ${version} == "7" ]]; then
			installbbrplus
		else
			echo -e "${Error} BBRplus内核不支持当前系统 ${release} ${version} ${bit} !" && exit 1
		fi
	elif [[ "${OS_type}" == "Debian" ]]; then
		apt-get --fix-broken install -y && apt-get autoremove -y
		installbbrplus
	else
		echo -e "${Error} BBRplus内核不支持当前系统 ${release} ${version} ${bit} !" && exit 1
	fi
}

check_sys_xanmod() {
	check_version
	if [[ "${OS_type}" == "CentOS" ]]; then
		if [[ ${version} == "7" || ${version} == "8" ]]; then
			installxanmod
		else
			echo -e "${Error} xanmod内核不支持当前系统 ${release} ${version} ${bit} !" && exit 1
		fi
	elif [[ "${OS_type}" == "Debian" ]]; then
		apt-get --fix-broken install -y && apt-get autoremove -y
		installxanmod
	else
		echo -e "${Error} xanmod内核不支持当前系统 ${release} ${version} ${bit} !" && exit 1
	fi
}

#检查保留的xanmod main内核并安装
cpu_has_all_flags() {
	local flags="$1"
	shift
	local flag=""
	for flag in "$@"; do
		[[ " ${flags} " == *" ${flag} "* ]] || return 1
	done
	return 0
}

get_xanmod_cpu_level_local() {
	local flags=""

	flags=$(awk -F: '/^flags[[:space:]]*:/ {print tolower($2); exit}' /proc/cpuinfo 2>/dev/null | xargs)
	if [[ -z "${flags}" ]]; then
		echo "1"
		return 0
	fi

	if cpu_has_all_flags "${flags}" ssse3 sse4_1 sse4_2 popcnt cx16 lahf_lm; then
		if cpu_has_all_flags "${flags}" avx avx2 bmi1 bmi2 f16c fma movbe xsave && [[ " ${flags} " == *" abm "* || " ${flags} " == *" lzcnt "* ]]; then
			if cpu_has_all_flags "${flags}" avx512f avx512bw avx512cd avx512dq avx512vl; then
				echo "4"
			else
				echo "3"
			fi
		else
			echo "2"
		fi
	else
		echo "1"
	fi
}

get_xanmod_keyring_file() {
	echo "${TCPX_XANMOD_KEYRING_FILE:-/etc/apt/keyrings/xanmod-archive-keyring.gpg}"
}

get_xanmod_repo_list_file() {
	echo "${TCPX_XANMOD_REPO_LIST_FILE:-/etc/apt/sources.list.d/xanmod-release.list}"
}

get_xanmod_repo_base() {
	echo "${TCPX_XANMOD_REPO_BASE:-http://deb.xanmod.org}"
}

get_xanmod_key_url() {
	echo "${TCPX_XANMOD_KEY_URL:-https://dl.xanmod.org/archive.key}"
}

get_xanmod_keyservers() {
	echo "${TCPX_XANMOD_KEYSERVERS:-hkps://keyserver.ubuntu.com hkp://keyserver.ubuntu.com:80}"
}

get_xanmod_repo_suite() {
	local suite="${TCPX_XANMOD_REPO_SUITE:-}"

	if [[ -n "${suite}" ]]; then
		echo "${suite}" | tr '[:upper:]' '[:lower:]'
		return 0
	fi

	if _exists lsb_release; then
		suite=$(lsb_release -sc 2>/dev/null | tr '[:upper:]' '[:lower:]')
	fi

	if [[ -z "${suite}" && -r /etc/os-release ]]; then
		suite=$(awk -F= '/^VERSION_CODENAME=/{gsub(/"/, "", $2); print tolower($2); exit} /^UBUNTU_CODENAME=/{gsub(/"/, "", $2); print tolower($2); exit}' /etc/os-release)
	fi

	echo "${suite}"
}

get_xanmod_fallback_suite() {
	echo "${TCPX_XANMOD_FALLBACK_SUITE:-releases}"
}

xanmod_suite_supported() {
	case "$1" in
	bookworm | trixie | forky | sid | noble | plucky | questing | resolute | faye | gigi | wilma | xia | zara | zena)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

get_xanmod_track() {
	local suite="$1"
	local cpu_level="$2"
	local track="${TCPX_XANMOD_TRACK:-auto}"

	track=$(echo "${track}" | tr '[:upper:]' '[:lower:]')
	if [[ -z "${track}" || "${track}" == "auto" ]]; then
		if [[ "${cpu_level}" == "1" || "${suite}" == "bookworm" || "${suite}" == "faye" ]]; then
			echo "lts"
		else
			echo "main"
		fi
		return 0
	fi

	case "${track}" in
	main | edge | lts | rt)
		echo "${track}"
		;;
	*)
		return 1
		;;
	esac
}

get_xanmod_cpu_level() {
	local tmp_script=""
	local level=""

	if [[ "${TCPX_XANMOD_FORCE_CPU_LEVEL:-}" =~ ^[1-4]$ ]]; then
		echo "${TCPX_XANMOD_FORCE_CPU_LEVEL}"
		return 0
	fi

	tmp_script="$(mktemp /tmp/check_x86-64_psabi.XXXXXX.sh)"
	if (_exists curl && curl -fsSL "https://dl.xanmod.org/check_x86-64_psabi.sh" -o "${tmp_script}") || (_exists wget && wget -qO "${tmp_script}" "https://dl.xanmod.org/check_x86-64_psabi.sh"); then
		chmod +x "${tmp_script}"
		level=$("${tmp_script}" 2>/dev/null | grep -oE 'v[1-4]' | tail -n1 | tr -d 'v')
	fi
	rm -f "${tmp_script}"

	if [[ "${level}" =~ ^[1-4]$ ]]; then
		echo "${level}"
		return 0
	fi

	echo -e "${Tip} 无法从 XanMod 站点获取 CPU 检测脚本，改用本地 CPU flags 判断档位。" >&2
	get_xanmod_cpu_level_local
}

install_xanmod_archive_keyring() {
	local keyring_file=""
	local key_url=""
	local keyservers=""
	local key_id="86F7D09EE734E623"
	local tmp_key_file=""
	local tmp_keyring=""
	local tmp_gnupg=""
	local method=""
	local keyserver=""

	keyring_file="$(get_xanmod_keyring_file)"
	key_url="$(get_xanmod_key_url)"
	keyservers="$(get_xanmod_keyservers)"
	mkdir -p "$(dirname "${keyring_file}")"

	tmp_key_file="$(mktemp /tmp/xanmod-archive-key.XXXXXX.asc)"
	tmp_keyring="$(mktemp /tmp/xanmod-archive-keyring.XXXXXX.gpg)"

	if (_exists curl && curl -fsSL "${key_url}" -o "${tmp_key_file}") || (_exists wget && wget -qO "${tmp_key_file}" "${key_url}"); then
		if [[ -s "${tmp_key_file}" ]] && gpg --batch --yes --dearmor -o "${tmp_keyring}" "${tmp_key_file}" >/dev/null 2>&1; then
			method="download"
		fi
	fi

	if [[ -z "${method}" ]]; then
		echo -e "${Tip} XanMod 公钥下载失败，改用 keyserver 导入公钥 ${key_id}。"
		tmp_gnupg="$(mktemp -d /tmp/xanmod-gnupg.XXXXXX)"
		chmod 700 "${tmp_gnupg}"
		for keyserver in ${keyservers}; do
			if GNUPGHOME="${tmp_gnupg}" gpg --batch --keyserver "${keyserver}" --recv-keys "${key_id}" >/dev/null 2>&1; then
				if GNUPGHOME="${tmp_gnupg}" gpg --batch --yes --output "${tmp_keyring}" --export "${key_id}" >/dev/null 2>&1 && [[ -s "${tmp_keyring}" ]]; then
					method="keyserver:${keyserver}"
					break
				fi
			fi
		done
	fi

	rm -f "${tmp_key_file}"
	if [[ -n "${tmp_gnupg}" ]]; then
		rm -rf "${tmp_gnupg}"
	fi

	if [[ -z "${method}" || ! -s "${tmp_keyring}" ]]; then
		rm -f "${tmp_keyring}"
		return 1
	fi

	install -m 644 "${tmp_keyring}" "${keyring_file}"
	rm -f "${tmp_keyring}"
	echo -e "${Info} XanMod 仓库公钥已通过 ${method} 方式安装。"
	return 0
}

get_xanmod_target_package() {
	local cpu_level="$1"
	local track="$2"

	case "${track}" in
	main)
		case "${cpu_level}" in
		4 | 3)
			echo "linux-xanmod-x64v3"
			;;
		2)
			echo "linux-xanmod-x64v2"
			;;
		*)
			return 1
			;;
		esac
		;;
	edge)
		case "${cpu_level}" in
		4 | 3)
			echo "linux-xanmod-edge-x64v3"
			;;
		2)
			echo "linux-xanmod-edge-x64v2"
			;;
		*)
			return 1
			;;
		esac
		;;
	rt)
		case "${cpu_level}" in
		4 | 3)
			echo "linux-xanmod-rt-x64v3"
			;;
		2)
			echo "linux-xanmod-rt-x64v2"
			;;
		*)
			return 1
			;;
		esac
		;;
	lts)
		case "${cpu_level}" in
		4 | 3)
			echo "linux-xanmod-lts-x64v3"
			;;
		2)
			echo "linux-xanmod-lts-x64v2"
			;;
		*)
			echo "linux-xanmod-lts-x64v1"
			;;
		esac
		;;
	*)
		return 1
		;;
	esac
}

get_xanmod_kernel_version_from_meta() {
	local meta_package="$1"
	local resolved=""

	resolved=$(apt-cache show "${meta_package}" 2>/dev/null | awk -F'[:, ]+' '/^Depends: / {for (i = 1; i <= NF; i++) if ($i ~ /^linux-image-/) {sub(/^linux-image-/, "", $i); print $i; exit}}')
	if [[ -z "${resolved}" ]]; then
		resolved=$(apt-cache depends "${meta_package}" 2>/dev/null | awk '/Depends: linux-image-/ {sub(/^.*Depends: linux-image-/, ""); gsub(/[[:space:]]+/, ""); print; exit}')
	fi
	echo "${resolved}"
}

check_sys_xanmod_main_kept() {
	check_version
	local cpu_level=""
	local xanmod_suite=""
	local xanmod_track=""
	local xanmod_package=""
	local xanmod_list=""
	local xanmod_keyring=""
	local xanmod_repo_base=""
	local xanmod_list_backup=""
	local xanmod_keyring_backup=""
	local backup_suffix=""
	local suite_overridden="0"
	local fallback_suite=""
	local auto_track="0"

	if [[ ${bit} != "x86_64" ]]; then
		echo -e "${Error} 不支持x86_64以外的系统 !" && exit 1
	fi

	xanmod_list="$(get_xanmod_repo_list_file)"
	xanmod_keyring="$(get_xanmod_keyring_file)"
	xanmod_repo_base="$(get_xanmod_repo_base)"
	[[ -n "${TCPX_XANMOD_REPO_SUITE:-}" ]] && suite_overridden="1"
	if [[ -z "${TCPX_XANMOD_TRACK:-}" || "$(echo "${TCPX_XANMOD_TRACK}" | tr '[:upper:]' '[:lower:]')" == "auto" ]]; then
		auto_track="1"
	fi

	cpu_level=$(get_xanmod_cpu_level)
	check_empty "$cpu_level"
	echo -e "CPU supports \033[32mv${cpu_level}\033[0m"

	if [[ "${OS_type}" == "Debian" ]]; then
		xanmod_suite=$(get_xanmod_repo_suite)
		check_empty "$xanmod_suite"
		if [[ "${suite_overridden}" == "0" ]] && ! xanmod_suite_supported "${xanmod_suite}"; then
			fallback_suite=$(get_xanmod_fallback_suite)
			if [[ -n "${fallback_suite}" ]]; then
				echo -e "${Tip} 当前发行版代号 ${xanmod_suite} 不在 XanMod 官方当前支持列表内，自动回退到 suite: ${fallback_suite}"
				xanmod_suite="${fallback_suite}"
				if [[ "${auto_track}" == "1" ]]; then
					xanmod_track="lts"
					echo -e "${Tip} 当前系统按旧发行版处理，自动切换为 XanMod LTS 分支。"
				fi
			else
				echo -e "${Error} 当前发行版代号 ${xanmod_suite} 不在 XanMod 官方当前支持列表内。"
				echo -e "${Tip} 若你有自建镜像或明确知道可用 suite，可通过环境变量 TCPX_XANMOD_REPO_SUITE 手动覆盖。"
				return 1
			fi
		fi
		if [[ -z "${xanmod_track}" ]]; then
			xanmod_track=$(get_xanmod_track "${xanmod_suite}" "${cpu_level}") || {
				echo -e "${Error} TCPX_XANMOD_TRACK 仅支持 auto/main/lts/edge/rt。"
				return 1
			}
		fi
		if [[ -z "${xanmod_track}" ]]; then
			echo -e "${Error} TCPX_XANMOD_TRACK 仅支持 auto/main/lts/edge/rt。"
			return 1
		fi
		xanmod_package=$(get_xanmod_target_package "${cpu_level}" "${xanmod_track}") || {
			echo -e "${Error} CPU x86-64-v${cpu_level} 不支持 XanMod ${xanmod_track} 分支，请改用 LTS 或提升 CPU 平台。"
			return 1
		}

		echo -e "${Info} XanMod suite: ${xanmod_suite}  track: ${xanmod_track}  package: ${xanmod_package}"
		backup_suffix=".$(date +%s)"
		if [[ -f "${xanmod_list}" ]]; then
			xanmod_list_backup="${xanmod_list}${backup_suffix}.bak"
			mv "${xanmod_list}" "${xanmod_list_backup}"
			echo -e "${Tip} 已临时禁用旧的 XanMod 源，避免 apt 被历史残留配置阻塞。"
		fi
		if [[ -f "${xanmod_keyring}" ]]; then
			xanmod_keyring_backup="${xanmod_keyring}${backup_suffix}.bak"
			cp -f "${xanmod_keyring}" "${xanmod_keyring_backup}"
		fi

		if ! (apt-get update || apt-get --allow-releaseinfo-change update); then
			if [[ -n "${xanmod_list_backup}" && -f "${xanmod_list_backup}" ]]; then
				mv "${xanmod_list_backup}" "${xanmod_list}"
			fi
			if [[ -n "${xanmod_keyring_backup}" && -f "${xanmod_keyring_backup}" ]]; then
				mv "${xanmod_keyring_backup}" "${xanmod_keyring}"
			fi
			echo -e "${Error} 初始化 APT 索引失败，请先检查系统源是否正常。"
			return 1
		fi

		if ! apt-get install gnupg ca-certificates wget curl -y; then
			if [[ -n "${xanmod_list_backup}" && -f "${xanmod_list_backup}" ]]; then
				mv "${xanmod_list_backup}" "${xanmod_list}"
			fi
			if [[ -n "${xanmod_keyring_backup}" && -f "${xanmod_keyring_backup}" ]]; then
				mv "${xanmod_keyring_backup}" "${xanmod_keyring}"
			fi
			echo -e "${Error} 安装 XanMod 所需依赖失败。"
			return 1
		fi

		if ! install_xanmod_archive_keyring; then
			if [[ -n "${xanmod_list_backup}" && -f "${xanmod_list_backup}" ]]; then
				mv "${xanmod_list_backup}" "${xanmod_list}"
			fi
			if [[ -n "${xanmod_keyring_backup}" && -f "${xanmod_keyring_backup}" ]]; then
				mv "${xanmod_keyring_backup}" "${xanmod_keyring}"
			else
				rm -f "${xanmod_keyring}"
			fi
			echo -e "${Error} XanMod 仓库公钥安装失败，请检查目标机到 dl.xanmod.org / keyserver 的连通性。"
			return 1
		fi

		echo "deb [signed-by=${xanmod_keyring}] ${xanmod_repo_base} ${xanmod_suite} main" >"${xanmod_list}"
		if ! (apt-get update || apt-get --allow-releaseinfo-change update); then
			rm -f "${xanmod_list}"
			if [[ -n "${xanmod_list_backup}" && -f "${xanmod_list_backup}" ]]; then
				mv "${xanmod_list_backup}" "${xanmod_list}"
			fi
			if [[ -n "${xanmod_keyring_backup}" && -f "${xanmod_keyring_backup}" ]]; then
				mv "${xanmod_keyring_backup}" "${xanmod_keyring}"
			else
				rm -f "${xanmod_keyring}"
			fi
			echo -e "${Error} XanMod 仓库索引刷新失败，已回滚 APT 源配置。"
			return 1
		fi

		rm -f "${xanmod_list_backup}" "${xanmod_keyring_backup}"

		if ! apt-get install "${xanmod_package}" -y; then
			echo -e "${Error} XanMod 内核包安装失败。"
			return 1
		fi
		kernel_version=$(get_xanmod_kernel_version_from_meta "${xanmod_package}")
		check_empty "$kernel_version"
	else
		echo -e "${Error} 不支持当前系统 ${release} ${version} ${bit} !" && exit 1
	fi

	BBR_grub
	show_kernel_install_finish_notice
}

#检查系统当前状态
check_status() {
	# 初始化变量，避免重复读取文件
	kernel_version=$(uname -r | awk -F "-" '{print $1}')
	kernel_version_full=$(uname -r)
	net_congestion_control=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo "unknown")
	net_qdisc=$(cat /proc/sys/net/core/default_qdisc 2>/dev/null || echo "unknown")
	bbr_version=$(tr '\0' '\n' </lib/modules/"${kernel_version_full}"/modules.builtin.modinfo 2>/dev/null | awk -F= '/^tcp_bbr.version=/{print $2; exit}')
	if [[ -z "$bbr_version" ]]; then
		bbr_version=$(modinfo tcp_bbr 2>/dev/null | awk '/^version:/{print $2; exit}')
	fi

	# 检测操作系统类型
	if [ -f /etc/redhat-release ]; then
		os_type="centos"
	elif [ -f /etc/debian_version ]; then
		os_type="debian"
	else
		os_type="unknown"
	fi

	# 检测内核类型
	if [[ "$kernel_version_full" == *bbrplus* ]]; then
		kernel_status="BBRplus"
	elif [[ "$kernel_version_full" =~ (4\.9\.0-4|4\.15\.0-30|4\.8\.0-36|3\.16\.0-77|3\.16\.0-4|3\.2\.0-4|4\.11\.2-1|2\.6\.32-504|4\.4\.0-47|3\.13\.0-29) ]]; then
		kernel_status="Lotserver"
	elif read major minor <<<$(echo "$kernel_version" | awk -F'.' '{print $1, $2}') &&
		{ [[ "$major" == "4" && "$minor" -ge 9 ]] || [[ "$major" == "5" ]] || [[ "$major" == "6" ]] || [[ "$major" == "7" ]]; }; then
		kernel_status="BBR"
	else
		kernel_status="noinstall"
	fi

	# 运行状态检测
	if [[ "$kernel_status" == "BBR" ]]; then
		case "$net_congestion_control" in
		"bbr")
			[[ "$bbr_version" == "3" ]] && run_status="BBR3启动成功" || run_status="BBR启动成功"
			;;
		"bbr2")
			run_status="BBR2启动成功"
			;;
		"tsunami")
			if lsmod | grep -q "^tcp_tsunami"; then
				run_status="BBR魔改版启动成功"
			else
				run_status="BBR魔改版启动失败"
			fi
			;;
		"nanqinlang")
			if lsmod | grep -q "^tcp_nanqinlang"; then
				run_status="暴力BBR魔改版启动成功"
			else
				run_status="暴力BBR魔改版启动失败"
			fi
			;;
		*)
			run_status="未安装加速模块"
			;;
		esac
	elif [[ "$kernel_status" == "Lotserver" ]]; then
		if [[ -e /appex/bin/lotServer.sh ]]; then
			run_status=$(bash /appex/bin/lotServer.sh status | grep "LotServer" | awk '{print $3}')
			[[ "$run_status" == "running!" ]] && run_status="启动成功" || run_status="启动失败"
		else
			run_status="未安装加速模块"
		fi
	elif [[ "$kernel_status" == "BBRplus" ]]; then
		case "$net_congestion_control" in
		"bbrplus")
			run_status="BBRplus启动成功"
			;;
		"bbr")
			[[ "$bbr_version" == "3" ]] && run_status="BBR3启动成功" || run_status="BBR启动成功"
			;;
		*)
			run_status="未安装加速模块"
			;;
		esac
	else
		run_status="未安装加速模块"
	fi

	# 检查 kernel-headers 或 kernel-devel（CentOS）/linux-headers（Debian/Ubuntu）状态
	if [[ "$os_type" == "centos" ]]; then
		installed_headers=$(rpm -qa | grep -E "kernel-devel|kernel-headers" | grep -v '^$' || echo "")
		if [[ -z "$installed_headers" ]]; then
			headers_status="未安装"
		else
			if echo "$installed_headers" | grep -q "kernel-devel-${kernel_version_full}\|kernel-headers-${kernel_version_full}"; then
				headers_status="已匹配"
			else
				headers_status="未匹配"
			fi
		fi
	elif [[ "$os_type" == "debian" ]]; then
		installed_headers=$(dpkg -l | grep -E "linux-headers|linux-image" | awk '{print $2}' | grep -v '^$' || echo "")
		if [[ -z "$installed_headers" ]]; then
			headers_status="未安装"
		else
			if echo "$installed_headers" | grep -q "linux-headers-${kernel_version_full}"; then
				headers_status="已匹配"
			else
				headers_status="未匹配"
			fi
		fi
	else
		headers_status="不支持的操作系统"
	fi

	# Brutal 状态检测
	brutal=""
	if lsmod | grep -q "brutal"; then
		brutal="brutal已加载"
	fi
}

#############系统检测组件#############
check_sys
check_version
[[ "${OS_type}" != "Debian" && "${OS_type}" != "CentOS" ]] && echo -e "${Error} 本脚本不支持当前系统 ${release} !" && exit 1
#check_github
start_menu
