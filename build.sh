#!/bin/bash
set -o errexit
set –o nounset # Displays an error and exits from a shell script when you use an unset variable in an interactive shell. The default is to display a null value for an unset variable.

# packages are installed with debootstrap
# additional packages are installed later on with apt-get
packages="ssh,curl,iputils-ping,iputils-tracepath,telnet,vim,rsync"
required_packages="ubuntu-standard ubuntu-minimal htop ldap-auth-client git net-tools aptitude apache2 php5 libapache2-mod-php5 php5-cgi ruby screen fish sudo emacs mc iotop iftop nodejs ldap-utils software-properties-common libgd2-xpm"
additional_packages="erlang ghc swi-prolog clisp ruby-dev ri rake python mercurial subversion cvs bzr default-jdk"
suite="raring"
variant="buildd"
vmroot_name=$(date +%d_%m_%Y)"_base"
basedir="/var/lib/lxc/$vmroot_name"
target="$basedir/rootfs"
VM_upstart="/etc/init" # Will be executed inside lxc-attach
mirror="http://apt-mirror.koding.com/ubuntu/"

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

mkdir -p $basedir

cp vmroot-config $basedir/config
/bin/sed -i "s!MY_DIR!$vmroot_name!" $basedir/config

id vmroot >> /dev/null 2>&1
if [[ "$?" -ne 0 ]]; then
  groupadd -g 500000 vmroot
  useradd -u 500000 -g 500000 -s /bin/bash --home $target --comment "VM root user" vmroot
fi

set +o errexit # Do not exit if the route cannot be set (usually because it is already there)
ip route add 10.128.2.1 dev lxcbr0
if [ $? -eq 2 ]; then
    echo -e "\e[0;31mGot exit code 2 when setting the VMHost route to the VM"
    echo -e "This usually means that this route already existed - if you don't have internet inside the new vmroot check this first!\n"
    echo -e "I tried this command:\n  ip route add 10.128.2.1 dev lxcbr0\n\e[0m"
fi
set -o errexit

if [[ ! -d "$target" ]]; then

  lxc-stop -n $vmroot_name
  $(which debootstrap) --include $packages --variant=$variant $suite $target $mirror

  cp apt-config $target/etc/apt/sources.list

  ../go/build.sh
  ../go/bin/idshift $target 500000
  echo -e "nameserver 8.8.8.8\nsearch koding.com" > $target/etc/resolv.conf
  chown 500000:500000 $target/etc/resolv.conf
  chmod 444 $target/etc/resolv.conf

  cp kdevent.sh $target/usr/bin/kdevent
  chown 500000:500000 $target/usr/bin/kdevent
  chmod 755 $target/usr/bin/kdevent
  
  lxc-start -n $vmroot_name -d
  # Wait until VM starts
  lxc-wait -s RUNNING -n $vmroot_name -t 60
  if [[ "$?" -ne 0 ]]; then
    echo -e "Error when starting $vmroot_name - did not start after 60s"
    echo -e "\033[1;31m\nABORTING! - VMRoot was not built correctly!\033[0m\n\n"
    exit 1
  fi

  # Fix locales
  lxc-attach -n $vmroot_name -- /usr/sbin/locale-gen en_US.UTF-8
  lxc-attach -n $vmroot_name -- /usr/sbin/update-locale LANG="en_US.UTF-8"

  # Insert chris-lea PPA keyring
  lxc-attach -n $vmroot_name -- apt-key adv --keyserver keyserver.ubuntu.com --recv-keys B9316A7BC7917B12

  # Fix fstab inside vmroot
  /bin/sed -i 's!none            /sys/fs/fuse/connections!#none            /sys/fs/fuse/connections!' $target/lib/init/fstab
  /bin/sed -i 's!none            /sys/kernel/!#none            /sys/kernel/!' $target/lib/init/fstab
  /bin/sed -i 's!none            /run/shm                  tmpfs           nosuid,nodev                                 0 0!none            /run/shm                  tmpfs           nosuid,nodev,noexec,size=500M                                 0 0!'  $target/lib/init/fstab

  # Deactivate unneccesary upstart services
