// galaxia.cu — Lab Final CC3069 "Galaxia en colisión"
// Simulación N-body de dos galaxias que chocan. Un hilo por estrella.
//
// Uso:
//   galaxia <entrada.bin> <salida.bin> <pasos> [--kernel ingenuo|tiling] [--bloque B]
//           [--frames K] [--cpu-pasos P] [--vs-ingenuo]
//   galaxia --generar <N> <salida.bin>
//
//   --kernel K     tiling (Fase 3, memoria compartida, por defecto) o ingenuo (Fase 1)
//   --bloque B     hilos por bloque (por defecto 256); en tiling también es el tamaño del tile
//   --vs-ingenuo   además corre el kernel ingenuo (sin medir) e imprime ERROR_VS_INGENUO
//   --frames K     guarda un frame PPM en frames/ cada K pasos (solo para el GIF, no para medir)
//   --cpu-pasos P  la CPU simula P pasos completos y se compara con la GPU después de P pasos
//
// Sin --cpu-pasos: si N²·pasos <= 4e9 la CPU simula todos los pasos con todas las estrellas;
// si no, la CPU calcula solo el paso 1 para una muestra de 1024 estrellas (cada una sumando
// las N), para que la verificación no tarde minutos ni ensucie la medición de energía.

#define _CRT_SECURE_NO_WARNINGS
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <vector>
#include <random>
#include <chrono>
#include <algorithm>
#include <cuda_runtime.h>
#ifdef _WIN32
#include <direct.h>
#define CREAR_DIR(ruta) _mkdir(ruta)
#else
#include <sys/stat.h>
#define CREAR_DIR(ruta) mkdir(ruta, 0755)
#endif

#include "kit_galaxia/parametros.h"

static_assert(sizeof(Estrella) == 28, "Estrella debe medir 28 bytes (7 floats)");

#define CHECK(llamada)                                                               \
    do {                                                                             \
        cudaError_t e_ = (llamada);                                                  \
        if (e_ != cudaSuccess) {                                                     \
            fprintf(stderr, "Error CUDA: %s en %s:%d\n", cudaGetErrorString(e_),     \
                    __FILE__, __LINE__);                                             \
            exit(1);                                                                 \
        }                                                                            \
    } while (0)

// En el dispositivo cada estrella se guarda en dos float4:
//   pos[i] = (x, y, z, m)    vel[i] = (vx, vy, vz, 0)
// Así una sola lectura de 16 bytes trae posición y masa de una estrella.

// ---------------------------------------------------------------------------
// Kernel ingenuo (Fase 1): un hilo por estrella, sin memoria compartida.
// Lee el estado del paso anterior (pos_ant, vel_ant) y escribe el nuevo en
// otros arreglos (pos_nue, vel_nue). Como nadie escribe en lo que se lee, todas
// las aceleraciones se calculan con las posiciones del paso anterior, tal como
// exige el contrato, sin necesitar un segundo kernel ni una barrera global.
// ---------------------------------------------------------------------------
__global__ void paso_ingenuo(const float4* __restrict__ pos_ant,
                             const float4* __restrict__ vel_ant,
                             float4* __restrict__ pos_nue,
                             float4* __restrict__ vel_nue,
                             int n)
{
    // i: número global de la estrella que calcula este hilo
    //    = (bloque en el que está el hilo) * (hilos por bloque) + (posición del hilo dentro del bloque)
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;  // hilos sobrantes del último bloque: no les toca ninguna estrella

    float4 pi = pos_ant[i];  // posición y masa de la estrella i al inicio del paso
    float ax = 0.0f, ay = 0.0f, az = 0.0f;

    // j: estrella que atrae a la estrella i; se recorren todas, incluida j == i (aporta 0 porque d = 0)
    for (int j = 0; j < n; ++j) {
        float4 pj = pos_ant[j];  // posición y masa de la estrella j
        float dx = pj.x - pi.x;
        float dy = pj.y - pi.y;
        float dz = pj.z - pi.z;
        float r2 = dx * dx + dy * dy + dz * dz + EPS2;  // distancia² suavizada
        float inv = 1.0f / (r2 * sqrtf(r2));             // 1 / r³
        float s = pj.w * inv;                            // m_j / r³
        ax += s * dx;
        ay += s * dy;
        az += s * dz;
    }

    float4 vi = vel_ant[i];  // velocidad de la estrella i al inicio del paso
    // Euler semi-implícito: primero la velocidad, luego la posición con la velocidad nueva.
    vi.x += G_CONST * ax * DT;
    vi.y += G_CONST * ay * DT;
    vi.z += G_CONST * az * DT;
    pi.x += vi.x * DT;
    pi.y += vi.y * DT;
    pi.z += vi.z * DT;

    pos_nue[i] = pi;  // estado nuevo de la estrella i (la masa en .w no cambia)
    vel_nue[i] = vi;
}

