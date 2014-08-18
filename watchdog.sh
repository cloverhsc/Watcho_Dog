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
if [ -f /nas/tmp/proc_record$1.txt ];then
    rm /nas/tmp/proc_record$1.txt 2>/dev/null
fi
touch /nas/tmp/proc_record$1.txt

test ! -f /nas/tmp/proc_ref$1.txt && touch /nas/tmp/proc_ref$1.txt		# record state at last time

declare -i count=0         #count process.
need_reboot="false"
#process state on Zombie or Dead
psx_state=$1
while read line
do
	# get state in "Z" or "D" process's PID,name,state
	pid=`echo $line|awk -v st=$psx_state '{if($3==st) printf "%s",$1}'`
	proc_name=`echo $line|awk -v st=$psx_state '{if($3==st) printf "%s",$6}'`
	
	if [ "$pid" != "" ];then
	
		count=`cat /nas/tmp/proc_ref$1.txt | awk -v pd=$pid '{if($1==pd && $2==st) printf "%s",$4}' st=$psx_state`		#search last time state in proc_ref$1.txt
		count=${count:-0}											
		count=`expr $count+1`
		echo $pid $psx_state $proc_name $count >> /nas/tmp/proc_record$1.txt												#save now state
						
	fi

done< /nas/tmp/psx.result

	#save zombie or Dead process log to /DOM/.wdog.log
	`cat /nas/tmp/proc_record$1.txt > /nas/tmp/proc_ref$1.txt`
	#check if need reboot.
	while read line
	do
		count=`echo $line|awk '{print $4}'`
		if [ $count -gt 10 ];then
			echo `date "+%Y %m %d %H:%M:%S"` >> /DOM/.wdog.log
			echo "Find Zombie process $line !" >> /DOM/.wdog.log
			echo "" >>/DOM/.wdog.log
			need_reboot="true"
		fi
	done < /nas/tmp/proc_ref$1.txt
	
	if [ "$need_reboot" == "true" ]&&[ $1 == "Z" ];then
		echo "Find Zombie process ! Please check /DOM/.wdog.log log"
		echo "Reboot by Watch dog..." >>/DOM/.wdog.log
		echo "Reboot by Watch dog..."
		sleep 5
		do_reboot
	elif [ "$need_reboot" == "true" ]&&[ $1 == "D" ];then
		echo "Find Dead process ! Please check /DOM/.wdog.log log"
		echo "Reboot by Watch dog..." >>/DOM/.wdog.log
		echo "Reboot by Watch dog..."
		sleep 5
		do_reboot
	fi

}

function find_filesystem_error()
{
	if str=`grep "XFS internal error" /nas/tmp/dmesg.result`;then
		`echo >>/DOM/.wdog.log`
		echo -e`date`"\n" Detect XFS ERROR : $str >> /DOM/.wdog.log
		touch /DOM/.fsrepair
		echo "Detect XFS error! Reboot for file system check !"
		do_reboot
	fi
	
	if str=`grep "EXT3-fs error" /nas/tmp/dmesg.result`;then
		`echo >>/DOM/.wdog.log`
		echo -e`date`"\n" Detect EXT3-fs ERROR : $str >> /DOM/.wdog.log
		touch /DOM/.fsrepair
		echo "Detect EXT3-fs error ! Reboot for file system check!"
		do_reboot
	fi
	
	if str=`grep "EXT4-fs error" /nas/tmp/dmesg.result`;then
		`echo >>/DOM/.wdog.log`
		echo -e`date`"\n" Detect EXT4 ERROR : $str >> /DOM/.wdog.log
		touch /DOM/.fsrepair
		echo "Detect EXT4 error! Reboot for file system check!"
		do_reboot
	fi
	
	if str=`grep "Kernel panic" /nas/tmp/dmesg.result`;then
		`echo >>/DOM/.wdog.log`
		echo -e`date`"\n" Detect KERNEL PANIC ERROR : $str >> /DOM/.wdog.log
		touch /DOM/.fsrepair
		echo "Detect Kernel panic ! Reboot !"
		do_reboot
	fi
	
	if str=`grep "Call Trace" /nas/tmp/dmesg.result`;then
		`echo >>/DOM/.wdog.log`
		echo -e`date`"\n" Detect KERNEL CALL TRACE ERROR : $str >> /DOM/.wdog.log
		touch /DOM/.fsrepair
		echo "Detect kernel call trace error! Reboot"
		do_reboot
	fi
	
}

function do_reboot()
{
	touch /nas/tmp/hwdogfreboot     # stopAllSvc will not stop bash
	`sync &`
	`stopAllSvc`
	`sleep 10`
	`forcereboot`
}

