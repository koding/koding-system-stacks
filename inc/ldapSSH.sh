#!/bin/bash

# get configuration from /etc/ldap.conf
for x in $(cat /etc/ldap.conf | grep -v \# | sed -n 's/^\([a-zA-Z_]*\) \(.*\)$/\1=\2/p'); do
    if [ "$x" != "=" ]; then
  export $x;
    fi
done
# Step 1
# Do the ldap search
# Step 2
# Decode base64 items
# Step 3
# When we have multiple keys ldapsearch returns :: - this indicates base64 follows, we decoded them in step 2, this just fixes the ::
# Step 4
# For multiple ssh keys put sshPublicKey on each line
# Step 5
# Strip off leading LDAP stuff
# Step 6
# Only accept keys with a ssh- prefix
ldapsearch -H ${uri} \
    -w "${bindpw}" -D "${binddn}" \
    -x \
    '(&(objectClass=posixAccount)(uid='"$1"'))' \
    'sshPublicKey' \
    | perl -MMIME::Base64 -MEncode=decode -n -00 -e 's/\n +//g;s/(?<=:: )(\S+)/decode("UTF-8",decode_base64($1))/eg;print' \
    | sed 's/sshPublicKey::/sshPublicKey:/g' \
    | sed 's/^ssh/sshPublicKey: ssh/g' \
    | sed -n '/^ /{H;d};/sshPublicKey:/x;$g;s/\n *//g;s/sshPublicKey: //gp' \
    | grep ssh-