// ---------------------------------------------------------------------------
// Kernel con tiling (Fase 3): misma física y mismo orden de suma que el ingenuo,
// pero las estrellas j se recorren por grupos ("tiles") de blockDim.x estrellas.
// Cada hilo del bloque trae UNA estrella del tile a memoria compartida, y después
// todos los hilos del bloque usan las blockDim.x estrellas desde ahí. Así cada
// estrella j se lee de memoria global una vez por bloque y no una vez por hilo.
// Se lanza con blockDim.x * sizeof(float4) bytes de memoria compartida dinámica.
// ---------------------------------------------------------------------------
__global__ void paso_tiling(const float4* __restrict__ pos_ant,
                            const float4* __restrict__ vel_ant,
                            float4* __restrict__ pos_nue,
                            float4* __restrict__ vel_nue,
                            int n)
{
    extern __shared__ float4 tile[];  // tile[k]: k-ésima estrella del grupo cargado (blockDim.x estrellas)

    // i: número global de la estrella que calcula este hilo
    //    = (bloque en el que está el hilo) * (hilos por bloque) + (posición del hilo dentro del bloque)
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    // Los hilos sobrantes (i >= n) NO pueden salir antes: tienen que ayudar a cargar
    // los tiles y llegar a cada __syncthreads(), o el bloque se queda esperándolos.
    float4 pi = (i < n) ? pos_ant[i] : make_float4(0.0f, 0.0f, 0.0f, 0.0f);
    float ax = 0.0f, ay = 0.0f, az = 0.0f;

    // base: primera estrella j del tile actual; avanza de blockDim.x en blockDim.x
    for (int base = 0; base < n; base += blockDim.x) {
        // j: estrella global que este hilo copia al tile = primera del tile + posición del hilo
        int j = base + threadIdx.x;
        if (j < n) tile[threadIdx.x] = pos_ant[j];  // la casilla threadIdx.x del tile es de este hilo
        __syncthreads();  // barrera 1: nadie lee el tile hasta que todos terminaron de escribirlo

        // cuantas: estrellas válidas en este tile (el último puede venir incompleto si n no es múltiplo)
        int cuantas = min((int)blockDim.x, n - base);
        for (int k = 0; k < cuantas; ++k) {  // k: posición dentro del tile; es la estrella global base + k
            float4 pj = tile[k];
            float dx = pj.x - pi.x;
            float dy = pj.y - pi.y;
            float dz = pj.z - pi.z;
            float r2 = dx * dx + dy * dy + dz * dz + EPS2;  // distancia² suavizada
            float inv = 1.0f / (r2 * sqrtf(r2));             // 1 / r³
            float s = pj.w * inv;                            // m_j / r³
            ax += s * dx;
            ay += s * dy;
            az += s * dz;
        }
        __syncthreads();  // barrera 2: nadie sobrescribe el tile con el siguiente grupo hasta que todos terminaron de leerlo
    }

    if (i >= n) return;  // ya pasaron todas las barreras: el hilo sobrante no escribe nada
    float4 vi = vel_ant[i];  // velocidad de la estrella i al inicio del paso
    vi.x += G_CONST * ax * DT;
    vi.y += G_CONST * ay * DT;
    vi.z += G_CONST * az * DT;
    pi.x += vi.x * DT;
    pi.y += vi.y * DT;
    pi.z += vi.z * DT;
    pos_nue[i] = pi;  // estado nuevo de la estrella i
    vel_nue[i] = vi;
}

