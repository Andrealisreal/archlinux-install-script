#!/bin/bash
set -e

# === ЦВЕТА ===
YELLOW="\e[33m"
GREEN="\e[32m"
RED="\e[31m"
BLUE="\e[34m"
RESET="\e[0m"

# === ПОДДЕРЖКА РУССКОГО В LIVE CD ===
if command -v setfont &>/dev/null; then
    setfont ter-v16b 2>/dev/null || setfont LatGrkCyr-8x16 2>/dev/null || true
fi
export LANG=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8

# === ФУНКЦИЯ ПОДТВЕРЖДЕНИЯ ===
confirm() {
    echo -e "${YELLOW}⚠️  $1${RESET}"
    read -rp "Продолжить? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}❌ Установка отменена пользователем.${RESET}"
        exit 130
    fi
}

echo -e "${BLUE}════════════════════════════════════════${RESET}"
echo -e "${YELLOW}   Установка Arch Linux (Cinnamon + Xorg)${RESET}"
echo -e "${BLUE}════════════════════════════════════════${RESET}"

# === [1/10] ВЫБОР ДИСКА ===
echo -e "\n${YELLOW}[1/10] Доступные диски:${RESET}"
lsblk -dpno NAME,SIZE,MODEL | grep -v loop | grep -v rom
echo ""
read -rp "Введите целевой диск (например, /dev/nvme0n1): " DISK

if [ ! -b "$DISK" ]; then
    echo -e "${RED}❌ Ошибка: Диск $DISK не найден.${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ Выбран диск: $DISK${RESET}"

# === ПРОВЕРКА ИНТЕРНЕТА ===
echo -e "${YELLOW}Проверка подключения к интернету...${RESET}"
if ! ping -c 1 archlinux.org &>/dev/null; then
    echo -e "${RED}❌ Ошибка: Нет подключения к интернету!${RESET}"
    echo -e "Подключите кабель или настройте WiFi через 'iwctl'"
    exit 1fi
echo -e "${GREEN}✓ Интернет работает${RESET}"

# === [2/10] ИМЯ ПОЛЬЗОВАТЕЛЯ ===
read -rp "Введите имя пользователя (латиницей, без пробелов): " USERNAME
USERNAME="${USERNAME:-andreal}"
if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    echo -e "${RED}❌ Имя пользователя должно начинаться с буквы и содержать только латиницу/цифры.${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ Имя пользователя: $USERNAME${RESET}"

# === НАСТРОЙКИ СИСТЕМЫ ===
HOSTNAME="archlinux"
TIMEZONE="Europe/Saratov"
LOCALE_MAIN="en_US.UTF-8"
LOCALE_ADD="ru_RU.UTF-8"
SWAP_SIZE="ram / 2"

# === [3/10] ИНИЦИАЛИЗАЦИЯ КЛЮЧЕЙ PACMAN ===
echo -e "\n${YELLOW}[3/10] Инициализация ключей pacman...${RESET}"
confirm "Будут созданы GPG-ключи для проверки пакетов (может занять время)"
mount -o remount,rw / 2>/dev/null || true
if [ ! -d /etc/pacman.d/gnupg ]; then
    mkdir -p /etc/pacman.d/gnupg
fi
pacman-key --init
pacman-key --populate archlinux

# === [4/10] ОБНОВЛЕНИЕ БАЗЫ И REFLECTOR ===
echo -e "\n${YELLOW}[4/10] Обновление базы пакетов и установка reflector...${RESET}"
pacman -Sy --noconfirm
if ! command -v reflector &>/dev/null; then
    echo -e "${YELLOW}Установка reflector...${RESET}"
    pacman -S --noconfirm reflector
fi
confirm "Будет обновлён файл /etc/pacman.d/mirrorlist (Россия)"
reflector --country Russia --latest 10 --sort rate --save /etc/pacman.d/mirrorlist

# === [5/10] РАЗМЕТКА ДИСКА (ПРОЦЕНТЫ) ===
echo -e "\n${YELLOW}[5/10] Разметка диска $DISK (проценты)...${RESET}"
echo -e "Схема разделов:"
echo -e "  ${GREEN}p1${RESET}: 1 MiB → 512 MiB   (~0.2%)  → ESP (загрузчик)"
echo -e "  ${GREEN}p2${RESET}: 512 MiB → 35%     (~33%)   → / (система + Unity)"
echo -e "  ${GREEN}p3${RESET}: 35% → 100%        (~65%)   → /home (файлы + ассеты)"
confirm "⚠️  ВСЕ ДАННЫЕ НА ДИСКЕ $DISK БУДУТ УДАЛЕНЫ! Продолжить?"

# Очистка и разметка
sgdisk --zap-all "$DISK"
parted -s "$DISK" mklabel gptparted -s "$DISK" mkpart ESP fat32 1MiB 512MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary ext4 512MiB 35%
parted -s "$DISK" mkpart primary ext4 35% 100%

# === 🔧 ВАЖНО: Определяем префикс разделов (p для NVMe, пусто для SATA) ===
if [[ "$DISK" == /dev/nvme* ]]; then
    PART_PREFIX="p"
else
    PART_PREFIX=""
fi
echo -e "${GREEN}✓ Префикс разделов: '${PART_PREFIX}' (NVMe: 'p', SATA: '')${RESET}"

