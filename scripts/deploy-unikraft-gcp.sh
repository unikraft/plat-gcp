#!/usr/bin/env bash
# This script automates the process of deploying unikraft built images 
# to GCP's Compute service.
#

#################################################
################ Global Defines #################
#################################################
GREEN="\e[92m"
LIGHT_BLUE="\e[94m"
RED="\e[31m"
LIGHT_RED="\e[91m"
GRAY_BG="\e[100m"
UNDERLINE="\e[4m"
BOLD="\e[1m"
END="\e[0m"

# Cloud specific global constants
# Default values, if not provided to the script. 
PROJECT="unikraft"
BASE_NAME="unikraft"
ZONE="europe-west3-c"
INSTYPE="f1-micro"
NAME=${BASE_NAME}-`date +%s`
TAG="http-server"

# System specific global vars
MOUNT_OPTS="rw"
SUDO="sudo"
MBR_SIZE=512
EXT_BUFF_SIZE=400
MBR_IMAGE="mbr.img"
FS_IMAGE="fs.img"
MBR="/usr/lib/syslinux/mbr/mbr.bin"
LIBCOM32="/usr/lib/syslinux/modules/bios/libcom32.c32"
MBOOT="/usr/lib/syslinux/modules/bios/mboot.c32"
ERROR="ERROR:"
LOG="${NAME}-log.uk"

# List of required tools 
req_tools=(
"sfdisk"
"gcloud"
"syslinux" 
"mkdosfs"
)

#################################################
############### Helper Functions ################
#################################################

# Gives script usage information to the user
function usage() {   
   echo "usage: $0 [-h] [-v] -k <unikernel> -b <bucket> [-n <name>]"
   echo "       [-z <zone>] [-i <instance-type>] [-t <tag>] [-v] [-s]"
   echo ""
   echo -e "${UNDERLINE}Mandatory Args:${END}"
   echo "<unikernel>: 	  Name/Path of the unikernel.(Please use \"KVM\" target images) "
   echo "<bucket>: 	  GCP bucket name"
   echo ""
   echo -e "${UNDERLINE}Optional Args:${END}"
   echo "<name>: 	  Image name to use on the cloud (default: ${BASE_NAME})"
   echo "<zone>: 	  GCP zone (default: ${ZONE})"
   echo "<instance-type>:  Specify the type of the machine on which you wish to deploy the unikernel (default: ${INSTYPE}) "
   echo "<tag>:		  Tag is used to identify the instances when adding network firewall rules (default: ${TAG})"
   echo "<-v>: 		  Turns on verbose mode"
   echo "<-s>: 		  Automatically starts an instance on the cloud"
   echo ""
   exit 1
}
# Directs the script output to data sink
log_pause() {
if [ -z "$V" ]
then
	exec 6>&1
	exec &>> $LOG
fi
}

# Restores/Resumes the script output to STGCPUT
log_resume() {
if [ -z "$V" ]
then
	exec >&6
fi
}

# If any command fails in script, this function will be invoked to handle the error.
function handle_error() {
	log_resume
	echo -e "${LIGHT_RED}[FAILED]${END}"
	echo -e "${LIGHT_RED}Error${END} on line:$1"
	if [ -z "$V" ]
	then
		echo -e "For more details, please see ${LIGHT_BLUE}$LOG${END} file, or run the script with verbose mode ${GRAY_BG}-v${END}" 
	fi
	clean
	exit 1
}

function handle_output() {
local cmd_out=$1
local status
status=$( echo $cmd_out | awk 'NR==1 {print $1;}' )
if [ ${status} == ${ERROR} ]
then
        echo -e "${LIGHT_RED}[FAILED]${END}"
	echo $cmd_out
	clean
	exit 1
else
	echo -e "${GREEN}[OK]${END}"
fi
}