# Can't rename /etc/init/ureadahead.conf.disabled /etc/init/ureadahead.conf.disabled.disabled: No such file or directory
# Can't rename /etc/init/ureadahead-other.conf /etc/init/ureadahead-other.conf.disabled: No such file or directory
# Can't rename /etc/init/plymouth-ready.conf /etc/init/plymouth-ready.conf.disabled: No such file or directory

  lxc-attach -n $vmroot_name -- /usr/bin/rename s/\.conf/\.conf\.disabled/ $VM_upstart/tty*
  lxc-attach -n $vmroot_name -- /usr/bin/rename s/\.conf/\.conf\.disabled/ $VM_upstart/udev*
  lxc-attach -n $vmroot_name -- /usr/bin/rename s/\.conf/\.conf\.disabled/ $VM_upstart/upstart-*
  # lxc-attach -n $vmroot_name -- /usr/bin/rename s/\.conf/\.conf\.disabled/ $VM_upstart/ureadahead*
  lxc-attach -n $vmroot_name -- /usr/bin/rename s/\.conf/\.conf\.disabled/ $VM_upstart/hwclock*
  # lxc-attach -n $vmroot_name -- /usr/bin/rename s/\.conf/\.conf\.disabled/ $VM_upstart/plymouth*


  # Replace /dev/ptmx by proper symlink
  lxc-attach -n $vmroot_name -- /bin/ln -sf pts/ptmx /dev/ptmx

  lxc-stop -n $vmroot_name
  lxc-wait -s STOPPED -n $vmroot_name -t 60
  if [[ "$?" -ne 0 ]]; then
    echo -e "Error when stopping $vmroot_name - did not stop after 60s"
    echo -e "\033[1;31m\nABORTING! - VMRoot was not built correctly!\033[0m\n\n"
    exit 1
  fi
  lxc-start -n $vmroot_name -d
  lxc-wait -s RUNNING -n $vmroot_name -t 60
  if [[ "$?" -ne 0 ]]; then
    echo -e "Error when starting $vmroot_name - did not start after 60s"
    echo -e "\033[1;31m\nABORTING! - VMRoot was not built correctly!\033[0m\n\n"
    exit 1
  fi
  # Install additional packages
  lxc-attach -n $vmroot_name -- /usr/bin/apt-get update
  lxc-attach -n $vmroot_name -- bash -c "DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get install $required_packages -y --force-yes"
  lxc-attach -n $vmroot_name -- /usr/bin/apt-get clean

  # Configure the VMs to use LDAP lookup for users
  lxc-attach -n $vmroot_name -- /usr/sbin/auth-client-config -t nss -p lac_ldap
  lxc-attach -n $vmroot_name -- /bin/hostname vmroot
  /bin/echo "vmroot" > $target/etc/hostname

  lxc-attach -n $vmroot_name -- /usr/bin/npm install -g coffee-script
  lxc-attach -n $vmroot_name -- /usr/bin/npm install -g kd
  lxc-attach -n $vmroot_name -- /usr/bin/npm install -g kdc

  cp default-site $target/etc/apache2/sites-available/default
  /bin/rm -rf $target/var/www
set +o errexit # Do not exit if this site is already activated
  lxc-attach -n $vmroot_name -- /usr/sbin/a2ensite default
