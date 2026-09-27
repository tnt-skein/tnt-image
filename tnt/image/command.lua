--- Аргументы ImageMagick: осмотр заголовка и преобразование.
---
--- Вход и итог идут трубой (`jpeg:-` на входе, `webp:-` на выходе),
--- а не файлами: данных на диске узла не остаётся, а формат на обоих
--- концах назван явно. Порядок действий один и не зависит от порядка
--- ключей в настройках: поворот по метке, обрезка, размер, удаление
--- метаданных, запись. Поворот первым — иначе область обрезки считалась бы
--- в координатах, которых человек на экране не видел.
---
--- Пределы программы стоят первыми в каждом вызове:
---
--- * `thread 1` — одно преобразование занимает одно ядро и не отнимает
---   процессор у самого узла;
--- * `width` и `height` — сторона любого кадра, в том числе итога:
---   увеличение сверх предела отказывает, а не съедает память;
--- * `memory` — память под точки, а `map 0` и `disk 0` запрещают
---   программе уходить с ними в файлы: без них картинка, не влезшая
---   в память, молча легла бы на диск узла.

local sniff = require('tnt.image.sniff')

local Module = {}

--- Метка строки с размерами итога в потоке ошибок.
Module.MARK = 'tnt-image'

---@class TntImageLimits Пределы программы
---@field max_side integer Предел стороны, точек
---@field memory integer Предел памяти под точки, байт

---@class TntImageCropOptions Обрезка
---@field width integer Ширина области, точек
---@field height integer Высота области, точек
---@field x integer|nil Левый край области; без `x` и `y` — область по центру
---@field y integer|nil Верхний край области

---@class TntImageResizeOptions Размер
---@field width integer|nil Ширина, точек
---@field height integer|nil Высота, точек
---@field fit string|nil `inside` — вписать в рамку (по умолчанию), `cover` — заполнить рамку и обрезать по центру
---@field enlarge boolean|nil Увеличивать ли меньшее рамки; по умолчанию нет

---@class TntImageSteps Что сделать с изображением
---@field orient boolean|nil Повернуть по метке ориентации; по умолчанию да
---@field crop TntImageCropOptions|nil Обрезка
---@field resize TntImageResizeOptions|nil Размер
---@field quality integer|nil Качество 1–100 — у форматов с потерями
---@field strip boolean|nil Удалить метаданные; по умолчанию да

--- Дописывает значения в конец списка.
---@param list string[]
---@param values string[]
---@return string[]
local function append(list, values)
    for _, value in ipairs(values) do
        table.insert(list, value)
    end

    return list
end

--- Пределы программы — начало всякого вызова.
---
--- Кусками по строке, а не столбиком: генератор мутантов пропускает
--- строку, на которой стоит одно значение, и `'1'` с `'0'` остались бы
--- без проверки.
---@param limits TntImageLimits
---@return string[]
local function limited(limits)
    local side = tostring(limits.max_side)
    local argv = { '-limit', 'thread', '1' }

    append(argv, { '-limit', 'width', side, '-limit', 'height', side })
    append(argv, { '-limit', 'memory', tostring(limits.memory), '-limit', 'map', '0', '-limit', 'disk', '0' })

    return argv
end

--- Вход трубой с названным форматом, только первый кадр.
---
--- Кадры анимации сверх первого не читаются вовсе: превью анимации
--- не нужно, а файл в тысячу кадров иначе стоил бы тысячи преобразований.
---@param format string
---@return string
local function input(format)
    return format .. ':-[0]'
end

--- Размер области: `300x200`.
---@param width integer
---@param height integer
---@return string
local function extent(width, height)
    return ('%dx%d'):format(width, height)
end

--- Обрезка по центру до размера: `-gravity center -crop 300x200+0+0`.
---
--- Область больше изображения обрезается его краем, а не дополняется
--- полями: у обрезки `crop` полей не бывает.
---@param width integer
---@param height integer
---@return string[]
local function centered(width, height)
    return { '-gravity', 'center', '-crop', extent(width, height) .. '+0+0', '+repage' }
end

--- Обрезка: область с краями либо по центру.
---@param crop TntImageCropOptions
---@return string[]
local function cropped(crop)
    if crop.x == nil then
        return centered(crop.width, crop.height)
    end

    return { '-crop', ('%s+%d+%d'):format(extent(crop.width, crop.height), crop.x, crop.y), '+repage' }
end

--- Размер: вписать в рамку либо заполнить её.
---
--- Сторона без значения не ограничена: `300x` — ширина 300, высота
--- по пропорции. `^` делает рамку нижней границей (заполнить), `>` —
--- только уменьшать: без него маленькая картинка раздулась бы до рамки.
---@param resize TntImageResizeOptions
---@return string[]
local function resized(resize)
    local size = ('%sx%s'):format(resize.width or '', resize.height or '')
    local cover = resize.fit == 'cover'

    if cover then
        size = size .. '^'
    end

    if not resize.enlarge then
        size = size .. '>'
    end

    local steps = { '-resize', size }

    if cover then
        append(steps, centered(resize.width --[[@as integer]], resize.height --[[@as integer]]))
    end

    return steps
end

--- Осмотр заголовка: ширина, высота и метка ориентации без чтения точек.
---
---     magick … -ping jpeg:-[0] -format '%w %h %[orientation]\n' info:
---@param limits TntImageLimits
---@param format string Формат входа
---@return string[]
function Module.inspect(limits, format)
    return append(limited(limits), { '-ping', input(format), '-format', '%w %h %[orientation]\\n', 'info:' })
end

--- Преобразование от входа до итога.
---
--- Размеры итога программа пишет строкой с меткой в поток ошибок
--- (`-write info:fd:2`) прямо перед записью: второй запуск ради них
--- не нужен, а поток вывода занят самим итогом. У JPEG нет прозрачности,
--- и прозрачное ложится на белое, а не на чёрное, как вышло бы само.
--- Качество уходит программе только у форматов с потерями: у PNG
--- ImageMagick читает то же число уровнем сжатия.
---@param limits TntImageLimits
---@param source string Формат входа
---@param target string Формат итога
---@param steps TntImageSteps
---@return string[]
function Module.transform(limits, source, target, steps)
    local argv = limited(limits)

    table.insert(argv, input(source))

    if steps.orient ~= false then
        table.insert(argv, '-auto-orient')
    end

    if steps.crop ~= nil then
        append(argv, cropped(steps.crop))
    end

    if steps.resize ~= nil then
        append(argv, resized(steps.resize))
    end

    if steps.strip ~= false then
        table.insert(argv, '-strip')
    end

    if target == sniff.JPEG then
        append(argv, { '-background', 'white', '-alpha', 'remove', '-alpha', 'off' })
    end

    if steps.quality ~= nil and sniff.LOSSY[target] then
        append(argv, { '-quality', tostring(steps.quality) })
    end

    return append(argv, { '-format', Module.MARK .. ' %w %h\\n', '-write', 'info:fd:2', target .. ':-' })
end

return Module
