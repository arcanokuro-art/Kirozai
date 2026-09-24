# Kirozai

Primer prototipo de un editor de dibujo multiplataforma hecho con Flutter. Este proyecto es nuevo: el código de Pinta no está copiado aquí.

## Funciones actuales

- Lienzo de 1024 × 768 píxeles, pincel con color de paleta o color personalizado y grosor, borrador por capa, línea recta y rectángulo.
- Capas editables, visibilidad, agregar, duplicar, renombrar, reordenar y borrar capas.
- Deshacer y rehacer trazos y cambios de capas.
- Atajos de escritorio: Ctrl/Cmd+Z para deshacer, Ctrl+Y o Ctrl/Cmd+Mayús+Z para rehacer y Ctrl/Cmd+S para guardar.
- Navegación del lienzo mediante el modo «Mover / zoom» y exportación PNG al almacenamiento temporal para compartir o guardar con el sistema.
- Guardar y volver a abrir el proyecto editable en el almacenamiento privado de la aplicación (`kirozai-project.json`). Guardar sustituye el proyecto anterior; exportar PNG crea una imagen para compartir.
- El título muestra un punto cuando hay cambios pendientes; abrir el proyecto guardado solicita confirmación antes de descartar esos cambios.
- Nuevo dibujo con confirmación antes de reemplazar el lienzo actual.

## Ejecutar

Instala Flutter y usa `flutter create --platforms=android,ios,windows,macos,linux .` una vez para generar los proyectos de plataforma (se necesitan las herramientas de compilación correspondientes a cada sistema). Luego ejecuta `flutter pub get`, `flutter run`, `flutter analyze` y `flutter test`.

Los proyectos de plataforma se generan a partir de esta base y se añadirán al repositorio después de comprobar la compilación en los sistemas de destino. La exportación funciona con la interfaz de compartir del sistema; la edición de imágenes importadas y los formatos adicionales aún no están implementados.
