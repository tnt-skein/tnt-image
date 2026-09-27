--- Аргументы ImageMagick: пределы, осмотр и преобразование шаг за шагом.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local command = helper.command

local g = t.group('tnt.image.command')

--- Пределы клиента по умолчанию.
local LIMITS = { max_side = 10000, memory = 536870912 }

--- Пределы в начале каждого вызова.
local LIMITED = {
    '-limit',
    'thread',
    '1',
    '-limit',
    'width',
    '10000',
    '-limit',
    'height',
    '10000',
    '-limit',
    'memory',
    '536870912',
    '-limit',
    'map',
    '0',
    '-limit',
    'disk',
    '0',
}

--- Конец преобразования: строка размеров и запись итога.
---@param target string
---@return string[]
local function written(target)
    return { '-format', 'tnt-image %w %h\\n', '-write', 'info:fd:2', target .. ':-' }
end

--- Преобразование без пределов в начале.
---@param source string
---@param target string
---@param steps table
---@return string[]
local function steps_of(source, target, steps)
    local argv = command.transform(LIMITS, source, target, steps)

    t.assert_equals({ unpack(argv, 1, #LIMITED) }, LIMITED)

    return { unpack(argv, #LIMITED + 1) }
end

--- Список из частей подряд.
---@param ... string[]
---@return string[]
local function joined(...)
    local list = {}

    for _, part in ipairs({ ... }) do
        for _, value in ipairs(part) do
            table.insert(list, value)
        end
    end

    return list
end

g.test_inspect_reads_the_header_of_the_first_frame = function()
    t.assert_equals(
        command.inspect({ max_side = 800, memory = 1048576 }, 'gif'),
        joined(
            { '-limit', 'thread', '1', '-limit', 'width', '800', '-limit', 'height', '800' },
            { '-limit', 'memory', '1048576', '-limit', 'map', '0', '-limit', 'disk', '0' },
            { '-ping', 'gif:-[0]', '-format', '%w %h %[orientation]\\n', 'info:' }
        )
    )
end

g.test_defaults_orient_and_strip = function()
    t.assert_equals(steps_of('png', 'png', {}), joined({ 'png:-[0]', '-auto-orient', '-strip' }, written('png')))
    t.assert_equals(steps_of('png', 'gif', { orient = false, strip = false }), joined({ 'png:-[0]' }, written('gif')))
    t.assert_equals(
        steps_of('gif', 'webp', { orient = true, strip = true }),
        joined({ 'gif:-[0]', '-auto-orient', '-strip' }, written('webp'))
    )
end

g.test_crop_by_area_and_by_centre = function()
    t.assert_equals(
        steps_of('png', 'png', { orient = false, strip = false, crop = { x = 7, y = 3, width = 40, height = 20 } }),
        joined({ 'png:-[0]', '-crop', '40x20+7+3', '+repage' }, written('png'))
    )
    t.assert_equals(
        steps_of('png', 'png', { orient = false, strip = false, crop = { width = 40, height = 20 } }),
        joined({ 'png:-[0]', '-gravity', 'center', '-crop', '40x20+0+0', '+repage' }, written('png'))
    )
end

g.test_resize_inside_the_frame = function()
    local plain = { orient = false, strip = false }

    plain.resize = { width = 300 }
    t.assert_equals(steps_of('png', 'png', plain), joined({ 'png:-[0]', '-resize', '300x>' }, written('png')))

    plain.resize = { height = 200 }
    t.assert_equals(steps_of('png', 'png', plain), joined({ 'png:-[0]', '-resize', 'x200>' }, written('png')))

    plain.resize = { width = 300, height = 200, fit = 'inside', enlarge = true }
    t.assert_equals(steps_of('png', 'png', plain), joined({ 'png:-[0]', '-resize', '300x200' }, written('png')))

    plain.resize = { width = 300, height = 200, enlarge = false }
    t.assert_equals(steps_of('png', 'png', plain), joined({ 'png:-[0]', '-resize', '300x200>' }, written('png')))
end

g.test_resize_covering_the_frame = function()
    local plain = { orient = false, strip = false, resize = { width = 64, height = 48, fit = 'cover' } }
    local centre = { '-gravity', 'center', '-crop', '64x48+0+0', '+repage' }

    t.assert_equals(steps_of('png', 'png', plain), joined({ 'png:-[0]', '-resize', '64x48^>' }, centre, written('png')))

    plain.resize.enlarge = true

    t.assert_equals(steps_of('png', 'png', plain), joined({ 'png:-[0]', '-resize', '64x48^' }, centre, written('png')))
end

g.test_order_of_steps_does_not_follow_the_options = function()
    t.assert_equals(
        steps_of('jpeg', 'webp', {
            quality = 80,
            resize = { width = 100 },
            crop = { width = 10, height = 10 },
        }),
        joined(
            { 'jpeg:-[0]', '-auto-orient', '-gravity', 'center', '-crop', '10x10+0+0', '+repage' },
            { '-resize', '100x>', '-strip', '-quality', '80' },
            written('webp')
        )
    )
end

g.test_jpeg_lays_transparency_on_white = function()
    t.assert_equals(
        steps_of('png', 'jpeg', { orient = false, strip = false }),
        joined({ 'png:-[0]', '-background', 'white', '-alpha', 'remove', '-alpha', 'off' }, written('jpeg'))
    )
end

g.test_quality_only_for_lossy_formats = function()
    local plain = { orient = false, strip = false, quality = 1 }
    local white = { '-background', 'white', '-alpha', 'remove', '-alpha', 'off' }

    t.assert_equals(steps_of('png', 'jpeg', plain), joined({ 'png:-[0]' }, white, { '-quality', '1' }, written('jpeg')))
    t.assert_equals(steps_of('png', 'webp', plain), joined({ 'png:-[0]', '-quality', '1' }, written('webp')))
    t.assert_equals(steps_of('png', 'avif', plain), joined({ 'png:-[0]', '-quality', '1' }, written('avif')))
    t.assert_equals(steps_of('jpeg', 'png', plain), joined({ 'jpeg:-[0]' }, written('png')))
    t.assert_equals(steps_of('jpeg', 'gif', plain), joined({ 'jpeg:-[0]' }, written('gif')))
end

g.test_mark_of_the_size_line = function()
    t.assert_equals(command.MARK, 'tnt-image')
end
