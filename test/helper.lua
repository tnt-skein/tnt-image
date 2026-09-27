--- Общие средства проверок изображений.
---
--- ImageMagick в проверках — сценарий оболочки в каталоге проверки: он
--- отвечает тем, что ему велели, и записывает, с чем его позвали, —
--- аргументы, вход, окружение и был ли временный каталог. Осмотр
--- заголовка и преобразование он различает по `-ping` и отвечает на них
--- по-разному: у одного вызова `transform` два запуска. Запускает его
--- настоящий `tnt-process`, и путь от вызова до процесса и обратно
--- проверяется целиком. Саму программу проверяет живой набор против
--- стенда (`make image-up`).
---
--- Исходники пакета читаются с диска, а не через `require`: у Tarantool
--- свой загрузчик `.rocks`, он идёт раньше `package.path` и подсунул бы
--- установленную копию пакета, если она есть. Проверки тогда шли бы
--- против вчерашнего кода, а покрытие считалось бы по нему. Зависимости
--- пакета — `tnt-process`, `tnt-fs`, `tnt-clock`, `tnt-must`
--- и `tnt-external` — и `tnt-env` проверок берутся из `.rocks` обычным
--- `require`: проверяется этот пакет, а не они.
---
--- Оснастка в `test/testing/` грузится так же, файлами, и один раз
--- на процесс: второй экземпляр загрузчика не знал бы, что вытеснил
--- первый, и не вернул бы вытесненное на место.
---
--- Проверки берут всё через этот помощник, а не из оснастки напрямую:
--- помощник — единственное, чем файл проверок отличается от того же файла
--- в наборе, где пакет живёт рядом со своими зависимостями.

local fio = require('fio')
local t = require('luatest')

--- Модули оснастки в порядке зависимостей.
local TESTING = {
    { name = 'tnt.testing.sources', path = 'test/testing/sources.lua' },
    { name = 'tnt.testing.files', path = 'test/testing/files.lua' },
}

for _, module in ipairs(TESTING) do
    if package.loaded[module.name] == nil then
        local chunk, failure = loadfile(fio.abspath(module.path))

        if chunk == nil then
            error(('оснастка %s не читается: %s'):format(module.name, tostring(failure)))
        end

        package.loaded[module.name] = chunk()
    end
end

--- Оснастка проверок под теми именами, что зовёт помощник.
local testing = {
    load_sources = package.loaded['tnt.testing.sources'].load,
    module = package.loaded['tnt.testing.sources'].module,
    read_file = package.loaded['tnt.testing.files'].read,
    write_file = package.loaded['tnt.testing.files'].write,
}

--- Модули пакета в порядке зависимостей.
local OWN = {
    'tnt.image.sniff',
    'tnt.image.system',
    'tnt.image.command',
    'tnt.image.options',
    'tnt.image.verdict',
    'tnt.image.client',
    'tnt.image',
}

local helper = {
    --- Модули пакета в порядке зависимостей: имя и путь исходника.
    MODULES = {},
}

for _, name in ipairs(OWN) do
    table.insert(helper.MODULES, { name = name, path = (name:gsub('%.', '/')) .. '.lua' })
end

--- Фасад пакета из исходников.
helper.image = testing.load_sources(helper.MODULES, 'tnt.image')

--- Части той же загрузки, что и фасад.
helper.sniff = testing.module('tnt.image.sniff')
helper.command = testing.module('tnt.image.command')
helper.verdict = testing.module('tnt.image.verdict')
helper.system = testing.module('tnt.image.system')

--- Зависимости — те же экземпляры из `.rocks`, что берёт пакет: подмена
--- средств `tnt-fs` доходит до него, а настоящие часы срока — те же часы
--- `tnt-clock`.
helper.process = require('tnt.process')
helper.fs = require('tnt.fs')
helper.clock = require('tnt.clock')

--- Окружение процесса проверок — через `tnt-env`: мимо него окружение
--- не читают и проверки. Живым проверкам оно называет каталог стенда.
--- `tnt-env` приходит из `.rocks`: сам пакет окружения не читает, и его
--- зависимостью он не объявлен — его ставит `make deps`.
helper.env = require('tnt.env')

--- Начала данных каждого формата — ровно то, что узнаёт сигнатура.
helper.DATA = {
    jpeg = '\xFF\xD8\xFF\xE0 jpeg',
    png = '\x89PNG\r\n\x1A\n png',
    gif = 'GIF89a gif',
    webp = 'RIFF\x10\x00\x00\x00WEBPVP8  webp',
    avif = '\x00\x00\x00\x1CftypavifXXXX avif',
}

