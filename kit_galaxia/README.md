# Kit oficial: Galaxia en colisión

Laboratorio Final · CC3069 Computación Paralela y Distribuida · UVG

Este kit **no trae el kernel**: el código lo construyen ustedes con Claude Code. El kit trae lo necesario para que todos los equipos simulen exactamente las mismas galaxias y se comparen contra la misma referencia en el Gran Premio.

## Contenido

| Archivo | Para qué sirve |
| --- | --- |
| `parametros.h` | Constantes físicas obligatorias (`DT`, `EPS2`, `G_CONST`) y el struct `Estrella`. |
| `datos/condiciones_4096.bin` | Galaxias de prueba con 4,096 estrellas, para verificar rápido. |
| `datos/condiciones_32768.bin` | Galaxias del benchmark oficial: 32,768 estrellas. |
| `datos/referencia_*.bin` | Estado esperado después de 10 pasos, calculado en doble precisión. |
| `verificar_y_medir.py` | Corre su programa, verifica el error y calcula las métricas del Gran Premio. |

Pásenle este README a Claude Code al iniciar (o referencien el kit en su `CLAUDE.md`) para que el programa cumpla el contrato desde el principio.

## Contrato que debe cumplir su programa

### 1. Línea de comandos

```
./galaxia <entrada.bin> <salida.bin> <pasos>
```

### 2. Formato de archivo

Sin encabezado. N registros seguidos de 7 `float` de 32 bits little-endian: `x, y, z, vx, vy, vz, m` (28 bytes por estrella). N = tamaño del archivo ÷ 28. La salida usa el mismo formato y el mismo orden de estrellas que la entrada.

### 3. Física (obligatoria para coincidir con la referencia)

Aceleración de la estrella *i*, sumando sobre **todas** las estrellas *j* (incluida *j = i*, que aporta cero gracias al softening):

```
d   = r_j - r_i
r2  = |d|² + EPS2
a_i = G · Σ_j  m_j · d / (r2 · sqrt(r2))
```

Integración (Euler semi-implícito): primero se calculan las aceleraciones de **todas** las estrellas con las posiciones actuales, y después:

```
v_i = v_i + a_i · DT
r_i = r_i + v_i · DT      (con la velocidad ya actualizada)
```

Usen `float` (32 bits) y los valores de `parametros.h`.

### 4. Medición de tiempo

Al terminar, su programa debe imprimir **una línea** con el tiempo total de kernel en milisegundos, sumado sobre todos los pasos y medido con `cudaEvent` (sin incluir `cudaMemcpy`):

```
KERNEL_MS=123.45
```

Pueden imprimir más cosas (por ejemplo, `MEMCPY_MS=...`); el script solo busca esa línea.

## Cómo usarlo

Verificación rápida durante la Fase 1:

```
python3 verificar_y_medir.py ./galaxia --equipo "Los Warps" --n 4096
```

Benchmark oficial del Gran Premio (Fase 5):

```
python3 verificar_y_medir.py ./galaxia --equipo "Los Warps"
```

Gran Premio Verde (mide la potencia con `nvidia-smi` mientras corre 100 pasos):

```
python3 verificar_y_medir.py ./galaxia --equipo "Los Warps" --energia
```

Si `nvidia-smi` no reporta potencia (pasa en algunas GPUs de laptop), agreguen `--tdp <W>` con el TDP oficial de su GPU y avísenle al catedrático.

El script imprime al final una línea lista para la tabla del pizarrón. **Un resultado con error mayor a 10⁻³ no cuenta para el Gran Premio.**

## Notas

- La tolerancia de 10⁻³ es la distancia máxima entre la posición de cualquier estrella y la referencia. Una versión correcta en `float` queda alrededor de 10⁻⁵; un bug que se salta un solo bloque de 256 estrellas ya da un error mayor a 10⁻³.
- Para la animación (GIF) pueden correr los pasos que quieran y guardar frames como prefieran; el contrato aplica solo al benchmark.
- No modifiquen los archivos de `datos/`.
