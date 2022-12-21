#! /bin/bash

### Add connexion type field to csv (virtual / physical)

___variables_declaration(){

	### Variables to fill out the CSV file
	declare interface_Name interface_IP interface_State interface_Access_Vlan interface_Mode_Trunk interface_Trunk_Allowed_Vlan 
	declare interface_Mode_Etherchannel interface_Etherchannel_Protocol interface_Etherchannel_Members
	declare vlan_Id vlan_Name vlan_State

	### Files & Directories
	dir_global="/mnt/partition2/home/greg/Documents/_client-stluc/_infra/_switches/_export_data"
	dir_switch="$dir_global/$hostname"
	file_sw_interfaces="$dir_switch/sw-infos-int"
	file_sw_config="$dir_switch/$hostname-confg"
	file_interfaces_output="$dir_switch/$hostname.csv"
	file_vlans_output="$dir_switch/$hostname-vlans.csv"

	### Temp files
	tmp_file_interfaces_output="$dir_switch/$hostname.tmp"
	tmp_file_vlans_output="$dir_switch/$hostname-vlans.tmp"
	tmp_file_to_write=""

	### Events variables
	cursor="Start"
	toSave=0
	type_of_data=""

}

___check_if_files_and_directories_exist(){

	[[ ! -e "$file_sw_config" ]] && echo "$file_sw_config doesn't exists!" && exit
	[[ ! -e "$file_sw_interfaces" ]] && echo "$file_sw_interfaces doesn't exists!" && exit
	[[ ! -d "$dir_switch" ]] && mkdir "$dir_switch" 

}

___interfaces_init(){

	interface_Name=""
	interface_Description=""
	interface_IP="unassigned"
	interface_State="down"
	interface_Access_Vlan="1"
	interface_Mode_Trunk="NON"
	interface_Trunk_Allowed_Vlan="-"
	interface_Mode_Etherchannel="NON"
	interface_Etherchannel_Protocol="-"
	interface_Etherchannel_Group="-"

}

___vlans_init(){

	vlan_Id=""
	vlan_Name=""
	vlan_State=""

}

___save_line(){

	[[ $type_of_data == "interface" ]] && line="$interface_Name;$interface_Description;$interface_IP;$interface_State;$interface_Access_Vlan;$interface_Mode_Trunk;$interface_Trunk_Allowed_Vlan;$interface_Mode_Etherchannel;$interface_Etherchannel_Protocol;$interface_Etherchannel_Group" && tmp_file_to_write=$tmp_file_interfaces_output
	[[ $type_of_data == "vlan" ]] && line="$vlan_Id;$vlan_Name;$vlan_State" && tmp_file_to_write=$tmp_file_vlans_output

	[[ -n $line ]] && echo $line >> $tmp_file_to_write

}

___write_output(){

	local sep

	### Insert columns headers
	[[ "$action_get_interfaces" == 1 ]] && sed -i '1 i\Interface;Description;IP;State;Vlans;Trunk;Vlans Allowed;Etherchannel;Etherchannel Protocol;Etherchannel Group' "$tmp_file_interfaces_output"
	[[ "$action_get_vlans" == 1 ]] && sed -i '1 i\Id;Name;State' "$tmp_file_vlans_output"

	### Remove white lines
	[[ "$action_get_interfaces" == 1 ]] && sed -i '/^$/d' "$tmp_file_interfaces_output"
	[[ "$action_get_vlans" == 1 ]] && sed -i '/^$/d' "$tmp_file_vlans_output"

	### Fill out the final output
	[[ "$action_get_interfaces" == 1 ]] && cat "$tmp_file_interfaces_output" > "$file_interfaces_output"
	[[ "$action_get_vlans" == 1 ]] && cat "$tmp_file_vlans_output" > "$file_vlans_output"

	### Clean up temp files
	[[ "$action_get_interfaces" == 1 ]] && rm "$tmp_file_interfaces_output"
	[[ "$action_get_vlans" == 1 ]] && rm "$tmp_file_vlans_output"

	### Say goodbye
	sep="****************************************************************"
	printf "\n\n%s\n\n%s%s\n\n\n" "$sep" "$hostname" " -> Done"

}

