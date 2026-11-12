#!/usr/bin/env python3
"""
Kit oficial - Laboratorio Final CC3069 "Galaxia en colisión"

Verifica la correctitud de su programa contra la referencia oficial y mide
el resultado para el Gran Premio (interacciones por segundo) y, opcionalmente,
para el Gran Premio Verde (interacciones por joule).

Uso:
    python3 verificar_y_medir.py ./galaxia --equipo "Nombre"
    python3 verificar_y_medir.py ./galaxia --equipo "Nombre" --n 4096
    python3 verificar_y_medir.py ./galaxia --equipo "Nombre" --energia
    python3 verificar_y_medir.py ./galaxia --equipo "Nombre" --energia --tdp 115

Solo usa la librería estándar de Python 3.
"""
import argparse
import array
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time

TOLERANCIA = 1e-3
PASOS_VERIFICACION = 10
AQUI = os.path.dirname(os.path.abspath(__file__))


def leer_bin(ruta):
    datos = array.array("f")
    with open(ruta, "rb") as f:
        datos.frombytes(f.read())
    if sys.byteorder != "little":
        datos.byteswap()
    if len(datos) % 7 != 0:
        raise ValueError(f"{ruta}: el tamaño no es múltiplo de 28 bytes (7 floats por estrella)")
    return datos


def error_maximo(salida, referencia):
    """Máxima distancia euclidiana entre la posición calculada y la de referencia."""
    peor, idx = 0.0, -1
    for i in range(len(referencia) // 7):
        b = i * 7
        dx = salida[b] - referencia[b]
        dy = salida[b + 1] - referencia[b + 1]
        dz = salida[b + 2] - referencia[b + 2]
        d = (dx * dx + dy * dy + dz * dz) ** 0.5
        if d != d:  # NaN
            return float("nan"), i
        if d > peor:
            peor, idx = d, i
    return peor, idx


def correr(exe, entrada, salida, pasos, timeout):
    t0 = time.time()
    p = subprocess.run([exe, entrada, salida, str(pasos)],
                       capture_output=True, text=True, timeout=timeout)
    pared = time.time() - t0
    if p.returncode != 0:
        print(p.stdout)
        print(p.stderr, file=sys.stderr)
        sys.exit(f"ERROR: el programa terminó con código {p.returncode}.")
    m = re.search(r"KERNEL_MS\s*=\s*([0-9.eE+-]+)", p.stdout)
    if not m:
        print(p.stdout)
        sys.exit("ERROR: el programa no imprimió la línea KERNEL_MS=<milisegundos>. Revisen el README.")
    return float(m.group(1)), pared


class MedidorPotencia:
    """Lee nvidia-smi cada 100 ms en segundo plano."""

    def __init__(self):
        self.muestras = []
        self.proc = None
        self.hilo = None

    def iniciar(self):
        if shutil.which("nvidia-smi") is None:
            return False
        self.proc = subprocess.Popen(
            ["nvidia-smi", "--query-gpu=power.draw", "--format=csv,noheader,nounits", "-lms", "100"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        self.hilo = threading.Thread(target=self._leer, daemon=True)
        self.hilo.start()
        return True

    def _leer(self):
        for linea in self.proc.stdout:
            try:
                self.muestras.append(float(linea.strip().split(",")[0]))
            except ValueError:
                pass  # "[N/A]" u otra cosa no numérica

    def detener(self):
        if self.proc:
            self.proc.terminate()
            self.proc.wait()

    def promedio(self):
        return sum(self.muestras) / len(self.muestras) if self.muestras else None


def main():
    ap = argparse.ArgumentParser(description="Verificación y benchmark oficial - Galaxia en colisión")
    ap.add_argument("exe", help="ruta a su ejecutable, por ejemplo ./galaxia")
    ap.add_argument("--equipo", required=True, help="nombre del equipo")
    ap.add_argument("--n", type=int, default=32768, choices=[4096, 32768],
                    help="tamaño del caso (4096 para pruebas rápidas, 32768 es el oficial)")
    ap.add_argument("--energia", action="store_true", help="medir también interacciones por joule")
    ap.add_argument("--pasos-energia", type=int, default=100)
    ap.add_argument("--tdp", type=float, default=None,
                    help="potencia en W a usar si nvidia-smi no reporta potencia")
    ap.add_argument("--timeout", type=int, default=600)
    a = ap.parse_args()

    exe = os.path.abspath(a.exe)
    entrada = os.path.join(AQUI, "datos", f"condiciones_{a.n}.bin")
    ref = os.path.join(AQUI, "datos", f"referencia_{a.n}.bin")
    n = a.n
    tmp = tempfile.mkdtemp(prefix="galaxia_")
    salida = os.path.join(tmp, "salida.bin")

    print(f"== Verificación: N = {n}, {PASOS_VERIFICACION} pasos ==")
    ms, _ = correr(exe, entrada, salida, PASOS_VERIFICACION, a.timeout)
    out = leer_bin(salida)
    referencia = leer_bin(ref)
    if len(out) != len(referencia):
        sys.exit(f"ERROR: la salida tiene {len(out)//7} estrellas y la referencia {n}.")
    err, idx = error_maximo(out, referencia)
    pasa = err == err and err < TOLERANCIA
    inter_s = n * n * PASOS_VERIFICACION / (ms / 1000.0) if ms > 0 else float("inf")
    print(f"Error máximo de posición: {err:.3e} (estrella {idx})  tolerancia {TOLERANCIA:.0e}")
    print(f"Correctitud: {'PASA' if pasa else 'NO PASA'}")
    print(f"Tiempo de kernel: {ms:.2f} ms")
    print(f"Interacciones por segundo: {inter_s:.3e}")

    inter_j = None
    fuente = ""
    if a.energia:
        print(f"\n== Energía: N = {n}, {a.pasos_energia} pasos ==")
        med = MedidorPotencia()
        hay_smi = med.iniciar()
        time.sleep(0.3)
        ms_e, _ = correr(exe, entrada, salida, a.pasos_energia, a.timeout)
        time.sleep(0.2)
        med.detener()
        potencia = med.promedio()
        if potencia is not None:
            fuente = f"nvidia-smi, {len(med.muestras)} muestras"
        elif a.tdp:
            potencia, fuente = a.tdp, "TDP declarado"
        else:
            msg = "nvidia-smi no está disponible" if not hay_smi else "nvidia-smi no reporta potencia"
            sys.exit(f"ERROR: {msg}. Vuelvan a correr con --tdp <W> usando el TDP oficial de su GPU.")
        joules = potencia * ms_e / 1000.0
        inter_j = n * n * a.pasos_energia / joules
        print(f"Potencia promedio: {potencia:.1f} W ({fuente})")
        print(f"Tiempo de kernel: {ms_e:.2f} ms  ->  energía aproximada: {joules:.2f} J")
        print(f"Interacciones por joule: {inter_j:.3e}")

    print("\n== Para la tabla del pizarrón ==")
    linea = f"{a.equipo} | N={n} | error={err:.2e} | {'PASA' if pasa else 'NO PASA'} | {inter_s:.3e} inter/s"
    if inter_j is not None:
        linea += f" | {inter_j:.3e} inter/J ({fuente})"
    print(linea)
    if not pasa:
        print("Este resultado NO cuenta para el Gran Premio hasta que pase la verificación.")
    shutil.rmtree(tmp, ignore_errors=True)
    sys.exit(0 if pasa else 1)


if __name__ == "__main__":
    main()
