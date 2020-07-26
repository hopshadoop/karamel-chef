#!/bin/bash

###################################################################################################
#                                                                                                 #
# This code is released under the GNU General Public License, Version 3, see for details:         #
# http://www.gnu.org/licenses/gpl-3.0.txt                                                         #
#                                                                                                 #
#                                                                                                 #
# Copyright (c) Logical Clocks AB, 2020.                                                          #
# All Rights Reserved.                                                                            #
#                                                                                                 #
###################################################################################################

###################################################################################################
# ______  __                                           ______                                     #
# ___  / / /_______________________      _________________  /_________                            #
# __  /_/ /_  __ \__  __ \_  ___/_ | /| / /  __ \_  ___/_  //_/_  ___/                            #
# _  __  / / /_/ /_  /_/ /(__  )__ |/ |/ // /_/ /  /   _  ,<  _(__  )                             #
# /_/ /_/  \____/_  .___//____/ ____/|__/ \____//_/    /_/|_| /____/                              #
# /_/                                                                                             # 
# ______________            _________                                                             #
# __  ____/__  /_________  _______  /                                                             #
# _  /    __  /_  __ \  / / /  __  /                                                              #
# / /___  _  / / /_/ / /_/ // /_/ /                                                               #
# \____/  /_/  \____/\__,_/ \__,_/                                                                #
#                                                                                                 #
# ________             _____       ___________                                                    #
# ____  _/_______________  /______ ___  /__  /____________                                        #
#  __  / __  __ \_  ___/  __/  __ `/_  /__  /_  _ \_  ___/                                        #            
# __/ /  _  / / /(__  )/ /_ / /_/ /_  / _  / /  __/  /                                            #
# /___/  /_/ /_//____/ \__/ \__,_/ /_/  /_/  \___//_/                                             #
#                                                                                                 #
###################################################################################################

email="test"

HOPSWORKS_INSTALLER_VERSION=1.3
BRANCH=master
HOPSWORKS_INSTALLER_BRANCH=https://raw.githubusercontent.com/logicalclocks/karamel-chef/$BRANCH
CLUSTER_DEFINITION_BRANCH=https://raw.githubusercontent.com/logicalclocks/karamel-chef/$BRANCH

declare -a CPU
declare -a GPU

declare -a PRIVATE_CPU
declare -a PRIVATE_GPU

DO_LISTING=0
RM_TYPE=

INSTALL_ACTION=
HOPSWORKS_VERSION=enterprise
DOWNLOAD_URL=
PREFIX=
host_ip=
INSTALL_CPU=0
INSTALL_GPU=1
INSTALL_CLUSTER=2
PURGE=3

NON_INTERACT=0
DRY_RUN=0

ENTERPRISE=0
KUBERNETES=0
HEAD_VM_TYPE=head_cpu

INPUT_YML="cluster-defns/hopsworks-installer.yml"
WORKER_YML="cluster-defns/hopsworks-worker.yml"
WORKER_GPU_YML="cluster-defns/hopsworks-worker-gpu.yml"
YML_FILE="cluster-defns/hopsworks-installer-active.yml"

WORKER_LIST=
WORKER_IP=
WORKER_DEFAULTS=
CPU_WORKER_ID=1
GPU_WORKER_ID=1

ENTERPRISE_DOWNLOAD_URL=
ENTERPRISE_USERNAME=
ENTERPRISE_PASSWORD=
SKIP_CREATE=0

NUM_GPUS_PER_VM=
GPU_TYPE=

NUM_WORKERS_CPU=0
NUM_WORKERS_GPU=0

CLOUD=
# GCP Config
REGION=us-east1
ZONE=us-east1-c
IMAGE=centos-7-v20200714
IMAGE_PROJECT=centos-cloud
MACHINE_TYPE=n1-standard-8
NAME=
PROJECT=
SUBNET=default
NETWORK_TIER=PREMIUM
MAINTENANCE_POLICY=TERMINATE
SERVICE_ACCOUNT=--no-service-account
RESERVATION_AFFINITY=any
#SHIELD="--no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring"
SHIELD=""

BOOT_DISK=pd-ssd
BOOT_DISK_SIZE_GBS=150

RAW_SSH_KEY="${USER}:$(cat /home/$USER/.ssh/id_rsa.pub)"
#printf -v ESCAPED_SSH_KEY "%q\n" "$RAW_SSH_KEY"
ESCAPED_SSH_KEY="$RAW_SSH_KEY"
TAGS=http-server,https-server,karamel

ACTION=
# Azure Config


# AWS Config


# $1 = String describing error
exit_error()
{
  #CleanUpTempFiles

  echo "" $ECHO_OUT
  echo "Error: $1"
  echo "Exiting Hopsworks cloud installer."
  echo ""
  exit 1
}

# called if interrupt signal is handled
TrapBreak()
{
  trap "" HUP INT TERM
  echo -e "\n\nInstallation cancelled by user!"
  exit_error $EXIT_SIGNAL_CAUGHT
}

clear_screen()
{
 if [ $NON_INTERACT -eq 0 ] ; then
   echo ""
   echo "Press ENTER to continue"
   read cont < /dev/tty
 fi
 clear
}


