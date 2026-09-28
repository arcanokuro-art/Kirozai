# Kirozai

Prototipo de un editor de dibujo para Android hecho con Flutter. Por ahora el desarrollo y la compilación se centran en el APK. Este proyecto es nuevo: el código de Pinta no está copiado aquí.

## Funciones actuales

- Lienzo de 1024 × 768 píxeles, pincel con color de paleta o color personalizado, grosor y opacidad; borrador por capa, línea recta, rectángulo y elipse. Rectángulos y elipses pueden dibujarse con contorno o relleno.
- Capas editables, visibilidad, agregar, duplicar, renombrar, reordenar y borrar capas.
- Deshacer y rehacer trazos y cambios de capas.
- Zoom con dos dedos mientras dibujas; el modo «Mover / zoom» permite desplazar el lienzo. Exportación PNG para compartir o guardar con el sistema.
- Guardar y volver a abrir el proyecto editable en el almacenamiento privado de la aplicación (`kirozai-project.json`). Guardar sustituye el proyecto anterior; exportar PNG crea una imagen para compartir.
- El guardado escribe primero un archivo temporal y después reemplaza el proyecto para evitar dejarlo incompleto si se interrumpe la escritura.
- Compartir el proyecto editable como JSON e importarlo de nuevo mediante el selector de archivos de Android; pide confirmación si hay cambios sin guardar. Un proyecto importado queda marcado como pendiente hasta guardarlo en la aplicación.
- En pantallas pequeñas, seleccionar una herramienta cierra el panel lateral para volver al lienzo.
- Al pulsar Atrás en Android con cambios pendientes, se puede guardar, salir sin guardar o cancelar.
- El título muestra un punto cuando hay cambios pendientes; abrir el proyecto guardado solicita confirmación antes de descartar esos cambios.
- Nuevo dibujo con confirmación antes de reemplazar el lienzo actual.
- Importar imágenes PNG, JPEG o WebP como capa para dibujar encima; la imagen importada queda incluida en el proyecto editable.

## Ejecutar

Instala Flutter y usa `flutter create --platforms=android .` una vez para generar el proyecto Android. Luego ejecuta `flutter pub get`, `flutter run`, `flutter analyze` y `flutter test`.

GitHub Actions comprueba el código y genera un APK Android de prueba (`app-release.apk`) como artefacto de la ejecución. El APK de modo release utiliza la clave de depuración del proyecto Flutter generado; es para pruebas y no para publicar en una tienda.

Los proyectos de plataforma se generan a partir de esta base. La exportación funciona con la interfaz de compartir del sistema. Las imágenes importadas se ajustan al lienzo de 1024 × 768 sin deformarse; todavía no hay controles para transformarlas, recortarlas o editar sus píxeles originales.
