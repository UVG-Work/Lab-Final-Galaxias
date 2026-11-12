"""
Fase 2 — Experimentos A, B y C del Lab Final CC3069.

Uso:  python experimentos.py A      (tamaño de bloque, N = 16,384)
      python experimentos.py B      (escalamiento CPU vs GPU, N = 1,024 ... 65,536)
      python experimentos.py C      (suma de vectores vs N-body, % de cudaMemcpy)
      python experimentos.py T      (Fase 3: kernel ingenuo vs tiling)

Cada medición se repite 3 veces y se reporta la mediana.
Salidas: experimentos/expX.csv y experimentos/expX.png
"""
import csv
import os
import re
import statistics
import subprocess
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

AQUI = os.path.dirname(os.path.abspath(__file__))
GALAXIA = os.path.join(AQUI, "galaxia.exe")
SUMA = os.path.join(AQUI, "suma_vectores.exe")
DATOS = os.path.join(AQUI, "datos_generados")
SALIDA_TMP = os.path.join(DATOS, "salida_tmp.bin")
DIR_EXP = os.path.join(AQUI, "experimentos")
REPETICIONES = 3
PASOS = 10


def correr(args):
    p = subprocess.run(args, capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit(f"Falló {' '.join(args)}:\n{p.stdout}\n{p.stderr}")
    valores = {}
    for clave, valor in re.findall(r"^([A-Z_]+)=([-0-9.eE+]+)", p.stdout, re.M):
        valores[clave] = float(valor)
    return valores


def condiciones(n):
    """Archivo de condiciones iniciales con N estrellas (se genera una sola vez)."""
    os.makedirs(DATOS, exist_ok=True)
    ruta = os.path.join(DATOS, f"condiciones_{n}.bin")
    if not os.path.exists(ruta):
        subprocess.run([GALAXIA, "--generar", str(n), ruta], check=True, capture_output=True)
    return ruta


def mediana_de(corridas, clave):
    return statistics.median(c[clave] for c in corridas)


def guardar_csv(nombre, encabezado, filas):
    ruta = os.path.join(DIR_EXP, nombre)
    with open(ruta, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(encabezado)
        w.writerows(filas)
    print(f"Tabla: {ruta}")


def experimento_a():
    n = 16384
    entrada = condiciones(n)
    filas = []
    print(f"Experimento A: N = {n}, {PASOS} pasos, {REPETICIONES} repeticiones por bloque")
    print(f"{'bloque':>7} {'bloques':>8} {'kernel ms (mediana)':>20} {'corridas':>30} {'inter/s':>11}")
    for bloque in (32, 64, 128, 256, 512, 1024):
        corridas = [correr([GALAXIA, entrada, SALIDA_TMP, str(PASOS), "--bloque", str(bloque),
                            "--cpu-pasos", "1"]) for _ in range(REPETICIONES)]
        ms = mediana_de(corridas, "KERNEL_MS")
        inter = n * n * PASOS / (ms / 1000)
        todas = ", ".join(f"{c['KERNEL_MS']:.2f}" for c in corridas)
        err = max(c["ERROR_GPU_CPU"] for c in corridas)
        bloques = (n + bloque - 1) // bloque
        print(f"{bloque:>7} {bloques:>8} {ms:>20.3f} {todas:>30} {inter:>11.3e}   error {err:.1e}")
        filas.append([bloque, bloques, f"{ms:.4f}", todas, f"{inter:.4e}", f"{err:.3e}"])
    guardar_csv("expA_bloque.csv",
                ["bloque", "bloques", "kernel_ms_mediana", "corridas_ms", "interacciones_s", "error_gpu_cpu"],
                filas)

    x = [f[0] for f in filas]
    y = [float(f[2]) for f in filas]
    fig, ax = plt.subplots(figsize=(7, 4.2))
    ax.plot(x, y, "o-", color="#2a6fdb")
    for xi, yi in zip(x, y):
        ax.annotate(f"{yi:.1f}", (xi, yi), textcoords="offset points", xytext=(0, 7), ha="center", fontsize=9)
    ax.set_xscale("log", base=2)
    ax.set_xticks(x)
    ax.set_xticklabels([str(v) for v in x])
    ax.set_xlabel("Hilos por bloque")
    ax.set_ylabel("Tiempo de kernel, 10 pasos (ms)")
    ax.set_ylim(0, max(y) * 1.15)  # eje desde 0 para no exagerar diferencias pequeñas
    ax.set_title(f"Experimento A: tamaño de bloque (N = {n:,}, kernel ingenuo)")
    ax.grid(alpha=0.3)
    fig.tight_layout()
    ruta = os.path.join(DIR_EXP, "expA_bloque.png")
    fig.savefig(ruta, dpi=150)
    print(f"Gráfica: {ruta}")


def experimento_b():
    filas = []
    print(f"Experimento B: {PASOS} pasos GPU, {REPETICIONES} repeticiones por N")
    print(f"{'N':>7} {'GPU ms/paso':>12} {'CPU ms/paso':>12} {'pasos CPU':>10} {'speedup':>8} "
          f"{'x GPU':>6} {'x CPU':>6} {'% memcpy':>9}")
    previo = None
    for n in (1024, 4096, 16384, 65536):
        entrada = condiciones(n)
        # La CPU completa con N = 65,536 tardaría más de un minuto: se mide 1 paso y se reporta por paso.
        pasos_cpu = PASOS if n <= 16384 else 1
        corridas = [correr([GALAXIA, entrada, SALIDA_TMP, str(PASOS), "--cpu-pasos", str(pasos_cpu)])
                    for _ in range(REPETICIONES)]
        gpu = mediana_de(corridas, "KERNEL_MS_POR_PASO")
        cpu = mediana_de(corridas, "CPU_MS_POR_PASO")
        memcpy = mediana_de(corridas, "PORCENTAJE_MEMCPY")
        err = max(c["ERROR_GPU_CPU"] for c in corridas)
        fg = gpu / previo[0] if previo else float("nan")
        fc = cpu / previo[1] if previo else float("nan")
        print(f"{n:>7} {gpu:>12.4f} {cpu:>12.2f} {pasos_cpu:>10} {cpu / gpu:>8.1f} "
              f"{fg:>6.2f} {fc:>6.2f} {memcpy:>8.2f}%   error {err:.1e}")
        filas.append([n, f"{gpu:.5f}", f"{cpu:.3f}", pasos_cpu, f"{cpu / gpu:.2f}",
                      f"{fg:.3f}", f"{fc:.3f}", f"{memcpy:.3f}", f"{err:.3e}"])
        previo = (gpu, cpu)
    print("(x GPU / x CPU: cuántas veces creció el tiempo por paso respecto al N anterior, que es 4 veces menor)")
    guardar_csv("expB_escalamiento.csv",
                ["N", "gpu_ms_por_paso", "cpu_ms_por_paso", "pasos_cpu_medidos", "speedup",
                 "factor_gpu_vs_N_anterior", "factor_cpu_vs_N_anterior", "porcentaje_memcpy", "error_gpu_cpu"],
                filas)

    ns = [f[0] for f in filas]
    g = [float(f[1]) for f in filas]
    c = [float(f[2]) for f in filas]
    fig, ax = plt.subplots(figsize=(7, 4.5))
    ax.loglog(ns, c, "s-", color="#d9622b", label="CPU (1 hilo)")
    ax.loglog(ns, g, "o-", color="#2a6fdb", label="GPU (kernel ingenuo)")
    # Referencia O(N²) anclada al último punto de cada curva
    for serie, color in ((c, "#d9622b"), (g, "#2a6fdb")):
        ref = [serie[-1] * (n / ns[-1]) ** 2 for n in ns]
        ax.loglog(ns, ref, ":", color=color, alpha=0.6)
    ax.plot([], [], ":", color="gray", label="pendiente N² (referencia)")
    ax.set_xticks(ns)
    ax.set_xticklabels([f"{n:,}" for n in ns])
    ax.set_xlabel("N (estrellas)")
    ax.set_ylabel("Tiempo por paso (ms)")
    ax.set_title("Experimento B: escalamiento CPU vs GPU")
    ax.grid(alpha=0.3, which="both")
    ax.legend()
    fig.tight_layout()
    ruta = os.path.join(DIR_EXP, "expB_escalamiento.png")
    fig.savefig(ruta, dpi=150)
    print(f"Gráfica: {ruta}")


def experimento_c():
    filas = []
    print(f"Experimento C: % del tiempo en cudaMemcpy, {REPETICIONES} repeticiones")
    print(f"{'programa':>14} {'N':>10} {'kernel ms':>10} {'memcpy ms':>10} {'% memcpy':>9} "
          f"{'Amdahl máx':>11} {'speedup c/memcpy':>17}")
    casos = [("suma_vectores", n) for n in (1 << 20, 1 << 22, 1 << 24, 1 << 26)]
    casos += [("nbody", n) for n in (4096, 16384, 65536)]
    for programa, n in casos:
        if programa == "suma_vectores":
            corridas = [correr([SUMA, str(n)]) for _ in range(REPETICIONES)]
        else:
            corridas = [correr([GALAXIA, condiciones(n), SALIDA_TMP, str(PASOS), "--cpu-pasos", "1"])
                        for _ in range(REPETICIONES)]
        k = mediana_de(corridas, "KERNEL_MS")
        m = mediana_de(corridas, "MEMCPY_MS")
        f = m / (m + k)
        amdahl = 1 / f  # speedup máximo si el kernel tardara 0: (memcpy + kernel) / memcpy
        sp = mediana_de(corridas, "SPEEDUP_CON_MEMCPY")
        print(f"{programa:>14} {n:>10,} {k:>10.3f} {m:>10.3f} {100 * f:>8.2f}% {amdahl:>11.2f} {sp:>17.2f}")
        filas.append([programa, n, f"{k:.4f}", f"{m:.4f}", f"{100 * f:.3f}", f"{amdahl:.3f}", f"{sp:.3f}"])
    print("(Amdahl máx = speedup máximo del programa en GPU si el kernel fuera infinitamente rápido)")
    guardar_csv("expC_memcpy.csv",
                ["programa", "N", "kernel_ms", "memcpy_ms", "porcentaje_memcpy", "amdahl_speedup_max",
                 "speedup_gpu_vs_cpu_con_memcpy"], filas)

    fig, ax = plt.subplots(figsize=(8, 4.5))
    etiquetas = [("Suma\n" if f[0] == "suma_vectores" else "N-body\n") + f"N={int(f[1]):,}" for f in filas]
    valores = [float(f[4]) for f in filas]
    colores = ["#d9622b" if f[0] == "suma_vectores" else "#2a6fdb" for f in filas]
    barras = ax.bar(range(len(filas)), valores, color=colores)
    for b, v in zip(barras, valores):
        ax.annotate(f"{v:.1f}%", (b.get_x() + b.get_width() / 2, v), textcoords="offset points",
                    xytext=(0, 3), ha="center", fontsize=9)
    ax.set_xticks(range(len(filas)))
    ax.set_xticklabels(etiquetas, fontsize=8)
    ax.set_ylabel("% del tiempo en cudaMemcpy")
    ax.set_ylim(0, 105)
    ax.set_title("Experimento C: el muro de memoria (memcpy / (memcpy + kernel))")
    ax.grid(alpha=0.3, axis="y")
    fig.tight_layout()
    ruta = os.path.join(DIR_EXP, "expC_memcpy.png")
    fig.savefig(ruta, dpi=150)
    print(f"Gráfica: {ruta}")


def experimento_tiling():
    """Fase 3: kernel ingenuo vs tiling en memoria compartida, bloque 256."""
    filas = []
    print(f"Fase 3: ingenuo vs tiling, {PASOS} pasos, bloque 256, {REPETICIONES} repeticiones")
    print(f"{'N':>7} {'ingenuo ms':>11} {'tiling ms':>10} {'speedup':>8} {'error vs ingenuo':>17} {'error vs CPU':>13}")
    for n in (4096, 16384, 32768, 65536):
        entrada = (os.path.join(AQUI, "kit_galaxia", "datos", "condiciones_32768.bin") if n == 32768
                   else condiciones(n))
        base = [GALAXIA, entrada, SALIDA_TMP, str(PASOS), "--cpu-pasos", "1"]
        ing = [correr(base + ["--kernel", "ingenuo"]) for _ in range(REPETICIONES)]
        til = [correr(base + ["--kernel", "tiling", "--vs-ingenuo"]) for _ in range(REPETICIONES)]
        mi = mediana_de(ing, "KERNEL_MS")
        mt = mediana_de(til, "KERNEL_MS")
        e_ing = max(c["ERROR_VS_INGENUO"] for c in til)
        e_cpu = max(c["ERROR_GPU_CPU"] for c in til)
        print(f"{n:>7} {mi:>11.3f} {mt:>10.3f} {mi / mt:>8.3f} {e_ing:>17.2e} {e_cpu:>13.2e}")
        filas.append([n, f"{mi:.4f}", f"{mt:.4f}", f"{mi / mt:.4f}", f"{e_ing:.3e}", f"{e_cpu:.3e}",
                      ", ".join(f"{c['KERNEL_MS']:.2f}" for c in ing),
                      ", ".join(f"{c['KERNEL_MS']:.2f}" for c in til)])
    guardar_csv("fase3_tiling.csv",
                ["N", "ingenuo_ms", "tiling_ms", "speedup_tiling", "error_vs_ingenuo", "error_vs_cpu",
                 "corridas_ingenuo_ms", "corridas_tiling_ms"], filas)

    ns = [f[0] for f in filas]
    sp = [float(f[3]) for f in filas]
    fig, ax = plt.subplots(figsize=(7, 4.2))
    barras = ax.bar([f"{n:,}" for n in ns], sp, color="#2a6fdb")
    for b, v in zip(barras, sp):
        ax.annotate(f"{v:.2f}x", (b.get_x() + b.get_width() / 2, v), textcoords="offset points",
                    xytext=(0, 3), ha="center", fontsize=9)
    ax.axhline(1.0, color="gray", ls="--", lw=1)
    ax.set_ylim(0, max(sp) * 1.2)
    ax.set_xlabel("N (estrellas)")
    ax.set_ylabel("Speedup tiling vs ingenuo")
    ax.set_title("Fase 3: tiling en memoria compartida vs kernel ingenuo (bloque 256)")
    ax.grid(alpha=0.3, axis="y")
    fig.tight_layout()
    ruta = os.path.join(DIR_EXP, "fase3_tiling.png")
    fig.savefig(ruta, dpi=150)
    print(f"Gráfica: {ruta}")


if __name__ == "__main__":
    os.makedirs(DIR_EXP, exist_ok=True)
    cual = sys.argv[1].upper() if len(sys.argv) > 1 else ""
    {"A": experimento_a, "B": experimento_b, "C": experimento_c, "T": experimento_tiling}.get(
        cual, lambda: sys.exit("Uso: python experimentos.py A|B|C|T"))()
