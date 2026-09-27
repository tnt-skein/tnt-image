#!/usr/bin/env bash
# Поднимает ImageMagick в контейнере для живых проверок tnt-image.
#
# Настоящая программа, а не двойник: двойник показывает, что мы правильно
# разбираем записанный вывод, а живой прогон — что программа отвечает
# именно так: какие слова на обрезанный JPEG, что пишет вместо формата
# без кодировщика, когда отказывает предел памяти, как поворачивает
# по метке EXIF.
#
# Два выпуска, по одному за подъём, — те, что ставятся пакетом на машинах
# развёртывания:
#   7 (по умолчанию) — ImageMagick 7.1 из Debian 13, программа magick;
#   6                — ImageMagick 6.9 из Ubuntu 24.04, программа convert.
# Выпуск выбирает IMAGE_STAND_VERSION. Образ собирается один раз: apt при
# каждом подъёме ходил бы в сеть.
#
# Программа видна хозяину сценарием в run/image/bin: он зовёт настоящую
# программу в контейнере через docker exec и передаёт ей язык и временный
# каталог. Каталог run/image/work смонтирован в контейнер тем же путём —
# временные каталоги пакета, заведённые в нём, программа видит там же.
#
# Чем стенд отличается от узла: процесс, убитый по сроку, — это docker
# exec на хозяине, а программа в контейнере дорабатывает сама. Срок
# и отказ по нему проверяются честно, убийство программы — нет.
#
#   test/stand/image.sh          # поднять
#   test/stand/image.sh stop     # погасить
set -euo pipefail

# Относительный каталог отсчитывается от места запуска: оттуда его
# читает и живая проверка. Ниже сценарий переходит в свой каталог, и без
# этого стенд лёг бы в одно место, а проверка искала бы его в другом.
case "${IMAGE_STAND_DIR:-}" in
    '' | /*) ;;
    *) IMAGE_STAND_DIR="${PWD}/${IMAGE_STAND_DIR}" ;;
esac

cd "$(dirname "$0")"

VERSION="${IMAGE_STAND_VERSION:-7}"
CONTAINER='tnt-stand-image'
DIR="${IMAGE_STAND_DIR:-run/image}"

# Образы закреплены отпечатком: тег мог бы тихо уехать на другую сборку.
case "${VERSION}" in
    7)
        BASE='debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a'
        PACKAGES='imagemagick libmagickcore-7.q16-10-extra'
        PROGRAM='magick'
        ;;
    6)
        BASE='ubuntu@sha256:008173c23f95b170204355c12626cb5a965d779a7e1283b09e9cffbb1bf33ca3'
        PACKAGES='imagemagick libmagickcore-6.q16-7-extra'
        PROGRAM='convert'
        ;;
    *)
        echo "выпуск ImageMagick «${VERSION}» неизвестен: 7 либо 6" >&2
        exit 2
        ;;
esac

IMAGE="tnt-stand-image:${VERSION}"

if ! command -v docker > /dev/null 2>&1; then
    echo 'docker не найден: ImageMagick поднять нечем' >&2
    exit 1
fi

if [ "${1:-up}" = 'stop' ]; then
    docker rm -f "${CONTAINER}" > /dev/null 2>&1 || true
    rm -rf "${DIR}"
    echo 'ImageMagick остановлен'
    exit 0
fi

if ! docker image inspect "${IMAGE}" > /dev/null 2>&1; then
    docker build -q -t "${IMAGE}" - > /dev/null << DOCKERFILE
FROM ${BASE}
RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends ${PACKAGES} > /dev/null && rm -rf /var/lib/apt/lists/*
DOCKERFILE
fi

docker rm -f "${CONTAINER}" > /dev/null 2>&1 || true
rm -rf "${DIR}"
mkdir -p "${DIR}/bin" "${DIR}/work"
DIR="$(cd "${DIR}" && pwd)"

docker run -d --name "${CONTAINER}" -v "${DIR}/work:${DIR}/work" --entrypoint sleep "${IMAGE}" infinity > /dev/null

# Сценарий для хозяина. Пакет запускает программу с окружением из пяти
# переменных, и HOME среди них нет, а docker без HOME ищет свои настройки
# не там: он вписан в сценарий при подъёме.
cat > "${DIR}/bin/${PROGRAM}" << WRAPPER
#!/bin/sh
HOME='${HOME}'
export HOME
exec docker exec -i -e LANG -e LC_ALL -e MAGICK_TEMPORARY_PATH -e TMPDIR ${CONTAINER} ${PROGRAM} "\$@"
WRAPPER
chmod 755 "${DIR}/bin/${PROGRAM}"

version="$(docker exec "${CONTAINER}" "${PROGRAM}" -version | head -n 1)"

echo "ImageMagick поднят: ${version}; программа ${DIR}/bin/${PROGRAM}, временные каталоги в ${DIR}/work"
