# Hoja de predicciones

Equipo: **Tamalones** · Piloto: June Herrera · Científico: Andrés Mazariegos · Auditor: Jonathan Zacarías

**La hoja oficial es la de papel** (página 7 del PDF, escrita a mano por el Científico antes de ejecutar y firmable por el catedrático). Este archivo es solo una transcripción posterior, para comparar con lo medido. Se entrega una foto o escaneo de la hoja en papel.

| # | Fase | Pregunta | Predicción (antes) | Hora | Medido | ¿Por qué la diferencia? |
|---|------|----------|--------------------|------|--------|-------------------------|
| 1 | 1 | Speedup GPU vs CPU con N = 4,096 | La GPU será 30x más rápida | | 59.9x (mediana de 3; de 51x a 78x) | Predijimos 30x y fue 60x: subestimamos la GPU |
| 2 | 1 | % del tiempo total en cudaMemcpy | 10 % | | 3.69 % | Predijimos 10 % y fue 3.7 %: subestimamos el trabajo de N-body por cada dato |
| 3 | 2A | Tamaño de bloque más rápido | Bloque de 16 | | De 32 a 512 hilos empatan (≈ 22.4 ms, ±0.5 %); 1,024 es 17 % más lento. (16 no se midió: el experimento va de 32 a 1,024) | |
| 4 | 2B | Si N se duplica, el tiempo se multiplica por… | ×2 | | CPU ≈ ×4 (×14.4 a ×17.2 cada vez que N se cuadruplica). GPU ≈ ×2 con N chico (×4.1 y ×4.2 por cuadruplicar) y ≈ ×3 al pasar a 65,536 (×9.4 por cuadruplicar) | |
| 5 | 2C | % en cudaMemcpy: suma de vectores vs N-body | 20 % | | Suma de vectores ≈ 97 %; N-body de 4.6 % a 0.45 % | |
| 6 | 2C | Speedup máximo según Amdahl | 1 / (1 − p) (procesadores) — 1 / fs | | Suma de vectores ≈ 1.03x; N-body de 22x a 221x | |
| 7 | 3 | Speedup del tiling vs kernel ingenuo | 40 % más rápido (1.4x) | | 1.66x (4,096), 1.57x (16,384), 1.07x (32,768), 1.18x (65,536) | |
| 8 | 5 | Interacciones por segundo en el Gran Premio | ≈ 2.4e11 inter/s (rango 2.0e11 a 2.6e11) — ver nota | 22:35 | **2.22e11** (mediana de 3: 2.223, 2.186 y 2.218e11). Error 1.40e-05, PASA | 8 % menos de lo previsto. El benchmark son solo 10 pasos (~48 ms de kernel) y la GPU arranca en reposo a ~250 MHz: los primeros pasos corren antes de que el reloj suba a ~1.9–2.5 GHz. Además la GPU venía caliente (65 °C) de otra carga |
| 9 | 5 | Interacciones por joule en el Gran Premio Verde | ≈ 5e9 inter/J (rango 2e9 a 6e9) — ver nota | 22:35 | **4.55e9** (mediana de 3: 5.52, 3.23 y 4.55e9). Seis corridas en total: de 3.2e9 a 7.6e9 | Cerca de lo previsto, pero la dispersión (2.4x con el mismo binario) muestra que domina la medición, no el kernel. (1) Potencia promedio de 24 a 38 W, muy por debajo de los 115 W de tope: la mayoría de las muestras caen con la GPU ociosa. (2) En esta GPU `nvidia-smi` refresca la potencia cada ~0.5 s, así que las "12 muestras" son 2 o 3 lecturas reales. (3) La GPU está limitada por potencia (`clocks_event_reasons` = 0x4, SW Power Cap) y su reloj varió entre 1.4 y 2.5 GHz de una corrida a otra, porque la laptop reparte la energía entre CPU, GPU y la carga de la batería. Ver `experimentos/relojes_gran_premio.csv` |

### Nota sobre las predicciones #8 y #9

No hubo tiempo de hacerlas a mano: **las escribió Claude por indicación del catedrático**, antes de correr el benchmark (22:35). El razonamiento:

- **#8 no es ciega.** El experimento T de la Fase 3 ya midió ≈ 2.4e11 inter/s con tiling y N = 32,768, y el benchmark corre ese mismo kernel (ahora es el de por defecto). Si la GPU está caliente, saldrá menos. Como referencia, el techo teórico es de unos 21 TFLOPS FP32 (36 SMs × 128 núcleos × 2 × ~2.25 GHz) ÷ ~20 FLOP por interacción ≈ 1e12 inter/s. Esperamos ~25 % de ese techo por dos razones: la división y la raíz en precisión IEEE son lentas, y 128 bloques de 256 hilos llenan mal 36 SMs (3 a 4 bloques por SM).
- **#9:** inter/J = inter/s ÷ potencia promedio. Con la GPU a tope esta laptop llega a 115 W, lo que daría 2.4e11 / 115 ≈ 2e9. Pero el script promedia **todas** las muestras de `nvidia-smi`: empieza 0.3 s antes de lanzar el programa, y 100 pasos son solo ~0.45 s de kernel. Muchas muestras caen en el arranque, en la lectura del archivo y en la verificación CPU, con la GPU casi ociosa. Esperamos un promedio de ~50 W → ≈ 5e9 inter/J. Es decir, la métrica premia corridas cortas por cómo se mide, no solo por eficiencia real.

## Máquina (Fase 0)

| | |
|---|---|
| GPU | NVIDIA GeForce RTX 5070 Laptop GPU, 8 GB, compute capability 12.0 |
| CUDA | nvcc 13.4 (V13.4.92), host compiler MSVC 14.51 |
| Potencia | `nvidia-smi` reporta `power.draw` (≈4 W en reposo); `power.limit` = N/A |
