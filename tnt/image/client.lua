--- Клиент изображений: осмотр, преобразование и превью программой
--- ImageMagick, запущенной `tnt-process`.
---
--- Данные идут программе на вход, итог — с её вывода: на диске узла
--- картинка не лежит. Временный каталог у каждого запуска всё же свой
--- (`MAGICK_TEMPORARY_PATH`): часть разборщиков читает вход с диска,
--- и программа копирует его туда сама. Процесс, убитый по сроку, свой
--- файл не уберёт — каталог сносится после запуска при всяком исходе.
---
--- Преобразование — два запуска под одним сроком. Первый читает только
--- заголовок (`-ping`): размеры и метку ориентации. По ним пределы
--- стороны и точек проверяются до того, как программа развернёт картинку
--- в памяти, — файл в сотню килобайт с заголовком 30 000×30 000 иначе
--- попросил бы гигабайты. Второй — само преобразование.
---
--- Окружение программы собрано целиком, а не взято у узла: пароли узла
--- ей ни к чему. В нём каталоги поиска, английский язык сообщений —
--- разбор знает один — и временный каталог.

local fs = require('tnt.fs')
local process = require('tnt.process')

local command = require('tnt.image.command')
local options_of = require('tnt.image.options')
local sniff = require('tnt.image.sniff')
local system = require('tnt.image.system')
local verdict = require('tnt.image.verdict')

local Module = {}

--- Программы по порядку поиска: ImageMagick 7, затем 6 — у него нет
--- `magick`, а у седьмого `convert` ругается на себя в поток ошибок.
Module.PROGRAMS = { 'magick', 'convert' }

--- Номера меток ориентации EXIF по словам ImageMagick. Без метки
--- (`Undefined`) картинка стоит как есть — это номер 1.
local ORIENTATIONS = {
    TopLeft = 1,
    TopRight = 2,
    BottomRight = 3,
    BottomLeft = 4,
    LeftTop = 5,
    RightTop = 6,
    RightBottom = 7,
    LeftBottom = 8,
}

--- С этого номера метка поворачивает на четверть оборота, и ширина
--- с высотой меняются местами.
local QUARTER = 5

---@class TntImageInfo Что сказал заголовок
---@field format string Формат: `jpeg`, `png`, `gif`, `webp`, `avif`
---@field width integer Ширина так, как картинку покажут: после поворота по метке
---@field height integer Высота так же
---@field orientation integer Метка ориентации EXIF, 1–8; 1 — поворота нет

---@class TntImageResult Итог преобразования
---@field data string Изображение
---@field format string Его формат
---@field width integer Ширина, точек
---@field height integer Высота, точек

---@class TntImageSettings: TntImageLimits Проверенные настройки клиента
---@field program string|nil Программа; `nil` — первая найденная из `PROGRAMS`
---@field path string Каталоги поиска программы через `:`
---@field timeout number Срок вызова по умолчанию, секунд
---@field temp_dir string|nil Где заводить временные каталоги; `nil` — системный
---@field max_bytes integer Предел входа и итога, байт
---@field max_side integer Предел стороны, точек
---@field max_pixels integer Предел точек входа
---@field memory integer Предел памяти программы под точки, байт

---@class TntImageClient: TntImageSettings Клиент изображений
local Client = {}
Client.__index = Client

--- Программа, которую запускать.
---@return string|nil program
---@return TntImageFailure|nil err
function Client:_program()
    if self.program ~= nil then
        return self.program
    end

    for _, name in ipairs(Module.PROGRAMS) do
        if process.which(name, { PATH = self.path }) ~= nil then
            return name
        end
    end

    local message = ('программы %s не найдены в %s'):format(
        table.concat(Module.PROGRAMS, ' и '),
        self.path
    )

    return nil, verdict.new(process.MISSING, Module.PROGRAMS[1], message)
end

--- Программа и формат входа: всё, что проверяется до запуска.
---@param data string
---@return string|nil program
---@return string|TntImageFailure|nil format Формат либо отказ
function Client:_prepare(data)
    local program, err = self:_program()

    if program == nil then
        return nil, err
    end

    if #data > self.max_bytes then
        local message = ('%s: изображение больше предела: %d байт, предел %d'):format(
            program,
            #data,
            self.max_bytes
        )

        return nil, verdict.new(verdict.TOO_LARGE, program, message)
    end

    local format = sniff.format(data)

    if format == nil then
        local message = ('%s: данные — не изображение: сигнатура не %s'):format(
            program,
            table.concat(sniff.FORMATS, ', ')
        )

        return nil, verdict.new(verdict.INVALID, program, message)
    end

    return program, format
end

--- Работа во временном каталоге, который сносится после неё.
---
--- Обёртка ради объявления работы: итог и отказ — два значения.
---@param work fun(dir: string): any, any
---@param within string|nil Где заводить каталог; `nil` — системный
---@return any
---@return any
local function scratch(work, within)
    return fs.with_temp_dir(work, { within = within })
