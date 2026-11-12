# CLAUDE.md — Lab Final CC3069 "Galaxia en colisión"

Equipo: **(pendiente)** · Piloto: June Herrera · Científico: Andrés Mazariegos · Auditor: Jonathan Zacarías
(Los roles rotan en la Fase 4: el Auditor pasa a Piloto.)

El contrato de entrada/salida, la física y la medición están en `kit_galaxia/README.md`. **Cumplirlo es obligatorio**; ante cualquier duda, manda el README sobre este archivo. No modificar nada en `kit_galaxia/datos/`.

## Reglas obligatorias

1. **Índices comentados.** Todo cálculo de índice lleva un comentario en español que explique qué estrella o qué posición representa (por ejemplo `// i: estrella global que calcula este hilo`).
2. **Versión CPU de referencia siempre.** Todo programa N-body tiene una versión CPU equivalente, y cada ejecución imprime `ERROR_GPU_CPU=<máxima distancia de posición>`. Para N grande, la comparación CPU puede limitarse a los primeros pasos o a un subconjunto de estrellas, pero eso se imprime explícitamente.
3. **Kernel y `cudaMemcpy` medidos por separado con `cudaEvent`.** Se imprime `KERNEL_MS=` (total de kernel sobre todos los pasos, sin copias) y `MEMCPY_MS=` (total de copias H2D + D2H).
4. **Prohibido Thrust, cuBLAS, CUB o cualquier librería que esconda el kernel.** Solo CUDA runtime y C/C++ estándar.

## Regla propia del equipo

5. **Predicción antes de ejecución.** Claude no compila para medir ni ejecuta ningún experimento o benchmark hasta que el Científico confirme en el chat que la predicción correspondiente ya está escrita en `predicciones.md`. Compilar para revisar errores de sintaxis sí está permitido.

## Convenciones del proyecto

- **Compilar:** `nvcc -O3 -arch=sm_120 -o galaxia galaxia.cu` (RTX 5070 Laptop, compute capability 12.0, CUDA 13.4). En Windows sale `galaxia.exe`.
- **Python:** usar `python` (3.12). `python3` no existe en PowerShell.
- **Verificar:** `python kit_galaxia/verificar_y_medir.py ./galaxia.exe --equipo "<equipo>" --n 4096`.
- **Línea de comandos:** `galaxia <entrada.bin> <salida.bin> <pasos> [--kernel ingenuo|tiling] [--bloque B] [--frames K] [--cpu-pasos P] [--vs-ingenuo]` y `galaxia --generar <N> <salida.bin>`. Todo lo opcional va con flags. Sin flags, el programa no escribe imágenes ni hace copias extra (así lo corre el benchmark oficial).
- **Verificación CPU por defecto:** completa si N²·pasos ≤ 4e9; si no, solo el paso 1 con una muestra de 1024 estrellas. Así no tarda minutos ni diluye la potencia promedio del Gran Premio Verde.
- **Física:** `float`, las constantes de `kit_galaxia/parametros.h` (`#include` del archivo, sin copiar los valores). Primero se calculan las aceleraciones de todas las estrellas y después `v += a·DT` y `r += v·DT` con la `v` nueva. La suma incluye `j = i`.
- **Comentarios y mensajes** en español.
- Cada kernel tiene que poder explicarse línea por línea (prueba de la línea, −5 por línea sin explicar): nada de trucos que el equipo no pueda defender.

## Archivos

| Archivo | Contenido |
|---|---|
| `galaxia.cu` | Kernel ingenuo (Fase 1) y con tiling en `__shared__` (Fase 3), con la versión CPU |
| `sabotaje.cu` | Copia con un solo bug sutil (Fase 4) |
| `suma_vectores.cu` | Experimento C |
| `bitacora.md` | Bitácora de prompts; se llena **en el momento** |
| `predicciones.md` | Hoja de predicciones; la columna de predicción se llena **antes** de ejecutar |
| `experimentos/` | Tablas (CSV) y gráficas de la Fase 2 |

## Mediciones

- Antes de medir: pausar OneDrive, cerrar juegos y launchers, dejar enfriar la GPU unos minutos (es una GPU de laptop y el throttling puede dar 3x de diferencia).
- Repetir cada medición al menos 3 veces y reportar la mediana.
