// suma_vectores.cu — Lab Final CC3069, Fase 2, Experimento C (el muro de memoria)
// c = a + b con un hilo por elemento. Mismas reglas de medición que galaxia.cu:
// kernel y cudaMemcpy medidos por separado con cudaEvent, y versión CPU de referencia.
//
// Uso: suma_vectores <N> [--bloque B]

#define _CRT_SECURE_NO_WARNINGS
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <vector>
#include <chrono>
#include <cuda_runtime.h>

#define CHECK(llamada)                                                               \
    do {                                                                             \
        cudaError_t e_ = (llamada);                                                  \
        if (e_ != cudaSuccess) {                                                     \
            fprintf(stderr, "Error CUDA: %s en %s:%d\n", cudaGetErrorString(e_),     \
                    __FILE__, __LINE__);                                             \
            exit(1);                                                                 \
        }                                                                            \
    } while (0)

__global__ void suma(const float* __restrict__ a, const float* __restrict__ b,
                     float* __restrict__ c, int n)
{
    // i: elemento global que suma este hilo = bloque * hilos por bloque + hilo dentro del bloque
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) c[i] = a[i] + b[i];  // hilos sobrantes del último bloque no hacen nada
}

int main(int argc, char** argv)
{
    if (argc < 2) {
        fprintf(stderr, "Uso: suma_vectores <N> [--bloque B]\n");
        return 1;
    }
    const int n = atoi(argv[1]);
    int bloque = 256;
    if (argc == 4 && strcmp(argv[2], "--bloque") == 0) bloque = atoi(argv[3]);
    const size_t bytes = (size_t)n * sizeof(float);

    std::vector<float> a(n), b(n), c_gpu(n), c_cpu(n);
    for (int i = 0; i < n; ++i) {  // i: elemento i de los vectores de entrada
        a[i] = 0.001f * (i % 1000);
        b[i] = 1.0f - 0.0005f * (i % 2000);
    }

    float *d_a, *d_b, *d_c;
    CHECK(cudaMalloc(&d_a, bytes));
    CHECK(cudaMalloc(&d_b, bytes));
    CHECK(cudaMalloc(&d_c, bytes));
    cudaEvent_t ev_ini, ev_fin;
    CHECK(cudaEventCreate(&ev_ini));
    CHECK(cudaEventCreate(&ev_fin));
    float ms;

    // bloques: cuántos bloques cubren los n elementos (redondeo hacia arriba)
    const int bloques = (int)(((long long)n + bloque - 1) / bloque);

    // Calentamiento con n = 0 (nadie trabaja) para sacar la carga del módulo de la medición.
    suma<<<1, bloque>>>(d_a, d_b, d_c, 0);
    CHECK(cudaDeviceSynchronize());

    // Copia host -> dispositivo (a y b)
    CHECK(cudaEventRecord(ev_ini));
    CHECK(cudaMemcpy(d_a, a.data(), bytes, cudaMemcpyHostToDevice));
    CHECK(cudaMemcpy(d_b, b.data(), bytes, cudaMemcpyHostToDevice));
    CHECK(cudaEventRecord(ev_fin));
    CHECK(cudaEventSynchronize(ev_fin));
    CHECK(cudaEventElapsedTime(&ms, ev_ini, ev_fin));
    const double h2d_ms = ms;

    // Kernel
    CHECK(cudaEventRecord(ev_ini));
    suma<<<bloques, bloque>>>(d_a, d_b, d_c, n);
    CHECK(cudaEventRecord(ev_fin));
    CHECK(cudaEventSynchronize(ev_fin));
    CHECK(cudaGetLastError());
    CHECK(cudaEventElapsedTime(&ms, ev_ini, ev_fin));
    const double kernel_ms = ms;

    // Copia dispositivo -> host (c)
    CHECK(cudaEventRecord(ev_ini));
    CHECK(cudaMemcpy(c_gpu.data(), d_c, bytes, cudaMemcpyDeviceToHost));
    CHECK(cudaEventRecord(ev_fin));
    CHECK(cudaEventSynchronize(ev_fin));
    CHECK(cudaEventElapsedTime(&ms, ev_ini, ev_fin));
    const double d2h_ms = ms;

    // Versión CPU de referencia
    auto t0 = std::chrono::high_resolution_clock::now();
    for (int i = 0; i < n; ++i) c_cpu[i] = a[i] + b[i];  // i: mismo elemento que el hilo i de la GPU
    auto t1 = std::chrono::high_resolution_clock::now();
    const double cpu_ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

    double err = 0.0;
    for (int i = 0; i < n; ++i) err = fmax(err, fabs((double)c_gpu[i] - c_cpu[i]));  // i: elemento comparado

    const double memcpy_ms = h2d_ms + d2h_ms;
    printf("N=%d BLOQUE=%d BLOQUES=%d BYTES_COPIADOS=%zu\n", n, bloque, bloques, 3 * bytes);
    printf("KERNEL_MS=%.4f\n", kernel_ms);
    printf("MEMCPY_MS=%.4f (H2D=%.4f, D2H=%.4f)\n", memcpy_ms, h2d_ms, d2h_ms);
    printf("PORCENTAJE_MEMCPY=%.2f%% (memcpy / (memcpy + kernel))\n",
           100.0 * memcpy_ms / (memcpy_ms + kernel_ms));
    printf("CPU_MS=%.4f\n", cpu_ms);
    printf("SPEEDUP_KERNEL=%.2f (CPU / kernel)\n", cpu_ms / kernel_ms);
    printf("SPEEDUP_CON_MEMCPY=%.2f (CPU / (kernel + memcpy))\n", cpu_ms / (kernel_ms + memcpy_ms));
    printf("ERROR_GPU_CPU=%.3e\n", err);

    cudaFree(d_a);
    cudaFree(d_b);
    cudaFree(d_c);
    cudaEventDestroy(ev_ini);
    cudaEventDestroy(ev_fin);
    return 0;
}
