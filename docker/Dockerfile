FROM ros:humble-ros-base-jammy

ARG DEBIAN_FRONTEND=noninteractive
ARG UNITREE_SDK2_REF=main
ARG UNITREE_SLAM_REF=main
ARG http_proxy
ARG https_proxy
ARG no_proxy

ENV http_proxy=${http_proxy}
ENV https_proxy=${https_proxy}
ENV no_proxy=${no_proxy}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        git \
        libeigen3-dev \
        libfmt-dev \
        libyaml-cpp-dev \
        libboost-all-dev \
        python3-pip \
        python3-rosdep \
        ros-humble-rmw-cyclonedds-cpp \
        ros-humble-rviz2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/src

RUN git clone --branch "${UNITREE_SDK2_REF}" --depth 1 \
        https://github.com/unitreerobotics/unitree_sdk2.git \
    && cmake -S unitree_sdk2 -B unitree_sdk2/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/opt/unitree_robotics \
    && cmake --build unitree_sdk2/build --parallel \
    && cmake --install unitree_sdk2/build

RUN git clone --branch "${UNITREE_SLAM_REF}" --depth 1 \
        https://github.com/unitreerobotics/unitree_slam.git \
    && cmake -S unitree_slam -B unitree_slam/build \
        -DCMAKE_BUILD_TYPE=Release \
    && cmake --build unitree_slam/build --parallel

ENV RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
ENV ROS_DOMAIN_ID=0
ENV UNITREE_SLAM_DIR=/opt/src/unitree_slam
ENV UNITREE_SDK2_DIR=/opt/src/unitree_sdk2
ENV LD_LIBRARY_PATH=/opt/unitree_robotics/lib:${LD_LIBRARY_PATH}

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /workspace
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
