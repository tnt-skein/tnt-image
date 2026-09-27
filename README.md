# tnt-image

Изображения на Tarantool программой ImageMagick: размер, обрезка, перевод
формата, качество, поворот по метке ориентации, удаление метаданных
и превью. Картинку разбирает отдельный процесс со сроком и пределом памяти,
узел не стоит, а отказ — пара `nil, err` с родом.

```lua
local image = require('tnt.image')

local images = image.new({ timeout = 10 })

images:inspect(photo)                                                    --> { format = 'jpeg', width = 3000, height = 4000, orientation = 6 }
images:thumbnail(photo, { width = 256, height = 256, format = 'webp' })  --> { data = 'RIFF…', format = 'webp', width = 256, height = 256 }
images:transform(photo, { resize = { width = 1200 }, format = 'webp', quality = 80 })
--> { data = 'RIFF…', format = 'webp', width = 1200, height = 1600 }

local avatar, err = images:transform(upload, { resize = { width = 256 } })

if avatar == nil and err.kind == image.INVALID then
    -- прислали не картинку — сказать посетителю, а не чинить узел
end
```

Зависимости: [tnt-process](https://github.com/tnt-skein/tnt-process),
[tnt-fs](https://github.com/tnt-skein/tnt-fs),
[tnt-clock](https://github.com/tnt-skein/tnt-clock),
[tnt-must](https://github.com/tnt-skein/tnt-must),
[tnt-external](https://github.com/tnt-skein/tnt-external). На машине —
ImageMagick 7 (программа `magick`) либо 6 (`convert`); какие пакеты
дистрибутива ставить — в документе.

## Зачем

Аватар, обложка статьи, превью ссылки — картинка, которую прислал
посетитель и которую надо уменьшить, обрезать и перевести в формат,
который браузер отдаёт быстро. Делать это в процессе узла опасно, и пакет
закрывает каждую из причин:

- **Разборщик живёт отдельно.** Разборщики форматов написаны на C, а файл
  присылает посетитель. Падение разборщика на злом файле — отказ `signal`,
  а не упавший узел; у процесса есть срок и предел памяти.
- **Узел не ждёт.** Процесс идёт через `tnt-process` поверх встроенного
  `popen`, и соседние файберы работают, пока снимок уменьшается.
- **Пределы — до разбора.** Размер входа проверяется до запуска, сторона
  и число точек — по заголовку: GIF в 29 байт, который просит кадр
  30 000×30 000, получает отказ до того, как программа развернёт его
  в памяти.
- **Формат входа — по сигнатуре.** JPEG, PNG, GIF, WebP и AVIF узнаются
  по первым байтам и называются программе явно: сценарии под видом
  картинки она не читает.
- **Отказ с родом.** Не изображение, повреждено, больше предела, формат
  не по силам, область вне изображения — каждое своим родом, по словам
  программы.

## Установка

```sh
tt rocks install tnt-image --server=https://tnt-skein.github.io/rocks
```

Или из исходников:

```sh
git clone https://github.com/tnt-skein/tnt-image.git
cd tnt-image && tt rocks make --server=https://tnt-skein.github.io/rocks
```

## Как пользоваться

| Вызов | Что отдаёт |
|---|---|
| `image.new(настройки)` | клиент: `program`, `path`, `timeout`, `temp_dir`, пределы `max_bytes`, `max_side`, `max_pixels`, `memory` |
| `images:inspect(данные, настройки)` | `{ format, width, height, orientation }` по заголовку — точки не читаются |
| `images:transform(данные, настройки)` | `{ data, format, width, height }`: поворот по метке, обрезка, размер, удаление метаданных, формат и качество |
| `images:thumbnail(данные, настройки)` | то же: рамка заполнена, лишнее обрезано по центру, меньшее рамки не растёт |
| `image.format(данные)` | формат по сигнатуре без запуска программы; `nil` — не изображение |

Обложка статьи — полоса из середины снимка:

```lua
images:transform(photo, {
    crop = { x = 0, y = 1200, width = 3000, height = 1575 },
    resize = { width = 1200 },
    format = 'jpeg',
    quality = 82,
})
--> { data = '\xFF\xD8\xFF…', format = 'jpeg', width = 1200, height = 630 }
```

Отказ — таблица с родом `kind` (`invalid`, `corrupt`, `too_large`,
`unsupported`, `outside`, `missing`, `denied`, `timeout`, `signal`,
`failed`), текстом `message` и причиной словами программы `reason`;
читается она как строка:

```lua
images:transform(photo:sub(1, math.floor(#photo / 2)))
--> nil, magick: изображение повреждено (Premature end of JPEG file)
images:transform(gif)          -- 29 байт, заголовок 30000×30000
--> nil, magick: изображение 30000×30000 больше предела стороны 10000
image.new({ path = '/nowhere' }):transform(photo)
--> nil, программы magick и convert не найдены в /nowhere
```

Промах в аргументах — бросок на строке вызывающего, а не отказ.

## Проверки

```sh
make deps            # luatest, luacheck, luacov с cluacov, зависимости пакета и tnt-env в .rocks
make check           # форматирование, линт, проверки, покрытие с порогом 100 %
make mutants-all     # мутационное тестирование утилитой tnt-mutants из PATH, порог 100 % убитых
make image-up        # ImageMagick 7.1 в докере для живых проверок; IMAGE_STAND_VERSION=6 — 6.9; make image-down гасит
```

Покрытие строк — 100 %, убитых мутантов — 100 % (66 проверок, из них
13 живых; 363 мутанта в шести модулях). ImageMagick в проверках —
сценарий оболочки, который отвечает записанным выводом настоящих выпусков
и запоминает, с чем его позвали. Живые проверки идут против настоящих
ImageMagick 7.1 и 6.9 и без них пропускаются.

## Документ

Полное описание с обоснованием решений: [docs/image.md](docs/image.md).

## Лицензия

MIT.