function create_image() {
echo -n "Creating image on the cloud.............."
OUTPUT=$( gcloud compute images -q create  $NAME --source-uri gs://$BUCKET/$TAR_FILE 2>&1 )
handle_output "$OUTPUT"
}

function delete_image() {
echo -n "Deleting existing image.................."
OUTPUT=$( gcloud compute images delete $NAME --quiet 2>&1 )
handle_output "$OUTPUT"
}

function create_bucket() {
echo -n "Creating bucket on the cloud............."
log_pause
gsutil mb gs://${BUCKET};sts_code=$?;ln=$LINENO
echo ------$sts_code
if [ "$sts_code" -ne 0 ];then
	handle_error $ln
fi
log_resume
echo -e "${GREEN}[OK]${END}"
}

function unmount() {  
  # If the script is interrupted before getting to this step you'll end up with
  # lots of half-mounted loopback-devices after a while.
  # Unmount by consecutive calls to command below.

  echo -e "Unmounting and detaching $LOOP"
  sudo umount -vd $MOUNT_DIR || :

}

function clean() {
	echo -n "Cleaning temporary files................."
	log_pause
	unmount
	${SUDO} rm -rf ${TMP_DIR}
	${SUDO} rm -rf ${MOUNT_DIR}
	rm $DISK
	log_resume
	echo -e "${GREEN}[OK]${END}"
}

#################################################
################ Main Routine ###################
#################################################

# Process the arguments given to script by user
while getopts "vshk:n:b:z:i:t:" opt; do
 case $opt in
 h) usage;;
 n) NAME=$OPTARG ;;
 b) BUCKET=$OPTARG ;;
 z) ZONE=$OPTARG ;;
 k) UNIKERNEL=$OPTARG ;;
 i) INSTYPE=$OPTARG ;;
 t) TAG=$OPTARG ;;
 v) V=true ;;
 s) S=true ;;
 esac
done

shift $((OPTIND-1))

# Take root priviledge for smooth execution
${SUDO} echo "" >/dev/null

# set error callback
trap 'handle_error $LINENO' ERR

# Check if provided image file exists.
if [ ! -e "$UNIKERNEL" ]; then
  echo "Please specify a unikraft image with mandatory [-k] flag."
  echo "Run '$0 -h' for more help"
  exit 1
fi

if [ -z $BUCKET ];
then
	echo "Please specify bucket-name with mandatory [-b] flag."
	echo "Run '$0 -h' for more help"
	exit 1
else
	log_pause
	gsutil ls -b gs://${BUCKET} || create_bkt=true
	log_resume
fi

# Check if required tools are installed
for i in "${req_tools[@]}"
do
   type $i >/dev/null 2>&1 || { echo -e "Tool Not Found: ${LIGHT_BLUE}$i${END}\nPlease install : $i\n${LIGHT_RED}Aborting.${END}"; exit 1;}
done

# Check if the required binaries are present
req_bins=("$MBR" "$LIBCOM32" "$MBOOT")
for i in "${req_bins[@]}"
do
   [ ! -f $i ] && { echo -e "File Not Found:${LIGHT_BLUE}${i}${END}\nPlease install syslinux: ${LIGHT_BLUE}sudo apt install syslinux${END}\n${LIGHT_RED}Aborting.${END} " ; exit 1; }
done


# Name the final Disk
DISK=${NAME}.img

echo -e "Deploying ${LIGHT_BLUE}${DISK}${END} on Google Cloud..."
echo -e "${BOLD}Name  :${END} ${NAME}"
echo -e "${BOLD}Bucket:${END} ${BUCKET}"
echo -e "${BOLD}Zone  :${END} ${ZONE}"
echo ""
# Create the image disk
echo -n "Creating disk partitions.................";
log_pause
echo ""
# Kernel size in KBs
KERNEL_SIZE=$(( ($(stat -c%s "$UNIKERNEL") / 1024) ))
DISK_SIZE=$(( KERNEL_SIZE + EXT_BUFF_SIZE ))
SIZE=${DISK_SIZE}K
# Create temporary directories
TMP_DIR=`mktemp -d /tmp/unikraft.XXX`
MOUNT_DIR=`mktemp -d /tmp/ukmount.XXX`
# Copy the mbr to tmp dir 
cp ${MBR} ${TMP_DIR}/${MBR_IMAGE}
truncate -s ${SIZE} ${TMP_DIR}/${MBR_IMAGE}
# Create primary partition (FAT32)
echo ",,0xc,*" | sfdisk ${TMP_DIR}/${MBR_IMAGE}
# Take out the partition by skipping MBR.
dd if=${TMP_DIR}/${MBR_IMAGE} of=${TMP_DIR}/${FS_IMAGE} bs=512 skip=1
# Truncate the size of actual image to contain only mbr
truncate -s ${MBR_SIZE} ${TMP_DIR}/${MBR_IMAGE}
# Create filesystem - FAT32
mkdosfs ${TMP_DIR}/${FS_IMAGE}
log_resume
echo -e "${GREEN}[OK]${END}"
echo -n "Installing boot loader..................."
log_pause
# Install syslinux
syslinux --install ${TMP_DIR}/${FS_IMAGE}
log_resume
echo -e "${GREEN}[OK]${END}"
echo -n "Creating bootable disk image............."
log_pause
# Find first available loopback device
LOOP=$(${SUDO} losetup -f)
echo -e "Associating $LOOP with $DISK"
echo ""
# Associate loopback with disk file
${SUDO} losetup $LOOP ${TMP_DIR}/${FS_IMAGE}
echo -e "Mounting ($MOUNT_OPTS)  ${FS_IMAGE} on $MOUNT_DIR"
mkdir -p $MOUNT_DIR
${SUDO} mount -o $MOUNT_OPTS $LOOP $MOUNT_DIR
${SUDO} cp ${LIBCOM32} $MOUNT_DIR/libcom32.c32
${SUDO} cp ${MBOOT} $MOUNT_DIR/mboot.c32
${SUDO} cp $UNIKERNEL $MOUNT_DIR/unikernel.bin
cat <<EOM >${TMP_DIR}/syslinux.cfg
TIMEOUT 0
DEFAULT unikernel
LABEL unikernel
  KERNEL mboot.c32
  APPEND unikernel.bin
