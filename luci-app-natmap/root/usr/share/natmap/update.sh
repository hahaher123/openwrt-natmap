#!/bin/sh

. /usr/share/libubox/jshn.sh

# 并发锁：natmap 通过 fork 异步执行本脚本且不等待返回，
# 多实例或映射连续变化时可能并发触发，这里串行化避免并发写 uci/防火墙。
# 加超时保护：若上一个实例异常卡住，等待 30 秒后跳过本次更新，
# 避免整条链路(状态JSON/转发/通知)被永久阻塞
exec 9>/tmp/.natmap.lock
flock -w 30 9 || {
	echo "$(date +'%Y-%m-%d %H:%M:%S') : ${GENERAL_NAT_NAME:-natmap} - 上一次更新未结束(锁等待超时), 跳过本次" >>/var/log/natmap/natmap.log
	exit 1
}

(
	json_init
	json_add_string ip "$1"
	json_add_int port "$2"
	json_add_string ip4p "$3"
	json_add_int inner_port "$4"
	json_add_string protocol "$5"
	json_add_string name "$GENERAL_NAT_NAME"
	json_dump >/var/run/natmap/$PPID.json
)

# 设置日志参数
log_size_limit=1024000
log_file="/var/log/natmap/natmap.log"

# natmap logs setting
# 日志大小限制超过1M则删除最早的日志，若日志不存在则创建日志文件
if [ -f "/var/log/natmap/natmap.log" ]; then
	[ "$(wc -c /var/log/natmap/natmap.log | awk '{print $1}')" -gt "${log_size_limit}" ] && {
		[ -f "/var/log/natmap/natmap.log.1" ] && {
			rm -f /var/log/natmap/natmap.log.1
		}
		mv /var/log/natmap/natmap.log /var/log/natmap/natmap.log.1
	}
else
	[ ! -d "/var/log/natmap" ] && {
		mkdir -p /var/log/natmap
	}
	touch /var/log/natmap/natmap.log
fi

echo "$(date +'%Y-%m-%d %H:%M:%S') : $GENERAL_NAT_NAME - 开始更新" >>/var/log/natmap/natmap.log
echo "$(date +'%Y-%m-%d %H:%M:%S') : $GENERAL_NAT_NAME - 开始更新"
echo "$(date +'%Y-%m-%d %H:%M:%S') : natmap update json: $(cat /var/run/natmap/$PPID.json)" >>/var/log/natmap/natmap.log
echo "$(date +'%Y-%m-%d %H:%M:%S') : natmap update json: $(cat /var/run/natmap/$PPID.json)"

# forward setting
[ "${FORWARD_ENABLE}" == 1 ] && source /usr/share/natmap/forward.sh "$@"

# link setting
[ "${LINK_ENABLE}" == 1 ] && source /usr/share/natmap/link.sh "$@"

# custom setting
[ "${CUSTOM_SCRIPT_ENABLE}" == 1 ] && [ -n "${CUSTOM_SCRIPT_PATH}" ] && {
	export -n CUSTOM_SCRIPT_PATH
	source "${CUSTOM_SCRIPT_PATH}" "$@"
}

# notify setting
[ "${NOTIFY_ENABLE}" == 1 ] && source /usr/share/natmap/notify.sh "$@"
