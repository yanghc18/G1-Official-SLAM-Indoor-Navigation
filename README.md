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
