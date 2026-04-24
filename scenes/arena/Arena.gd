class_name Arena
extends Node3D

@onready var match_node: Node = $BeaconMatch
@onready var hud: CanvasLayer = $HUD
@onready var pause_menu: CanvasLayer = $PauseMenu

const DEBUG_PENROSE := false

const _PENROSE_VERTS: Array = [
  Vector2(9.511, -71.631),
  Vector2(-0.000, -68.541),
  Vector2(40.287, -55.451),
  Vector2(40.287, -45.451),
  Vector2(30.777, -42.361),
  Vector2(30.777, -52.361),
  Vector2(9.511, -55.451),
  Vector2(9.511, -45.451),
  Vector2(-0.000, -42.361),
  Vector2(-0.000, -52.361),
  Vector2(-9.511, -55.451),
  Vector2(-9.511, -45.451),
  Vector2(-19.021, -42.361),
  Vector2(-19.021, -52.361),
  Vector2(-40.287, -55.451),
  Vector2(-40.287, -45.451),
  Vector2(-49.798, -42.361),
  Vector2(-49.798, -52.361),
  Vector2(65.186, -21.180),
  Vector2(65.186, -31.180),
  Vector2(49.798, -26.180),
  Vector2(49.798, -16.180),
  Vector2(40.287, -13.090),
  Vector2(40.287, -23.090),
  Vector2(24.899, -34.270),
  Vector2(24.899, -24.270),
  Vector2(15.388, -21.180),
  Vector2(15.388, -31.180),
  Vector2(-0.000, -26.180),
  Vector2(-0.000, -16.180),
  Vector2(-9.511, -13.090),
  Vector2(-9.511, -23.090),
  Vector2(-24.899, -34.270),
  Vector2(-24.899, -24.270),
  Vector2(-34.410, -21.180),
  Vector2(-34.410, -31.180),
  Vector2(-55.676, -34.270),
  Vector2(-55.676, -24.270),
  Vector2(-65.186, -21.180),
  Vector2(-65.186, -31.180),
  Vector2(65.186, -5.000),
  Vector2(65.186, 5.000),
  Vector2(55.676, 8.090),
  Vector2(55.676, -1.910),
  Vector2(34.410, -5.000),
  Vector2(34.410, 5.000),
  Vector2(24.899, 8.090),
  Vector2(24.899, -1.910),
  Vector2(0.000, 0.000),
  Vector2(0.000, 10.000),
  Vector2(-9.511, 13.090),
  Vector2(-9.511, 3.090),
  Vector2(-24.899, -8.090),
  Vector2(-24.899, 1.910),
  Vector2(-34.410, 5.000),
  Vector2(-34.410, -5.000),
  Vector2(-55.676, -8.090),
  Vector2(-55.676, 1.910),
  Vector2(-65.186, 5.000),
  Vector2(-65.186, -5.000),
  Vector2(65.186, 21.180),
  Vector2(65.186, 31.180),
  Vector2(55.676, 34.270),
  Vector2(55.676, 24.270),
  Vector2(34.410, 21.180),
  Vector2(34.410, 31.180),
  Vector2(24.899, 34.270),
  Vector2(24.899, 24.270),
  Vector2(15.388, 21.180),
  Vector2(15.388, 31.180),
  Vector2(5.878, 34.270),
  Vector2(5.878, 24.270),
  Vector2(-15.388, 21.180),
  Vector2(-15.388, 31.180),
  Vector2(-24.899, 34.270),
  Vector2(-24.899, 24.270),
  Vector2(-40.287, 13.090),
  Vector2(-40.287, 23.090),
  Vector2(-49.798, 26.180),
  Vector2(-49.798, 16.180),
  Vector2(-65.186, 21.180),
  Vector2(-65.186, 31.180),
  Vector2(49.798, 42.361),
  Vector2(49.798, 52.361),
  Vector2(40.287, 55.451),
  Vector2(40.287, 45.451),
  Vector2(24.899, 50.451),
  Vector2(24.899, 60.451),
  Vector2(15.388, 63.541),
  Vector2(15.388, 53.541),
  Vector2(0.000, 42.361),
  Vector2(0.000, 52.361),
  Vector2(-9.511, 55.451),
  Vector2(-9.511, 45.451),
  Vector2(-30.777, 42.361),
  Vector2(-30.777, 52.361),
  Vector2(-40.287, 55.451),
  Vector2(-40.287, 45.451),
  Vector2(0.000, 68.541),
  Vector2(-9.511, 71.631),
  Vector2(15.388, -63.541),
  Vector2(-15.388, -63.541),
  Vector2(24.899, -50.451),
  Vector2(24.899, -60.451),
  Vector2(-24.899, -50.451),
  Vector2(-24.899, -60.451),
  Vector2(30.777, -26.180),
  Vector2(30.777, -16.180),
  Vector2(-15.388, -21.180),
  Vector2(-15.388, -31.180),
  Vector2(-49.798, -26.180),
  Vector2(-49.798, -16.180),
  Vector2(40.287, 3.090),
  Vector2(40.287, 13.090),
  Vector2(-40.287, -3.090),
  Vector2(-40.287, -13.090),
  Vector2(49.798, 26.180),
  Vector2(49.798, 16.180),
  Vector2(9.511, 23.090),
  Vector2(9.511, 13.090),
  Vector2(-34.410, 21.180),
  Vector2(-34.410, 31.180),
  Vector2(19.021, 52.361),
  Vector2(19.021, 42.361),
  Vector2(-24.899, 50.451),
  Vector2(-24.899, 60.451),
  Vector2(-15.388, 63.541),
  Vector2(-9.511, -71.631),
  Vector2(-30.777, -52.361),
  Vector2(-30.777, -42.361),
  Vector2(15.388, -53.541),
  Vector2(49.798, -52.361),
  Vector2(49.798, -42.361),
  Vector2(-40.287, -23.090),
  Vector2(5.878, -24.270),
  Vector2(5.878, -34.270),
  Vector2(55.676, -24.270),
  Vector2(55.676, -34.270),
  Vector2(-46.165, -5.000),
  Vector2(-46.165, 5.000),
  Vector2(46.165, 5.000),
  Vector2(46.165, -5.000),
  Vector2(-55.676, 24.270),
  Vector2(-55.676, 34.270),
  Vector2(-9.511, 23.090),
  Vector2(40.287, 23.090),
  Vector2(-49.798, 52.361),
  Vector2(-49.798, 42.361),
  Vector2(-19.021, 52.361),
  Vector2(-19.021, 42.361),
  Vector2(30.777, 52.361),
  Vector2(30.777, 42.361),
  Vector2(9.511, 71.631),
  Vector2(19.021, -42.361),
  Vector2(19.021, -52.361),
  Vector2(9.511, -13.090),
  Vector2(9.511, -23.090),
  Vector2(-15.388, 5.000),
  Vector2(-15.388, -5.000),
  Vector2(9.511, 3.090),
  Vector2(15.388, -5.000),
  Vector2(15.388, 5.000),
  Vector2(-30.777, 26.180),
  Vector2(-30.777, 16.180),
  Vector2(-5.878, 34.270),
  Vector2(-5.878, 24.270),
  Vector2(-15.388, 53.541),
  Vector2(9.511, 55.451),
  Vector2(9.511, 45.451),
  Vector2(71.064, -13.090),
  Vector2(59.309, 13.090),
  Vector2(55.676, -8.090),
  Vector2(34.410, -31.180),
  Vector2(43.920, -34.270),
  Vector2(34.410, -63.541),
  Vector2(40.287, 39.270),
  Vector2(30.777, 16.180),
  Vector2(24.899, -8.090),
  Vector2(19.021, -16.180),
  Vector2(9.511, -39.270),
  Vector2(5.878, -60.451),
  Vector2(0.000, 16.180),
  Vector2(-5.878, -8.090),
  Vector2(-5.878, -24.270),
  Vector2(-15.388, -53.541),
  Vector2(-5.878, 60.451),
  Vector2(-9.511, 39.270),
  Vector2(-21.266, 13.090),
  Vector2(-30.777, -16.180),
  Vector2(-40.287, -39.270),
  Vector2(-34.410, 63.541),
  Vector2(-40.287, 39.270),
  Vector2(-46.165, 31.180),
  Vector2(-55.676, 8.090),
  Vector2(-59.309, -13.090),
  Vector2(-71.064, 13.090),
  Vector2(46.165, -31.180),
  Vector2(21.266, -13.090),
  Vector2(9.511, 39.270),
  Vector2(-5.878, -34.270),
  Vector2(-9.511, -39.270),
  Vector2(-24.899, 8.090),
  Vector2(40.287, -39.270),
  Vector2(34.410, 63.541),
  Vector2(5.878, 60.451),
  Vector2(46.165, 31.180),
  Vector2(71.064, 13.090),
  Vector2(0.000, 26.180),
  Vector2(21.266, 13.090),
  Vector2(59.309, -13.090),
  Vector2(5.878, -8.090),
  Vector2(-59.309, 13.090),
  Vector2(-19.021, -16.180),
  Vector2(-71.064, -13.090),
  Vector2(-43.920, -34.270),
  Vector2(-5.878, -60.451),
  Vector2(-34.410, -63.541),
  Vector2(43.920, 34.270),
  Vector2(19.021, 16.180),
]

