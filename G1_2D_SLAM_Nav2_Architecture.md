# G1 2D SLAM + Nav2 導航架構完整指南

**最後更新**：2026-09-03  
**狀態**：實驗驗證中（時間同步待修正）  
**目標**：實現 G1 基於 2D LiDAR 的自主導航

---

## 📐 架構概覽

```
┌─────────────────────────────────────────────────────────────────┐
│                        G1 Humanoid Robot                         │
│                                                                   │
│  ┌──────────────────┐    ┌─────────────┐    ┌──────────────┐   │
│  │  Mid-360 LiDAR   │    │  IMU (in    │    │   Odometry   │   │
│  │  (native time)   │    │  Mid-360)   │    │  (firmware)  │   │
│  └────────┬─────────┘    └──────┬──────┘    └──────┬───────┘   │
│           │                     │                  │            │
│           └─────────────────────┴──────────────────┘            │
│                        │                                         │
│                G1 Firmware Bridge (utlidar)                      │
│                        │                                         │
└────────────────────────┼─────────────────────────────────────────┘
                         │
                  DDS/CycloneDDS
                    (ROS2 middleware)
                         │
        ┌────────────────┴────────────────┬──────────────┐
        │                                 │              │
   ┌────▼─────────┐           ┌──────────▼──┐    ┌─────▼────┐
   │   Docker     │           │   Docker    │    │ G1 Firmware
   │  Container   │           │  Container  │    │
   │ (ROS2 Humble)│           │   (NAV2)    │    │
   └────┬─────────┘           └─────────────┘    └────┬─────┘
        │                                             │
        │  PointCloud2 (/utlidar/cloud_livox_mid360) │
        │  IMU (/utlidar/imu_livox_mid360)           │
        │  Odom (/dog_odom)                          │
        └─────────────┬──────────────────────────────┘
                      │
        ┌─────────────▼──────────────┐
        │  pointcloud_to_laserscan   │
        │  (PointCloud2 → LaserScan) │
        └─────────────┬──────────────┘
                      │ /scan (LaserScan)
        ┌─────────────▼──────────────┐
        │    slam_toolbox            │
        │  (2D SLAM Mapping)         │
        └─────────────┬──────────────┘
                      │ /map
        ┌─────────────▼──────────────┐
        │      Nav2                  │
        │  (Path Planning & Control) │
        └─────────────┬──────────────┘
                      │ /cmd_vel
        ┌─────────────▼──────────────┐
        │  unitree_sdk2_python       │
        │ (cmd_vel → LocoClient API) │
        └────────────────────────────┘
                      │
                G1 Motor Control
```

---

## 🔧 系統架構組件

| 組件 | 功能 | 數據格式 | 頻率 |
|------|------|--------|------|
| **G1 Firmware utlidar** | 感測器讀取、時間戳生成 | PointCloud2, Imu | 10 Hz |
| **pointcloud_to_laserscan** | 3D → 2D 點雲轉換 | LaserScan | 10 Hz |
| **slam_toolbox** | 2D SLAM 建圖與定位 | OccupancyGrid, TF | 5-10 Hz |
| **Nav2** | 路徑規劃、障礙物避免、速度控制 | Path, Twist | 20 Hz |
| **unitree_sdk2_python** | 機器人運動控制 | MotionCommand | 20 Hz |

---

## 📋 前置要求

- **硬體**：Unitree G1 + Intel PTL (可選)
- **系統**：Ubuntu 22.04 LTS
- **容器**：Docker with `g1-nav2` image
- **ROS2**：Humble (Docker 內)
- **Python**：3.10+

---

## 🚀 逐步部署指南

### **第 1 步：系統時間同步**

**問題**：LiDAR 時間戳與系統時間差異 ~1734 秒，導致 SLAM 過濾消息

**解決方案**：

#### 在 G1 主機上
```bash
# SSH 連到 G1
ssh hc-g1@10.5.235.34

# 檢查當前時間
date
timedatectl

# 同步時間（使用 NTP）
sudo timedatectl set-timezone UTC
sudo ntpdate -s time.nist.gov
# 或使用 Intel 內部 NTP
sudo ntpdate -s time.intel.com

# 驗證同步
date +%s
```

