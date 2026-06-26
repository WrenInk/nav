#!/usr/bin/env bash
# 一键搭建 nav 工作区(新设备首次部署 / 依赖变更后运行)
# 用法: ./setup.sh
set -e
cd "$(dirname "$0")"
source /opt/ros/humble/setup.bash

# --- 0. github 连通性:build 阶段 small_gicp_relocalization 用 FetchContent 从 github 拉 koide3/small_gicp。
#        直连不通但本机 mihomo(127.0.0.1:7897)可达时,自动给 github 配 git 代理。 ---
PROXY=http://127.0.0.1:7897
if ! curl -fsI -m 8 https://github.com >/dev/null 2>&1; then
  if curl -fsI -m 8 -x "$PROXY" https://github.com >/dev/null 2>&1; then
    echo "==> 直连 github 不通,检测到 mihomo,为 github 配置 git 代理"
    git config --global http.https://github.com.proxy "$PROXY"
    export HTTPS_PROXY="$PROXY" HTTP_PROXY="$PROXY"
  else
    echo "⚠ 警告:直连 github 不通,且未检测到 127.0.0.1:7897 代理。"
    echo "   build 阶段 small_gicp 的 FetchContent 可能失败 —— 请确保能访问 github 后重试。"
  fi
fi

echo "==> [1/3] 系统依赖 (rosdep)"
sudo rosdep init 2>/dev/null || true
rosdep update || true
rosdep install --from-paths src -y --ignore-src

echo "==> [2/3] Python 依赖 (sdformat_tools 运行时需要 xmacro)"
pip install "xmacro==1.2.1"

echo "==> [3/3] 编译 (Release + symlink-install)"
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release

echo
echo "✅ 完成。每个新终端执行: source ~/nav/install/setup.bash"
echo "   建图: ros2 run nav_bringup run_mapping --map-name arena"
echo "   导航: ros2 launch nav_bringup navigation.launch.py map_name:=arena"