# Форматирование
mkfs.vfat "${DISK}${PART_PREFIX}1"
mkfs.ext4 "${DISK}${PART_PREFIX}2"
mkfs.ext4 "${DISK}${PART_PREFIX}3"

# Монтирование
mount "${DISK}${PART_PREFIX}2" /mnt
mkdir -p /mnt/boot/efi /mnt/home
mount "${DISK}${PART_PREFIX}1" /mnt/boot/efi
mount "${DISK}${PART_PREFIX}3" /mnt/home
echo -e "${GREEN}✓ Разделы созданы и смонтированы${RESET}"

# === [6/10] УСТАНОВКА ПАКЕТОВ (PACSTRAP) ===
echo -e "\n${YELLOW}[6/10] Установка базовой системы...${RESET}"
echo -e "Пакеты: ядро, драйверы NVIDIA, Cinnamon, Xorg, утилиты..."
confirm "Начать загрузку и установку (~2.5 ГБ)? Это займёт 10-30 минут"

pacstrap /mnt \
    base base-devel linux linux-firmware linux-headers \
    intel-ucode amd-ucode \
    nano vim bash-completion \
    grub efibootmgr \
    ttf-ubuntu-font-family ttf-hack ttf-dejavu ttf-opensans \
    cinnamon lightdm lightdm-gtk-greeter \
    xorg-server xorg-xinit xorg-drivers \
    nvidia-dkms nvidia-settings \
    networkmanager network-manager-applet \
    sudo zram-generator reflector git fastfetch btop sof-firmware \
    bluez bluez-utils blueman \
    telegram-desktop chromium discord webkit2gtk

genfstab -U /mnt >> /mnt/etc/fstab
echo -e "${GREEN}✓ Базовая система установлена${RESET}"

# === [7/10] НАСТРОЙКА В CHROOT ===
echo -e "\n${YELLOW}[7/10] Настройка системы (chroot)...${RESET}"
confirm "Будут настроены: hostname, locale, пользователь, сервисы, GRUB"
cat <<CHROOT_EOF > /mnt/root/chroot-setup.sh
set -e
echo "$HOSTNAME" > /etc/hostname
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

echo "LANG=$LOCALE_MAIN" > /etc/locale.conf
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
sed -i 's/^#\(ru_RU.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen

systemctl enable NetworkManager
systemctl enable bluetooth.service
systemctl enable lightdm

useradd -m -G wheel,audio,video,input "$USERNAME"
echo "Установите пароль для пользователя $USERNAME:"
passwd "$USERNAME"
echo "Установите пароль для root:"
passwd root

echo "$USERNAME ALL=(ALL:ALL) ALL" > /etc/sudoers.d/$USERNAME
chmod 440 /etc/sudoers.d/$USERNAME

echo -e "[zram0]\nzram-size = $SWAP_SIZE\ncompression-algorithm = zstd\nswap-priority = 100" > /etc/systemd/zram-generator.conf

grub-install "$DISK"
sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/quiet *//g' /etc/default/grub
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nvidia-drm.modeset=1"/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT_EOF

arch-chroot /mnt /bin/bash -c "/root/chroot-setup.sh" < /dev/tty
rm -f /mnt/root/chroot-setup.sh
echo -e "${GREEN}✓ Система настроена${RESET}"

# === [8/10] СОЗДАНИЕ .xinitrc ===
echo -e "\n${YELLOW}[8/10] Создание ~/.xinitrc для $USERNAME...${RESET}"
confirm "Создать файл /home/$USERNAME/.xinitrc для запуска Cinnamon?"

# 🔧 Исправлен heredoc: перенос строки перед XINITRC
cat <<XINITRC > "/mnt/home/$USERNAME/.xinitrc"
#!/bin/bash
exec cinnamon-session
XINITRC
chown "$USERNAME:$USERNAME" "/mnt/home/$USERNAME/.xinitrc"
chmod +x "/mnt/home/$USERNAME/.xinitrc"
echo -e "${GREEN}✓ .xinitrc создан${RESET}"
# === [9/10] ЗАВЕРШЕНИЕ ===
echo -e "\n${YELLOW}[9/10] Размонтирование разделов...${RESET}"
confirm "Размонтировать /mnt и завершить установку?"
umount -R /mnt || echo -e "${RED}⚠️ Не удалось размонтировать некоторые разделы${RESET}"

# === [10/10] ФИНАЛ ===
echo -e "\n${GREEN}════════════════════════════════════════${RESET}"
echo -e "${GREEN}✅ Установка завершена успешно!${RESET}"
echo -e "${GREEN}════════════════════════════════════════${RESET}"
echo -e "${YELLOW}Дальнейшие действия после перезагрузки:${RESET}"
echo -e "  1. На экране входа (LightDM) выберите сессию ${YELLOW}Cinnamon (X11)${RESET}"
echo -e "  2. Войдите под пользователем ${YELLOW}$USERNAME${RESET}"
echo -e "  3. Проверьте тип сессии: ${GREEN}echo \$XDG_SESSION_TYPE${RESET} (должно быть ${GREEN}x11${RESET})"
echo -e "  4. Запустите Unity Hub — интерфейс будет работать стабильно!"
echo -e "\n${YELLOW}Перезагрузить систему сейчас?${RESET}"
read -rp "[y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Перезагрузка...${RESET}"
    reboot
fi