#### 重啟 Docker 容器
```bash
# 重啟容器使時間生效
docker stop g1-nav2
docker start g1-nav2

# 驗證容器內時間
docker exec -it g1-nav2 bash -c 'date +%s'
```

**驗收標準**：
- 主機和容器的 `date +%s` 輸出相差 < 2 秒
- SLAM 日誌不再出現 "timestamp earlier than cache" 警告

---

### **第 2 步：啟動基礎設施（TF + 時間對齊）**

#### 進入 Docker 容器
```bash
docker exec -it g1-nav2 bash
cd /root/ws
source install/setup.bash
```

#### 啟動靜態 TF 發布
```bash
# 在後台啟動 TF launch
ros2 launch launch/g1_static_tf.launch.py &

# 驗證 TF 發布
sleep 2
ros2 topic echo /tf_static --once
```

**期望輸出**：
- 4 個 TF 轉換（base_link → lidar_link, imu_link, camera_link）
- 1 個額外的轉換：lidar_link → livox_frame

---

### **第 3 步：PointCloud2 → LaserScan 轉換**

#### 安裝 pointcloud_to_laserscan
```bash
apt-get update
apt-get install -y ros-humble-pointcloud-to-laserscan
```

#### 啟動轉換節點
```bash
ros2 run pointcloud_to_laserscan pointcloud_to_laserscan_node \
  --ros-args \
  -r cloud_in:=/utlidar/cloud_livox_mid360 \
  -r scan:=/scan &
```

#### 驗證 LaserScan 發布
```bash
# 檢查頻率
ros2 topic hz /scan --window 5

# 檢查一個樣本
ros2 topic echo /scan --once | head -20
```

**期望結果**：
- 頻率：~10 Hz
- 數據點：1000+ 點/掃描
- 無 NaN 或無窮值

---

### **第 4 步：啟動 SLAM Toolbox**

#### 安裝 slam_toolbox
```bash
apt-get install -y ros-humble-slam-toolbox
```

#### 啟動 SLAM
```bash
ros2 run slam_toolbox async_slam_toolbox_node \
  --ros-args \
  -p use_sim_time:=false \
  -p map_frame:=map \
  -p odom_frame:=odom \
  -p base_frame:=base_link \
  -p tf_buffer_duration:=10.0 &
```

#### 監控 SLAM 運作
```bash
# 檢查地圖更新
ros2 topic hz /map --window 5

# 查看地圖大小
ros2 topic echo /map --once | head -30

# 檢查 TF 樹（odom → base_link）
ros2 topic echo /tf --once | grep -A 10 'odom'
```

**期望結果**：
- `/map` 以 5-10 Hz 發布
- `/tf` 包含 `odom → base_link` 鏈接
- 地圖從空白逐漸填充點雲數據

---

### **第 5 步：安裝 & 配置 Nav2**

#### 安裝 Nav2
```bash
apt-get install -y ros-humble-nav2-* \
  ros-humble-navigation2
```

#### 創建 Nav2 Launch 文件

**檔案路徑**：`/root/ws/launch/g1_nav2.launch.py`

```python
from launch import LaunchDescription
from launch_ros.actions import Node
from launch.substitutions import LaunchConfiguration
from launch.actions import DeclareLaunchArgument
import os

def generate_launch_description():
    # 配置路徑
    config_dir = os.path.expanduser('~/ws/config')
    nav2_config = os.path.join(config_dir, 'nav2_params.yaml')
    
    return LaunchDescription([
        # 聲明參數
        DeclareLaunchArgument('map_file', default_value=''),
        DeclareLaunchArgument('use_sim_time', default_value='false'),
        
        # Nav2 主程序
        Node(
            package='nav2_bringup',
            executable='bringup_launch.py',
            name='nav2',
            parameters=[
                LaunchConfiguration('nav2_config_file'),
                {'use_sim_time': LaunchConfiguration('use_sim_time')},
            ],
            remappings=[
                ('/map', '/map'),
                ('/scan', '/scan'),
                ('/odom', '/odom'),
            ],
        ),
        
        # RViz 可視化
        Node(
            package='rviz2',
            executable='rviz2',
            name='rviz2',
            arguments=['-d', os.path.join(config_dir, 'rviz_nav2.rviz')],
        ),
    ])
```

