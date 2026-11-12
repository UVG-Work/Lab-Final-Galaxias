# Handoff — Lab Final CC3069 "Galaxia en colisión"

Actualizado: 2026-11-11, durante el lab en vivo, al pasar a la Fase 4 (caza).
Enunciado: `Laboratorio_Final_CC3069_Galaxia_en_colision.pdf`. Kit: `kit_galaxia/` (no modificar `kit_galaxia/datos/`).

**Equipo:** nombre **pendiente** (lo pide `verificar_y_medir.py --equipo`). Piloto: June Herrera · Científico: Andrés Mazariegos · Auditor: Jonathan Zacarías. En la Fase 4 rotan: Jonathan pasa a Piloto.

## Estado por fase

| Fase | Estado | Resultado clave |
|---|---|---|
| 0 | Hecha | `CLAUDE.md` con las 4 reglas + la regla propia (Claude no ejecuta experimentos hasta que el Científico confirme la predicción escrita) |
| 1 | Hecha | Kernel ingenuo. Kit N = 4,096: error 9.8e-07, PASA. Speedup ~60x (51x a 78x), memcpy ~3.7 %. Predicciones a mano: 30x y 10 % |
| 2 | Hecha | A: de 32 a 512 hilos empatan (~22.4 ms), 1,024 es 17 % más lento. B: CPU ≈ N²; GPU casi lineal hasta 16,384, ×9.4 al pasar a 65,536. C: suma de vectores 97 % en memcpy (pierde contra la CPU, 0.4x); N-body 4.6 % a 0.45 % |
| 3 | Hecha | Tiling: 1.66x (4,096), 1.57x (16,384), 1.07x (32,768), 1.18x (65,536). Error contra el ingenuo = 0 (bit a bit idéntico) |
| 4 | **En curso** | Bug plantado en `sabotaje.cu`. **La solución está SOLO en el papel entregado al catedrático** (no se escribe aquí: el equipo cazador usa esta laptop). Falta: cazar el bug del equipo vecino, sin IA |
| 5 | Pendiente | Ver abajo |
| Reflexión | Pendiente | Individual, 5 preguntas (página 5 del PDF) |

Tablas y gráficas en `experimentos/`. Mediciones crudas de la Fase 1 en `experimentos/fase1_n4096.md`.

## Pendientes, en orden

1. **Antes de cerrar esta sesión: `/export` → `prompts.md`.** Es un entregable: el historial completo de Claude Code.
2. **Fase 4, caza:** hipótesis escrita sin IA (línea, tipo de bug y por qué causa el síntoma). Después se puede usar Claude para confirmar y corregir. Guardar la hipótesis y la corrección para el "reporte de sabotaje" (entregable 5).
3. **Después de la caza:** completar la entrada 11 de `bitacora.md` con la solución del bug propio, y hacer commit de `sabotaje.cu` y `cazar_sabotaje.bat`. **No se subieron a GitHub a propósito.**
4. **Fase 5, Gran Premio:**
   - Andrés escribe a mano las predicciones **#8** (inter/s) y **#9** (inter/J) **antes** de correr.
   - ~~Cambiar el kernel por defecto de `galaxia.cu` a `tiling`~~ **Hecho**: sin flags corre `tiling`; `--kernel ingenuo` sigue disponible.
   - Opcional: optimizar (por ejemplo `rsqrtf`, `#pragma unroll`, otro tamaño de tile), siempre con error < 1e-3 contra la referencia del kit. Hoy el tiling da ~2.4e11 inter/s con N = 32,768.
   - Antes de medir: dejar enfriar la GPU, pausar OneDrive y cerrar launchers.
   - `python kit_galaxia/verificar_y_medir.py ./galaxia.exe --equipo "<nombre>"` y luego lo mismo con `--energia`. Anotar en la tabla del pizarrón.
5. **GIF: hecho.** `galaxia.gif` = condiciones oficiales de 32,768, 800 pasos, un frame cada 4 (201 frames, 5.3 MB). Para rehacerlo: `galaxia.exe kit_galaxia\datos\condiciones_32768.bin salida_gif.bin 800 --frames 4` y luego `python hacer_gif.py 40` (ms por frame). El choque ocurre en los primeros ~600 pasos; con más pasos solo se agrega una bola fusionada.
6. **Bitácora:** June llena las columnas Decisión y Por qué de las entradas 1 a 11, marca al menos 2 casos de corrección o rechazo (candidatas: la #6, donde Claude corrigió el eje Y de la gráfica A; y la #4, el diagnóstico de Smart App Control) y elige el **prompt de oro**.
7. **Hoja de predicciones en papel:** columnas Medido y "¿Por qué la diferencia?" de la #1 a la #7. Transcribir a `predicciones.md` si sirve. Entregar una foto o escaneo.
8. **Preguntas de validación** de las Fases 1, 2 y 3. Las de la Fase 3 las responde Jonathan **sin IA**.
9. **Entrega (.zip):** `CLAUDE.md`, `galaxia.cu`, `sabotaje.cu`, `prompts.md`, `bitacora.md`, hoja de predicciones, tablas y gráficas de la Fase 2, GIF, reporte de sabotaje, respuestas de validación y reflexiones individuales.

## Máquina

| | |
|---|---|
| GPU | RTX 5070 Laptop, 8 GB, cc 12.0, **36 SMs**, 1,536 hilos/SM, 24 bloques/SM, 48 KB de shared por bloque, 32 MB de L2 |
| Compilar | `nvcc -O3 -arch=sm_120 -o galaxia galaxia.cu` (nvcc 13.4, MSVC 14.51) |
| Python | `python` (3.12), con matplotlib, numpy y Pillow. **`python3` no existe en PowerShell** |
| Script del kit | Pasar `./galaxia.exe` (con `.exe`) |
| Smart App Control | **Desactivado** (bloqueaba los `.exe` sin firma con `WinError 4551`) |
| Potencia | `nvidia-smi` reporta `power.draw`; `power.limit` = N/A |

## Comandos útiles

```
galaxia.exe <entrada.bin> <salida.bin> <pasos> [--kernel ingenuo|tiling] [--bloque B] [--frames K] [--cpu-pasos P] [--vs-ingenuo]
galaxia.exe --generar <N> <salida.bin>
python experimentos.py A|B|C|T
```
