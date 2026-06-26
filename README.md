# nav — MID360 完整导航工作区 (ROS 2 Humble)

基于 **Livox MID360** 的一体化导航栈:**建图(自动保存点云+栅格图) → 重定位 → 路径规划 → 导航**。
整理自 `~/mid360_nav`(pb2025 实车导航栈的去仿真版),剔除底盘串口与决策机,新增统一入口包 `nav_bringup`。

> 决策机/任务逻辑(箱子识别、搬运调度)**不在本工作区**,后续单独接入。

---

## 一、目录结构

```
nav/src/
├── driver/        livox_ros_driver2          MID360 驱动 (含 Livox-SDK2)
├── mapping/       point_lio                  Point-LIO 激光惯性里程计 (建图核心, 退出存 PCD)
├── localization/  small_gicp_relocalization  点云重定位 (PCD 配准出 map->odom)
├── perception/    sensor_scan_generation     里程计 -> odom->base TF
│                  terrain_analysis(_ext)     地形分割 -> 代价地图障碍源
│                  pointcloud_to_laserscan    3D 点云 -> 2D 激光
├── navigation/    pb2025_nav_bringup         Nav2 总启动 (launch/config/map/pcd/bt)
│                  pb_omni_pid_pursuit_controller  全向 PID 纯跟踪控制器
│                  pb_nav2_plugins / fake_vel_transform  Nav2 插件 / 速度变换
├── description/   pb2025_robot_description   URDF / RViz
├── teleop/        pb_teleop_twist_joy        手柄遥控 (建图时开车用)
└── bringup/       nav_bringup ★新增★         统一入口: 建图(自动保存) / 导航 launch + 工具
```

## 二、编译

```bash
cd ~/nav
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release
source install/setup.bash
```

## 三、用法

### ① 建图(结束自动保存点云 + 栅格图)
```bash
ros2 run nav_bringup run_mapping --map-name arena
```
- 用手柄/键盘把机器人在场地里开一圈,point_lio 实时建 3D 点云图。
- **结束时按 `Ctrl+C`**,自动保存:
  - 点云 → `pb2025_nav_bringup/pcd/reality/arena.pcd`(重定位用)
  - 栅格图 → `pb2025_nav_bringup/map/reality/arena.pgm` + `.yaml`(Nav2 用)
  - **src 与 install/share 两处同时写,导航无需再 `colcon build`。**
- 栅格图由点云投影生成(高度带默认 `0.1~0.8m`,正好含 0.8m 围墙、滤掉地面),与重定位用的 PCD **同源、坐标系天然对齐**。
- 可调:`--resolution 0.05 --zmin 0.1 --zmax 0.8`。
- ⚠️ 用 `run_mapping`(不是直接 `ros2 launch`):它做父进程,Ctrl+C 时先等 point_lio 写完点云再投影栅格图,
  避免 `ros2 launch` 收尾 5 秒超时把保存进程杀掉(这点已实测踩坑)。`mapping.launch.py` 只是它内部起的核心。

### ② 重定位 + 路径规划 + 导航
```bash
ros2 launch nav_bringup navigation.launch.py map_name:=arena
# 无头: 追加 use_rviz:=false
```
- 加载 `arena.pcd` / `arena.yaml`,point_lio 出里程计、small_gicp 出 `map->odom`、Nav2 规划并发 `/cmd_vel`。
- 在 RViz 用 **2D Goal Pose** 给目标即可导航。

### 工具:点云重投栅格图(免重新建图调参)
```bash
ros2 run nav_bringup pcd_to_grid --pcd <某.pcd> --out <输出前缀> --resolution 0.05 --zmin 0.1 --zmax 0.8
```

## 四、数据流 / TF
```
MID360 ─livox_ros_driver2─▶ /livox/lidar,/livox/imu
        │
        ├─ point_lio ─▶ odom (/aft_mapped_to_init, /cloud_registered)
        ├─ sensor_scan_generation ─▶ TF odom->base
        └─ small_gicp(载入<map>.pcd) ─▶ TF map->odom
                                          │
   TF: map ─▶ odom ─▶ base ─▶ mid360     ▼
   Nav2: costmap(static<map>.yaml + terrain/scan + inflation) + planner + omni-pid-pursuit ─▶ /cmd_vel
```

## 五、给机器狗 / N150 的调优(可选,见对话记录)
- N150 上为省 CPU:costmap 可改 2D `ObstacleLayer`(走 `/scan`),控制器用 omni-pid-pursuit(已内置),
  重定位可换 AMCL(2D 更省)。详见性能分析结论。
- `~/nav/src/navigation/pb2025_nav_bringup/config/reality/nav2_params.yaml` 为主参数文件。

## 六、注意
- MID360 网络:雷达 `192.168.1.146`、主机 `192.168.1.50`(驱动 config 已设);本机若开 mihomo TUN 会劫持
  `192.168.1.0/24`,真机/狗上无此问题。
- URDF 挂载(`pb2025_robot_description`)目前是实车配置,换到机器狗需更新 MID360 安装位姿(前顶、下俯 30°)。

## 七、部署到新设备 / 多设备对齐

本工作区是 **monorepo**:所有包(含第三方 `sdformat_tools`、桥接节点 `loam_interface`)都已入库,
`git clone` 即得全部源码,部署不依赖外网逐个拉取。

```bash
git clone <仓库地址> ~/nav && cd ~/nav
./setup.sh          # 装系统依赖(rosdep)+ pip xmacro + colcon build
source install/setup.bash
./smoke_test.sh     # 可选:验证包齐全 + 两条 launch 可解析
```

- **改完同步到其它设备**:`git pull && colcon build --symlink-install`(或局域网 `rsync` 直推 `src/`)。
- **锁版本**:用 git tag/commit 保证各设备构建同一份代码。
- `nav.repos`:外部依赖来源台账(溯源/更新用)。
- ⚠️ 关键依赖(整合时曾漏,已补):
  - `sdformat_tools`(纯 Python,转 URDF)+ `pip install xmacro` —— 缺则**导航 launch 直接报错起不来**。
  - `loam_interface` —— point_lio→`/registered_scan`+`/lidar_odometry` 的桥梁,缺则**重定位/感知/导航全瘫**。
  - `./smoke_test.sh` 能在部署时立刻发现这类"缺包"问题。
