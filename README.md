# G1 Official SLAM Indoor Navigation

使用 Unitree 官方 SLAM interface，在 G1 + Mid-360 上驗證室內建圖、重定位與導航。

## Current Direction

第一階段使用：

```text
unitree_slam + unitree_sdk2 + G1 firmware SLAM service
```

暫不導入 `slam_toolbox`、AMCL、Nav2 或自建 `cmd_vel` bridge。只有在官方導航介面無法滿足需求時，才增加 ROS2 adapter。

## Official Source

- [unitree_slam](https://github.com/unitreerobotics/unitree_slam)
- [unitree_sdk2](https://github.com/unitreerobotics/unitree_sdk2)
- [unitree_ros2](https://github.com/unitreerobotics/unitree_ros2)
- [Python_unitree_demos](https://github.com/unitreerobotics/Python_unitree_demos)

## Documents

- [Official SLAM indoor navigation guide](G1_Official_SLAM_Indoor_Navigation.md)
- [Previous 2D SLAM + Nav2 design](G1_2D_SLAM_Nav2_Architecture.md)
- [Official SLAM comparison](G1_vs_Official_SLAM_Comparison.md)

## PTL Quick Start

在 PTL 上執行以下流程。需要外網時，請在目前 shell 設定公司核准的 proxy；不要把 proxy 位址寫入 repository。

```bash
ssh <user>@<ptl-host>
cd ~/projects
git clone https://github.com/yanghc18/G1-Official-SLAM-Indoor-Navigation.git
cd G1-Official-SLAM-Indoor-Navigation

# 使用連接 G1 Unitree 網段的實際介面
export UNITREE_NETWORK_INTERFACE=<unitree-network-interface>
export ROS_DOMAIN_ID=0

# 建立官方 SLAM image
docker compose -f docker/compose.yaml build
```

### Read-only Verification

在啟動建圖前，先確認官方 image 與 G1 topics：

```bash
docker compose -f docker/compose.yaml run --rm g1-official-slam \
	bash -lc 'ros2 topic list | grep -E "utlidar|imu|odom|slam|qt|lio"'

docker compose -f docker/compose.yaml run --rm g1-official-slam \
	bash -lc 'ros2 topic hz /utlidar/cloud_livox_mid360 --window 5'
```

預期 Mid-360 cloud 約為 10 Hz。確認 topic、時間戳與頻率正常後，再啟動官方 demo：

```bash
docker compose -f docker/compose.yaml run --rm g1-official-slam \
	/opt/src/unitree_slam/build/demo_mid360 "$UNITREE_NETWORK_INTERFACE"
```

第一次啟動只確認程式正常，不要立即按建圖或導航按鍵。實機安全確認後才使用官方 demo 顯示的按鍵操作。

## Verified PTL Baseline

目前已驗證：

- PTL 為 Ubuntu 24.04、x86_64。
- `enp2s0` 為 G1 Unitree 網段介面。
- `g1-official-slam:humble` image 已成功建立。
- `unitree_slam` 的 `demo_mid360` 已成功編譯。
- Mid-360 cloud 約為 10 Hz。
- 官方 SLAM topics 可被新 container 看見。

尚未完成：

- 實際按鍵開始建圖。
- 地圖保存與重定位。
- 低速單點導航與多點導航。

## Version Control

- `V0.1/` 為舊版資料，已從 repository 與 history 移除並由 `.gitignore` 忽略。
- PTL 的 build output、rosbag、地圖與本機 proxy 設定不提交到 Git。

## First Milestone

在 PTL/G1 上完成以下驗證：

1. 確認 Mid-360、IMU、odometry 與 SLAM topics。
2. 編譯並執行官方 `demo_mid360`。
3. 完成一次室內建圖並保存地圖。
4. 載入地圖並完成重定位。
5. 完成低速單點導航。
6. 驗證暫停、恢復與停止流程。

## Repository Policy

本 repository 保存原始碼、設定、腳本、文件與測試紀錄。ROS2 build output、rosbag、地圖與本機 secrets 不提交到 Git。

實機測試應記錄：

- G1 firmware version
- `unitree_slam` commit
- `unitree_sdk2` commit
- ROS2/DDS environment
- network interface
- 測試結果與錯誤訊息
