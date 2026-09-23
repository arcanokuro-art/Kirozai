# Kirozai

Primer prototipo de un editor de dibujo multiplataforma hecho con Flutter. Este proyecto es nuevo: el código de Pinta no está copiado aquí.

## Funciones actuales

- Lienzo de 1024 × 768 píxeles, pincel con color y grosor, borrador por capa.
- Capas editables, visibilidad, agregar y borrar capas.
- Deshacer y rehacer trazos y cambios de capas.
- Navegación del lienzo mediante el modo «Mover / zoom» y exportación PNG al almacenamiento temporal para compartir o guardar con el sistema.

## Ejecutar

Instala Flutter y usa `flutter create --platforms=android,ios,windows,macos,linux .` una vez para generar los proyectos de plataforma (se necesitan las herramientas de compilación correspondientes a cada sistema). Luego ejecuta `flutter pub get`, `flutter run`, `flutter analyze` y `flutter test`.

Los proyectos de plataforma se generan a partir de esta base y se añadirán al repositorio después de comprobar la compilación en los sistemas de destino. La exportación funciona con la interfaz de compartir del sistema; la edición de imágenes importadas, persistencia de proyectos y formatos adicionales aún no están implementados.