#### 創建 Nav2 參數文件

**檔案路徑**：`/root/ws/config/nav2_params.yaml`

```yaml
amcl:
  ros__parameters:
    use_sim_time: false
    alpha1: 0.2
    alpha2: 0.2
    alpha3: 0.2
    alpha4: 0.2
    alpha5: 0.2
    base_frame_id: "base_link"
    beam_search_angle: 0.545
    do_beamskip: false
    global_frame_id: "map"
    lambda_short: 0.1
    laser_likelihood_max_dist: 2.0
    laser_max_range: 100.0
    laser_min_range: 0.1
    max_beams: 60
    max_particles: 2000
    min_particles: 500
    odom_frame_id: "odom"
    pf_err: 0.05
    pf_z: 0.99
    recovery_alpha_fast: 0.0
    recovery_alpha_slow: 0.0
    resample_interval: 1
    robot_model_type: "differential"
    save_pose_rate: 0.5
    sigma_hit: 0.2
    sigma_short: 0.1
    tf_broadcast: true
    transform_tolerance: 1.0
    update_min_a: 0.2
    update_min_d: 0.25
    z_hit: 0.5
    z_max: 0.05
    z_rand: 0.5
    z_short: 0.05

bt_navigator:
  ros__parameters:
    use_sim_time: false
    global_frame: map
    robot_base_frame: base_link
    odom_topic: /odom
    bt_xml_filename: "navigate_w_replanning_and_recovery.xml"
    default_nav_to_pose_bt_xml_filename: "navigate_w_replanning_and_recovery.xml"
    plugin_lib_names:
      - nav2_compute_path_to_pose_action_bt_node
      - nav2_compute_path_through_poses_action_bt_node
      - nav2_smooth_path_action_bt_node
      - nav2_follow_path_action_bt_node
      - nav2_spin_action_bt_node
      - nav2_wait_action_bt_node
      - nav2_assisted_teleop_action_bt_node
      - nav2_back_up_action_bt_node
      - nav2_drive_on_heading_bt_node
      - nav2_clear_costmap_service_bt_node
      - nav2_is_stuck_action_bt_node
      - nav2_planner_selector_bt_node
      - nav2_controller_selector_bt_node
      - nav2_goal_checker_selector_bt_node
      - nav2_controller_cancel_bt_node
      - nav2_planner_cancel_bt_node
      - nav2_reinitialize_global_costmap_bt_node
      - nav2_reinitialize_local_costmap_bt_node

controller_server:
  ros__parameters:
    use_sim_time: false
    controller_frequency: 20.0
    min_x_velocity_threshold: 0.001
    min_y_velocity_threshold: 0.5
    min_theta_velocity_threshold: 0.001
    failure_tolerance: 0.3
    progress_checker_plugin: "progress_checker"
    goal_checker_plugins: ["general_goal_checker"]
    controller_plugins: ["FollowPath"]
    
    progress_checker:
      plugin: "nav2_core::SimpleProgressChecker"
      required_movement_radius: 0.5
      movement_time_allowance: 10.0
    general_goal_checker:
      stateful: true
      plugin: "nav2_core::SimpleGoalChecker"
      xy_goal_tolerance: 0.25
      yaw_goal_tolerance: 0.25
    FollowPath:
      plugin: "nav2_regulated_pure_pursuit_controller::RegulatedPurePursuitController"
      desired_linear_vel: 0.5
      lookahead_dist: 0.6
      min_lookahead_dist: 0.3
      max_lookahead_dist: 0.9
      lookahead_time: 1.5
      rotate_to_heading_angular_vel: 1.8
      transform_tolerance: 0.1
      use_velocity_scaled_lookahead_dist: false
      min_amcl_pose_uncertainty: 0.1
      use_cost_regulated_linear_velocity_scaling: true
      cost_scaling_dist: 0.6
      cost_scaling_gain: 1.0
      inflation_radius: 0.55

planner_server:
  ros__parameters:
    use_sim_time: false
    expected_planner_frequency: 20.0
    planner_plugins: ["GridBased"]
    GridBased:
      plugin: "nav2_navfn_planner::NavfnPlanner"
      tolerance: 0.5
      use_astar: false
      allow_unknown: false

local_costmap:
  local_costmap:
    ros__parameters:
      update_frequency: 5.0
      publish_frequency: 2.0
      global_frame: odom
      robot_base_frame: base_link
      use_sim_time: false
      rolling_window: true
      width: 3
      height: 3
      resolution: 0.05
      robot_radius: 0.22
      plugins: ["obstacle_layer", "inflation_layer"]
      inflation_layer:
        plugin: "nav2_costmap_2d::InflationLayer"
        cost_scaling_factor: 3.0
        inflation_radius: 0.55
      obstacle_layer:
        plugin: "nav2_costmap_2d::ObstacleLayer"
        enabled: true
        observation_sources: scan
        scan:
          topic: /scan
          max_obstacle_height: 2.0
          clearing: true
          marking: true
          data_type: "LaserScan"

global_costmap:
  global_costmap:
    ros__parameters:
      update_frequency: 1.0
      publish_frequency: 1.0
      global_frame: map
      robot_base_frame: base_link
      use_sim_time: false
      robot_radius: 0.22
      resolution: 0.05
      plugins: ["static_layer", "obstacle_layer", "inflation_layer"]
      static_layer:
        plugin: "nav2_costmap_2d::StaticLayer"
        map_subscribe_transient_local: true
      obstacle_layer:
        plugin: "nav2_costmap_2d::ObstacleLayer"
        enabled: true
        observation_sources: scan
        scan:
          topic: /scan
          max_obstacle_height: 2.0
          clearing: true
          marking: true
          data_type: "LaserScan"
      inflation_layer:
        plugin: "nav2_costmap_2d::InflationLayer"
        cost_scaling_factor: 3.0
        inflation_radius: 0.55
```

