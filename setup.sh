#!/usr/bin/env bash
# 一键搭建 nav 工作区(新设备首次部署 / 依赖变更后运行)
# 用法: ./setup.sh
set -e
cd "$(dirname "$0")"

echo "==> [1/3] 系统依赖 (rosdep)"
sudo rosdep init 2>/dev/null || true
rosdep update || true
source /opt/ros/humble/setup.bash
rosdep install --from-paths src -y --ignore-src || true

echo "==> [2/3] Python 依赖 (sdformat_tools 需要 xmacro)"
pip install xmacro

echo "==> [3/3] 编译 (Release + symlink-install)"
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release

echo
echo "✅ 完成。每个新终端执行: source ~/nav/install/setup.bash"
echo "   建图: ros2 run nav_bringup run_mapping --map-name arena"
echo "   导航: ros2 launch nav_bringup navigation.launch.py map_name:=arena"
