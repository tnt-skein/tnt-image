--- Клиент над программой-двойником: поиск программы, окружение
--- и временный каталог запуска, осмотр, пределы до разбора, преобразование,
--- сверка итога и отказы запуска как есть.

local fio = require('fio')
local t = require('luatest')

local helper = dofile('test/helper.lua')

local image = helper.image
local DATA = helper.DATA
local STDERR = helper.STDERR
local done = helper.done
local refused = helper.refused

local g = helper.group('tnt.image.client')

--- Часы срока, которые отвечают по списку.
---@param moments number[]
local function clock_says(moments)
    local asked = 0

    image._set_source({
        now = function()
            asked = asked + 1

            return moments[asked]
        end,
    })
end

g.test_inspect_asks_the_header_with_a_clean_environment = function()
    helper.healthy()

    local info = done(helper.client():inspect(DATA.jpeg))
    local env = helper.lines('ping', 'env')

    t.assert_equals(info, { format = 'jpeg', width = 400, height = 200, orientation = 1 })
    t.assert_equals(helper.argv('ping'), { '-ping', 'jpeg:-[0]', '-format', '%w %h %[orientation]\\n', 'info:' })
    t.assert_equals(helper.seen('ping', 'stdin'), DATA.jpeg)
    t.assert_equals({ env[1], env[2], env[3] }, { 'C', 'C', helper.root() })
    t.assert_equals(env[4], env[5])
    t.assert_str_matches(env[5], '.*/%.tmp%-%x+')
    t.assert_equals(fio.dirname(env[5]), helper.root())
    t.assert_equals(helper.seen('ping', 'temp'), 'yes\n')
    t.assert_equals(helper.leftovers(), {})
    t.assert_equals(helper.seen('convert', 'argv'), nil)
end

g.test_limits_come_first_in_every_call = function()
    helper.healthy()

    done(helper.client({ max_side = 640, memory = 2048 }):transform(DATA.png))

    local limits = {
        '-limit',
        'thread',
        '1',
        '-limit',
        'width',
        '640',
        '-limit',
        'height',
        '640',
        '-limit',
        'memory',
        '2048',
        '-limit',
        'map',
        '0',
        '-limit',
        'disk',
        '0',
    }

    t.assert_equals({ unpack(helper.lines('ping', 'argv'), 1, 18) }, limits)
    t.assert_equals({ unpack(helper.lines('convert', 'argv'), 1, 18) }, limits)
end

g.test_orientation_turns_the_sides = function()
    helper.fake()

    for word, expected in pairs({
        Undefined = { 1, 400, 200 },
        TopLeft = { 1, 400, 200 },
        TopRight = { 2, 400, 200 },
        BottomRight = { 3, 400, 200 },
        BottomLeft = { 4, 400, 200 },
        LeftTop = { 5, 200, 400 },
        RightTop = { 6, 200, 400 },
        RightBottom = { 7, 200, 400 },
        LeftBottom = { 8, 200, 400 },
    }) do
        helper.answer('ping', { stdout = '400 200 ' .. word .. '\n' })

        local info = done(helper.client():inspect(DATA.jpeg))

        t.assert_equals({ info.orientation, info.width, info.height }, expected, word)
    end
end

g.test_inspect_refusals = function()
    helper.fake()
    helper.answer('ping', { stdout = 'что-то не то\n' })

    local err = refused(helper.client():inspect(DATA.gif))

    t.assert_equals(err.kind, 'failed')
    t.assert_equals(tostring(err), 'magick: ответ не разобран')
    t.assert_equals(err.stdout, 'что-то не то\n')

    for _, stdout in ipairs({ ' 200 TopLeft\n', '400  TopLeft\n', '400 200 \n' }) do
        helper.answer('ping', { stdout = stdout })
        t.assert_equals(refused(helper.client():inspect(DATA.gif)).kind, 'failed', stdout)
    end

    helper.answer('ping', { stdout = '', stderr = STDERR.insufficient, code = 1 })
    err = refused(helper.client():inspect(DATA.jpeg))

    t.assert_equals(err.kind, 'corrupt')
    t.assert_equals(err.code, 1)
    t.assert_equals(helper.leftovers(), {})

    err = refused(helper.client():transform(DATA.jpeg, { format = 'webp' }))

    t.assert_equals(err.kind, 'corrupt')
    t.assert_equals(helper.seen('convert', 'argv'), nil)
end