// Lanza un paso con el kernel elegido. tiling usa bloque * 16 bytes de memoria compartida.
static void lanzar_paso(bool tiling, int bloques, int bloque, const float4* pos_ant, const float4* vel_ant,
                        float4* pos_nue, float4* vel_nue, int n)
{
    if (tiling)
        paso_tiling<<<bloques, bloque, bloque * sizeof(float4)>>>(pos_ant, vel_ant, pos_nue, vel_nue, n);
    else
        paso_ingenuo<<<bloques, bloque>>>(pos_ant, vel_ant, pos_nue, vel_nue, n);
}

// ---------------------------------------------------------------------------
// Versión CPU de referencia: misma física y mismo orden de suma que el kernel.
// ---------------------------------------------------------------------------
static void estrella_cpu(int i, const float4* pos_ant, const float4* vel_ant, int n,
                         float4* pos_nue, float4* vel_nue)
{
    float4 pi = pos_ant[i];  // posición y masa de la estrella i al inicio del paso
    float ax = 0.0f, ay = 0.0f, az = 0.0f;
    // j: estrella que atrae a la estrella i (todas, incluida j == i)
    for (int j = 0; j < n; ++j) {
        float4 pj = pos_ant[j];
        float dx = pj.x - pi.x;
        float dy = pj.y - pi.y;
        float dz = pj.z - pi.z;
        float r2 = dx * dx + dy * dy + dz * dz + EPS2;
        float inv = 1.0f / (r2 * sqrtf(r2));
        float s = pj.w * inv;
        ax += s * dx;
        ay += s * dy;
        az += s * dz;
    }
    float4 vi = vel_ant[i];
    vi.x += G_CONST * ax * DT;
    vi.y += G_CONST * ay * DT;
    vi.z += G_CONST * az * DT;
    pi.x += vi.x * DT;
    pi.y += vi.y * DT;
    pi.z += vi.z * DT;
    pos_nue[i] = pi;  // estrella i en el arreglo del paso nuevo
    vel_nue[i] = vi;
}

// Máxima distancia euclidiana de posición entre GPU y CPU sobre las estrellas indicadas.
static double error_maximo(const std::vector<float4>& gpu, const std::vector<float4>& cpu,
                           const std::vector<int>& estrellas)
{
    double peor = 0.0;
    for (int i : estrellas) {  // i: estrella que se compara
        double dx = (double)gpu[i].x - cpu[i].x;
        double dy = (double)gpu[i].y - cpu[i].y;
        double dz = (double)gpu[i].z - cpu[i].z;
        double d = sqrt(dx * dx + dy * dy + dz * dz);
        if (d != d) return d;  // NaN
        if (d > peor) peor = d;
    }
    return peor;
}

// ---------------------------------------------------------------------------
// Archivos .bin del kit: N registros de 7 floats (x, y, z, vx, vy, vz, m)
// ---------------------------------------------------------------------------
static std::vector<Estrella> leer_bin(const char* ruta)
{
    FILE* f = fopen(ruta, "rb");
    if (!f) { fprintf(stderr, "No se pudo abrir %s\n", ruta); exit(1); }
    fseek(f, 0, SEEK_END);
    long bytes = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (bytes <= 0 || bytes % sizeof(Estrella) != 0) {
        fprintf(stderr, "%s: el tamaño (%ld bytes) no es múltiplo de 28\n", ruta, bytes);
        exit(1);
    }
    std::vector<Estrella> e(bytes / sizeof(Estrella));
    if (fread(e.data(), sizeof(Estrella), e.size(), f) != e.size()) {
        fprintf(stderr, "Error leyendo %s\n", ruta);
        exit(1);
    }
    fclose(f);
    return e;
}

