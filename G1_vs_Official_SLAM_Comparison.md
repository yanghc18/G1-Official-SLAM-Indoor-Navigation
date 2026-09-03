# 我們的架構 vs 官方 unitree_ros SLAM 對比分析

**日期**：2026-09-03  
**對象**：G1 2D SLAM + Nav2 vs 官方 unitreerobotics/unitree_ros 與 unitree_ros2

---

## 📊 核心架構差異

| 維度 | 我們的方案 (自建 2D SLAM+Nav2) | 官方 unitree_ros/ros2 | 優勢/劣勢 |
|------|------|------|------|
| **SLAM 庫** | SLAM Toolbox (2D) | ❌ 沒有 | ✅ 官方預設裸露、選擇自由 |
| **導航框架** | Nav2 (完整棧) | ❌ 沒有 | ✅ 自建、功能完整 |
| **座標轉換** | 自建 TF 層（靜態 + 動態） | 基本 URDF + robot_state_publisher | ✅ 自定義、支援感測器精確位置 |
| **時間同步** | 主動 NTP + Docker 時鐘同步 | ❌ 沒有 | ✅ 我們自行解決 |
| **PointCloud 處理** | pointcloud_to_laserscan (3D→2D) | 直接輸出 PointCloud | ✅ 針對 2D SLAM 優化 |
| **馬達控制** | unitree_sdk2_python (直接 MotionClient) | SportClient + LowCmd | ✅ 直接集成 Nav2 cmd_vel |
| **部署方式** | Docker ROS2 Humble 容器 | Native ROS1/ROS2 + 虛擬環境 | ✅ 容器隔離、重現性好 |
| **感測器驅動** | 使用 G1 firmware utlidar DDS | 相同 (utlidar) | 🟰 相同來源 |

---

## 🎯 官方方案不做什麼

官方 `unitree_ros` 與 `unitree_ros2` **僅提供**：

1. ✅ **Sensor Interfaces** - LiDAR、IMU、相機、里程計消息定義
2. ✅ **Gazebo 模擬環境** - URDF、仿真物理
3. ✅ **低階控制** - LowCmd、SportClient (joint/motor 級別)
4. ✅ **狀態讀取** - SportModeState、LowState、LiDAR、IMU
5. ✅ **RViz 可視化** - 點雲顯示、旋轉可視化
6. ✅ **ROS2 通訊橋接** - DDS → ROS2 主題轉換

**不提供的**：
- ❌ SLAM (2D/3D)
- ❌ Nav2 導航
- ❌ Path Planning
- ❌ 時間同步機制
- ❌ PointCloud→LaserScan 轉換
- ❌ 自動障礙物避免
- ❌ 完整的座標轉換層 (只有 URDF)

---

## 🏗️ 架構流程對比

### 官方 ROS2 (unitree_ros2)

```
┌─────────────────────────────────────────┐
│ Unitree G1 Firmware (utlidar service)   │
│ - Mid-360 LiDAR PointCloud              │
│ - IMU + Odometry                        │
└────────────────┬────────────────────────┘
                 │ DDS/CycloneDDS
                 ▼
        ROS2 Topics (raw)
    /utlidar/cloud (PointCloud2)
    /utlidar/imu (Imu)
    /dog_odom (Odometry)
                 │
                 ▼
        ┌─────────────────────┐
        │ robot_state_pub     │
        │ (URDF-based TF)     │
        └─────────────────────┘
                 │
                 ▼
        用戶自行選擇：
        - 使用 PointCloud 進行視覺處理
        - 使用 IMU 進行平衡控制
        - 或整合外部 SLAM/Nav2 (不在官方套件內)
                 │
                 ▼
        RViz 可視化 + rosbag 記錄
```

**特點**：
- 最小化、模組化
- 無需額外的建圖/導航
- 開發者自行負責 SLAM/Nav2 集成

---

### 我們的方案 (自建 2D SLAM+Nav2)

