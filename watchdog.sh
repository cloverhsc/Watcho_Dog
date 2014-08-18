#!/bin/bash
#######################################################################################
#boot
#if [ -f /DOM/.nasboot ] | [ -f /DOM/.fsrepair ];then

#       echo "do FS repair and show on LCD! "
#       echo "Write to log /DOM/.wdog.log"
#fi

#touch /DOM/.nasboot
#echo "hwdog init"
#echo "hwdog start monitor !"

#if [ -f /nas/tmp/psx.result ];then
#       while read line
#       do
#               echo $line

#       done< /nas/tmp/psx.result

#fi
########################################################################################

#function find_broken_process()  need 1 parameter for check process state . if "D" => dead process , "Z"=> zombie process
function find_broken_process()
{

#record process state in now
if [ -f /tmp/proc_record$1.txt ];then
        rm /tmp/proc_record$1.txt 2>/dev/null
fi
touch /tmp/proc_record$1.txt

test ! -f /tmp/proc_ref$1.txt && touch /tmp/proc_ref$1.txt		# record state at last time

declare -i count=0         #count process.
#process state on Zombie or Dead
psx_state=$1
while read line
do
	# get state in "Z" or "D" process's PID,name,state
	pid=`echo $line|awk -v st=$psx_state '{if($3==st) printf "%s",$1}'`
	proc_name=`echo $line|awk -v st=$psx_state '{if($3==st) printf "%s",$6}'`
	
	if [ "$pid" != "" ];then
	
		count=`cat /tmp/proc_ref$1.txt | awk -v pd=$pid '{if($1==pd && $2==st) printf "%s",$4}' st=$psx_state`		#search last time state in proc_ref$1.txt
		count=${count:-0}											
		count=`expr $count+1`
		echo $pid $psx_state $proc_name $count >> /tmp/proc_record$1.txt												#save now state
						
	fi

done< /nas/tmp/psx.1
	#save zombie or Dead process log to /DOM/.wdog.log
	`cat /tmp/proc_record$1.txt > /tmp/proc_ref$1.txt`
	if [ "$str" != "" ];then
        echo `date` >> /DOM/.wdog.log
        `cat /tmp/proc_ref$1.txt >> /DOM/.wdog.log`
        echo "" >>/DOM/.wdog.log
    fi
	
	#check if need reboot.
	while read line
	do
		count=`echo $line|awk '{print $4}'`
		if [ $count -gt 10 ];then
			rm /DOM/.nasboot 2>/dev/null
			rm /DOM/.fsrepair 2>/dev/null
			echo "Find Zombie process $line ! Reboot now! >> /DOM/.wdog.log"
			echo "Reboot now cmd"
		fi
	done < /tmp/proc_ref$1.txt

}

function find_filesystem_error()
{
	if str=`grep "XFS internal error" /nas/tmp/dmesg.result`;then
		`echo >>/DOM/.wdog.log`
		echo -e`date`"\n" Detect XFS ERROR : $str >> /DOM/.wdog.log
		touch /DOM/.fsrepair
	fi
	
	if str=`grep "EXT3-fs error" /nas/tmp/dmesg.result`;then
		`echo >>/DOM/.wdog.log`
		echo -e`date`"\n" Detect EXT3-fs ERROR : $str >> /DOM/.wdog.log
		touch /DOM/.fsrepair
	fi
	
	if str=`grep "EXT4-fs error" /nas/tmp/dmesg.result`;then
		`echo >>/DOM/.wdog.log`
		echo -e`date`"\n" Detect EXT4 ERROR : $str >> /DOM/.wdog.log
		touch /DOM/.fsrepair
	fi
	
	if str=`grep "Kernel panic" /nas/tmp/dmesg.result`;then
		`echo >>/DOM/.wdog.log`
		echo -e`date`"\n" Detect KERNEL PANIC ERROR : $str >> /DOM/.wdog.log
		touch /DOM/.fsrepair
	fi
	
	if str=`grep "Call Trace" /nas/tmp/dmesg.result`;then
		`echo >>/DOM/.wdog.log`
		echo -e`date`"\n" Detect KERNEL CALL TRACE ERROR : $str >> /DOM/.wdog.log
		touch /DOM/.fsrepair
	fi
	
}

function do_reboot()
{
	`sync &`
	cd /root
	for SVC in cron afp smbd rsync nfs-kernel-server ddclient
	do
		/etc/init.d/${SVC} stop
	done

	ruby /usr/ruby/runMonitor.rb stop
	killall ruby
	killall profamd
	killall lcd2usb
	killall udevd
	killall irqbalance
	killall MCS
	killall remoteCommSvr
	killall ipwatchd
	killall mysqld

	`sleep 10`
	`forcereboot`
}