--- Записанный поток ошибок настоящих программ: ImageMagick 7.1.1-43
--- (Debian 13) и 6.9.12-98 (Ubuntu 24.04).
helper.STDERR = {
    premature = "magick: Premature end of JPEG file `/tmp/magick-1_3n' @ warning/jpeg.c/JPEGWarningHandler/411.\n"
        .. 'magick: Corrupt JPEG data: premature end of data segment '
        .. "`/tmp/magick-1_3n' @ warning/jpeg.c/JPEGWarningHandler/411.\n",
    extraneous = 'magick: Corrupt JPEG data: 2 extraneous bytes before marker 0xd9 '
        .. "`/tmp/magick-x' @ warning/jpeg.c/JPEGWarningHandler/411.\n",
    insufficient = 'magick: insufficient image data in file '
        .. "`/tmp/magick-l8ZG' @ error/jpeg.c/ReadOneJPEGImage/1117.\n",
    header = "magick: improper image header `/tmp/magick-tyAH' @ error/png.c/ReadPNGImage/3943.\n",
    exhausted = "magick: cache resources exhausted `-' @ error/cache.c/OpenPixelCache/3931.\n",
    ihdr = "convert-im6.q16: Image width exceeds user limit in IHDR `/tmp/magick-am0u' "
        .. '@ warning/png.c/MagickPNGWarningHandler/1669.\n'
        .. "convert-im6.q16: Invalid IHDR data `/tmp/magick-am0u' @ error/png.c/MagickPNGErrorHandler/1643.\n",
    encoder = "magick: no encode delegate for this image format `AVIF' @ warning/constitute.c/WriteImage/1403.\n",
    srgb = 'magick: iCCP: known incorrect sRGB profile '
        .. "`/tmp/magick-q' @ warning/png.c/MagickPNGWarningHandler/1527.\n",
}

--- Каталог проверки с программой.
---@type string|nil
local sandbox

--- Программа-двойник. Вызов с `-ping` — осмотр, прочие — преобразование;
--- ответ каждого берётся из своих файлов. Окружение записывается до смены
--- `PATH`: программу зовут с каталогом проверки вместо системных,
--- а `cat` и `sleep` лежат там, где лежат.
local PROGRAM = [[#!/bin/sh
here=$(CDPATH= cd -- "${0%/*}" && pwd)
case " $* " in
    *' -ping '*) step=ping ;;
    *) step=convert ;;
esac
printf '%s\n' "$LANG" "$LC_ALL" "$PATH" "$TMPDIR" "$MAGICK_TEMPORARY_PATH" > "$here/$step.env"
PATH=/bin:/usr/bin
export PATH
printf '%s\n' "$@" > "$here/$step.argv"
cat > "$here/$step.stdin"
[ -d "$MAGICK_TEMPORARY_PATH" ] && echo yes > "$here/$step.temp"
[ -f "$here/$step.sleep" ] && sleep "$(cat "$here/$step.sleep")"
[ -f "$here/$step.stdout" ] && cat "$here/$step.stdout"
[ -f "$here/$step.stderr" ] && cat "$here/$step.stderr" >&2
[ -f "$here/$step.code" ] && exit "$(cat "$here/$step.code")"
exit 0
]]

--- Пишет файл в каталог проверки средством оснастки.
---@param name string
---@param content string
local function put(name, content)
    testing.write_file(fio.pathjoin(sandbox, name), content)
end

--- Кладёт программу-двойника под именем.
---@param name string|nil `magick` либо `convert`; по умолчанию `magick`
function helper.fake(name)
    local path = fio.pathjoin(sandbox, name or 'magick')

    testing.write_file(path, PROGRAM)
    fio.chmod(path, tonumber('755', 8) --[[@as integer]])
end

---@class TntImageFakeAnswer
---@field stdout string|nil Вывод
---@field stderr string|nil Поток ошибок
---@field code integer|nil Код выхода; по умолчанию 0
---@field sleep number|nil Сколько секунд ждать перед ответом

