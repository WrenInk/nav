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

## 二、部署操作指南(新设备从零到能跑导航)

> 从一台干净的设备开始,**按 0→7 顺序往下做即可**。原理 / 多设备对齐见第七节。

### 0. 前提(设备要求,务必先满足)
- **Ubuntu 22.04 + ROS 2 Humble**,且已 `source /opt/ros/humble/setup.bash`(没装 `setup.sh` 会直接提示退出)。
- 架构 **x86_64 或 arm64**(Livox-SDK2 两种预编译库都已 bundle,Jetson 狗可直接用)。
- **网络正常**:装系统依赖(apt)、`xmacro`(pip)、首次 `rosdep update` 需联网;`build` 本身离线(small_gicp 已 vendored)。

### 1. 国内换源(国外 / 网络已通畅可跳过)
`build` 本身不依赖 GitHub(small_gicp 已 vendored),但 **`git clone` 本仓库、`rosdep update`、apt 装依赖** 在国内可能卡。换源后这三处都顺。

**1a. 换 apt / rosdep 源** —— 推荐 fishros 一键(系统 apt 源 + ROS 源 + rosdep 一起换,最省事):
```bash
wget http://fishros.com/install -O fishros && . fishros
# 菜单里选「换源」(系统源 + ROS 源) 和「一键配置 rosdep」
```
或手动用清华 tuna 配 rosdep:
```bash
echo 'export ROSDISTRO_INDEX_URL=https://mirrors.tuna.tsinghua.edu.cn/rosdistro/index-v4.yaml' >> ~/.bashrc && source ~/.bashrc
sudo sed -i 's#https://raw.githubusercontent.com#https://mirrors.tuna.tsinghua.edu.cn/github-raw#g' /etc/ros/rosdep/sources.list.d/20-default.list
rosdep update
```

**1b. `git clone` 走镜像 / 代理**(下一步克隆本仓库用,直连慢/失败时):
```bash
# 镜像(下一步把 clone 地址换成它):https://gitclone.com/github.com/WrenInk/nav
# 或有 mihomo 时走代理:
git config --global http.https://github.com.proxy http://127.0.0.1:7897
```
> ⚠️ 设备**没运行 mihomo** 时,别让 git / 环境变量指向 `127.0.0.1:7897`,否则一切外连"连接被拒绝"。
> 检查:`env | grep -i proxy`,清理:`unset http_proxy https_proxy all_proxy`。

### 2. 克隆
```bash
git clone https://github.com/WrenInk/nav ~/nav && cd ~/nav
# 国内直连慢:git clone https://gitclone.com/github.com/WrenInk/nav ~/nav && cd ~/nav
```

### 3. 一键搭建(装依赖 + 编译)
```bash
./setup.sh            # 装完即可;想顺带自检用: ./setup.sh --smoke
```
`setup.sh` 自动依次完成:① 环境自检(ROS/架构)→ ② `rosdep` 装系统依赖 → ③ `pip install xmacro` →
④ `colcon build --symlink-install`(Release)。任一步失败都会停下并打印怎么修;若卡在 `rosdep update`,回第 1 步换源再重跑。

### 4. 每个新终端都要 source
```bash
source ~/nav/install/setup.bash      # 嫌烦可写进 ~/.bashrc
```

### 5. 验证(推荐)
```bash
./smoke_test.sh                       # 校验包齐全 + 建图/导航两条 launch 可解析
```

### 6. 配 MID360 有线网口(接真雷达、跑建图/导航前必做)
MID360 是**有线以太网雷达**。驱动启动时把数据套接字 **bind 到主机 IP `192.168.1.50`**(见 `src/driver/livox_ros_driver2/config/MID360_config.json`)。若连雷达的有线网口没有这个 IP,会报 `bind failed → Failed to init livox lidar sdk → Init lds lidar fail!` → point_lio 收不到点 → **RViz 没有点云**。

**网段固定**:雷达 `192.168.1.146`、主机 `192.168.1.50`、掩码 `/24`(同网段直连,无需网关)。

**方法 A:图形界面(永久,推荐)** —— 设置 → 网络 → 有线 → ⚙ → **IPv4 → 手动(Manual)**:

| 字段 | 值 |
|---|---|
| 地址 Address | `192.168.1.50` |
| 子网掩码 Netmask | `255.255.255.0`(或前缀 `24`) |
| 网关 Gateway | **留空!** 填了会抢默认路由、断 WiFi 上网 |
| DNS / 路由 | 留空 |

保存后把该有线连接**关→开**一次。上网仍走 WiFi,互不影响。

**方法 B:命令行(临时,重启失效,先用来测通)**
```bash
ip link show                                       # 找连雷达的有线口名(如 enp2s0 / enxXXXX)
sudo ip addr add 192.168.1.50/24 dev <网口名>
```