#### 啟動 Nav2
```bash
# 啟動 Nav2（不含 RViz 先）
ros2 launch nav2_bringup navigation_launch.py \
  use_sim_time:=false \
  map:=  \
  params_file:=/root/ws/config/nav2_params.yaml &

# 檢查節點
ros2 node list | grep nav2
```

**期望結果**：
- Nav2 主要節點啟動（controller_server, planner_server, amcl 等）
- `/cmd_vel` topic 可訂閱

---

### **第 6 步：整合控制層（cmd_vel → 馬達命令）**

#### 選項 A：使用 unitree_sdk2_python（推薦）

**檔案路徑**：`/root/ws/src/g1_locomotion_bridge/g1_cmd_vel_bridge.py`

```python
#!/usr/bin/env python3
"""
G1 cmd_vel to LocoClient Bridge
將 Nav2 的 /cmd_vel 轉換為 G1 馬達命令
"""

import rclpy
from rclpy.node import Node
from geometry_msgs.msg import Twist
from unitree_sdk2py.core.client import Client
from unitree_sdk2py.core.motion.motion_client import MotionClient
from unitree_sdk2py.idl.default import *
import time

class G1CmdVelBridge(Node):
    def __init__(self):
        super().__init__('g1_cmd_vel_bridge')
        
        # 訂閱 cmd_vel
        self.subscription = self.create_subscription(
            Twist,
            '/cmd_vel',
            self.cmd_vel_callback,
            10
        )
        
        # 初始化 Unitree SDK
        self.motion_client = MotionClient()
        self.motion_client.SetTimeout(10)
        
        # 參數
        self.linear_x = 0.0
        self.linear_y = 0.0
        self.angular_z = 0.0
        self.last_cmd_time = time.time()
        
        # 創建計時器（20 Hz 控制迴圈）
        self.timer = self.create_timer(0.05, self.control_loop)
        
        self.get_logger().info('G1 cmd_vel Bridge 啟動')
    
    def cmd_vel_callback(self, msg: Twist):
        """訂閱 cmd_vel 並保存命令"""
        self.linear_x = msg.linear.x
        self.linear_y = msg.linear.y
        self.angular_z = msg.angular.z
        self.last_cmd_time = time.time()
        
        self.get_logger().debug(
            f'cmd_vel: vx={self.linear_x:.2f}, vy={self.linear_y:.2f}, wz={self.angular_z:.2f}'
        )
    
    def control_loop(self):
        """控制迴圈：定期發送馬達命令"""
        # 若超過 0.5 秒未接收命令，停止
        if time.time() - self.last_cmd_time > 0.5:
            self.linear_x = 0.0
            self.linear_y = 0.0
            self.angular_z = 0.0
        
        # 限制速度（G1 安全限制）
        max_linear = 0.5  # m/s
        max_angular = 1.0  # rad/s
        
        vx = max(-max_linear, min(max_linear, self.linear_x))
        vy = max(-max_linear, min(max_linear, self.linear_y))
        wz = max(-max_angular, min(max_angular, self.angular_z))
        
        # 呼叫 Unitree SDK 移動 API
        try:
            # 使用 LocoClient.Move() 或等價 API
            # 這取決於您使用的 unitree_sdk2 版本
            # 簡化示例：
            self.motion_client.Move(vx, vy, wz)
        except Exception as e:
            self.get_logger().error(f'馬達命令發送失敗: {e}')

def main(args=None):
    rclpy.init(args=args)
    bridge = G1CmdVelBridge()
    rclpy.spin(bridge)
    bridge.destroy_node()
    rclpy.shutdown()

if __name__ == '__main__':
    main()
```

