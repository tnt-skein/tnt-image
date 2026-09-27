--- Изображения программой ImageMagick через `tnt-process`: размер,
--- обрезка, формат, качество, поворот по метке, метаданные и превью.
---
---     local image = require('tnt.image')
---
---     local images = image.new({ timeout = 10 })
---
---     local info, err = images:inspect(photo)                       -- формат, размеры, метка
---     local avatar, err = images:thumbnail(photo, { width = 256, height = 256, format = 'webp' })
---     local cover, err = images:transform(photo, {
---         crop = { x = 100, y = 40, width = 1200, height = 630 },
---         resize = { width = 600 },
---         format = 'jpeg',
---         quality = 82,
---     })
---
--- Разбор картинок — самый опасный ввод, какой бывает у узла: файл
--- присылает посетитель, а разборщики форматов написаны на C. Поэтому
--- картинку разбирает отдельный процесс, а не код в процессе узла:
--- падение разборщика на злом файле — отказ, а не упавший узел; у процесса
--- есть срок и предел памяти, и просроченный убит; узел не стоит, пока
--- идёт преобразование. Пакет даёт то, чего у программы нет:
---
--- 1. **Отказ — пара с родом.** Не изображение, повреждено, больше
---    предела, формат не по силам — каждое своим родом.
--- 2. **Формат входа — по сигнатуре.** Программа не угадывает формат сама
---    и не читает сценариев под видом картинки.
--- 3. **Пределы — до разбора.** Размер входа проверяется до запуска,
---    сторона и число точек — по заголовку, до того как программа
---    развернёт картинку в памяти.
---
--- Подробно — `docs/image.md`.

local failure = require('tnt.process.failure')
local must = require('tnt.must')

local client = require('tnt.image.client')
local options_of = require('tnt.image.options')
local sniff = require('tnt.image.sniff')
local system = require('tnt.image.system')
local verdict = require('tnt.image.verdict')

local Module = {}

--- Программы нет: ImageMagick не установлен либо не в каталогах поиска.
Module.MISSING = failure.MISSING

--- Программа есть, но не запускается.
Module.DENIED = failure.DENIED

--- Срок вышел; процесс убит вместе с группой.
Module.TIMEOUT = failure.TIMEOUT

--- Процесс убит сигналом: разборщик упал либо его убила система.
Module.SIGNAL = failure.SIGNAL

--- Не изображение: сигнатура не узнана.
Module.INVALID = verdict.INVALID

--- Изображение повреждено.
Module.CORRUPT = verdict.CORRUPT

--- Формат программе не по силам.
Module.UNSUPPORTED = verdict.UNSUPPORTED

--- Больше предела: байтов, стороны, точек либо памяти.
Module.TOO_LARGE = verdict.TOO_LARGE

--- Область обрезки вне изображения.
Module.OUTSIDE = verdict.OUTSIDE

--- Прочее.
Module.FAILED = verdict.FAILED

--- JPEG.
Module.JPEG = sniff.JPEG

--- PNG.
Module.PNG = sniff.PNG

--- GIF.
Module.GIF = sniff.GIF

--- WebP.
Module.WEBP = sniff.WEBP

--- AVIF.
Module.AVIF = sniff.AVIF

--- Заполнить рамку и обрезать по центру.
Module.COVER = options_of.COVER

--- Вписать в рамку целиком.
Module.INSIDE = options_of.INSIDE

--- Каталоги поиска программы по умолчанию: системные и Homebrew на macOS.
Module.PATH = '/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin'

--- Срок вызова по умолчанию, секунд. Снимок в 25 мегапикселей с поворотом
--- по метке уменьшается за секунду с небольшим; срок держит медленные
--- форматы и занятую машину.
Module.DEFAULT_TIMEOUT = 30

--- Предел входа и итога по умолчанию, байт: 20 МиБ.
Module.DEFAULT_MAX_BYTES = 20 * 1024 * 1024

--- Предел стороны по умолчанию, точек.
Module.DEFAULT_MAX_SIDE = 10000

--- Предел точек входа по умолчанию: 25 мегапикселей.
Module.DEFAULT_MAX_PIXELS = 25000000

--- Предел памяти программы под точки по умолчанию, байт: 512 МиБ.
---
--- Согласован с пределом точек: точка в памяти ImageMagick стоит восемь
--- байт, а поворот по метке держит две копии кадра — 25 мегапикселей
--- с поворотом укладываются в 512 МиБ и не укладываются в 256 (проверено
--- на 7.1 и 6.9).
Module.DEFAULT_MEMORY = 512 * 1024 * 1024

--- Настройки `new`.
local NEW = {
    program = '?not_empty',
    path = '?not_empty',
    timeout = '?positive',
    temp_dir = '?not_empty',
    max_bytes = '?positive',
    max_side = '?positive',
    max_pixels = '?positive',
    memory = '?positive',
}

--- Настройки, которые считаются целыми: байты и точки.
local INTEGERS = { 'max_bytes', 'max_side', 'max_pixels', 'memory' }

---@class TntImageOptions
---@field program string|nil Программа: имя либо путь; по умолчанию `magick`, а без него `convert`
---@field path string|nil Каталоги поиска программы через `:`; по умолчанию `PATH`
---@field timeout number|nil Срок вызова по умолчанию, секунд
---@field temp_dir string|nil Где заводить временные каталоги; по умолчанию системный
---@field max_bytes integer|nil Предел входа и итога, байт
---@field max_side integer|nil Предел стороны входа и итога, точек
---@field max_pixels integer|nil Предел точек входа
---@field memory integer|nil Предел памяти программы под точки, байт

--- Новый клиент изображений.
---
--- Программа не ищется при сборке: узел, на который ImageMagick поставят
--- позже, не требует пересборки клиента, а её отсутствие — отказ
--- `missing` у вызова, а не бросок при подъёме.
---@param options TntImageOptions|nil
---@return TntImageClient
function Module.new(options)
    local caller = must.at(2)
    local given = options or {}

    caller.options(given, 'настройки', NEW)

    for _, key in ipairs(INTEGERS) do
        caller.optional.integer(given[key], 'настройки.' .. key)
    end

    return client.new({
        program = given.program,
        path = given.path or Module.PATH,
        timeout = given.timeout or Module.DEFAULT_TIMEOUT,
        temp_dir = given.temp_dir,
        max_bytes = given.max_bytes or Module.DEFAULT_MAX_BYTES,
        max_side = given.max_side or Module.DEFAULT_MAX_SIDE,
        max_pixels = given.max_pixels or Module.DEFAULT_MAX_PIXELS,
        memory = given.memory or Module.DEFAULT_MEMORY,
    })
end

--- Формат по сигнатуре без запуска программы; `nil` — не изображение
--- из пяти узнаваемых.
---
---     image.format(upload)   --> 'png'
Module.format = sniff.format

--- Подменяет часы срока. Только для проверок.
Module._set_source = system._set_source

return Module
