# Arma galaxia.gif con los frames PPM que escribe:  galaxia.exe <entrada> <salida> <pasos> --frames K
# Uso: python hacer_gif.py [ms_por_frame]
import glob
import sys

from PIL import Image

rutas = sorted(glob.glob("frames/frame_*.ppm"))
if not rutas:
    sys.exit("No hay frames en frames/: corran primero galaxia.exe ... --frames K")
ms = int(sys.argv[1]) if len(sys.argv) > 1 else 50
frames = [Image.open(r) for r in rutas]
frames[0].save("galaxia.gif", save_all=True, append_images=frames[1:], duration=ms, loop=0)
print(f"galaxia.gif: {len(frames)} frames, {ms} ms por frame")