check_linux()
{

    UNAME=$(uname | tr \"[:upper:]\" \"[:lower:]\")
    # If Linux, try to determine specific distribution
    if [ \"$UNAME\" == \"linux\" ]; then
	# If available, use LSB to identify distribution
	if [ -f /etc/lsb-release -o -d /etc/lsb-release.d ]; then
	    DISTRO=$(lsb_release -i | cut -d: -f2 | sed s/'^\t'//)
	    # Otherwise, use release info file
	else
	    DISTRO=$(ls -d /etc/[A-Za-z]*[_-][rv]e[lr]* | grep -v \"lsb\" | cut -d'/' -f3 | cut -d'-' -f1 | cut -d'_' -f1 | head -1)
	    if [ "$DISTRO" == "Ubuntu" ] ; then
		sudo apt install lsb-core -y
	    elif [ "$DISTRO" == "centos" ] || [ "$DISTRO" == "os" ] ; then
		sudo yum install redhat-lsb-core -y
	    else
		echo "Could not recognize Linux distro: $DISTRO"
		exit_error
	    fi
	fi
    else
        exit_error "This script only works for Linux."
    fi
}

splash_screen()
{
  clear
  echo ""
  echo "Karamel/Hopsworks Cloud Installer, Copyright(C) 2020 Logical Clocks AB. All rights reserved."
  echo ""
  echo "This program creates VMs on GCP/Azure/AWS and installs Hopsworks on the VMs."
  echo ""
  echo "To cancel installation at any time, press CONTROL-C"
  echo ""

  if [ ! -e ~/.ssh/id_rsa.pub ] ; then
      echo "ATTENTION."
      echo "A public ssh key cannot be found at: ~/.ssh/id_rsa.pub"
      echo "To continue, you need to create one at that path. Is that ok (y/n)?"
      read ACCEPT
      if [ "$ACCEPT" == "y" ] ; then
	  cat /dev/zero | ssh-keygen -q -N "" > /dev/null
      else
	  echo "Exiting...."
	  exit 99
      fi
  fi
  
  clear_screen
}


display_license()
{
  echo ""
  echo "This code is released under the GNU General Public License, Version 3, see:"
  echo "http://www.gnu.org/licenses/gpl-3.0.txt"
  echo ""
  echo "Copyright(C) 2020 Logical Clocks AB. All rights reserved."
  echo "Logical Clocks AB is furnishing this item \"as is\". Logical Clocks AB does not provide any"
  echo "warranty of the item whatsoever, whether express, implied, or statutory,"
  echo "including, but not limited to, any warranty of merchantability or fitness"
  echo "for a particular purpose or any warranty that the contents of the item will"
  echo "be error-free. In no respect shall Logical Clocks AB incur any liability for any"
  echo "damages, including, but limited to, direct, indirect, special, or consequential"
  echo "damages arising out of, resulting from, or any way connected to the use of the"
  echo "item, whether or not based upon warranty, contract, tort, or otherwise; "
  echo "whether or not injury was sustained by persons or property or otherwise;"
  echo "and whether or not loss was sustained from, or arose out of, the results of,"
  echo "the item, or any services that may be provided by Logical Clocks AB."
  echo ""
  printf 'Do you accept these terms and conditions? [ yes or no ] '
}

accept_license ()
  {
    read ACCEPT
    case $ACCEPT in
      yes | Yes | YES)
        ;;
	no | No | NO)
        echo ""
        exit 0
        ;;
      *)
        echo ""
        echo "Please enter either 'yes' or 'no'."
	printf 'Do you accept these terms and conditions? [ yes or no ] '
        accept_license
      ;;
     esac
}



clear_screen_no_skipline()
{
 if [ $NON_INTERACT -eq 0 ] ; then
    echo "Press ENTER to continue"
    read cont < /dev/tty
 fi
 clear
}


install_action()
{
    if [ "$INSTALL_ACTION" == "" ] ; then

        echo "-------------------- Installation Options --------------------"
	echo ""
        echo "What would you like to do?"
	echo ""
	echo "(1) Install single-host Hopsworks Community (CPU only)."
	echo ""
	echo "(2) Install single-host Hopsworks Community (with GPU(s))."
	echo ""
	echo "(3) Install a multi-host Hopsworks Community cluster."
	echo ""
	echo "(4) Install a Hopsworks Enterprise cluster."
	echo ""
	echo "(5) Install a Hopsworks Enterprise cluster with Kubernetes"
	echo ""
	printf 'Please enter your choice '1', '2', '3', '4', '5',  'q' \(quit\), or 'h' \(help\) :  '
        read ACCEPT
        case $ACCEPT in
          1)
	    INSTALL_ACTION=$INSTALL_CPU
	    ACTION="localhost-tls"
            ;;
          2)
	    INSTALL_ACTION=$INSTALL_GPU
	    ACTION="localhost-tls"
            ;;
          3)
            INSTALL_ACTION=$INSTALL_CLUSTER
            ACTION="cluster"
            ;;
          4)
            INSTALL_ACTION=$INSTALL_CLUSTER
            ACTION="enterprise"
            ENTERPRISE=1
            ;;
          5)
            INSTALL_ACTION=$INSTALL_CLUSTER
            ACTION="kubernetes"
            ENTERPRISE=1
	    KUBERNETES=1
            ;;
          h | H)
	  clear
	  get_install_option_help
	  echo -e $INSTALL_OPTION_HELP
          clear_screen_no_skipline
          install_action
          ;;
          q | Q)
          exit_error
          ;;
          *)
            echo ""
            echo "Invalid Choice: $ACCEPT"
            echo "Please enter your choice '1', '2', '3', '4', 'q', or 'h'."
	    clear_screen
            install_action
            ;;
        esac
	clear_screen
   fi
}


error_download_url()
{
    echo ""
    echo "Error. You need to export the following environment variable to run this script:"
    echo "export DOWNLOAD_URL=https://path/to/hopsworks/enterprise/binaries"
    echo ""    
    exit
}

get_ips()
{
    if [ "$CLOUD" == "gcp" ] ; then
	gcloud_get_ips
    elif [ "$CLOUD" == "azure" ] ; then
	azure_get_ips
    elif [ "$CLOUD" == "aws" ] ; then
	aws_get_ips
    fi    
    
}

cpus_gpus()
{
    if [ "$CLOUD" == "gcp" ] ; then
	CPUS=$(gcloud compute instances list | awk '{ print $1 }' | grep "^${PREFIX}" | grep -e "cpu[1-99]" | wc -l)
	GPUS=$(gcloud compute instances list | awk '{ print $1 }' | grep "^${PREFIX}" | grep -e "gpu[1-99]" | wc -l)	
    elif [ "$CLOUD" == "azure" ] ; then
	echo ""
    elif [ "$CLOUD" == "aws" ] ; then
	echo ""	
    fi
}

