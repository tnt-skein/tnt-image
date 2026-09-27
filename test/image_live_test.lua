--- Живые проверки против настоящего ImageMagick (`make image-up`, выпуск 7;
--- `IMAGE_STAND_VERSION=6 make image-up` — выпуск 6).
---
--- Двойник показывает, что мы правильно разбираем записанный вывод; здесь —
--- что программа отвечает именно так: уменьшает и обрезает до названных
--- размеров, поворачивает по метке EXIF и стирает её, пишет WebP, кладёт
--- прозрачное на белое, отказывает на не-изображении, на обрезанном файле
--- и на пределе памяти. Картинки рисует сама программа стенда, метка EXIF
--- вписывается руками: двоичных образцов в дереве нет. Без стенда проверки
--- пропускаются.

local fio = require('fio')
local t = require('luatest')

local helper = dofile('test/helper.lua')

local image = helper.image
local process = helper.process
local done = helper.done
local refused = helper.refused

local g = t.group('tnt.image.live')

--- Окружение стенда — через `tnt-env`, как у всех проверок.
local env = helper.env

--- Где стенд: та же переменная и то же умолчание, что у его сценария.
local DIR = fio.abspath(env.string('IMAGE_STAND_DIR', 'test/stand/run/image'))

--- Контейнер стенда.
local CONTAINER = 'tnt-stand-image'

--- Каталог временных каталогов: смонтирован в контейнер тем же путём.
local WORK = fio.pathjoin(DIR, 'work')

--- Программа стенда: `magick` у выпуска 7, `convert` у 6.
---@return string|nil
local function program()
    for _, name in ipairs({ 'magick', 'convert' }) do
        local path = fio.pathjoin(DIR, 'bin', name)

        if fio.path.exists(path) then
            return path
        end
    end

    return nil
end

--- Поднят ли стенд: программа на месте и контейнер жив.
---@return boolean
local function up()
    local running = process.run({ 'docker', 'inspect', '-f', '{{.State.Running}}', CONTAINER }, { timeout = 10 })

    return running ~= nil and running.stdout == 'true\n' and program() ~= nil
end

--- Рисует картинку программой стенда: её аргументы, итог — вывод.
---@param argv string[]
---@param input string|nil
---@return string
local function draw(argv, input)
    local command = { program() }

    for _, value in ipairs(argv) do
        table.insert(command, value)
    end

    return done(process.run(command, { input = input, timeout = 30 })).stdout
end

--- Цвет точки картинки: красный, зелёный и синий от 0 до 255.
---
--- Числами через `fx`, а не `%[pixel:…]`: тот называет точный цвет
--- именем (`white`), а не числами.
---@param data string PNG либо JPEG
---@param format string
---@param x integer
---@param y integer
---@return table
local function pixel(data, format, x, y)
    local at = ('p{%d,%d}'):format(x, y)
    local spec = ('%%[fx:int(255*%s.r)],%%[fx:int(255*%s.g)],%%[fx:int(255*%s.b)]'):format(at, at, at)
    local red, green, blue = draw({ format .. ':-', '-format', spec, 'info:' }, data):match('(%d+),(%d+),(%d+)')

    return { tonumber(red), tonumber(green), tonumber(blue) }
end

--- Сколько кадров в картинке.
---@param data string
---@param format string
---@return integer
local function frames(data, format)
    return tonumber(draw({ format .. ':-', '-format', '%n\\n', 'info:' }, data):match('^(%d+)')) --[[@as integer]]
end

--- Вписывает метку ориентации EXIF сразу за началом JPEG: сегмент APP1
--- с каталогом из одной записи 0x0112 (SHORT) — ровно то, что пишут камеры.
---@param jpeg string
---@param mark integer 1–8
---@return string
local function oriented(jpeg, mark)
    local exif = '\xFF\xE1\x00\x22Exif\x00\x00MM\x00\x2A\x00\x00\x00\x08\x00\x01\x01\x12\x00\x03\x00\x00\x00\x01'
        .. '\x00'
        .. string.char(mark)
        .. '\x00\x00\x00\x00\x00\x00'

    return jpeg:sub(1, 2) .. exif .. jpeg:sub(3)
end

--- Заголовок GIF с названными размерами и одной точкой данных: файл
--- в полсотни байт, который просит развернуть кадр любого размера.
---@param width integer
---@param height integer
---@return string
local function gif_bomb(width, height)
    local function le16(value)
        return string.char(value % 256, math.floor(value / 256))
    end

    return 'GIF89a'
        .. le16(width)
        .. le16(height)
        .. '\x00\x00\x00\x2C'
        .. le16(0)
        .. le16(0)
        .. le16(width)
        .. le16(height)
        .. '\x00\x02\x02\x44\x01\x00\x3B'