___interfaces_state(){

	local interface_name="$interface_Name\b"
	local interface_name_adapted_to_sw_interface_file=`echo $interface_name | sed 's|TenGigabitEthernet|Te|'`

	state=`cat "$file_sw_interfaces" | grep -i "$interface_name_adapted_to_sw_interface_file" | awk '{print $NF}'`
	interface_State=$state

}

___interfaces_switchport(){

	local data_value

	data_value="$1"

	interface_mode=`echo $data_value | awk '{print $1}'`
	last_value=`echo $data_value | awk '{print $NF}'`

	case $interface_mode in

		access)
			interface_Access_Vlan=$last_value
		;;
		trunk)
			isAboutAllowedVlan=`echo "$data_value" | grep -i allowed`
			[[ -n $isAboutAllowedVlan ]] && interface_Trunk_Allowed_Vlan=$last_value
		;;
		mode)
			which_mode=$last_value
			[[ "$which_mode" == "trunk" ]] && interface_Mode_Trunk="OUI" && interface_Access_Vlan="1"
			[[ "$which_mode" == "access" ]] && interface_Mode_Trunk="NON" && interface_Trunk_Allowed_Vlan="-"
		;;

	esac

}

### Set global variables for "standards" interfaces, Gi, Fa etc
___interfaces_channel(){

	local data_value

	data_value="$1"

	interface_Etherchannel_Group=`echo $data_value | awk '{print $1}'`
	interface_etherchannel_mode=`echo $data_value | awk '{print $3}'`
	interface_etherchannel_PoName=`echo "Port-Channel$interface_Etherchannel_Group"`

	[[ $interface_etherchannel_mode == "active" ]] && interface_Etherchannel_Protocol="LACP"
	[[ $interface_etherchannel_mode == "passive" ]] && interface_Etherchannel_Protocol="LACP"
	[[ $interface_etherchannel_mode == "on" ]] && interface_Etherchannel_Protocol="Static"

	local grep_pattern="$interface_etherchannel_PoName\b"
	local line_to_replace=`cat "$tmp_file_interfaces_output" | grep -i $grep_pattern`

	# new_line=`echo "$line_to_replace" | awk -v proto=$interface_Etherchannel_Protocol -v group=$interface_Etherchannel_Group '{print $7=$8=$9=""; print $0"OUI;"proto";"group}'`
	# echo $new_line
	# d=$'\03'
	# interface_etherchannel_PoName_002=`echo "Port\-Channel$interface_Etherchannel_Group"`
	# sed -i "s${d}$interface_etherchannel_PoName_002;.*${d}test${d}g" $tmp_file_interfaces_output

}

### Check if actual is a port channel or not. If yes, it fills out the global variables.
___interfaces_check_if_portchannel(){

	local check

	check=`echo "$interface_Name" | grep -i "port-channel"`

	if [ -n "$check" ]
	then

		interface_Mode_Etherchannel="OUI"
		interface_Etherchannel_Group=`echo $interface_Name | grep -o "[0-9]*\b"`

	fi

}

___interfaces_check_if_vlan_interface(){

	local check

	check=`echo "$interface_Name" | grep -i "vlan"`

	if [ -n "$check" ]
	then

		interface_Access_Vlan=`echo "$interface_Name" | grep -o "[0-9]*$"`

	fi

}

___interfaces(){

	local interface_data
	local data_type

	interface_data="$1"
	data_type=`echo $interface_data | awk '{print $1}'`
	data_value=`echo $interface_data | awk '{$1=""; print $0}' | sed 's|^ ||'`

	case $data_type in

		interface)
			interface_Name=$data_value

			printf "%s\n" "Collecting infos from switch: $hostname -> $interface_Name"

			### ___interfaces_state
			___interfaces_check_if_portchannel
			___interfaces_check_if_vlan_interface
		;;
		description)
			interface_Description=$data_value
		;;
		ip)
			interface_IP=`echo $data_value | awk '{print $2}'`	
		;;
		switchport)
			___interfaces_switchport "$data_value"
		;;
		channel-group)
			interface_Mode_Etherchannel="OUI"
			___interfaces_channel "$data_value"
		;;

	esac

}

