#!/usr/bin/env bash
set -eo pipefail

source /opt/ros/humble/setup.bash

ARCH="$(uname -m)"
SLAM_LIB_DIR="/opt/src/unitree_slam/unitree_robotics/lib/${ARCH}"
if [[ -d "${SLAM_LIB_DIR}" ]]; then
    export LD_LIBRARY_PATH="/opt/unitree_robotics/lib:${SLAM_LIB_DIR}:${LD_LIBRARY_PATH:-}"
else
    export LD_LIBRARY_PATH="/opt/unitree_robotics/lib:${LD_LIBRARY_PATH:-}"
fi

printf 'G1 Official SLAM container\n'
printf 'Architecture: %s\n' "${ARCH}"
printf 'ROS distro: %s\n' "${ROS_DISTRO}"
printf 'Network interface: %s\n' "${UNITREE_NETWORK_INTERFACE:-not set}"
printf 'Official SLAM build: %s\n' "/opt/src/unitree_slam/build"
printf '\nAvailable official executables:\n'
find /opt/src/unitree_slam/build -maxdepth 1 -type f -executable -printf '  %f\n' 2>/dev/null || true
printf '\nUse the official demo with:\n'
printf '  /opt/src/unitree_slam/build/demo_mid360 ${UNITREE_NETWORK_INTERFACE:-eth0}\n\n'

exec "$@"