**验证**
```bash
ip -4 addr show | grep 192.168.1.50                # 网口已有 .50
ping -c 3 192.168.1.146                            # 雷达 ping 通
```
两条都正常即可。常见问题:
- **`ip -4 addr` 里根本没有有线网口**:这台机只有 WiFi。MID360 不能走 WiFi,需插 **USB 转千兆以太网**适配器(会出现成 `enxXXXX`),再按上面配 `.50`。
- **`bind failed`**:有线口没配 `192.168.1.50`(最常见)。
- **ping 不通 `192.168.1.146`**:网线没插对口 / 雷达没上电 / 雷达 IP 不是 `.146`。
- **配了 `.50` 仍连不上**:本机若开了 mihomo/代理 TUN,可能劫持 `192.168.1.0/24`。查 `ip route get 192.168.1.146`,应显示 `dev <有线口>` 而非 `dev Meta/tun`;若被劫持,在代理里把 `192.168.1.0/24` 设为直连或临时关 TUN。

### 7. 跑起来(详细用法见第三节)
```bash
ros2 run nav_bringup run_mapping --map-name arena                              # 建图(Ctrl+C 自动存图)
ros2 launch nav_bringup navigation.launch.py map_name:=arena use_rviz:=false   # 导航(已带 arena 地图,无需先建图)
```

### 仅改了代码后重新编译
```bash
cd ~/nav && colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release
source install/setup.bash
```
> 只改 `*.yaml` / `launch` 时因 `--symlink-install` **即时生效,无需重编**。

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

## 五、注意
- MID360 网络:雷达 `192.168.1.146`、主机 `192.168.1.50`(驱动 config 已设);本机若开 mihomo TUN 会劫持
  `192.168.1.0/24`,真机/狗上无此问题。
- URDF 挂载(`pb2025_robot_description`)目前是实车配置,换到机器狗需更新 MID360 安装位姿(前顶、下俯 30°)。

## 六、部署原理 / 多设备对齐

> 部署步骤见第二节;这里是背后的原理 + 代码更新后多设备如何同步。

本工作区是 **monorepo**:所有包(含第三方 `sdformat_tools`、桥接节点 `loam_interface`、bundle 的 `Livox-SDK2` amd64/arm64 预编译库)都已入库,`git clone` 即得全部源码。

- **构建期无需 GitHub**:`small_gicp` 已 vendored 进仓库(`small_gicp_relocalization/third_party/`),build 只需 apt(系统库) + PyPI(`xmacro`)。仅**首次 `git clone` 本仓库**需要网络。
- `nav.repos`:外部依赖来源台账(溯源/更新用)。
- ⚠️ 关键依赖(整合时曾漏,已补):
  - `sdformat_tools`(纯 Python,转 URDF)+ `pip install xmacro` —— 缺则**导航 launch 直接报错起不来**。
  - `loam_interface` —— point_lio→`/registered_scan`+`/lidar_odometry` 的桥梁,缺则**重定位/感知/导航全瘫**。
  - `./smoke_test.sh` 能在部署时立刻发现这类"缺包"问题。

### 更新 / 同步到其它设备

`git clone` 只在第一次做;之后所有设备靠 `git pull` 增量更新——GitHub 远端是"唯一真相",**一台改完 `push`,其它设备 `pull` 下来重编即可**。标准流程(每台消费设备上):

```bash
cd ~/nav
git pull                                                          # 拉最新代码(地图 arena.* 也在 git 里,一并更新)
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release
source install/setup.bash
```

按"改了什么"可以更省事:

| 这次改动 | 其它设备要做什么 |
|---|---|
| 只改 `*.yaml` / `launch` / 地图 | `git pull` 即可,**因 `--symlink-install` 即时生效,连 build 都不用**,重启 launch 就行 |
| 改了 C++(point_lio / small_gicp / terrain / 驱动 等) | `git pull` + `colcon build`(增量,只重编动过的包,很快) |
| 改了依赖(`package.xml` 加了新包) | `git pull` 后重跑 `./setup.sh`(补 rosdep 依赖再 build) |

注意:
- **消费设备别在本地改代码**,否则 `git pull` 会和本地改动冲突。真冲突了:`git stash`(临时存)或 `git checkout -- <文件>`(丢弃本地改)再 pull。保持"一台编辑机 push、其它只 pull"最干净。
- **锁版本**:要几台机跑同一份代码,`git pull` 到同一个 commit / tag,别各 pull 各的 HEAD。
- `build/` `install/` `log/` 都在 `.gitignore`,不随 git 同步;各设备本地各自编译,互不干扰。