___vlans(){

	local vlan_data 
	local data_type

	vlan_data="$1"
	data_type=`echo $vlan_data | awk '{print $1}'`
	data_value=`echo $vlan_data | awk '{print $2}'`

	case $data_type in

		vlan)
			vlan_Id=$data_value
			printf "%s\n" "Collecting infos from switch: $hostname ->  Vlan $vlan_Id"
		;;	
		name)
			vlan_Name=$data_value
		;;

	esac

}

___vlans_merge(){

	echo "into vlan merge"

}

___help(){

	sep="--------------------------------------------------------------"
	printf "\n\n%s\n%s\n" "This script collects data from the switch configuration files." "$sep"
	printf "\n%s\n" "Usage: ./script_export_interfaces_data_V002.sh -s <hostname>"
	printf "\n\t%s\n\n" "Available options are:"
	printf "\t\t%s %s\t%s\n" "-i" "->" "Check Interfaces"	
	printf "\t\t%s %s\t%s\n" "-v" "->" "Check Vlans for the switch"	
	printf "\t\t%s %s\t%s\n\n\n" "-m" "->" "Merge all vlans data collected from all the switches"	
	exit

}

___loop_through_files(){

	### Reading files line by line
	while read data
	do 
		### Setting up the cursor ###
		### Check we are reading an empty line
		isEmpty=`echo "$data" | grep "^!"`
		[[ -n "$isEmpty" ]] && cursor=""

		### Setting up the cursor ###
		### Check if we are reading interfaces's sections
		isInterface=`echo "$data" | grep "^interface"`
		[[ -n "$isInterface" ]] && cursor="interface"

		### Setting up the cursor ###
		### Check if we are reading vlans's sections
		isVlan=`echo "$data" | grep "^vlan\b\s[0-9]*$"`
		[[ -n "$isVlan" ]] && cursor="vlan"

		### Start functions depending on the cursor
		[[ "$cursor" == "interface" ]] && [[ "$action_get_interfaces" == 1 ]] && ___interfaces "$data" && type_of_data=$cursor && toSave=1 && continue
		[[ "$cursor" == "vlan" ]] && [[ "$action_get_vlans" == 1 ]] && ___vlans "$data" && type_of_data=$cursor && toSave=1 && continue

		### Exit save line and re-init variables if necessary
		if [ -z "$cursor" ]
		then
			[[ $toSave == 1 ]] && ___save_line && ___vlans_init && ___interfaces_init && toSave=0 && continue
		fi
	done < "$file_sw_config"

}

___init(){

	### Check if arguments exist
	[[ -z "$@" ]] && echo "Please provide at least one argument." && exit

	### Actions variables
	declare action_get_interfaces action_get_vlans action_merge_vlans

	action_get_vlans=0
	action_get_interfaces=0
	action_merge_vlans=0

	### Get command arguments
	while getopts "ivmhs:" flag
	do
		case "${flag}" in 

			i) action_get_interfaces=1;;
			v) action_get_vlans=1;;
			m) action_merge_vlans=1;;
			s) hostname=${OPTARG};;
			h) ___help;;

		esac
	done

	### Check if hostname argument exists
	[[ -z "$hostname" ]] && echo "Please provide the switch hostanme using the option \"-s\"" && exit

	### Declaring variables
	___variables_declaration

	### Check if files and directories exists on the disk
	___check_if_files_and_directories_exist
	
	### Initializing global variables
	[[ "$action_get_interfaces" == 1 ]] && ___interfaces_init
	[[ "$action_get_vlans" == 1 ]] && ___vlans_init
	[[ "$action_merge_vlans" == 1 ]] && ___vlans_merge

	### Initializing temp files
	[[ "$action_get_interfaces" == 1 ]] && echo "" > $tmp_file_interfaces_output
	[[ "$action_get_vlans" == 1 ]] && echo "" > $tmp_file_vlans_output

	### Check if we have at least one action to make and then start to loop through file(s)
	[[ "$(($action_get_vlans + $action_get_interfaces))" > 0 ]] && ___loop_through_files 
	[[ "$(($action_get_vlans + $action_get_interfaces))" > 0 ]] && ___write_output

}

### Starts the script
___init "$@"
