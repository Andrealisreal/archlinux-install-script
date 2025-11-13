#!/bin/bash
set -e

# === Цвета для вывода ===
YELLOW="\e[33m"
GREEN="\e[32m"
RED="\e[31m"
RESET="\e[0m"

echo -e "${YELLOW}=== Очистка системы Arch Linux ===${RESET}"

# Проверка root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Ошибка: скрипт нужно запускать от имени root.${RESET}"
    exit 1
fi

echo -e "\n${YELLOW}[1/7] Очистка кеша пакетов pacman...${RESET}"
# Удаляет все старые версии пакетов, оставляя только последние
paccache -r -k1 || true
pacman -Sc --noconfirm || true

echo -e "\n${YELLOW}[2/7] Удаление неиспользуемых зависимостей...${RESET}"
# Удаляет пакеты, установленные как зависимости, которые больше не нужны
pacman -Qtdq | xargs -r pacman -Rns --noconfirm

echo -e "\n${YELLOW}[3/7] Очистка временных файлов...${RESET}"
rm -rf /var/tmp/* /tmp/*
journalctl --vacuum-time=3d

echo -e "\n${YELLOW}[4/7] Очистка кэша пользователей...${RESET}"
for dir in /home/*; do
    if [ -d "$dir/.cache" ]; then
        rm -rf "$dir/.cache/"*
    fi
done
rm -rf /root/.cache/*

echo -e "\n${YELLOW}[5/7] Проверка осиротевших пакетов...${RESET}"
orphans=$(pacman -Qtdq || true)
if [ -n "$orphans" ]; then
    echo -e "${RED}Найдены осиротевшие пакеты:${RESET}"
    echo "$orphans"
    read -rp "Удалить их? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        pacman -Rns --noconfirm $orphans
    fi
else
    echo -e "${GREEN}Осиротевших пакетов не найдено.${RESET}"
fi

echo -e "\n${YELLOW}[6/7] Очистка ненужных журналов systemd...${RESET}"
journalctl --vacuum-size=100M

echo -e "\n${YELLOW}[7/7] Оптимизация базы пакетов и defrag Btrfs (если используется)...${RESET}"
pacman-optimize || true
if findmnt -n -o FSTYPE / | grep -q btrfs; then
    btrfs filesystem defragment -r -v /
fi

echo -e "\n${GREEN}✅ Очистка завершена!${RESET}"
echo -e "Система оптимизирована и готова к работе."
