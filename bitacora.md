# Bitácora de prompts — Lab Final CC3069 "Galaxia en colisión"

Equipo: (pendiente) · Piloto: June Herrera · Científico: Andrés Mazariegos · Auditor: Jonathan Zacarías

Decisión: **Aceptado**, **Aceptado con cambios** o **Rechazado**. Se registra en el momento, no al final.

| # | Fase | Objetivo | Prompt (texto exacto) | Qué devolvió Claude | Decisión | Por qué |
|---|------|----------|-----------------------|---------------------|----------|---------|
| 1 | 0 | Que Claude lea el enunciado, el kit y el handoff | "lee" | Resumen del estado, del contrato del kit, del riesgo de `galaxia.exe` en Windows y de las 4 decisiones abiertas | (Piloto) | |
| 2 | 0 | Definir modalidad y roles, y crear `CLAUDE.md` | "se hace ahora, en grupoo de 3 cientifico Andres Mazariegos, Auditor Jonathan Zacarias, Piloto June Herrera, dale." | Verificó la GPU, nvcc, MSVC y Python. Creó `CLAUDE.md` (4 reglas + regla propia "predicción antes de ejecución"), `bitacora.md` y `predicciones.md` | (Piloto) | |
| 3 | 1 | Kernel ingenuo de N-body + versión CPU | (mismo prompt #2) | `galaxia.cu`: un hilo por estrella con doble búfer (lee el paso anterior y escribe el nuevo, así no hace falta un segundo kernel); CPU con el mismo orden de suma; `KERNEL_MS`/`MEMCPY_MS` medidos con `cudaEvent`; generador `--generar N`; frames PPM con `--frames K`. Solo se compiló, no se ejecutó (regla 5) | (Piloto) | |
| 4 | 1 | Verificar contra el kit y medir | "ya están escritas, corre la verificación" (antes, "1 ya esta desactivado") | El primer intento falló: Smart App Control de Windows bloqueó `galaxia.exe` por no tener firma (`WinError 4551`). Claude lo diagnosticó y el equipo lo desactivó. Después: PASA con error 9.83e-07; mediana de 3 corridas: kernel 5.34 ms, memcpy 3.69 %, speedup 59.9x. Tabla en `experimentos/fase1_n4096.md` | (Piloto) | |
| 5 | 2 | Preparar los experimentos A, B y C | "sigue con la fase 2" | `suma_vectores.cu` (mismas reglas de medición: `cudaEvent` separado y CPU de referencia), `experimentos.py A/B/C` (3 repeticiones, mediana, CSV y gráfica), condiciones generadas para N = 1,024 a 65,536 con la estructura del kit. No corrió ningún experimento antes de las predicciones (regla 5) | (Piloto) | |
| 6 | 2 | Correr el Experimento A | "ya está la #3, corre el experimento A" | Tabla y gráfica. De 32 a 512 hilos, todos ≈ 22.4 ms (dentro de ±0.5 %); 1,024 hilos = 26.1 ms (+17 %). Claude corrigió su propia gráfica: el eje Y no empezaba en 0 y exageraba la diferencia | (Piloto) | |
| 7 | 2 | Correr el Experimento B | "ya está la #4, corre el experimento B" | Tabla y gráfica log-log. La CPU crece ×14.4, ×16.2 y ×17.2 cada vez que N se cuadruplica (≈ N²). La GPU crece ×4.1, ×4.2 y ×9.4 (subutilizada con N chico, entra a N² con N = 65,536). Speedup de 23x a 579x; memcpy de 11.5 % a 0.4 % | (Piloto) | |
| 8 | 2 | Correr el Experimento C | "ya están la #5 y #6, corre el experimento C" | Tabla y gráfica de barras. Suma de vectores: ~97 % en memcpy, Amdahl máx ≈ 1.03x, y la GPU pierde contra la CPU contando copias (0.35x a 0.41x). N-body: 4.6 % a 0.45 % en memcpy, Amdahl máx de 22x a 221x | (Piloto) | |
| 9 | 3 | Kernel con tiling en `__shared__` | "sí, sigue con la fase 3 y dame lo que hay q eescribir de nuevo" | `paso_tiling` en `galaxia.cu` (tiles de `blockDim.x` estrellas, dos `__syncthreads()`, los hilos sobrantes no salen antes de las barreras), flags `--kernel` y `--vs-ingenuo`, y `experimentos.py T`. Claude no respondió las preguntas de validación de la Fase 3 porque las contesta el Auditor sin IA. Solo se compiló | (Piloto) | |
| 10 | 3 | Medir el tiling contra el ingenuo | "ya dale" | Speedup 1.66x (N = 4,096), 1.57x (16,384), 1.07x (32,768) y 1.18x (65,536). Error contra el ingenuo exactamente 0: mismo orden de suma, resultado bit a bit idéntico. Tabla y gráfica en `experimentos/fase3_tiling.*` | (Piloto) | |
| 11 | 4 | Plantar un solo bug sutil en `sabotaje.cu` | "sigue" | Claude probó 4 candidatos fuera del repo y descartó el que no dejaba síntoma. Plantó uno que compila, corre y pasa la tolerancia del kit, pero deja un síntoma medible. Creó `cazar_sabotaje.bat` para el equipo cazador. La solución está en el papel entregado al catedrático (se completa aquí después de la caza) | (Piloto) | |
| 12 | 5 | Preparar el Gran Premio y el GIF | "pullea y continue" | Kernel por defecto de `galaxia.cu` → `tiling` (el kit corre el programa sin flags); `hacer_gif.py` (Pillow) y `galaxia.gif` con las condiciones oficiales de 32,768 (800 pasos, un frame cada 4). Primer intento con 2,000 pasos descartado: el choque ocupaba solo el primer 25 % del GIF. No corrió el benchmark: faltan las predicciones #8 y #9 (regla 5) | (Piloto) | |

## Prompt de oro

(Se elige al final: cuál funcionó mejor y qué lo hizo bueno.)