#### 啟動控制橋接
```bash
# 安裝依賴
pip install unitree-sdk2

# 啟動橋接節點
python3 /root/ws/src/g1_locomotion_bridge/g1_cmd_vel_bridge.py &
```

**驗收標準**：
- 橋接節點成功訂閱 `/cmd_vel`
- 機器人收到低速指令時（0.03 m/s）開始移動
- 停止 Nav2 後機器人立即停止

---

### **第 7 步：完整系統測試**

#### 啟動完整棧
```bash
# Terminal 1: TF
ros2 launch launch/g1_static_tf.launch.py

# Terminal 2: PointCloud 轉換
ros2 run pointcloud_to_laserscan pointcloud_to_laserscan_node \
  --ros-args -r cloud_in:=/utlidar/cloud_livox_mid360 -r scan:=/scan

# Terminal 3: SLAM
ros2 run slam_toolbox async_slam_toolbox_node --ros-args \
  -p use_sim_time:=false -p map_frame:=map -p odom_frame:=odom \
  -p base_frame:=base_link -p tf_buffer_duration:=10.0

# Terminal 4: Nav2
ros2 launch nav2_bringup navigation_launch.py use_sim_time:=false \
  params_file:=/root/ws/config/nav2_params.yaml

# Terminal 5: 控制橋接
python3 /root/ws/src/g1_locomotion_bridge/g1_cmd_vel_bridge.py

# Terminal 6: RViz
rviz2
```

#### 在 RViz 中測試
1. 訂閱以下 topics：
   - `/map` (OccupancyGrid)
   - `/scan` (LaserScan)
   - TF frames (base_link, odom, map)

2. 使用 `2D Nav Goal` 按鈕在地圖上設置目標點

3. 觀察：
   - 機器人路徑規劃
   - 地圖實時更新
   - 機器人沿路徑移動

---

## 📊 驗收標準

| 里程碑 | 驗收條件 | 檢查方法 |
|--------|--------|--------|
| 時間同步 | 主機 vs 容器時間差 < 2s | `date +%s` |
| TF 發布 | 5 個 transform 活躍 | `ros2 tf2 list_frames` |
| LaserScan | 10 Hz, 1000+ 點 | `ros2 topic hz /scan` |
| SLAM 運作 | `/map` 逐漸填充 | RViz 可視化 |
| Nav2 就緒 | 控制器節點啟動 | `ros2 node list \| grep nav2` |
| 低速移動 | G1 以 0.03-0.1 m/s 移動 | 人工觀察 + rosbag |
| 路徑執行 | RViz Nav Goal → 自主移動 | 人工測試 |

---

