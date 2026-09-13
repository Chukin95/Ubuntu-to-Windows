#!/usr/bin/env bash
set -euo pipefail

# Windows Server VM over KVM on Linux
# SAFE VERSION: does NOT delete the host Linux system

GREEN='\033[1;32m'
GREEN_D='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ISO_URL='https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_es-es.iso'
ISO_PATH='/dev/shm/qemu/SERVER_EVAL_x64FRE_es-es.iso'
EXPECTED_SHA256='052C7D7785A99DB7C5FF710090050FBD424A2F17312F0C6463E959E4E19CEE98'

echo "=== Verificando entorno ==="
if ! grep -Eiq 'vmx|svm' /proc/cpuinfo; then
  echo -e "[Error] ${RED}La virtualización/KVM está apagada.${NC}"
  exit 1
fi

if [[ ! -e /dev/kvm ]]; then
  echo -e "[Error] ${RED}/dev/kvm no existe. KVM no está disponible.${NC}"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo -e "[Error] ${RED}Debe ejecutarse como root. Usa sudo o entra como root.${NC}"
  exit 1
fi

ROOT_FREE_MB=$(df -Pm / | awk 'NR == 2 {print $4}')
if (( ROOT_FREE_MB < 150 )); then
  echo -e "[Error] ${RED}La partición raíz tiene menos de 150 MiB libres.${NC}"
  echo "Elimina descargas incompletas, por ejemplo: /mnt/SERVER_EVAL_x64FRE_es-es.iso"
  exit 1
fi

echo "=== Instalando paquetes ==="
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y sudo wget curl vim genisoimage qemu-kvm qemu-utils
elif command -v yum >/dev/null 2>&1; then
  yum update -y
  yum install -y sudo wget curl vim genisoimage qemu-kvm qemu-img
else
  echo -e "[Error] ${RED}Sistema no soportado.${NC}"
  exit 1
fi

ln -sf /usr/bin/genisoimage /usr/bin/mkisofs 2>/dev/null || true

mkdir -p /floppy /dev/shm/qemu /sw

SHM_FREE_MB=$(df -Pm /dev/shm/qemu | awk 'NR == 2 {print $4}')
if (( SHM_FREE_MB < 5000 )); then
  echo -e "[Error] ${RED}Se necesitan al menos 5.000 MiB libres en /dev/shm para la ISO.${NC}"
  exit 1
fi

echo "=== Descargando ISO ==="
if [[ ! -f "$ISO_PATH" ]]; then
  wget -O "$ISO_PATH" "$ISO_URL"
fi

ACTUAL_SHA=$(sha256sum "$ISO_PATH" | awk '{print toupper($1)}')
if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA256" ]]; then
  echo -e "[Error] ${RED}SHA256 no coincide.${NC}"
  echo "Esperado: $EXPECTED_SHA256"
  echo "Obtenido: $ACTUAL_SHA"
  exit 1
fi

echo "ISO verificada: $ISO_PATH"

echo "=== Preparando archivos de arranque y drivers ==="
wget -O /floppy/Firefox.exe \
  'https://ftp.mozilla.org/pub/firefox/releases/64.0/win32/en-US/Firefox%20Setup%2064.0.exe' || true

wget -O /floppy/WinRAR.exe \
  'https://archive.org/download/winrar-x64-591es/winrar-x64-591es.exe' || true

cat > /floppy/EnableRDP.ps1 <<'EOF'
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\' -Name "fDenyTSConnections" -Value 0
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp\' -Name "UserAuthentication" -Value 1
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
EOF

mkisofs -o /sw.iso /floppy

echo "=== Detectando disco disponible ==="
CPUS=$(nproc)
AVAILABLE_RAM_MB=$(free -m | awk '/^Mem:/ {print ($7 > 0 ? $7 : $4)}')
RAM_ARG="-m $((AVAILABLE_RAM_MB - 200))M"

DISK=""
for d in $(lsblk -dn -o NAME,TYPE | awk '$2=="disk" {print "/dev/"$1}'); do
  case "$d" in
    /dev/loop*|/dev/sda)
      continue
      ;;
    *)
      DISK="$d"
      break
      ;;
  esac
done

if [[ -z "$DISK" ]]; then
  echo "No hay segundo disco; creando /disk.img"
  dd if=/dev/zero of=/disk.img bs=1M count=40960 status=none
  DISK="/disk.img"
fi

IP=$(curl -fsSL ifconfig.me || hostname -I | awk '{print $1}')

echo "=== Arrancando VM ==="
QEMU_BIN=$(command -v qemu-system-x86_64)

"$QEMU_BIN" \
  -net nic \
  -net user,hostfwd=tcp::3389-:3389 \
  -show-cursor \
  $RAM_ARG \
  -localtime \
  -enable-kvm \
  -cpu host,hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time,+nx \
  -M pc \
  -smp "cores=$CPUS" \
  -vga std \
  -machine type=pc,accel=kvm \
  -usb \
  -device usb-tablet \
  -k en-us \
  -drive "file=$DISK,index=0,media=disk,format=raw" \
  -drive "file=$ISO_PATH,index=1,media=cdrom" \
  -drive "file=/sw.iso,index=2,media=cdrom" \
  -boot once=d \
  -vnc :9 &

sleep 3

echo -e "${YELLOW}La VM está arrancando.${NC}"
echo -e "${BLUE}Conéctate por VNC a: ${IP}:9${NC}"
echo -e "${GREEN}Si quieres detenerla más tarde: pkill qemu-system-x86_64${NC}"
echo "Job Done :)"
