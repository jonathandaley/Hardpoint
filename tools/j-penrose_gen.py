from pynrose import Tiling, Grid, Vector

tiling = Tiling(seed=2)
grid = Grid(Vector(0, 0), Vector(30, 30))
rhombii = list(tiling.rhombii(grid))
tiling.save_svg('penrose-sun_02.svg', rhombii=rhombii)
print("Saved")