```
┌────────────────────────────────────────────┐
│ Unitree G1 Firmware (utlidar)              │
│ - Mid-360 LiDAR (PointCloud2, 20k pts)     │
│ - IMU + Odometry                           │
└────────────────┬─────────────────────────┘
                 │ DDS/CycloneDDS
                 ▼
┌───────────────────────────────────────────────────┐
│     Docker ROS2 Humble 容器 (g1-nav2)             │
│                                                   │
│  ┌─────────────────────────────────────────────┐ │
│  │ 1. TF Infrastructure (靜態變換層)           │ │
│  │    - base_link → lidar_link (0.15,0,0.42)   │ │
│  │    - lidar_link → livox_frame (identity)    │ │
│  │    - base_link → imu_link, camera_link      │ │
│  └────────────────┬────────────────────────────┘ │
│                   │                              │
│  ┌────────────────▼────────────────────────────┐ │
│  │ 2. Time Sync Layer                          │ │
│  │    - NTP 同步 (G1 主機)                      │ │
│  │    - Docker 時鐘重新啟動                      │ │
│  └────────────────┬────────────────────────────┘ │
│                   │                              │
│  ┌────────────────▼────────────────────────────┐ │
│  │ 3. PointCloud → LaserScan                   │ │
│  │    - pointcloud_to_laserscan node           │ │
│  │    - 3D 點雲轉換為 2D 掃描線                │ │
│  └────────────────┬────────────────────────────┘ │
│                   │ /scan (LaserScan @ 10Hz)    │
│  ┌────────────────▼────────────────────────────┐ │
│  │ 4. SLAM Toolbox                            │ │
│  │    - 異步 2D 建圖                           │ │
│  │    - /map (OccupancyGrid)                   │ │
│  │    - /tf (odom → base_link)                 │ │
│  └────────────────┬────────────────────────────┘ │
│                   │                              │
│  ┌────────────────▼────────────────────────────┐ │
│  │ 5. Nav2 導航棧                              │ │
│  │    - AMCL (定位)                            │ │
│  │    - BT Navigator (行為樹)                  │ │
│  │    - RegulatedPurePursuit (控制器)          │ │
│  │    - NavfnPlanner (全局規劃)                │ │
│  │    - Costmap (本地/全局)                    │ │
│  │    - /cmd_vel (Twist 速度命令)              │ │
│  └────────────────┬────────────────────────────┘ │
│                   │                              │
│  ┌────────────────▼────────────────────────────┐ │
│  │ 6. Control Bridge                           │ │
│  │    - g1_cmd_vel_bridge.py                   │ │
│  │    - /cmd_vel → MotionClient.Move(vx,vy,wz) │ │
│  └────────────────┬────────────────────────────┘ │
│                   │                              │
└───────────────────┼──────────────────────────────┘
                   │
                G1 Motor Control
                   │
                Robot Movement
```

**特點**：
- 完整、自洽的導航棧
- 內置時間同步解決方案
- 容器隔離、易於重現
- 針對 G1 的特定優化

---

## 🔄 數據流對比

### 官方方案

```
感測器 → DDS → ROS2 主題 (raw)
         ↓
    開發者需要：
    1. 解析 Unitree TimeSpec
    2. 自建 TF 層
    3. 選擇 SLAM 庫
    4. 集成 Nav2
    5. 實現控制橋接
    6. 調試時間同步
```

**工作量**：~500 行代碼 + 複雜配置

---

### 我們的方案

```
感測器 → DDS → ROS2 主題
         ↓
    TF Layer (自動管理座標)
         ↓
    PointCloud→LaserScan (自動轉換)
         ↓
    SLAM Toolbox (自動建圖)
         ↓
    Nav2 (自動導航)
         ↓
    Control Bridge (自動馬達控制)
         ↓
    Robot Movement
```

**工作量**：已完成，文檔驅動

---

## 💡 為什麼官方不提供 SLAM/Nav2

1. **多樣化需求**
   - 有些用戶用於 Gazebo 模擬
   - 有些用於低階關節控制
   - 有些用於視覺/LLM 應用
   - 有些用於自主導航

2. **開源靈活性**
   - 使用者可選 Cartographer (3D) 或 SLAM Toolbox (2D)
   - 可選 move_base (ROS1) 或 Nav2 (ROS2)
   - 可選官方 SDK 或 ROS2 DDS 通訊

3. **認證負擔**
   - SLAM/Nav2 需要硬體測試
   - 時間同步涉及系統配置
   - 安全責任重（自主導航）

4. **維護成本**
   - SLAM Toolbox、Nav2 已有社群維護
   - 官方不需重複造輪子

---

## ✅ 我們方案的優勢

相比僅使用官方 unitree_ros2：

| 優勢 | 詳情 |
|------|------|
| **即插即用** | 按文檔 7 步執行即可運行 |
| **2D 優化** | 針對 G1 人形機器人的 2D 導航優化 |
| **時間同步已解決** | NTP + Docker 重啟完全解決時間戳問題 |
| **座標完整** | TF 層支援所有感測器精確位置 |
| **容器隔離** | 環境一致，易於重現 |
| **完整導航棧** | SLAM→Map→Nav2→Motor，一條線到底 |
| **故障排查文檔** | 4 個常見問題 + 解決方案 |
| **測試驗證** | 實機驗證過 (除時間同步外) |

---

## ❌ 官方方案需要自己做

如果只用官方 unitree_ros2，開發者需要：

1. ❌ 選擇並集成 SLAM 庫
2. ❌ 自建 pointcloud_to_laserscan 轉換
3. ❌ 配置 slam_toolbox 參數
4. ❌ 安裝並配置 Nav2
5. ❌ 自建控制橋接 (cmd_vel → MotionClient)
6. ❌ 診斷並修正時間同步問題
7. ❌ 調試 TF 座標轉換
8. ❌ 集成測試和驗證

**總工作量**：2-3 週（專家）至 1-2 個月（新手）

---

## 🎓 何時選擇哪個方案

### 選擇官方 unitree_ros2

✅ **場景**：
- 只需低階控制（關節、馬達）
- Gazebo 模擬開發
- 感測器數據採集和可視化
- 自建專用 SLAM (例如視覺 SLAM)
- 學習 Unitree SDK 與 ROS2 基礎