gcloud_get_ips()
{
    MY_IPS=$(gcloud compute instances list | grep "$PREFIX")

    echo "$MY_IPS"
    
    head="${PREFIX}head${REGION/-/}"
    if [ $INSTALL_ACTION -eq $INSTALL_CPU ] ; then
       head="${PREFIX}cpu${REGION/-/}"	
    elif [ $INSTALL_ACTION -eq $INSTALL_GPU ] ; then
       head="${PREFIX}gpu${REGION/-/}"		
    fi
    
    IP=$(echo $MY_IPS | sed -e "s/.*${head}/${head}/" | sed -e "s/RUNNING.*//"| awk '{ print $5 }')
    PRIVATE_IP=$(echo $MY_IPS | sed -e "s/.*${head}/${head}/" | sed -e "s/RUNNING.*//" | awk '{ print $4 }')
    echo -e "${head}\t Public IP: $IP \t Private IP: $PRIVATE_IP"

    cpus_gpus
    
    for i in $(seq 1 ${CPUS}) ;
    do
        cpuid="${PREFIX}cpu${i}${REGION/-/}"
	CPU[$i]=$(echo $MY_IPS | sed -e "s/.*${cpuid}/${cpuid}/" | sed -e "s/RUNNING.*//"| awk '{ print $5 }')
	PRIVATE_CPU[$i]=$(echo $MY_IPS | sed -e "s/.*${cpuid}/${cpuid}/" | sed -e "s/RUNNING.*//" | awk '{ print $4 }')
        echo -e "${cpuid}\t Public IP: ${CPU[${i}]} \t Private IP: ${PRIVATE_CPU[${i}]}"
    done

    for j in $(seq 1 ${GPUS}) ;
    do
        gpuid="${PREFIX}gpu${j}${REGION/-/}"
	GPU[$j]=$(echo $MY_IPS | sed -e "s/.*${gpuid}/${gpuid}/" | sed -e "s/RUNNING.*//"| awk '{ print $5 }')
	PRIVATE_GPU[$j]=$(echo $MY_IPS | sed -e "s/.*${gpuid}/${gpuid}/" | sed -e "s/RUNNING.*//" | awk '{ print $4 }')
        echo -e "${gpuid}\t Public IP: ${GPU[${j}]} \t Private IP: ${PRIVATE_GPU[${j}]}"
    done
}    

clear_known_hosts()
{
   echo "   ssh-keygen -R $host_ip -f /home/$USER/.ssh/known_host"
   ssh-keygen -R $host_ip -f "/home/$USER/.ssh/known_hosts" 
}    

enter_email()
{
    if [ "$email" == "" ] ; then
	printf "Please enter your email address to continue: "
	read email

	if [[ $email =~ .*@.* ]]
	then
	    echo "Registering...."
	    echo "{\"id\": \"$rand\", \"name\":\"$email\"}" > .details
	else
	    echo "Exiting. Invalid email address."
	    exit 1
	fi

	curl -H "Content-type:application/json" --data @.details http://snurran.sics.se:8443/keyword --connect-timeout 10 > /dev/null 2>&1
	clear_screen
    fi
}

enter_cloud()
{
    if [ "$CLOUD" == "" ] ; then
        echo "-------------------- Where are you installing Hopsworks? --------------------"
	echo ""
        echo "On what platform are you installing Hopsworks?"
	echo ""
	echo "(1) On-premises or private cloud."
	echo ""
	echo "(2) AWS."
	echo ""
	echo "(3) GCP."
	echo ""
	echo "(4) Azure."
	echo ""
	printf 'Please enter your choice '1', '2', '3', '4' :  '
        read ACCEPT
        case $ACCEPT in
          1)
	    CLOUD="on-premises"
            ;;
          2)
	    CLOUD="aws"
            ;;
          3)
   	    CLOUD="gcp"
            ;;
          4)
       	    CLOUD="azure"
            ;;
          *)
            echo ""
            echo "Invalid Choice: $ACCEPT"
            echo "Please enter your choice '1', '2', '3', '4'."
	    clear_screen
            enter_cloud
            ;;
        esac
	clear_screen
   fi
}


enter_prefix()
{
    if [ "$PREFIX" == "" ] ; then 
	printf "All VMs created will have their names prefixed with the string you enter here. Enter the prefix (default: $USER): "
	read PREFIX

	if [ "$PREFIX" == "" ] ; then
            PREFIX=$USER
	fi

	echo "VM name prefix: $PREFIX"

	clear_screen
    fi
}

download_installer() {

    wget -q -nc ${HOPSWORKS_INSTALLER_BRANCH}/hopsworks-installer.sh 2>&1 > /dev/null
    if [ $? -ne 0 ] ; then
	echo "Could not download hopsworks-installer.sh"
	echo "WARNING: There could be a problem with your proxy server settings."	  
        echo "You need to export either the http_proxy or https_proxy enviornment variables."
	echo "Current settings:"
	echo "http_proxy=$http_proxy"
	echo "https_proxy=$https_proxy"
	echo "PROXY=$PROXY"
	exit 3
    fi
    chmod +x hopsworks-installer.sh

    if [ ! -d cluster-defns ] ; then
	mkdir cluster-defns
    fi
    cd cluster-defns
    # Don't overwrite the YML files, so that users can customize them
    wget -q -nc ${CLUSTER_DEFINITION_BRANCH}/$INPUT_YML 2>&1 > /dev/null
    wget -q -nc ${CLUSTER_DEFINITION_BRANCH}/$WORKER_YML 2>&1 > /dev/null
    wget -q -nc ${CLUSTER_DEFINITION_BRANCH}/$WORKER_GPU_YML 2>&1 > /dev/null
    cd ..
}




add_worker()
{
    WORKER_GPUS=$1
    
    if [ "$WORKER_GPUS" -gt "0" ] ; then
        NAME="${PREFIX}gpu${GPU_WORKER_ID}${REGION/-/}"
        create_vm_gpu "worker"
        GPU_WORKER_ID=$((GPU_WORKER_ID+1))	
    else
        NAME="${PREFIX}cpu${CPU_WORKER_ID}${REGION/-/}"	
	create_vm_cpu "worker"
        CPU_WORKER_ID=$((CPU_WORKER_ID+1))		
    fi
}


cpu_worker_size()
{
   if [ $NUM_WORKERS_CPU -eq 0 ] ; then
       printf 'Please enter the number of CPU-only workers you want to add (default: 0): '
       read NUM_WORKERS_CPU
       if [ "$NUM_WORKERS_CPU" == "" ] ; then
	   NUM_WORKERS_CPU=0
       fi
   fi
   i=0
   while [ $i -lt $NUM_WORKERS_CPU ] ;
   do
       echo "Adding CPU worker ${i}"
       echo ""
      add_worker 0
      i=$((i+1))
      clear
   done
}


gpu_worker_size()
{
   if [ $NUM_WORKERS_GPU -eq 0 ] ; then    
     printf 'Please enter the number of GPU-enabled workers you want to add (default: 0): '
     read NUM_WORKERS_GPU
     if [ "$NUM_WORKERS_GPU" == "" ] ; then
       NUM_WORKERS_GPU=0
     fi
   fi
   if [ $NUM_WORKERS_GPU -ne 0 ] ; then
       select_gpu "worker"
   fi
   i=0
   while [ $i -lt $NUM_WORKERS_GPU ] ;
   do
       echo "Adding GPU worker $i"
       echo ""       
      add_worker $NUM_GPUS_PER_VM 
      i=$((i+1))
      clear
   done
}


