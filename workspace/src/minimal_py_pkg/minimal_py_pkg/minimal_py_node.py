import rclpy
from rclpy.node import Node


def main(args=None):
    rclpy.init(args=args)
    node = Node('minimal_py_node')
    node.get_logger().info('minimal_py_pkg: colcon build smoke test OK')
    node.destroy_node()
    rclpy.shutdown()


if __name__ == '__main__':
    main()