const _PENROSE_EDGES: Array = [
  # [mid_x, mid_z, angle_rad, type]  rotation_y = PI/2 - angle_rad
  [4.7553, -70.0861, 2.827433, "fat"],
  [40.2874, -50.4508, 1.570796, "fat"],
  [35.5321, -43.9058, 2.827433, "thin"],
  [30.7768, -47.3607, -1.570796, "thin"],
  [35.5321, -53.9058, -0.314159, "fat"],
  [9.5106, -50.4508, 1.570796, "thin"],
  [4.7553, -43.9058, 2.827433, "thin"],
  [-0.0000, -47.3607, -1.570796, "fat"],
  [4.7553, -53.9058, -0.314159, "thin"],
  [-9.5106, -50.4508, 1.570796, "fat"],
  [-14.2658, -43.9058, 2.827433, "thin"],
  [-19.0211, -47.3607, -1.570796, "thin"],
  [-14.2658, -53.9058, -0.314159, "fat"],
  [-40.2874, -50.4508, 1.570796, "fat"],
  [-45.0427, -43.9058, 2.827433, "thin"],
  [-49.7980, -47.3607, -1.570796, "thin"],
  [-45.0427, -53.9058, -0.314159, "fat"],
  [65.1864, -26.1803, -1.570796, "fat"],
  [49.7980, -21.1803, 1.570796, "thin"],
  [45.0427, -14.6353, 2.827433, "fat"],
  [40.2874, -18.0902, -1.570796, "fat"],
  [45.0427, -24.6353, -0.314159, "thin"],
  [24.8990, -29.2705, 1.570796, "thin"],
  [20.1437, -22.7254, 2.827433, "fat"],
  [15.3884, -26.1803, -1.570796, "fat"],
  [20.1437, -32.7254, -0.314159, "fat"],
  [-0.0000, -21.1803, 1.570796, "thin"],
  [-4.7553, -14.6353, 2.827433, "fat"],
  [-9.5106, -18.0902, -1.570796, "thin"],
  [-4.7553, -24.6353, -0.314159, "fat"],
  [-24.8990, -29.2705, 1.570796, "fat"],
  [-29.6543, -22.7254, 2.827433, "thin"],
  [-34.4095, -26.1803, -1.570796, "thin"],
  [-29.6543, -32.7254, -0.314159, "fat"],
  [-55.6758, -29.2705, 1.570796, "thin"],
  [-60.4311, -22.7254, 2.827433, "fat"],
  [-65.1864, -26.1803, -1.570796, "fat"],
  [-60.4311, -32.7254, -0.314159, "thin"],
  [65.1864, -0.0000, 1.570796, "fat"],
  [60.4311, 6.5451, 2.827433, "thin"],
  [55.6758, 3.0902, -1.570796, "fat"],
  [60.4311, -3.4549, -0.314159, "thin"],
  [34.4095, -0.0000, 1.570796, "thin"],
  [29.6543, 6.5451, 2.827433, "fat"],
  [24.8990, 3.0902, -1.570796, "fat"],
  [29.6543, -3.4549, -0.314159, "thin"],
  [0.0000, 5.0000, 1.570796, "fat"],
  [-4.7553, 11.5451, 2.827433, "fat"],
  [-9.5106, 8.0902, -1.570796, "fat"],
  [-4.7553, 1.5451, -0.314159, "fat"],
  [-24.8990, -3.0902, 1.570796, "fat"],
  [-29.6543, 3.4549, 2.827433, "thin"],
  [-34.4095, 0.0000, -1.570796, "thin"],
  [-29.6543, -6.5451, -0.314159, "fat"],
  [-55.6758, -3.0902, 1.570796, "fat"],
  [-60.4311, 3.4549, 2.827433, "thin"],
  [-65.1864, 0.0000, -1.570796, "fat"],
  [-60.4311, -6.5451, -0.314159, "thin"],
  [65.1864, 26.1803, 1.570796, "fat"],
  [60.4311, 32.7254, 2.827433, "thin"],
  [55.6758, 29.2705, -1.570796, "thin"],
  [60.4311, 22.7254, -0.314159, "fat"],
  [34.4095, 26.1803, 1.570796, "thin"],
  [29.6543, 32.7254, 2.827433, "fat"],
  [24.8990, 29.2705, -1.570796, "fat"],
  [29.6543, 22.7254, -0.314159, "thin"],
  [15.3884, 26.1803, 1.570796, "thin"],
  [10.6331, 32.7254, 2.827433, "thin"],
  [5.8779, 29.2705, -1.570796, "fat"],
  [10.6331, 22.7254, -0.314159, "fat"],
  [-15.3884, 26.1803, 1.570796, "thin"],
  [-20.1437, 32.7254, 2.827433, "fat"],
  [-24.8990, 29.2705, -1.570796, "fat"],
  [-20.1437, 22.7254, -0.314159, "fat"],
  [-40.2874, 18.0902, 1.570796, "thin"],
  [-45.0427, 24.6353, 2.827433, "thin"],
  [-49.7980, 21.1803, -1.570796, "thin"],
  [-45.0427, 14.6353, -0.314159, "fat"],
  [-65.1864, 26.1803, 1.570796, "fat"],
  [49.7980, 47.3607, 1.570796, "thin"],
  [45.0427, 53.9058, 2.827433, "fat"],
  [40.2874, 50.4508, -1.570796, "fat"],
  [45.0427, 43.9058, -0.314159, "thin"],
  [24.8990, 55.4508, 1.570796, "thin"],
  [20.1437, 61.9959, 2.827433, "fat"],
  [15.3884, 58.5410, -1.570796, "fat"],
  [20.1437, 51.9959, -0.314159, "fat"],
  [0.0000, 47.3607, 1.570796, "fat"],
  [-4.7553, 53.9058, 2.827433, "thin"],
  [-9.5106, 50.4508, -1.570796, "fat"],
  [-4.7553, 43.9058, -0.314159, "thin"],
  [-30.7768, 47.3607, 1.570796, "thin"],
  [-35.5321, 53.9058, 2.827433, "fat"],
  [-40.2874, 50.4508, -1.570796, "fat"],
  [-35.5321, 43.9058, -0.314159, "thin"],
  [-4.7553, 70.0861, -0.314159, "fat"],
  [15.3884, -68.5410, 1.570796, "thin"],
  [12.4495, -67.5861, -2.199115, "thin"],
  [-15.3884, -68.5410, 1.570796, "thin"],
  [-18.3273, -67.5861, -2.199115, "thin"],
  [27.8379, -46.4058, -2.199115, "thin"],
  [24.8990, -55.4508, -1.570796, "thin"],
  [27.8379, -56.4058, 0.942478, "thin"],
  [-21.9601, -46.4058, -2.199115, "thin"],
  [-24.8990, -55.4508, -1.570796, "thin"],
  [-21.9601, -56.4058, 0.942478, "thin"],
  [-52.7369, -46.4058, -2.199115, "thin"],
  [30.7768, -21.1803, 1.570796, "thin"],
  [27.8379, -20.2254, -2.199115, "thin"],
  [27.8379, -30.2254, 0.942478, "thin"],
  [-12.4495, -17.1353, -2.199115, "thin"],
  [-15.3884, -26.1803, -1.570796, "thin"],
  [-12.4495, -27.1353, 0.942478, "thin"],
  [-49.7980, -21.1803, 1.570796, "thin"],
  [-52.7369, -20.2254, -2.199115, "thin"],
  [-52.7369, -30.2254, 0.942478, "thin"],
  [40.2874, 8.0902, 1.570796, "thin"],
  [37.3485, 9.0451, -2.199115, "thin"],
  [37.3485, -0.9549, 0.942478, "thin"],
  [-37.3485, 0.9549, -2.199115, "thin"],
  [-40.2874, -8.0902, -1.570796, "thin"],
  [-37.3485, -9.0451, 0.942478, "thin"],
  [52.7369, 30.2254, -2.199115, "thin"],
  [49.7980, 21.1803, -1.570796, "thin"],
  [52.7369, 20.2254, 0.942478, "thin"],
  [12.4495, 27.1353, -2.199115, "thin"],
  [9.5106, 18.0902, -1.570796, "thin"],
  [12.4495, 17.1353, 0.942478, "thin"],
  [-34.4095, 26.1803, 1.570796, "thin"],
  [-37.3485, 27.1353, -2.199115, "thin"],
  [-37.3485, 17.1353, 0.942478, "thin"],
  [52.7369, 46.4058, 0.942478, "thin"],
  [21.9601, 56.4058, -2.199115, "thin"],
  [19.0211, 47.3607, -1.570796, "thin"],
  [21.9601, 46.4058, 0.942478, "thin"],
  [-24.8990, 55.4508, 1.570796, "thin"],
  [-27.8379, 56.4058, -2.199115, "thin"],
  [-27.8379, 46.4058, 0.942478, "thin"],
  [15.3884, 68.5410, -1.570796, "thin"],
  [18.3273, 67.5861, 0.942478, "thin"],
  [-15.3884, 68.5410, -1.570796, "thin"],
  [-12.4495, 67.5861, 0.942478, "thin"],
  [-12.4495, -67.5861, -0.942478, "thin"],
  [24.8990, -65.4508, 1.570796, "thin"],
  [27.8379, -64.4959, -0.942478, "thin"],
  [-30.7768, -47.3607, 1.570796, "thin"],
  [-27.8379, -46.4058, -0.942478, "thin"],
  [-27.8379, -56.4058, 2.199115, "thin"],
  [12.4495, -49.4959, -0.942478, "thin"],
  [15.3884, -58.5410, -1.570796, "thin"],
  [12.4495, -59.4959, 2.199115, "thin"],
  [49.7980, -47.3607, 1.570796, "thin"],
  [52.7369, -46.4058, -0.942478, "thin"],
  [-40.2874, -18.0902, 1.570796, "thin"],
  [-37.3485, -17.1353, -0.942478, "thin"],
  [-37.3485, -27.1353, 2.199115, "thin"],
  [2.9389, -20.2254, -0.942478, "thin"],
  [5.8779, -29.2705, -1.570796, "thin"],
  [2.9389, -30.2254, 2.199115, "thin"],
  [52.7369, -20.2254, -0.942478, "thin"],
  [55.6758, -29.2705, -1.570796, "thin"],
  [52.7369, -30.2254, 2.199115, "thin"],
  [-46.1653, 0.0000, 1.570796, "thin"],
  [-43.2263, 0.9549, -0.942478, "thin"],
  [-43.2263, -9.0451, 2.199115, "thin"],
  [43.2263, 9.0451, -0.942478, "thin"],
  [46.1653, -0.0000, -1.570796, "thin"],
  [43.2263, -0.9549, 2.199115, "thin"],
  [-55.6758, 29.2705, 1.570796, "thin"],
  [-52.7369, 30.2254, -0.942478, "thin"],
  [-52.7369, 20.2254, 2.199115, "thin"],
  [-12.4495, 27.1353, -0.942478, "thin"],
  [-9.5106, 18.0902, -1.570796, "thin"],
  [-12.4495, 17.1353, 2.199115, "thin"],
  [37.3485, 27.1353, -0.942478, "thin"],
  [40.2874, 18.0902, -1.570796, "thin"],
  [37.3485, 17.1353, 2.199115, "thin"],
  [-49.7980, 47.3607, -1.570796, "thin"],
  [-52.7369, 46.4058, 2.199115, "thin"],
  [-21.9601, 56.4058, -0.942478, "thin"],
  [-19.0211, 47.3607, -1.570796, "thin"],
  [-21.9601, 46.4058, 2.199115, "thin"],
  [27.8379, 56.4058, -0.942478, "thin"],
  [30.7768, 47.3607, -1.570796, "thin"],
  [27.8379, 46.4058, 2.199115, "thin"],
  [-24.8990, 65.4508, -1.570796, "thin"],
  [-27.8379, 64.4959, 2.199115, "thin"],
  [12.4495, 67.5861, 2.199115, "thin"],
  [-4.7553, -70.0861, 0.314159, "fat"],
  [20.1437, -61.9959, 0.314159, "fat"],
  [-35.5321, -43.9058, 0.314159, "thin"],
  [-35.5321, -53.9058, -2.827433, "fat"],
  [-4.7553, -43.9058, 0.314159, "thin"],
  [-4.7553, -53.9058, -2.827433, "thin"],
  [14.2658, -43.9058, 0.314159, "thin"],
  [19.0211, -47.3607, -1.570796, "fat"],
  [14.2658, -53.9058, -2.827433, "fat"],
  [45.0427, -43.9058, 0.314159, "thin"],
  [45.0427, -53.9058, -2.827433, "fat"],
  [-45.0427, -14.6353, 0.314159, "fat"],
  [-45.0427, -24.6353, -2.827433, "fat"],
  [-20.1437, -22.7254, 0.314159, "thin"],
  [-20.1437, -32.7254, -2.827433, "fat"],
  [4.7553, -14.6353, 0.314159, "fat"],
  [9.5106, -18.0902, -1.570796, "fat"],
  [4.7553, -24.6353, -2.827433, "fat"],
  [35.5321, -14.6353, 0.314159, "fat"],
  [35.5321, -24.6353, -2.827433, "thin"],
  [60.4311, -22.7254, 0.314159, "fat"],
  [60.4311, -32.7254, -2.827433, "thin"],
  [-69.9417, 3.4549, 0.314159, "thin"],
  [-69.9417, -6.5451, -2.827433, "thin"],
  [-50.9205, 3.4549, 0.314159, "thin"],
  [-50.9205, -6.5451, -2.827433, "fat"],
  [-20.1437, 3.4549, 0.314159, "thin"],
  [-15.3884, 0.0000, -1.570796, "fat"],
  [-20.1437, -6.5451, -2.827433, "fat"],
  [4.7553, 11.5451, 0.314159, "fat"],
  [9.5106, 8.0902, -1.570796, "fat"],
  [4.7553, 1.5451, -2.827433, "fat"],
  [15.3884, -0.0000, 1.570796, "fat"],
  [20.1437, 6.5451, 0.314159, "fat"],
  [20.1437, -3.4549, -2.827433, "thin"],
  [50.9205, 6.5451, 0.314159, "fat"],
  [50.9205, -3.4549, -2.827433, "thin"],
  [69.9417, 6.5451, 0.314159, "thin"],
  [69.9417, -3.4549, -2.827433, "thin"],
  [-60.4311, 32.7254, 0.314159, "thin"],
  [-60.4311, 22.7254, -2.827433, "fat"],
  [-35.5321, 24.6353, 0.314159, "thin"],
  [-30.7768, 21.1803, -1.570796, "fat"],
  [-35.5321, 14.6353, -2.827433, "fat"],
  [-10.6331, 32.7254, 0.314159, "thin"],
  [-5.8779, 29.2705, -1.570796, "fat"],
  [-10.6331, 22.7254, -2.827433, "fat"],
  [20.1437, 32.7254, 0.314159, "fat"],
  [20.1437, 22.7254, -2.827433, "thin"],
  [45.0427, 24.6353, 0.314159, "fat"],
  [45.0427, 14.6353, -2.827433, "fat"],
  [-45.0427, 53.9058, 0.314159, "fat"],
  [-45.0427, 43.9058, -2.827433, "thin"],
  [-20.1437, 61.9959, 0.314159, "fat"],
  [-15.3884, 58.5410, -1.570796, "fat"],
  [-20.1437, 51.9959, -2.827433, "fat"],
  [4.7553, 53.9058, 0.314159, "thin"],
  [9.5106, 50.4508, -1.570796, "fat"],
  [4.7553, 43.9058, -2.827433, "thin"],
  [35.5321, 53.9058, 0.314159, "fat"],
  [35.5321, 43.9058, -2.827433, "thin"],
  [4.7553, 70.0861, -2.827433, "fat"],
  [68.1253, -17.1353, -2.199115, "fat"],
  [60.4311, -35.8156, 2.827433, "thin"],
  [52.7369, -38.3156, -2.199115, "fat"],
  [54.5532, -43.9058, -0.314159, "thin"],
  [54.5532, 14.6353, -0.314159, "thin"],
  [62.2475, 17.1353, 0.942478, "fat"],
  [50.9205, -6.5451, 2.827433, "thin"],
  [43.2263, -9.0451, -2.199115, "fat"],
  [52.7369, -12.1353, 0.942478, "thin"],
  [37.3485, -27.1353, -2.199115, "thin"],
  [39.1648, -32.7254, -0.314159, "fat"],
  [46.8590, -30.2254, 0.942478, "fat"],
  [29.6543, -61.9959, -0.314159, "thin"],
  [37.3485, -59.4959, 0.942478, "fat"],
  [35.5321, 40.8156, 2.827433, "thin"],
  [27.8379, 38.3156, -2.199115, "fat"],
  [37.3485, 35.2254, 0.942478, "thin"],
  [35.5321, 14.6353, 2.827433, "thin"],
  [27.8379, 12.1353, -2.199115, "fat"],
  [20.1437, -6.5451, 2.827433, "thin"],
  [12.4495, -9.0451, -2.199115, "fat"],
  [14.2658, -14.6353, -0.314159, "fat"],
  [21.9601, -12.1353, 0.942478, "fat"],
  [12.4495, -35.2254, -2.199115, "thin"],
  [14.2658, -40.8156, -0.314159, "thin"],
  [21.9601, -38.3156, 0.942478, "fat"],
  [10.6331, -61.9959, 2.827433, "thin"],
  [2.9389, -64.4959, -2.199115, "fat"],
  [27.8379, 64.4959, 0.942478, "thin"],
  [12.4495, 49.4959, -2.199115, "fat"],
  [14.2658, 43.9058, -0.314159, "thin"],
  [2.9389, 20.2254, -2.199115, "fat"],
  [4.7553, 14.6353, -0.314159, "fat"],
  [-12.4495, -0.9549, -2.199115, "fat"],
  [-10.6331, -6.5451, -0.314159, "fat"],
  [-2.9389, -4.0451, 0.942478, "fat"],
  [-10.6331, -22.7254, -0.314159, "fat"],
  [-2.9389, -20.2254, 0.942478, "fat"],
  [-20.1437, -51.9959, -0.314159, "fat"],
  [-12.4495, -49.4959, 0.942478, "fat"],
  [-20.1437, -61.9959, 2.827433, "fat"],
  [-27.8379, -64.4959, -2.199115, "thin"],
  [-10.6331, 61.9959, -0.314159, "thin"],
  [-2.9389, 64.4959, 0.942478, "fat"],
  [-14.2658, 40.8156, 2.827433, "thin"],
  [-21.9601, 38.3156, -2.199115, "fat"],
  [-12.4495, 35.2254, 0.942478, "thin"],
  [-27.8379, 20.2254, -2.199115, "fat"],
  [-26.0216, 14.6353, -0.314159, "thin"],
  [-18.3273, 17.1353, 0.942478, "fat"],
  [-35.5321, -14.6353, -0.314159, "thin"],
  [-27.8379, -12.1353, 0.942478, "fat"],
  [-37.3485, -35.2254, -2.199115, "thin"],
  [-35.5321, -40.8156, -0.314159, "thin"],
  [-27.8379, -38.3156, 0.942478, "fat"],
  [-29.6543, 61.9959, 2.827433, "thin"],
  [-37.3485, 59.4959, -2.199115, "fat"],
  [-45.0427, 40.8156, 2.827433, "thin"],
  [-52.7369, 38.3156, -2.199115, "fat"],
  [-50.9205, 32.7254, -0.314159, "thin"],
  [-43.2263, 35.2254, 0.942478, "fat"],
  [-52.7369, 12.1353, -2.199115, "thin"],
  [-50.9205, 6.5451, -0.314159, "thin"],
  [-43.2263, 9.0451, 0.942478, "fat"],
  [-54.5532, -14.6353, 2.827433, "thin"],
  [-62.2475, -17.1353, -2.199115, "fat"],
  [-54.5532, 43.9058, 2.827433, "thin"],
  [-60.4311, 35.8156, -0.314159, "thin"],
  [-68.1253, 17.1353, 0.942478, "fat"],
  [69.9417, -6.5451, 2.827433, "thin"],
  [68.1253, -9.0451, -0.942478, "thin"],
  [52.7369, 12.1353, -0.942478, "thin"],
  [62.2475, 9.0451, 2.199115, "thin"],
  [43.2263, -27.1353, -0.942478, "thin"],
  [50.9205, -32.7254, -0.314159, "thin"],
  [27.8379, 20.2254, -0.942478, "thin"],
  [18.3273, -9.0451, -0.942478, "thin"],
  [26.0216, -14.6353, -0.314159, "thin"],
  [27.8379, -12.1353, 2.199115, "thin"],
  [2.9389, -56.4058, -0.942478, "thin"],
  [4.7553, 40.8156, 2.827433, "thin"],
  [2.9389, 38.3156, -0.942478, "thin"],
  [12.4495, 35.2254, 2.199115, "thin"],
  [-10.6331, -32.7254, 2.827433, "thin"],
  [-12.4495, -35.2254, -0.942478, "thin"],
  [-4.7553, -40.8156, -0.314159, "thin"],
  [-2.9389, -38.3156, 2.199115, "thin"],
  [-12.4495, 59.4959, -0.942478, "thin"],
  [-2.9389, 56.4058, 2.199115, "thin"],
  [-27.8379, 12.1353, -0.942478, "thin"],
  [-20.1437, 6.5451, -0.314159, "thin"],
  [-18.3273, 9.0451, 2.199115, "thin"],
  [-27.8379, -20.2254, 2.199115, "thin"],
  [-43.2263, 27.1353, 2.199115, "thin"],
  [-62.2475, -9.0451, -0.942478, "thin"],
  [-52.7369, -12.1353, 2.199115, "thin"],
  [-69.9417, 6.5451, -0.314159, "thin"],
  [-68.1253, 9.0451, 2.199115, "thin"],
  [35.5321, -40.8156, 0.314159, "thin"],
  [45.0427, -40.8156, -0.314159, "thin"],
  [60.4311, -6.5451, -2.827433, "thin"],
  [60.4311, 35.8156, 0.314159, "thin"],
  [4.7553, -40.8156, 0.314159, "thin"],
  [29.6543, -6.5451, -2.827433, "thin"],
  [45.0427, 40.8156, -2.827433, "thin"],
  [-14.2658, -40.8156, 0.314159, "thin"],
  [14.2658, 40.8156, -2.827433, "thin"],
  [-45.0427, -40.8156, 0.314159, "thin"],
  [-29.6543, 6.5451, 0.314159, "thin"],
  [-14.2658, 43.9058, 0.314159, "thin"],
  [-4.7553, 40.8156, -2.827433, "thin"],
  [-60.4311, -35.8156, -2.827433, "thin"],
  [-60.4311, 6.5451, 0.314159, "thin"],
  [-35.5321, 40.8156, -2.827433, "thin"],
  [37.3485, 59.4959, -0.942478, "fat"],
  [52.7369, 38.3156, -0.942478, "fat"],
  [58.6147, 38.3156, 0.942478, "fat"],
  [2.9389, 56.4058, 0.942478, "thin"],
  [2.9389, 64.4959, 2.199115, "fat"],
  [21.9601, 38.3156, -0.942478, "fat"],
  [43.2263, 27.1353, 0.942478, "fat"],
  [43.2263, 35.2254, 2.199115, "fat"],
  [68.1253, 9.0451, 0.942478, "thin"],
  [68.1253, 17.1353, 2.199115, "fat"],
  [-27.8379, 38.3156, -0.942478, "fat"],
  [-2.9389, 38.3156, -2.199115, "thin"],
  [-2.9389, 30.2254, -0.942478, "fat"],
  [2.9389, 30.2254, 0.942478, "fat"],
  [12.4495, 9.0451, -0.942478, "fat"],
  [18.3273, 9.0451, 0.942478, "fat"],
  [18.3273, 17.1353, 2.199115, "fat"],
  [37.3485, -9.0451, -0.942478, "fat"],
  [62.2475, -9.0451, -2.199115, "thin"],
  [62.2475, -17.1353, -0.942478, "fat"],
  [-58.6147, 38.3156, -0.942478, "fat"],
  [-37.3485, 35.2254, 2.199115, "fat"],
  [-12.4495, 9.0451, 0.942478, "fat"],
  [-2.9389, -12.1353, -0.942478, "fat"],
  [2.9389, -12.1353, 0.942478, "fat"],
  [2.9389, -4.0451, 2.199115, "fat"],
  [21.9601, -20.2254, -0.942478, "fat"],
  [46.8590, -38.3156, -0.942478, "fat"],
  [-62.2475, 9.0451, 0.942478, "thin"],
  [-62.2475, 17.1353, 2.199115, "fat"],
  [-37.3485, 9.0451, 2.199115, "fat"],
  [-21.9601, -20.2254, 0.942478, "thin"],
  [-21.9601, -12.1353, 2.199115, "fat"],
  [-2.9389, -30.2254, -2.199115, "fat"],
  [2.9389, -38.3156, 0.942478, "thin"],
  [21.9601, -46.4058, -0.942478, "fat"],
  [27.8379, -38.3156, 2.199115, "fat"],
  [-68.1253, -9.0451, -2.199115, "thin"],
  [-68.1253, -17.1353, -0.942478, "fat"],
  [-52.7369, -38.3156, -0.942478, "fat"],
  [-46.8590, -38.3156, 0.942478, "thin"],
  [-46.8590, -30.2254, 2.199115, "fat"],
  [-21.9601, -38.3156, 2.199115, "fat"],
  [-2.9389, -56.4058, -2.199115, "thin"],
  [-2.9389, -64.4959, -0.942478, "fat"],
  [-37.3485, -59.4959, 2.199115, "fat"],
  [29.6543, 61.9959, 0.314159, "thin"],
  [54.5532, 43.9058, 0.314159, "thin"],
  [12.4495, 59.4959, 0.942478, "thin"],
  [10.6331, 61.9959, -2.827433, "thin"],
  [39.1648, 32.7254, 0.314159, "thin"],
  [46.8590, 38.3156, 0.942478, "thin"],
  [14.2658, 14.6353, 0.314159, "thin"],
  [21.9601, 20.2254, 0.942478, "thin"],
  [54.5532, -14.6353, 0.314159, "thin"],
  [-27.8379, 30.2254, 0.942478, "thin"],
  [-29.6543, 32.7254, -2.827433, "thin"],
  [29.6543, -32.7254, 0.314159, "thin"],
  [-54.5532, 14.6353, -2.827433, "thin"],
  [-14.2658, -14.6353, -2.827433, "thin"],
  [10.6331, -32.7254, -2.827433, "thin"],
  [-39.1648, -32.7254, -2.827433, "thin"],
  [-12.4495, -59.4959, -2.199115, "thin"],
  [-10.6331, -61.9959, 0.314159, "thin"],
  [-58.6147, -38.3156, 0.942478, "thin"],
  [-29.6543, -61.9959, -2.827433, "thin"],
  [-14.2658, 53.9058, 0.314159, "fat"],
  [-4.7553, 24.6353, 0.314159, "fat"],
  [-54.5532, -43.9058, 0.314159, "fat"],
  [-12.4495, -9.0451, 2.199115, "fat"],
  [10.6331, -6.5451, 0.314159, "fat"],
  [12.4495, -0.9549, 2.199115, "fat"],
  [26.0216, 14.6353, 0.314159, "fat"],
  [50.9205, 32.7254, 0.314159, "fat"],
  [12.4495, -27.1353, 2.199115, "fat"],
  [21.9601, -56.4058, 2.199115, "fat"],
  [37.3485, -35.2254, 2.199115, "fat"],
]