end

--- Отказ по сроку вызова.
---
--- Текст называет срок вызова, а не остаток, который достался запуску:
--- вызывающий задавал первый и узнаёт его, а остаток второго запуска —
--- число с хвостом дробей, которого он не задавал.
---@param program string
---@param timeout number
---@param extra table|nil
---@return TntImageFailure
local function late(program, timeout, extra)
    local message = ('программа %s не уложилась в срок %s с'):format(program, timeout)

    return verdict.new(process.TIMEOUT, program, message, extra)
end

--- Запускает программу до конца во временном каталоге.
---
--- Срок один на весь вызов: остаток считается от мига срока, и запуск,
--- которому не осталось ничего, не начинается. Вывод больше `max_bytes`
--- — отказ `too_large`: итог не уместился бы в предел; прочие отказы
--- запуска — нет программы, сигнал — приходят отказом `tnt-process`
--- как есть.
---@param program string
---@param argv string[]
---@param data string Вход программы
---@param deadline number Миг срока по монотонным часам
---@param timeout number Срок вызова — для текста отказа
---@return TntProcessResult|nil result
---@return TntImageFailure|TntProcessFailure|TntFsFailure|nil err
function Client:_run(program, argv, data, deadline, timeout)
    local left = deadline - system.current().now()

    if left <= 0 then
        return nil, late(program, timeout)
    end

    return scratch(function(dir)
        local line = { program }

        for _, value in ipairs(argv) do
            table.insert(line, value)
        end

        local env = { PATH = self.path, LANG = 'C', LC_ALL = 'C', MAGICK_TEMPORARY_PATH = dir, TMPDIR = dir }
        local result, err = process.run(line, { input = data, timeout = left, env = env, max_output = self.max_bytes })
        local failed = err --[[@as TntProcessFailure]]

        if result == nil and failed.kind == process.OVERFLOW then
            local message = ('%s: вывод программы больше предела %d байт'):format(
                program,
                self.max_bytes
            )

            return nil, verdict.new(verdict.TOO_LARGE, program, message, { stderr = failed.stderr })
        end

        if result == nil and failed.kind == process.TIMEOUT then
            return nil, late(program, timeout, { stdout = failed.stdout, stderr = failed.stderr })
        end

        if result == nil and failed.kind ~= process.EXIT then
            return nil, failed
        end

        local refusal = verdict.refusal(program, result or failed)

        if refusal ~= nil then
            return nil, refusal
        end

        return result
    end, self.temp_dir)
end

--- Отказ на ответ, который программа дала удачей, а разобрать его нечем.
---@param program string
---@param result TntProcessResult
---@return TntImageFailure
local function unreadable(program, result)
    return verdict.new(verdict.FAILED, program, program .. ': ответ не разобран', {
        stdout = result.stdout,
        stderr = result.stderr,
    })
end

--- Осмотр заголовка названной программой.
---@param program string
---@param format string
---@param data string
---@param deadline number
---@param timeout number
---@return TntImageInfo|nil info
---@return TntImageFailure|TntProcessFailure|TntFsFailure|nil err
function Client:_look(program, format, data, deadline, timeout)
    local result, err = self:_run(program, command.inspect(self, format), data, deadline, timeout)

    if result == nil then
        return nil, err
    end

    local width, height, orientation = result.stdout:match('^(%d+) (%d+) (%a+)')

    if width == nil then
        return nil, unreadable(program, result)
    end

    ---@type TntImageInfo
    local info = {
        format = format,
        width = tonumber(width) --[[@as integer]],
        height = tonumber(height) --[[@as integer]],
        orientation = ORIENTATIONS[orientation] or 1,
    }

    if info.orientation >= QUARTER then
        info.width, info.height = info.height, info.width
    end

    return info
end

--- Отказ по заголовку до преобразования: пределы и область обрезки.
---
--- Область, вылезшая за край, обрезается краем; область, начатая за
--- краем, — отказ: от неё не остаётся ни точки. Края области считаются
--- в тех координатах, которые увидит человек: после поворота по метке,
--- а без поворота — в записанных.
---@param program string
---@param info TntImageInfo
---@param steps TntImageSteps
---@return TntImageFailure|nil
function Client:_admit(program, info, steps)
    local width, height = info.width, info.height
    local size = ('%d×%d'):format(width, height)

    if width > self.max_side or height > self.max_side then
        local message = ('%s: изображение %s больше предела стороны %d'):format(
            program,
            size,
            self.max_side
        )

        return verdict.new(verdict.TOO_LARGE, program, message)
    end

    if width * height > self.max_pixels then
        local message = ('%s: изображение %s больше предела %d точек'):format(
            program,
            size,
            self.max_pixels
        )

        return verdict.new(verdict.TOO_LARGE, program, message)
    end

    local crop = steps.crop

    if crop == nil or crop.x == nil then
        return nil
    end

    if steps.orient == false and info.orientation >= QUARTER then
        width, height = height, width
    end

    if crop.x >= width or crop.y >= height then
        local area = ('%dx%d+%d+%d'):format(crop.width, crop.height, crop.x, crop.y)
        local message = ('%s: область обрезки %s вне изображения %d×%d'):format(
            program,
            area,
            width,
            height
        )

        return verdict.new(verdict.OUTSIDE, program, message)
    end

    return nil