static void escribir_bin(const char* ruta, const std::vector<Estrella>& e)
{
    FILE* f = fopen(ruta, "wb");
    if (!f) { fprintf(stderr, "No se pudo crear %s\n", ruta); exit(1); }
    fwrite(e.data(), sizeof(Estrella), e.size(), f);
    fclose(f);
}

// ---------------------------------------------------------------------------
// Generador de condiciones iniciales con la misma estructura que el kit:
// dos discos de masa 1 cada uno (m = 2/N por estrella), centrados en
// (-3, -1, 0) y (3, 1, 0), acercándose a ±0.25 en x. La primera mitad del
// archivo es la galaxia A y la segunda la galaxia B (girando al revés e inclinada).
// ---------------------------------------------------------------------------
static void generar(int n, const char* ruta)
{
    std::mt19937 rng(20261111);
    std::uniform_real_distribution<float> uni(0.0f, 1.0f);
    std::normal_distribution<float> gauss(0.0f, 1.0f);
    std::vector<Estrella> e(n);
    const float m = 2.0f / n;
    const float escala = 0.8f, r_max = 3.5f;

    for (int g = 0; g < 2; ++g) {
        // primera y última estrella (exclusiva) de la galaxia g dentro del archivo
        int ini = (g == 0) ? 0 : n / 2;
        int fin = (g == 0) ? n / 2 : n;
        int cuantas = fin - ini;
        float cx = g == 0 ? -3.0f : 3.0f, cy = g == 0 ? -1.0f : 1.0f;
        float cvx = g == 0 ? 0.25f : -0.25f;
        float giro = g == 0 ? 1.0f : -1.0f;               // sentido de rotación del disco
        float incl = g == 0 ? 0.0f : 0.45f;               // inclinación (rad) alrededor del eje x
        float masa_galaxia = m * cuantas;

        // Radios con perfil exponencial truncado, ordenados para saber la masa encerrada.
        std::vector<float> radios(cuantas);
        for (int k = 0; k < cuantas; ++k) {  // k: estrella k-ésima dentro de la galaxia g
            float u = uni(rng);
            radios[k] = -escala * logf(1.0f - u * (1.0f - expf(-r_max / escala)));
        }
        std::sort(radios.begin(), radios.end());

        for (int k = 0; k < cuantas; ++k) {  // k: estrella k-ésima (de adentro hacia afuera) de la galaxia g
            float r = radios[k];
            float th = 6.2831853f * uni(rng);
            float x = r * cosf(th), y = r * sinf(th), z = 0.08f * gauss(rng);
            // Velocidad circular con la masa encerrada y el mismo suavizado de la simulación.
            float m_enc = masa_galaxia * (k + 1) / cuantas;
            float r2 = r * r + EPS2;
            float vc = sqrtf(G_CONST * m_enc * r * r / (r2 * sqrtf(r2)));
            float vx = -giro * vc * sinf(th) + 0.03f * gauss(rng);
            float vy = giro * vc * cosf(th) + 0.03f * gauss(rng);
            float vz = 0.03f * gauss(rng);
            // Inclinar el disco alrededor del eje x.
            float ci = cosf(incl), si = sinf(incl);
            float y2 = y * ci - z * si, z2 = y * si + z * ci;
            float vy2 = vy * ci - vz * si, vz2 = vy * si + vz * ci;
            Estrella& s = e[ini + k];  // estrella ini+k: posición global en el archivo
            s.x = cx + x; s.y = cy + y2; s.z = z2;
            s.vx = cvx + vx; s.vy = vy2; s.vz = vz2;
            s.m = m;
        }
    }
    escribir_bin(ruta, e);
    printf("Generadas %d estrellas en %s\n", n, ruta);
}