end

---@type TntImageClient
local images

--- Снимок 400×200: переход от красного к синему.
---@type string
local PHOTO

g.before_all(function()
    t.skip_if(not up(), 'ImageMagick нет: make image-up')

    images = image.new({ path = fio.pathjoin(DIR, 'bin') .. ':/usr/bin:/bin', temp_dir = WORK, timeout = 30 })
    PHOTO = draw({ '-size', '400x200', 'gradient:red-blue', 'jpeg:-' })
end)

g.test_inspect_and_resize_a_real_photo = function()
    t.assert_equals(done(images:inspect(PHOTO)), { format = 'jpeg', width = 400, height = 200, orientation = 1 })

    local smaller = done(images:transform(PHOTO, { resize = { width = 100 } }))

    t.assert_equals({ smaller.format, smaller.width, smaller.height }, { 'jpeg', 100, 50 })
    t.assert_equals(image.format(smaller.data), 'jpeg')
    t.assert_equals(done(images:inspect(smaller.data)).width, 100)

    local kept = done(images:transform(PHOTO, { resize = { width = 1000 } }))
    local larger = done(images:transform(PHOTO, { resize = { width = 1000, enlarge = true } }))
    local framed = done(images:transform(PHOTO, { resize = { width = 300, height = 50 } }))

    t.assert_equals({ kept.width, kept.height }, { 400, 200 })
    t.assert_equals({ larger.width, larger.height }, { 1000, 500 })
    t.assert_equals({ framed.width, framed.height }, { 100, 50 })
end

g.test_rotation_by_the_exif_mark = function()
    -- Левые десять столбцов синие: после поворота на четверть по часовой
    -- они — верхние строки.
    local plain = draw({ '-size', '40x20', 'xc:red', '-fill', 'blue', '-draw', 'rectangle 0,0 9,19', 'jpeg:-' })
    local photo = oriented(plain, 6)

    t.assert_equals(done(images:inspect(photo)), { format = 'jpeg', width = 20, height = 40, orientation = 6 })

    local turned = done(images:transform(photo, { format = 'png' }))
    local top = pixel(turned.data, 'png', 10, 2)
    local bottom = pixel(turned.data, 'png', 10, 37)

    t.assert_equals({ turned.width, turned.height }, { 20, 40 })
    t.assert(top[3] > 200 and top[1] < 60, 'сверху синее')
    t.assert(bottom[1] > 200 and bottom[3] < 60, 'снизу красное')
    t.assert_equals(done(images:inspect(turned.data)).orientation, 1)

    local kept = done(images:transform(photo, { format = 'png', orient = false }))

    t.assert_equals({ kept.width, kept.height }, { 40, 20 })
end

g.test_metadata_goes_away = function()
    local photo = oriented(PHOTO, 1)

    t.assert_not_equals(photo:find('Exif', 1, true), nil)
    t.assert_equals(done(images:transform(photo)).data:find('Exif', 1, true), nil)
    t.assert_not_equals(
        done(images:transform(photo, { strip = false, orient = false })).data:find('Exif', 1, true),
        nil
    )
end

g.test_crop_by_area_and_by_centre = function()
    local area = done(images:transform(PHOTO, { crop = { x = 10, y = 10, width = 100, height = 60 } }))
    local edge = done(images:transform(PHOTO, { crop = { x = 350, y = 150, width = 100, height = 100 } }))
    local centre = done(images:transform(PHOTO, { crop = { width = 100, height = 100 } }))
    local whole = done(images:transform(PHOTO, { crop = { width = 1000, height = 1000 } }))

    t.assert_equals({ area.width, area.height }, { 100, 60 })
    t.assert_equals({ edge.width, edge.height }, { 50, 50 })
    t.assert_equals({ centre.width, centre.height }, { 100, 100 })
    t.assert_equals({ whole.width, whole.height }, { 400, 200 })
    t.assert_equals(
        refused(images:transform(PHOTO, { crop = { x = 400, y = 0, width = 10, height = 10 } })).kind,
        'outside'
    )
end