select_gpu()
{
   printf "Please enter the number of GPUs for the $1 VM(s) (default: 0): "
   read NUM_GPUS_PER_VM
   if [ "$NUM_GPUS_PER_VM" == "" ] ; then
       NUM_GPUS_PER_VM=0
   else
     echo ""
     echo "Available GPU types: v100, p100, k80"
     printf 'Please enter the type of GPU: '
     read GPU_TYPE
     case $GPU_TYPE in
         v100 | p100 | k80)
	  echo ""
	  echo "Number of GPUs per GPU-enabled VM: $NUM_GPUS_PER_VM  GPU type: $GPU_TYPE"
        ;;
        *)
          echo "Invalid GPU choice. Try again."
          echo ""
          select_gpu $1
        ;;
     esac
   fi
}



enter_enterprise_credentials()
{

    if [ "$ENTERPRISE_DOWNLOAD_URL" == "" ] ; then
        echo ""
        printf "Enter the URL for downloading the Enterprise binaries: "
        read ENTERPRISE_DOWNLOAD_URL
        if [ "$ENTERPRISE_DOWNLOAD_URL" == "" ] ; then
	    echo "Enterprise URL cannot be empty"
	    echo "Exiting."
	    exit 30
	fi
	# Escape URL
	ENTERPRISE_DOWNLOAD_URL=${ENTERPRISE_DOWNLOAD_URL//\./\\\.}
	ENTERPRISE_DOWNLOAD_URL=${ENTERPRISE_DOWNLOAD_URL//\//\\\/}
    fi
    if [ "$ENTERPRISE_USERNAME" == "" ] ; then    
        echo ""
        printf "Enter the username for downloading the Enterprise binaries: "
        read ENTERPRISE_USERNAME
        if [ "$ENTERPRISE_USERNAME" == "" ] ; then
	    echo "Enterprise username cannot be empty"
	    echo "Exiting."
	    exit 32
	fi
    fi
    if [ "$ENTERPRISE_PASSWORD" == "" ] ; then    
        echo ""
        printf "Enter the password for the user ($ENTERPRISE_USERNAME): "
        read -s ENTERPRISE_PASSWORD
	echo ""
        if [ "$ENTERPRISE_PASSWORD" == "" ] ; then
	    echo "The password cannot be empty"
	    echo "Exiting."
	    exit 3
	fi
    fi
}


###################################################################
#  GCLOUD VM OPERATIONS                                           #
###################################################################

check_gcp_tools()
{    
    which gcloud > /dev/null
    if [ $? -ne 0 ] ; then
	echo "gcloud does not appear to be installed"
	printf 'Do you want to install gcloud tools? Enter: 'yes' or 'no' (default: yes): '
	read INSTALL_GCLOUD
	if [ "$INSTALL_GCLOUD" == "yes" ] ; then
            echo "Installing google-cloud-sdk"
	else
	    echo "Exiting...."
	    exit 44
	fi

	if [ "$DISTRO" == "Ubuntu" ] ; then
          echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
          sudo apt-get install apt-transport-https ca-certificates gnupg
          curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
          sudo apt-get update -y && sudo apt-get install google-cloud-sdk
	elif [ "$DISTRO" == "centos" ] || [ "$DISTRO" == "os" ] ; then
          sudo tee -a /etc/yum.repos.d/google-cloud-sdk.repo << EOM
[google-cloud-sdk]
name=Google Cloud SDK
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOM
	  yum install google-cloud-sdk -y
        fi
      gcloud init
    fi
}


gcloud_setup()
{
    if [ $NON_INTERACT -eq 0 ] ; then
	check_gcp_tools
    fi
    
    if [ ! -e ~/.ssh/id_rsa.pub ] ; then
	clear_screen
	echo "Error!"
	echo "You do not a public openssh key in ~/.ssh/id_rsa.pub"
	echo "Exiting ..."
	echo ""
	exit 1
    fi    

    RAW_SSH_KEY="${USER}:$(cat /home/$USER/.ssh/id_rsa.pub)"
    #printf -v ESCAPED_SSH_KEY "%q\n" "$RAW_SSH_KEY"
    ESCAPED_SSH_KEY="$RAW_SSH_KEY"
    TAGS=http-server,https-server,karamel
    SUBNET=default
    NETWORK_TIER=PREMIUM
    MAINTENANCE_POLICY=TERMINATE
    SERVICE_ACCOUNT=--no-service-account
    BOOT_DISK=pd-ssd
    RESERVATION_AFFINITY=any
    #SHIELD="--no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring"
    SHIELD=""
    #LOCAL_DISK=
    # add many local NVMe disks with multiple entries
    #LOCAL_DISK="--local-ssd=interface=NVME --local-ssd=interface=NVME "

    GCP_USER=$USER

    if [ $NON_INTERACT -eq 0 ] ; then    
	gcloud config get-value project
	echo ""
	printf "Do you want to use the current active project (y/n)? (default: y) "
	read CHANGE_PROJECT

	if [ "$CHANGE_PROJECT" == "" ] || [ "$CHANGE_PROJECT" == "y" ] ; then
	    echo ""
	else
	    gcloud projects list --sort-by=projectId
	    echo ""
	    printf "Enter the PROJECT_ID: "
	    read CHANGE_PROJECT
	    gcloud config set core/project $CHANGE_PROJECT > /dev/null 2>&1
	fi
    fi
    PROJECT=$(gcloud config get-value core/project 2> /dev/null)
    echo "Active project is: $PROJECT"

    if [ $NON_INTERACT -eq 0 ] ; then
       clear_screen
    fi

    if [ $NON_INTERACT -eq 0 ] ; then
	gcloud config get-value compute/region
	echo ""
	printf "Do you want to use the current active region (y/n)? (default: y) "
	read CHANGE_REGION

	if [ "$CHANGE_REGION" == "" ] || [ "$CHANGE_REGION" == "y" ] ; then
	    echo ""
	else
	    gcloud compute regions list | awk '{ print $1 }'
	    echo ""
	    printf "Enter the REGION: "
	    read CHANGE_REGION
	    gcloud config set compute/region $CHANGE_REGION  > /dev/null 2>&1
	fi
    fi
    REGION=$(gcloud config get-value compute/region 2> /dev/null)    
    echo "Active region is: $REGION"
    if [ $NON_INTERACT -eq 0 ] ; then
       clear_screen
    fi
    
    if [ $NON_INTERACT -eq 0 ] ; then
	gcloud config get-value compute/zone
	echo ""
	printf "Do you want to use the current active zone (y/n)? (default: y) "
	read CHANGE_ZONE

	if [ "$CHANGE_ZONE" == "" ] || [ "$CHANGE_ZONE" == "y" ] ; then
	    echo ""
	else
	    gcloud compute zones list | grep $REGION  | awk '{ print $1 }'
	    echo ""
	    printf "Enter the ZONE: "
	    read CHANGE_ZONE
	    gcloud config set compute/zone $CHANGE_ZONE > /dev/null 2>&1
	fi
    fi
    ZONE=$(gcloud config get-value compute/zone 2> /dev/null)    
    echo "Active zone is: $ZONE"
    if [ $NON_INTERACT -eq 0 ] ; then
      clear_screen
    fi

    if [ $NON_INTERACT -eq 0 ] ; then    
	printf "Select IMAGE/IMAGE_PROJECT (centos/ubuntu/custom)? (default: centos) "
	read SELECT_IMAGE

	if [ "$SELECT_IMAGE" == "" ] || [ "$SELECT_IMAGE" == "centos" ] ; then
	    IMAGE=centos-7-v20200714
	    IMAGE_PROJECT=centos-cloud
	elif [ "$SELECT_IMAGE" == "ubuntu" ] ; then
	    IMAGE=ubuntu-1804-bionic-v20200716
	    IMAGE_PROJECT=ubuntu-os-cloud
	else
	    echo "Examples of IMAGE/IMAGE_PROJECT are:"
	    echo "IMAGE=centos-7-v20200714  \t IMAGE_PROJECT=ubuntu-os-cloud"
	    echo "IMAGE=ubuntu-1804-bionic-v20200716 \t IMAGE_PROJECT=ubuntu-os-cloud"
	    echo ""
	    printf "Enter the IMAGE: "
	    read IMAGE
	    printf "Enter the IMAGE_PROJECT: "
	    read IMAGE_PROJECT
	fi
	echo
	echo "Active IMAGE is: $IMAGE"
	echo "Active IMAGE_PROJECT is: $IMAGE_PROJECT"
	echo ""    
	clear_screen
    fi
}

gcloud_list_private_ips()
{
    echo ""
}


gcloud_list_public_ips()
{    
    gcloud compute instances list 
}


_gcloud_precreate()
{
    VM_IP=$(gcloud compute instances list | grep $NAME | awk '{ print $5 }')
    if [ "$VM_IP" != "" ] ; then
	echo ""
	echo "WARNING:"	
	echo "VM already exists with name: $NAME"
	echo ""	
    fi

    echo ""
    echo "For the $1 VM:"
    echo "Image type: $MACHINE_TYPE"
    printf "Is the default image type OK (y/n)? (default: y) "
    read CHANGE_IMAGE
    if [ "$CHANGE_IMAGE" == "y" ] || [ "$CHANGE_IMAGE" == "" ] ; then
	echo ""
    else
	echo ""
	echo "Example image types: n1-standard-8, n1-standard-16, n1-standard-32"
	printf "Enter the image type: "
	read MACHINE_TYPE
    fi
    echo "Image type selected: $MACHINE_TYPE"

    echo ""
    echo "Boot disk size: $BOOT_DISK_SIZE_GBS"
    printf "Is the default boot disk size (GBs) OK (y/n)? (default: y) "
    read CHANGE_SIZE
    if [ "$CHANGE_SIZE" == "y" ] || [ "$CHANGE_SIZE" == "" ] ; then
	echo ""
    else
	echo ""
	printf "Enter the boot disk size in GBs: "
	read BOOT_DISK_SIZE_GBS
    fi
    BOOT_SIZE="${BOOT_DISK_SIZE_GBS}GB"
    echo "Boot disk size: $BOOT_SIZE"
    
}

gcloud_create_gpu()
{
    GCP_GPU_TYPE=nvidia-tesla-${GPU_TYPE}
    ACCELERATOR="--accelerator=type=${GCP_GPU_TYPE},count=${NUM_GPUS_PER_VM} "    
    _gcloud_create_vm $1
}

gcloud_create_cpu()
{
    ACCELERATOR=""
    _gcloud_create_vm $1 
}

_gcloud_create_vm()
{
    _gcloud_precreate $1
echo "    gcloud compute --project=$PROJECT instances create $NAME --zone=$ZONE --machine-type=$MACHINE_TYPE --subnet=$SUBNET --network-tier=$NETWORK_TIER --maintenance-policy=$MAINTENANCE_POLICY $SERVICE_ACCOUNT --no-scopes $ACCELERATOR --tags=$TAGS --image=$IMAGE --image-project=$IMAGE_PROJECT --boot-disk-size=$BOOT_SIZE --boot-disk-type=$BOOT_DISK $LOCAL_DISK --boot-disk-device-name=$NAME --reservation-affinity=$RESERVATION_AFFINITY --metadata=ssh-keys=\"$ESCAPED_SSH_KEY\""
    
    gcloud compute --project=$PROJECT instances create $NAME --zone=$ZONE --machine-type=$MACHINE_TYPE --subnet=$SUBNET --network-tier=$NETWORK_TIER --maintenance-policy=$MAINTENANCE_POLICY $SERVICE_ACCOUNT --no-scopes $ACCELERATOR --tags=$TAGS --image=$IMAGE --image-project=$IMAGE_PROJECT --boot-disk-size=$BOOT_SIZE --boot-disk-type=$BOOT_DISK $LOCAL_DISK --boot-disk-device-name=$NAME --reservation-affinity=$RESERVATION_AFFINITY --metadata=ssh-keys="$ESCAPED_SSH_KEY"
    if [ $? -ne 0 ] ; then
      echo "Problem creating VM. Exiting ..."
      exit 12
    fi
}


gcloud_delete_vm()
{
    if [ "$RM_TYPE" == "cluster" ] ; then
	NAME="${PREFIX}head${REGION/-/}"
	echo "nohup gcloud compute instances delete -q $NAME > gcp-installer.log 2>&1 </dev/null &"
        nohup gcloud compute instances delete -q $NAME > gcp-installer.log 2>&1  &

	cpus_gpus

	for i in $(seq 1 ${CPUS}) ;
	do
            cpuid="${PREFIX}cpu${i}${REGION/-/}"
            nohup gcloud compute instances delete -q $cpuid > gcp-installer.log 2>&1  &	    
	done
	
	for j in $(seq 1 ${GPUS}) ;
	do
            gpuid="${PREFIX}gpu${i}${REGION/-/}"
            nohup gcloud compute instances delete -q $gpuid > gcp-installer.log 2>&1  &	    	    
	done
    else
        NAME="${PREFIX}${RM_TYPE}${REGION/-/}"
	echo "nohup gcloud compute instances delete -q $NAME > gcp-installer.log 2>&1 </dev/null &"
        nohup gcloud compute instances delete -q $NAME > gcp-installer.log 2>&1  & 	
    fi
    RES=$?
    echo "Deleting in the background. Check gcp-installer.log for status."
    exit $RES
}

###################################################################
#  AZURE VM OPERATIONS                                            #
###################################################################


check_az_tools()
{
  echo "Checking az tools"
}

az_setup()
{
  echo ""
}


az_list_private_ips()
{
  echo ""
}


az_list_public_ips()
{
  echo ""
}

_az_precreate()
{
  echo ""
}

az_create_gpu()
{
  echo ""    
}

az_create_cpu()
{
  echo ""    
}

_az_create_vm()
{
  echo ""    
}


az_delete_vm()
{
  echo ""
}


###################################################################
#  AWS VM OPERATIONS                                              #
###################################################################

check_aws_tools()
{
  echo ""
}

aws_setup()
{
  echo ""
}

aws_list_private_ips()
{
  echo ""
}


aws_list_public_ips()
{
  echo ""
}

_aws_precreate()
{
  echo ""
}

aws_create_gpu()
{
  echo ""    
}

aws_create_cpu()
{
  echo ""    
}

_aws_create_vm()
{
  echo ""    
}


aws_delete_vm()
{
  echo ""
}


###################################################################
#  ABSTRACT VM OPERATIONS                                              #
###################################################################


_missing_cloud()
{
    echo "You forgot to specify your cloud provider. "
    echo "Add the switch '-c gcp' for GCP, '-c aws' for AWS, '-c azure' for Azure."
    echo ""
    exit 42    
}    

create_vm_cpu()
{
    echo "Creating VM...."
    echo ""
    if [ "$CLOUD" == "gcp" ] ; then
      gcloud_create_cpu $1
    elif [ "$CLOUD" == "azure" ] ; then
      az_create_cpu $1
    elif [ "$CLOUD" == "aws" ] ; then
      aws_create_cpu $1
    else
      _missing_cloud	
    fi
    clear
}

create_vm_gpu()
{
    echo "Creating gpu-enabled VM...."
    echo ""
    if [ "$CLOUD" == "gcp" ] ; then
      gcloud_create_gpu $1
    elif [ "$CLOUD" == "azure" ] ; then
      az_create_gpu $1
    elif [ "$CLOUD" == "aws" ] ; then
      aws_create_gpu $1
    else
      _missing_cloud	
    fi
    clear
}


delete_vm()
{
    if [ "$CLOUD" == "gcp" ] ; then
      gcloud_delete_vm
    elif [ "$CLOUD" == "azure" ] ; then
      az_delete_vm
    elif [ "$CLOUD" == "aws" ] ; then
	aws_delete_vm
    else
      _missing_cloud	
    fi    
}

list_private_ips()
{
    if [ "$CLOUD" == "gcp" ] ; then
      gcloud_list_private_ips
    elif [ "$CLOUD" == "azure" ] ; then
      az_list_private_ips
    elif [ "$CLOUD" == "aws" ] ; then
      aws_list_private_ips
    else
      _missing_cloud	
    fi    
}

list_public_ips()
{
    echo "Listing public IPs"
    echo ""
    if [ "$CLOUD" == "gcp" ] ; then
      gcloud_list_public_ips
    elif [ "$CLOUD" == "azure" ] ; then
      az_list_public_ips
    elif [ "$CLOUD" == "aws" ] ; then
	aws_list_public_ips
    else
      _missing_cloud	
    fi    
}

cloud_setup()
{
    if [ "$CLOUD" == "gcp" ] ; then
      gcloud_setup
    elif [ "$CLOUD" == "azure" ] ; then
      az_setup
    elif [ "$CLOUD" == "aws" ] ; then
      aws_setup
    else
      _missing_cloud	
    fi    
}    

###################################################################
#   MAIN                                                          #
###################################################################



while [ $# -gt 0 ]; do    # Until you run out of parameters . . .
  case "$1" in
    -h|--help|-help)
              echo "usage: [sudo] ./$SCRIPTNAME "
	      echo " [-h|--help]      help message"
	      echo " [-i|--install-action community|community-gpu|community-cluster|enterprise|kubernetes]"
	      echo "                 'community' installs Hopsworks Community on a single VM"
	      echo "                 'community-gpu' installs Hopsworks Community on a single VM with GPU(s)"
	      echo "                 'community-cluster' installs Hopsworks Community on a multi-VM cluster"
	      echo "                 'enterprise' installs Hopsworks Enterprise (single VM or multi-VM)"
	      echo "                 'kubernetes' installs Hopsworks Enterprise (single VM or multi-VM) alson with open-source Kubernetes"
	      echo "                 'purge' removes any existing Hopsworks Cluster (single VM or multi-VM) and destroys its VMs"	      
	      echo " [-c|--cloud gcp|aws|azure] Name of the public cloud "
	      echo " [-dr|--dry-run]  generates cluster definition (YML) files, allowing customization of clusters."	      
	      echo " [-g|--num-gpu-workers num] Number of workers (with GPUs) to create for the cluster."
	      echo " [-gpus|--num-gpus-per-worker num] Number of GPUs per worker."
	      echo " [-gt|--gpu-type type]"
	      echo "                 'v100' Nvidia Tesla V100"
	      echo "                 'p100' Nvidia Tesla P100"
	      echo "                 'k80' Nvidia K80"	      
	      echo " [-d|--download-enterprise-url url] downloads enterprise binaries from this URL."
	      echo " [-dc|--download-url url] downloads binaries from this URL."
	      echo " [-du|--download-user username] Username for downloading enterprise binaries."
	      echo " [-dp|--download-password password] Password for downloading enterprise binaries."
	      echo " [-l|--list-public-ips] List the public ips of all VMs."
	      echo " [-n|--vm-name-prefix name] The prefix for the VM name created."
	      echo " [-ni|--non-interactive] skip license/terms acceptance and all confirmation screens."
	      echo " [-rm|--remove cluster]"
	      echo "                 'cpu' single-VM Hopsworks Community (no GPUs)"
	      echo "                 'gpu' single-VM Hopsworks Community with GPU(s)"
	      echo "                 'cluster' Hopsworks Cluster - Community or Entperise"
	      echo " [-sc|--skip-create] skip creating the VMs, use the existing VM(s) with the same vm_name(s)."
	      echo " [-w|--num-cpu-workers num] Number of workers (CPU only) to create for the cluster."	      
	      echo ""
	      exit 3
              break
	      ;;
    -i|--install-action)
	      shift
	      case $1 in
		 community)
		      INSTALL_ACTION=$INSTALL_CPU
		      ACTION="localhost-tls"
  		      ;;
		 community-gpu)
                      INSTALL_ACTION=$INSTALL_GPU
		      ACTION="localhost-tls"		     
  		      ;;
		 community-cluster)
                      INSTALL_ACTION=$INSTALL_CLUSTER
		      ENTERPRISE=0
		      ACTION="cluster"
		      ;;
		 enterprise)
		      INSTALL_ACTION=$INSTALL_CLUSTER
                      ENTERPRISE=1
		      ACTION="enterprise"		      
		      ;;
		 kubernetes)
		      INSTALL_ACTION=$INSTALL_CLUSTER
                      ENTERPRISE=1
                      KUBERNETES=1
		      ACTION="kubernetes"		      
		      ;;
	         purge)
		      INSTALL_ACTION=$PURGE
		      ;;
		  *)
		      echo "Could not recognise '-i' option: $1"
		      exit_error "Failed."
		 esac
	       ;;
    -c|--cloud)
	      shift
	      case $1 in
		 gcp|aws|azure)
		      CLOUD=$1
  		      ;;
		  *)
		      echo "Could not recognise '-c' option: $1"
		      exit_error "Failed."
		 esac
	       ;;
    -d|--download-enterprise-url)
      	      shift
	      ENTERPRISE_DOWNLOAD_URL=$1
	      ;;
    -dc|--download-url)
      	      shift
	      DOWNLOAD_URL=$1
	      ;;
    -du|--download-username)
      	      shift
	      ENTERPRISE_USER=$1
	      ;;
    -dp|--download-password)
      	      shift
	      ENTERPRISE_PASSWORD=$1
	      ;;
    -dr|--dry-run)
              DRY_RUN=1
              ;;
    -g|--num-gpu-workers)
              shift
	      NUM_WORKERS_GPU=$1
              ;;
    -gpus|--num-gpus-per-host)
      	      shift
              NUM_GPUS_PER_VM=$1
	      ;;
    -gt|--gpu-type)
      	      shift
	      case $1 in
		 v100 | p100 | k80)
		      GPU_TYPE=$1
  		      ;;
		  *)
		      echo "Could not recognise option: $1"
		      exit_error "Failed."
	      esac
	      ;;
    # -gn|--gcp-nvme)
    # 	      NUM_GCP_NVME_DRIVES_PER_WORKER=$1
    # 	      GCP_NVME=1
    # 	      ;;
    -l|--list-public-ips)
	      DO_LISTING=1
	      ;;	
    -ni|--non-interactive)
	      NON_INTERACT=1
	      ;;
    -rm|--remove)
              shift
	      case $1 in
		 cpu | gpu | cluster)
		      RM_TYPE=$1
  		      ;;
		  *)
		      echo "Could not recognise option: $1"
		      exit_error "Failed."
	      esac
	      ;;

    -n|--vm-name-prefix)
      	      shift
	      PREFIX=$1
              ;;
    -sc|--skip-create)
      	      SKIP_CREATE=1
              ;;
    -p|--http-proxy)
              shift
              PROXY=$1
              proto="$(echo $PROXY | grep :// | sed -e's,^\(.*://\).*,\1,g')"
	      if [ "$proto" == "http://" ] ; then
		  export http_proxy=$PROXY
	      elif [ "$proto" == "https://" ] ; then
		  export https_proxy=$PROXY
	      else
		  echo "Invalid proxy URL: $PROXY"
		  echo "URL must start with 'https://'  or 'http://'"
		  exit 20
	      fi	      
	      ;;
    -w|--num-cpu-workers)
              shift
	      NUM_WORKERS_CPU=$1
              ;;
    *)
	  exit_error "Unrecognized parameter: $1"
	  ;;
  esac
  shift       # Check next set of parameters.