g.test_input_is_checked_before_the_program_runs = function()
    helper.healthy()

    local client = helper.client({ max_bytes = 64 })
    local full = DATA.png .. ('x'):rep(64 - #DATA.png)
    local err = refused(client:inspect(full .. 'x'))

    t.assert_equals(err.kind, 'too_large')
    t.assert_equals(err.program, 'magick')
    t.assert_equals(
        tostring(err),
        'magick: изображение больше предела: 65 байт, предел 64'
    )
    t.assert_equals(done(client:inspect(full)).format, 'png')

    helper.fake()
    os.remove(fio.pathjoin(helper.root(), 'ping.argv'))
    err = refused(helper.client():transform('<svg/>'))

    t.assert_equals(err.kind, 'invalid')
    t.assert_equals(
        tostring(err),
        'magick: данные — не изображение: сигнатура не jpeg, png, gif, webp, avif'
    )
    t.assert_equals(helper.seen('ping', 'argv'), nil)
end

g.test_program_is_looked_for_magick_first = function()
    helper.healthy()
    helper.fake('convert')

    done(helper.client():inspect(DATA.png))
    t.assert_not_equals(helper.seen('ping', 'argv'), nil)

    os.remove(fio.pathjoin(helper.root(), 'magick'))
    os.remove(fio.pathjoin(helper.root(), 'ping.argv'))

    local info = done(helper.client():inspect(DATA.png))

    t.assert_equals(info.width, 400)
    t.assert_not_equals(helper.seen('ping', 'argv'), nil)
end

g.test_no_program_is_a_refusal_not_a_throw = function()
    local err = refused(helper.client():transform(DATA.png))

    t.assert_equals(err.kind, 'missing')
    t.assert_equals(err.program, 'magick')
    t.assert_equals(tostring(err), 'программы magick и convert не найдены в ' .. helper.root())
end

g.test_named_program_runs_as_is = function()
    helper.healthy()

    local program = fio.pathjoin(helper.root(), 'magick')

    t.assert_equals(done(helper.client({ program = program, path = '/nowhere' }):inspect(DATA.png)).width, 400)

    local err = refused(helper.client({ program = 'nothing-like-it' }):inspect(DATA.png))

    t.assert_equals(err.kind, 'missing')
    t.assert_equals(err.program, 'nothing-like-it')
end

g.test_transform_runs_both_steps_on_the_same_data = function()
    helper.healthy('webp')

    local result =
        done(helper.client():transform(DATA.png, { format = 'webp', quality = 70, resize = { width = 100 } }))

    t.assert_equals(result, { data = DATA.webp, format = 'webp', width = 100, height = 50 })
    t.assert_equals(helper.seen('ping', 'stdin'), DATA.png)
    t.assert_equals(helper.seen('convert', 'stdin'), DATA.png)
    t.assert_equals(helper.argv('convert'), {
        'png:-[0]',
        '-auto-orient',
        '-resize',
        '100x>',
        '-strip',
        '-quality',
        '70',
        '-format',
        'tnt-image %w %h\\n',
        '-write',
        'info:fd:2',
        'webp:-',
    })
    t.assert_equals(helper.seen('convert', 'temp'), 'yes\n')
    t.assert_equals(helper.leftovers(), {})
end

g.test_format_stays_the_same_by_default = function()
    helper.healthy('png')

    local result = done(helper.client():transform(DATA.png))

    t.assert_equals(result.format, 'png')
    t.assert_equals(helper.argv('convert')[#helper.argv('convert')], 'png:-')
end

g.test_result_of_another_format_is_unsupported = function()
    helper.healthy('png')

    local err = refused(helper.client():transform(DATA.png, { format = 'avif' }))

    t.assert_equals(err.kind, 'unsupported')
    t.assert_equals(err.reason, nil)
    t.assert_equals(
        tostring(err),
        'magick: формат avif программе не по силам (итог не в нём)'
    )

    helper.answer('convert', { stdout = '', stderr = STDERR.encoder .. 'tnt-image 100 50\n' })
    err = refused(helper.client():transform(DATA.png, { format = 'avif' }))

    t.assert_equals(err.reason, 'no encode delegate for this image format')
    t.assert_equals(err.stderr, STDERR.encoder .. 'tnt-image 100 50\n')
    t.assert_equals(
        tostring(err),
        'magick: формат avif программе не по силам (no encode delegate for this image format)'
    )
end

g.test_result_without_the_size_line_is_unreadable = function()
    helper.healthy()
    helper.answer('convert', { stderr = '' })

    local err = refused(helper.client():transform(DATA.png))

    t.assert_equals(err.kind, 'failed')
    t.assert_equals(tostring(err), 'magick: ответ не разобран')
    t.assert_equals(err.stdout, DATA.png)
end

g.test_damage_found_by_the_program = function()
    helper.healthy('jpeg')
    helper.answer('convert', { stderr = STDERR.premature .. 'tnt-image 400 200\n' })

    local err = refused(helper.client():transform(DATA.jpeg))

    t.assert_equals(err.kind, 'corrupt')
    t.assert_equals(err.reason, 'Premature end of JPEG file')
end

g.test_side_and_pixels_are_limited_by_the_header = function()
    helper.healthy()

    local err = refused(helper.client({ max_side = 399 }):transform(DATA.png))

    t.assert_equals(err.kind, 'too_large')
    t.assert_equals(
        tostring(err),
        'magick: изображение 400×200 больше предела стороны 399'
    )
    t.assert_equals(helper.seen('convert', 'argv'), nil)

    helper.answer('ping', { stdout = '200 400 Undefined\n' })
    err = refused(helper.client({ max_side = 399 }):transform(DATA.png))

    t.assert_equals(
        tostring(err),
        'magick: изображение 200×400 больше предела стороны 399'
    )

    helper.answer('ping', { stdout = '400 200 Undefined\n' })
    err = refused(helper.client({ max_pixels = 79999 }):transform(DATA.png))

    t.assert_equals(err.kind, 'too_large')
    t.assert_equals(
        tostring(err),
        'magick: изображение 400×200 больше предела 79999 точек'
    )
    t.assert_equals(helper.seen('convert', 'argv'), nil)

    done(helper.client({ max_side = 400, max_pixels = 80000 }):transform(DATA.png))
    t.assert_not_equals(helper.seen('convert', 'argv'), nil)

    helper.answer('ping', { stdout = '200 400 Undefined\n' })
    done(helper.client({ max_side = 400 }):transform(DATA.png))
end

g.test_crop_starting_outside_is_refused = function()
    helper.healthy()

    local client = helper.client()
    local err = refused(client:transform(DATA.png, { crop = { x = 400, y = 0, width = 10, height = 10 } }))

    t.assert_equals(err.kind, 'outside')
    t.assert_equals(
        tostring(err),
        'magick: область обрезки 10x10+400+0 вне изображения 400×200'
    )
    t.assert_equals(helper.seen('convert', 'argv'), nil)

    err = refused(client:transform(DATA.png, { crop = { x = 0, y = 200, width = 10, height = 10 } }))

    t.assert_equals(
        tostring(err),
        'magick: область обрезки 10x10+0+200 вне изображения 400×200'
    )

    done(client:transform(DATA.png, { crop = { x = 399, y = 199, width = 10, height = 10 } }))
    t.assert_equals(helper.argv('convert')[3], '-crop')
    t.assert_equals(helper.argv('convert')[4], '10x10+399+199')

    done(client:transform(DATA.png, { crop = { width = 1000, height = 1000 } }))
end

g.test_crop_edges_follow_the_orientation = function()
    helper.healthy('jpeg')
    helper.answer('ping', { stdout = '400 200 RightTop\n' })

    local client = helper.client()
    local area = { x = 300, y = 100, width = 10, height = 10 }
    local err = refused(client:transform(DATA.jpeg, { crop = area }))

    t.assert_equals(
        tostring(err),
        'magick: область обрезки 10x10+300+100 вне изображения 200×400'
    )

    done(client:transform(DATA.jpeg, { crop = area, orient = false }))

    err = refused(client:transform(DATA.jpeg, { crop = { x = 100, y = 300, width = 10, height = 10 }, orient = false }))

    t.assert_equals(
        tostring(err),
        'magick: область обрезки 10x10+100+300 вне изображения 400×200'
    )

    helper.answer('ping', { stdout = '400 200 BottomLeft\n' })

    done(client:transform(DATA.jpeg, { crop = area, orient = false }))
    done(client:transform(DATA.jpeg, { crop = area }))

    helper.answer('ping', { stdout = '400 200 LeftTop\n' })

    done(client:transform(DATA.jpeg, { crop = area, orient = false }))
    t.assert_equals(refused(client:transform(DATA.jpeg, { crop = area })).kind, 'outside')
end

g.test_output_over_the_limit_is_too_large = function()
    helper.healthy()
    helper.answer('convert', { stdout = DATA.png .. ('x'):rep(64) })

    local err = refused(helper.client({ max_bytes = 64 }):transform(DATA.png))

    t.assert_equals(err.kind, 'too_large')
    t.assert_equals(tostring(err), 'magick: вывод программы больше предела 64 байт')
    t.assert_equals(type(err.stderr), 'string')
    t.assert_equals(helper.leftovers(), {})
end

g.test_process_refusals_come_as_they_are = function()
    helper.healthy()
    helper.answer('ping', { sleep = 1 })

    local err = refused(helper.client({ timeout = 0.2 }):inspect(DATA.png))

    t.assert_equals(err.kind, 'timeout')
    t.assert_equals(err.program, 'magick')
    t.assert_equals(tostring(err), 'программа magick не уложилась в срок 0.2 с')
    t.assert_equals({ err.stdout, err.stderr }, { '', '' })
    t.assert_equals(helper.leftovers(), {})

    fio.chmod(fio.pathjoin(helper.root(), 'magick'), tonumber('644', 8) --[[@as integer]])
    err = refused(helper.client({ program = fio.pathjoin(helper.root(), 'magick') }):inspect(DATA.png))

    t.assert_equals(err.kind, 'denied')
end

g.test_one_deadline_for_both_runs = function()
    helper.healthy()
    helper.answer('convert', { sleep = 0.3 })

    local err = refused(helper.client({ timeout = 5 }):transform(DATA.png, { timeout = 0.2 }))

    t.assert_equals(err.kind, 'timeout')
    t.assert_equals(helper.seen('ping', 'argv') ~= nil, true)

    clock_says({ 100, 100, 110.25 })
    err = refused(helper.client():transform(DATA.png, { timeout = 10.25 }))

    t.assert_equals(err.kind, 'timeout')
    t.assert_equals(err.program, 'magick')
    t.assert_equals(tostring(err), 'программа magick не уложилась в срок 10.25 с')

    clock_says({ 100, 100, 111 })
    t.assert_equals(refused(helper.client():transform(DATA.png, { timeout = 10.25 })).kind, 'timeout')

    os.remove(fio.pathjoin(helper.root(), 'convert.argv'))
    clock_says({ 100, 100, 109.5 })
    done(helper.client():transform(DATA.png, { timeout = 10.25 }))
    t.assert_not_equals(helper.seen('convert', 'argv'), nil)
end

g.test_inspect_has_its_own_deadline = function()
    helper.healthy()

    clock_says({ 100, 110.25 })
    t.assert_equals(
        tostring(refused(helper.client():inspect(DATA.png, { timeout = 10.25 }))),
        'программа magick не уложилась в срок 10.25 с'
    )
    t.assert_equals(helper.seen('ping', 'argv'), nil)

    clock_says({ 100, 109.5 })
    t.assert_equals(done(helper.client({ timeout = 10.25 }):inspect(DATA.png)).width, 400)
end

g.test_temp_dir_refusal_comes_as_it_is = function()
    helper.healthy()
    helper.fs._set_source({
        fio = setmetatable({
            mkdir = function()
                return false, 'No space left on device'
            end,
        }, { __index = fio }),
    })

    local err = refused(helper.client():inspect(DATA.png))

    t.assert_equals(err.kind, 'full')
    t.assert_equals(helper.seen('ping', 'argv'), nil)
end

g.test_thumbnail_covers_the_frame = function()
    helper.healthy('webp')

    local result =
        done(helper.client():thumbnail(DATA.jpeg, { width = 64, height = 48, format = 'webp', quality = 60 }))

    t.assert_equals(result.format, 'webp')
    t.assert_equals(helper.argv('convert'), {
        'jpeg:-[0]',
        '-auto-orient',
        '-resize',
        '64x48^>',
        '-gravity',
        'center',
        '-crop',
        '64x48+0+0',
        '+repage',
        '-strip',
        '-quality',
        '60',
        '-format',
        'tnt-image %w %h\\n',
        '-write',
        'info:fd:2',
        'webp:-',
    })

    helper.answer('convert', { sleep = 0.5 })

    local err =
        refused(helper.client():thumbnail(DATA.jpeg, { width = 64, height = 48, format = 'webp', timeout = 0.2 }))

    t.assert_equals(err.kind, 'timeout')
end

g.test_arguments_are_checked_at_the_caller = function()
    local client = helper.client()

    for _, case in ipairs({
        {
            function()
                client:inspect(1)
            end,
            'данные — строка, а не число',
        },
        {
            function()
                client:inspect('x', { timout = 1 })
            end,
            'настройки: ключа «timout» нет, есть timeout',
        },
        {
            function()
                client:transform(false)
            end,
            'данные — строка, а не логическое значение',
        },
        {
            function()
                client:transform('x', { format = 'bmp' })
            end,
            'настройки.format — одно из «jpeg», «png», «gif», «webp», «avif», а не «bmp»',
        },
        {
            function()
                client:transform('x', { quality = 101 })
            end,
            'настройки.quality — число от 1 до 100, а не 101',
        },
        {
            function()
                client:transform('x', { quality = 50.5 })
            end,
            'настройки.quality — целое число, а не 50.5',
        },
        {
            function()
                client:transform('x', { crop = { width = 1.5, height = 1 } })
            end,
            'настройки.crop.width — целое число, а не 1.5',
        },
        {
            function()
                client:transform('x', { crop = { width = 1, height = 2.5 } })
            end,
            'настройки.crop.height — целое число, а не 2.5',
        },
        {
            function()
                client:transform('x', { crop = { width = 1, height = 1, x = 0.5, y = 0 } })
            end,
            'настройки.crop.x — целое число, а не 0.5',
        },
        {
            function()
                client:transform('x', { crop = { width = 1, height = 1, x = 0, y = 0.5 } })
            end,
            'настройки.crop.y — целое число, а не 0.5',
        },
        {
            function()
                client:transform('x', { crop = { width = 1, height = 1, x = 0 } })
            end,
            'настройки.crop: края x и y задаются вместе, а без обоих область стоит по центру',
        },
        {
            function()
                client:transform('x', { crop = { width = 1, height = 1, y = 0 } })
            end,
            'настройки.crop: края x и y задаются вместе, а без обоих область стоит по центру',
        },
        {
            function()
                client:transform('x', { crop = { width = 0, height = 1 } })
            end,
            'настройки.crop.width — число больше 0, а не 0',
        },
        {
            function()
                client:transform('x', { resize = {} })
            end,
            'настройки.resize: нужна ширина, высота либо обе',
        },
        {
            function()
                client:transform('x', { resize = { width = 1.5 } })
            end,
            'настройки.resize.width — целое число, а не 1.5',
        },
        {
            function()
                client:transform('x', { resize = { height = 2.5 } })
            end,
            'настройки.resize.height — целое число, а не 2.5',
        },
        {
            function()
                client:transform('x', { resize = { width = 10, fit = 'cover' } })
            end,
            'настройки.resize: рамке cover нужны и ширина, и высота',
        },
        {
            function()
                client:transform('x', { resize = { height = 10, fit = 'cover' } })
            end,
            'настройки.resize: рамке cover нужны и ширина, и высота',
        },
        {
            function()
                client:transform('x', { resize = { width = 10, fit = 'fill' } })
            end,
            'настройки.resize.fit — одно из «inside», «cover», а не «fill»',
        },
        {
            function()
                client:thumbnail('x', { width = 10 })
            end,
            'настройки.height — число больше 0, а не nil',
        },
        {
            function()
                client:thumbnail(1, { width = 10, height = 10 })
            end,
            'данные — строка, а не число',
        },
        {
            function()
                client:thumbnail('x', { width = 10.5, height = 10 })
            end,
            'настройки.width — целое число, а не 10.5',
        },
        {
            function()
                client:thumbnail('x', { width = 10, height = 10.5 })
            end,
            'настройки.height — целое число, а не 10.5',
        },
        {
            function()
                client:thumbnail('x', { width = 10, height = 10, quality = 7.5 })
            end,
            'настройки.quality — целое число, а не 7.5',
        },
    }) do
        local err, place = helper.blamed(case[1])

        t.assert_equals(err, place .. case[2])
    end
end

g.test_thumbnail_and_transform_accept_what_they_check = function()
    helper.healthy('png')

    local client = helper.client()

    done(client:transform(DATA.png, { resize = { width = 10, height = 10, fit = 'cover' } }))
    done(client:transform(DATA.png, { resize = { height = 10 } }))
    done(client:transform(DATA.png, { crop = { width = 1, height = 1, x = 0, y = 0 }, quality = 100 }))
    done(client:thumbnail(DATA.png, { width = 1, height = 1, quality = 1 }))
    done(client:inspect(DATA.png, { timeout = 1 }))
end