// ---------------------------------------------------------------------------
// Frames PPM para el GIF: proyección en el plano x-y. Galaxia A azulada,
// galaxia B anaranjada (según la mitad del archivo de la que viene la estrella).
// ---------------------------------------------------------------------------
static void escribir_frame(const std::vector<float4>& pos, int n, int numero, float semiancho)
{
    const int L = 600;  // lado de la imagen en píxeles
    std::vector<float> acum(3 * L * L, 0.0f);
    const float colA[3] = {0.45f, 0.65f, 1.0f}, colB[3] = {1.0f, 0.6f, 0.25f};
    for (int i = 0; i < n; ++i) {  // i: estrella que se dibuja
        const float* c = (i < n / 2) ? colA : colB;
        // px, py: columna y fila del píxel donde cae la estrella i (y crece hacia arriba)
        int px = (int)((pos[i].x / semiancho * 0.5f + 0.5f) * L);
        int py = (int)((0.5f - pos[i].y / semiancho * 0.5f) * L);
        for (int d = 0; d < 5; ++d) {  // d: centro y sus 4 vecinos (brillo suave)
            int qx = px + (d == 1) - (d == 2), qy = py + (d == 3) - (d == 4);
            if (qx < 0 || qx >= L || qy < 0 || qy >= L) continue;
            float w = d == 0 ? 1.0f : 0.35f;
            int base = 3 * (qy * L + qx);  // primer canal (R) del píxel (qx, qy)
            for (int k = 0; k < 3; ++k) acum[base + k] += w * c[k];
        }
    }
    std::vector<unsigned char> img(3 * L * L);
    for (size_t k = 0; k < img.size(); ++k)  // k: canal k del arreglo de píxeles
        img[k] = (unsigned char)(255.0f * (1.0f - expf(-0.6f * acum[k])));
    char nombre[64];
    snprintf(nombre, sizeof nombre, "frames/frame_%04d.ppm", numero);
    FILE* f = fopen(nombre, "wb");
    if (!f) { fprintf(stderr, "No se pudo crear %s\n", nombre); return; }
    fprintf(f, "P6\n%d %d\n255\n", L, L);
    fwrite(img.data(), 1, img.size(), f);
    fclose(f);
}

static void uso()
{
    fprintf(stderr,
            "Uso: galaxia <entrada.bin> <salida.bin> <pasos> [--kernel ingenuo|tiling] [--bloque B]\n"
            "             [--frames K] [--cpu-pasos P] [--vs-ingenuo]\n"
            "     galaxia --generar <N> <salida.bin>\n");
    exit(1);
}