done


if [ $DO_LISTING -eq 1 ] ; then
    list_public_ips
    exit 0
fi

if [ "$RM_TYPE" != "" ] ; then
    if [ "$PREFIX" == "" ] ; then
	PREFIX=$USER
    fi
    delete_vm
    exit 0
fi    

#CPUS=$1
#GPUS=$2

#. config.sh $PREFIX "head"
if [ $DRY_RUN -eq 1 ] ; then
    NON_INTERACT=1
fi    

if [ $NON_INTERACT -eq 0 ] ; then    
  check_linux
  splash_screen
  display_license
  accept_license
  clear_screen
  enter_email
  enter_cloud
  install_action
  enter_prefix    
fi

download_installer
if [ $DRY_RUN -eq 1 ] ; then
    echo ""
    echo "The cluster definition (YML) files are now available here:"
    echo "$(pwd)/cluster-defns"
    ls -l $(pwd)/cluster-defns
    echo ""    
    echo "You can customize/edit them and re-run this installer."
    echo ""
    exit 0
fi    
cloud_setup

if [ $INSTALL_ACTION -eq $INSTALL_CPU ] ; then
    NAME="${PREFIX}cpu${REGION/-/}"    
elif [ $INSTALL_ACTION -eq $INSTALL_GPU ] ; then
    NAME="${PREFIX}gpu${REGION/-/}"
    if [ $NON_INTERACT -eq 0 ] ; then        
	select_gpu "head"
    fi
