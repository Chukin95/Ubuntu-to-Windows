INSTALAR WINDOWS SERVER 2022 EN UN VPS LINUX (MODO RESCUE)
==========================================================

Esta guía usa el script seguro del repositorio:

https://github.com/Chukin95/Ubuntu-to-Windows

Archivo usado:

ubuntu-to-windows-safe.sh

IMPORTANTE
----------

- Ejecutar desde el modo RESCUE del proveedor y como root.
- El script NO borra el disco del sistema Linux (/dev/sda).
- Windows se instalará en el primer disco distinto de /dev/sda. En este caso
  debe ser /dev/sdb, de 100 GB.
- Verificar siempre el nombre y tamaño del disco antes de continuar. Elegir un
  disco incorrecto puede destruir sus datos.
- Se requiere KVM habilitado, al menos 6 GB de RAM disponible para la ISO y
  una conexión SSH al VPS.

1. COMPROBAR KVM Y LOS DISCOS
-----------------------------

Entrar como root:

su -

Comprobar que KVM existe:

ls -l /dev/kvm

Debe mostrar un dispositivo parecido a:

crw-rw---- 1 root kvm ... /dev/kvm

Comprobar los discos:

lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS

Ejemplo esperado:

sda     2.9G
└─sda1  2.9G ext4   /
sdb     100G

En este ejemplo, /dev/sda es Linux Rescue y /dev/sdb será Windows.
NO continúe si no hay un segundo disco vacío destinado a Windows.

2. LIBERAR ESPACIO EN LA RAÍZ
-----------------------------

El sistema Rescue suele tener una raíz pequeña. La ISO de Windows se descarga
en RAM, pero el script necesita espacio libre para archivos auxiliares.

df -h / /dev/shm

Se recomienda disponer de al menos 150 MiB libres en /.
Si no hay espacio, se pueden eliminar restos de intentos anteriores:

rm -f /mnt/SERVER_EVAL_x64FRE_es-es.iso
rm -f /tmp/vkvm.tar.gz
rm -rf /tmp/vkvm*
rm -f /sw.iso
rm -f /floppy/Firefox.exe /floppy/WinRAR.exe
rm -f /virtio/virtio-win.iso*
apt-get clean
rm -rf /var/lib/apt/lists/*
journalctl --vacuum-size=20M
sync
df -h / /dev/shm

No borrar /usr, /var ni /boot manualmente.

3. DESCARGAR EL SCRIPT DESDE GITHUB
-----------------------------------

rm -f /opt/ubuntu-to-windows-safe.sh

wget -O /opt/ubuntu-to-windows-safe.sh \
'https://raw.githubusercontent.com/Chukin95/Ubuntu-to-Windows/main/ubuntu-to-windows-safe.sh'

sed -i 's/\r$//' /opt/ubuntu-to-windows-safe.sh
chmod 700 /opt/ubuntu-to-windows-safe.sh
bash -n /opt/ubuntu-to-windows-safe.sh

Si bash -n no muestra salida, la sintaxis es correcta.

4. EJECUTAR EL SCRIPT
---------------------

Comprobar espacio antes de ejecutar:

df -h / /dev/shm

Ejecutar:

bash /opt/ubuntu-to-windows-safe.sh

El script hace lo siguiente:

- Comprueba virtualización y /dev/kvm.
- Reutiliza o descarga la ISO de Windows Server 2022 en:
  /dev/shm/qemu/SERVER_EVAL_x64FRE_es-es.iso
- Verifica el SHA-256 de la ISO.
- Crea un ISO auxiliar pequeño con EnableRDP.ps1.
- Inicia Windows mediante QEMU/KVM y VNC en el puerto 5909.

COMPROBAR QUE QEMU Y VNC ESTÁN ACTIVOS
--------------------------------------

ps -ef | grep '[q]emu-system-x86_64'
ss -ltnp | grep ':5909'

Debe aparecer LISTEN en 0.0.0.0:5909 o [::]:5909.

Prueba local de VNC en el VPS:

timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.1/5909; head -c 12 <&3'

La respuesta esperada contiene:

RFB 003.008

5. CONECTAR VNC DE FORMA SEGURA MEDIANTE UN TÚNEL PUTTY
-------------------------------------------------------

No hace falta exponer el puerto VNC al público. En el PC:

1. Abrir PuTTY y cargar la sesión SSH del VPS.
2. Antes de conectar, ir a Connection > SSH > Tunnels.
3. Configurar:

   Source port: 5909
   Destination: 127.0.0.1:5909
   Tipo: Local
   Dirección: Auto

4. Pulsar Add. Debe aparecer:

   L5909  127.0.0.1:5909

5. Volver a Session, guardar si se desea y pulsar Open.
6. Mantener la ventana PuTTY abierta durante toda la instalación.

Comprobar el túnel desde PowerShell en el PC:

Test-NetConnection 127.0.0.1 -Port 5909

Debe mostrar:

TcpTestSucceeded : True

Abrir TightVNC Viewer (u otro visor compatible) y conectar a:

127.0.0.1::5909

El doble :: indica un número de puerto explícito en TightVNC.

6. INSTALAR WINDOWS DESDE VNC
-----------------------------

En el instalador de Windows:

1. Elegir idioma y continuar.
2. Seleccionar:

   Windows Server 2022 Standard Evaluation (Experiencia de escritorio)

   La opción "Experiencia de escritorio" incluye interfaz gráfica.

3. En tipo de instalación, elegir:

   Personalizada: instalar solo Windows (avanzado)

4. Seleccionar el disco de 100 GB destinado a Windows (/dev/sdb en el ejemplo).
5. Dejar que el instalador cree sus particiones automáticamente.
6. Completar la instalación inicial de Windows.

DESPUÉS DEL PRIMER REINICIO
---------------------------

Si el instalador vuelve a aparecer tras el primer reinicio, apagar la VM y
arrancarla sin la ISO. No repetir la instalación sobre el disco ya particionado.

Para detener la VM desde Linux:

pkill qemu-system-x86_64

Para iniciar Windows ya instalado, el comando debe arrancar desde /dev/sdb sin
la unidad de CD de la ISO. Guardar el comando de QEMU o adaptar el script para
un modo de arranque posterior a la instalación.

SOLUCIÓN DE PROBLEMAS
---------------------

"No space left on device" al descargar la ISO:
  La ISO no debe descargarse en /mnt ni en /. Debe usar /dev/shm/qemu.
  Comprobar: df -h / /dev/shm /dev/shm/qemu

"Couldn't create temporary file /tmp/apt.conf...":
  La raíz del sistema Rescue está llena. Liberar espacio según el paso 2.
  Si las dependencias ya existen, no es necesario actualizar APT.

VNC no conecta desde el PC:
  Confirmar primero RFB 003.008 dentro del VPS y luego comprobar el túnel SSH
  con Test-NetConnection 127.0.0.1 -Port 5909.

QEMU muestra una opción inválida:
  Usar la versión actual del script. No debe contener -show-cursor ni
  -localtime; usa -rtc base=localtime.

