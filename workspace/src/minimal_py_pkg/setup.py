from setuptools import setup

package_name = 'minimal_py_pkg'

setup(
    name=package_name,
    version='0.0.1',
    packages=[package_name],
    data_files=[
        ('share/ament_index/resource_index/packages', ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='ros2-docker maintainers',
    maintainer_email='businesswhatdheck@gmail.com',
    description='Trivial ament_python package for the colcon build smoke test',
    license='Apache-2.0',
    entry_points={
        'console_scripts': [
            'minimal_py_node = minimal_py_pkg.minimal_py_node:main',
        ],
    },
)