elif [ $INSTALL_ACTION -eq $INSTALL_CLUSTER ] ; then    
    NAME="${PREFIX}head${REGION/-/}"
    if [ $NON_INTERACT -eq 0 ] ; then        
	select_gpu "head"
    fi
elif [ $INSTALL_ACTION -eq $PURGE ] ; then
    delete
else
    exit_error "Bad install action: $INSTALL_ACTION"
fi

if [ $SKIP_CREATE -eq 0 ] ; then
    if [ $INSTALL_ACTION -eq $INSTALL_GPU ] ; then    
	create_vm_gpu "head"
    else
	create_vm_cpu "head"
    fi
    #$PREFIX $CPUS $GPUS $HEAD_VM_TYPE
    if [ $INSTALL_ACTION -eq $INSTALL_CLUSTER ] ; then    
      cpu_worker_size
      gpu_worker_size
    fi
else
    echo "Skipping VM creation...."
fi	

if [ $INSTALL_ACTION -eq $INSTALL_CLUSTER ] ; then    
    NAME="${PREFIX}head${REGION/-/}"
fi  

get_ips
host_ip=$IP
clear_known_hosts

if [[ "$IMAGE" == *"centos"* ]]; then
    ssh -t -o StrictHostKeyChecking=no $IP "sudo yum install wget -y > /dev/null"