set -o errexit
  /bin/sed -i "s!ULIMIT_MAX_FILES=\"${APACHE_ULIMIT_MAX_FILES:-ulimit -n 8192}\"!ULIMIT_MAX_FILES=\"${APACHE_ULIMIT_MAX_FILES:-ulimit -n 4096}\"!" $target/usr/sbin/apache2ctl

  lxc-attach -n $vmroot_name -- /usr/bin/updatedb

  lxc-attach -n $vmroot_name -- wget http://dev.marc.waeckerlin.org/repo/PublicKey 
  lxc-attach -n $vmroot_name -- apt-key add PublicKey
  lxc-attach -n $vmroot_name -- apt-add-repository http://dev.marc.waeckerlin.org/repo
  lxc-attach -n $vmroot_name -- apt-get update
  lxc-attach -n $vmroot_name -- apt-get install openssh-akc-server -y
  cp ldapSSH.sh $target/usr/sbin/
  chown vmroot: $target/usr/sbin/ldapSSH.sh
  chmod 755 $target/usr/sbin/ldapSSH.sh
  echo -e "AuthorizedKeysCommand /usr/sbin/ldapSSH.sh" >> $target/etc/ssh/sshd_config
  echo -e "alias mc=\"mc -x\"" >> $target/etc/bash.bashrc
  chown vmroot: $target/bin/ping
  chmod u+s $target/bin/ping

  curl "https://godeb.s3.amazonaws.com/godeb-amd64.tar.gz" | tar xz -C $target/usr/bin/
  lxc-attach -n $vmroot_name -- /usr/bin/godeb install 1.1.1


  
  ######
  # Stop and start because of inaccessible /dev in vmroot
  ######
  lxc-stop -n $vmroot_name
  lxc-wait -s STOPPED -n $vmroot_name -t 60
  if [[ "$?" -ne 0 ]]; then
    echo -e "Error when stopping $vmroot_name - did not stop after 60s"
    echo -e "\033[1;31m\nABORTING! - VMRoot was not built correctly!\033[0m\n\n"
    exit 1
  fi
  cd $basedir
  /bin/sed -i "s!lxc.rootfs = /var/lib/lxc/$vmroot_name/rootfs!lxc.rootfs = /var/lib/lxc/vmroot/rootfs!" $basedir/config
  /bin/sed -i "s!lxc.rootfs = /var/lib/lxc/vmroot/rootfs!lxc.rootfs = /var/lib/lxc/$vmroot_name/rootfs!" $basedir/config

  lxc-start -n $vmroot_name -d
  lxc-wait -s RUNNING -n $vmroot_name -t 60
  if [[ "$?" -ne 0 ]]; then
    echo -e "Error when starting $vmroot_name - did not start after 60s"
    echo -e "\033[1;31m\nABORTING! - VMRoot was not built correctly!\033[0m\n\n"
    exit 1
  fi
  sleep 30
  lxc-attach -n $vmroot_name -- /usr/bin/apt-get update
  lxc-attach -n $vmroot_name -- bash -c "DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get install $additional_packages -y --force-yes"
  lxc-attach -n $vmroot_name -- /usr/bin/apt-get clean
  
  lxc-stop -n $vmroot_name
  lxc-wait -s STOPPED -n $vmroot_name -t 60
  if [[ "$?" -ne 0 ]]; then
    echo -e "Error when stopping $vmroot_name - did not stop after 60s"
    echo -e "\033[1;31m\nABORTING! - VMRoot was not built correctly!\033[0m\n\n"
    exit 1
  fi
  /bin/sed -i "s!lxc.rootfs = /var/lib/lxc/$vmroot_name/rootfs!lxc.rootfs = /var/lib/lxc/vmroot/rootfs!" $basedir/config
  /bin/tar -czvf ../$vmroot_name.tgz .
  /bin/sed -i "s!lxc.rootfs = /var/lib/lxc/vmroot/rootfs!lxc.rootfs = /var/lib/lxc/$vmroot_name/rootfs!" $basedir/config

for i in $(ls build_scripts);
   do
    if [ -f $i/install ];
      then      
        lxc-attach -n $vmroot_name -- /usr/bin/apt-get update
        lxc-attach -n $vmroot_name -- bash -c "$(cat $i/install)"
        lxc-attach -n $vmroot_name -- /usr/bin/apt-get clean
        lxc-stop -n $vmroot_name
        lxc-wait -s STOPPED -n $vmroot_name -t 60
        if [[ "$?" -ne 0 ]]; then
          echo -e "Error when stopping $vmroot_name - did not stop after 60s"
          echo -e "\033[1;31m\nABORTING! - VMRoot was not built correctly!\033[0m\n\n"
          exit 1
        fi
        /bin/sed -i "s!lxc.rootfs = /var/lib/lxc/$vmroot_name/rootfs!lxc.rootfs = /var/lib/lxc/vmroot/rootfs!" $basedir/config
        /bin/tar -czvf ../$vmroot_name"_"$i.tgz .
        /bin/sed -i "s!lxc.rootfs = /var/lib/lxc/vmroot/rootfs!lxc.rootfs = /var/lib/lxc/$vmroot_name/rootfs!" $basedir/config
      done
done
  cd ..

  echo -e "\e[0;32mSuccessfully created your new vmroot - you will find two tar files in /var/lib/lxc\e[0m"

else
  echo -e "\n$vmroot_name was already created, leaving it like it was!\n"
fi

lxc-stop -n $vmroot_name
lxc-wait -s STOPPED -n $vmroot_name -t 60
  if [[ "$?" -ne 0 ]]; then
    echo -e "Error when stopping $vmroot_name - did not stop after 60s"
    echo -e "\nThis was the last step, I don't know why this happened but the $vmroot_name was probably still build correctly :)\n\n"
    exit 1
  fi
