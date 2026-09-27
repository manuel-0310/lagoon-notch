# mediaremote-adapter (copia)

Copia de [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
(licencia BSD 3-Clause, ver `LICENSE`), commit `73f14ab1568371e6e3c44063f21c34c5e2712c4d`.

Desde macOS 15.4 las apps normales no pueden leer "Ahora suena" con MediaRemote. Este adaptador
carga un framework pequeño dentro de `/usr/bin/perl` (que sí tiene acceso) y escribe el estado en
JSON por la salida estándar. `scripts/build-app.sh` lo compila con `clang` (sin cmake) y lo copia
dentro de `Lagoon.app`.

Para actualizarlo: reemplazar `src/`, `include/`, `bin/` y `LICENSE` por los de una versión nueva.