## 🔍 故障排查

### 問題 1：SLAM 消息被過濾
**症狀**：`Message Filter dropping message: frame 'livox_frame'`

**解決**：
```bash
# 檢查時間同步
docker exec -it g1-nav2 date +%s
date +%s

# 如不同步，重新同步
sudo ntpdate -s time.nist.gov
docker restart g1-nav2
```

### 問題 2：TF 鏈接中斷
**症狀**：`Could not transform frame 'livox_frame' to 'base_link'`

**解決**：
```bash
# 檢查 TF 發布者
ros2 node info /base_to_lidar

# 檢查 TF 轉換
ros2 topic echo /tf | grep -A 5 'child_frame_id'
```

### 問題 3：地圖無法構建
**症狀**：`/map` topic 存在但為空

**解決**：
```bash
# 檢查 SLAM 日誌
tail -50 ~/.ros/log/*/slam_toolbox-*.log

# 檢查 LaserScan 數據質量
ros2 topic echo /scan --once | grep -E 'ranges|intensities'
```

### 問題 4：機器人不移動
**症狀**：Nav2 發送 `/cmd_vel` 但 G1 無反應

**解決**：
```bash
# 監控 cmd_vel
ros2 topic echo /cmd_vel

# 檢查馬達連接
# (取決於 Unitree SDK 的健康檢查方法)

# 確保 unitree_sdk2 已安裝
python3 -c "import unitree_sdk2py; print('OK')"
```

---

## 📁 文件結構

```
/root/ws/
├── launch/
│   ├── g1_static_tf.launch.py
│   └── g1_nav2.launch.py
├── config/
│   ├── nav2_params.yaml
│   └── rviz_nav2.rviz
├── src/
│   ├── g1_locomotion_bridge/
│   │   └── g1_cmd_vel_bridge.py
│   └── ...
├── install/
└── build/
```

---

## 📝 快速啟動腳本

**檔案**：`/root/ws/start_nav_stack.sh`

```bash
#!/bin/bash

# 顏色定義
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}[1/5] 啟動 TF...${NC}"
ros2 launch launch/g1_static_tf.launch.py &
sleep 2

echo -e "${BLUE}[2/5] 啟動 PointCloud→LaserScan...${NC}"
ros2 run pointcloud_to_laserscan pointcloud_to_laserscan_node \
  --ros-args -r cloud_in:=/utlidar/cloud_livox_mid360 -r scan:=/scan &
sleep 2

echo -e "${BLUE}[3/5] 啟動 SLAM Toolbox...${NC}"
ros2 run slam_toolbox async_slam_toolbox_node \
  --ros-args -p use_sim_time:=false -p map_frame:=map \
  -p odom_frame:=odom -p base_frame:=base_link &
sleep 2

echo -e "${BLUE}[4/5] 啟動 Nav2...${NC}"
ros2 launch nav2_bringup navigation_launch.py use_sim_time:=false \
  params_file:=/root/ws/config/nav2_params.yaml &
sleep 2

echo -e "${BLUE}[5/5] 啟動控制橋接...${NC}"
python3 /root/ws/src/g1_locomotion_bridge/g1_cmd_vel_bridge.py &

echo -e "${GREEN}✓ 所有組件已啟動${NC}"
echo "啟動 RViz：rviz2"
```

使用方式：
```bash
cd /root/ws
source install/setup.bash
bash start_nav_stack.sh
```

---

## 🎯 下一步

1. **驗證 2D SLAM + Nav2 完整流程**
   - 小型室內環境測試（< 10m × 10m）
   - 記錄 rosbag 以便離線分析

2. **性能優化**
   - 調整 SLAM 參數（掃描匹配、環閉合）
   - 微調 Nav2 PID 控制器

3. **安全性強化**
   - 添加緊急停止（E-Stop）邏輯
   - 實現速度限制與碰撞緩衝

4. **後續功能**（可選）
   - 3D LIO 增強（FAST-LIO2）
   - 多樓層地圖
   - 長期自主運作

---

**文檔版本**：v1.0  
**最後更新**：2026-09-03  
**作者**：GitHub Copilot  
**狀態**：待驗證