var player_mech: CharacterBody3D
var bot_mech: CharacterBody3D

var _player: Node
var _bot_player: Node
var _match_over: bool = false
var _beacons_captured: Array[int] = [0, 0]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pause_menu.resume_requested.connect(_on_pause_resume)
	pause_menu.quit_requested.connect(_on_pause_quit)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if DEBUG_PENROSE:
		_create_walls()
		_paint_penrose_floor()
		_spawn_player_only()
		return
	_spawn_mechs()
	_create_walls()
	_create_steps()
	_create_columns()
	_create_temple_walls()
	_wire_beacons()
	_setup_players()
	match_node.match_ended.connect(_on_match_ended)
	match_node.start()
	SoundManager.play_music("arena")
	_set_mech_color(player_mech, Color(0.25, 0.52, 0.95))
	_set_mech_color(bot_mech,    Color(0.92, 0.28, 0.22))
	hud.setup(match_node, player_mech, 0)
	hud.setup_bot_bar(bot_mech)
	for weapon in player_mech.get_weapons():
		if weapon.has_signal("hit_confirmed"):
			weapon.hit_confirmed.connect(hud.register_hit)
	player_mech.damaged.connect(hud.show_damage)
	print("[Arena] Match started. Score to drain: %d" % match_node.score_limit)

