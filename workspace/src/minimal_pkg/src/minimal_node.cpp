#include "rclcpp/rclcpp.hpp"

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  auto node = std::make_shared<rclcpp::Node>("minimal_node");
  RCLCPP_INFO(node->get_logger(), "minimal_pkg: colcon build smoke test OK");
  rclcpp::shutdown();
  return 0;
}
