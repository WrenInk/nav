#!/usr/bin/env bash
# 一键搭建 nav 工作区(新设备首次部署 / 依赖变更后运行)
# 用法: ./setup.sh [--smoke]
#   --smoke   build 完成后自动跑 ./smoke_test.sh(包齐全 + launch 可解析)
# 前提: Ubuntu 22.04 + ROS 2 Humble 已装、网络正常。
# 说明: small_gicp 已 vendored 进仓库,build 全程不需要访问 GitHub。
#       仅需:apt(系统库) + PyPI(xmacro)。
set -eo pipefail
cd "$(dirname "$0")"

RUN_SMOKE=0
[ "${1:-}" = "--smoke" ] && RUN_SMOKE=1

# ---- 0) 环境自检(缺了直接给清楚提示,不让后面报一行看不懂的错就退出)----
ROS_SETUP=/opt/ros/humble/setup.bash
if [ ! -f "$ROS_SETUP" ]; then
  echo "✗ 未检测到 ROS 2 Humble($ROS_SETUP 不存在)。"
  echo "  本工作区要求 Ubuntu 22.04 + ROS 2 Humble,请先装好再重跑 ./setup.sh"
  echo "  (国内可用 fishros 一键装:wget http://fishros.com/install -O fishros && . fishros)"
  exit 1
fi
source "$ROS_SETUP"
echo "==> 环境: ROS_DISTRO=${ROS_DISTRO}  架构=$(uname -m)  (Livox-SDK2 amd64/arm64 预编译库已 bundle)"

# ---- 1) 系统依赖 (rosdep) ----
echo "==> [1/4] 系统依赖 (rosdep)"
sudo rosdep init 2>/dev/null || true
if ! rosdep update; then
  echo "✗ rosdep update 失败(国内常见:raw.githubusercontent.com 被墙)。"
  echo "  解决见 README 第八节:fishros 一键配置 或 清华 tuna 镜像,再重跑 ./setup.sh"
  exit 1
fi
if ! rosdep install --from-paths src -y --ignore-src; then
  echo "✗ rosdep install 失败:部分系统依赖没装上(多为网络/源问题)。"
  echo "  见 README 第八节换国内源后重跑 ./setup.sh"
  exit 1
fi

# ---- 2) pip(部分纯净系统没带)----
echo "==> [2/4] 确认 pip 可用"
if ! python3 -m pip --version >/dev/null 2>&1; then
  echo "    未检测到 pip,安装 python3-pip ..."
  sudo apt-get install -y python3-pip
fi

# ---- 3) Python 依赖 (sdformat_tools 运行时需要 xmacro) ----
echo "==> [3/4] Python 依赖 (xmacro)"
# 兼容 PEP 668(externally-managed)系统:依次回退
python3 -m pip install "xmacro==1.2.1" \
  || python3 -m pip install --user "xmacro==1.2.1" \
  || python3 -m pip install --break-system-packages "xmacro==1.2.1"

# ---- 4) 编译 ----
echo "==> [4/4] 编译 (Release + symlink-install) —— small_gicp 已 vendored,无需 GitHub"
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release

echo
echo "✅ 搭建完成。每个新终端执行: source ~/nav/install/setup.bash"
echo "   建图: ros2 run nav_bringup run_mapping --map-name arena"
echo "   导航: ros2 launch nav_bringup navigation.launch.py map_name:=arena"

if [ "$RUN_SMOKE" = "1" ]; then
  echo
  echo "==> 运行冒烟测试 (./smoke_test.sh)"
  ./smoke_test.sh
else
  echo
  echo "   建议验证: ./smoke_test.sh  (或直接 ./setup.sh --smoke 一步带上)"
fi