func _paint_penrose_floor() -> void:
	var fat_mat := StandardMaterial3D.new()
	fat_mat.albedo_color = Color(0.40, 0.55, 0.85)
	fat_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var thin_mat := StandardMaterial3D.new()
	thin_mat.albedo_color = Color(0.95, 0.75, 0.20)
	thin_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for e in _PENROSE_EDGES:
		var mat: StandardMaterial3D = thin_mat if e[3] == "thin" else fat_mat
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.25, 0.05, 10.0)
		mi.mesh = mesh
		mi.position = Vector3(e[0], 0.03, e[1])
		mi.rotation.y = PI / 2.0 - e[2]
		mi.set_surface_override_material(0, mat)
		add_child(mi)

var _overhead_cam: Camera3D

func _toggle_overhead() -> void:
	if _overhead_cam == null:
		_overhead_cam = Camera3D.new()
		_overhead_cam.position = Vector3(0, 80, 0)
		_overhead_cam.rotation_degrees = Vector3(-90, 0, 0)
		_overhead_cam.far = 200.0
		add_child(_overhead_cam)
	_overhead_cam.current = not _overhead_cam.current

func _slots_with_overrides(slots: Array) -> Array:
	var overrides: Array = Game.loadout.get("weapon_overrides", [])
	if overrides.is_empty():
		return slots
	var result: Array = []
	for i in slots.size():
		if i < overrides.size() and overrides[i] != null:
			var s = slots[i].duplicate()
			s.weapon_scene = overrides[i]
			result.append(s)
		else:
			result.append(slots[i])
	return result