--- Велит двойнику ответить на шаг: `ping` — осмотр, `convert` —
--- преобразование.
---@param step string
---@param answer TntImageFakeAnswer
function helper.answer(step, answer)
    for _, field in ipairs({ 'stdout', 'stderr' }) do
        if answer[field] ~= nil then
            put(step .. '.' .. field, answer[field])
        end
    end

    if answer.code ~= nil then
        put(step .. '.code', tostring(answer.code))
    end

    if answer.sleep ~= nil then
        put(step .. '.sleep', tostring(answer.sleep))
    end
end

--- Двойник отвечает на оба шага как настоящая программа на картинку
--- 400×200: заголовок без метки и итог в названном формате 100×50.
---@param target string|nil Формат итога; по умолчанию `png`
function helper.healthy(target)
    helper.fake()
    helper.answer('ping', { stdout = '400 200 Undefined\n' })
    helper.answer('convert', { stdout = helper.DATA[target or 'png'], stderr = 'tnt-image 100 50\n' })
end

--- Что двойник записал о шаге: `argv`, `stdin`, `env`, `temp`.
---@param step string
---@param what string
---@return string|nil
function helper.seen(step, what)
    local path = fio.pathjoin(sandbox, step .. '.' .. what)

    return fio.path.exists(path) and testing.read_file(path) or nil
end

--- Строки записанного файла списком: двойник пишет каждое значение
--- своей строкой.
---@param step string
---@param what string
---@return string[]
function helper.lines(step, what)
    local list = {}

    for line in (helper.seen(step, what) or ''):gmatch('([^\n]*)\n') do
        table.insert(list, line)
    end

    return list
end

--- Аргументы шага без пределов программы: они одни на все вызовы
--- и сверяются отдельно.
---@param step string
---@return string[]
function helper.argv(step)
    local argv = helper.lines(step, 'argv')

    return { unpack(argv, 19) }
end

--- Каталог проверки: в нём двойник, его записи и временные каталоги.
---@return string
function helper.root()
    return sandbox --[[@as string]]
end

--- Временные каталоги запусков, оставшиеся в каталоге проверки.
---@return string[]
function helper.leftovers()
    local left = {}

    for _, name in
        ipairs(fio.listdir(sandbox --[[@as string]]) or {})
    do
        if name:find('^%.tmp%-') ~= nil then
            table.insert(left, name)
        end
    end

    return left
end

--- Клиент над двойником: каталоги поиска программы и временных каталогов —
--- каталог проверки; настройки сверх них — поверх.
---@param extra table|nil
---@return TntImageClient
function helper.client(extra)
    local options = setmetatable(extra or {}, { __index = { path = sandbox, temp_dir = sandbox } })

    return helper.image.new({
        program = options.program,
        path = options.path,
        timeout = options.timeout,
        temp_dir = options.temp_dir,
        max_bytes = options.max_bytes,
        max_side = options.max_side,
        max_pixels = options.max_pixels,
        memory = options.memory,
    })
end

--- Итог удачного вызова; отказ — провал проверки.
---@param value any
---@param err any
---@return any
function helper.done(value, err)
    t.assert_equals(err, nil)

    return value
end

--- Отказ вызова; удача — провал проверки.
---@param value any
---@param err any
---@return TntImageFailure
function helper.refused(value, err)
    t.assert_equals(value, nil)
    t.assert_not_equals(err, nil)

    return err --[[@as TntImageFailure]]
end

--- Текст броска и место, которое он обязан назвать.
---
--- Тело пишется так, что вызов стоит первой строкой после `function()`:
--- бросок обязан показать на эту строку файла проверок, а не на строку
--- внутри пакета.
---@param fn function
---@return string|nil err Текст броска; nil — функция не бросила
---@return string place Файл и строка вызова с двоеточием и пробелом
function helper.blamed(fn)
    local info = debug.getinfo(fn, 'S') --[[@as { short_src: string, linedefined: integer }]]
    local ok, err = pcall(fn)
    local place = ('%s:%d: '):format(info.short_src, info.linedefined + 1)

    if ok then
        return nil, place
    end

    return tostring(err), place
end

--- Группа проверок: перед каждой — свой каталог проверки, после — настоящие
--- средства пакетов и снесённый каталог.
---@param name string
---@return table
function helper.group(name)
    local g = t.group(name)

    g.before_each(function()
        sandbox = fio.tempdir()
    end)
    g.after_each(function()
        helper.image._set_source(nil)
        helper.fs._set_source(nil)
        fio.rmtree(sandbox --[[@as string]])
        sandbox = nil
    end)

    return g
end

return helper