int main(int argc, char** argv)
{
    if (argc == 4 && strcmp(argv[1], "--generar") == 0) {
        generar(atoi(argv[2]), argv[3]);
        return 0;
    }
    if (argc < 4) uso();
    const char* entrada = argv[1];
    const char* salida = argv[2];
    int pasos = atoi(argv[3]);
    int bloque = 256, frames_cada = 0, pasos_cpu = -1;
    bool tiling = true, vs_ingenuo = false;  // tiling por defecto: es lo que corre el benchmark del kit (sin flags)
    for (int a = 4; a < argc; ++a) {  // a: índice del argumento opcional que se está leyendo
        if (strcmp(argv[a], "--kernel") == 0 && a + 1 < argc) {
            ++a;  // a: ahora apunta al nombre del kernel
            if (strcmp(argv[a], "tiling") == 0) tiling = true;
            else if (strcmp(argv[a], "ingenuo") == 0) tiling = false;
            else uso();
        }
        else if (strcmp(argv[a], "--vs-ingenuo") == 0) vs_ingenuo = true;
        else if (strcmp(argv[a], "--bloque") == 0 && a + 1 < argc) bloque = atoi(argv[++a]);
        else if (strcmp(argv[a], "--frames") == 0 && a + 1 < argc) frames_cada = atoi(argv[++a]);
        else if (strcmp(argv[a], "--cpu-pasos") == 0 && a + 1 < argc) pasos_cpu = atoi(argv[++a]);
        else uso();
    }
    if (pasos < 1 || bloque < 1 || bloque > 1024) uso();

    // --- Lectura y empaquetado en float4 ---
    std::vector<Estrella> ini = leer_bin(entrada);
    const int n = (int)ini.size();
    std::vector<float4> h_pos(n), h_vel(n);
    for (int i = 0; i < n; ++i) {  // i: estrella i del archivo, misma posición en los arreglos
        h_pos[i] = make_float4(ini[i].x, ini[i].y, ini[i].z, ini[i].m);
        h_vel[i] = make_float4(ini[i].vx, ini[i].vy, ini[i].vz, 0.0f);
    }

    // --- Modo de verificación CPU ---
    bool cpu_completa;
    if (pasos_cpu >= 1) {
        pasos_cpu = std::min(pasos_cpu, pasos);
        cpu_completa = true;
    } else if ((double)n * n * pasos <= 4e9) {
        pasos_cpu = pasos;
        cpu_completa = true;
    } else {
        pasos_cpu = 1;
        cpu_completa = false;
    }

    // --- Memoria en el dispositivo: dos juegos (A y B) que se alternan cada paso ---
    float4 *d_pos[2], *d_vel[2];
    const size_t bytes = (size_t)n * sizeof(float4);
    for (int b = 0; b < 2; ++b) {  // b: juego de arreglos 0 (A) o 1 (B)
        CHECK(cudaMalloc(&d_pos[b], bytes));
        CHECK(cudaMalloc(&d_vel[b], bytes));
    }
    cudaEvent_t ev_ini, ev_fin;
    CHECK(cudaEventCreate(&ev_ini));
    CHECK(cudaEventCreate(&ev_fin));
    float ms;

    // --- Copia host -> dispositivo (medida aparte) ---
    CHECK(cudaEventRecord(ev_ini));
    CHECK(cudaMemcpy(d_pos[0], h_pos.data(), bytes, cudaMemcpyHostToDevice));
    CHECK(cudaMemcpy(d_vel[0], h_vel.data(), bytes, cudaMemcpyHostToDevice));
    CHECK(cudaEventRecord(ev_fin));
    CHECK(cudaEventSynchronize(ev_fin));
    CHECK(cudaEventElapsedTime(&ms, ev_ini, ev_fin));
    const double h2d_ms = ms;

    // bloques: cuántos bloques hacen falta para cubrir las n estrellas (redondeo hacia arriba)
    const int bloques = (n + bloque - 1) / bloque;

    // Calentamiento: con n = 0 ningún hilo calcula nada. Sirve para que la carga
    // perezosa del módulo CUDA no caiga dentro del primer paso medido.
    lanzar_paso(tiling, 1, bloque, d_pos[0], d_vel[0], d_pos[1], d_vel[1], 0);
    CHECK(cudaGetLastError());
    CHECK(cudaDeviceSynchronize());

    float semiancho = 0.0f;
    if (frames_cada > 0) {
        for (int i = 0; i < n; ++i)  // i: estrella usada para encuadrar la imagen
            semiancho = std::max(semiancho, std::max(fabsf(h_pos[i].x), fabsf(h_pos[i].y)));
        semiancho *= 1.15f;
        CREAR_DIR("frames");
        escribir_frame(h_pos, n, 0, semiancho);
    }

    // --- Simulación en GPU: solo el kernel queda entre los eventos ---
    double kernel_ms = 0.0;
    int act = 0;  // act: juego de arreglos (0 o 1) que tiene el estado actual
    std::vector<float4> gpu_verif(n), tmp(n);
    for (int paso = 1; paso <= pasos; ++paso) {
        CHECK(cudaEventRecord(ev_ini));
        lanzar_paso(tiling, bloques, bloque, d_pos[act], d_vel[act], d_pos[1 - act], d_vel[1 - act], n);
        CHECK(cudaEventRecord(ev_fin));
        CHECK(cudaEventSynchronize(ev_fin));
        CHECK(cudaGetLastError());
        CHECK(cudaEventElapsedTime(&ms, ev_ini, ev_fin));
        kernel_ms += ms;
        act = 1 - act;  // el estado nuevo quedó en el otro juego de arreglos

        // Copias extra (verificación intermedia y frames): no cuentan en KERNEL_MS ni en MEMCPY_MS.
        if (paso == pasos_cpu && pasos_cpu < pasos)
            CHECK(cudaMemcpy(gpu_verif.data(), d_pos[act], bytes, cudaMemcpyDeviceToHost));
        if (frames_cada > 0 && paso % frames_cada == 0) {
            CHECK(cudaMemcpy(tmp.data(), d_pos[act], bytes, cudaMemcpyDeviceToHost));
            escribir_frame(tmp, n, paso / frames_cada, semiancho);
        }
    }

    // --- Copia dispositivo -> host del estado final (medida aparte) ---
    std::vector<float4> fin_pos(n), fin_vel(n);
    CHECK(cudaEventRecord(ev_ini));
    CHECK(cudaMemcpy(fin_pos.data(), d_pos[act], bytes, cudaMemcpyDeviceToHost));
    CHECK(cudaMemcpy(fin_vel.data(), d_vel[act], bytes, cudaMemcpyDeviceToHost));
    CHECK(cudaEventRecord(ev_fin));
    CHECK(cudaEventSynchronize(ev_fin));
    CHECK(cudaEventElapsedTime(&ms, ev_ini, ev_fin));
    const double d2h_ms = ms;
    if (pasos_cpu == pasos) gpu_verif = fin_pos;

    // --- Comparación contra el kernel ingenuo (Fase 3), fuera de toda medición ---
    double err_ingenuo = -1.0;
    if (vs_ingenuo) {
        CHECK(cudaMemcpy(d_pos[0], h_pos.data(), bytes, cudaMemcpyHostToDevice));
        CHECK(cudaMemcpy(d_vel[0], h_vel.data(), bytes, cudaMemcpyHostToDevice));
        int ing = 0;  // ing: juego de arreglos con el estado actual de la corrida ingenua
        for (int paso = 1; paso <= pasos; ++paso) {
            lanzar_paso(false, bloques, bloque, d_pos[ing], d_vel[ing], d_pos[1 - ing], d_vel[1 - ing], n);
            ing = 1 - ing;
        }
        CHECK(cudaGetLastError());
        CHECK(cudaMemcpy(tmp.data(), d_pos[ing], bytes, cudaMemcpyDeviceToHost));
        std::vector<int> todas(n);
        for (int i = 0; i < n; ++i) todas[i] = i;  // i: se comparan todas las estrellas
        err_ingenuo = error_maximo(fin_pos, tmp, todas);
    }

    // --- Escritura de la salida en el formato del kit, mismo orden de estrellas ---
    std::vector<Estrella> out(n);
    for (int i = 0; i < n; ++i) {  // i: estrella i, misma posición que en la entrada
        out[i] = {fin_pos[i].x, fin_pos[i].y, fin_pos[i].z,
                  fin_vel[i].x, fin_vel[i].y, fin_vel[i].z, fin_pos[i].w};
    }
    escribir_bin(salida, out);

    // --- Referencia CPU ---
    std::vector<float4> c_pos[2] = {h_pos, h_pos}, c_vel[2] = {h_vel, h_vel};
    std::vector<int> comparar;
    int c_act = 0;  // c_act: juego de arreglos CPU con el estado actual
    auto t0 = std::chrono::high_resolution_clock::now();
    if (cpu_completa) {
        for (int paso = 1; paso <= pasos_cpu; ++paso) {
            for (int i = 0; i < n; ++i)  // i: estrella que calcula la CPU en este paso
                estrella_cpu(i, c_pos[c_act].data(), c_vel[c_act].data(), n,
                             c_pos[1 - c_act].data(), c_vel[1 - c_act].data());
            c_act = 1 - c_act;
        }
        for (int i = 0; i < n; ++i) comparar.push_back(i);  // se comparan todas las estrellas
    } else {
        const int muestra = std::min(n, 1024);
        for (int k = 0; k < muestra; ++k) {
            // i: k-ésima estrella de la muestra, repartida uniformemente en todo el archivo
            int i = (int)((long long)k * n / muestra);
            estrella_cpu(i, c_pos[0].data(), c_vel[0].data(), n, c_pos[1].data(), c_vel[1].data());
            comparar.push_back(i);
        }
        c_act = 1;
    }
    auto t1 = std::chrono::high_resolution_clock::now();
    const double cpu_ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
    const double err = error_maximo(gpu_verif, c_pos[c_act], comparar);

    // --- Reporte ---
    const double memcpy_ms = h2d_ms + d2h_ms;
    const double kernel_por_paso = kernel_ms / pasos;
    // CPU por paso con todas las estrellas (en modo muestra se extrapola a las N)
    const double cpu_por_paso = cpu_completa ? cpu_ms / pasos_cpu : cpu_ms * n / comparar.size();
    printf("N=%d PASOS=%d BLOQUE=%d BLOQUES=%d KERNEL=%s\n", n, pasos, bloque, bloques,
           tiling ? "tiling" : "ingenuo");
    printf("KERNEL_MS=%.4f\n", kernel_ms);
    printf("MEMCPY_MS=%.4f (H2D=%.4f, D2H=%.4f)\n", memcpy_ms, h2d_ms, d2h_ms);
    printf("PORCENTAJE_MEMCPY=%.2f%% (memcpy / (memcpy + kernel))\n",
           100.0 * memcpy_ms / (memcpy_ms + kernel_ms));
    printf("KERNEL_MS_POR_PASO=%.4f\n", kernel_por_paso);
    if (cpu_completa)
        printf("CPU_MS=%.2f (%d pasos completos, %d estrellas, 1 hilo)\n", cpu_ms, pasos_cpu, n);
    else
        printf("CPU_MS=%.2f (paso 1, muestra de %zu estrellas; por paso extrapolado a N)\n",
               cpu_ms, comparar.size());
    printf("CPU_MS_POR_PASO=%.2f%s\n", cpu_por_paso, cpu_completa ? "" : " (estimado)");
    printf("SPEEDUP_KERNEL=%.1f (CPU por paso / kernel por paso)\n", cpu_por_paso / kernel_por_paso);
    printf("SPEEDUP_CON_MEMCPY=%.1f (CPU de %d pasos / (kernel + memcpy))\n",
           cpu_por_paso * pasos / (kernel_ms + memcpy_ms), pasos);
    printf("ERROR_GPU_CPU=%.3e (máxima distancia de posición tras %d paso(s), %zu estrellas)\n",
           err, pasos_cpu, comparar.size());
    if (vs_ingenuo)
        printf("ERROR_VS_INGENUO=%.3e (máxima distancia de posición contra el kernel ingenuo, %d pasos)\n",
               err_ingenuo, pasos);
    if (frames_cada > 0)
        printf("AVISO: se escribieron frames; esta corrida no sirve para medir.\n");

    for (int b = 0; b < 2; ++b) {
        cudaFree(d_pos[b]);
        cudaFree(d_vel[b]);
    }
    cudaEventDestroy(ev_ini);
    cudaEventDestroy(ev_fin);
    return 0;
}
