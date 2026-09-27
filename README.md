# Lagoon · Notch

App para macOS que convierte el notch de tu MacBook en un centro de actividades con animaciones:
música, timer/Pomodoro, cronómetro, bandeja de archivos con AirDrop, agenda, portapapeles,
espejo, reloj mundial, clima, batería de tus dispositivos, volumen y brillo.

Está hecha en **Swift + SwiftUI** (nativa, sin Electron) y pensada para gastar poco:

- **Sin sondeos**: la música, la batería, el volumen y el calendario funcionan por avisos del sistema.
  Solo el portapapeles consulta un contador (un entero) dos veces por segundo, porque macOS no avisa.
- **Animaciones continuas con Core Animation** (la onda de la música la pinta el sistema, no la app).
- Los relojes y contadores solo se actualizan mientras se ven.
- La cámara solo se enciende con la pestaña Espejo abierta.
- Un único binario de unos pocos MB; los íconos son una fuente de ~9 KB embebida.

## Requisitos

- macOS 14 Sonoma o posterior (funciona mejor en un Mac con notch, aunque en otras pantallas dibuja uno virtual).
- Xcode 15 o posterior, **o** solo las Command Line Tools: `xcode-select --install`.

## Bajar el código

La primera vez:

```bash
git clone https://github.com/manuel-0310/lagoon-notch.git
cd lagoon-notch
git checkout claude/stoic-bell-inqz95
```

Para traer cambios nuevos después:

```bash
cd lagoon-notch
git pull origin claude/stoic-bell-inqz95
```

## Compilar, instalar y abrir

```bash
./scripts/build-app.sh --install --run
```

Eso compila en modo release, arma `build/Lagoon.app`, la firma (ad-hoc), la copia a
`/Applications` y la abre. Otras opciones:

| Comando | Qué hace |
| --- | --- |
| `./scripts/build-app.sh` | Solo compila y deja la app en `build/Lagoon.app` |
| `./scripts/build-app.sh --run` | Compila y la abre desde `build/` |
| `./scripts/build-app.sh --install` | Compila y la copia a `/Applications` |

Lagoon no tiene ícono en el Dock ni en la barra de menús: vive en el notch.

- **Pasa el cursor** por el notch para abrir el panel (o haz clic).
- **Clic derecho** en el notch → *Ajustes de Lagoon…* o *Salir de Lagoon*.
- Abrir la app otra vez desde el Finder también muestra los Ajustes.
- **Esc** cierra el panel; **deslizar con dos dedos** cambia de pestaña.

> La primera vez, si macOS dice que no puede verificar la app, haz clic derecho en
> `Lagoon.app` → *Abrir*. Pasa porque está firmada localmente y no por Apple.

## Permisos

macOS pide cada permiso la primera vez que se necesita:

| Permiso | Para qué |
| --- | --- |
| Automatización (Música / Spotify) | Canción actual, portada y controles |
| Calendario y Recordatorios | Agenda, próximo evento y avisos |
| Ubicación | Clima (también puedes elegir una ciudad a mano) |
| Cámara | Espejo, solo con la pestaña abierta |
| Bluetooth | Batería de AirPods y otros dispositivos |
| Accesibilidad (opcional) | Pegar desde el portapapeles con un clic y reemplazar el indicador de volumen/brillo de macOS |

Como la app está firmada ad-hoc, **cada vez que la recompilas** macOS la trata como una app nueva
y puede volver a pedir los permisos (sobre todo Accesibilidad). Si algo deja de responder,
quita Lagoon de *Ajustes del Sistema → Privacidad y seguridad → Accesibilidad* y vuelve a añadirla.

## Estructura

```
Sources/Lagoon/
  App/          arranque, estado global, enlaces a Ajustes del Sistema
  Notch/        ventana, geometría del notch, máquina de estados y animaciones
  Activities/   actividades en vivo (alas y bloques) y modo "soltar archivos"
  Panel/        panel expandido: Inicio, Música, Bandeja, Agenda, Timer, Portapapeles, Espejo…
  Services/     música, batería, Bluetooth, audio/brillo, calendario, clima, portapapeles, bandeja, timer, cámara
  Design/       colores, tipografía, íconos, componentes y curvas de animación
  Settings/     preferencias y ventana de Ajustes
  Snapshots/    modo `--snapshots` que renderiza cada estado a PNG con datos de ejemplo
Resources/      Info.plist e ícono provisional
scripts/        build-app.sh
tools/          generador del subconjunto de la fuente de íconos
```

## Capturas de cada estado

```bash
./build/Lagoon.app/Contents/MacOS/Lagoon --snapshots ~/Desktop/lagoon-capturas
```

Genera un PNG por cada pantalla del prototipo (1a…5f) con los datos de ejemplo del diseño.
GitHub Actions también las genera en cada push (artefacto `snapshots`) junto con la app ya
compilada (artefacto `Lagoon-app`).

## Créditos

Íconos: [Material Symbols Rounded](https://fonts.google.com/icons) de Google (licencia Apache 2.0),
subconjunto estático embebido en `Design/IconFontData.swift`. El clima viene de
[Open-Meteo](https://open-meteo.com).