EOM
${SUDO} mv ${TMP_DIR}/syslinux.cfg $MOUNT_DIR/syslinux.cfg
sync
unmount
# Create Final Deployable Disk Image
echo "Creating RAW Disk"
cat ${TMP_DIR}/${MBR_IMAGE} ${TMP_DIR}/${FS_IMAGE} | dd of=${DISK} conv=sparse
log_resume
echo -e "${GREEN}[OK]${END}"
TAR_FILE=$NAME.tar.gz
# Instance name to be used on the cloud
INSTANCE_NAME=$NAME
# Create the bucket if doesn't exists
if [ "$create_bkt" = "true" ];then
	create_bucket
fi
echo -n "Uploading disk to the cloud.............."
log_pause
echo ""
echo "Creating tarfile "
cp ${DISK} disk.raw
tar -zcf $TAR_FILE disk.raw
echo "Uploading (previous image having same name will be overwritten) "
gsutil mv $TAR_FILE gs://$BUCKET/$TAR_FILE
log_resume
echo -e "${GREEN}[OK]${END}"
# Check if image already exists
IMG_STATUS=`gcloud compute images list --filter="name=($NAME)"`
if [ -z "$IMG_STATUS" ]
then
	create_image
else
	echo -e "${LIGHT_RED}An image already exists on cloud with the name: ${LIGHT_BLUE}${NAME}${END}${END}"
	echo -n "Would you like to delete the existing image and create new one (y/n)?"
	read choice
	case "$choice" in
		y|Y )	delete_image
			create_image ;;
		n|N ) echo "Please change the image name and try again." 
			clean
			exit 1 ;;
		* ) echo "Invalid choice. Please enter y|Y or n|N"
			clean
			exit 1 ;;
	esac
fi

if [ -z "$S" ]
then
        clean
        echo ""
        echo "To run the instance on GCP, use following command-"
	echo -e "${GRAY_BG}gcloud compute instances -q create $INSTANCE_NAME --image $NAME --machine-type $INSTYPE --zone $ZONE --tags $TAG ${END}"
else
        echo -n "Starting instance on the cloud..........."
        log_pause
        # This echo maintains the formatting
        echo ""
        # Start an instance on the cloud
	gcloud compute instances --quiet create $INSTANCE_NAME --image $NAME --machine-type $INSTYPE --zone $ZONE --tags $TAG > tmp_inst_info
        log_resume
        echo -e "${GREEN}[OK]${END}"
	cat tmp_inst_info
	rm tmp_inst_info
        clean
fi
log_resume
echo ""
echo -e "${UNDERLINE}NOTE:${END}"
echo "1) To see the GCP system console log, use following command-"
echo -e "${GRAY_BG} gcloud compute instances get-serial-port-output $INSTANCE_NAME --zone=${ZONE} ${END}"
echo "2) GCP takes some time to initialise the instance and start the booting process, If there is no output on serial console, Please run it again in few secs"
echo "3) Don't forget to customise GCP with proper firewall settings (if no --tags are given),"
echo "as the default one won't let any inbound traffic in."
echo ""