func _spawn_player_only() -> void:
	var mech_def = Game.loadout.get("mech_def")
	if mech_def == null:
		push_error("[Arena] No mech_def in loadout; falling back to Hippogriff")
		mech_def = load("res://resources/mechs/Hippogriff.tres")
	player_mech = mech_def.scene.instantiate()
	player_mech.name = "PlayerMech"
	player_mech.position = Vector3(0, 1.0, 0)
	player_mech.scale = Vector3.ONE * mech_def.body_scale
	player_mech.max_health = mech_def.max_health
	player_mech.base_walk_speed = mech_def.walk_speed
	player_mech.turn_acceleration = mech_def.turn_acceleration
	player_mech.leg_rotation_speed = mech_def.leg_rotation_speed
	add_child(player_mech)
	player_mech.configure_legs(mech_def.leg_hip_sweep, mech_def.leg_bob_magnitude, mech_def.leg_cycle_rate)
	player_mech.configure_weapons(_slots_with_overrides(mech_def.weapon_slots))
	player_mech.configure_abilities(mech_def.abilities)
	_set_mech_color(player_mech, Color(0.25, 0.52, 0.95))

	_player = Node.new()
	_player.set_script(load("res://scripts/Player.gd"))
	_player.name = "Player"
	_player.set("team", 0)
	add_child(_player)
	var input := Node.new()
	input.set_script(load("res://scripts/PlayerInputSource.gd"))
	_player.add_child(input)
	_player.set("input_source", input)
	var pilot := Node.new()
	pilot.set_script(load("res://scripts/Pilot.gd"))
	pilot.set("pilot_name", Game.profile.get("pilot_name", "Pilot"))
	_player.add_child(pilot)
	_player.set("pilot", pilot)
	_player.call("possess", player_mech)
	player_mech.died.connect(Callable(_player, "on_pawn_destroyed"))

