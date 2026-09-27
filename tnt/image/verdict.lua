--- Приговор ImageMagick: удача либо отказ с родом по его словам.
---
--- Код выхода говорит только «получилось или нет», а вызывающему нужно
--- знать, что делать: не изображение — сказать посетителю, не хватило
--- пределов — поднять их или отказать, нет разборщика — ставить другую
--- сборку программы. Поэтому род читается из потока ошибок: каждое
--- сообщение ImageMagick — строка `программа: причина `файл' @ error/…`
--- либо `@ warning/…`, и причины у него постоянные, английские. Пакет
--- запускает программу с `LC_ALL=C`, и разбор знает один язык.
---
--- Две ловушки проверены на ImageMagick 7.1 и 6.9:
---
--- * **обрезанный JPEG — удача.** Программа пишет «Premature end of JPEG
---   file» предупреждением, дорисовывает недостающее серым и кончается
---   кодом 0; `-regard-warnings` делает это отказом у 6.9, но не у 7.1.
---   Поэтому предупреждение о порче данных — тоже отказ `corrupt`. Кроме
---   «extraneous bytes»: это мусор после конца картинки, на точки он
---   не влияет, а камеры пишут его часто;
--- * **формат итога без кодировщика не отказ.** ImageMagick 6 на `avif:-`
---   без кодировщика молча пишет итог в формате входа, 7 — пустоту, и оба
---   без единого сообщения. Это ловит клиент, сверяя сигнатуру итога,
---   а не этот разбор.

local failure = require('tnt.process.failure')

local Module = {}

--- Не изображение: сигнатура не узнана.
Module.INVALID = 'invalid'

--- Изображение повреждено: разборщик отказал либо пожаловался на порчу.
Module.CORRUPT = 'corrupt'

--- Формат программе не по силам: нет разборщика либо кодировщика.
Module.UNSUPPORTED = 'unsupported'

--- Изображение больше предела: байтов, стороны, точек либо памяти.
Module.TOO_LARGE = 'too_large'

--- Область обрезки вне изображения.
Module.OUTSIDE = 'outside'

--- Прочее: программа не справилась по причине вне изображения.
Module.FAILED = failure.FAILED

--- Слова отказа по роду.
local WORDS = {
    [Module.CORRUPT] = 'изображение повреждено',
    [Module.UNSUPPORTED] = 'формат программе не по силам',
    [Module.TOO_LARGE] = 'изображение не уместилось в пределы программы',
    [Module.FAILED] = 'программа не справилась',
}

--- Роды отказа с ненулевым кодом по причинам, по порядку: первый
--- совпавший решает. Образцы сверяются со строчными буквами.
---
--- Пределы идут первыми: ImageMagick 6 отвечает на сторону сверх предела
--- ещё и «Invalid IHDR data», и без порядка это читалось бы порчей.
--- Запрет политики безопасности программы (`policy.xml`) — тоже «не по
--- силам»: оба выпуска стенда говорят «not allowed by the security
--- policy», прежние выпуски шестого — «not authorized». Прочие отказы
--- среды — временный файл, место, права — порчей не являются: изображение
--- тут ни при чём.
local RULES = {
    {
        kind = Module.TOO_LARGE,
        patterns = { 'cache resources exhausted', 'exceeds.-limit', 'memory allocation failed' },
    },
    {
        kind = Module.UNSUPPORTED,
        patterns = { 'no decode delegate', 'no encode delegate', 'not authorized', 'security policy' },
    },
    {
        kind = Module.FAILED,
        patterns = { 'temporary file', 'no space left', 'permission denied', 'unable to open' },
    },
}

--- Причины предупреждений, которые значат порчу данных.
local DAMAGE = { 'corrupt', 'premature end', 'truncat', 'insufficient image data', 'expected %d+ bytes' }

--- Строка о мусоре после конца картинки: порчей она не считается и из
--- сверки уходит целиком — в ней самой есть слово «corrupt».
local BENIGN = '[^\n]*extraneous bytes[^\n]*'

--- Сообщение ImageMagick об ошибке — не предупреждении. Знаков образца
--- в нём нет, и ищется он образцом.
local ERROR = ' @ error/'

--- Первый образец списка, совпавший с текстом; `nil` — не совпал ни один.
---@param text string
---@param patterns string[]
---@return string|nil
local function matched(text, patterns)
    for _, pattern in ipairs(patterns) do
        if text:find(pattern) ~= nil then
            return pattern
        end
    end

    return nil
end

--- Род отказа при ненулевом коде.
---
--- Сообщение об ошибке, не узнанное правилами, — порча: программа читает
--- только наши данные разборщиком названного формата и пишет в трубу,
--- и отказывать ей больше не на чем. Ненулевой код без сообщения
--- ImageMagick — не порча, а поломка: отказал не разборщик, а то, что его
--- запускало.
---@param text string Поток ошибок строчными
---@return string
local function refused(text)
    for _, rule in ipairs(RULES) do
        if matched(text, rule.patterns) ~= nil then
            return rule.kind
        end
    end

    if text:find(ERROR) ~= nil then
        return Module.CORRUPT
    end

    return Module.FAILED
end

--- Поток ошибок строчными без строк о мусоре после конца картинки: всё,
--- что в нём осталось, сверяется со словами порчи.
---@param stderr string
---@return string
local function harmless(stderr)
    return (stderr:lower():gsub(BENIGN, ''))
end

--- Причина словами программы: первое её сообщение без имени программы,
--- файла и места в исходниках.
---
---     verdict.reason("magick: Premature end of JPEG file `/tmp/magick-x' @ warning/jpeg.c/…")
---     --> 'Premature end of JPEG file'
---@param stderr string
---@return string|nil
function Module.reason(stderr)
    -- Перевод строки впереди — чтобы и первая строка начиналась с него:
    -- образец ищет строку сообщения целиком, от начала.
    local said = ('\n' .. stderr):match('\n[^\n:]*: ([^\n]-) @ %a+/')

    if said == nil then
        return nil
    end

    return (said:gsub(" [`'].*$", ''))
end

--- Размеры итога из строки с меткой; `nil` — строки нет.
---@param stderr string
---@return number|nil width
---@return number|nil height
function Module.size(stderr)
    local width, height = stderr:match('tnt%-image (%d+) (%d+)')

    return tonumber(width), tonumber(height)
end

--- Новый отказ с родом.
---@param kind string
---@param program string
---@param message string
---@param extra table|nil
---@return TntImageFailure
function Module.new(kind, program, message, extra)
    return failure.new(kind, program, message, extra) --[[@as TntImageFailure]]
end

---@class TntImageFailure: TntProcessFailure Отказ пакета изображений
---@field reason string|nil Причина словами программы: первое её сообщение

--- Отказ по выводу программы либо `nil`, если она справилась.
---@param program string
---@param output TntProcessResult|TntProcessFailure Итог либо отказ `exit` — с выводом
---@return TntImageFailure|nil
function Module.refusal(program, output)
    local stderr = output.stderr --[[@as string]]
    local kind

    if output.code ~= 0 then
        kind = refused(stderr:lower())
    elseif matched(harmless(stderr), DAMAGE) ~= nil then
        kind = Module.CORRUPT
    end

    if kind == nil then
        return nil
    end

    local reason = Module.reason(stderr)
    local message = ('%s: %s (%s)'):format(program, WORDS[kind], reason or 'без пояснения')

    return Module.new(kind, program, message, { reason = reason, code = output.code, stderr = stderr })
end

return Module