fi    


echo "Installing installer on $IP"
scp -o StrictHostKeyChecking=no ./hopsworks-installer.sh ${IP}:
if [ $? -ne 0 ] ; then
    echo "Problem copying installer to head server. Exiting..."
    exit 10
fi    

ssh -t -o StrictHostKeyChecking=no $IP "mkdir -p cluster-defns"
if [ $? -ne 0 ] ; then
    echo "Problem creating 'cluster-defns' directory on head server. Exiting..."
    exit 11
fi    

scp -o StrictHostKeyChecking=no ./cluster-defns/hopsworks-*.yml ${IP}:~/cluster-defns/
if [ $? -ne 0 ] ; then
    echo "Problem scp'ing cluster definitions to head server. Exiting..."
    exit 12
fi    

if [ $INSTALL_ACTION -eq $INSTALL_CLUSTER ] ; then
    
    ssh -t -o StrictHostKeyChecking=no $IP "if [ ! -e ~/.ssh/id_rsa.pub ] ; then cat /dev/zero | ssh-keygen -q -N \"\" ; fi"
    pubkey=$(ssh -t -o StrictHostKeyChecking=no $IP "cat ~/.ssh/id_rsa.pub")

    keyfile=".pubkey.pub"
    echo "$pubkey" > $keyfile
    echo ""
    echo "Public key for head node is:"
    echo "$pubkey"
    echo ""


    WORKERS="-w "
    for i in $(seq 1 ${CPUS}) ;
    do
	host_ip=${CPU[${i}]}
	echo "I think host_ip is ${CPU[$i]}"
	echo "I think host_ip is ${CPU[${i}]}"
	echo "All  hosts ${CPU[*]}"    
	clear_known_hosts

	ssh-copy-id -o StrictHostKeyChecking=no -f -i $keyfile ${CPU[${i}]}
	ssh -t -o StrictHostKeyChecking=no $IP "ssh -t -o StrictHostKeyChecking=no ${PRIVATE_CPU[${i}]} \"pwd\""
	if [ $? -ne 0 ] ; then
	    echo ""
	    echo "Error. Public key SSH from $IP to ${PRIVATE_CPU[${i}]} not working."
	    echo "Exiting..."
	    echo ""
	    exit 9
	else
	    echo "Success: SSH from $IP to ${PRIVATE_CPU[${i}]}"
	fi

	WORKERS="${WORKERS}${PRIVATE_CPU[${i}]},"

	echo "workers: $WORKERS"
    done

    for i in $(seq 1 ${GPUS}) ;
    do
	host_ip=${GPU[${i}]}	
	echo "I think host_ip is ${GPU[$i]}"
	echo "I think host_ip is ${GPU[${i}]}"
	echo "All  hosts ${GPU[*]}"    
	clear_known_hosts
	ssh-copy-id -o StrictHostKeyChecking=no -f -i $keyfile ${GPU[${i}]}
	ssh -t -o StrictHostKeyChecking=no $IP "ssh -t -o StrictHostKeyChecking=no ${PRIVATE_GPU[${i}]} \"pwd\""
	if [ $? -ne 0 ] ; then
	    echo ""
	    echo "Error. Public key SSH from $IP to ${PRIVATE_GPU[${i}]} not working."
	    echo "Exiting..."
	    echo ""
	    exit 9
	else
	    echo "Success: SSH from $IP to ${PRIVATE_GPU[${i}]}"
	fi

	WORKERS="${WORKERS}${PRIVATE_GPU[${i}]},"

	echo "workers: $WORKERS"
    done
    WORKERS=${WORKERS::-1}
