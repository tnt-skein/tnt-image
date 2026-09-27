--- Фасад: умолчания клиента, проверка настроек, слова пакета и настоящие
--- часы срока.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local image = helper.image

local g = helper.group('tnt.image')

g.test_defaults_of_the_client = function()
    local client = image.new()

    t.assert_equals(client.program, nil)
    t.assert_equals(client.path, '/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin')
    t.assert_equals(client.timeout, 30)
    t.assert_equals(client.temp_dir, nil)
    t.assert_equals(client.max_bytes, 20971520)
    t.assert_equals(client.max_side, 10000)
    t.assert_equals(client.max_pixels, 25000000)
    t.assert_equals(client.memory, 536870912)
    t.assert_equals(image.new({}).timeout, 30)
end

g.test_settings_are_kept = function()
    local client = image.new({
        program = '/opt/im/bin/magick',
        path = '/opt/im/bin',
        timeout = 2.5,
        temp_dir = '/var/lib/app/tmp',
        max_bytes = 1024,
        max_side = 800,
        max_pixels = 640000,
        memory = 1048576,
    })

    t.assert_equals(client.program, '/opt/im/bin/magick')
    t.assert_equals(client.path, '/opt/im/bin')
    t.assert_equals(client.timeout, 2.5)
    t.assert_equals(client.temp_dir, '/var/lib/app/tmp')
    t.assert_equals(client.max_bytes, 1024)
    t.assert_equals(client.max_side, 800)
    t.assert_equals(client.max_pixels, 640000)
    t.assert_equals(client.memory, 1048576)
end

g.test_settings_are_checked_at_the_caller = function()
    for _, case in ipairs({
        {
            function()
                image.new({ programm = 'magick' })
            end,
            'настройки: ключа «programm» нет, есть max_bytes, max_pixels, max_side, memory, path, program, '
                .. 'temp_dir, timeout',
        },
        {
            function()
                image.new({ timeout = 0 })
            end,
            'настройки.timeout — число больше 0, а не 0',
        },
        {
            function()
                image.new({ program = '' })
            end,
            'настройки.program — непустая строка, а не пустая',
        },
        {
            function()
                image.new({ max_bytes = 1.5 })
            end,
            'настройки.max_bytes — целое число, а не 1.5',
        },
        {
            function()
                image.new({ max_side = 1.5 })
            end,
            'настройки.max_side — целое число, а не 1.5',
        },
        {
            function()
                image.new({ max_pixels = 1.5 })
            end,
            'настройки.max_pixels — целое число, а не 1.5',
        },
        {
            function()
                image.new({ memory = 1.5 })
            end,
            'настройки.memory — целое число, а не 1.5',
        },
    }) do
        local err, place = helper.blamed(case[1])

        t.assert_equals(err, place .. case[2])
    end
end

g.test_words_of_the_package = function()
    t.assert_equals({
        image.MISSING,
        image.DENIED,
        image.TIMEOUT,
        image.SIGNAL,
        image.INVALID,
        image.CORRUPT,
        image.UNSUPPORTED,
        image.TOO_LARGE,
        image.OUTSIDE,
        image.FAILED,
    }, {
        'missing',
        'denied',
        'timeout',
        'signal',
        'invalid',
        'corrupt',
        'unsupported',
        'too_large',
        'outside',
        'failed',
    })
    t.assert_equals(
        { image.JPEG, image.PNG, image.GIF, image.WEBP, image.AVIF },
        { 'jpeg', 'png', 'gif', 'webp', 'avif' }
    )
    t.assert_equals({ image.COVER, image.INSIDE }, { 'cover', 'inside' })
    t.assert_equals(
        { image.DEFAULT_TIMEOUT, image.DEFAULT_MAX_BYTES, image.DEFAULT_MAX_SIDE, image.DEFAULT_MAX_PIXELS },
        { 30, 20971520, 10000, 25000000 }
    )
    t.assert_equals(image.DEFAULT_MEMORY, 536870912)
end

g.test_format_without_the_program = function()
    t.assert_equals(image.format(helper.DATA.webp), 'webp')
    t.assert_equals(image.format('текст'), nil)
end

g.test_real_clock_is_monotonic = function()
    t.assert_is(helper.system.current().now, helper.clock.monotonic)
end
