# Hoja de predicciones

Equipo: (pendiente) · Piloto: June Herrera · Científico: Andrés Mazariegos · Auditor: Jonathan Zacarías

**La hoja oficial es la de papel** (página 7 del PDF, escrita a mano por el Científico antes de ejecutar y firmable por el catedrático). Este archivo es solo una transcripción posterior, para comparar con lo medido. Se entrega una foto o escaneo de la hoja en papel.

| # | Fase | Pregunta | Predicción (antes) | Hora | Medido | ¿Por qué la diferencia? |
|---|------|----------|--------------------|------|--------|-------------------------|
| 1 | 1 | Speedup GPU vs CPU con N = 4,096 | | | | |
| 2 | 1 | % del tiempo total en cudaMemcpy | | | | |
| 3 | 2A | Tamaño de bloque más rápido | | | | |
| 4 | 2B | Si N se duplica, el tiempo se multiplica por… | | | | |
| 5 | 2C | % en cudaMemcpy: suma de vectores vs N-body | | | | |
| 6 | 2C | Speedup máximo según Amdahl | | | | |
| 7 | 3 | Speedup del tiling vs kernel ingenuo | | | | |
| 8 | 5 | Interacciones por segundo en el Gran Premio | | | | |
| 9 | 5 | Interacciones por joule en el Gran Premio Verde | | | | |

## Máquina (Fase 0)

| | |
|---|---|
| GPU | NVIDIA GeForce RTX 5070 Laptop GPU, 8 GB, compute capability 12.0 |
| CUDA | nvcc 13.4 (V13.4.92), host compiler MSVC 14.51 |
| Potencia | `nvidia-smi` reporta `power.draw` (≈4 W en reposo); `power.limit` = N/A |