end

--- Преобразование без проверки настроек: её сделал тот, кто позвал.
---@param data string
---@param steps TntImageTransformOptions
---@return TntImageResult|nil result
---@return TntImageFailure|TntProcessFailure|TntFsFailure|nil err
function Client:_convert(data, steps)
    local timeout = steps.timeout or self.timeout
    local deadline = system.current().now() + timeout
    local program, format = self:_prepare(data)

    if program == nil then
        return nil, format --[[@as TntImageFailure]]
    end

    local info, err = self:_look(program, format --[[@as string]], data, deadline, timeout)

    if info == nil then
        return nil, err
    end

    local refusal = self:_admit(program, info, steps)

    if refusal ~= nil then
        return nil, refusal
    end

    local target = steps.format or info.format
    local argv = command.transform(self, info.format, target, steps)
    local result

    result, err = self:_run(program, argv, data, deadline, timeout)

    if result == nil then
        return nil, err
    end

    if sniff.format(result.stdout) ~= target then
        local reason = verdict.reason(result.stderr)
        local message = ('%s: формат %s программе не по силам (%s)'):format(
            program,
            target,
            reason or 'итог не в нём'
        )

        return nil, verdict.new(verdict.UNSUPPORTED, program, message, { reason = reason, stderr = result.stderr })
    end

    local width, height = verdict.size(result.stderr)

    if width == nil then
        return nil, unreadable(program, result)
    end

    return {
        data = result.stdout,
        format = target,
        width = width --[[@as integer]],
        height = height --[[@as integer]],
    }
end

--- Осмотр заголовка: формат, размеры и метка ориентации.
---
--- Точки не читаются, и пределы стороны и точек тут не проверяются:
--- осмотр как раз и нужен, чтобы узнать размер до преобразования.
---
---     images:inspect(photo)   --> { format = 'jpeg', width = 3000, height = 4000, orientation = 6 }
---@param data string
---@param options { timeout: number|nil }|nil
---@return TntImageInfo|nil info
---@return TntImageFailure|TntProcessFailure|TntFsFailure|nil err
function Client:inspect(data, options)
    local given = options_of.inspect(data, options)
    local timeout = given.timeout or self.timeout
    local deadline = system.current().now() + timeout
    local program, format = self:_prepare(data)

    if program == nil then
        return nil, format --[[@as TntImageFailure]]
    end

    return self:_look(program, format --[[@as string]], data, deadline, timeout)
end

--- Преобразование: поворот по метке, обрезка, размер, метаданные, формат.
---
---     images:transform(photo, { resize = { width = 1200 }, format = 'webp', quality = 80 })
---     --> { data = '…', format = 'webp', width = 1200, height = 1600 }
---     images:transform(photo, { crop = { x = 100, y = 40, width = 600, height = 600 } })
---@param data string
---@param options TntImageTransformOptions|nil
---@return TntImageResult|nil result
---@return TntImageFailure|TntProcessFailure|TntFsFailure|nil err
function Client:transform(data, options)
    return self:_convert(data, options_of.transform(data, options))
end

--- Превью: заполнить рамку и обрезать лишнее по центру.
---
--- Меньшее рамки не увеличивается — превью тогда меньше рамки, но без
--- размытых точек. Метка ориентации применяется, метаданные удаляются.
---
---     images:thumbnail(photo, { width = 256, height = 256, format = 'webp' })
---     --> { data = '…', format = 'webp', width = 256, height = 256 }
---@param data string
---@param options TntImageThumbnailOptions
---@return TntImageResult|nil result
---@return TntImageFailure|TntProcessFailure|TntFsFailure|nil err
function Client:thumbnail(data, options)
    return self:_convert(data, options_of.thumbnail(data, options))
end

--- Новый клиент.
---@param settings TntImageSettings
---@return TntImageClient
function Module.new(settings)
    return setmetatable({
        program = settings.program,
        path = settings.path,
        timeout = settings.timeout,
        temp_dir = settings.temp_dir,
        max_bytes = settings.max_bytes,
        max_side = settings.max_side,
        max_pixels = settings.max_pixels,
        memory = settings.memory,
    }, Client)
end

return Module
