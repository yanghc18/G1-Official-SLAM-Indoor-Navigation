# G1 官方 SLAM 室內導航方案

**日期**：2026-09-03  
**目標**：使用 Unitree 官方 SLAM interface，在 G1 + Mid-360 上完成室內建圖、重定位與導航  
**策略**：先使用 G1 韌體內建 SLAM，不先導入 `slam_toolbox` 或 Nav2

---

## 1. 官方 Source

### 主要 Repository

- [unitreerobotics/unitree_slam](https://github.com/unitreerobotics/unitree_slam)
- [unitreerobotics/unitree_sdk2](https://github.com/unitreerobotics/unitree_sdk2)
- [unitreerobotics/unitree_ros2](https://github.com/unitreerobotics/unitree_ros2)
- [unitreerobotics/Python_unitree_demos](https://github.com/unitreerobotics/Python_unitree_demos)

### Source 責任範圍

```text
unitree_slam
  官方 DDS message、SLAM command、建圖/導航範例

unitree_sdk2
  Unitree DDS/RPC client 與通訊底層

unitree_ros2
  ROS2 message、CycloneDDS 與 Unitree ROS2 基礎介面

G1 韌體
  真正的 SLAM 演算法、定位、地圖處理與機器人導航執行
```

`unitree_slam` 是官方 interface/example，不是 SLAM 演算法本身的開源實作。

---

## 2. 目標架構

```text
                  G1 Robot
┌─────────────────────────────────────────────┐
│ Unitree Firmware                             │
│                                             │
│ Mid-360 LiDAR + IMU + locomotion odometry  │
│                                             │
│ Internal SLAM / Localization / Navigation   │
└──────────────────────┬──────────────────────┘
                       │ Unitree DDS
                       │
        ┌──────────────▼──────────────┐
        │ unitree_slam C++ interface   │
        │ unitree_sdk2 Channel API     │
        └──────────────┬──────────────┘
                       │
        ┌──────────────▼──────────────┐
        │ G1 SLAM operator             │
        │ - start mapping              │
        │ - save map                   │
        │ - relocation                 │
        │ - navigate to pose           │
        │ - pause/resume/stop          │
        └──────────────┬──────────────┘
                       │
              Robot moves indoors
```

本方案不使用以下自建 pipeline：

```text
PointCloud2 -> LaserScan -> slam_toolbox -> Nav2 -> cmd_vel bridge
```

這條 pipeline 保留作為後備方案，只有在官方 SLAM 不支援目前 G1 韌體或功能不足時才啟用。

---

## 3. 官方介面與資料流

`unitree_slam` 的 Mid-360 範例使用下列 topics：

```text
rt/qt_command
rt/qt_notice
rt/lio_sam_ros2/mapping/re_location_odometry
rt/qt_add_node
rt/qt_add_edge
```

常見功能：

| 功能 | 說明 |
|---|---|
| Start mapping | 開始室內建圖 |
| End mapping | 結束建圖並保存地圖 |
| Start relocation | 載入地圖並開始重定位 |
| Init pose | 設定初始位置 |
| Start navigation | 啟動導航模式 |
| Add node/edge | 建立導航圖節點與連線 |
| Save node/edge | 保存導航圖 |
| Pause navigation | 暫停導航 |
| Recover navigation | 恢復導航 |
| Close all nodes | 關閉導航節點 |
| Delete nodes/edges | 清除導航圖資料 |

實際 topic 是否帶有 `/` 前綴，必須以 G1 現場的 `ros2 topic list` 為準。

---

## 4. 前置條件

### 硬體

- Unitree G1
- G1 內建或連接的 Mid-360 LiDAR
- G1 韌體已啟用 SLAM service
- 測試用室內環境
- 可連接 G1 的 Ubuntu 22.04 電腦或 G1 onboard computer

### 軟體

- Ubuntu 22.04
- ROS2 Humble 或官方環境相容版本
- CycloneDDS
- C++17 compiler
- CMake 3.16+
- `unitree_sdk2`
- `unitree_slam`

### 網路

- 開發機與 G1 位於同一個 Unitree 網段
- 使用正確網路介面，例如 `eth0`、`enp0s3` 或實際介面名稱
- 不要同時啟用會攔截 DDS 的 VPN、代理或其他 ROS domain

---

## 5. 下載官方 source

```bash
cd ~/src

git clone https://github.com/unitreerobotics/unitree_sdk2.git
git clone https://github.com/unitreerobotics/unitree_slam.git
git clone https://github.com/unitreerobotics/unitree_ros2.git
```

查看官方 Mid-360 範例：

```bash
cd ~/src/unitree_slam
sed -n '1,220p' unitree_slam_example/demo_mid360.cpp
```

優先研究這些檔案：

```text
unitree_slam_example/demo_mid360.cpp
unitree_slam_example/start_mapping.cpp
unitree_slam_example/end_mapping.cpp
unitree_slam_example/start_relocation.cpp
unitree_slam_example/start_nav.cpp
unitree_slam_example/multiple_nav_set.cpp
unitree_slam_example/pause_nav.cpp
unitree_slam_example/recover_nav.cpp
```

---

## 6. 編譯官方 SLAM interface

```bash
cd ~/src/unitree_slam
mkdir -p build
cd build
cmake ..
make -j$(nproc)
```

設定官方附帶的 library：

```bash
export LD_LIBRARY_PATH="$PWD/../unitree_robotics/lib/$(uname -m):$LD_LIBRARY_PATH"
```

確認執行檔：

```bash
find . -maxdepth 1 -type f -executable -print
```

官方 README 的基本執行方式：

```bash
./demo_mid360 <network-interface>
```

例如：

```bash
./demo_mid360 eth0
```

注意：`eth0` 只是範例，必須替換成實際連接 G1 的網路介面。

---

## 7. 第一步：確認 G1 DDS 通訊

先不要啟動 SLAM 操作，確認網路與 topics：

```bash
source /opt/ros/humble/setup.bash
source ~/unitree_ros2/setup.sh

ros2 topic list
```

確認至少能看到相關資料：

```bash
ros2 topic list | grep -E 'utlidar|imu|odom|slam|qt|lio'
```

確認 Mid-360：

```bash
ros2 topic echo /utlidar/cloud_livox_mid360 --once
ros2 topic echo /utlidar/imu_livox_mid360 --once
```

確認里程計：

```bash
ros2 topic echo /dog_odom --once
```

確認官方 SLAM topics：

```bash
ros2 topic list | grep -E 'slam|qt|lio_sam'
```

若完全沒有 `slam` 或 `qt` 相關 topic，先不要進行建圖，應先確認 G1 韌體版本與 SLAM service 是否啟用。

---

## 8. 第二步：時間與 DDS 檢查

官方 SLAM interface 依賴 DDS 時序與 G1 韌體服務。先檢查主機和 G1 時間：

```bash
date +%s
```

若 LiDAR 或 SLAM topic 的時間戳和系統時間差距很大，先同步時間，再重啟相關容器或 SLAM service。

G1 主機上的範例：

```bash
sudo ntpdate -s time.nist.gov
```

如果 SLAM 在 Docker 中執行，重啟容器後再次確認：

```bash
docker restart g1-nav2
```

檢查 DDS 網路介面：

```bash
ip addr
```

確認 `unitree_ros2/setup.sh` 或 CycloneDDS 設定使用正確介面。不要在同一時間混用錯誤的 `RMW_IMPLEMENTATION` 或錯誤的 ROS domain。

---

## 9. 第三步：啟動官方 Mid-360 範例

```bash
cd ~/src/unitree_slam/build
export LD_LIBRARY_PATH="$PWD/../unitree_robotics/lib/$(uname -m):$LD_LIBRARY_PATH"
./demo_mid360 <network-interface>
```

例如：

```bash
./demo_mid360 enp3s0
```

程式通常以鍵盤操作：

```text
q  關閉 ROS node
w  開始建圖
 e  結束建圖
 a  開始導航
 s  暫停導航
 d  恢復導航
 z  重定位並初始化 pose
 x  增加 node/edge
 c  保存 node/edge
 v  刪除 node/edge
```

實際按鍵請以目前 checkout 的 `demo_mid360.cpp` 顯示為準。

---

## 10. 室內建圖流程

### 10.1 建圖前

1. 清空室內測試區域中的不必要障礙物。
2. 確認 G1 可以安全站立和低速行走。
3. 確認 Mid-360 topic 持續發布。
4. 確認 odometry topic 持續發布。
5. 確認時間戳沒有倒退或長時間跳動。
6. 確認網路線與電源穩定。

### 10.2 開始建圖

執行：

```text
w
```

讓 G1 以低速在室內移動，建議依序經過：

```text
起點 -> 走廊 -> 房間入口 -> 房間內部 -> 另一條走廊 -> 回到起點附近
```

建圖時避免：

- 快速旋轉
- 長時間遮擋 LiDAR
- 經過大量玻璃或完全無特徵牆面
- 讓人員近距離持續遮住 LiDAR
- 在定位尚未穩定時快速行走

### 10.3 結束並保存

執行：

```text
e
```

官方範例會根據 Unitree SLAM interface 保存地圖或導航圖資料。保存位置與格式必須以 `end_mapping.cpp` 和 G1 韌體回覆為準，不要預設一定是 ROS2 的 `.yaml + .pgm`。

---

## 11. 重定位流程

1. 將 G1 放到已建圖環境中的已知位置附近。
2. 載入保存的地圖。
3. 執行重定位：

```text
z
```

4. 觀察 `rt/qt_notice` 或對應 topic。
5. 確認位置不再持續跳動。
6. 確認 G1 朝向與實際方向一致。

如果官方介面需要明確初始 pose，使用官方的 `pose_init` 或 `start_relocation` 範例，不要直接套用 ROS2 AMCL 的 `/initialpose`，兩者不是同一個協定。

---

## 12. 導航流程

### 12.1 基本導航

先使用官方單點導航範例：

```bash
./start_nav <network-interface>
```

或：

```bash
./single_nav <network-interface>
```

實際執行檔名稱以 `build` 目錄為準。

### 12.2 節點式導航

官方範例支援建立 node 和 edge：

```text
x  增加節點或邊
c  保存節點與邊
v  刪除節點與邊
```

建議先在小型測試區建立 3 個點：

```text
Node A: 起點
Node B: 走廊轉角
Node C: 房間入口
```

然後建立：

```text
A -> B
B -> C
C -> A
```

確認單點導航穩定後，再測試多點導航。

### 12.3 暫停與恢復

```text
s  暫停
 d  恢復
```

停止或異常時優先使用官方停止/關閉 node 功能，不要直接關閉電源。

---

## 13. ROS2 整合策略

第一階段不要求 Nav2。先讓官方 SLAM 完成：

```text
建圖 -> 保存 -> 重定位 -> 單點導航 -> 多點導航
```

第二階段才考慮建立 ROS2 adapter：

```text
Unitree SLAM DDS
       |
       v
ROS2 adapter
       |
       +--> nav_msgs/Odometry
       +--> geometry_msgs/Pose
       +--> visualization topics
       +--> optional Nav2 action adapter
```

只有在確定官方導航 API 不足時，才接入 Nav2：

```text
Nav2 NavigateToPose
       |
       v
Pose adapter
       |
       v
Unitree official navigation API
```

不建議第一階段把 Nav2 的 `/cmd_vel` 直接送入 G1。官方 SLAM/navigation service 可能需要自己的動作狀態、速度限制、導航圖和安全邏輯。

---

## 14. G1 相容性檢查

官方 repository 有 `demo_mid360.cpp`，但目前沒有明確命名為 `demo_g1.cpp`。因此必須確認：

| 檢查項目 | 結果 |
|---|---|
| G1 是否發布 Mid-360 cloud | 待現場確認 |
| G1 是否發布官方 SLAM topics | 待現場確認 |
| `demo_mid360` 是否能建立 DDS channel | 待現場確認 |
| `w` 是否成功開始建圖 | 待現場確認 |
| `e` 是否成功保存地圖 | 待現場確認 |
| `z` 是否成功重定位 | 待現場確認 |
| 單點導航是否成功 | 待現場確認 |
| 多點導航是否成功 | 待現場確認 |

不要因為能看到 `/utlidar/cloud_livox_mid360` 就假設官方 SLAM 一定可用；SLAM service 仍可能受韌體版本、機型設定和授權狀態影響。

---

## 15. 安全測試順序

```text
1. 只讀取 topics
2. 執行官方範例但不移動
3. 確認建圖 service 可啟動
4. 手動低速移動建圖
5. 保存地圖
6. 靜止測試重定位
7. 低速單點導航
8. 測試暫停/恢復
9. 測試多點導航
10. 才考慮 ROS2 adapter 或 Nav2
```

實機測試時：

- 保持急停或遙控器可用。
- 第一次導航使用空曠區域和極短距離。
- 不要直接使用高速度參數。
- 任何定位跳動、碰撞風險或 DDS 錯誤都立即停止。
- 不要同時啟動官方導航和自建 `cmd_vel` bridge。

---

## 16. 驗收標準

| 階段 | 通過條件 |
|---|---|
| DDS | 能穩定看到 Mid-360、IMU、odometry topics |
| SLAM service | 官方範例能成功初始化 |
| Mapping | G1 移動時沒有持續定位失敗或 service error |
| Map save | 建圖能成功結束並產生可重用地圖 |
| Relocation | 在已知位置能重新取得穩定 pose |
| Single navigation | G1 能到達指定室內目標點 |
| Pause/resume | 導航可安全暫停並恢復 |
| Multi-point | G1 能依序通過多個目標點 |
| Recovery | 導航失敗後能使用官方 recovery/stop 流程 |
| ROS integration | 需要時才加入 ROS2 standard topic/action adapter |

---

## 17. 常見問題

### 沒有 SLAM topics

確認：

```bash
ros2 topic list | grep -E 'slam|qt|lio_sam'
```

可能原因：

- G1 韌體沒有啟用 SLAM service。
- 使用錯誤的網路介面。
- DDS domain 或 CycloneDDS 設定錯誤。
- G1 韌體版本不支援目前 interface。

### 官方範例能編譯但無法連線

確認：

```bash
ip addr
printenv | grep -E 'RMW|CYCLONE|ROS_DOMAIN'
```

重新設定正確的 Unitree 網段與 CycloneDDS 介面。

### 建圖開始但沒有有效地圖

確認：

- Mid-360 cloud 持續發布。
- odometry 持續發布。
- G1 沒有被快速旋轉或劇烈晃動。
- LiDAR 沒被身體、衣物或人員遮擋。
- 時間戳沒有與系統時間嚴重偏離。

### 導航目標無法到達

確認：

- 已完成保存地圖或導航圖。
- G1 已成功重定位。
- 目標點位於地圖可通行區域。
- 目標點格式和座標系統符合官方 API。
- 未同時啟動另一套速度控制器。

### 想直接使用 Nav2

先完成官方 SLAM 的建圖、重定位與導航驗證，再設計 adapter。不要在官方導航尚未確認前，同時維護兩套定位和運動控制系統。

---

## 18. 第一輪實作清單

```text
[ ] clone unitree_sdk2
[ ] clone unitree_slam
[ ] build unitree_slam
[ ] 找出 G1 實際網路介面
[ ] 確認 /utlidar/cloud_livox_mid360
[ ] 確認 /utlidar/imu_livox_mid360
[ ] 確認 /dog_odom
[ ] 確認 slam/qt/lio_sam topics
[ ] 執行 demo_mid360
[ ] 測試 start mapping
[ ] 測試 end mapping
[ ] 確認地圖保存位置與格式
[ ] 測試 relocation
[ ] 測試 single navigation
[ ] 測試 pause/resume
[ ] 測試 multiple navigation
[ ] 記錄韌體版本、SDK commit 與測試結果
```

---

## 結論

目前最合理的 G1 室內導航起點是：

```text
unitree_slam + unitree_sdk2 + G1 內建 SLAM service
```

先驗證官方 `demo_mid360` 在 G1 上是否可用。若建圖、重定位和導航均成功，就不需要自行維護 `slam_toolbox`、AMCL、Nav2 controller 或 `cmd_vel` motor bridge。只有在官方介面無法滿足 ROS2 標準整合需求時，才增加一個薄的 ROS2 adapter。
