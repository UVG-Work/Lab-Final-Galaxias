// Kit oficial - Laboratorio Final CC3069 "Galaxia en colisión"
// Parámetros físicos OBLIGATORIOS para el benchmark del Gran Premio.
// Si los cambian, su resultado no va a coincidir con la referencia.

#ifndef PARAMETROS_GALAXIA_H
#define PARAMETROS_GALAXIA_H

#define G_CONST   1.0f      // constante gravitacional (unidades de simulación)
#define DT        0.02f     // paso de tiempo
#define EPS2      0.0025f   // softening al cuadrado (eps = 0.05)

// Formato de los archivos .bin: N registros seguidos, sin encabezado,
// cada uno con 7 floats de 32 bits little-endian (28 bytes por estrella).
// N = tamaño del archivo / 28.
typedef struct {
    float x, y, z;     // posición
    float vx, vy, vz;  // velocidad
    float m;           // masa
} Estrella;

#endif