func _spawn_mechs() -> void:
	var mech_def = Game.loadout.get("mech_def")
	if mech_def == null:
		push_error("[Arena] No mech_def in loadout; falling back to Hippogriff")
		mech_def = load("res://resources/mechs/Hippogriff.tres")

	player_mech = mech_def.scene.instantiate()
	player_mech.name = "PlayerMech"
	player_mech.position = Vector3(-20, 3.0, 0)
	player_mech.rotation_degrees = Vector3(0, -90, 0)
	player_mech.scale = Vector3.ONE * mech_def.body_scale
	player_mech.max_health = mech_def.max_health
	player_mech.base_walk_speed = mech_def.walk_speed
	player_mech.turn_acceleration = mech_def.turn_acceleration
	player_mech.leg_rotation_speed = mech_def.leg_rotation_speed
	add_child(player_mech)
	player_mech.configure_legs(mech_def.leg_hip_sweep, mech_def.leg_bob_magnitude, mech_def.leg_cycle_rate)
	player_mech.configure_shield(mech_def.has_shields, mech_def.shield_max_hp)
	player_mech.configure_energy_shield(mech_def.has_energy_shield, mech_def.energy_shield_max_hp, mech_def.energy_shield_regen_rate, mech_def.energy_shield_regen_delay)
	player_mech.configure_weapons(_slots_with_overrides(mech_def.weapon_slots))
	player_mech.configure_abilities(mech_def.abilities)

	var bot_def = Game.loadout.get("bot_def")
	if bot_def == null:
		push_error("[Arena] No bot_def in loadout; falling back to Hippogriff")
		bot_def = load("res://resources/mechs/Hippogriff.tres")
	bot_mech = bot_def.scene.instantiate()
	bot_mech.name = "BotMech"
	bot_mech.position = Vector3(20, 3.0, 0)
	bot_mech.team = 1
	bot_mech.scale = Vector3.ONE * bot_def.body_scale
	bot_mech.max_health = bot_def.max_health
	bot_mech.base_walk_speed = bot_def.walk_speed
	bot_mech.turn_acceleration = bot_def.turn_acceleration
	bot_mech.leg_rotation_speed = bot_def.leg_rotation_speed
	add_child(bot_mech)
	bot_mech.configure_legs(bot_def.leg_hip_sweep, bot_def.leg_bob_magnitude, bot_def.leg_cycle_rate)
	bot_mech.configure_shield(bot_def.has_shields, bot_def.shield_max_hp)
	bot_mech.configure_energy_shield(bot_def.has_energy_shield, bot_def.energy_shield_max_hp, bot_def.energy_shield_regen_rate, bot_def.energy_shield_regen_delay)
	bot_mech.configure_weapons(bot_def.weapon_slots)
	bot_mech.configure_abilities(bot_def.abilities)

