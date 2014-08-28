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

#record process state now
if [ -f /nas/tmp/proc_record$1.txt ];then
    rm /nas/tmp/proc_record$1.txt 2>/dev/null
fi
touch /nas/tmp/proc_record$1.txt

test ! -f /nas/tmp/proc_ref$1.txt && touch /nas/tmp/proc_ref$1.txt		# record state at last time

declare -i count=0         #count every processes Dead or Zombie times.
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
			if [ "$1" == "Z" ];then
				echo "Find Zombie process $line !" >> /DOM/.wdog.log
			elif [ "$1" == "D" ];then
				echo "Find Dead process $line !" >> /DOM/.wdog.log
			fi
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
		echo -e`date "+%Y %m %d %H:%M:%S"`"\n" Detect XFS ERROR : $str >> /DOM/.wdog.log
		touch /DOM/.fsrepair
		echo "Detect XFS error! Reboot for file system check !"
		do_reboot
	fi
	
	if str=`grep "EXT3-fs error" /nas/tmp/dmesg.result`;then
		`echo >>/DOM/.wdog.log`
		echo -e`date "+%Y %m %d %H:%M:%S"`"\n" Detect EXT3-fs ERROR : $str >> /DOM/.wdog.log
		touch /DOM/.fsrepair
		echo "Detect EXT3-fs error ! Reboot for file system check!"
		do_reboot
	fi
	
	if str=`grep "EXT4-fs error" /nas/tmp/dmesg.result`;then
		`echo >>/DOM/.wdog.log`
		echo -e`date "+%Y %m %d %H:%M:%S"`"\n" Detect EXT4 ERROR : $str >> /DOM/.wdog.log
		touch /DOM/.fsrepair
		echo "Detect EXT4 error! Reboot for file system check!"
		do_reboot
	fi
	
	if str=`grep "Kernel panic" /nas/tmp/dmesg.result`;then
		`echo >>/DOM/.wdog.log`
		echo -e`date "+%Y %m %d %H:%M:%S"`"\n" Detect KERNEL PANIC ERROR : $str >> /DOM/.wdog.log
		touch /DOM/.fsrepair
		echo "Detect Kernel panic ! Reboot !"
		do_reboot
	fi
	
	if str=`grep "Call Trace" /nas/tmp/dmesg.result`;then
		`echo >>/DOM/.wdog.log`
		echo -e`date "+%Y %m %d %H:%M:%S"`"\n" Detect KERNEL CALL TRACE ERROR : $str >> /DOM/.wdog.log
		touch /DOM/.fsrepair
		echo "Detect kernel call trace error! Reboot"
		do_reboot
	fi
	
}

function do_reboot()
{
	test ! -f /DOM/.wdogrbt.log && echo "WatchDog reboot count:0" > /DOM/.wdogrbt.log
	touch /nas/tmp/hwfreboot     # stopAllSvc will not stop bash
	declare -i count=`cat /DOM/.wdogrbt.log |awk -F ":" '{print $2}'`
	count=$(( $count + 1 ))
	echo "WatchDog reboot count:$count" > /vol/test/count
	`sync &`
	`stopAllSvc`
	`sleep 10`
	`forcereboot`
}

# ------------------Start here--------------------------
test ! -f /DOM/.wdogrbt.log && echo "WatchDog reboot count:0" > /DOM/.wdogrbt.log
test ! -f /DOM/.nasboot && touch /DOM/.nasboot
test -f /DOM/.fsrepair && rm /DOM/.fsrepair 2>/dev/null
declare -i count=`cat /vol/test/count |awk -F ":" '{print $2}'`

#every 2 mins clear watch dog. So every 10 clear times => pass by 20 mins
declare -i is20mins=0;				

for ((;;))
do
		#first check reboot times by watch dog
		if [ "$count" -gt "3" ];then
			echo `date "+%Y %m %d %H:%M:%S"` >> /DOM/.wdog.log
			echo "reboot over 3 times. Stop watch dog !" >> /DOM/.wdog.log
			`hwdog off`
			break
		fi
		
		#if system run over 20 mins. Clean /DOM/.wdogrbt.log count=0 
		if [ "$is20mins" -gt "9" ];then
			is20mins=0
			echo "WatchDog reboot count:0" > /DOM/.wdogrbt.log
		fi
		
        `ps -o pid,tty,stat,user,time,args > /nas/tmp/psx.result`   # equal to psx > /nas/tmp/psx.result
        find_broken_process Z
        find_broken_process D
        cc=`expr $cc + 1 `
        echo $cc
        sleep 120
		is20mins=$(( $is20mins + 1 ))
done


