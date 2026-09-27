--- Сигнатуры: пять форматов узнаются по первым байтам, всё прочее — нет.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local sniff = helper.sniff
local DATA = helper.DATA

local g = t.group('tnt.image.sniff')

g.test_each_format_by_its_first_bytes = function()
    for format, data in pairs(DATA) do
        t.assert_equals(sniff.format(data), format, format)
    end

    t.assert_equals(sniff.format('GIF87a'), 'gif')
    t.assert_equals(sniff.format('GIF89a'), 'gif')
    t.assert_equals(sniff.format('\x00\x00\x00\x20ftypavis'), 'avif')
    t.assert_equals(sniff.format('\xFF\xD8\xFF'), 'jpeg')
end

g.test_everything_else_is_not_an_image = function()
    for _, data in ipairs({
        '',
        '<svg xmlns="http://www.w3.org/2000/svg"/>',
        'push graphic-context',
        ' \xFF\xD8\xFF',
        '\xFF\xD8',
        '\x89PNG\r\n\x1A',
        'x\x89PNG\r\n\x1A\n',
        'GIF88a',
        'GIF81a',
        'GIF8a',
        'RIFF\x10\x00\x00\x00WAVEfmt ',
        'xRIFF\x10\x00\x00\x00WEBP',
        '\x00\x00\x00\x18ftypheic',
        '\x00\x00\x00\x18ftypavio',
        'x\x00\x00\x00\x18ftypavif',
    }) do
        t.assert_equals(sniff.format(data), nil, data)
    end
end

g.test_words_of_the_module = function()
    t.assert_equals(sniff.FORMATS, { 'jpeg', 'png', 'gif', 'webp', 'avif' })
    t.assert_equals(sniff.LOSSY, { jpeg = true, webp = true, avif = true })
    t.assert_equals(
        { sniff.JPEG, sniff.PNG, sniff.GIF, sniff.WEBP, sniff.AVIF },
        { 'jpeg', 'png', 'gif', 'webp', 'avif' }
    )
end