g.test_webp_and_quality = function()
    local webp = done(images:transform(PHOTO, { format = 'webp', quality = 80 }))

    t.assert_equals({ webp.format, webp.width, webp.height }, { 'webp', 400, 200 })
    t.assert_equals(image.format(webp.data), 'webp')
    t.assert_equals(done(images:inspect(webp.data)).format, 'webp')

    local rough = done(images:transform(PHOTO, { quality = 10 }))
    local fine = done(images:transform(PHOTO, { quality = 95 }))

    t.assert(
        #rough.data < #fine.data,
        ('качество 10 — %d байт, 95 — %d'):format(#rough.data, #fine.data)
    )
end

g.test_thumbnail_fills_the_frame_without_enlarging = function()
    local thumb = done(images:thumbnail(PHOTO, { width = 64, height = 64, format = 'webp' }))
    local small = draw({ '-size', '40x20', 'xc:green', 'png:-' })
    local kept = done(images:thumbnail(small, { width = 64, height = 64 }))

    t.assert_equals({ thumb.format, thumb.width, thumb.height }, { 'webp', 64, 64 })
    t.assert_equals({ kept.format, kept.width, kept.height }, { 'png', 40, 20 })
end

g.test_transparency_lies_on_white_in_jpeg = function()
    local clear = draw({ '-size', '10x10', 'xc:none', 'png:-' })
    local jpeg = done(images:transform(clear, { format = 'jpeg' }))

    t.assert_equals(pixel(jpeg.data, 'jpeg', 5, 5), { 255, 255, 255 })
end

g.test_animation_keeps_the_first_frame = function()
    local animation = draw({ '-size', '30x20', 'xc:red', 'xc:blue', 'xc:lime', 'gif:-' })

    t.assert_equals(frames(animation, 'gif'), 3)

    local first = done(images:transform(animation))

    t.assert_equals(frames(first.data, 'gif'), 1)
    t.assert_equals({ first.width, first.height }, { 30, 20 })
end

g.test_format_without_an_encoder_is_unsupported = function()
    local err = refused(images:transform(PHOTO, { format = 'avif' }))

    t.assert_equals(err.kind, 'unsupported')
end

g.test_not_an_image_and_damaged_files = function()
    local png = draw({ '-size', '400x200', 'gradient:red-blue', 'png:-' })

    t.assert_equals(refused(images:transform('это не картинка')).kind, 'invalid')
    t.assert_equals(refused(images:transform('\xFF\xD8\xFF это не картинка')).kind, 'corrupt')
    t.assert_equals(refused(images:transform('\x89PNG\r\n\x1A\n это не картинка')).kind, 'corrupt')
    t.assert_equals(refused(images:transform('GIF89a это не картинка')).kind, 'corrupt')
    t.assert_equals(refused(images:transform('RIFF\x10\x00\x00\x00WEBPVP8 мусор')).kind, 'corrupt')

    local cut = refused(images:transform(PHOTO:sub(1, math.floor(#PHOTO / 2))))

    t.assert_equals(cut.kind, 'corrupt')
    t.assert_str_contains(cut.reason, 'JPEG')
    t.assert_equals(refused(images:transform(png:sub(1, math.floor(#png / 2)))).kind, 'corrupt')
end

g.test_limits_before_and_inside_the_program = function()
    local bomb = refused(images:transform(gif_bomb(30000, 30000)))

    t.assert_equals(bomb.kind, 'too_large')
    t.assert_str_contains(
        tostring(bomb),
        'изображение 30000×30000 больше предела стороны 10000'
    )
    t.assert_equals(refused(image.new({ path = images.path, max_side = 399 }):transform(PHOTO)).kind, 'too_large')

    local tight = image.new({ path = images.path, temp_dir = WORK, memory = 1024 * 1024 })
    local memory = refused(tight:transform(PHOTO, { resize = { width = 2000, enlarge = true } }))

    t.assert_equals(memory.kind, 'too_large')
    t.assert_equals(memory.reason, 'cache resources exhausted')

    local narrow = image.new({ path = images.path, temp_dir = WORK, max_side = 1000 })

    t.assert_equals(refused(narrow:transform(PHOTO, { resize = { width = 2000, enlarge = true } })).kind, 'too_large')

    -- Шум сжимается плохо: без потерь он вчетверо больше, чем в JPEG.
    local noise = draw({ '-size', '200x200', 'plasma:fractal', 'jpeg:-' })
    local short = image.new({ path = images.path, temp_dir = WORK, max_bytes = #noise })
    local overflow = refused(short:transform(noise, { format = 'png' }))

    t.assert_equals(overflow.kind, 'too_large')
    t.assert_str_contains(tostring(overflow), 'вывод программы больше предела')
end

g.test_deadline_is_a_refusal = function()
    local err = refused(images:transform(PHOTO, { timeout = 0.02 }))

    t.assert_equals(err.kind, 'timeout')
end

g.test_nothing_is_left_behind = function()
    done(images:transform(PHOTO, { format = 'webp' }))
    refused(images:transform(PHOTO:sub(1, 100)))

    t.assert_equals(fio.listdir(WORK), {})
end
