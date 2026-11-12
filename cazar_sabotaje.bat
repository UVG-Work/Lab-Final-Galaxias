@echo off
rem Fase 4 - Sabotaje galactico: compilar y correr sabotaje.cu (sin IA).
rem Uso: doble clic, o en una terminal:  cazar_sabotaje.bat
rem Para correrlo a mano con otras opciones:
rem   sabotaje.exe <entrada.bin> <salida.bin> <pasos> [--kernel ingenuo|tiling] [--bloque B] [--cpu-pasos P] [--vs-ingenuo]
rem Datos: kit_galaxia\datos\condiciones_4096.bin y condiciones_32768.bin

echo == Compilando sabotaje.cu ==
nvcc -O3 -arch=sm_120 -o sabotaje sabotaje.cu || goto :error

echo.
echo == Verificacion oficial del kit (N = 4096) ==
python kit_galaxia\verificar_y_medir.py sabotaje.exe --equipo "cazadores" --n 4096

echo.
echo == Corrida directa (N = 4096, 10 pasos) ==
sabotaje.exe kit_galaxia\datos\condiciones_4096.bin salida_sabotaje.bin 10
pause
exit /b 0

:error
echo Fallo la compilacion.
pause
exit /b 1