else
    WORKERS="-w none"
fi

if [ $ENTERPRISE -eq 1 ] ; then
    DOWNLOAD=""
    if [ "$ENTERPRISE_DOWNLOAD_URL" != "" ] ; then
	DOWNLOAD="-d $ENTERPRISE_DOWNLOAD_URL "
    fi
    if [ "$ENTERPRISE_USERNAME" != "" ] ; then
	DOWNLOAD_USERNAME="-du $ENTERPRISE_USERNAME "
    fi
    if [ "$ENTERPRISE_PASSWORD" != "" ] ; then
	DOWNLOAD_PASSWORD="-dp $ENTERPRISE_PASSWORD "
    fi
fi

echo ""
echo "Running installer on $IP :"
echo ""

echo "ssh -t -o StrictHostKeyChecking=no $IP \"/home/$USER/hopsworks-installer.sh -i $ACTION -ni -c $CLOUD ${DOWNLOAD}${DOWNLOAD_USERNAME}${DOWNLOAD_PASSWORD}$WORKERS && sleep 5\""

ssh -t -o StrictHostKeyChecking=no $IP "/home/$USER/hopsworks-installer.sh -i $ACTION -ni -c $CLOUD ${DOWNLOAD}${DOWNLOAD_USERNAME}${DOWNLOAD_PASSWORD}$WORKERS && sleep 5"

if [ $? -ne 0 ] ; then
    echo "Problem running installer. Exiting..."
    exit 2
fi

echo ""
echo "****************************************"
echo "*                                      *"
echo "* Public IP access to Karamel at:      *"
echo "  http://${IP}:9090/index.html   "
echo "*                                      *"
echo "* Public IP access to Hopsworks at:    *"
echo "  https://${IP}/hopsworks   "
echo "*                                      *"
echo "* View installation progress:          *"
echo " ssh ${IP} \"tail -f installation.log\"   "
echo "****************************************"
