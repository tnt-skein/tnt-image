--- Проверка аргументов вызовов клиента: данные и настройки.
---
--- Негодный аргумент — ошибка программиста, и бросок показывает на строку
--- того, кто позвал метод клиента. Проверки зовутся из методов клиента,
--- поэтому уровень вины у них 3: сама проверка, метод, его вызывающий.
---
--- Сверх описания настроек проверяется то, чего описание не выразит:
--- точки — целые, края области задаются парой, рамке `cover` нужны обе
--- стороны.

local must = require('tnt.must')

local sniff = require('tnt.image.sniff')

local Module = {}

--- Заполнить рамку и обрезать лишнее по центру.
Module.COVER = 'cover'

--- Вписать в рамку целиком.
Module.INSIDE = 'inside'

--- Качество: от худшего к лучшему.
local QUALITY = { '?between', 1, 100 }

--- Формат итога.
local FORMAT = { '?one_of', sniff.FORMATS }

--- Настройки `inspect`.
local INSPECT = { timeout = '?positive' }

--- Настройки `transform`.
local TRANSFORM = {
    orient = '?boolean',
    crop = {
        '?options',
        { width = 'positive', height = 'positive', x = '?non_negative', y = '?non_negative' },
    },
    resize = {
        '?options',
        {
            width = '?positive',
            height = '?positive',
            fit = { '?one_of', { Module.INSIDE, Module.COVER } },
            enlarge = '?boolean',
        },
    },
    format = FORMAT,
    quality = QUALITY,
    strip = '?boolean',
    timeout = '?positive',
}

--- Отказ на один край области без другого.
local UNPAIRED =
    'настройки.crop: края x и y задаются вместе, а без обоих область стоит по центру'

--- Настройки `thumbnail`.
local THUMBNAIL = { width = 'positive', height = 'positive', format = FORMAT, quality = QUALITY, timeout = '?positive' }

---@class TntImageTransformOptions: TntImageSteps
---@field format string|nil Формат итога; по умолчанию тот же, что у входа
---@field timeout number|nil Срок вызова, секунд

---@class TntImageThumbnailOptions
---@field width integer Ширина рамки, точек
---@field height integer Высота рамки, точек
---@field format string|nil Формат итога; по умолчанию тот же, что у входа
---@field quality integer|nil Качество 1–100 — у форматов с потерями
---@field timeout number|nil Срок вызова, секунд

--- Аргументы `inspect`.
---@param data any
---@param options any
---@return { timeout: number|nil }
function Module.inspect(data, options)
    local caller = must.at(3)
    local given = options or {}

    caller.string(data, 'данные')
    caller.options(given, 'настройки', INSPECT)

    return given
end

--- Аргументы `transform`.
---
--- Края области задаются парой: один край без другого — не область и не
--- центр. Рамке `cover` нужны обе стороны: заполнять нечего, если одна
--- из них не ограничена.
---@param data any
---@param options any
---@return TntImageTransformOptions
function Module.transform(data, options)
    local caller = must.at(3)
    local steps = options or {}

    caller.string(data, 'данные')
    caller.options(steps, 'настройки', TRANSFORM)
    caller.optional.integer(steps.quality, 'настройки.quality')

    local crop = steps.crop

    if crop ~= nil then
        caller.integer(crop.width, 'настройки.crop.width')
        caller.integer(crop.height, 'настройки.crop.height')
        caller.optional.integer(crop.x, 'настройки.crop.x')
        caller.optional.integer(crop.y, 'настройки.crop.y')

        if (crop.x == nil) ~= (crop.y == nil) then
            error(UNPAIRED, 3)
        end
    end

    local resize = steps.resize

    if resize == nil then
        return steps
    end

    caller.optional.integer(resize.width, 'настройки.resize.width')
    caller.optional.integer(resize.height, 'настройки.resize.height')

    if resize.width == nil and resize.height == nil then
        error('настройки.resize: нужна ширина, высота либо обе', 3)
    end

    if resize.fit == Module.COVER and (resize.width == nil or resize.height == nil) then
        error('настройки.resize: рамке cover нужны и ширина, и высота', 3)
    end

    return steps
end

--- Аргументы `thumbnail` и шаги преобразования по ним: рамка, заполненная
--- с обрезкой по центру.
---@param data any
---@param options any
---@return TntImageTransformOptions
function Module.thumbnail(data, options)
    local caller = must.at(3)

    caller.string(data, 'данные')
    caller.options(options, 'настройки', THUMBNAIL)
    caller.integer(options.width, 'настройки.width')
    caller.integer(options.height, 'настройки.height')
    caller.optional.integer(options.quality, 'настройки.quality')

    return {
        resize = { width = options.width, height = options.height, fit = Module.COVER },
        format = options.format,
        quality = options.quality,
        timeout = options.timeout,
    }
end

return Module
