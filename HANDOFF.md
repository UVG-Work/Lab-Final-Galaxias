# Handoff — Lab Final CC3069 "Galaxia en colisión"

Fecha: 2026-11-11. Enunciado: `Laboratorio_Final_CC3069_Galaxia_en_colision.pdf`. Kit oficial: `kit_galaxia/` (extraído de `kit_galaxia.zip`, no modificar `kit_galaxia/datos/`).

## Estado

- **No hay código todavía.** Solo se leyeron el PDF y el kit, y se revisó la máquina.
- **No se ha corrido nada**, así que las 9 predicciones de la hoja siguen limpias. Escríbanlas **antes** de ejecutar: una predicción escrita después vale cero.

## Máquina (verificado)

| | |
|---|---|
| GPU | RTX 5070 Laptop, 8 GB, compute capability **12.0** → compilar con `-arch=sm_120` |
| CUDA | nvcc 13.4 |
| Potencia | `nvidia-smi --query-gpu=power.draw` **sí reporta** (37.85 W en reposo, máximo 115 W), así que `--energia` debería andar sin `--tdp`. Si fallara: `--tdp 115`. |
| Python | `python3` = 3.14, `python` = 3.10. El script solo usa la librería estándar. |

Sin verificar: en Windows el binario será `galaxia.exe`; falta confirmar que `verificar_y_medir.py ./galaxia` lo encuentra (si no, pasar `./galaxia.exe`).

## Contrato del kit (resumen del `kit_galaxia/README.md`)

- **Comando:** `./galaxia <entrada.bin> <salida.bin> <pasos>`.
- **Archivo:** sin encabezado; 7 `float` LE por estrella (`x,y,z,vx,vy,vz,m`), 28 bytes. N = tamaño / 28. La salida conserva el mismo formato y el mismo orden.
- **Física:** `d = r_j - r_i`, `r2 = |d|² + EPS2`, `a_i = G · Σ_j m_j · d / (r2 · sqrt(r2))`, sumando **todas** las j, incluida `j = i` (aporta 0).
- **Integración:** primero las aceleraciones de **todas** las estrellas con las posiciones actuales; después `v += a·DT` y luego `r += v·DT` con la `v` ya nueva.
- **Precisión:** `float` y las constantes de `kit_galaxia/parametros.h` (`G_CONST=1`, `DT=0.02`, `EPS2=0.0025`).
- **Tiempo:** imprimir `KERNEL_MS=<ms>`, el total de kernel sobre todos los pasos medido con `cudaEvent`, **sin** `cudaMemcpy`. Se puede imprimir también `MEMCPY_MS=` (el CLAUDE.md lo exige).
- **Correctitud:** máxima distancia de posición contra la referencia < 10⁻³ (una versión correcta da ~10⁻⁵). Saltarse un bloque de 256 estrellas ya rompe la tolerancia.

Comandos:

```bash
python3 kit_galaxia/verificar_y_medir.py ./galaxia --equipo "Nombre" --n 4096    # Fase 1
python3 kit_galaxia/verificar_y_medir.py ./galaxia --equipo "Nombre"             # Gran Premio, N=32768
python3 kit_galaxia/verificar_y_medir.py ./galaxia --equipo "Nombre" --energia   # Gran Premio Verde
```

## Decisiones abiertas (la entrevista quedó aquí)

1. **¿El lab se hace ahora, en vivo (90 min, en clase)?** Está planteado así. Respuesta pendiente.
2. **¿Solo o en grupo de 3?** Hay que asignar Piloto, Científico y Auditor (rotan en la Fase 4), y la Fase 4 necesita un equipo vecino para intercambiar máquina.
3. Nombre del equipo (lo usa el script) y la **regla propia** del CLAUDE.md.
4. Frames del GIF: recomendación, que sean opcionales (por ejemplo un 4.º argumento) para que el benchmark no escriba imágenes ni haga copias extra.

## Orden recomendado

1. **Fase 0:** crear `CLAUDE.md` con las 4 reglas obligatorias (comentario en español en cada cálculo de índice; versión CPU de referencia que imprima el error máximo GPU vs CPU; kernel y `cudaMemcpy` medidos por separado con `cudaEvent`; prohibido Thrust/cuBLAS), la regla propia y una referencia a `kit_galaxia/README.md`. Abrir `bitacora.md` desde ya.
2. Llenar las predicciones #1 y #2 de la hoja (página 7 del PDF) **antes** de compilar nada.
3. **Fase 1:** `galaxia.cu` ingenuo, un hilo por estrella, más la versión CPU. Verificar con `--n 4096`.
4. **Fase 2:** experimentos A (tamaño de bloque, N = 16384), B (escalamiento, N de 1024 a 65536) y C (suma de vectores contra N-body, % de memcpy). Cada uno sigue el ciclo predicción → medición → explicación y lleva tabla y gráfica.
5. **Fase 3:** versión con tiling en `__shared__` y dos `__syncthreads()`; error contra la ingenua < 10⁻³.
6. **Fase 4:** `sabotaje.cu` con un solo bug sutil, y la solución en papel.
7. **Fase 5:** Gran Premio y Gran Premio Verde.

## Trampas conocidas

- **Bitácora:** se escribe en el momento, no al final, y debe coincidir con el historial. Al cerrar, `/export` de Claude Code → `prompts.md`.
- **Requisitos de la bitácora:** al menos una entrada por fase (0 a 5), al menos 2 casos de rechazo o corrección con una razón técnica, y el "prompt de oro".
- **Prueba de la línea:** −5 por cada línea del kernel que nadie del grupo sepa explicar.
- **Temperatura:** la GPU es de laptop. Si el Gran Premio se corre justo después de los experimentos, sale con la GPU caliente y peores números (en el proyecto anterior la misma máquina dio 3x de diferencia por throttling). Hay que dejarla enfriar unos minutos.
- **OneDrive:** el repo vive dentro de OneDrive y la sincronización de `.exe` nuevos perturba las mediciones. Pausarla al medir, y cerrar juegos y launchers.
