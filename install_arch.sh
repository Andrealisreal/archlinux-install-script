#!/bin/bash
set -e

# === Цвета для вывода ===
YELLOW="\e[33m"
GREEN="\e[32m"
RED="\e[31m"
RESET="\e[0m"

echo -e "${YELLOW}=== Arch Linux автоматизированная установка ===${RESET}"

# === Выбор диска ===
echo -e "\n${YELLOW}[1/12] Доступные диски:${RESET}"
lsblk -dpno NAME,SIZE | grep -v loop
echo ""
read -rp "Введите путь к диску (например /dev/nvme0n1): " DISK

if [ ! -b "$DISK" ]; then
    echo -e "${RED}Ошибка: диск $DISK не найден.${RESET}"
    exit 1
fi

# === Ввод имени пользователя ===
read -rp "Введите имя пользователя: " USERNAME
USERNAME=${USERNAME:-andreal}

# === Настройки ===
HOSTNAME="archlinux"
TIMEZONE="Europe/Saratov"
LOCALE="en_US.UTF-8"
SWAP_SIZE="ram / 2"

echo -e "\n${YELLOW}[2/12] Настройка времени и региона...${RESET}"
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

echo -e "\n${YELLOW}[3/12] Настройка зеркал...${RESET}"
reflector --country Russia --latest 10 --sort rate --save /etc/pacman.d/mirrorlist

echo -e "\n${YELLOW}[4/12] Разметка и форматирование диска $DISK...${RESET}"
sgdisk --zap-all $DISK
parted -s $DISK mklabel gpt
parted -s $DISK mkpart ESP fat32 1MiB 257MiB
parted -s $DISK set 1 esp on
parted -s $DISK mkpart primary ext4 257MiB 200257MiB
parted -s $DISK mkpart primary ext4 200257MiB 100%

mkfs.vfat ${DISK}p1
mkfs.ext4 ${DISK}p2
mkfs.ext4 ${DISK}p3

mount ${DISK}p2 /mnt
mkdir -p /mnt/boot/efi /mnt/home
mount ${DISK}p1 /mnt/boot/efi
mount ${DISK}p3 /mnt/home

echo -e "\n${YELLOW}[5/12] Установка базовой системы...${RESET}"
pacstrap /mnt base base-devel linux linux-firmware linux-headers nano vim bash-completion \
grub efibootmgr ttf-ubuntu-font-family ttf-hack ttf-dejavu ttf-opensans gdm gnome nvidia \
networkmanager sudo telegram-desktop chromium bluez bluez-utils gnome-bluetooth \
gnome-bluetooth-3.0 sof-firmware gnome-tweaks zram-generator

genfstab -U /mnt >> /mnt/etc/fstab

echo -e "\n${YELLOW}[6/12] Настройка системы в chroot...${RESET}"
arch-chroot /mnt /bin/bash <<EOF
set -e

echo "$HOSTNAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

echo "LANG=$LOCALE" > /etc/locale.conf
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
sed -i 's/^#\(ru_RU.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen

systemctl enable NetworkManager
systemctl enable bluetooth.service
systemctl enable gdm

useradd -m $USERNAME
echo "Установите пароль для пользователя $USERNAME:"
passwd $USERNAME
echo "Установите пароль для root:"
passwd root

echo "$USERNAME ALL=(ALL:ALL) ALL" >> /etc/sudoers

cat <<ZRAMCONF > /etc/systemd/zram-generator.conf
[zram0]
zram-size = $SWAP_SIZE
compression-algorithm = zstd
swap-priority = 100
ZRAMCONF

grub-install $DISK
sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/quiet *//g' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

EOF

echo -e "\n${GREEN}[✔] Установка завершена успешно!${RESET}"
echo -e "Теперь можешь выполнить:${YELLOW} reboot${RESET}"