func _create_steps() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.82, 0.90, 1)
	mat.roughness = 0.65
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	const STEP_H := 0.35
	# Bowl/amphitheater: outer ring highest, center (r<7) is arena floor.
	# Each pentagon ring: [r_outer, r_inner, top_y]
	var rings: Array = [
		[40.0, 28.0, STEP_H * 4.0],
		[28.0, 18.0, STEP_H * 3.0],
		[18.0, 12.0, STEP_H * 2.0],
		[12.0,  7.0, STEP_H * 1.0],
	]
	for ring in rings:
		_place_pent_ring(ring[0], ring[1], ring[2], mat)

func _place_pent_ring(r_out: float, r_in: float, top: float, mat: StandardMaterial3D) -> void:
	var faces := PackedVector3Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(5):
		var a0 := PI / 2.0 + float(i) * 2.0 * PI / 5.0
		var a1 := PI / 2.0 + float(i + 1) * 2.0 * PI / 5.0

		var oc_t := Vector3(cos(a0) * r_out, top, sin(a0) * r_out)
		var on_t := Vector3(cos(a1) * r_out, top, sin(a1) * r_out)
		var oc_b := Vector3(cos(a0) * r_out, 0.0, sin(a0) * r_out)
		var on_b := Vector3(cos(a1) * r_out, 0.0, sin(a1) * r_out)
		var ic_t := Vector3(cos(a0) * r_in,  top, sin(a0) * r_in)
		var in_t := Vector3(cos(a1) * r_in,  top, sin(a1) * r_in)
		var ic_b := Vector3(cos(a0) * r_in,  0.0, sin(a0) * r_in)
		var in_b := Vector3(cos(a1) * r_in,  0.0, sin(a1) * r_in)

		for tri: Array in [
			# Top face (ring segment)
			[oc_t, on_t, in_t], [oc_t, in_t, ic_t],
			# Outer wall
			[oc_b, oc_t, on_t], [oc_b, on_t, on_b],
			# Inner wall
			[ic_b, in_t, ic_t], [ic_b, in_b, in_t],
		]:
			var a: Vector3 = tri[0]; var b: Vector3 = tri[1]; var c: Vector3 = tri[2]
			var n := (b - a).cross(c - a).normalized()
			st.set_normal(n); st.add_vertex(a)
			st.set_normal(n); st.add_vertex(b)
			st.set_normal(n); st.add_vertex(c)
			faces.append(a); faces.append(b); faces.append(c)

	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.set_surface_override_material(0, mat)
	body.add_child(mi)
	add_child(body)

