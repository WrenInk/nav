#!/usr/bin/env python3
"""重定位 + 路径规划 + 导航。

加载建图阶段保存的 <map_name>.pcd / .yaml:
  - point_lio 出实时里程计 (odom)
  - sensor_scan_generation 出 odom->base TF
  - small_gicp_relocalization 用 <map_name>.pcd 配准出 map->odom TF
  - Nav2 (costmap + planner + omni-pid-pursuit 控制器) 规划并输出 /cmd_vel

用法:
  ros2 launch nav_bringup navigation.launch.py map_name:=arena
  (可加 use_rviz:=false 无头运行)

说明: 复用 pb2025_nav_bringup 的 rm_navigation_reality_mapping_launch.py (slam:=False = 重定位模式),
它会拉起驱动 + point_lio + 感知 + small_gicp + Nav2。地图按 world=<map_name> 从
pb2025_nav_bringup/{map,pcd}/reality/ 解析 (建图阶段已写入此处)。
"""
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration, PathJoinSubstitution
from launch_ros.substitutions import FindPackageShare


def generate_launch_description():
    map_name = LaunchConfiguration("map_name")
    use_rviz = LaunchConfiguration("use_rviz")

    nav_launch = PathJoinSubstitution(
        [FindPackageShare("pb2025_nav_bringup"), "launch",
         "rm_navigation_reality_mapping_launch.py"])

    return LaunchDescription([
        DeclareLaunchArgument("map_name", default_value="arena",
                              description="要加载的地图名 (建图阶段保存的)"),
        DeclareLaunchArgument("use_rviz", default_value="true"),
        IncludeLaunchDescription(
            PythonLaunchDescriptionSource(nav_launch),
            launch_arguments={
                "slam": "False",          # False = 重定位+导航模式
                "world": map_name,
                "use_rviz": use_rviz,
            }.items(),
        ),
    ])
