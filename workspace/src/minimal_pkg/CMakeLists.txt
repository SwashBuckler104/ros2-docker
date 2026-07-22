cmake_minimum_required(VERSION 3.8)
project(minimal_pkg)

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)

add_executable(minimal_node src/minimal_node.cpp)
ament_target_dependencies(minimal_node rclcpp)

install(TARGETS minimal_node DESTINATION lib/${PROJECT_NAME})

ament_package()