func _create_walls() -> void:
	# Invisible boundary walls at the floor edge (±75m). 10m tall so nothing flies over.
	var walls := [
		[Vector3(  0, 5,  75), Vector3(150, 10, 1)],
		[Vector3(  0, 5, -75), Vector3(150, 10, 1)],
		[Vector3( 75, 5,   0), Vector3(1, 10, 150)],
		[Vector3(-75, 5,   0), Vector3(1, 10, 150)],
	]
	for w in walls:
		var body := StaticBody3D.new()
		body.position = w[0]
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = w[1]
		col.shape = shape
		body.add_child(col)
		add_child(body)

func _set_mech_color(mech: Node3D, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.3
	var leg_mat := StandardMaterial3D.new()
	leg_mat.albedo_color = color.darkened(0.2)
	leg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	leg_mat.emission_enabled = true
	leg_mat.emission = color.darkened(0.2)
	leg_mat.emission_energy_multiplier = 0.3
	var torso := mech.get_node_or_null("Torso")
	if torso:
		for mesh in torso.find_children("*", "MeshInstance3D", true, false):
			mesh.set_surface_override_material(0, mat)
	var legs := mech.get_node_or_null("Legs")
	if legs:
		for mesh in legs.find_children("*", "MeshInstance3D", true, false):
			mesh.set_surface_override_material(0, leg_mat)

func _create_columns() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.88, 0.90, 0.95, 1)
	mat.roughness = 0.3
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	for p in _PENROSE_VERTS:
		if p.length() <= 32.0:
			_place_column(p.x, p.y, mat)

func _place_column(x: float, z: float, mat: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(x, 0.0, z)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.24
	shape.height = 5.0
	col.position = Vector3(0, 2.5, 0)
	col.shape = shape
	body.add_child(col)

	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.20
	mesh.bottom_radius = 0.26
	mesh.height = 5.0
	mi.mesh = mesh
	mi.position = Vector3(0, 2.5, 0)
	mi.set_surface_override_material(0, mat)
	body.add_child(mi)

	add_child(body)

func _create_temple_walls() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.68, 0.80, 1)
	mat.roughness = 0.85
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	const H := 3.2
	const T := 0.4
	const L := 10.0

	for e in _PENROSE_EDGES:
		if e[3] != "thin":
			continue
		if Vector2(e[0], e[1]).length() > 30.0:
			continue
		var cx: float = e[0]
		var cz: float = e[1]
		var rot: float = PI / 2.0 - e[2]
		var body := StaticBody3D.new()
		body.position = Vector3(cx, 0.0, cz)
		body.rotation.y = rot

		var sz := Vector3(T, H, L)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = sz
		col.position = Vector3(0, H * 0.5, 0)
		col.shape = shape
		body.add_child(col)

		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = sz
		mi.mesh = mesh
		mi.position = Vector3(0, H * 0.5, 0)
		mi.set_surface_override_material(0, mat)
		body.add_child(mi)

		add_child(body)

func _wire_beacons() -> void:
	for child in get_children():
		if child.is_in_group("beacons"):
			match_node.register_beacon(child)
			child.captured.connect(func(team: int): _beacons_captured[team] += 1)

func _setup_players() -> void:
	# Human player
	_player = Node.new()
	_player.set_script(load("res://scripts/Player.gd"))
	_player.name = "Player"
	_player.set("team", 0)
	add_child(_player)

	var input := Node.new()
	input.set_script(load("res://scripts/PlayerInputSource.gd"))
	_player.add_child(input)
	_player.set("input_source", input)

	var pilot := Node.new()
	pilot.set_script(load("res://scripts/Pilot.gd"))
	pilot.set("pilot_name", Game.profile.get("pilot_name", "Pilot"))
	_player.add_child(pilot)
	_player.set("pilot", pilot)

	_player.call("possess", player_mech)
	player_mech.died.connect(Callable(_player, "on_pawn_destroyed"))

	# Bot player
	_bot_player = Node.new()
	_bot_player.set_script(load("res://scripts/Player.gd"))
	_bot_player.name = "BotPlayer"
	_bot_player.set("team", 1)
	add_child(_bot_player)

	var ai_input := Node.new()
	ai_input.set_script(load("res://scripts/AIInputSource.gd"))
	_bot_player.add_child(ai_input)
	_bot_player.set("input_source", ai_input)

	_bot_player.call("possess", bot_mech)
	bot_mech.died.connect(Callable(_bot_player, "on_pawn_destroyed"))

func _input(event: InputEvent) -> void:
	if DEBUG_PENROSE and event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		_toggle_overhead()
		return
	if event.is_action_pressed("ui_cancel") and not _match_over:
		_toggle_pause()

func _toggle_pause() -> void:
	if get_tree().paused:
		_on_pause_resume()
	else:
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		pause_menu.show()

func _on_pause_resume() -> void:
	pause_menu.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_pause_quit() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/ui/Hangar.tscn")

func on_player_eliminated(p: Node) -> void:
	var losing_team: int = p.get("team") if p.get("team") != null else 0
	match_node.force_end(1 - losing_team)
	print("[Arena] Player eliminated." if p == _player else "[Arena] Bot eliminated.")

func _on_match_ended(winning_team: int) -> void:
	_match_over = true
	SoundManager.stop_music()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player_team: int = _player.get("team") if _player != null else 0
	var stats := {
		"damage_dealt":       bot_mech.damage_taken_total if is_instance_valid(bot_mech) else 0.0,
		"damage_taken":       player_mech.damage_taken_total if is_instance_valid(player_mech) else 0.0,
		"beacons_captured":   _beacons_captured[player_team],
		"bot_beacons":        _beacons_captured[1 - player_team],
	}
	if is_instance_valid(player_mech):
		player_mech.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(bot_mech):
		bot_mech.process_mode = Node.PROCESS_MODE_DISABLED
	hud.show_result(winning_team, stats)
	if winning_team == 0:
		Game.profile["wins"] = Game.profile.get("wins", 0) + 1
	else:
		Game.profile["losses"] = Game.profile.get("losses", 0) + 1
	Game.save_profile()
	print("[Arena] Match over. Team %d wins." % winning_team)