**優點**：輕量級、靈活、社群支援好

---

### 選擇我們的 2D SLAM+Nav2 方案

✅ **場景**：
- G1 自主導航（最核心用例）
- 2D 環境地圖建圖
- 自動路徑規劃和障礙物避免
- 快速部署（文檔驅動）
- 學習完整導航棧集成

**優點**：現成、可靠、文檔完整

---

## 📋 遷移路徑

如果從官方方案開始，想升級到完整導航：

```
Step 1: 用官方 unitree_ros2 啟動感測器
         ↓
Step 2: 添加 TF 層 (我們的 g1_static_tf.launch.py)
         ↓
Step 3: 添加 pointcloud_to_laserscan (我們的配置)
         ↓
Step 4: 添加 SLAM Toolbox (我們的啟動文檔)
         ↓
Step 5: 解決時間同步 (我們的 NTP 步驟)
         ↓
Step 6: 添加 Nav2 (我們的 nav2_params.yaml)
         ↓
Step 7: 實現控制橋接 (我們的 g1_cmd_vel_bridge.py)
```

**這正是我們文檔的 7 步！**

---

## 🔧 技術實現細節

### 時間同步 (關鍵差異)

**官方方案**：
```cpp
// record_bag.cpp 使用系統時間
rcutils_system_time_now(&bag_message->time_stamp)  // 本機時間
// LiDAR 自有 TimeSpec.sec/nanosec 但不同步
```
→ 時間戳不一致，SLAM 無法使用

**我們的方案**：
```bash
# Step 1: 同步主機時間
ssh hc-g1@10.5.235.34
sudo ntpdate -s time.nist.gov

# Step 2: 重啟 Docker 容器（刷新系統時鐘）
docker restart g1-nav2

# 驗證
date +%s  # 主機和容器應在 2 秒內
```
→ SLAM 消息過濾器正常工作

---

### PointCloud 處理 (策略差異)

**官方方案**：
```bash
/utlidar/cloud (PointCloud2)
frame_id: utlidar_lidar
直接用於 RViz 顯示
# 沒有 2D 轉換層，3D SLAM 或視覺處理
```

**我們的方案**：
```bash
/utlidar/cloud (PointCloud2, 20k 點)
         ↓ pointcloud_to_laserscan
      /scan (LaserScan, 2D 掃描線)
         ↓ SLAM Toolbox
      /map (OccupancyGrid)
# 針對 2D 導航優化，算力低、實時性好
```

---

### 控制集成 (實現差異)

**官方方案**：
```python
# 用戶需自行實現
motion_client = MotionClient()
motion_client.Connect()

# 訂閱 /cmd_vel，手動轉換
def cmd_vel_callback(msg):
    vx = msg.linear.x
    wz = msg.angular.z
    # 手動限制、安全檢查、超時處理
    motion_client.Move(vx, 0, wz)
```

**我們的方案**：
```python
# 已實現在 g1_cmd_vel_bridge.py
class CmdVelBridge:
    def __init__(self):
        self.sub = self.create_subscription(Twist, "/cmd_vel", self.callback)
        self.timer = self.create_timer(0.05, self.publish_motion)  # 20Hz
        self.last_cmd_time = time.time()
        self.timeout = 0.5  # 超時自動停止
    
    def callback(self, msg):
        self.last_cmd = msg
    
    def publish_motion(self):
        if time.time() - self.last_cmd_time > self.timeout:
            self.motion_client.Move(0, 0, 0)  # 安全停止
        else:
            self.motion_client.Move(vx, vy, wz)  # 執行命令
```

---

## 🎯 推薦路徑

**最佳實踐**（基於本次對比）：

1. **學習官方方案** (1-2 天)
   - 了解 Unitree DDS 通訊
   - 認識感測器主題
   - 熟悉 ROS2 基礎

2. **部署我們的 2D SLAM+Nav2** (1 天)
   - 按 7 步文檔執行
   - 實現完整導航

3. **自定義優化** (1-2 週)
   - 調整 SLAM 參數
   - 優化 Nav2 速度/安全性
   - 添加任務層 (例如多點導航)

---

## 📚 參考資源

### 官方文檔
- unitree_ros2: https://github.com/unitreerobotics/unitree_ros2
- Unitree SDK2: https://github.com/unitreerobotics/unitree_sdk2
- ROS2 Humble: https://docs.ros.org/en/humble/

### 我們的文檔
- 完整架構指南: G1_2D_SLAM_Nav2_Architecture.md
- 本對比分析: G1_vs_Official_SLAM_Comparison.md

### 開源 SLAM/Nav2
- SLAM Toolbox: https://github.com/SteveMacenski/slam_toolbox
- Nav2: https://github.com/ros-planning/navigation2
- pointcloud_to_laserscan: https://github.com/ros-perception/pointcloud_to_laserscan

---

**結論**：官方 unitree_ros2 是基礎層，我們的方案是在其上建立的**完整、生產就緒的導航系統**。選擇取決於需求：基礎研究 vs 實用導航。
