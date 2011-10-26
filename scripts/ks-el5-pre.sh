%pre --interpreter /bin/bash
#!/bin/bash

# this is the same as el4, except that it adds the 'nodev' mount option
# to comply withe CIS Rhel5 Benchmark

# Options...
#
# lvm="nolvm" or lvm="lvm"
# layout="noraid" "raid0" "raid1" "raid5"
# swapsize="0" or "1+" in megs
# extraparts="<mnt point>=<size megs>,<mnt point>=<size megs>" ie "/opt=256"

lvm="%LVM%"
layout="%DISKLAYOUT%"
swapsize="%SWAPSIZE%"

# set up extraparts
while IFS=',' read -ra ADDR; do 
    for i in "${ADDR[@]}"; do
        extraparts[${#extraparts[*]}]=$i
    done 
done <<< "%EXTRAPART%"

if [ "$lvm" != "nolvm" ]
then
    echo 'LVM not supported' >&2
    exit 1
fi

# set fd 3 to our output file
exec 3<> '/tmp/disklayout.txt'

# This returns a list of devices
find_devices () {

    # look for cciss devices, and return if we find one
    # d1 goes first, as the storage blade will take the 0 spot
    for d in 'cciss/c1d0', 'cciss/c0d0'
    do
        if [ -e "/dev/$d" ]
        then

            if [ "$layout" != "noraid" ]
            then
                echo "Hard raid shouldnt be layered with soft raid" >2&
                exit 1
            fi

            disks[${#disks[*]}]=$d
        fi
    done

    # return if we have found some disks
    if [ ! -z "${disks[0]}" ]; then
        return
    fi  

    # look for scsi devices, and return if we find one
    for d in sda sdb sdc
    do
        if [ -e "/dev/$d" ]
        then
            disks[${#disks[*]}]=$d
        fi
    done

    # return if we have found some disks
    if [ ! -z "${disks[0]}" ]; then
        return
    fi  

    # look for ide devices, and return if we find one
    for d in hda hdb hdc
    do
        if [ -e "/dev/$d" ]
        then
            disks[${#disks[*]}]=$d
        fi
    done

    # return if we have found some disks
    if [ ! -z "${disks[0]}" ]; then
        return
    fi  

    echo "No disks found?" >&2
    exit 1

}

# Basic no raid profile
noraid () {

    dev=${disks[0]}

    echo "clearpart --all --initlabel" >&3
    echo "part /boot   --ondisk=$dev --size=100    --asprimary --fsoptions=nodev" >&3
    echo "part /       --ondisk=$dev --size=1      --grow" >&3

    for d in "${extraparts[@]}"
    do

        m="${d%=*}"
        s="${d##*=}"

        echo "part $m --ondisk=$dev --size=$s --asprimary --fsoptions=nodev" >&3

    done

    if [ $swapsize ] && [ $swapsize -gt 0 ]
    then
        echo "part swap    --ondisk=$dev --size=$swapsize --asprimary" >&3
    fi

}

# Basic raid0 profile
raid0 () {

    if [ ${#disks[*]} -le "2" ]
    then
        echo "Not enought disks for raid0" >&2
        exit 1
    fi

    deva=${disks[0]}
    devb=${disks[1]}

    echo "clearpart --all --initlabel\n" >&3

    echo "part raid.00 --ondisk=$deva --size=100    --asprimary\n" >&3
    echo "part raid.10 --ondisk=$devb --size=100    --asprimary\n" >&3

    echo "part raid.01 --ondisk=$deva --size=1      --grow\n" >&3
    echo "part raid.11 --ondisk=$devb --size=1      --grow\n" >&3

    c=1

    for d in "${extraparts[@]}"
    do

        c=$((c+1))

        m="${d%=*}"
        s="${d##*=}"

        echo "part raid.0$c --ondisk=$deva --size=$s   --asprimary\n" >&3
        echo "part raid.1$c --ondisk=$deva --size=$s   --asprimary\n" >&3

        extras="${extras}raid $m --level=0    --device=md$c  --fsoptions=nodev  raid.0$c raid.1$c\n"

    done

    if [ $swapsize ] && [ $swapsize -gt 0 ]
    then

        c=$((c+1))
    
        echo "part raid.0$c --ondisk=$deva --size=$swapsize   --asprimary" >&3
        echo "part raid.1$c --ondisk=$devb --size=$swapsize   --asprimary" >&3
    
        extras="${extras}raid swap    --level=0   --device=md$c  raid.0$c raid.1$c\n"

    fi

    # /boot has to be mirrored, the bios cant boot striped
    echo "raid /boot   --level=1   --device=md0  --fsoptions=nodev  raid.00 raid.10" >&3
    echo "raid /       --level=0   --device=md1  raid.01 raid.11" >&3

    if [ $extras ]
    then
        echo -e $extras  >&3
    fi

}

# Basic raid1 profile
raid1 () {

    if [ ${#disks[*]} -le "2" ]
    then
        echo "Not enought disks for raid1" >&2
        exit 1
    fi

    deva=${disks[0]}
    devb=${disks[1]}

    echo "clearpart --all --initlabel" >&3

    echo "part raid.00 --ondisk=$deva --size=100    --asprimary" >&3
    echo "part raid.10 --ondisk=$devb --size=100    --asprimary" >&3

    echo "part raid.01 --ondisk=$deva --size=1      --grow" >&3
    echo "part raid.11 --ondisk=$devb --size=1      --grow" >&3

    c=1

    for d in "${extraparts[@]}"
    do

        c=$((c+1))

        m="${d%=*}"
        s="${d##*=}"

        echo "part raid.0$c --ondisk=$deva --size=$s   --asprimary" >&3
        echo "part raid.1$c --ondisk=$deva --size=$s   --asprimary" >&3

        extras="${extras}raid $m --level=1    --device=md$c  --fsoptions=nodev  raid.0$c raid.1$c\n"

    done

    if [ $swapsize ] && [ $swapsize -gt 0 ]
    then

        c=$((c+1))
    
        echo "part raid.0$c --ondisk=$deva --size=$swapsize   --asprimary" >&3
        echo "part raid.1$c --ondisk=$devb --size=$swapsize   --asprimary" >&3
    
        extras="${extras}raid swap    --level=1   --device=md$c  raid.0$c raid.1$c\n"

    fi

    # /boot has to be mirrored, the bios cant boot striped
    echo "raid /boot   --level=1   --device=md0  --fsoptions=nodev  raid.00 raid.10" >&3
    echo "raid /       --level=1   --device=md1  raid.01 raid.11" >&3

    if [ $extras ]
    then
        echo -e $extras  >&3
    fi

}

# Basic raid5 profile
raid5 () {

    if [ ${#disks[*]} -le "3" ]
    then
        echo "Not enought disks for raid5" >&2
        exit 1
    fi

    deva=${disks[0]}
    devb=${disks[1]}
    devc=${disks[2]}

    echo "clearpart --all --initlabel" >&3

    echo "part raid.00 --ondisk=$deva --size=100     --asprimary" >&3
    echo "part raid.10 --ondisk=$devb --size=100     --asprimary" >&3
    echo "part raid.20 --ondisk=$devc --size=100     --asprimary" >&3

    echo "part raid.01 --ondisk=$deva --size=1       --grow" >&3
    echo "part raid.11 --ondisk=$devb --size=1       --grow" >&3
    echo "part raid.21 --ondisk=$devc --size=1       --grow" >&3

    c=1

    for d in "${extraparts[@]}"
    do

        c=$((c+1))

        m="${d%=*}"
        s="${d##*=}"

        echo "part raid.0$c --ondisk=$deva --size=$s   --asprimary" >&3
        echo "part raid.1$c --ondisk=$devb --size=$s   --asprimary" >&3
        echo "part raid.2$c --ondisk=$devc --size=$s   --asprimary" >&3

        extras="${extras}raid $m --level=5    --device=md$c  --fsoptions=nodev  raid.0$c raid.1$c raid.2$c\n"

    done

    if [ $swapsize ] && [ $swapsize -gt 0 ]
    then

        c=$((c+1))
    
        echo "part raid.0$c --ondisk=$deva --size=$swapsize    --asprimary" >&3
        echo "part raid.1$c --ondisk=$devb --size=$swapsize    --asprimary" >&3
        echo "part raid.2$c --ondisk=$devc --size=$swapsize    --asprimary" >&3
    
        extras="${extras}raid swap    --level=5   --device=md$c  raid.0$c raid.1$c raid.2$c\n"

    fi

    # /boot has to be mirrored, the bios cant boot parity
    echo "raid /boot   --level=1   --device=md0  --fsoptions=nodev raid.00 raid.10 raid.20" >&3
    echo "raid /       --level=5   --device=md1  raid.01 raid.11 raid.21" >&3

    if [ $extras ]
    then
        echo $extras  >&3
    fi

}

# Virtio Disks are special
if [ -e '/dev/vda' ]
then

    if [ "$layout" != "noraid" ]
    then
        echo "Virtual machines shouldnt use soft raid" >&2
        exit 1
    fi

    # 64s aligned
    start=204864 

    # create the partitions now
    parted -s /dev/vda mktable msdos
    parted -s /dev/vda mkpart primary 64s 204863s

    echo "part /boot --onpart=vda1 --fsoptions=nodev" >&3

    c=1

    for d in "${extraparts[@]}"
    do

        c=$((c+1))

        m="${d##*=}"
        s="${d%=*}"

        # sectors=(N * megabytes * kilobytes) / sector size
        finish=$((start + (s*1024*1024)/512 - 1))
    
        parted -s /dev/vda mkpart primary "${start}s" "${finish}s"

        echo "part $m --onpart=vda$c --fsoptions=nodev" >&3

        # ready for next disk 
        start=$((finish+1))

    done

    if [ $swapsize ] && [ $swapsize -gt 0 ]
    then

        c=$((c+1))

        # sectors=(N * megabytes * kilobytes) / sector size
        finish=$((start + (swapsize * 1024 * 1024)/512 - 1))
    
        parted -s /dev/vda mkpart primary "${start}s" "${finish}s"

        echo "part swap --onpart=vda$c" >&3

        # ready for next disk 
        start=$((finish+1))

    fi

    c=$((c+1))

    parted -s -- /dev/vda mkpart primary "${start}s" -1s

    echo "part / --onpart=vda$c" >&3

    # close fd 3
    exec 3>&- 

    exit 0

fi

# find devices firstly

find_devices

# decide what to do
case $layout in

    noraid)
        noraid
    ;;

    raid0)
        raid0
    ;;

    raid1)
        raid1
    ;;

    raid5)
        raid5
    ;;

    *)
    echo 'Something bad happened!!!!' >&2
    exit 1

esac

# close fd 3
exec 3>&- 

exit 0
