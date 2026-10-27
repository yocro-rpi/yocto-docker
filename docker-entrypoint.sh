#!/usr/bin/env bash

# verify container user was set in dockerfile
if [ -z "${USER}" ]; then
  echo "Set user in Dockerfile";
  exit -1
fi

# verify host uid and gid passed in
if [ -z "${HOST_USER_ID}" -a -z "${HOST_USER_GID}" ]; then
    echo "Pass host uid and gid in docker run command" ;
    echo "e.g. -e HOST_USER_ID=$uid -e HOST_USER_GID=$gid" ;
    exit -2
fi

# replace uid and guid in /etc/passwd and /etc/group
sed -i -e "s/^${USER}:\([^:]*\):[0-9]*:[0-9]*/${USER}:\1:${HOST_USER_ID}:${HOST_USER_GID}/"  /etc/passwd
sed -i -e "s/^${USER}:\([^:]*\):[0-9]*/${USER}:\1:${HOST_USER_GID}/"  /etc/group

# Update ownership of the user's home directory
chown -R ${HOST_USER_ID}:${HOST_USER_GID} /home/${USER}

# Copy the .gitconfig file from the host to the container's user directory.
# This ensures that the container uses the same Git configuration as the host.
# Copying (instead of mounting) avoids potential access conflicts, especially
# when the file is being accessed or modified by multiple containers or the host simultaneously.
cp /tmp/host_gitconfig /home/yocto/.gitconfig
chown ${USER}:${USER} /home/yocto/.gitconfig

# allow user to run sudo
adduser ${USER} sudo

#change to /workdir after login
echo "cd /workdir" > /home/${USER}/.bashrc

# If ENV_RUN_SCRIPT set in Docker Environment, run it after login
if [ ! "${ENV_RUN_SCRIPT}" = "" ]; then
    echo "${ENV_RUN_SCRIPT}" >> /home/${USER}/.bashrc
fi

YOCTO_TMP_DIR="${YOCTO_BUILD_DIR:-/workdir/yocto-conf}/tmp"
if [ -d "${YOCTO_TMP_DIR}" ]; then
    chown ${HOST_USER_ID}:${HOST_USER_GID} "${YOCTO_TMP_DIR}"
fi

# Remove bitbake server sockets left in the build directory by an earlier
# container. On a macOS bind mount bitbake can't replace them and fails with
# "OSError: [Errno 95] Operation not supported". Only one container may use a
# build directory at a time, so no server can be running.
rm -f "${YOCTO_BUILD_DIR}/bitbake.sock" "${YOCTO_BUILD_DIR}/hashserve.sock"

# If a command was passed to docker run, execute it as the user. Otherwise, start a login shell.
if [ -n "$1" ]; then
    exec su - "${USER}" -c "$@"
else
    su - "${USER}"
fi